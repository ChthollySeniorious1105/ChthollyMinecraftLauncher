// Remembers the main window position / size / maximized state between runs
// (HKCU\Software\Pulse\WindowPlacement). Restored placements are clamped to the
// current monitors so the window never opens off-screen after a monitor change.
#pragma once
#include <windows.h>

inline constexpr wchar_t kPlacementKey[] = L"Software\\Pulse";
inline constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

inline void SaveWindowPlacement(HWND hwnd) {
  WINDOWPLACEMENT wp{sizeof wp};
  if (!::GetWindowPlacement(hwnd, &wp)) return;
  HKEY key;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kPlacementKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
  ::RegSetValueExW(key, kPlacementValue, 0, REG_BINARY, reinterpret_cast<const BYTE*>(&wp), sizeof wp);
  ::RegCloseKey(key);
}

inline void RestoreWindowPlacement(HWND hwnd) {
  WINDOWPLACEMENT wp{};
  DWORD size = sizeof wp, type = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue, RRF_RT_REG_BINARY, &type, &wp, &size) != ERROR_SUCCESS ||
      size != sizeof wp || wp.length != sizeof wp) {
    return;
  }
  RECT& r = wp.rcNormalPosition;
  if (r.right - r.left < 640 || r.bottom - r.top < 400) return;
  // keep at least the title bar on a visible monitor
  RECT probe{r.left + 40, r.top, r.right - 40, r.top + 40};
  if (!::MonitorFromRect(&probe, MONITOR_DEFAULTTONULL)) return;
  const bool maximized = wp.showCmd == SW_SHOWMAXIMIZED;
  // the window is still hidden until Flutter renders its first frame: apply the rectangle
  // without showing it; Win32Window::Show() reads the property and maximizes then
  wp.showCmd = SW_HIDE;
  ::SetWindowPlacement(hwnd, &wp);
  if (maximized) ::SetPropW(hwnd, L"PulseMaximize", reinterpret_cast<HANDLE>(1));
}
