#include "opus_dyn.h"

#include <windows.h>

namespace pn {

OpusLib& opus() {
  static OpusLib lib;
  return lib;
}

template <typename T>
static bool bind(HMODULE h, const char* name, T& out) {
  out = reinterpret_cast<T>(GetProcAddress(h, name));
  return out != nullptr;
}

bool loadOpus(const std::wstring& dir) {
  auto& o = opus();
  if (o.ok) return true;
  HMODULE h = LoadLibraryExW((dir + L"opus.dll").c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!h) h = LoadLibraryW(L"opus.dll");
  if (!h) {
    o.error = "opus.dll not found";
    return false;
  }
  bool ok = bind(h, "opus_encoder_create", o.encoder_create) && bind(h, "opus_encode_float", o.encode_float) &&
            bind(h, "opus_encoder_ctl", o.encoder_ctl) && bind(h, "opus_encoder_destroy", o.encoder_destroy) &&
            bind(h, "opus_decoder_create", o.decoder_create) && bind(h, "opus_decode_float", o.decode_float) &&
            bind(h, "opus_decoder_destroy", o.decoder_destroy) && bind(h, "opus_get_version_string", o.get_version_string);
  if (!ok) {
    o.error = "opus.dll is missing required exports";
    return false;
  }
  o.ok = true;
  return true;
}

}  // namespace pn
