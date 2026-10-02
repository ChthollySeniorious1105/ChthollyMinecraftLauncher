#include "video_textures.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

typedef void (*FrameCb)(uint32_t id);
typedef void (*SetFrameCbFn)(FrameCb cb);
typedef int32_t (*LockFrameFn)(uint32_t id, const uint8_t** rgba, int32_t* w,
                               int32_t* h);
typedef void (*UnlockFrameFn)(uint32_t id);

struct NativeApi {
  SetFrameCbFn set_frame_cb = nullptr;
  LockFrameFn lock_frame = nullptr;
  UnlockFrameFn unlock_frame = nullptr;
  bool ok() const { return set_frame_cb && lock_frame && unlock_frame; }
};

// Resolves the decoder API from pulse_native.dll (already loaded by Dart;
// otherwise loaded from the executable's directory).
NativeApi ResolveNative() {
  NativeApi api;
  HMODULE dll = GetModuleHandleW(L"pulse_native.dll");
  if (!dll) {
    wchar_t path[MAX_PATH * 2];
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH * 2);
    std::wstring p(path, n);
    p = p.substr(0, p.find_last_of(L"\\/") + 1) + L"pulse_native.dll";
    dll = LoadLibraryW(p.c_str());
  }
  if (!dll) return api;
  api.set_frame_cb = reinterpret_cast<SetFrameCbFn>(
      reinterpret_cast<void*>(GetProcAddress(dll, "pn_video_set_frame_cb")));
  api.lock_frame = reinterpret_cast<LockFrameFn>(
      reinterpret_cast<void*>(GetProcAddress(dll, "pn_video_lock_frame")));
  api.unlock_frame = reinterpret_cast<UnlockFrameFn>(
      reinterpret_cast<void*>(GetProcAddress(dll, "pn_video_unlock_frame")));
  return api;
}

// One Flutter texture showing the newest decoded frame of a stream.
struct VideoTexture {
  uint32_t stream_id = 0;
  int64_t texture_id = -1;
  int refs = 1;
  NativeApi api;
  std::mutex mu;  // guards buffer / pixels (raster thread vs. disposal)
  std::vector<uint8_t> buffer;
  FlutterDesktopPixelBuffer pixels{};
  std::unique_ptr<flutter::TextureVariant> variant;

  // Called on the raster thread: copy the locked frame into our own buffer.
  const FlutterDesktopPixelBuffer* Copy() {
    std::lock_guard<std::mutex> lock(mu);
    const uint8_t* rgba = nullptr;
    int32_t w = 0, h = 0;
    if (api.lock_frame(stream_id, &rgba, &w, &h)) {
      if (rgba && w > 0 && h > 0) {
        size_t size = static_cast<size_t>(w) * static_cast<size_t>(h) * 4;
        buffer.resize(size);
        memcpy(buffer.data(), rgba, size);
        pixels.buffer = buffer.data();
        pixels.width = static_cast<size_t>(w);
        pixels.height = static_cast<size_t>(h);
      }
      api.unlock_frame(stream_id);
    }
    return pixels.buffer ? &pixels : nullptr;
  }
};

class VideoTexturesPlugin : public flutter::Plugin {
 public:
  explicit VideoTexturesPlugin(flutter::PluginRegistrarWindows* registrar)
      : textures_(registrar->texture_registrar()) {
    channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "pulse/video",
            &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      HandleMethodCall(call, std::move(result));
    });
    std::lock_guard<std::mutex> lock(instance_mu_);
    instance_ = this;
  }

  ~VideoTexturesPlugin() override {
    {
      std::lock_guard<std::mutex> lock(instance_mu_);
      instance_ = nullptr;
    }
    if (api_.ok()) api_.set_frame_cb(nullptr);
    for (auto& entry : by_stream_) Unregister(entry.second);
    by_stream_.clear();
  }

 private:
  // Decoder thread: a new frame of `stream_id` is ready.
  static void OnFrame(uint32_t stream_id) {
    std::lock_guard<std::mutex> lock(instance_mu_);
    if (!instance_) return;
    auto it = instance_->by_stream_.find(stream_id);
    if (it != instance_->by_stream_.end()) {
      instance_->textures_->MarkTextureFrameAvailable(it->second->texture_id);
    }
  }

  static bool StreamIdArg(const flutter::EncodableValue* args, uint32_t* id) {
    if (!args) return false;
    if (const auto* v32 = std::get_if<int32_t>(args)) {
      *id = static_cast<uint32_t>(*v32);
      return true;
    }
    if (const auto* v64 = std::get_if<int64_t>(args)) {
      *id = static_cast<uint32_t>(*v64);
      return true;
    }
    return false;
  }

  void Unregister(VideoTexture* tex) {
    // The engine may still be using the texture; delete it once it is gone.
    textures_->UnregisterTexture(tex->texture_id, [tex]() { delete tex; });
  }

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    uint32_t stream_id = 0;
    if (!StreamIdArg(call.arguments(), &stream_id)) {
      result->Error("bad_args", "expected an int stream id");
      return;
    }
    if (call.method_name() == "create") {
      if (!api_.ok()) api_ = ResolveNative();
      if (!api_.ok()) {
        result->Error("unavailable", "pulse_native.dll video API not found");
        return;
      }
      // (Re)install the callback: pn_shutdown/pn_init may have happened.
      api_.set_frame_cb(&VideoTexturesPlugin::OnFrame);
      std::lock_guard<std::mutex> lock(instance_mu_);
      auto it = by_stream_.find(stream_id);
      if (it != by_stream_.end()) {
        it->second->refs++;
        result->Success(flutter::EncodableValue(it->second->texture_id));
        return;
      }
      auto* tex = new VideoTexture();
      tex->stream_id = stream_id;
      tex->api = api_;
      tex->variant = std::make_unique<flutter::TextureVariant>(
          flutter::PixelBufferTexture([tex](size_t, size_t) {
            return tex->Copy();
          }));
      tex->texture_id = textures_->RegisterTexture(tex->variant.get());
      if (tex->texture_id < 0) {
        delete tex;
        result->Error("register_failed", "RegisterTexture failed");
        return;
      }
      by_stream_[stream_id] = tex;
      textures_->MarkTextureFrameAvailable(tex->texture_id);
      result->Success(flutter::EncodableValue(tex->texture_id));
    } else if (call.method_name() == "dispose") {
      std::lock_guard<std::mutex> lock(instance_mu_);
      auto it = by_stream_.find(stream_id);
      if (it != by_stream_.end() && --it->second->refs <= 0) {
        Unregister(it->second);
        by_stream_.erase(it);
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  }

  flutter::TextureRegistrar* textures_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NativeApi api_;
  std::map<uint32_t, VideoTexture*> by_stream_;  // guarded by instance_mu_

  static std::mutex instance_mu_;
  static VideoTexturesPlugin* instance_;
};

std::mutex VideoTexturesPlugin::instance_mu_;
VideoTexturesPlugin* VideoTexturesPlugin::instance_ = nullptr;

}  // namespace

void RegisterVideoTextures(flutter::FlutterEngine* engine) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
                        ->GetRegistrar<flutter::PluginRegistrarWindows>(
                            engine->GetRegistrarForPlugin("PulseVideo"));
  registrar->AddPlugin(std::make_unique<VideoTexturesPlugin>(registrar));
}
