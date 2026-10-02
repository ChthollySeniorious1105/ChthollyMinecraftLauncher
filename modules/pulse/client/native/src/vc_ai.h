// GPU voice changer: RVC v2 pipeline on ONNX Runtime.
//
//   48 kHz mic ─► resample 16 kHz ─► HuBERT (content) ─┐
//                                  └► RMVPE (pitch f0) ─┼► RVC generator ─► model rate ─► 48 kHz
//
// Inference providers (multi-vendor):
//   dml:<n>      DirectML on DXGI adapter n — any DirectX 12 GPU (NVIDIA / AMD / Intel / Qualcomm ...)
//   ep:<name>:<n> plugin execution providers registered from ai\providers\*.dll
//                 (ORT "plugin EP" ABI, e.g. vendor TensorRT-RTX / OpenVINO / QNN builds)
//   cpu          ONNX Runtime CPU (slow fallback)
//   auto         best D3D12 adapter by dedicated VRAM
//
// onnxruntime.dll / DirectML.dll are loaded at runtime from the app folder, so
// the client still runs (without the AI voice changer) if they are missing.
#pragma once
#include <condition_variable>
#include <functional>
#include <map>
#include <memory>
#include <thread>

#include "common.h"
#include "dsp.h"

namespace pn {

struct GpuAdapter {
  int index;  // DXGI EnumAdapters1 order == DirectML device_id
  std::string name, vendor, driver;
  uint32_t vendorId, deviceId;
  uint64_t vramMB;
  bool software, d3d12;
};

std::vector<GpuAdapter> enumerateAdapters();
std::string vendorName(uint32_t id);
std::string gpuInfoJson();

struct Session;  // cached ONNX Runtime session (vc_ai.cpp)

class AiVoice {
 public:
  AiVoice();
  ~AiVoice();

  // Requests a (re)configuration. Non-blocking; requests are coalesced (only the
  // latest one is applied) and the running pipeline keeps converting until the
  // new one is ready, then it is swapped in without a gap. Sessions are cached,
  // so changing block / context / speaker after the first load is fast.
  int configure(const std::string& provider, const std::string& model, int blockMs, int extraMs, int speaker);
  // Frees the sessions (and GPU memory). Asynchronous.
  void unload();
  // (block, context) ms pairs compiled in the background once a pipeline is running,
  // so switching between these presets is instant (needs >= 6 GB VRAM).
  void setPrewarm(const std::vector<std::pair<int, int>>& presets);
  void setPitch(float semitones) { pitch_.store(semitones); }
  void setSpeaker(int sid) { speaker_.store(sid); }
  // Call when audio starts being routed through the AI again after a pause
  // (mode switched back to AI): drops stale history so no old audio is replayed.
  void requestReset() { resetRequested_.store(true); }

  bool running() const { return state_.load() == PN_VC_STATE_RUNNING; }
  int state() const { return state_.load(); }
  std::string statusJson();

  // Audio side (DSP thread): push 48 kHz processed mic, pull converted 48 kHz.
  // pull() returns false (and leaves `out` untouched) while not primed.
  void push(const float* in48, int n);
  bool pull(float* out48, int n);
  int latencyMs() const { return latencyMs_.load(); }

  // Debug: run inference steps inline instead of on the worker.
  void setInline(bool on) { inline_ = on; }

 private:
  struct Impl;
  struct Config {
    std::string provider, model;
    int blockMs = 200, extraMs = 300;
  };

  // Current pipeline. Swapped under mu_; the worker holds a shared_ptr while running a step.
  std::shared_ptr<Impl> impl_;
  std::atomic<int> state_{PN_VC_STATE_OFF};
  std::atomic<float> pitch_{0.f};
  std::atomic<int> speaker_{0};
  std::atomic<int> latencyMs_{0};
  std::atomic<int> extraLatMs_{0};
  std::atomic<bool> resetRequested_{false};
  std::atomic<bool> switching_{false};  // a hot reconfiguration is being built
  bool inline_ = false;

  void setState(int s, const std::string& err = "");
  void emitStatus();
  void loaderLoop();
  static void infer(Impl& im, const std::vector<float>& win16, std::vector<float>& prevTail, Resampler& up,
                    std::vector<float>& out48, float pitch, int speaker);
  bool build(const Config& c, std::shared_ptr<Impl>& out, std::string& err);
  void workerLoop();
  bool step();  // one block of inference; false if not enough input
  void resetBuffersLocked(const Impl& im);

  // loader: single persistent thread fed with the latest request
  std::thread loader_, worker_;
  std::mutex loadMu_;
  std::condition_variable loadCv_;
  bool havePending_ = false, unloadPending_ = false, quit_ = false;
  Config pending_, lastConfig_;
  std::vector<std::pair<int, int>> prewarm_, prewarmQueue_;
  static uint64_t vramOf(const std::string& provider);
  static std::string genKey(const Config& c);

  std::mutex mu_;  // guards impl_, buffers below and status strings
  std::condition_variable cv_;
  std::atomic<bool> stopWorker_{false};

  // input @16k (history) and conversion state
  Resampler down_;
  std::vector<float> hist16_;   // most recent kHist samples
  size_t newSamples_ = 0;       // 16k samples since the last step
  Ring out48_;
  bool primed_ = false;
  std::vector<float> prevTail_;  // crossfade region from the previous block

  // session cache (loader thread only)
  std::map<std::string, std::shared_ptr<Session>> cache_;
  std::vector<std::string> genLru_;
  std::shared_ptr<Session> cached(const std::string& key, const std::function<std::shared_ptr<Session>()>& make);

  // stats
  std::atomic<int> inferMs_{0};
  std::atomic<int> underruns_{0};
  std::string error_, providerId_, providerLabel_, modelPath_;
  int blockMs_ = 200, extraMs_ = 300;
  int modelRate_ = 40000, speakers_ = 1;
};

}  // namespace pn
