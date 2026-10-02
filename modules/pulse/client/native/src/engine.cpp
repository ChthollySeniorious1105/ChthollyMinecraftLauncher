// pulse_native.dll — audio engine, hotkeys and C API.
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_WASAPI
#include <windows.h>

#include "miniaudio.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <thread>

#include "common.h"
#include "dsp.h"
#include "opus_dyn.h"
#include "rnnoise.h"
#include "vc_ai.h"
#include "overlay.h"
#include "screen.h"
#include "video_dec.h"

namespace pn {
std::atomic<pn_event_cb> g_cb{nullptr};
}

using namespace pn;

namespace {

// ============================================================ jitter buffer

// Per-speaker adaptive jitter buffer + Opus decoder (48 kHz mono).
struct Speaker {
  OpusDecoder* dec = nullptr;
  std::map<uint16_t, std::vector<uint8_t>> pending;  // seq -> packet
  bool started = false;
  uint16_t next = 0;
  int targetFrames = 3;        // packets (20 ms each) to buffer before playing
  std::vector<float> pcm;      // decoded samples not yet mixed
  size_t pcmPos = 0;
  float volume = 1.f;
  float level = 0.f;
  int lostInRow = 0;
  DWORD lastArrival = 0;
  float jitterMs = 0.f;
  DWORD lastHeard = 0;

  ~Speaker() {
    if (dec) opus().decoder_destroy(dec);
  }
};

// ============================================================ UI sounds

std::vector<float> synthSound(int kind) {
  std::vector<float> out;
  auto tone = [&](float f0, float f1, float ms, float amp) {
    int n = static_cast<int>(kRate * ms / 1000.f);
    double ph = 0;
    for (int i = 0; i < n; i++) {
      float t = static_cast<float>(i) / n;
      float f = f0 + (f1 - f0) * t;
      ph += 2 * 3.14159265358979 * f / kRate;
      float env = std::min(1.f, i / (kRate * 0.005f)) * std::pow(1.f - t, 1.6f);
      out.push_back(static_cast<float>(std::sin(ph) + 0.25 * std::sin(2 * ph)) * env * amp);
    }
  };
  switch (kind) {
    case PN_SND_JOIN: tone(520, 520, 70, .25f); tone(780, 780, 110, .25f); break;
    case PN_SND_LEAVE: tone(780, 780, 70, .25f); tone(520, 520, 110, .25f); break;
    case PN_SND_MUTE: tone(600, 380, 90, .22f); break;
    case PN_SND_UNMUTE: tone(380, 600, 90, .22f); break;
    case PN_SND_DEAFEN: tone(500, 300, 70, .22f); tone(300, 220, 90, .22f); break;
    case PN_SND_UNDEAFEN: tone(300, 500, 70, .22f); tone(500, 650, 90, .22f); break;
    case PN_SND_MESSAGE: tone(880, 880, 60, .18f); tone(1320, 1320, 90, .14f); break;
    case PN_SND_MENTION: tone(990, 990, 70, .22f); tone(1320, 1320, 70, .2f); tone(1760, 1760, 120, .16f); break;
    default: tone(440, 440, 400, .3f); break;
  }
  return out;
}

// ============================================================ engine

struct Engine {
  ma_context ctx{};
  bool ctxOk = false;
  std::mutex devMu;  // device start/stop/selection
  ma_device cap{}, play{};
  bool capOn = false, playOn = false;
  std::string capId, playId;  // "" = default

  // ---- capture settings (atomics: read on the audio thread)
  std::atomic<bool> transmit{false}, muted{false}, monitor{false}, pttSoft{false}, pttHot{false};
  std::atomic<int> mode{PN_MODE_VAD}, nsLevel{2}, bitrate{64000}, pttReleaseMs{200}, vcMode{PN_VC_OFF};
  std::atomic<float> gain{1.f}, vadThreshold{0.5f}, vcPitch{0.f};
  std::atomic<bool> vcRobot{false};

  // ---- capture state (capture DSP thread only)
  std::vector<float> capAcc;  // 48k samples awaiting a 10 ms frame
  DenoiseState* rn = nullptr;
  HighPass hp;
  PitchShifter shifter;
  int vcPrev = PN_VC_OFF, vcFrom = PN_VC_OFF, vcFade = 3;  // mode crossfade
  float aiWet = 0.f;     // 0 = dry fallback, 1 = AI output
  DWORD aiLastUsed = 0;  // last time AI mode was active (background warm period)
  bool aiFed = false;
  DWORD mutedTalkAt = 0;
  Robot robot;
  OpusEncoder* enc = nullptr;
  int encBitrate = 0;
  std::vector<float> encAcc;  // 20 ms
  uint16_t seq = 0;
  bool gateOpen = false;
  int hangFrames = 0;
  DWORD pttReleasedAt = 0;
  bool wasPtt = false;
  float vadSmooth = 0.f;
  std::atomic<bool> speaking{false};  // written by the DSP thread, read by the overlay
  AiVoice ai;
  std::vector<float> aiOut;
  Ring monitorRing{48000};

  // capture thread handoff (audio callback -> DSP thread)
  Ring capRing{48000};
  std::thread dspThread;
  std::atomic<bool> dspStop{false};
  HANDLE dspEvent = nullptr;

  // ---- playback
  std::mutex spkMu;
  std::map<uint32_t, std::unique_ptr<Speaker>> speakers;
  std::map<uint32_t, float> userVolumes;
  std::atomic<float> outVolume{1.f}, soundVolume{0.6f};
  std::atomic<bool> deafened{false};
  std::mutex sndMu;
  std::vector<std::pair<std::vector<float>, size_t>> sounds;

  // ---- meters
  std::atomic<float> mMic{0}, mTx{0}, mVad{0}, mOut{0}, mGate{0};

  // ---- hotkeys
  struct Hk {
    int vk = 0, mods = 0;
    bool down = false;
  };
  Hk hk[PN_HK_COUNT];
  std::mutex hkMu;
  std::atomic<bool> hkCapture{false};
  std::thread hkThread;
  DWORD hkThreadId = 0;
  HHOOK kbHook = nullptr, msHook = nullptr;
  std::atomic<bool> hkOn{false};
};

Engine* g = nullptr;

// ------------------------------------------------------------ capture DSP

void ensureEncoder() {
  auto& o = opus();
  if (!o.ok) return;
  if (!g->enc) {
    int err = 0;
    g->enc = o.encoder_create(kRate, 1, OPUS_APPLICATION_VOIP, &err);
    if (!g->enc) {
      loge("opus_encoder_create failed " + std::to_string(err));
      return;
    }
    o.encoder_ctl(g->enc, OPUS_SET_COMPLEXITY_REQUEST, 9);
    o.encoder_ctl(g->enc, OPUS_SET_INBAND_FEC_REQUEST, 1);
    o.encoder_ctl(g->enc, OPUS_SET_PACKET_LOSS_PERC_REQUEST, 5);
    o.encoder_ctl(g->enc, OPUS_SET_SIGNAL_REQUEST, OPUS_SIGNAL_VOICE);
    g->encBitrate = 0;
  }
  int br = g->bitrate.load();
  if (br != g->encBitrate) {
    o.encoder_ctl(g->enc, OPUS_SET_BITRATE_REQUEST, br);
    g->encBitrate = br;
  }
}

void emitPacket(const float* pcm20) {
  ensureEncoder();
  if (!g->enc) return;
  uint8_t buf[2 + 1500];
  int32_t n = opus().encode_float(g->enc, pcm20, kOpusFrame, buf + 2, 1500);
  if (n <= 0) return;
  uint16_t s = g->seq++;
  buf[0] = static_cast<uint8_t>(s >> 8);
  buf[1] = static_cast<uint8_t>(s & 0xFF);
  emit(PN_EV_PACKET, 0, 0, buf, n + 2);
}

// Processes one 10 ms frame in place (480 samples, [-1, 1]); returns voice probability.
float processFrame(float* x, bool* outGate) {
  const int ns = g->nsLevel.load();
  // 1) gain + high-pass
  const float gn = g->gain.load();
  float peak = 0;
  for (int i = 0; i < kFrame; i++) {
    x[i] = g->hp.process(x[i] * gn);
    peak = std::max(peak, std::abs(x[i]));
  }
  float cur = g->mMic.load();
  g->mMic.store(peak > cur ? peak : cur * 0.85f + peak * 0.15f);

  // 2) RNNoise (expects 16-bit scale); also yields voice probability for VAD
  float vad = 0;
  if (g->rn) {
    float tmp[kFrame];
    for (int i = 0; i < kFrame; i++) tmp[i] = x[i] * 32768.f;
    float out[kFrame];
    vad = rnnoise_process_frame(g->rn, out, tmp);
    if (ns > 0) {
      // levels: 1 light = 60% denoised mix, 2 standard = full, 3 strong = full + residual gate
      float wet = ns == 1 ? 0.6f : 1.f;
      for (int i = 0; i < kFrame; i++) x[i] = (out[i] * wet + tmp[i] * (1 - wet)) / 32768.f;
      if (ns >= 3) {
        float att = vad < 0.3f ? 0.15f : (vad < 0.6f ? 0.6f : 1.f);
        for (int i = 0; i < kFrame; i++) x[i] *= att;
      }
    }
  } else {
    float e = 0;
    for (int i = 0; i < kFrame; i++) e += x[i] * x[i];
    float db = 10 * std::log10(e / kFrame + 1e-10f);
    vad = clampf((db + 55.f) / 25.f, 0.f, 1.f);
  }
  g->vadSmooth = g->vadSmooth * 0.7f + vad * 0.3f;
  g->mVad.store(g->vadSmooth);

  // 3) voice changer — every mode is rendered into its own buffer and mode changes
  //    crossfade over 30 ms, so toggling never clicks or drops syllables.
  const int vm = g->vcMode.load();
  float dry[kFrame];
  memcpy(dry, x, sizeof dry);
  bool pulledAi = false;
  auto render = [&](int mode, float* out) {
    memcpy(out, dry, sizeof dry);
    if (mode == PN_VC_DSP) {
      g->shifter.setSemitones(g->vcPitch.load());
      g->shifter.process(out, kFrame);
      if (g->vcRobot.load()) g->robot.process(out, kFrame);
    } else if (mode == PN_VC_AI) {
      // while the AI pipeline is (re)priming, pass the dry voice instead of silence
      bool ok = false;
      if (g->ai.running()) {
        g->ai.setPitch(g->vcPitch.load());
        ok = g->ai.pull(out, kFrame);
        pulledAi = true;
      }
      g->aiWet = clampf(g->aiWet + (ok ? 1.f : -1.f) / 4.f, 0.f, 1.f);  // 40 ms fade in / out of the dry fallback
      if (!ok) memcpy(out, dry, sizeof dry);
      for (int i = 0; i < kFrame; i++) out[i] = dry[i] + (out[i] - dry[i]) * g->aiWet;
    }
  };
  // keep feeding the AI for a while after leaving AI mode so switching back is instant
  const DWORD now = GetTickCount();
  if (vm == PN_VC_AI) g->aiLastUsed = now;
  const bool feedAi = g->ai.running() && (vm == PN_VC_AI || now - g->aiLastUsed < 30000);
  if (feedAi) {
    if (!g->aiFed) g->ai.requestReset();  // resuming after a pause: drop stale history
    g->ai.push(dry, kFrame);
  }
  g->aiFed = feedAi;
  if (vm != g->vcPrev) {
    g->vcFrom = g->vcPrev;
    g->vcFade = 0;
    g->vcPrev = vm;
    if (vm == PN_VC_DSP) g->shifter.reset();
  }
  render(vm, x);
  if (g->vcFade < 3) {  // 3 frames = 30 ms equal-power crossfade from the previous mode
    float from[kFrame];
    render(g->vcFrom, from);
    for (int i = 0; i < kFrame; i++) {
      const float a = (g->vcFade * kFrame + i) / (3.f * kFrame);
      x[i] = from[i] * std::cos(a * 1.5707963f) + x[i] * std::sin(a * 1.5707963f);
    }
    g->vcFade++;
  }
  // AI kept warm in the background: drain its output so the queue never grows stale.
  if (feedAi && !pulledAi) {
    float junk[kFrame];
    g->ai.pull(junk, kFrame);
  }

  // 4) transmit gate
  bool open = false;
  const int md = g->mode.load();
  const bool ptt = g->pttSoft.load() || g->pttHot.load();
  if (md == PN_MODE_OPEN) {
    open = true;
  } else if (md == PN_MODE_PTT) {
    DWORD now = GetTickCount();
    if (ptt) {
      open = true;
      g->wasPtt = true;
    } else if (g->wasPtt) {
      g->pttReleasedAt = now;
      g->wasPtt = false;
    }
    if (!ptt && now - g->pttReleasedAt < static_cast<DWORD>(g->pttReleaseMs.load())) open = true;
  } else {
    // VAD: sensitivity threshold on (smoothed) voice probability or level, with hangover
    float th = g->vadThreshold.load();
    float level = 0;
    for (int i = 0; i < kFrame; i++) level = std::max(level, std::abs(x[i]));
    bool voice = g->vadSmooth > th * 0.9f || (g->rn == nullptr && level > th * 0.2f);
    if (vm == PN_VC_AI) voice = voice || level > 0.02f;  // converted audio lags the VAD
    if (voice) {
      g->hangFrames = vm == PN_VC_AI ? 60 : 30;  // 300 ms (600 ms with AI latency)
    } else if (g->hangFrames > 0) {
      g->hangFrames--;
    }
    open = g->hangFrames > 0;
  }
  if (g->muted.load()) {
    // talking while muted: tell the UI once per burst (it shows "you are muted")
    if (open && g->transmit.load()) {
      const DWORD now = GetTickCount();
      if (now - g->mutedTalkAt > 3000) {
        g->mutedTalkAt = now;
        emit(PN_EV_MUTED_TALK, 0, 0);
      }
    }
    open = false;
  }
  *outGate = open;
  return vad;
}

void dspLoop() {
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
  std::vector<float> chunk(kFrame);
  while (!g->dspStop.load()) {
    WaitForSingleObject(g->dspEvent, 20);
    while (g->capRing.size() >= kFrame) {
      g->capRing.read(chunk.data(), kFrame);
      bool open = false;
      processFrame(chunk.data(), &open);
      float pk = 0;
      for (float v : chunk) pk = std::max(pk, std::abs(v));
      g->mTx.store(open ? pk : 0.f);
      g->mGate.store(open ? 1.f : 0.f);
      if (g->monitor.load()) g->monitorRing.write(chunk.data(), kFrame);

      const bool tx = g->transmit.load() && open;
      if (tx != g->speaking) {
        g->speaking = tx;
        emit(PN_EV_SPEAKING, tx ? 1 : 0, 0);
      }
      if (tx) {
        g->encAcc.insert(g->encAcc.end(), chunk.begin(), chunk.end());
      } else if (!g->encAcc.empty()) {
        // flush the partial packet with silence so the tail is not cut off
        g->encAcc.resize(kOpusFrame, 0.f);
      }
      if (g->encAcc.size() >= static_cast<size_t>(kOpusFrame)) {
        if (g->transmit.load()) emitPacket(g->encAcc.data());
        g->encAcc.clear();
      }
    }
  }
}

void onCapture(ma_device*, void*, const void* input, ma_uint32 frames) {
  if (!g || !input) return;
  g->capRing.write(static_cast<const float*>(input), frames);
  SetEvent(g->dspEvent);
}

// ------------------------------------------------------------ playback mix

void decodeMore(Speaker& s) {
  auto& o = opus();
  if (!o.ok) return;
  if (!s.dec) {
    int err = 0;
    s.dec = o.decoder_create(kRate, 1, &err);
    if (!s.dec) return;
  }
  float pcm[kOpusFrame * 6];
  if (!s.started) {
    if (static_cast<int>(s.pending.size()) < s.targetFrames) return;
    s.next = s.pending.begin()->first;
    s.started = true;
  }
  auto it = s.pending.find(s.next);
  int n;
  if (it != s.pending.end()) {
    n = o.decode_float(s.dec, it->second.data(), static_cast<int32_t>(it->second.size()), pcm, kOpusFrame * 6, 0);
    s.pending.erase(it);
    s.lostInRow = 0;
  } else if (s.pending.empty()) {
    // buffer ran dry: rebuffer (and buffer a bit more next time)
    s.started = false;
    s.targetFrames = std::min(10, s.targetFrames + 1);
    return;
  } else {
    // packet lost: use FEC from the next packet if available, else PLC
    auto nx = s.pending.find(static_cast<uint16_t>(s.next + 1));
    if (nx != s.pending.end()) {
      n = o.decode_float(s.dec, nx->second.data(), static_cast<int32_t>(nx->second.size()), pcm, kOpusFrame, 1);
    } else {
      n = o.decode_float(s.dec, nullptr, 0, pcm, kOpusFrame, 0);
    }
    if (++s.lostInRow > 25) {  // long gap: resync to the oldest pending packet
      s.next = s.pending.begin()->first;
      s.lostInRow = 0;
      return;
    }
  }
  s.next++;
  // drop old packets that can no longer be played
  while (!s.pending.empty()) {
    uint16_t first = s.pending.begin()->first;
    if (static_cast<int16_t>(first - s.next) < 0) {
      s.pending.erase(s.pending.begin());
    } else {
      break;
    }
  }
  if (n > 0) {
    if (s.pcmPos > 0) {
      s.pcm.erase(s.pcm.begin(), s.pcm.begin() + s.pcmPos);
      s.pcmPos = 0;
    }
    s.pcm.insert(s.pcm.end(), pcm, pcm + n);
  }
  // shrink the buffer slowly when the network is calm
  if (s.pending.size() > static_cast<size_t>(s.targetFrames) + 4) {
    s.pending.erase(s.pending.begin());
    s.next = s.pending.begin()->first;
  }
}

void onPlayback(ma_device* dev, void* output, const void*, ma_uint32 frames) {
  float* out = static_cast<float*>(output);
  const ma_uint32 ch = dev->playback.channels;
  std::vector<float> mix(frames, 0.f);
  if (g && !g->deafened.load()) {
    std::lock_guard<std::mutex> lk(g->spkMu);
    for (auto& [id, sp] : g->speakers) {
      Speaker& s = *sp;
      float pk = 0;
      ma_uint32 done = 0;
      while (done < frames) {
        if (s.pcmPos >= s.pcm.size()) {
          s.pcm.clear();
          s.pcmPos = 0;
          decodeMore(s);
          if (s.pcm.empty()) break;
        }
        size_t take = std::min<size_t>(frames - done, s.pcm.size() - s.pcmPos);
        const float v = s.volume;
        for (size_t i = 0; i < take; i++) {
          float x = s.pcm[s.pcmPos + i] * v;
          mix[done + i] += x;
          pk = std::max(pk, std::abs(x));
        }
        s.pcmPos += take;
        done += static_cast<ma_uint32>(take);
      }
      s.level = pk > s.level ? pk : s.level * 0.9f;
    }
  }
  if (g && g->monitor.load()) {
    std::vector<float> m(frames);
    size_t got = g->monitorRing.read(m.data(), frames);
    for (size_t i = 0; i < got; i++) mix[i] += m[i];
    // keep monitor latency low
    while (g->monitorRing.size() > 4800) {
      float junk[480];
      g->monitorRing.read(junk, 480);
    }
  }
  if (g) {
    std::lock_guard<std::mutex> lk(g->sndMu);
    const float sv = g->soundVolume.load();
    for (auto& [buf, pos] : g->sounds) {
      size_t take = std::min<size_t>(frames, buf.size() - pos);
      for (size_t i = 0; i < take; i++) mix[i] += buf[pos + i] * sv;
      pos += take;
    }
    g->sounds.erase(std::remove_if(g->sounds.begin(), g->sounds.end(), [](auto& s) { return s.second >= s.first.size(); }),
                    g->sounds.end());
  }
  const float vol = g ? g->outVolume.load() : 1.f;
  float pk = 0;
  for (ma_uint32 i = 0; i < frames; i++) {
    float v = mix[i] * vol;
    // soft clip
    if (v > 1.f || v < -1.f) v = std::tanh(v);
    pk = std::max(pk, std::abs(v));
    for (ma_uint32 c = 0; c < ch; c++) out[i * ch + c] = v;
  }
  if (g) {
    float cur = g->mOut.load();
    g->mOut.store(pk > cur ? pk : cur * 0.9f + pk * 0.1f);
  }
}

// ------------------------------------------------------------ devices

bool findDevice(ma_device_type type, const std::string& id, ma_device_id* out) {
  if (id.empty() || !g->ctxOk) return false;
  ma_device_info *pb = nullptr, *cp = nullptr;
  ma_uint32 npb = 0, ncp = 0;
  if (ma_context_get_devices(&g->ctx, &pb, &npb, &cp, &ncp) != MA_SUCCESS) return false;
  ma_device_info* list = type == ma_device_type_capture ? cp : pb;
  ma_uint32 n = type == ma_device_type_capture ? ncp : npb;
  std::wstring wid = widen(id);
  for (ma_uint32 i = 0; i < n; i++) {
    if (wid == list[i].id.wasapi) {
      *out = list[i].id;
      return true;
    }
  }
  return false;
}

void onNotification(const ma_device_notification* n) {
  if (!g || !n) return;
  const bool capture = n->pDevice == &g->cap;
  if (n->type == ma_device_notification_type_stopped) {
    // Device unplugged or invalidated. miniaudio reroutes "default" devices itself;
    // for an explicit device we report it so the UI can fall back.
    emit(PN_EV_DEVICE, capture ? 0 : 1, 0, "stopped", 7);
  } else if (n->type == ma_device_notification_type_rerouted) {
    emit(PN_EV_DEVICE, capture ? 0 : 1, 2, "rerouted", 8);
  }
}

int startDevice(bool capture) {
  std::lock_guard<std::mutex> lk(g->devMu);
  if (!g->ctxOk) return -1;
  ma_device& dev = capture ? g->cap : g->play;
  bool& on = capture ? g->capOn : g->playOn;
  if (on) {
    ma_device_uninit(&dev);
    on = false;
  }
  ma_device_config cfg = ma_device_config_init(capture ? ma_device_type_capture : ma_device_type_playback);
  ma_device_id id{};
  const std::string& want = capture ? g->capId : g->playId;
  bool explicitDev = findDevice(capture ? ma_device_type_capture : ma_device_type_playback, want, &id);
  if (capture) {
    cfg.capture.format = ma_format_f32;
    cfg.capture.channels = 1;
    cfg.capture.pDeviceID = explicitDev ? &id : nullptr;
    cfg.capture.shareMode = ma_share_mode_shared;
    cfg.dataCallback = onCapture;
  } else {
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = 2;
    cfg.playback.pDeviceID = explicitDev ? &id : nullptr;
    cfg.dataCallback = onPlayback;
  }
  cfg.sampleRate = kRate;
  cfg.periodSizeInMilliseconds = 10;
  cfg.performanceProfile = ma_performance_profile_low_latency;
  cfg.notificationCallback = onNotification;
  cfg.wasapi.noAutoConvertSRC = MA_FALSE;
  ma_result r = ma_device_init(&g->ctx, &cfg, &dev);
  if (r != MA_SUCCESS && explicitDev) {
    logw("selected device failed to open, falling back to default");
    if (capture) {
      cfg.capture.pDeviceID = nullptr;
    } else {
      cfg.playback.pDeviceID = nullptr;
    }
    r = ma_device_init(&g->ctx, &cfg, &dev);
  }
  if (r != MA_SUCCESS) {
    std::string msg = std::string(capture ? "无法打开麦克风：" : "无法打开扬声器：") + ma_result_description(r);
    emit(PN_EV_DEVICE, capture ? 0 : 1, -1, msg.data(), static_cast<int32_t>(msg.size()));
    return -1;
  }
  r = ma_device_start(&dev);
  if (r != MA_SUCCESS) {
    ma_device_uninit(&dev);
    std::string msg = std::string("设备启动失败：") + ma_result_description(r);
    emit(PN_EV_DEVICE, capture ? 0 : 1, -1, msg.data(), static_cast<int32_t>(msg.size()));
    return -1;
  }
  on = true;
  std::string name = capture ? dev.capture.name : dev.playback.name;
  emit(PN_EV_DEVICE, capture ? 0 : 1, 1, name.data(), static_cast<int32_t>(name.size()));
  return 0;
}

void stopDevice(bool capture) {
  std::lock_guard<std::mutex> lk(g->devMu);
  ma_device& dev = capture ? g->cap : g->play;
  bool& on = capture ? g->capOn : g->playOn;
  if (on) {
    ma_device_uninit(&dev);
    on = false;
    emit(PN_EV_DEVICE, capture ? 0 : 1, 0, nullptr, 0);
  }
}

// ------------------------------------------------------------ hotkeys

int currentMods() {
  int m = 0;
  if (GetAsyncKeyState(VK_CONTROL) & 0x8000) m |= PN_MOD_CTRL;
  if (GetAsyncKeyState(VK_SHIFT) & 0x8000) m |= PN_MOD_SHIFT;
  if (GetAsyncKeyState(VK_MENU) & 0x8000) m |= PN_MOD_ALT;
  if ((GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000) m |= PN_MOD_WIN;
  return m;
}

bool isModifierVk(int vk) {
  switch (vk) {
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT:
    case VK_MENU: case VK_LMENU: case VK_RMENU: case VK_LWIN: case VK_RWIN:
      return true;
  }
  return false;
}

int normalizeVk(int vk) {
  switch (vk) {
    case VK_LCONTROL: case VK_RCONTROL: return VK_CONTROL;
    case VK_LSHIFT: case VK_RSHIFT: return VK_SHIFT;
    case VK_LMENU: case VK_RMENU: return VK_MENU;
    case VK_RWIN: return VK_LWIN;
  }
  return vk;
}

int modBit(int vk) {
  switch (normalizeVk(vk)) {
    case VK_CONTROL: return PN_MOD_CTRL;
    case VK_SHIFT: return PN_MOD_SHIFT;
    case VK_MENU: return PN_MOD_ALT;
    case VK_LWIN: return PN_MOD_WIN;
  }
  return 0;
}

// Called for every key / mouse-button transition. Never swallows input: Pulse
// only observes keys (PTT on a game key must still reach the game).
void onKey(int vk, bool down) {
  if (!g) return;
  vk = normalizeVk(vk);
  if (g->hkCapture.load()) {
    if (down && vk != VK_ESCAPE) {
      int mods = currentMods();
      if (isModifierVk(vk)) mods &= ~modBit(vk);  // a bare modifier (e.g. Ctrl) as the key itself
      g->hkCapture = false;
      emit(PN_EV_HOTKEY_CAPTURED, vk, mods);
    } else if (down && vk == VK_ESCAPE) {
      g->hkCapture = false;
      emit(PN_EV_HOTKEY_CAPTURED, 0, 0);
    }
    return;
  }
  std::lock_guard<std::mutex> lk(g->hkMu);
  for (int s = 0; s < PN_HK_COUNT; s++) {
    auto& h = g->hk[s];
    if (!h.vk || h.vk != vk) continue;
    if (down) {
      if (h.down) continue;  // auto-repeat
      int mods = currentMods();
      if (isModifierVk(vk)) mods &= ~modBit(vk);
      if ((mods & h.mods) != h.mods) continue;  // required modifiers held (extra ones allowed)
      h.down = true;
      if (s == PN_HK_PTT) g->pttHot = true;
      emit(PN_EV_HOTKEY, s, 1);
    } else if (h.down) {
      h.down = false;
      if (s == PN_HK_PTT) g->pttHot = false;
      emit(PN_EV_HOTKEY, s, 0);
    }
  }
}

LRESULT CALLBACK kbProc(int code, WPARAM w, LPARAM l) {
  if (code == HC_ACTION) {
    auto* k = reinterpret_cast<KBDLLHOOKSTRUCT*>(l);
    bool down = w == WM_KEYDOWN || w == WM_SYSKEYDOWN;
    bool up = w == WM_KEYUP || w == WM_SYSKEYUP;
    if ((down || up) && !(k->flags & LLKHF_INJECTED && k->dwExtraInfo == 0x50554C53)) onKey(static_cast<int>(k->vkCode), down);
  }
  return CallNextHookEx(nullptr, code, w, l);
}

LRESULT CALLBACK msProc(int code, WPARAM w, LPARAM l) {
  if (code == HC_ACTION) {
    auto* m = reinterpret_cast<MSLLHOOKSTRUCT*>(l);
    switch (w) {
      case WM_MBUTTONDOWN: onKey(VK_MBUTTON, true); break;
      case WM_MBUTTONUP: onKey(VK_MBUTTON, false); break;
      case WM_XBUTTONDOWN: case WM_XBUTTONUP:
        onKey(HIWORD(m->mouseData) == XBUTTON1 ? VK_XBUTTON1 : VK_XBUTTON2, w == WM_XBUTTONDOWN);
        break;
    }
  }
  return CallNextHookEx(nullptr, code, w, l);
}

void hookThread() {
  // Low-level hooks need a message loop on the installing thread. They see input
  // system-wide (also when a fullscreen game has focus) without stealing it.
  g->hkThreadId = GetCurrentThreadId();
  g->kbHook = SetWindowsHookExW(WH_KEYBOARD_LL, kbProc, GetModuleHandleW(nullptr), 0);
  g->msHook = SetWindowsHookExW(WH_MOUSE_LL, msProc, GetModuleHandleW(nullptr), 0);
  if (!g->kbHook) loge("SetWindowsHookEx(WH_KEYBOARD_LL) failed: " + std::to_string(GetLastError()));
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
  }
  if (g->kbHook) UnhookWindowsHookEx(g->kbHook);
  if (g->msHook) UnhookWindowsHookEx(g->msHook);
  g->kbHook = g->msHook = nullptr;
}

}  // namespace

// ============================================================ C API

PN_API int32_t pn_init(pn_event_cb cb, const char* base_dir) {
  if (g) return 0;
  g_cb.store(cb);
  setBaseDir(base_dir);
  g = new Engine();
  g->dspEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  g->hp.init(80.f, kRate);
  if (!loadOpus(moduleDirW())) loge("Opus unavailable: " + opus().error);
  g->rn = rnnoise_create(nullptr);
  ma_context_config cc = ma_context_config_init();
  g->ctxOk = ma_context_init(nullptr, 0, &cc, &g->ctx) == MA_SUCCESS;
  if (!g->ctxOk) loge("audio context init failed");
  g->dspThread = std::thread(dspLoop);
  logi(std::string("native engine ready, opus ") + (opus().ok ? opus().get_version_string() : "missing"));
  return g->ctxOk ? 0 : -1;
}

PN_API void pn_shutdown(void) {
  if (!g) return;
  screen::shutdown();
  video::shutdown();
  overlay::shutdown();
  pn_hotkeys_enable(0);
  stopDevice(true);
  stopDevice(false);
  g->dspStop = true;
  SetEvent(g->dspEvent);
  if (g->dspThread.joinable()) g->dspThread.join();
  if (g->enc) opus().encoder_destroy(g->enc);
  if (g->rn) rnnoise_destroy(g->rn);
  {
    std::lock_guard<std::mutex> lk(g->spkMu);
    g->speakers.clear();
  }
  if (g->ctxOk) ma_context_uninit(&g->ctx);
  CloseHandle(g->dspEvent);
  g_cb.store(nullptr);
  delete g;
  g = nullptr;
}

PN_API char* pn_list_devices(int32_t kind) {
  std::string j = "[";
  if (g && g->ctxOk) {
    std::lock_guard<std::mutex> lk(g->devMu);
    ma_device_info *pb = nullptr, *cp = nullptr;
    ma_uint32 npb = 0, ncp = 0;
    if (ma_context_get_devices(&g->ctx, &pb, &npb, &cp, &ncp) == MA_SUCCESS) {
      ma_device_info* list = kind == 0 ? cp : pb;
      ma_uint32 n = kind == 0 ? ncp : npb;
      for (ma_uint32 i = 0; i < n; i++) {
        if (i) j += ",";
        j += "{\"id\":\"" + jsonEscape(narrow(list[i].id.wasapi)) + "\",\"name\":\"" + jsonEscape(list[i].name) +
             "\",\"default\":" + (list[i].isDefault ? "true" : "false") + "}";
      }
    }
  }
  j += "]";
  return dupString(j);
}

PN_API int32_t pn_set_device(int32_t kind, const char* id) {
  if (!g) return -1;
  bool running;
  {
    std::lock_guard<std::mutex> lk(g->devMu);
    (kind == 0 ? g->capId : g->playId) = id ? id : "";
    running = kind == 0 ? g->capOn : g->playOn;
  }
  return running ? startDevice(kind == 0) : 0;
}

PN_API int32_t pn_capture_start(void) { return g ? startDevice(true) : -1; }
PN_API void pn_capture_stop(void) {
  if (!g) return;
  stopDevice(true);
  g->mMic = 0;
  g->mTx = 0;
}
PN_API void pn_set_transmit(int32_t on) {
  if (g) g->transmit = on != 0;
}
PN_API void pn_set_mute(int32_t m) {
  if (g) g->muted = m != 0;
}
PN_API void pn_set_input_mode(int32_t m) {
  if (g) g->mode = std::clamp(m, 0, 2);
}
PN_API void pn_set_ptt(int32_t held) {
  if (g) g->pttSoft = held != 0;
}
PN_API void pn_set_input_gain(float v) {
  if (g) g->gain = clampf(v, 0.f, 4.f);
}
PN_API void pn_set_vad_threshold(float t) {
  if (g) g->vadThreshold = clampf(t, 0.f, 1.f);
}
PN_API void pn_set_noise_suppression(int32_t l) {
  if (g) g->nsLevel = std::clamp(l, 0, 3);
}
PN_API void pn_set_bitrate(int32_t bps) {
  if (g) g->bitrate = std::clamp(bps, 8000, 128000);
}
PN_API void pn_set_monitor(int32_t on) {
  if (!g) return;
  g->monitor = on != 0;
  if (!on) g->monitorRing.clear();
}
PN_API void pn_set_ptt_release_ms(int32_t ms) {
  if (g) g->pttReleaseMs = std::clamp(ms, 0, 2000);
}

PN_API int32_t pn_playback_start(void) { return g ? startDevice(false) : -1; }
PN_API void pn_playback_stop(void) {
  if (g) stopDevice(false);
}
PN_API void pn_set_output_volume(float v) {
  if (g) g->outVolume = clampf(v, 0.f, 2.f);
}
PN_API void pn_set_deafen(int32_t on) {
  if (g) g->deafened = on != 0;
}
PN_API void pn_set_user_volume(uint32_t user, float v) {
  if (!g) return;
  std::lock_guard<std::mutex> lk(g->spkMu);
  g->userVolumes[user] = clampf(v, 0.f, 2.f);
  auto it = g->speakers.find(user);
  if (it != g->speakers.end()) it->second->volume = g->userVolumes[user];
}

PN_API void pn_play_push(uint32_t user, const uint8_t* data, int32_t len) {
  if (!g || !data || len < 3 || len > 1502 || g->deafened.load()) return;
  uint16_t seq = static_cast<uint16_t>((data[0] << 8) | data[1]);
  std::lock_guard<std::mutex> lk(g->spkMu);
  auto& sp = g->speakers[user];
  if (!sp) {
    sp = std::make_unique<Speaker>();
    auto v = g->userVolumes.find(user);
    if (v != g->userVolumes.end()) sp->volume = v->second;
  }
  Speaker& s = *sp;
  DWORD now = GetTickCount();
  if (s.lastArrival) {
    float d = std::abs(static_cast<float>(now - s.lastArrival) - 20.f);
    s.jitterMs = s.jitterMs * 0.95f + d * 0.05f;
    // target ≈ 2 packets + 2× jitter, clamped 40–200 ms
    int want = std::clamp(2 + static_cast<int>(s.jitterMs * 2 / 20.f), 2, 10);
    if (want > s.targetFrames) s.targetFrames = want;
    else if (want < s.targetFrames && (now / 1000) % 5 == 0) s.targetFrames--;
  }
  s.lastArrival = now;
  s.lastHeard = now;
  // a long silence (talk spurt boundary): restart cleanly
  if (s.started && static_cast<int16_t>(seq - s.next) < -50) {
    s.pending.clear();
    s.started = false;
  }
  if (s.started && static_cast<int16_t>(seq - s.next) < 0) return;  // too late
  if (s.pending.size() > 50) s.pending.erase(s.pending.begin());
  s.pending[seq] = std::vector<uint8_t>(data + 2, data + len);
}

PN_API void pn_play_remove(uint32_t user) {
  if (!g) return;
  std::lock_guard<std::mutex> lk(g->spkMu);
  g->speakers.erase(user);
}

PN_API void pn_play_clear(void) {
  if (!g) return;
  std::lock_guard<std::mutex> lk(g->spkMu);
  g->speakers.clear();
}

PN_API void pn_play_sound(int32_t kind) {
  if (!g) return;
  auto s = synthSound(kind);
  std::lock_guard<std::mutex> lk(g->sndMu);
  if (g->sounds.size() < 8) g->sounds.emplace_back(std::move(s), 0);
}

PN_API void pn_set_sound_volume(float v) {
  if (g) g->soundVolume = clampf(v, 0.f, 1.f);
}

PN_API int32_t pn_get_levels(float* l, int32_t n) {
  if (!g || !l) return 0;
  float v[5] = {g->mMic.load(), g->mTx.load(), g->mVad.load(), g->mOut.load(), g->mGate.load()};
  int k = std::min(n, 5);
  memcpy(l, v, k * sizeof(float));
  return k;
}

PN_API int32_t pn_get_user_levels(uint32_t* users, float* levels, int32_t n) {
  if (!g || !users || !levels) return 0;
  std::lock_guard<std::mutex> lk(g->spkMu);
  int k = 0;
  DWORD now = GetTickCount();
  for (auto& [id, s] : g->speakers) {
    if (k >= n) break;
    users[k] = id;
    levels[k] = now - s->lastHeard < 300 ? std::max(s->level, 0.02f) : 0.f;
    k++;
  }
  return k;
}

PN_API int32_t pn_hotkeys_enable(int32_t on) {
  if (!g) return -1;
  if (on && !g->hkOn.load()) {
    g->hkOn = true;
    g->hkThread = std::thread(hookThread);
  } else if (!on && g->hkOn.load()) {
    g->hkOn = false;
    while (!g->hkThreadId) Sleep(1);
    PostThreadMessageW(g->hkThreadId, WM_QUIT, 0, 0);
    if (g->hkThread.joinable()) g->hkThread.join();
    g->hkThreadId = 0;
    g->pttHot = false;
  }
  return 0;
}

PN_API void pn_hotkey_set(int32_t slot, int32_t vk, int32_t mods) {
  if (!g || slot < 0 || slot >= PN_HK_COUNT) return;
  std::lock_guard<std::mutex> lk(g->hkMu);
  g->hk[slot].vk = normalizeVk(vk);
  g->hk[slot].mods = mods;
  if (g->hk[slot].down && slot == PN_HK_PTT) g->pttHot = false;
  g->hk[slot].down = false;
}

PN_API void pn_hotkey_capture(int32_t on) {
  if (g) g->hkCapture = on != 0;
}

PN_API char* pn_key_name(int32_t vk) {
  switch (vk) {
    case 0: return dupString("");
    case VK_LBUTTON: return dupString("鼠标左键");
    case VK_RBUTTON: return dupString("鼠标右键");
    case VK_MBUTTON: return dupString("鼠标中键");
    case VK_XBUTTON1: return dupString("鼠标侧键 1");
    case VK_XBUTTON2: return dupString("鼠标侧键 2");
    case VK_CONTROL: return dupString("Ctrl");
    case VK_SHIFT: return dupString("Shift");
    case VK_MENU: return dupString("Alt");
    case VK_LWIN: return dupString("Win");
    case VK_CAPITAL: return dupString("CapsLock");
    case VK_OEM_3: return dupString("`");
  }
  UINT sc = MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
  switch (vk) {  // extended keys need the extended bit for a correct name
    case VK_LEFT: case VK_UP: case VK_RIGHT: case VK_DOWN: case VK_PRIOR: case VK_NEXT: case VK_END: case VK_HOME:
    case VK_INSERT: case VK_DELETE: case VK_DIVIDE: case VK_NUMLOCK:
      sc |= 0x100;
  }
  wchar_t name[64] = {0};
  int n = GetKeyNameTextW(static_cast<LONG>(sc << 16), name, 64);
  if (n <= 0) {
    char b[16];
    snprintf(b, sizeof b, "键 %d", vk);
    return dupString(b);
  }
  return dupString(narrow(std::wstring(name, n)));
}

PN_API char* pn_gpu_info(void) { return dupString(gpuInfoJson()); }

// ---- speaker overlay
namespace pn {
float userSpeakingLevel(uint32_t uid, bool self) {
  if (!g) return 0.f;
  if (self) return g->speaking ? std::max(0.05f, g->mTx.load()) : 0.f;
  std::lock_guard<std::mutex> lk(g->spkMu);
  auto it = g->speakers.find(uid);
  if (it == g->speakers.end()) return 0.f;
  return GetTickCount() - it->second->lastHeard < 250 ? std::max(it->second->level, 0.02f) : 0.f;
}
}  // namespace pn

PN_API void pn_overlay_show(int32_t on) { overlay::show(on != 0); }
PN_API void pn_overlay_config(int32_t mode, float opacity, float scale, int32_t locked, int32_t hide_when_focused) {
  overlay::config(mode, opacity, scale, locked != 0, hide_when_focused != 0);
}
PN_API void pn_overlay_roster_begin(const char* title, uint32_t me) { overlay::rosterBegin(title ? title : "", me); }
PN_API void pn_overlay_roster_add(uint32_t id, const char* name, uint32_t argb, int32_t flags) {
  overlay::rosterAdd(id, name ? name : "", argb, flags);
}
PN_API void pn_overlay_roster_commit(void) { overlay::rosterCommit(); }
PN_API void pn_overlay_avatar(uint32_t id, const uint8_t* data, int32_t len) { overlay::setAvatar(id, data, len); }
PN_API void pn_overlay_reset_position(void) { overlay::resetPosition(); }

// Flashes the app's taskbar button until the window is focused (unread @mention).
PN_API void pn_flash_window(void) {
  HWND h = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  DWORD pid = 0;
  for (; h; h = FindWindowExW(nullptr, h, L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr)) {
    GetWindowThreadProcessId(h, &pid);
    if (pid == GetCurrentProcessId()) break;
  }
  if (!h || GetForegroundWindow() == h) return;
  FLASHWINFO fi{sizeof fi, h, FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
  FlashWindowEx(&fi);
}

PN_API void pn_vc_set_mode(int32_t m) {
  if (g) g->vcMode = std::clamp(m, 0, 2);  // the DSP thread crossfades to the new mode
}
PN_API void pn_vc_set_pitch(float st) {
  if (g) g->vcPitch = clampf(st, -24.f, 24.f);
}
PN_API void pn_vc_set_robot(int32_t on) {
  if (g) g->vcRobot = on != 0;
}
PN_API int32_t pn_vc_ai_config(const char* provider, const char* model, int32_t block_ms, int32_t extra_ms, int32_t speaker) {
  if (!g) return -1;
  return g->ai.configure(provider ? provider : "auto", model ? model : "", block_ms, extra_ms, speaker);
}
PN_API void pn_vc_ai_prewarm(const int32_t* pairs, int32_t count) {
  if (!g) return;
  std::vector<std::pair<int, int>> v;
  for (int32_t i = 0; pairs && i < count; i++) v.emplace_back(pairs[2 * i], pairs[2 * i + 1]);
  g->ai.setPrewarm(v);
}

PN_API void pn_vc_set_speaker(int32_t sid) {
  if (g) g->ai.setSpeaker(sid);
}
PN_API void pn_vc_ai_unload(void) {
  if (g) g->ai.unload();
}
PN_API char* pn_vc_status(void) { return dupString(g ? g->ai.statusJson() : "{}"); }

PN_API void pn_debug_inline(int32_t on) {
  if (g) g->ai.setInline(on != 0);
}

PN_API int32_t pn_debug_process(const float* in, int32_t n, float* out) {
  if (!g || !in || !out) return 0;
  for (int32_t off = 0; off + kFrame <= n; off += kFrame) {
    float f[kFrame];
    memcpy(f, in + off, sizeof f);
    bool open;
    processFrame(f, &open);
    memcpy(out + off, f, sizeof f);
  }
  return n - n % kFrame;
}

// ---- screen sharing
PN_API char* pn_screen_sources(void) { return dupString(screen::sourcesJson()); }
PN_API uint8_t* pn_screen_thumbnail(const char* id, int32_t max_w, int32_t max_h, int32_t* w, int32_t* h) {
  return screen::thumbnail(id ? id : "", max_w, max_h, w, h);
}
PN_API int32_t pn_screen_start(const char* id, int32_t max_w, int32_t max_h, int32_t fps, int32_t bitrate_kbps) {
  return screen::start(id ? id : "", max_w, max_h, fps, bitrate_kbps);
}
PN_API void pn_screen_stop(void) { screen::stop(); }
PN_API void pn_screen_keyframe(void) { screen::keyframe(); }
PN_API void pn_screen_set_bitrate(int32_t kbps) { screen::setBitrate(kbps); }
PN_API char* pn_screen_status(void) { return dupString(screen::statusJson()); }

PN_API int32_t pn_video_open(uint32_t id) { return video::open(id); }
PN_API void pn_video_close(uint32_t id) { video::close(id); }
PN_API void pn_video_push(uint32_t id, const uint8_t* data, int32_t len, int32_t keyframe) {
  video::push(id, data, len, keyframe != 0);
}
PN_API char* pn_video_stats(uint32_t id) { return dupString(video::statsJson(id)); }
PN_API void pn_video_set_frame_cb(pn_frame_cb cb) { video::setFrameCallback(cb); }
PN_API int32_t pn_video_lock_frame(uint32_t id, const uint8_t** rgba, int32_t* w, int32_t* h) {
  int iw = 0, ih = 0;
  bool ok = video::lockFrame(id, rgba, &iw, &ih);
  if (w) *w = iw;
  if (h) *h = ih;
  return ok ? 1 : 0;
}
PN_API void pn_video_unlock_frame(uint32_t id) { video::unlockFrame(id); }
