// H.264 encoding with Media Foundation (see h264_enc.h).
#include <windows.h>
#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mftransform.h>
#include <strmif.h>
#include <wmcodecdsp.h>
#include <wrl/client.h>

#include <condition_variable>
#include <deque>

#include "h264_enc.h"

using Microsoft::WRL::ComPtr;

namespace pn {

// ============================================================ Annex-B helpers

static size_t startCodeLen(const uint8_t* p, size_t n) {
  if (n >= 4 && p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 1) return 4;
  if (n >= 3 && p[0] == 0 && p[1] == 0 && p[2] == 1) return 3;
  return 0;
}

void toAnnexB(const uint8_t* p, size_t n, std::vector<uint8_t>& out) {
  if (startCodeLen(p, n)) {
    out.insert(out.end(), p, p + n);
    return;
  }
  static const uint8_t sc[4] = {0, 0, 0, 1};
  size_t i = 0;
  while (i + 4 <= n) {
    size_t len = (size_t(p[i]) << 24) | (size_t(p[i + 1]) << 16) | (size_t(p[i + 2]) << 8) | p[i + 3];
    i += 4;
    if (len > n - i) break;
    out.insert(out.end(), sc, sc + 4);
    out.insert(out.end(), p + i, p + i + len);
    i += len;
  }
}

void forEachNal(const uint8_t* p, size_t n, const std::function<void(int, const uint8_t*, size_t)>& fn) {
  size_t i = 0;
  // find first start code
  while (i + 3 <= n && !startCodeLen(p + i, n - i)) i++;
  while (i < n) {
    size_t sc = startCodeLen(p + i, n - i);
    if (!sc) break;
    size_t j = i + sc;
    size_t k = j;
    while (k + 3 <= n && !(p[k] == 0 && p[k + 1] == 0 && (p[k + 2] == 1 || (k + 3 < n && p[k + 2] == 0 && p[k + 3] == 1)))) k++;
    if (k + 3 > n) k = n;
    if (j < n) fn(p[j] & 0x1f, p + i, k - i);
    i = k;
  }
}

// MF_MT_MPEG_SEQUENCE_HEADER may be Annex-B or an avcC record.
static std::vector<uint8_t> seqHeaderToAnnexB(const uint8_t* p, size_t n) {
  std::vector<uint8_t> out;
  if (!n) return out;
  if (startCodeLen(p, n)) return std::vector<uint8_t>(p, p + n);
  if (p[0] == 1 && n >= 7) {  // avcC
    static const uint8_t sc[4] = {0, 0, 0, 1};
    size_t i = 5;
    for (int pass = 0; pass < 2 && i < n; pass++) {
      int cnt = pass == 0 ? (p[i] & 0x1f) : p[i];
      i++;
      for (int k = 0; k < cnt && i + 2 <= n; k++) {
        size_t len = (size_t(p[i]) << 8) | p[i + 1];
        i += 2;
        if (len > n - i) return out;
        out.insert(out.end(), sc, sc + 4);
        out.insert(out.end(), p + i, p + i + len);
        i += len;
      }
    }
  }
  return out;
}

// ============================================================ MFT event pump (async MFTs)

namespace {

// Collects events of an async MFT (BeginGetEvent loop) so the encoder thread can wait with a timeout.
class EventPump : public IMFAsyncCallback {
 public:
  explicit EventPump(IMFMediaEventGenerator* gen) : gen_(gen) {}
  STDMETHODIMP QueryInterface(REFIID iid, void** pv) override {
    if (iid == __uuidof(IUnknown) || iid == __uuidof(IMFAsyncCallback)) {
      *pv = static_cast<IMFAsyncCallback*>(this);
      AddRef();
      return S_OK;
    }
    *pv = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++ref_; }
  STDMETHODIMP_(ULONG) Release() override {
    ULONG r = --ref_;
    if (!r) delete this;
    return r;
  }
  STDMETHODIMP GetParameters(DWORD*, DWORD*) override { return E_NOTIMPL; }
  STDMETHODIMP Invoke(IMFAsyncResult* res) override {
    ComPtr<IMFMediaEvent> ev;
    HRESULT hr;
    {
      std::lock_guard<std::mutex> lk(mu_);
      if (!gen_) return S_OK;
      hr = gen_->EndGetEvent(res, &ev);
    }
    MediaEventType t = MEError;
    HRESULT st = hr;
    if (SUCCEEDED(hr)) {
      ev->GetType(&t);
      ev->GetStatus(&st);
    }
    {
      std::lock_guard<std::mutex> lk(mu_);
      q_.push_back({t, st});
      if (SUCCEEDED(hr) && gen_ && !stop_ && FAILED(gen_->BeginGetEvent(this, nullptr))) q_.push_back({MEError, E_FAIL});
    }
    cv_.notify_all();
    return S_OK;
  }
  bool start() { return SUCCEEDED(gen_->BeginGetEvent(this, nullptr)); }
  void stop() {
    std::lock_guard<std::mutex> lk(mu_);
    stop_ = true;
    gen_ = nullptr;
  }
  // Pops the next event, waiting up to ms. Returns false on timeout.
  bool next(int ms, MediaEventType* t, HRESULT* st) {
    std::unique_lock<std::mutex> lk(mu_);
    if (!cv_.wait_for(lk, std::chrono::milliseconds(ms), [&] { return !q_.empty(); })) return false;
    *t = q_.front().first;
    *st = q_.front().second;
    q_.pop_front();
    return true;
  }

 private:
  virtual ~EventPump() = default;
  std::atomic<ULONG> ref_{1};
  std::mutex mu_;
  std::condition_variable cv_;
  std::deque<std::pair<MediaEventType, HRESULT>> q_;
  IMFMediaEventGenerator* gen_;  // not owned; cleared by stop() before the MFT is released
  bool stop_ = false;
};

HRESULT setUi4(ICodecAPI* api, const GUID& g, ULONG v) {
  VARIANT var;
  VariantInit(&var);
  var.vt = VT_UI4;
  var.ulVal = v;
  return api->SetValue(&g, &var);
}
HRESULT setBool(ICodecAPI* api, const GUID& g, bool v) {
  VARIANT var;
  VariantInit(&var);
  var.vt = VT_BOOL;
  var.boolVal = v ? VARIANT_TRUE : VARIANT_FALSE;
  return api->SetValue(&g, &var);
}

std::string hrStr(HRESULT hr) {
  char b[16];
  snprintf(b, sizeof b, "0x%08lX", static_cast<unsigned long>(hr));
  return b;
}

}  // namespace

// ============================================================ encoder

struct H264Encoder::Impl {
  ComPtr<IMFTransform> mft;
  ComPtr<ICodecAPI> api;
  EventPump* pump = nullptr;  // async MFTs only
  bool async = false, hw = false, providesSamples = false;
  DWORD outSize = 0;
  int needInput = 0;           // async: pending METransformNeedInput grants
  int pending = 0;             // async: frames fed (or dropped) without output yet
  std::string name;
  std::vector<uint8_t> seqHdr;  // Annex-B SPS+PPS
  std::vector<uint8_t> au;      // scratch

  ~Impl() {
    if (mft) {
      mft->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
      if (pump) pump->stop();
      ComPtr<IMFShutdown> sd;
      if (SUCCEEDED(mft.As(&sd))) sd->Shutdown();
    }
    if (pump) pump->Release();
    api.Reset();
    mft.Reset();
  }

  void refreshSeqHeader() {
    ComPtr<IMFMediaType> t;
    if (FAILED(mft->GetOutputCurrentType(0, &t))) return;
    UINT32 n = 0;
    if (FAILED(t->GetBlobSize(MF_MT_MPEG_SEQUENCE_HEADER, &n)) || !n) return;
    std::vector<uint8_t> b(n);
    if (SUCCEEDED(t->GetBlob(MF_MT_MPEG_SEQUENCE_HEADER, b.data(), n, nullptr))) seqHdr = seqHeaderToAnnexB(b.data(), n);
  }

  HRESULT configure(int w, int h, int fps, int kbps) {
    HRESULT hr;
    if (async) {
      ComPtr<IMFAttributes> attrs;
      if (FAILED(hr = mft->GetAttributes(&attrs))) return hr;
      if (FAILED(hr = attrs->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, TRUE))) return hr;
      attrs->SetUINT32(MF_LOW_LATENCY, TRUE);
    }
    mft.As(&api);
    if (api) {
      // Must be set before the media types for most encoders.
      setUi4(api.Get(), CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_CBR);
      setUi4(api.Get(), CODECAPI_AVEncCommonMeanBitRate, kbps * 1000);
      setUi4(api.Get(), CODECAPI_AVEncMPVGOPSize, fps * 5);
      setUi4(api.Get(), CODECAPI_AVEncMPVDefaultBPictureCount, 0);
      setBool(api.Get(), CODECAPI_AVLowLatencyMode, true);
      setUi4(api.Get(), CODECAPI_AVEncCommonQualityVsSpeed, 50);
    }
    ComPtr<IMFMediaType> out, in;
    MFCreateMediaType(&out);
    out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    out->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    out->SetUINT32(MF_MT_AVG_BITRATE, kbps * 1000);
    MFSetAttributeSize(out.Get(), MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(out.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(out.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    out->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main);
    if (FAILED(hr = mft->SetOutputType(0, out.Get(), 0))) return hr;
    MFCreateMediaType(&in);
    in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    MFSetAttributeSize(in.Get(), MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(in.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(in.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    in->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
    in->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
    if (FAILED(hr = mft->SetInputType(0, in.Get(), 0))) return hr;
    if (api) {  // some encoders only accept these once the types are set
      setUi4(api.Get(), CODECAPI_AVEncMPVGOPSize, fps * 5);
      setUi4(api.Get(), CODECAPI_AVEncMPVDefaultBPictureCount, 0);
    }
    MFT_OUTPUT_STREAM_INFO si{};
    if (FAILED(hr = mft->GetOutputStreamInfo(0, &si))) return hr;
    providesSamples = (si.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    outSize = std::max<DWORD>(si.cbSize, w * h * 3 / 2 + 4096);
    refreshSeqHeader();
    if (async) {
      ComPtr<IMFMediaEventGenerator> gen;
      if (FAILED(hr = mft.As(&gen))) return hr;
      pump = new EventPump(gen.Get());
      if (!pump->start()) return E_FAIL;
    }
    mft->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    if (FAILED(hr = mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0))) return hr;
    if (FAILED(hr = mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0))) return hr;
    return S_OK;
  }

  // Pulls one output sample. Returns S_OK with data, MF_E_TRANSFORM_NEED_MORE_INPUT, or an error.
  HRESULT pull(const H264Encoder::Sink& sink) {
    MFT_OUTPUT_DATA_BUFFER ob{};
    ComPtr<IMFSample> own;
    if (!providesSamples) {
      ComPtr<IMFMediaBuffer> buf;
      MFCreateMemoryBuffer(outSize, &buf);
      MFCreateSample(&own);
      own->AddBuffer(buf.Get());
      ob.pSample = own.Get();
    }
    DWORD status = 0;
    HRESULT hr = mft->ProcessOutput(0, 1, &ob, &status);
    if (ob.pEvents) ob.pEvents->Release();
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      ComPtr<IMFMediaType> t;
      if (SUCCEEDED(mft->GetOutputAvailableType(0, 0, &t))) mft->SetOutputType(0, t.Get(), 0);
      refreshSeqHeader();
      if (ob.pSample && !own) ob.pSample->Release();
      return S_FALSE;
    }
    if (FAILED(hr)) {
      if (ob.pSample && !own) ob.pSample->Release();
      return hr;
    }
    ComPtr<IMFSample> s = ob.pSample;
    if (!own && ob.pSample) ob.pSample->Release();  // MFT-provided: we own the reference
    if (!s) return S_FALSE;
    ComPtr<IMFMediaBuffer> buf;
    if (FAILED(s->ConvertToContiguousBuffer(&buf))) return S_FALSE;
    BYTE* p = nullptr;
    DWORD len = 0;
    if (FAILED(buf->Lock(&p, nullptr, &len))) return S_FALSE;
    au.clear();
    toAnnexB(p, len, au);
    buf->Unlock();
    // Scan NAL units: keep in-band SPS/PPS, find IDR.
    bool idr = false, hasSps = false;
    std::vector<uint8_t> sps;
    forEachNal(au.data(), au.size(), [&](int t, const uint8_t* n, size_t sz) {
      if (t == 5) idr = true;
      if (t == 7 || t == 8) {
        if (t == 7) hasSps = true;
        sps.insert(sps.end(), n, n + sz);
      }
    });
    if (hasSps) seqHdr = sps;
    if (idr && !hasSps && !seqHdr.empty()) au.insert(au.begin(), seqHdr.begin(), seqHdr.end());
    if (!au.empty()) sink(au.data(), au.size(), idr);
    return S_OK;
  }
};

H264Encoder::H264Encoder() = default;
H264Encoder::~H264Encoder() { close(); }

void H264Encoder::close() { d_.reset(); }
std::string H264Encoder::name() const { return d_ ? d_->name : ""; }
bool H264Encoder::hardware() const { return d_ && d_->hw; }

static std::string attrString(IMFAttributes* a, const GUID& key) {
  wchar_t* s = nullptr;
  UINT32 n = 0;
  if (FAILED(a->GetAllocatedString(key, &s, &n))) return {};
  std::string r = narrow(std::wstring(s, n));
  CoTaskMemFree(s);
  return r;
}

bool H264Encoder::open(int w, int h, int fps, int kbps, bool allowHw, std::string* err) {
  close();
  w_ = w;
  h_ = h;
  fps_ = fps;
  kbps_ = kbps;
  std::string errs;
  if (allowHw) {
    MFT_REGISTER_TYPE_INFO inT{MFMediaType_Video, MFVideoFormat_NV12}, outT{MFMediaType_Video, MFVideoFormat_H264};
    IMFActivate** acts = nullptr;
    UINT32 count = 0;
    if (SUCCEEDED(MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER, &inT, &outT,
                            &acts, &count))) {
      for (UINT32 i = 0; i < count; i++) {
        if (!d_) {
          auto d = std::make_unique<Impl>();
          d->async = d->hw = true;
          d->name = attrString(acts[i], MFT_FRIENDLY_NAME_Attribute);
          HRESULT hr = acts[i]->ActivateObject(IID_PPV_ARGS(&d->mft));
          if (SUCCEEDED(hr)) hr = d->configure(w, h, fps, kbps);
          if (SUCCEEDED(hr)) {
            d_ = std::move(d);
          } else {
            errs += d->name + " " + hrStr(hr) + "; ";
            d.reset();
            acts[i]->ShutdownObject();
          }
        }
        acts[i]->Release();
      }
      CoTaskMemFree(acts);
    }
  }
  if (!d_) {
    auto d = std::make_unique<Impl>();
    d->name = "Microsoft H.264 Encoder (软件)";
    HRESULT hr = CoCreateInstance(CLSID_CMSH264EncoderMFT, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&d->mft));
    if (SUCCEEDED(hr)) hr = d->configure(w, h, fps, kbps);
    if (FAILED(hr)) {
      if (err) *err = errs + "software encoder " + hrStr(hr);
      return false;
    }
    d_ = std::move(d);
  }
  if (!errs.empty()) logw("screen: hardware encoders skipped: " + errs);
  return true;
}

void H264Encoder::setBitrate(int kbps) {
  kbps_ = kbps;
  if (d_ && d_->api) setUi4(d_->api.Get(), CODECAPI_AVEncCommonMeanBitRate, kbps * 1000);
}

bool H264Encoder::encode(const uint8_t* nv12, int64_t time, bool forceKey, const Sink& sink) {
  if (!d_) return false;
  Impl& d = *d_;
  // Input sample (system memory, tightly packed NV12).
  DWORD size = w_ * h_ * 3 / 2;
  ComPtr<IMFMediaBuffer> buf;
  ComPtr<IMFSample> s;
  if (FAILED(MFCreateMemoryBuffer(size, &buf)) || FAILED(MFCreateSample(&s))) return false;
  BYTE* p = nullptr;
  buf->Lock(&p, nullptr, nullptr);
  memcpy(p, nv12, size);
  buf->Unlock();
  buf->SetCurrentLength(size);
  s->AddBuffer(buf.Get());
  s->SetSampleTime(time);
  s->SetSampleDuration(10000000LL / fps_);
  if (forceKey && d.api) setUi4(d.api.Get(), CODECAPI_AVEncVideoForceKeyFrame, 1);

  HRESULT hr = S_OK;
  if (!d.async) {
    hr = d.mft->ProcessInput(0, s.Get(), 0);
    if (hr == MF_E_NOTACCEPTING) {  // drain then retry once
      while (d.pull(sink) == S_OK) {}
      hr = d.mft->ProcessInput(0, s.Get(), 0);
    }
    if (SUCCEEDED(hr)) {
      HRESULT r;
      while ((r = d.pull(sink)) == S_OK || r == S_FALSE) {}
    }
  } else {
    // Async: METransformNeedInput grants one ProcessInput, METransformHaveOutput one ProcessOutput.
    // Feed this frame, then wait (bounded) for its output so latency stays at one frame.
    auto handle = [&](int waitMs) -> int {  // 1 event handled, 0 timeout
      MediaEventType t;
      HRESULT st;
      if (!d.pump->next(waitMs, &t, &st)) return 0;
      if (t == METransformNeedInput) {
        d.needInput++;
      } else if (t == METransformHaveOutput) {
        HRESULT r = d.pull(sink);
        if (r == S_OK) d.pending = std::max(0, d.pending - 1);
        else if (FAILED(r) && r != MF_E_TRANSFORM_NEED_MORE_INPUT) hr = r;
      } else if (t == MEError || FAILED(st)) {
        hr = FAILED(st) ? st : E_FAIL;
      }
      return 1;
    };
    while (SUCCEEDED(hr) && handle(0)) {}
    DWORD t0 = GetTickCount();
    while (SUCCEEDED(hr) && d.needInput == 0 && GetTickCount() - t0 < 100) handle(20);
    if (SUCCEEDED(hr) && d.needInput > 0) {
      hr = d.mft->ProcessInput(0, s.Get(), 0);
      if (SUCCEEDED(hr)) {
        d.needInput--;
        d.pending++;
        t0 = GetTickCount();
        while (SUCCEEDED(hr) && d.pending > 0 && GetTickCount() - t0 < 100) handle(10);
      }
    } else if (SUCCEEDED(hr)) {
      d.pending++;  // frame dropped: the encoder did not ask for input
    }
    if (SUCCEEDED(hr) && d.pending > fps_ * 2) hr = E_FAIL;  // no output for ~2 s: stuck
  }
  if (SUCCEEDED(hr)) return true;
  if (!d.hw) {
    loge("screen: software encoder failed " + hrStr(hr));
    return false;
  }
  // Hardware encoder broke at runtime: fall back to software and resend this frame as IDR.
  logw("screen: " + d.name + " failed (" + hrStr(hr) + "), switching to software encoder");
  std::string err;
  if (!open(w_, h_, fps_, kbps_, false, &err)) {
    loge("screen: " + err);
    return false;
  }
  return encode(nv12, time, true, sink);
}

}  // namespace pn
