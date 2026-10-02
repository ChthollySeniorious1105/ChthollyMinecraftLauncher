// H.264 decoding for remote screen shares (see video_dec.h).
#include <windows.h>
#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wmcodecdsp.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <thread>

#include "h264_enc.h"
#include "video_dec.h"

using Microsoft::WRL::ComPtr;

namespace pn::video {

// ============================================================ colour conversion

namespace {
// BT.709 limited range lookup tables, fixed point scaled by 1 << 12.
struct Tables {
  int y[256], rv[256], gu[256], gv[256], bu[256];
  uint8_t clip[1024];  // index + 384
  Tables() {
    for (int i = 0; i < 256; i++) {
      y[i] = static_cast<int>(1.16438 * 4096 * (i - 16) + 2048);
      rv[i] = static_cast<int>(1.79274 * 4096 * (i - 128));
      gu[i] = static_cast<int>(-0.21325 * 4096 * (i - 128));
      gv[i] = static_cast<int>(-0.53291 * 4096 * (i - 128));
      bu[i] = static_cast<int>(2.11240 * 4096 * (i - 128));
    }
    for (int i = 0; i < 1024; i++) clip[i] = static_cast<uint8_t>(std::clamp(i - 384, 0, 255));
  }
};
const Tables& tables() {
  static const Tables t;
  return t;
}
}  // namespace

// w must be even.
void nv12ToRgba(const uint8_t* yp, int yPitch, const uint8_t* uvp, int uvPitch, int w, int h, uint8_t* out) {
  const Tables& t = tables();
  const uint8_t* clip = t.clip + 384;
  for (int row = 0; row < h; row++) {
    const uint8_t* yr = yp + static_cast<size_t>(row) * yPitch;
    const uint8_t* uv = uvp + static_cast<size_t>(row / 2) * uvPitch;
    uint32_t* o = reinterpret_cast<uint32_t*>(out + static_cast<size_t>(row) * w * 4);
    for (int x = 0; x + 1 < w; x += 2) {
      int u = uv[x], v = uv[x + 1];
      int r = t.rv[v], g = t.gu[u] + t.gv[v], b = t.bu[u];
      int y0 = t.y[yr[x]], y1 = t.y[yr[x + 1]];
      o[x] = clip[(y0 + r) >> 12] | (clip[(y0 + g) >> 12] << 8) | (clip[(y0 + b) >> 12] << 16) | 0xff000000u;
      o[x + 1] = clip[(y1 + r) >> 12] | (clip[(y1 + g) >> 12] << 8) | (clip[(y1 + b) >> 12] << 16) | 0xff000000u;
    }
  }
}

// ============================================================ decoder

namespace {

using Clock = std::chrono::steady_clock;

struct Decoder {
  uint32_t id = 0;
  std::thread th;

  // input queue (mu)
  std::mutex mu;
  std::condition_variable cv;
  std::deque<std::vector<uint8_t>> q;
  bool stop = false, needKey = true;
  uint64_t dropped = 0;

  // frame double buffer (frameMu)
  std::mutex frameMu;
  std::vector<uint8_t> front, back;
  int fw = 0, fh = 0;
  bool hasFrame = false;

  // stats (mu)
  uint64_t frames = 0, errors = 0;
  std::deque<Clock::time_point> recent;
  std::string decoderName = "Microsoft H.264 Video Decoder MFT";

  // decoder thread only
  ComPtr<IMFTransform> mft;
  int outW = 0, outH = 0, stride = 0, allocH = 0;  // visible size, NV12 pitch, rows in the Y plane
  DWORD outSize = 0;
  bool providesSamples = false;
  int lastW = 0, lastH = 0;
};

std::mutex g_mu;  // guards g_decoders
std::map<uint32_t, std::shared_ptr<Decoder>> g_decoders;
std::atomic<pn_frame_cb> g_frameCb{nullptr};
thread_local std::map<uint32_t, std::shared_ptr<Decoder>> t_locked;  // keeps locked decoders alive

std::shared_ptr<Decoder> find(uint32_t id) {
  std::lock_guard<std::mutex> lk(g_mu);
  auto it = g_decoders.find(id);
  return it == g_decoders.end() ? nullptr : it->second;
}

bool setNv12Output(Decoder& d) {
  for (DWORD i = 0;; i++) {
    ComPtr<IMFMediaType> t;
    if (FAILED(d.mft->GetOutputAvailableType(0, i, &t))) return false;
    GUID sub{};
    t->GetGUID(MF_MT_SUBTYPE, &sub);
    if (sub != MFVideoFormat_NV12) continue;
    if (FAILED(d.mft->SetOutputType(0, t.Get(), 0))) return false;
    UINT32 w = 0, h = 0;
    MFGetAttributeSize(t.Get(), MF_MT_FRAME_SIZE, &w, &h);
    d.outW = w;
    d.outH = h;
    d.allocH = h;
    MFVideoArea area{};
    if (SUCCEEDED(t->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE, reinterpret_cast<UINT8*>(&area), sizeof area, nullptr)) &&
        area.Area.cx > 0 && area.Area.cy > 0) {
      d.outW = std::min<int>(area.Area.cx, w);
      d.outH = std::min<int>(area.Area.cy, h);
    }
    UINT32 st = 0;
    d.stride = SUCCEEDED(t->GetUINT32(MF_MT_DEFAULT_STRIDE, &st)) && static_cast<int>(st) > 0 ? static_cast<int>(st) : static_cast<int>(w);
    MFT_OUTPUT_STREAM_INFO si{};
    d.mft->GetOutputStreamInfo(0, &si);
    d.providesSamples = (si.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    d.outSize = std::max<DWORD>(si.cbSize, static_cast<DWORD>(d.stride) * h * 3 / 2);
    return true;
  }
}

bool createMft(Decoder& d) {
  d.mft.Reset();
  if (FAILED(CoCreateInstance(CLSID_CMSH264DecoderMFT, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&d.mft)))) return false;
  ComPtr<IMFAttributes> attrs;
  if (SUCCEEDED(d.mft->GetAttributes(&attrs))) attrs->SetUINT32(MF_LOW_LATENCY, TRUE);  // output each frame immediately
  ComPtr<ICodecAPI> api;
  if (SUCCEEDED(d.mft.As(&api))) {
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_BOOL;
    v.boolVal = VARIANT_TRUE;
    api->SetValue(&CODECAPI_AVLowLatencyMode, &v);
  }
  ComPtr<IMFMediaType> in;
  MFCreateMediaType(&in);
  in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  if (FAILED(d.mft->SetInputType(0, in.Get(), 0))) return false;
  if (!setNv12Output(d)) return false;
  d.mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  d.mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  return true;
}

void deliver(Decoder& d, IMFSample* s) {
  ComPtr<IMFMediaBuffer> buf;
  if (FAILED(s->ConvertToContiguousBuffer(&buf))) return;
  BYTE* p = nullptr;
  DWORD len = 0;
  ComPtr<IMF2DBuffer> b2;
  LONG pitch = d.stride;
  BYTE* scan0 = nullptr;
  bool locked2d = SUCCEEDED(buf.As(&b2)) && SUCCEEDED(b2->Lock2D(&scan0, &pitch)) && pitch > 0;
  if (!locked2d) {
    if (FAILED(buf->Lock(&p, nullptr, &len))) return;
    scan0 = p;
    pitch = d.stride;
    if (len < static_cast<DWORD>(pitch) * d.allocH * 3 / 2) {
      buf->Unlock();
      return;
    }
  }
  int w = d.outW & ~1, h = d.outH & ~1;
  d.back.resize(static_cast<size_t>(w) * h * 4);
  nv12ToRgba(scan0, pitch, scan0 + static_cast<size_t>(pitch) * d.allocH, pitch, w, h, d.back.data());
  if (locked2d) b2->Unlock2D();
  else buf->Unlock();
  {
    std::lock_guard<std::mutex> lk(d.frameMu);
    std::swap(d.front, d.back);
    d.fw = w;
    d.fh = h;
    d.hasFrame = true;
  }
  {
    std::lock_guard<std::mutex> lk(d.mu);
    d.frames++;
    auto now = Clock::now();
    d.recent.push_back(now);
    while (!d.recent.empty() && now - d.recent.front() > std::chrono::seconds(2)) d.recent.pop_front();
  }
  if (w != d.lastW || h != d.lastH) {
    d.lastW = w;
    d.lastH = h;
    emit(PN_EV_VIDEO_SIZE, static_cast<int32_t>(d.id), (w << 16) | h);
  }
  if (auto cb = g_frameCb.load()) cb(d.id);
}

// Returns false on a decode error (caller waits for the next keyframe).
bool decode(Decoder& d, const std::vector<uint8_t>& au, int64_t ts) {
  ComPtr<IMFMediaBuffer> buf;
  ComPtr<IMFSample> s;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(au.size()), &buf)) || FAILED(MFCreateSample(&s))) return false;
  BYTE* p = nullptr;
  buf->Lock(&p, nullptr, nullptr);
  memcpy(p, au.data(), au.size());
  buf->Unlock();
  buf->SetCurrentLength(static_cast<DWORD>(au.size()));
  s->AddBuffer(buf.Get());
  s->SetSampleTime(ts);
  HRESULT hr = d.mft->ProcessInput(0, s.Get(), 0);
  if (hr == MF_E_NOTACCEPTING) {
    d.mft->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    hr = d.mft->ProcessInput(0, s.Get(), 0);
  }
  if (FAILED(hr)) return false;
  for (int guard = 0; guard < 16; guard++) {
    MFT_OUTPUT_DATA_BUFFER ob{};
    ComPtr<IMFSample> own;
    if (!d.providesSamples) {
      ComPtr<IMFMediaBuffer> ob2;
      MFCreateMemoryBuffer(d.outSize, &ob2);
      MFCreateSample(&own);
      own->AddBuffer(ob2.Get());
      ob.pSample = own.Get();
    }
    DWORD status = 0;
    hr = d.mft->ProcessOutput(0, 1, &ob, &status);
    if (ob.pEvents) ob.pEvents->Release();
    ComPtr<IMFSample> got;
    if (ob.pSample) {
      got = ob.pSample;
      if (!own) ob.pSample->Release();
    }
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) return true;
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      if (!setNv12Output(d)) return false;
      continue;
    }
    if (FAILED(hr)) return false;
    if (got) deliver(d, got.Get());
  }
  return true;
}

void run(std::shared_ptr<Decoder> dp) {
  Decoder& d = *dp;
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  MFStartup(MF_VERSION, MFSTARTUP_LITE);
  bool ok = createMft(d);
  if (!ok) loge("video: cannot create H.264 decoder");
  int64_t ts = 0;
  while (true) {
    std::vector<uint8_t> au;
    {
      std::unique_lock<std::mutex> lk(d.mu);
      d.cv.wait(lk, [&] { return d.stop || !d.q.empty(); });
      if (d.stop) break;
      au = std::move(d.q.front());
      d.q.pop_front();
    }
    if (!ok) continue;
    ts += 333333;
    if (!decode(d, au, ts)) {
      std::lock_guard<std::mutex> lk(d.mu);
      d.errors++;
      d.needKey = true;  // corrupt / unsupported data: resync on the next IDR
      d.q.clear();
      d.mft->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    }
  }
  if (d.mft) {
    d.mft->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    d.mft.Reset();
  }
  MFShutdown();
  CoUninitialize();
}

bool isKeyframe(const uint8_t* p, int n) {
  bool idr = false;
  forEachNal(p, n, [&](int t, const uint8_t*, size_t) { idr |= t == 5; });
  return idr;
}

}  // namespace

// ============================================================ API

int open(uint32_t id) {
  std::lock_guard<std::mutex> lk(g_mu);
  if (g_decoders.count(id)) return 0;
  auto d = std::make_shared<Decoder>();
  d->id = id;
  d->th = std::thread(run, d);
  g_decoders[id] = d;
  return 0;
}

void close(uint32_t id) {
  std::shared_ptr<Decoder> d;
  {
    std::lock_guard<std::mutex> lk(g_mu);
    auto it = g_decoders.find(id);
    if (it == g_decoders.end()) return;
    d = it->second;
    g_decoders.erase(it);
  }
  {
    std::lock_guard<std::mutex> lk(d->mu);
    d->stop = true;
  }
  d->cv.notify_all();
  if (d->th.joinable()) d->th.join();
}

void push(uint32_t id, const uint8_t* data, int len, bool keyframe) {
  if (!data || len <= 0) return;
  auto d = find(id);
  if (!d) return;
  bool key = keyframe || isKeyframe(data, len);
  {
    std::lock_guard<std::mutex> lk(d->mu);
    if (d->q.size() > 10) {  // decoder cannot keep up: skip to the next keyframe
      d->dropped += d->q.size();
      d->q.clear();
      d->needKey = true;
    }
    if (d->needKey && !key) {
      d->dropped++;
      return;
    }
    d->needKey = false;
    d->q.emplace_back(data, data + len);
  }
  d->cv.notify_one();
}

std::string statsJson(uint32_t id) {
  auto d = find(id);
  if (!d) return "{}";
  std::lock_guard<std::mutex> lk(d->mu);
  auto now = Clock::now();
  while (!d->recent.empty() && now - d->recent.front() > std::chrono::seconds(2)) d->recent.pop_front();
  double fps = 0;
  if (d->recent.size() >= 2) {
    double span = std::chrono::duration<double>(now - d->recent.front()).count();
    if (span > 0.2) fps = (d->recent.size() - 1) / span;
  }
  char b[512];
  snprintf(b, sizeof b,
           "{\"w\":%d,\"h\":%d,\"fps\":%.1f,\"frames\":%llu,\"dropped\":%llu,\"errors\":%llu,\"queued\":%zu,\"waitingKey\":%s,"
           "\"decoder\":\"%s\",\"hw\":false}",
           d->lastW, d->lastH, fps, static_cast<unsigned long long>(d->frames), static_cast<unsigned long long>(d->dropped),
           static_cast<unsigned long long>(d->errors), d->q.size(), d->needKey ? "true" : "false", jsonEscape(d->decoderName).c_str());
  return b;
}

void setFrameCallback(pn_frame_cb cb) { g_frameCb = cb; }

bool lockFrame(uint32_t id, const uint8_t** rgba, int* w, int* h) {
  auto d = find(id);
  if (!d) return false;
  d->frameMu.lock();
  if (!d->hasFrame) {
    d->frameMu.unlock();
    return false;
  }
  if (rgba) *rgba = d->front.data();
  if (w) *w = d->fw;
  if (h) *h = d->fh;
  t_locked[id] = d;
  return true;
}

void unlockFrame(uint32_t id) {
  auto it = t_locked.find(id);
  if (it == t_locked.end()) return;
  it->second->frameMu.unlock();
  t_locked.erase(it);
}

void shutdown() {
  std::vector<uint32_t> ids;
  {
    std::lock_guard<std::mutex> lk(g_mu);
    for (auto& kv : g_decoders) ids.push_back(kv.first);
  }
  for (uint32_t id : ids) close(id);
  g_frameCb = nullptr;
}

}  // namespace pn::video
