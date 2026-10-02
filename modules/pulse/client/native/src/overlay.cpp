#include <windows.h>
#include <windowsx.h>
#include <objidl.h>
#include <shlwapi.h>

#include <algorithm>
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

#include <map>
#include <memory>
#include <thread>

#include "overlay.h"

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "shlwapi.lib")

namespace pn::overlay {
namespace {

using namespace Gdiplus;

constexpr UINT kMsgAvatar = WM_APP + 1;  // decode queued avatars
constexpr UINT kMsgRedraw = WM_APP + 2;
constexpr UINT_PTR kTimerFrame = 1, kTimerTopmost = 2;
constexpr wchar_t kClass[] = L"PulseSpeakerOverlay";
constexpr wchar_t kRegKey[] = L"Software\\Pulse\\Overlay";

struct User {
  uint32_t id;
  std::wstring name;
  uint32_t argb;
  int flags;
};

struct State {
  std::mutex mu;  // guards everything below that is written from other threads
  std::thread th;
  DWORD tid = 0;
  HWND hwnd = nullptr;
  bool want = false;
  int mode = kModeAll;
  float opacity = 0.85f, scale = 1.f;
  bool locked = false, hideFocused = false;
  std::wstring title, pendingTitle;
  uint32_t me = 0, pendingMe = 0;
  std::vector<User> users, pending;
  std::map<uint32_t, std::vector<uint8_t>> avatarQueue;  // raw bytes waiting for decode (empty = clear)

  // overlay thread only
  ULONG_PTR gdip = 0;
  std::map<uint32_t, std::unique_ptr<Bitmap>> avatars;
  std::map<uint32_t, DWORD> lastSpoke;
  RECT closeRect{};
  std::string lastFrame;
  bool shown = false;
} S;

std::wstring wide(const std::string& s) { return widen(s); }

bool appIsForeground() {
  HWND fg = GetForegroundWindow();
  if (!fg || fg == S.hwnd) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(fg, &pid);
  return pid == GetCurrentProcessId();
}

void savePosition() {
  RECT r;
  if (!S.hwnd || !GetWindowRect(S.hwnd, &r)) return;
  HKEY k;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) != ERROR_SUCCESS) return;
  DWORD x = static_cast<DWORD>(r.left), y = static_cast<DWORD>(r.top);
  RegSetValueExW(k, L"X", 0, REG_DWORD, reinterpret_cast<BYTE*>(&x), 4);
  RegSetValueExW(k, L"Y", 0, REG_DWORD, reinterpret_cast<BYTE*>(&y), 4);
  RegCloseKey(k);
}

POINT defaultPosition() {
  RECT wa{0, 0, 1280, 720};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
  return {wa.left + 24, wa.top + 160};
}

POINT loadPosition() {
  DWORD x = 0, y = 0, sz = 4;
  bool ok = RegGetValueW(HKEY_CURRENT_USER, kRegKey, L"X", RRF_RT_REG_DWORD, nullptr, &x, &sz) == ERROR_SUCCESS;
  sz = 4;
  ok = ok && RegGetValueW(HKEY_CURRENT_USER, kRegKey, L"Y", RRF_RT_REG_DWORD, nullptr, &y, &sz) == ERROR_SUCCESS;
  POINT p{static_cast<LONG>(static_cast<int32_t>(x)), static_cast<LONG>(static_cast<int32_t>(y))};
  // the saved spot must still be on a monitor (monitors change)
  if (!ok || !MonitorFromPoint({p.x + 20, p.y + 10}, MONITOR_DEFAULTTONULL)) return defaultPosition();
  return p;
}

void decodeAvatars() {
  std::map<uint32_t, std::vector<uint8_t>> q;
  {
    std::lock_guard<std::mutex> lk(S.mu);
    q.swap(S.avatarQueue);
  }
  for (auto& [id, bytes] : q) {
    if (bytes.empty()) {
      S.avatars.erase(id);
      continue;
    }
    IStream* st = SHCreateMemStream(bytes.data(), static_cast<UINT>(bytes.size()));
    if (!st) continue;
    {
      Bitmap src(st);
      if (src.GetLastStatus() == Ok && src.GetWidth() > 0) {
        // pre-scale once to a small square; the stream can then be released
        auto dst = std::make_unique<Bitmap>(64, 64, PixelFormat32bppPARGB);
        Graphics g(dst.get());
        g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
        g.DrawImage(&src, 0, 0, 64, 64);
        S.avatars[id] = std::move(dst);
      }
    }
    st->Release();
  }
  S.lastFrame.clear();
}

void roundRect(GraphicsPath& p, REAL x, REAL y, REAL w, REAL h, REAL r) {
  p.AddArc(x, y, r * 2, r * 2, 180, 90);
  p.AddArc(x + w - r * 2, y, r * 2, r * 2, 270, 90);
  p.AddArc(x + w - r * 2, y + h - r * 2, r * 2, r * 2, 0, 90);
  p.AddArc(x, y + h - r * 2, r * 2, r * 2, 90, 90);
  p.CloseFigure();
}

struct Row {
  const User* u;
  bool speaking;
  float alpha;  // fade-out in "speaking only" mode
};

void render() {
  if (!S.hwnd) return;
  std::vector<User> users;
  std::wstring title;
  uint32_t me;
  int mode;
  float opacity, scale;
  bool want, locked, hideFocused;
  {
    std::lock_guard<std::mutex> lk(S.mu);
    users = S.users;
    title = S.title;
    me = S.me;
    mode = S.mode;
    opacity = S.opacity;
    scale = S.scale;
    want = S.want;
    locked = S.locked;
    hideFocused = S.hideFocused;
  }
  const bool visible = want && !(hideFocused && appIsForeground());
  if (!visible) {
    if (S.shown) {
      ShowWindow(S.hwnd, SW_HIDE);
      S.shown = false;
    }
    S.lastFrame.clear();
    return;
  }

  const DWORD now = GetTickCount();
  std::vector<Row> rows;
  bool anyone = false;
  for (auto& u : users) {
    const bool silenced = (u.flags & (kFlagMute | kFlagServerMute)) != 0;
    const bool speaking = !silenced && userSpeakingLevel(u.id, u.id == me) > 0.015f;
    if (speaking) S.lastSpoke[u.id] = now;
    anyone = anyone || speaking;
    float alpha = 1.f;
    if (mode == kModeSpeaking && !speaking) {
      auto it = S.lastSpoke.find(u.id);
      const DWORD since = it == S.lastSpoke.end() ? 100000 : now - it->second;
      if (since > 1500) continue;
      alpha = since < 900 ? 1.f : 1.f - (since - 900) / 600.f;  // linger, then fade
    }
    rows.push_back({&u, speaking, alpha});
  }

  POINT cur;
  RECT wr{};
  GetCursorPos(&cur);
  GetWindowRect(S.hwnd, &wr);
  const bool hover = S.shown && PtInRect(&wr, cur);

  const float dpi = GetDpiForWindow(S.hwnd) / 96.f;
  const float sc = dpi * clampf(scale, 0.6f, 2.f);
  const int W = static_cast<int>(210 * sc), headerH = static_cast<int>(26 * sc), rowH = static_cast<int>(28 * sc);
  const int pad = static_cast<int>(6 * sc);
  const int H = headerH + static_cast<int>(rows.size()) * rowH + (rows.empty() ? 0 : pad);

  // skip identical frames (the timer runs at 20 fps)
  std::string key = std::to_string(W) + "|" + std::to_string(H) + "|" + std::to_string(hover) + "|" + std::to_string(locked) +
                    "|" + std::to_string(static_cast<int>(opacity * 100)) + "|" + narrow(title) + "|" + std::to_string(anyone);
  for (auto& r : rows) {
    key += "|" + std::to_string(r.u->id) + ":" + std::to_string(r.speaking) + ":" + std::to_string(static_cast<int>(r.alpha * 20)) + ":" +
           std::to_string(r.u->flags) + ":" + std::to_string(S.avatars.count(r.u->id));
  }
  if (key == S.lastFrame && S.shown) return;
  S.lastFrame = key;

  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = W;
  bi.bmiHeader.biHeight = -H;  // top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib) {
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return;
  }
  HGDIOBJ old = SelectObject(mem, dib);
  {
    Bitmap canvas(W, H, W * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(bits));
    Graphics g(&canvas);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);  // ClearType breaks per-pixel alpha
    g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    g.Clear(Color(0, 0, 0, 0));

    const BYTE bgA = static_cast<BYTE>(clampf(opacity, 0.2f, 1.f) * 255);
    {
      GraphicsPath bg;
      roundRect(bg, 0.5f, 0.5f, W - 1.f, H - 1.f, 8 * sc);
      SolidBrush fill(Color(bgA, 22, 24, 28));
      g.FillPath(&fill, &bg);
      Pen edge(Color(static_cast<BYTE>(bgA / 2), 255, 255, 255), 1.f);
      g.DrawPath(&edge, &bg);
    }
    FontFamily family(L"Microsoft YaHei UI");
    Font titleFont(&family, 11.f * sc, FontStyleBold, UnitPixel);
    Font nameFont(&family, 12.5f * sc, FontStyleRegular, UnitPixel);
    Font nameBold(&family, 12.5f * sc, FontStyleBold, UnitPixel);
    Font badgeFont(&family, 10.f * sc, FontStyleBold, UnitPixel);
    StringFormat ellipsis;
    ellipsis.SetTrimming(StringTrimmingEllipsisCharacter);
    ellipsis.SetFormatFlags(StringFormatFlagsNoWrap);
    ellipsis.SetLineAlignment(StringAlignmentCenter);

    // header: activity dot, channel name, close button
    const REAL dot = 7 * sc;
    SolidBrush dotBrush(anyone ? Color(255, 35, 165, 90) : Color(200, 128, 132, 142));
    g.FillEllipse(&dotBrush, pad + 2 * sc, (headerH - dot) / 2, dot, dot);
    const REAL closeW = locked ? 0.f : static_cast<REAL>(headerH);
    SolidBrush titleBrush(Color(215, 230, 232, 236));
    RectF tr(pad + dot + 8 * sc, 0, W - (pad + dot + 8 * sc) - closeW - 2 * sc, static_cast<REAL>(headerH));
    g.DrawString(title.c_str(), -1, &titleFont, tr, &ellipsis, &titleBrush);
    if (!locked) {
      S.closeRect = {W - headerH, 0, W, headerH};
      POINT local{cur.x - wr.left, cur.y - wr.top};
      const bool overClose = hover && PtInRect(&S.closeRect, local);
      if (overClose) {
        SolidBrush hl(Color(200, 218, 55, 60));
        GraphicsPath hp;
        roundRect(hp, W - headerH + 3 * sc, 3 * sc, headerH - 6 * sc, headerH - 6 * sc, 4 * sc);
        g.FillPath(&hl, &hp);
      }
      Pen x(overClose ? Color(255, 255, 255, 255) : Color(hover ? 220 : 150, 200, 204, 210), 1.6f * sc);
      const REAL c = W - headerH / 2.f, cy = headerH / 2.f, k = 4.f * sc;
      g.DrawLine(&x, c - k, cy - k, c + k, cy + k);
      g.DrawLine(&x, c - k, cy + k, c + k, cy - k);
    } else {
      S.closeRect = {};
    }

    // rows
    for (size_t i = 0; i < rows.size(); i++) {
      const Row& r = rows[i];
      const User& u = *r.u;
      const BYTE a = static_cast<BYTE>(255 * r.alpha);
      const REAL y = static_cast<REAL>(headerH + static_cast<int>(i) * rowH);
      const REAL av = 20 * sc, ax = pad + 3 * sc, ay = y + (rowH - av) / 2;
      if (r.speaking) {
        Pen ring(Color(a, 35, 165, 90), 2.2f * sc);
        g.DrawEllipse(&ring, ax - 2 * sc, ay - 2 * sc, av + 4 * sc, av + 4 * sc);
      }
      auto it = S.avatars.find(u.id);
      if (it != S.avatars.end()) {
        GraphicsPath clip;
        clip.AddEllipse(ax, ay, av, av);
        g.SetClip(&clip);
        ImageAttributes ia;
        ColorMatrix cm = {{{1, 0, 0, 0, 0}, {0, 1, 0, 0, 0}, {0, 0, 1, 0, 0}, {0, 0, 0, r.alpha, 0}, {0, 0, 0, 0, 1}}};
        ia.SetColorMatrix(&cm);
        g.DrawImage(it->second.get(), RectF(ax, ay, av, av), 0, 0, 64, 64, UnitPixel, &ia);
        g.ResetClip();
      } else {
        SolidBrush circle(Color(a, (u.argb >> 16) & 0xFF, (u.argb >> 8) & 0xFF, u.argb & 0xFF));
        g.FillEllipse(&circle, ax, ay, av, av);
        std::wstring initial = u.name.empty() ? L"?" : u.name.substr(0, IS_HIGH_SURROGATE(u.name[0]) && u.name.size() > 1 ? 2 : 1);
        CharUpperBuffW(initial.data(), static_cast<DWORD>(initial.size()));
        StringFormat center;
        center.SetAlignment(StringAlignmentCenter);
        center.SetLineAlignment(StringAlignmentCenter);
        Font initFont(&family, 10.5f * sc, FontStyleBold, UnitPixel);
        SolidBrush white(Color(a, 255, 255, 255));
        g.DrawString(initial.c_str(), -1, &initFont, RectF(ax, ay + 0.5f * sc, av, av), &center, &white);
      }
      // badges on the right
      std::wstring badge;
      if (u.flags & kFlagServerMute) {
        badge = L"禁言";
      } else if (u.flags & kFlagDeaf) {
        badge = L"闭麦";
      } else if (u.flags & kFlagMute) {
        badge = L"静音";
      }
      REAL right = W - pad - 2 * sc;
      if (!badge.empty()) {
        RectF bb;
        g.MeasureString(badge.c_str(), -1, &badgeFont, PointF(0, 0), &bb);
        const REAL bw = bb.Width + 6 * sc, bh = 15 * sc;
        GraphicsPath bp;
        roundRect(bp, right - bw, y + (rowH - bh) / 2, bw, bh, 3 * sc);
        SolidBrush bf(Color(static_cast<BYTE>(a * 0.85f), 218, 55, 60));
        g.FillPath(&bf, &bp);
        StringFormat center;
        center.SetAlignment(StringAlignmentCenter);
        center.SetLineAlignment(StringAlignmentCenter);
        SolidBrush bt(Color(a, 255, 255, 255));
        g.DrawString(badge.c_str(), -1, &badgeFont, RectF(right - bw, y + (rowH - bh) / 2, bw, bh), &center, &bt);
        right -= bw + 4 * sc;
      }
      const REAL nx = ax + av + 8 * sc;
      SolidBrush nb(r.speaking ? Color(a, 255, 255, 255) : Color(static_cast<BYTE>(a * 0.7f), 220, 222, 226));
      g.DrawString(u.name.c_str(), -1, r.speaking ? &nameBold : &nameFont, RectF(nx, y, right - nx, static_cast<REAL>(rowH)), &ellipsis, &nb);
    }
  }

  POINT src{0, 0};
  POINT pos{wr.left, wr.top};
  SIZE size{W, H};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(S.hwnd, screen, &pos, &size, mem, &src, 0, &blend, ULW_ALPHA);
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  if (!S.shown) {
    SetWindowPos(S.hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    S.shown = true;
  }
}

void applyLocked(bool locked) {
  if (!S.hwnd) return;
  LONG_PTR ex = GetWindowLongPtrW(S.hwnd, GWL_EXSTYLE);
  const LONG_PTR want = locked ? (ex | WS_EX_TRANSPARENT) : (ex & ~WS_EX_TRANSPARENT);
  if (want != ex) SetWindowLongPtrW(S.hwnd, GWL_EXSTYLE, want);
}

LRESULT CALLBACK wndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  switch (m) {
    case WM_NCHITTEST: {
      POINT p{GET_X_LPARAM(l), GET_Y_LPARAM(l)};
      ScreenToClient(h, &p);
      if (PtInRect(&S.closeRect, p)) return HTCLIENT;
      return HTCAPTION;  // drag anywhere
    }
    case WM_LBUTTONUP: {
      POINT p{GET_X_LPARAM(l), GET_Y_LPARAM(l)};
      if (PtInRect(&S.closeRect, p)) {
        {
          std::lock_guard<std::mutex> lk(S.mu);
          S.want = false;
        }
        render();
        emit(PN_EV_OVERLAY, 0, 0);  // closed by the user
      }
      return 0;
    }
    case WM_NCLBUTTONDBLCLK:  // no maximize
    case WM_NCRBUTTONDOWN:    // no system menu
    case WM_NCRBUTTONUP:
    case WM_CONTEXTMENU:
      return 0;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_EXITSIZEMOVE:
      savePosition();
      return 0;
    case WM_TIMER:
      if (w == kTimerTopmost) {
        // games / other topmost windows can push us down; re-assert quietly
        if (S.shown) SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      } else {
        render();
      }
      return 0;
    case kMsgAvatar:
      decodeAvatars();
      render();
      return 0;
    case kMsgRedraw:
      S.lastFrame.clear();
      {
        bool locked;
        {
          std::lock_guard<std::mutex> lk(S.mu);
          locked = S.locked;
        }
        applyLocked(locked);
      }
      render();
      return 0;
    case WM_DPICHANGED:
      S.lastFrame.clear();
      render();
      return 0;
  }
  return DefWindowProcW(h, m, w, l);
}

void threadMain() {
  GdiplusStartupInput in;
  GdiplusStartup(&S.gdip, &in, nullptr);
  WNDCLASSEXW wc{sizeof wc};
  wc.lpfnWndProc = wndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClass;
  wc.hCursor = LoadCursorW(nullptr, IDC_SIZEALL);
  RegisterClassExW(&wc);
  const POINT p = loadPosition();
  HWND h = CreateWindowExW(WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kClass, L"Pulse 正在说话", WS_POPUP,
                           p.x, p.y, 10, 10, nullptr, nullptr, wc.hInstance, nullptr);
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.hwnd = h;
    applyLocked(S.locked);
  }
  SetTimer(h, kTimerFrame, 50, nullptr);
  SetTimer(h, kTimerTopmost, 2000, nullptr);
  decodeAvatars();
  render();
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  savePosition();
  DestroyWindow(h);
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.hwnd = nullptr;
  }
  S.avatars.clear();
  S.shown = false;
  UnregisterClassW(kClass, wc.hInstance);
  GdiplusShutdown(S.gdip);
}

void post(UINT m) {
  HWND h;
  {
    std::lock_guard<std::mutex> lk(S.mu);
    h = S.hwnd;
  }
  if (h) PostMessageW(h, m, 0, 0);
}

}  // namespace

void show(bool on) {
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.want = on;
  }
  if (on && !S.th.joinable()) {
    S.th = std::thread([] {
      S.tid = GetCurrentThreadId();
      threadMain();
    });
  }
  post(kMsgRedraw);
}

void config(int mode, float opacity, float scale, bool locked, bool hideWhenAppFocused) {
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.mode = mode;
    S.opacity = opacity;
    S.scale = scale;
    S.locked = locked;
    S.hideFocused = hideWhenAppFocused;
  }
  post(kMsgRedraw);
}

void rosterBegin(const std::string& title, uint32_t me) {
  std::lock_guard<std::mutex> lk(S.mu);
  S.pending.clear();
  S.pendingTitle = wide(title);
  S.pendingMe = me;
}

void rosterAdd(uint32_t id, const std::string& name, uint32_t argb, int flags) {
  std::lock_guard<std::mutex> lk(S.mu);
  if (S.pending.size() < 99) S.pending.push_back({id, wide(name), argb, flags});
}

void rosterCommit() {
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.users = S.pending;
    S.title = S.pendingTitle;
    S.me = S.pendingMe;
  }
  post(kMsgRedraw);
}

void setAvatar(uint32_t id, const uint8_t* data, int len) {
  {
    std::lock_guard<std::mutex> lk(S.mu);
    S.avatarQueue[id] = data && len > 0 ? std::vector<uint8_t>(data, data + len) : std::vector<uint8_t>{};
  }
  post(kMsgAvatar);
}

void resetPosition() {
  HWND h;
  {
    std::lock_guard<std::mutex> lk(S.mu);
    h = S.hwnd;
  }
  RegDeleteKeyW(HKEY_CURRENT_USER, kRegKey);
  if (h) {
    const POINT p = defaultPosition();
    SetWindowPos(h, HWND_TOPMOST, p.x, p.y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
    post(kMsgRedraw);
  }
}

void shutdown() {
  if (!S.th.joinable()) return;
  while (!S.tid) Sleep(1);
  PostThreadMessageW(S.tid, WM_QUIT, 0, 0);
  S.th.join();
  S.tid = 0;
}

}  // namespace pn::overlay
