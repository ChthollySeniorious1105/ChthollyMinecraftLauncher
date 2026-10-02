// Screen capture + H.264 encoding (see screen.h).
#include <windows.h>
#include <unknwn.h>
#include <d3d11_4.h>
#include <dwmapi.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <wrl/client.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <stdexcept>
#include <thread>

#include "h264_enc.h"
#include "screen.h"

using Microsoft::WRL::ComPtr;
namespace wgc = winrt::Windows::Graphics::Capture;
namespace wdx = winrt::Windows::Graphics::DirectX;

namespace pn::screen {
namespace {

// ============================================================ sources

struct Monitor {
  HMONITOR h;
  RECT rc;   // physical pixels (per-monitor DPI aware thread)
  int w, h2;
  bool primary;
};

// Runs fn with a per-monitor-DPI-aware thread context so sizes are physical pixels.
template <class F>
auto dpiAware(F fn) {
  DPI_AWARENESS_CONTEXT old = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  auto r = fn();
  if (old) SetThreadDpiAwarenessContext(old);
  return r;
}

std::vector<Monitor> monitors() {
  return dpiAware([] {
    std::vector<Monitor> v;
    EnumDisplayMonitors(nullptr, nullptr, [](HMONITOR h, HDC, LPRECT, LPARAM p) -> BOOL {
      MONITORINFOEXW mi{};
      mi.cbSize = sizeof mi;
      if (!GetMonitorInfoW(h, &mi)) return TRUE;
      DEVMODEW dm{};
      dm.dmSize = sizeof dm;
      int w = mi.rcMonitor.right - mi.rcMonitor.left, ht = mi.rcMonitor.bottom - mi.rcMonitor.top;
      if (EnumDisplaySettingsW(mi.szDevice, ENUM_CURRENT_SETTINGS, &dm)) {
        w = dm.dmPelsWidth;
        ht = dm.dmPelsHeight;
      }
      reinterpret_cast<std::vector<Monitor>*>(p)->push_back({h, mi.rcMonitor, w, ht, (mi.dwFlags & MONITORINFOF_PRIMARY) != 0});
      return TRUE;
    }, reinterpret_cast<LPARAM>(&v));
    return v;
  });
}

bool isCapturableWindow(HWND h) {
  if (!IsWindowVisible(h) || GetAncestor(h, GA_ROOT) != h) return false;
  LONG_PTR ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
  if (ex & WS_EX_TOOLWINDOW) return false;
  if (GetWindowTextLengthW(h) == 0 || h == GetShellWindow()) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(h, &pid);
  if (pid == GetCurrentProcessId()) return false;
  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(h, DWMWA_CLOAKED, &cloaked, sizeof cloaked)) && cloaked) return false;
  return true;
}

std::string exeName(HWND h) {
  DWORD pid = 0;
  GetWindowThreadProcessId(h, &pid);
  HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!p) return {};
  wchar_t buf[MAX_PATH * 2];
  DWORD n = MAX_PATH * 2;
  std::wstring s;
  if (QueryFullProcessImageNameW(p, 0, buf, &n)) s.assign(buf, n);
  CloseHandle(p);
  return narrow(s.substr(s.find_last_of(L"\\/") + 1));
}

std::string windowTitle(HWND h) {
  wchar_t buf[512];
  int n = GetWindowTextW(h, buf, 512);
  return narrow(std::wstring(buf, n > 0 ? n : 0));
}

// "m:<index>" -> monitor, "w:<hwnd>" -> window.
bool parseId(const std::string& id, HMONITOR* mon, HWND* wnd, RECT* monRc = nullptr) {
  *mon = nullptr;
  *wnd = nullptr;
  if (id.size() < 3 || id[1] != ':') return false;
  char* end = nullptr;
  unsigned long long v = strtoull(id.c_str() + 2, &end, 10);
  if (!end || *end) return false;
  if (id[0] == 'm') {
    auto ms = monitors();
    if (v >= ms.size()) return false;
    *mon = ms[v].h;
    if (monRc) *monRc = ms[v].rc;
    return true;
  }
  if (id[0] == 'w') {
    *wnd = reinterpret_cast<HWND>(static_cast<uintptr_t>(v));
    return IsWindow(*wnd) != FALSE;
  }
  return false;
}

// ============================================================ pixel conversion (CPU)

// BT.709 limited range, 8-bit fixed point (x256).
inline uint8_t clamp8(int v) { return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v)); }

// Scales BGRA content (cw x ch, pitch) into the dst rect of an NV12 frame (ow x oh, black borders).
// Each output pixel averages 2x2 samples of its source footprint (exact box filter at 2:1).
void bgraToNv12(const uint8_t* src, int pitch, int cw, int ch, uint8_t* nv12, int ow, int oh, RECT dst) {
  uint8_t* Y = nv12;
  uint8_t* UV = nv12 + ow * oh;
  memset(Y, 16, ow * oh);
  memset(UV, 128, ow * oh / 2);
  int dw = dst.right - dst.left, dh = dst.bottom - dst.top;
  if (dw <= 0 || dh <= 0) return;
  auto sampleAt = [](double v, int n) { return std::clamp(static_cast<int>(v), 0, n - 1); };
  std::vector<int> xa(dw), xb(dw);  // byte offsets of the two sample columns
  for (int x = 0; x < dw; x++) {
    xa[x] = sampleAt((x + 0.25) * cw / dw, cw) * 4;
    xb[x] = sampleAt((x + 0.75) * cw / dw, cw) * 4;
  }
  std::vector<int> rgb(static_cast<size_t>(dw) * 6);  // two output rows of summed (x4) R, G, B
  for (int y = 0; y < dh; y += 2) {
    for (int k = 0; k < 2; k++) {
      const uint8_t* ra = src + sampleAt((y + k + 0.25) * ch / dh, ch) * static_cast<size_t>(pitch);
      const uint8_t* rb = src + sampleAt((y + k + 0.75) * ch / dh, ch) * static_cast<size_t>(pitch);
      int* o = rgb.data() + static_cast<size_t>(k) * dw * 3;
      uint8_t* yo = Y + (dst.top + y + k) * ow + dst.left;
      for (int x = 0; x < dw; x++) {
        const uint8_t *p0 = ra + xa[x], *p1 = ra + xb[x], *p2 = rb + xa[x], *p3 = rb + xb[x];
        int b = p0[0] + p1[0] + p2[0] + p3[0], g = p0[1] + p1[1] + p2[1] + p3[1], r = p0[2] + p1[2] + p2[2] + p3[2];
        o[x * 3] = r;
        o[x * 3 + 1] = g;
        o[x * 3 + 2] = b;
        // BT.709 limited: Y = 16 + (47 R + 157 G + 16 B) / 256 (sums are x4)
        yo[x] = static_cast<uint8_t>((47 * r + 157 * g + 16 * b + 4 * 4096 + 512) >> 10);
      }
    }
    uint8_t* uv = UV + ((dst.top + y) / 2) * ow + dst.left;
    const int *o0 = rgb.data(), *o1 = rgb.data() + static_cast<size_t>(dw) * 3;
    for (int x = 0; x < dw; x += 2) {
      int r = o0[x * 3] + o0[x * 3 + 3] + o1[x * 3] + o1[x * 3 + 3];  // x16
      int g = o0[x * 3 + 1] + o0[x * 3 + 4] + o1[x * 3 + 1] + o1[x * 3 + 4];
      int b = o0[x * 3 + 2] + o0[x * 3 + 5] + o1[x * 3 + 2] + o1[x * 3 + 5];
      uv[x] = clamp8((-26 * r - 87 * g + 112 * b + 16 * 32768 + 2048) >> 12);
      uv[x + 1] = clamp8((112 * r - 102 * g - 10 * b + 16 * 32768 + 2048) >> 12);
    }
  }
}

RECT letterbox(int cw, int ch, int ow, int oh) {
  double s = std::min(static_cast<double>(ow) / cw, static_cast<double>(oh) / ch);
  int dw = std::min(ow, static_cast<int>(cw * s + 0.5)) & ~1, dh = std::min(oh, static_cast<int>(ch * s + 0.5)) & ~1;
  int x = ((ow - dw) / 2) & ~1, y = ((oh - dh) / 2) & ~1;
  return {x, y, x + dw, y + dh};
}

// ============================================================ capture session

using Clock = std::chrono::steady_clock;

struct Session {
  std::string id;
  int maxW, maxH, fps, kbps;
  std::thread th;
  std::atomic<bool> stopReq{false}, quiet{false}, keyReq{true};
  std::atomic<int> newKbps{0}, inCallback{0};
  winrt::event_token frameToken{};
  std::string stopReason;  // set before stopReq by the Closed handler

  // capture side (guarded by mu)
  std::mutex mu;
  std::condition_variable cv;
  bool fresh = false;
  ComPtr<ID3D11Texture2D> bufs[2];  // copies of captured frames; the encoder reads one while the other is written
  int cws[2]{}, chs[2]{};            // content size inside bufs[i]
  int latest = -1, busy = -1;
  Clock::time_point nextDue{};
  winrt::Windows::Graphics::SizeInt32 poolSize{};

  // D3D
  ComPtr<ID3D11Device> dev;
  ComPtr<ID3D11DeviceContext> ctx;
  wdx::Direct3D11::IDirect3DDevice rtDev{nullptr};
  wgc::GraphicsCaptureItem item{nullptr};
  wgc::Direct3D11CaptureFramePool pool{nullptr};
  wgc::GraphicsCaptureSession session{nullptr};

  // GPU conversion
  bool gpu = false;
  ComPtr<ID3D11VideoDevice> vdev;
  ComPtr<ID3D11VideoContext> vctx;
  ComPtr<ID3D11VideoProcessorEnumerator> venum;
  ComPtr<ID3D11VideoProcessor> vp;
  ComPtr<ID3D11VideoProcessorInputView> inView[2];
  ComPtr<ID3D11Texture2D> inTex[2];  // textures the input views were made for
  int vpInW = 0, vpInH = 0;
  ComPtr<ID3D11Texture2D> nv12Tex, nv12Staging;
  ComPtr<ID3D11VideoProcessorOutputView> outView;
  ComPtr<ID3D11Texture2D> bgraStaging;  // CPU path
  int bgraW = 0, bgraH = 0;

  int ow = 0, oh = 0, srcW = 0, srcH = 0;
  HWND hwnd = nullptr;  // window capture: polled because item.Closed is not always delivered
  std::vector<uint8_t> nv12;
  H264Encoder enc;

  // stats (mu)
  std::string encName;
  bool encHw = false;
  uint64_t frames = 0, keyframes = 0, dropped = 0, bytes = 0;
  double convertMs = 0, encodeMs = 0;  // smoothed per-frame cost
  std::deque<std::pair<Clock::time_point, size_t>> recent;  // last ~2 s of encoded frames
};

std::mutex g_mu;  // guards g_session
std::unique_ptr<Session> g_session;

void windowClosed(Session* s) {
  {
    std::lock_guard<std::mutex> lk(s->mu);
    s->stopReason = "窗口已关闭";
  }
  s->stopReq = true;
  s->cv.notify_all();
}

void onFrame(Session* s, wgc::Direct3D11CaptureFramePool const& pool) {
  if (s->stopReq) return;
  auto frame = pool.TryGetNextFrame();
  if (!frame) return;
  auto cs = frame.ContentSize();
  if (cs.Width <= 0 || cs.Height <= 0) return;
  if (cs.Width != s->poolSize.Width || cs.Height != s->poolSize.Height) {
    s->poolSize = cs;  // window resized: recreate the pool, keep the output size
    pool.Recreate(s->rtDev, wdx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, cs);
  }
  // pace to the requested fps (accept a frame when it is at most 1/4 interval early)
  auto now = Clock::now();
  auto interval = std::chrono::microseconds(1000000 / s->fps);
  if (now < s->nextDue - interval / 4) return;
  s->nextDue = std::max(s->nextDue + interval, now - interval);

  ComPtr<ID3D11Texture2D> tex;
  auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
  if (FAILED(access->GetInterface(IID_PPV_ARGS(&tex)))) return;
  D3D11_TEXTURE2D_DESC d;
  tex->GetDesc(&d);
  int w = std::min<int>(cs.Width, d.Width), h = std::min<int>(cs.Height, d.Height);
  std::lock_guard<std::mutex> lk(s->mu);
  int i = s->busy == 0 ? 1 : (s->busy == 1 ? 0 : (s->latest == 0 ? 1 : 0));
  auto& dstTex = s->bufs[i];
  D3D11_TEXTURE2D_DESC ld{};
  if (dstTex) dstTex->GetDesc(&ld);
  if (!dstTex || static_cast<int>(ld.Width) < w || static_cast<int>(ld.Height) < h) {
    D3D11_TEXTURE2D_DESC nd{};
    nd.Width = std::max<UINT>(w, ld.Width);
    nd.Height = std::max<UINT>(h, ld.Height);
    nd.MipLevels = nd.ArraySize = 1;
    nd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    nd.SampleDesc.Count = 1;
    nd.Usage = D3D11_USAGE_DEFAULT;
    nd.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    dstTex.Reset();
    if (FAILED(s->dev->CreateTexture2D(&nd, nullptr, &dstTex))) return;
  }
  D3D11_BOX box{0, 0, 0, static_cast<UINT>(w), static_cast<UINT>(h), 1};
  s->ctx->CopySubresourceRegion(dstTex.Get(), 0, 0, 0, 0, tex.Get(), 0, &box);
  if (s->fresh) s->dropped++;  // encoder has not taken the previous one
  s->fresh = true;
  s->latest = i;
  s->cws[i] = w;
  s->chs[i] = h;
  s->cv.notify_all();
}

bool createDevice(Session* s, std::string* err) {
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
  D3D_FEATURE_LEVEL fl[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, fl, 4, D3D11_SDK_VERSION, &s->dev, nullptr, &s->ctx);
  if (FAILED(hr)) {
    flags &= ~D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, fl, 4, D3D11_SDK_VERSION, &s->dev, nullptr, &s->ctx);
  }
  if (FAILED(hr)) {
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, fl, 4, D3D11_SDK_VERSION, &s->dev,
                           nullptr, &s->ctx);
  }
  if (FAILED(hr)) {
    *err = "无法创建 D3D11 设备";
    return false;
  }
  // WGC, our frame callback and the encoder thread all use the immediate context.
  ComPtr<ID3D10Multithread> mt;
  if (SUCCEEDED(s->ctx.As(&mt))) mt->SetMultithreadProtected(TRUE);
  ComPtr<IDXGIDevice> dxgi;
  s->dev.As(&dxgi);
  winrt::com_ptr<::IInspectable> insp;
  if (FAILED(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), insp.put()))) {
    *err = "无法创建 WinRT D3D 设备";
    return false;
  }
  s->rtDev = insp.as<wdx::Direct3D11::IDirect3DDevice>();
  return true;
}

// Sets up the video processor for input textures of size (iw, ih). Returns false -> CPU path.
bool setupVideoProcessor(Session* s, int iw, int ih) {
  s->venum.Reset();
  s->vp.Reset();
  for (int i = 0; i < 2; i++) {
    s->inView[i].Reset();
    s->inTex[i].Reset();
  }
  if (!s->vdev && (FAILED(s->dev.As(&s->vdev)) || FAILED(s->ctx.As(&s->vctx)))) return false;
  D3D11_VIDEO_PROCESSOR_CONTENT_DESC cd{};
  cd.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
  cd.InputFrameRate = {static_cast<UINT>(s->fps), 1};
  cd.InputWidth = iw;
  cd.InputHeight = ih;
  cd.OutputFrameRate = {static_cast<UINT>(s->fps), 1};
  cd.OutputWidth = s->ow;
  cd.OutputHeight = s->oh;
  cd.Usage = D3D11_VIDEO_USAGE_OPTIMAL_SPEED;
  if (FAILED(s->vdev->CreateVideoProcessorEnumerator(&cd, &s->venum))) return false;
  UINT sup = 0;
  if (FAILED(s->venum->CheckVideoProcessorFormat(DXGI_FORMAT_NV12, &sup)) || !(sup & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT))
    return false;
  if (FAILED(s->venum->CheckVideoProcessorFormat(DXGI_FORMAT_B8G8R8A8_UNORM, &sup)) || !(sup & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT))
    return false;
  if (FAILED(s->vdev->CreateVideoProcessor(s->venum.Get(), 0, &s->vp))) return false;
  if (!s->nv12Tex) {
    D3D11_TEXTURE2D_DESC d{};
    d.Width = s->ow;
    d.Height = s->oh;
    d.MipLevels = d.ArraySize = 1;
    d.Format = DXGI_FORMAT_NV12;
    d.SampleDesc.Count = 1;
    d.Usage = D3D11_USAGE_DEFAULT;
    d.BindFlags = D3D11_BIND_RENDER_TARGET;
    if (FAILED(s->dev->CreateTexture2D(&d, nullptr, &s->nv12Tex))) return false;
    d.Usage = D3D11_USAGE_STAGING;
    d.BindFlags = 0;
    d.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(s->dev->CreateTexture2D(&d, nullptr, &s->nv12Staging))) return false;
  }
  s->outView.Reset();
  D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC od{};
  od.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
  if (FAILED(s->vdev->CreateVideoProcessorOutputView(s->nv12Tex.Get(), s->venum.Get(), &od, &s->outView))) return false;
  // Colour spaces: full-range sRGB in, BT.709 limited range out.
  ComPtr<ID3D11VideoContext1> vc1;
  if (SUCCEEDED(s->vctx.As(&vc1))) {
    vc1->VideoProcessorSetStreamColorSpace1(s->vp.Get(), 0, DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
    vc1->VideoProcessorSetOutputColorSpace1(s->vp.Get(), DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
  } else {
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE in{}, out{};
    in.RGB_Range = 0;  // full
    out.YCbCr_Matrix = 1;  // BT.709
    out.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
    s->vctx->VideoProcessorSetStreamColorSpace(s->vp.Get(), 0, &in);
    s->vctx->VideoProcessorSetOutputColorSpace(s->vp.Get(), &out);
  }
  s->vctx->VideoProcessorSetStreamFrameFormat(s->vp.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
  s->vctx->VideoProcessorSetStreamAutoProcessingMode(s->vp.Get(), 0, FALSE);
  D3D11_VIDEO_COLOR black{};
  black.RGBA = {0.f, 0.f, 0.f, 1.f};
  s->vctx->VideoProcessorSetOutputBackgroundColor(s->vp.Get(), FALSE, &black);
  RECT full{0, 0, s->ow, s->oh};
  s->vctx->VideoProcessorSetOutputTargetRect(s->vp.Get(), TRUE, &full);
  s->vpInW = iw;
  s->vpInH = ih;
  return true;
}

// Copies a mapped NV12 staging texture into the tightly packed buffer.
bool readNv12(Session* s) {
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(s->ctx->Map(s->nv12Staging.Get(), 0, D3D11_MAP_READ, 0, &m))) return false;  // waits for the GPU (~1 ms)
  const uint8_t* p = static_cast<const uint8_t*>(m.pData);
  uint8_t* y = s->nv12.data();
  for (int r = 0; r < s->oh; r++) memcpy(y + r * s->ow, p + r * static_cast<size_t>(m.RowPitch), s->ow);
  const uint8_t* uvSrc = p + static_cast<size_t>(m.RowPitch) * s->oh;
  uint8_t* uv = y + s->ow * s->oh;
  for (int r = 0; r < s->oh / 2; r++) memcpy(uv + r * s->ow, uvSrc + r * static_cast<size_t>(m.RowPitch), s->ow);
  s->ctx->Unmap(s->nv12Staging.Get(), 0);
  return true;
}

bool convertGpu(Session* s, int slot, ID3D11Texture2D* tex, int cw, int ch) {
  D3D11_TEXTURE2D_DESC d;
  tex->GetDesc(&d);
  if (!s->vp || s->vpInW != static_cast<int>(d.Width) || s->vpInH != static_cast<int>(d.Height)) {
    if (!setupVideoProcessor(s, d.Width, d.Height)) return false;
  }
  if (s->inTex[slot].Get() != tex) {
    s->inView[slot].Reset();
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC id{};
    id.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    if (FAILED(s->vdev->CreateVideoProcessorInputView(tex, s->venum.Get(), &id, &s->inView[slot]))) return false;
    s->inTex[slot] = tex;
  }
  RECT src{0, 0, cw, ch}, dst = letterbox(cw, ch, s->ow, s->oh);
  s->vctx->VideoProcessorSetStreamSourceRect(s->vp.Get(), 0, TRUE, &src);
  s->vctx->VideoProcessorSetStreamDestRect(s->vp.Get(), 0, TRUE, &dst);
  D3D11_VIDEO_PROCESSOR_STREAM st{};
  st.Enable = TRUE;
  st.pInputSurface = s->inView[slot].Get();
  if (FAILED(s->vctx->VideoProcessorBlt(s->vp.Get(), s->outView.Get(), 0, 1, &st))) return false;
  s->ctx->CopyResource(s->nv12Staging.Get(), s->nv12Tex.Get());
  return readNv12(s);
}

bool convertCpu(Session* s, ID3D11Texture2D* tex, int cw, int ch) {
  if (!s->bgraStaging || s->bgraW < cw || s->bgraH < ch) {
    D3D11_TEXTURE2D_DESC d{};
    tex->GetDesc(&d);
    d.Usage = D3D11_USAGE_STAGING;
    d.BindFlags = 0;
    d.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    d.MiscFlags = 0;
    s->bgraStaging.Reset();
    if (FAILED(s->dev->CreateTexture2D(&d, nullptr, &s->bgraStaging))) return false;
    s->bgraW = d.Width;
    s->bgraH = d.Height;
  }
  D3D11_BOX box{0, 0, 0, static_cast<UINT>(cw), static_cast<UINT>(ch), 1};
  s->ctx->CopySubresourceRegion(s->bgraStaging.Get(), 0, 0, 0, 0, tex, 0, &box);
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(s->ctx->Map(s->bgraStaging.Get(), 0, D3D11_MAP_READ, 0, &m))) return false;
  bgraToNv12(static_cast<const uint8_t*>(m.pData), m.RowPitch, cw, ch, s->nv12.data(), s->ow, s->oh, letterbox(cw, ch, s->ow, s->oh));
  s->ctx->Unmap(s->bgraStaging.Get(), 0);
  return true;
}

std::string statusLocked(Session* s) {
  auto now = Clock::now();
  while (!s->recent.empty() && now - s->recent.front().first > std::chrono::seconds(2)) s->recent.pop_front();
  double fps = 0, kbps = 0;
  if (s->recent.size() >= 2) {
    double span = std::chrono::duration<double>(now - s->recent.front().first).count();
    size_t b = 0;
    for (auto& r : s->recent) b += r.second;
    if (span > 0.2) {
      fps = (s->recent.size() - 1) / span;
      kbps = b * 8 / 1000.0 / span;
    }
  }
  char buf[1024];
  snprintf(buf, sizeof buf,
           "{\"active\":true,\"source\":\"%s\",\"w\":%d,\"h\":%d,\"srcW\":%d,\"srcH\":%d,\"fps\":%.1f,\"targetFps\":%d,"
           "\"kbps\":%.0f,\"targetKbps\":%d,\"encoder\":\"%s\",\"hw\":%s,\"gpuConvert\":%s,\"frames\":%llu,"
           "\"keyframes\":%llu,\"dropped\":%llu,\"convertMs\":%.1f,\"encodeMs\":%.1f}",
           jsonEscape(s->id).c_str(), s->ow, s->oh, s->srcW, s->srcH, fps, s->fps, kbps, s->kbps, jsonEscape(s->encName).c_str(),
           s->encHw ? "true" : "false", s->gpu ? "true" : "false", static_cast<unsigned long long>(s->frames),
           static_cast<unsigned long long>(s->keyframes), static_cast<unsigned long long>(s->dropped), s->convertMs, s->encodeMs);
  return buf;
}

void run(Session* s) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  MFStartup(MF_VERSION, MFSTARTUP_LITE);
  std::string err;
  bool started = false;
  try {
    HMONITOR mon;
    HWND wnd;
    if (!parseId(s->id, &mon, &wnd)) throw std::runtime_error("找不到要共享的屏幕或窗口");
    s->hwnd = wnd;
    if (!wgc::GraphicsCaptureSession::IsSupported()) throw std::runtime_error("系统不支持屏幕捕获（需要 Windows 10 1903 以上）");
    if (!createDevice(s, &err)) throw std::runtime_error(err);
    auto interop = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    HRESULT hr = mon ? interop->CreateForMonitor(mon, winrt::guid_of<wgc::GraphicsCaptureItem>(), winrt::put_abi(s->item))
                     : interop->CreateForWindow(wnd, winrt::guid_of<wgc::GraphicsCaptureItem>(), winrt::put_abi(s->item));
    if (FAILED(hr) || !s->item) throw std::runtime_error("无法捕获该" + std::string(mon ? "屏幕" : "窗口"));
    auto sz = s->item.Size();
    s->srcW = std::max(2, sz.Width);
    s->srcH = std::max(2, sz.Height);
    // output size: fit into max_w x max_h, even, at most 4096
    double sc = 1.0;
    if (s->maxW > 0) sc = std::min(sc, static_cast<double>(s->maxW) / s->srcW);
    if (s->maxH > 0) sc = std::min(sc, static_cast<double>(s->maxH) / s->srcH);
    sc = std::min(sc, 4096.0 / std::max(s->srcW, s->srcH));
    s->ow = std::max(64, static_cast<int>(s->srcW * sc + 0.5) & ~1);
    s->oh = std::max(64, static_cast<int>(s->srcH * sc + 0.5) & ~1);
    s->nv12.assign(s->ow * s->oh * 3 / 2, 0);
    // Test hook: PULSE_SCREEN_FORCE=sw (software encoder) / cpu (CPU conversion) / both.
    char force[16] = {};
    GetEnvironmentVariableA("PULSE_SCREEN_FORCE", force, sizeof force);
    bool forceSw = strstr(force, "sw") || strstr(force, "both"), forceCpu = strstr(force, "cpu") || strstr(force, "both");
    if (!s->enc.open(s->ow, s->oh, s->fps, s->kbps, !forceSw, &err)) throw std::runtime_error("无法创建 H.264 编码器：" + err);
    s->encName = s->enc.name();
    s->encHw = s->enc.hardware();
    s->gpu = !forceCpu && setupVideoProcessor(s, s->srcW, s->srcH);
    if (!s->gpu) logw("screen: GPU colour conversion unavailable, using CPU");

    s->poolSize = sz;
    s->pool = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(s->rtDev, wdx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, sz);
    s->frameToken = s->pool.FrameArrived([s](auto const& pool, auto const&) {
      s->inCallback++;
      try {
        onFrame(s, pool);
      } catch (...) {
      }
      s->inCallback--;
    });
    s->item.Closed([s](auto const&, auto const&) { windowClosed(s); });
    s->session = s->pool.CreateCaptureSession(s->item);
    try {
      s->session.IsCursorCaptureEnabled(true);
    } catch (...) {
    }
    try {
      s->session.IsBorderRequired(false);
    } catch (...) {
    }
    try {
      s->session.MinUpdateInterval(winrt::Windows::Foundation::TimeSpan(std::chrono::microseconds(1000000 / s->fps / 2)));
    } catch (...) {
    }
    s->session.StartCapture();
    started = true;
    std::string st;
    {
      std::lock_guard<std::mutex> lk(s->mu);
      st = statusLocked(s);
    }
    logi("screen: capturing " + s->id + " " + std::to_string(s->ow) + "x" + std::to_string(s->oh) + " via " + s->encName);
    emit(PN_EV_SCREEN, 1, 0, st.data(), static_cast<int32_t>(st.size()));
  } catch (const std::exception& e) {
    err = e.what();
  } catch (const winrt::hresult_error& e) {
    err = "屏幕捕获失败：" + narrow(std::wstring(e.message()));
  }

  // ---- encoder loop
  auto t0 = Clock::now();
  auto lastEnc = t0 - std::chrono::hours(1);
  bool haveFrame = false;
  while (started && !s->stopReq) {
    ComPtr<ID3D11Texture2D> tex;
    int cw = 0, ch = 0, slot = -1;
    bool fresh;
    {
      std::unique_lock<std::mutex> lk(s->mu);
      // wake at least every 250 ms (window-closed poll); a static source is re-encoded once per second
      auto deadline = Clock::now() + std::chrono::milliseconds(250);
      s->cv.wait_until(lk, deadline,
                       [&] { return s->fresh || s->stopReq || (s->keyReq && haveFrame); });
      if (s->stopReq) break;
      if (s->hwnd && !IsWindow(s->hwnd)) {
        lk.unlock();
        windowClosed(s);
        break;
      }
      fresh = s->fresh;
      s->fresh = false;
      if (fresh) {
        slot = s->busy = s->latest;
        tex = s->bufs[slot];
        cw = s->cws[slot];
        ch = s->chs[slot];
      }
    }
    if (int k = s->newKbps.exchange(0)) {
      s->kbps = k;
      s->enc.setBitrate(k);
    }
    auto tc = Clock::now();
    if (fresh) {
      bool ok = s->gpu && convertGpu(s, slot, tex.Get(), cw, ch);
      if (!ok && s->gpu) {
        logw("screen: GPU conversion failed, switching to CPU");
        s->gpu = false;
      }
      if (!ok) ok = convertCpu(s, tex.Get(), cw, ch);
      {
        std::lock_guard<std::mutex> lk(s->mu);
        s->busy = -1;  // conversion waited for the GPU, the texture may be overwritten now
      }
      if (!ok) continue;
      haveFrame = true;
      double ms = std::chrono::duration<double, std::milli>(Clock::now() - tc).count();
      std::lock_guard<std::mutex> lk(s->mu);
      s->convertMs = s->convertMs ? s->convertMs * 0.9 + ms * 0.1 : ms;
    } else if (!haveFrame || (Clock::now() - lastEnc < std::chrono::seconds(1) && !s->keyReq)) {
      continue;  // static source: repeat the last frame once per second (or on a keyframe request)
    }
    lastEnc = Clock::now();
    bool key = s->keyReq.exchange(false);
    int64_t ts = std::chrono::duration_cast<std::chrono::nanoseconds>(lastEnc - t0).count() / 100;
    bool ok = s->enc.encode(s->nv12.data(), ts, key, [&](const uint8_t* au, size_t len, bool idr) {
      {
        std::lock_guard<std::mutex> lk(s->mu);
        s->frames++;
        s->keyframes += idr;
        s->bytes += len;
        s->recent.emplace_back(Clock::now(), len);
      }
      emit(PN_EV_VIDEO_PACKET, idr ? 1 : 0, 0, au, static_cast<int32_t>(len));
    });
    {
      double ms = std::chrono::duration<double, std::milli>(Clock::now() - lastEnc).count();
      std::lock_guard<std::mutex> lk(s->mu);
      s->encodeMs = s->encodeMs ? s->encodeMs * 0.9 + ms * 0.1 : ms;
      s->encName = s->enc.name();
      s->encHw = s->enc.hardware();
    }
    if (!ok) {
      err = "视频编码失败";
      break;
    }
  }

  // ---- teardown
  s->stopReq = true;
  try {
    if (s->pool) s->pool.FrameArrived(s->frameToken);
    if (s->session) s->session.Close();
    if (s->pool) s->pool.Close();
  } catch (...) {
  }
  while (s->inCallback > 0) Sleep(1);  // a frame callback may still be running on the thread pool
  s->session = nullptr;
  s->pool = nullptr;
  s->item = nullptr;
  s->enc.close();
  MFShutdown();
  if (started && !err.empty()) err = "屏幕共享中断：" + err;
  if (!err.empty()) {
    loge("screen: " + err);
    emit(PN_EV_SCREEN, -1, 0, err.data(), static_cast<int32_t>(err.size()));
  } else if (!s->quiet) {
    std::string reason;
    {
      std::lock_guard<std::mutex> lk(s->mu);
      reason = s->stopReason;
    }
    logi("screen: stopped " + reason);
    emit(PN_EV_SCREEN, 0, 0, reason.data(), static_cast<int32_t>(reason.size()));
  }
}

void stopSession(bool quiet) {
  std::unique_ptr<Session> s;
  {
    std::lock_guard<std::mutex> lk(g_mu);
    s = std::move(g_session);
  }
  if (!s) return;
  if (quiet) s->quiet = true;
  s->stopReq = true;
  s->cv.notify_all();
  if (s->th.joinable()) s->th.join();
}

}  // namespace

// ============================================================ API

std::string sourcesJson() {
  std::string j = "{\"monitors\":[";
  auto ms = monitors();
  for (size_t i = 0; i < ms.size(); i++) {
    char b[256];
    snprintf(b, sizeof b, "%s{\"id\":\"m:%zu\",\"name\":\"显示器 %zu\",\"w\":%d,\"h\":%d,\"primary\":%s}", i ? "," : "", i, i + 1,
             ms[i].w, ms[i].h2, ms[i].primary ? "true" : "false");
    j += b;
  }
  j += "],\"windows\":[";
  std::vector<HWND> wins;
  EnumWindows([](HWND h, LPARAM p) -> BOOL {
    if (isCapturableWindow(h)) reinterpret_cast<std::vector<HWND>*>(p)->push_back(h);
    return TRUE;
  }, reinterpret_cast<LPARAM>(&wins));
  bool first = true;
  for (HWND h : wins) {
    j += first ? "" : ",";
    first = false;
    j += "{\"id\":\"w:" + std::to_string(reinterpret_cast<uintptr_t>(h)) + "\",\"title\":\"" + jsonEscape(windowTitle(h)) +
         "\",\"exe\":\"" + jsonEscape(exeName(h)) + "\"}";
  }
  return j + "]}";
}

uint8_t* thumbnail(const std::string& id, int maxW, int maxH, int* outW, int* outH) {
  if (outW) *outW = 0;
  if (outH) *outH = 0;
  if (maxW <= 0 || maxH <= 0) return nullptr;
  return dpiAware([&]() -> uint8_t* {
    HMONITOR mon;
    HWND wnd;
    RECT rc{};
    if (!parseId(id, &mon, &wnd, &rc)) return nullptr;
    if (wnd) {
      if (IsIconic(wnd)) return nullptr;
      if (FAILED(DwmGetWindowAttribute(wnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof rc))) GetWindowRect(wnd, &rc);
    }
    int sw = rc.right - rc.left, sh = rc.bottom - rc.top;
    if (sw <= 0 || sh <= 0) return nullptr;
    double sc = std::min({1.0, static_cast<double>(maxW) / sw, static_cast<double>(maxH) / sh});
    int tw = std::max(1, static_cast<int>(sw * sc + 0.5)), th = std::max(1, static_cast<int>(sh * sc + 0.5));
    HDC screen = GetDC(nullptr);
    HDC src = CreateCompatibleDC(screen), dst = CreateCompatibleDC(screen);
    HBITMAP srcBmp = nullptr;
    int sx = rc.left, sy = rc.top;
    if (wnd) {
      // PrintWindow renders the window even when it is covered by others.
      RECT wr;
      GetWindowRect(wnd, &wr);
      srcBmp = CreateCompatibleBitmap(screen, wr.right - wr.left, wr.bottom - wr.top);
      SelectObject(src, srcBmp);
      PrintWindow(wnd, src, PW_RENDERFULLCONTENT);
      sx = rc.left - wr.left;  // crop the invisible resize borders
      sy = rc.top - wr.top;
    }
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader;
    bi.bmiHeader.biWidth = tw;
    bi.bmiHeader.biHeight = -th;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(dst, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    uint8_t* out = nullptr;
    if (dib && bits) {
      HGDIOBJ old = SelectObject(dst, dib);
      SetStretchBltMode(dst, HALFTONE);
      SetBrushOrgEx(dst, 0, 0, nullptr);
      StretchBlt(dst, 0, 0, tw, th, wnd ? src : screen, sx, sy, sw, sh, SRCCOPY | (wnd ? 0 : CAPTUREBLT));
      GdiFlush();
      out = static_cast<uint8_t*>(malloc(static_cast<size_t>(tw) * th * 4));
      if (out) {
        const uint8_t* p = static_cast<const uint8_t*>(bits);
        for (int i = 0; i < tw * th; i++) {
          out[i * 4] = p[i * 4 + 2];
          out[i * 4 + 1] = p[i * 4 + 1];
          out[i * 4 + 2] = p[i * 4];
          out[i * 4 + 3] = 255;
        }
        if (outW) *outW = tw;
        if (outH) *outH = th;
      }
      SelectObject(dst, old);
    }
    if (dib) DeleteObject(dib);
    if (srcBmp) DeleteObject(srcBmp);
    DeleteDC(src);
    DeleteDC(dst);
    ReleaseDC(nullptr, screen);
    return out;
  });
}

int start(const std::string& id, int maxW, int maxH, int fps, int kbps) {
  HMONITOR mon;
  HWND wnd;
  if (!parseId(id, &mon, &wnd)) return -1;
  stopSession(true);
  auto s = std::make_unique<Session>();
  s->id = id;
  s->maxW = std::max(0, maxW);
  s->maxH = std::max(0, maxH);
  s->fps = std::clamp(fps, 5, 60);
  s->kbps = std::clamp(kbps, 500, 20000);
  Session* p = s.get();
  std::lock_guard<std::mutex> lk(g_mu);
  g_session = std::move(s);
  p->th = std::thread(run, p);
  return 0;
}

void stop() { stopSession(false); }

void keyframe() {
  std::lock_guard<std::mutex> lk(g_mu);
  if (!g_session) return;
  g_session->keyReq = true;
  g_session->cv.notify_all();
}

void setBitrate(int kbps) {
  std::lock_guard<std::mutex> lk(g_mu);
  if (g_session) g_session->newKbps = std::clamp(kbps, 500, 20000);
}

std::string statusJson() {
  std::lock_guard<std::mutex> lk(g_mu);
  if (!g_session || g_session->stopReq) return "{\"active\":false}";
  std::lock_guard<std::mutex> lk2(g_session->mu);
  return statusLocked(g_session.get());
}

void shutdown() { stopSession(true); }

}  // namespace pn::screen
