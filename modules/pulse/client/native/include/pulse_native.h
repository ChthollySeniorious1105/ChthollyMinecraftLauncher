// Pulse native audio engine — C ABI consumed by the Flutter client via dart:ffi.
//
// Everything audio-related that needs low latency or native APIs lives here:
//   * device enumeration / capture / playback (miniaudio, WASAPI)
//   * capture chain: gain -> RNNoise -> voice changer -> VAD / push-to-talk gate -> Opus
//   * playback: per-speaker jitter buffer -> Opus decode (+PLC) -> per-user volume -> mix
//   * global hotkeys (low-level keyboard / mouse hooks, work while the app is unfocused)
//   * GPU voice changer (ONNX Runtime + DirectML / CUDA / plugin execution providers)
//   * DPAPI helpers to keep login tokens encrypted at rest
//   * screen sharing: Windows Graphics Capture -> H.264 (Media Foundation) and decoding of
//     remote streams into RGBA frames for the Flutter texture plugin in pulse.exe
//
// Threading: all pn_* functions may be called from the Dart main isolate.
// Asynchronous results are delivered through the event callback registered with
// pn_init (from arbitrary native threads; Dart uses NativeCallable.listener).
// Event `data` is only valid during the callback for synchronous callers; for
// NativeCallable.listener it is heap memory that the receiver frees with pn_free.
//
// Bump PN_ABI_VERSION whenever a signature below changes (Dart checks it).
#pragma once
#include <stdint.h>

#ifdef _WIN32
#define PN_API extern "C" __declspec(dllexport)
#else
#define PN_API extern "C"
#endif

#define PN_ABI_VERSION 4

// ---- events (pn_event_cb type) ----
enum {
  PN_EV_PACKET = 1,           // data = [u16 seq BE][opus bytes]; send to server as a voice frame
  PN_EV_SPEAKING = 2,         // a = 1 transmitting / 0 stopped
  PN_EV_HOTKEY = 3,           // a = slot, b = 1 down / 0 up
  PN_EV_HOTKEY_CAPTURED = 4,  // a = vk code, b = modifier mask (PN_MOD_*); a = 0 cancelled
  PN_EV_VC_STATUS = 5,        // a = PN_VC_STATE_*, data = UTF-8 JSON (see pn_vc_status)
  PN_EV_LOG = 6,              // a = level (0 info, 1 warn, 2 error), data = UTF-8 text
  PN_EV_DEVICE = 7,           // a = 0 capture / 1 playback, b = 1 started / 0 stopped / -1 failed; data = message
  PN_EV_MUTED_TALK = 8,       // voice detected while self-muted (at most every 3 s)
  PN_EV_OVERLAY = 9,          // speaker overlay closed with its × button (a = 0)
  PN_EV_VIDEO_PACKET = 10,    // screen share encoder output: a = flags (1 = keyframe), data = one H.264 Annex-B access unit (with SPS/PPS before every IDR)
  PN_EV_SCREEN = 11,          // screen share state: a = 1 started / 0 stopped / -1 failed; data = UTF-8 (JSON status when started, error text when failed, reason when stopped e.g. "窗口已关闭")
  PN_EV_VIDEO_SIZE = 12,      // decoder: a = stream id, b = (width << 16) | height of decoded frames (sent on first frame and on change)
};

enum { PN_MOD_CTRL = 1, PN_MOD_SHIFT = 2, PN_MOD_ALT = 4, PN_MOD_WIN = 8 };

// hotkey slots
enum { PN_HK_PTT = 0, PN_HK_MUTE = 1, PN_HK_DEAFEN = 2, PN_HK_VC = 3, PN_HK_OVERLAY = 4, PN_HK_COUNT = 5 };

// input (transmit) modes
enum { PN_MODE_VAD = 0, PN_MODE_PTT = 1, PN_MODE_OPEN = 2 };

// voice changer modes
enum { PN_VC_OFF = 0, PN_VC_DSP = 1, PN_VC_AI = 2 };

enum { PN_VC_STATE_OFF = 0, PN_VC_STATE_LOADING = 1, PN_VC_STATE_RUNNING = 2, PN_VC_STATE_ERROR = 3 };

// UI sounds for pn_play_sound
enum {
  PN_SND_JOIN = 0, PN_SND_LEAVE = 1, PN_SND_MUTE = 2, PN_SND_UNMUTE = 3, PN_SND_MESSAGE = 4,
  PN_SND_DEAFEN = 5, PN_SND_UNDEAFEN = 6, PN_SND_TEST = 7, PN_SND_MENTION = 8,
};

typedef void (*pn_event_cb)(int32_t type, int32_t a, int32_t b, uint8_t* data, int32_t len);

// Lifecycle. `base_dir` = folder containing opus.dll and the ai\ folder (UTF-8);
// NULL = folder of pulse_native.dll.
PN_API int32_t pn_abi_version(void);
PN_API int32_t pn_init(pn_event_cb cb, const char* base_dir);
PN_API void pn_shutdown(void);
PN_API void pn_free(void* p);

// Devices. Returns malloc'd UTF-8 JSON: [{"id": "...", "name": "...", "default": true}]
// kind 0 = capture (microphones), 1 = playback (speakers / headsets). Free with pn_free.
PN_API char* pn_list_devices(int32_t kind);
// Select a device by id from pn_list_devices ("" or NULL = follow system default).
// Restarts the stream if it is running. Returns 0 on success.
PN_API int32_t pn_set_device(int32_t kind, const char* id);

// Capture control
PN_API int32_t pn_capture_start(void);
PN_API void pn_capture_stop(void);
PN_API void pn_set_transmit(int32_t on);        // connected to a voice channel (packets are emitted)
PN_API void pn_set_mute(int32_t muted);         // self mute (nothing transmitted)
PN_API void pn_set_input_mode(int32_t mode);    // PN_MODE_*
PN_API void pn_set_ptt(int32_t held);           // software PTT (in-app button), OR'ed with hotkey
PN_API void pn_set_input_gain(float gain);      // linear, 0..4
PN_API void pn_set_vad_threshold(float t);      // 0..1 sensitivity threshold
PN_API void pn_set_noise_suppression(int32_t level);  // 0 off, 1 light, 2 standard, 3 strong
PN_API void pn_set_bitrate(int32_t bps);        // Opus bitrate, 8000..128000
PN_API void pn_set_monitor(int32_t on);         // hear your own processed voice (mic test)
PN_API void pn_set_ptt_release_ms(int32_t ms);  // keep transmitting this long after PTT release

// Playback control
PN_API int32_t pn_playback_start(void);
PN_API void pn_playback_stop(void);
PN_API void pn_set_output_volume(float v);      // linear 0..2
PN_API void pn_set_deafen(int32_t on);
PN_API void pn_set_user_volume(uint32_t user, float v);  // 0..2 (0 = locally muted)
PN_API void pn_play_push(uint32_t user, const uint8_t* data, int32_t len);  // [u16 seq][opus]
PN_API void pn_play_remove(uint32_t user);
PN_API void pn_play_clear(void);
PN_API void pn_play_sound(int32_t kind);        // PN_SND_*
PN_API void pn_set_sound_volume(float v);       // UI sounds 0..1

// Meters: [0] mic level (post gain, 0..1), [1] transmitted level, [2] voice probability,
// [3] output level, [4] 1 if gate open. Returns number written.
PN_API int32_t pn_get_levels(float* levels, int32_t n);
// Per-user output levels for speaking rings: writes up to n (user, level) pairs.
PN_API int32_t pn_get_user_levels(uint32_t* users, float* levels, int32_t n);

// Global hotkeys (system-wide). vk = Windows virtual-key code (mouse: 4 middle, 5 X1, 6 X2).
PN_API int32_t pn_hotkeys_enable(int32_t on);
PN_API void pn_hotkey_set(int32_t slot, int32_t vk, int32_t mods);  // vk 0 = unbound
PN_API void pn_hotkey_capture(int32_t on);  // next key press is reported via PN_EV_HOTKEY_CAPTURED
PN_API char* pn_key_name(int32_t vk);       // localized key label, free with pn_free

// GPU / inference providers. Returns JSON (free with pn_free):
// {"ort":"1.24.4","ortError":"","adapters":[{"index":0,"name":"...","vendor":"NVIDIA",
//   "vendorId":4318,"deviceId":..,"vramMB":..,"driver":"32.0.16.1692","software":false}],
//  "providers":[{"id":"dml:0","label":"...","kind":"gpu","vendor":"NVIDIA"}, {"id":"cpu",...}]}
PN_API char* pn_gpu_info(void);

// Flash the taskbar button until the user focuses Pulse (no-op if already focused).
PN_API void pn_flash_window(void);

// ---- "who is speaking" overlay: small topmost, draggable, closable layered window.
// Speaking highlights come straight from the audio engine; the roster comes from Dart.
enum { PN_OVL_ALL = 0, PN_OVL_SPEAKING_ONLY = 1 };
enum { PN_OVL_MUTE = 1, PN_OVL_DEAF = 2, PN_OVL_SERVER_MUTE = 4 };
PN_API void pn_overlay_show(int32_t on);
// mode PN_OVL_*, opacity 0.2..1 (background), scale 0.6..2, locked = click-through (no drag / close),
// hide_when_focused = hide while a Pulse window is in the foreground.
PN_API void pn_overlay_config(int32_t mode, float opacity, float scale, int32_t locked, int32_t hide_when_focused);
PN_API void pn_overlay_roster_begin(const char* title, uint32_t me);              // UTF-8
PN_API void pn_overlay_roster_add(uint32_t id, const char* name, uint32_t argb, int32_t flags);
PN_API void pn_overlay_roster_commit(void);
PN_API void pn_overlay_avatar(uint32_t id, const uint8_t* data, int32_t len);   // PNG/JPEG/WebP bytes, len 0 = clear
PN_API void pn_overlay_reset_position(void);

// Voice changer.
PN_API void pn_vc_set_mode(int32_t mode);           // PN_VC_*
PN_API void pn_vc_set_pitch(float semitones);       // -24..24 (DSP and AI)
PN_API void pn_vc_set_robot(int32_t on);            // DSP only
// AI: configure and (re)load asynchronously; progress via PN_EV_VC_STATUS.
// provider = id from pn_gpu_info ("dml:0", "cuda:0", "ep:<name>:<n>", "cpu").
// model = path of an RVC v2 ONNX voice (768-dim features, with f0); "" = built-in base model.
// block_ms = 100..500, extra_ms = context 0..1000, speaker = sid.
// Requests are debounced/coalesced; while a pipeline is running the new one is built in the
// background and swapped in without an audio gap (status "switching": true meanwhile).
PN_API int32_t pn_vc_ai_config(const char* provider, const char* model, int32_t block_ms,
                               int32_t extra_ms, int32_t speaker);
// Latency presets to pre-compile in the background (count pairs of {block_ms, extra_ms}),
// making later pn_vc_ai_config calls with those values instant. Ignored on GPUs < 6 GB.
PN_API void pn_vc_ai_prewarm(const int32_t* pairs, int32_t count);
PN_API void pn_vc_set_speaker(int32_t sid);
PN_API void pn_vc_ai_unload(void);
// {"state":2,"provider":"dml:0","providerLabel":"...","model":"...","sampleRate":40000,
//  "speakers":109,"latencyMs":..,"inferMs":..,"underruns":..,"error":""}
PN_API char* pn_vc_status(void);

// ---- screen sharing (capture + H.264 encode). Uses the GPU (D3D11 video processor for
// scaling / colour conversion, hardware H.264 encoder MFT) with software fallbacks.
// Screen capture sources: {"monitors":[{"id":"m:0","name":"显示器 1","w":2560,"h":1440,"primary":true}],
//  "windows":[{"id":"w:<hwnd decimal>","title":"...","exe":"chrome.exe"}]}  (only visible, non-tool, titled, non-cloaked top-level windows; skip Pulse's own windows)
PN_API char* pn_screen_sources(void);
// Small RGBA8888 thumbnail (aspect preserved, fits max_w x max_h); malloc'd, free with pn_free; NULL on failure.
PN_API uint8_t* pn_screen_thumbnail(const char* id, int32_t max_w, int32_t max_h, int32_t* w, int32_t* h);
// Starts capture + H.264 encoding asynchronously (result via PN_EV_SCREEN). Output size = source size scaled down to fit
// max_w x max_h (0 = no limit), even dimensions; fps 5..60; bitrate in kbps (500..20000). Starting while active restarts.
// Returns -1 if the id is invalid. Content is letterboxed (black) if a captured window changes its aspect ratio.
PN_API int32_t pn_screen_start(const char* id, int32_t max_w, int32_t max_h, int32_t fps, int32_t bitrate_kbps);
PN_API void pn_screen_stop(void);
PN_API void pn_screen_keyframe(void);              // force an IDR frame soon (new viewer / lost data)
PN_API void pn_screen_set_bitrate(int32_t kbps);
// {"active":true,"source":"...","w":1920,"h":1080,"fps":29.9,"kbps":5800,"encoder":"NVIDIA H.264 Encoder MFT","hw":true,"dropped":0}
PN_API char* pn_screen_status(void);

// Decoding of remote streams (id = streamer user id; 0 is used by the client for its own local preview).
PN_API int32_t pn_video_open(uint32_t id);
PN_API void pn_video_close(uint32_t id);
PN_API void pn_video_push(uint32_t id, const uint8_t* data, int32_t len, int32_t keyframe);  // one complete Annex-B access unit
PN_API char* pn_video_stats(uint32_t id);          // {"w":..,"h":..,"fps":..,"frames":..,"decoder":"..","hw":false}
// Used by pulse.exe's texture plugin (not by Dart):
typedef void (*pn_frame_cb)(uint32_t id);
PN_API void pn_video_set_frame_cb(pn_frame_cb cb);  // called from the decoder thread when a new frame is ready
// Locks the newest decoded frame (RGBA8888, tightly packed, w*h*4) for reading; returns 1 if a frame exists. Always call unlock after a 1.
// Lock and unlock must happen on the same thread; the decoder waits while a frame is locked, so copy and unlock quickly.
PN_API int32_t pn_video_lock_frame(uint32_t id, const uint8_t** rgba, int32_t* w, int32_t* h);
PN_API void pn_video_unlock_frame(uint32_t id);

// DPAPI (CurrentUser scope). Returns malloc'd buffer, *out_len set; NULL on failure.
PN_API uint8_t* pn_protect(const uint8_t* data, int32_t len, int32_t* out_len);
PN_API uint8_t* pn_unprotect(const uint8_t* data, int32_t len, int32_t* out_len);

// Offline test hooks. pn_debug_inline(1) before pn_vc_ai_config makes AI inference run
// synchronously inside pn_debug_process (no worker thread).
PN_API void pn_debug_inline(int32_t on);
// runs the full capture chain synchronously on 48 kHz mono float input
// (AI worker steps run inline). Returns number of samples written to out (== n).
PN_API int32_t pn_debug_process(const float* in, int32_t n, float* out);
