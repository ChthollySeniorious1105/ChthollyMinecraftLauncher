// Shared helpers: event dispatch, module paths, UTF-8 conversion, DPAPI.
#include <windows.h>
#include <dpapi.h>

#include "common.h"

namespace pn {

extern std::atomic<pn_event_cb> g_cb;

void emit(int32_t type, int32_t a, int32_t b, const void* data, int32_t len) {
  pn_event_cb cb = g_cb.load();
  if (!cb) return;
  // NativeCallable.listener delivers asynchronously, so the payload must
  // outlive this call: the Dart side frees it with pn_free.
  uint8_t* copy = nullptr;
  if (data && len > 0) {
    copy = static_cast<uint8_t*>(malloc(len));
    if (!copy) return;
    memcpy(copy, data, len);
  }
  cb(type, a, b, copy, copy ? len : 0);
}

void log(int level, const std::string& msg) {
  OutputDebugStringA(("[pulse] " + msg + "\n").c_str());
  emit(PN_EV_LOG, level, 0, msg.data(), static_cast<int32_t>(msg.size()));
}

static std::wstring g_dirW;
static std::string g_dir;

void setBaseDir(const char* utf8) {
  if (utf8 && *utf8) {
    g_dirW = widen(utf8);
  } else {
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&setBaseDir), &self);
    wchar_t buf[MAX_PATH * 2];
    DWORD n = GetModuleFileNameW(self, buf, MAX_PATH * 2);
    std::wstring p(buf, n);
    g_dirW = p.substr(0, p.find_last_of(L"\\/") + 1);
  }
  if (!g_dirW.empty() && g_dirW.back() != L'\\' && g_dirW.back() != L'/') g_dirW += L'\\';
  g_dir = narrow(g_dirW);
}

const std::string& moduleDir() { return g_dir; }
const std::wstring& moduleDirW() { return g_dirW; }

std::wstring widen(const std::string& s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

std::string narrow(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  std::string s(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
  return s;
}

std::string jsonEscape(const std::string& s) {
  std::string o;
  o.reserve(s.size() + 8);
  for (unsigned char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default:
        if (c < 0x20) {
          char b[8];
          snprintf(b, sizeof b, "\\u%04x", c);
          o += b;
        } else {
          o += static_cast<char>(c);
        }
    }
  }
  return o;
}

char* dupString(const std::string& s) {
  char* p = static_cast<char*>(malloc(s.size() + 1));
  if (!p) return nullptr;
  memcpy(p, s.c_str(), s.size() + 1);
  return p;
}

}  // namespace pn

using namespace pn;

static uint8_t* dpapi(const uint8_t* data, int32_t len, int32_t* out_len, bool protect) {
  if (out_len) *out_len = 0;
  if (!data || len < 0) return nullptr;
  DATA_BLOB in{static_cast<DWORD>(len), const_cast<BYTE*>(data)}, out{};
  static const char kEntropy[] = "pulse-client-v1";
  DATA_BLOB ent{sizeof kEntropy - 1, (BYTE*)kEntropy};
  BOOL ok = protect ? CryptProtectData(&in, L"Pulse", &ent, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)
                    : CryptUnprotectData(&in, nullptr, &ent, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out);
  if (!ok) return nullptr;
  uint8_t* r = static_cast<uint8_t*>(malloc(out.cbData ? out.cbData : 1));
  if (r) {
    memcpy(r, out.pbData, out.cbData);
    if (out_len) *out_len = static_cast<int32_t>(out.cbData);
  }
  SecureZeroMemory(out.pbData, out.cbData);
  LocalFree(out.pbData);
  return r;
}

PN_API uint8_t* pn_protect(const uint8_t* data, int32_t len, int32_t* out_len) { return dpapi(data, len, out_len, true); }
PN_API uint8_t* pn_unprotect(const uint8_t* data, int32_t len, int32_t* out_len) { return dpapi(data, len, out_len, false); }
PN_API void pn_free(void* p) { free(p); }
PN_API int32_t pn_abi_version(void) { return PN_ABI_VERSION; }
