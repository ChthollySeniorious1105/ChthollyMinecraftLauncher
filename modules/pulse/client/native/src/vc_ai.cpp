#include "vc_ai.h"

#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>

#include <algorithm>
#include <map>
#include <chrono>
#include <cmath>
#include <random>
#include <stdexcept>

#include "dml_provider_factory.h"
#include "onnxruntime_c_api.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d12.lib")

namespace pn {

// ============================================================ GPU enumeration

std::string vendorName(uint32_t id) {
  switch (id) {
    case 0x10DE: return "NVIDIA";
    case 0x1002: case 0x1022: return "AMD";
    case 0x8086: return "Intel";
    case 0x5143: case 0x4D4F4351: return "Qualcomm";
    case 0x1414: return "Microsoft";
    case 0x13B5: return "ARM";
    case 0x106B: return "Apple";
    case 0x1AE0: return "Google";
    case 0x1D17: return "Zhaoxin";
    case 0x1ED5: return "Moore Threads";
    default: {
      char b[16];
      snprintf(b, sizeof b, "0x%04X", id);
      return b;
    }
  }
}

std::vector<GpuAdapter> enumerateAdapters() {
  std::vector<GpuAdapter> out;
  IDXGIFactory1* f = nullptr;
  if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&f))) || !f) return out;
  IDXGIAdapter1* a = nullptr;
  std::vector<std::string> seen;
  for (UINT i = 0; f->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; i++) {
    DXGI_ADAPTER_DESC1 d{};
    a->GetDesc1(&d);
    // Virtual display drivers (IddCx: emulators, remote desktop, streaming) re-expose the
    // same physical GPU under another LUID. List each piece of hardware once (the first
    // DXGI index is the one DirectML should use). Two identical physical cards collapse
    // too — acceptable for a chat app; see ARCHITECTURE.md.
    char key[96];
    snprintf(key, sizeof key, "%x:%x:%x:%x:%llu", d.VendorId, d.DeviceId, d.SubSysId, d.Revision,
             static_cast<unsigned long long>(d.DedicatedVideoMemory));
    if (std::find(seen.begin(), seen.end(), key) != seen.end()) {
      a->Release();
      continue;
    }
    seen.push_back(key);
    GpuAdapter g{};
    g.index = static_cast<int>(i);
    g.name = narrow(d.Description);
    g.vendorId = d.VendorId;
    g.deviceId = d.DeviceId;
    g.vendor = vendorName(d.VendorId);
    g.vramMB = d.DedicatedVideoMemory / (1024 * 1024);
    g.software = (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0;
    LARGE_INTEGER umd{};
    if (SUCCEEDED(a->CheckInterfaceSupport(__uuidof(IDXGIDevice), &umd))) {
      char b[64];
      snprintf(b, sizeof b, "%u.%u.%u.%u", HIWORD(umd.HighPart), LOWORD(umd.HighPart), HIWORD(umd.LowPart),
               LOWORD(umd.LowPart));
      g.driver = b;
    }
    // S_FALSE = "would succeed" when ppDevice is null
    g.d3d12 = SUCCEEDED(D3D12CreateDevice(a, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), nullptr));
    out.push_back(g);
    a->Release();
  }
  f->Release();
  return out;
}

// ============================================================ ONNX Runtime loader

namespace {

struct Ort {
  HMODULE dll = nullptr;
  const OrtApi* api = nullptr;
  const OrtDmlApi* dml = nullptr;
  OrtEnv* env = nullptr;
  std::string version, error;
  std::vector<std::string> available;  // GetAvailableProviders
  std::vector<std::string> plugins;    // registered plugin EP libraries
  bool tried = false;
};

Ort& ort() {
  static Ort o;
  return o;
}

std::mutex g_ortMu;

void check(OrtStatus* st) {
  if (!st) return;
  std::string msg = ort().api->GetErrorMessage(st);
  ort().api->ReleaseStatus(st);
  throw std::runtime_error(msg);
}

bool loadOrt() {
  std::lock_guard<std::mutex> lk(g_ortMu);
  auto& o = ort();
  if (o.api) return true;
  if (o.tried) return false;
  o.tried = true;
  // Load by full path so the (older) Windows ML copy in System32 is never picked up;
  // LOAD_WITH_ALTERED_SEARCH_PATH makes its dependencies (DirectML.dll) resolve next to it.
  std::wstring path = moduleDirW() + L"onnxruntime.dll";
  o.dll = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!o.dll) {
    o.error = "onnxruntime.dll not found next to the app (AI voice changer disabled)";
    return false;
  }
  using GetApiBaseFn = const OrtApiBase*(ORT_API_CALL*)();
  auto getBase = reinterpret_cast<GetApiBaseFn>(GetProcAddress(o.dll, "OrtGetApiBase"));
  if (!getBase) {
    o.error = "onnxruntime.dll has no OrtGetApiBase";
    return false;
  }
  const OrtApiBase* base = getBase();
  o.version = base->GetVersionString();
  o.api = base->GetApi(ORT_API_VERSION);
  if (!o.api) {
    o.error = "onnxruntime " + o.version + " is older than the API version Pulse was built with (" +
              std::to_string(ORT_API_VERSION) + ")";
    return false;
  }
  try {
    check(o.api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "pulse", &o.env));
    const void* dmlApi = nullptr;
    if (!o.api->GetExecutionProviderApi("DML", ORT_API_VERSION, &dmlApi) && dmlApi) {
      o.dml = static_cast<const OrtDmlApi*>(dmlApi);
    }
    char** provs = nullptr;
    int n = 0;
    if (!o.api->GetAvailableProviders(&provs, &n)) {
      for (int i = 0; i < n; i++) o.available.push_back(provs[i]);
      o.api->ReleaseAvailableProviders(provs, n);
    }
    // Plugin execution providers: every DLL in ai\providers\ is registered with ORT.
    WIN32_FIND_DATAW fd;
    std::wstring dir = moduleDirW() + L"ai\\providers\\";
    HANDLE h = FindFirstFileW((dir + L"*.dll").c_str(), &fd);
    if (h != INVALID_HANDLE_VALUE) {
      do {
        std::wstring file = fd.cFileName;
        std::string reg = narrow(file.substr(0, file.size() - 4));
        OrtStatus* st = o.api->RegisterExecutionProviderLibrary(o.env, reg.c_str(), (dir + file).c_str());
        if (st) {
          logw("plugin EP " + reg + " failed to register: " + o.api->GetErrorMessage(st));
          o.api->ReleaseStatus(st);
        } else {
          o.plugins.push_back(reg);
          logi("registered plugin EP library " + reg);
        }
      } while (FindNextFileW(h, &fd));
      FindClose(h);
    }
  } catch (const std::exception& e) {
    o.error = e.what();
    o.api = nullptr;
    return false;
  }
  logi("ONNX Runtime " + o.version + " loaded");
  return true;
}

struct EpDev {
  std::string id, label, ep, vendor, kind;
  const OrtEpDevice* dev;
};

// Plugin / auto-discovered EP devices other than the built-in CPU and DML ones.
std::vector<EpDev> epDevices() {
  std::vector<EpDev> r;
  auto& o = ort();
  if (!o.api || !o.env) return r;
  const OrtEpDevice* const* devs = nullptr;
  size_t n = 0;
  if (OrtStatus* st = o.api->GetEpDevices(o.env, &devs, &n)) {
    o.api->ReleaseStatus(st);
    return r;
  }
  std::map<std::string, int> counter;
  for (size_t i = 0; i < n; i++) {
    std::string ep = o.api->EpDevice_EpName(devs[i]);
    if (ep == "CPUExecutionProvider" || ep == "DmlExecutionProvider") continue;
    const OrtHardwareDevice* hw = o.api->EpDevice_Device(devs[i]);
    auto type = o.api->HardwareDevice_Type(hw);
    std::string vendor = o.api->HardwareDevice_Vendor(hw);
    if (vendor.empty()) vendor = vendorName(o.api->HardwareDevice_VendorId(hw));
    int idx = counter[ep]++;
    std::string kind = type == OrtHardwareDeviceType_GPU ? "gpu" : (type == OrtHardwareDeviceType_NPU ? "npu" : "cpu");
    std::string name = ep;
    if (const OrtKeyValuePairs* md = o.api->HardwareDevice_Metadata(hw)) {
      if (const char* d = o.api->GetKeyValue(md, "Description")) name = std::string(d) + " · " + ep;
    }
    r.push_back({"ep:" + ep + ":" + std::to_string(idx), name, ep, vendor, kind, devs[i]});
  }
  return r;
}

}  // namespace

std::string gpuInfoJson() {
  auto adapters = enumerateAdapters();
  bool ortOk = loadOrt();
  auto& o = ort();
  std::string j = "{\"ort\":\"" + jsonEscape(o.version) + "\",\"ortError\":\"" + jsonEscape(o.error) + "\",\"adapters\":[";
  for (size_t i = 0; i < adapters.size(); i++) {
    auto& a = adapters[i];
    if (i) j += ",";
    j += "{\"index\":" + std::to_string(a.index) + ",\"name\":\"" + jsonEscape(a.name) + "\",\"vendor\":\"" +
         jsonEscape(a.vendor) + "\",\"vendorId\":" + std::to_string(a.vendorId) + ",\"deviceId\":" +
         std::to_string(a.deviceId) + ",\"vramMB\":" + std::to_string(a.vramMB) + ",\"driver\":\"" + a.driver +
         "\",\"software\":" + (a.software ? "true" : "false") + ",\"d3d12\":" + (a.d3d12 ? "true" : "false") + "}";
  }
  j += "],\"providers\":[";
  std::vector<std::string> ps;
  if (ortOk) {
    ps.push_back("{\"id\":\"auto\",\"label\":\"自动（显存最大的显卡）\",\"kind\":\"gpu\",\"vendor\":\"\"}");
    if (o.dml) {
      for (auto& a : adapters) {
        if (a.software || !a.d3d12) continue;
        ps.push_back("{\"id\":\"dml:" + std::to_string(a.index) + "\",\"label\":\"DirectML · " + jsonEscape(a.name) +
                     "\",\"kind\":\"gpu\",\"vendor\":\"" + jsonEscape(a.vendor) + "\"}");
      }
    }
    if (std::find(o.available.begin(), o.available.end(), "CUDAExecutionProvider") != o.available.end()) {
      int k = 0;
      for (auto& a : adapters) {
        if (a.vendorId != 0x10DE) continue;
        ps.push_back("{\"id\":\"cuda:" + std::to_string(k) + "\",\"label\":\"CUDA · " + jsonEscape(a.name) +
                     "\",\"kind\":\"gpu\",\"vendor\":\"NVIDIA\"}");
        k++;
      }
    }
    for (auto& d : epDevices()) {
      ps.push_back("{\"id\":\"" + jsonEscape(d.id) + "\",\"label\":\"" + jsonEscape(d.label) + "\",\"kind\":\"" + d.kind +
                   "\",\"vendor\":\"" + jsonEscape(d.vendor) + "\"}");
    }
    ps.push_back("{\"id\":\"cpu\",\"label\":\"CPU（很慢，仅用于测试）\",\"kind\":\"cpu\",\"vendor\":\"\"}");
  }
  for (size_t i = 0; i < ps.size(); i++) j += (i ? "," : "") + ps[i];
  j += "]}";
  return j;
}

// ============================================================ model helpers

namespace {

uint16_t f2h(float f) {
  uint32_t x;
  memcpy(&x, &f, 4);
  uint32_t sign = (x >> 16) & 0x8000;
  int32_t exp = static_cast<int32_t>((x >> 23) & 0xFF) - 127 + 15;
  uint32_t mant = x & 0x7FFFFF;
  if (exp <= 0) {
    if (exp < -10) return static_cast<uint16_t>(sign);
    mant |= 0x800000;
    uint32_t t = 14 - exp;
    uint32_t h = mant >> t;
    if ((mant >> (t - 1)) & 1) h++;
    return static_cast<uint16_t>(sign | h);
  }
  if (exp >= 31) return static_cast<uint16_t>(sign | 0x7C00 | (((x >> 23) & 0xFF) == 0xFF && mant ? 0x200 : 0));
  uint16_t h = static_cast<uint16_t>(sign | (exp << 10) | (mant >> 13));
  if (mant & 0x1000) h++;
  return h;
}

float h2f(uint16_t h) {
  uint32_t sign = (h & 0x8000u) << 16, exp = (h >> 10) & 0x1F, mant = h & 0x3FF, x;
  if (exp == 0) {
    if (mant == 0) {
      x = sign;
    } else {
      exp = 127 - 15 + 1;
      while (!(mant & 0x400)) {
        mant <<= 1;
        exp--;
      }
      mant &= 0x3FF;
      x = sign | (exp << 23) | (mant << 13);
    }
  } else if (exp == 31) {
    x = sign | 0x7F800000 | (mant << 13);
  } else {
    x = sign | ((exp - 15 + 127) << 23) | (mant << 13);
  }
  float f;
  memcpy(&f, &x, 4);
  return f;
}

struct InputInfo {
  std::string name;
  ONNXTensorElementDataType type;
  std::vector<int64_t> dims;
  std::vector<std::string> sym;
};

}  // namespace

struct Session {
  OrtSession* s = nullptr;
  std::string label;  // human readable provider ("DirectML · NVIDIA ...")
  std::vector<InputInfo> inputs;
  std::vector<std::string> outputs;
  std::map<std::string, std::string> meta;

  ~Session() {
    if (s) ort().api->ReleaseSession(s);
  }
  const InputInfo* input(const std::string& n) const {
    for (auto& i : inputs) {
      if (i.name == n) return &i;
    }
    return nullptr;
  }
};

namespace {

// Reads input/output names, types and symbolic dims without creating a full session
// on the GPU (CPU session with minimal optimization).
void introspect(OrtSession* s, Session& out) {
  auto* api = ort().api;
  OrtAllocator* alloc = nullptr;
  check(api->GetAllocatorWithDefaultOptions(&alloc));
  size_t n = 0;
  check(api->SessionGetInputCount(s, &n));
  for (size_t i = 0; i < n; i++) {
    char* name = nullptr;
    check(api->SessionGetInputName(s, i, alloc, &name));
    InputInfo info;
    info.name = name;
    api->AllocatorFree(alloc, name);
    OrtTypeInfo* ti = nullptr;
    check(api->SessionGetInputTypeInfo(s, i, &ti));
    const OrtTensorTypeAndShapeInfo* tsi = nullptr;
    check(api->CastTypeInfoToTensorInfo(ti, &tsi));
    check(api->GetTensorElementType(tsi, &info.type));
    size_t nd = 0;
    check(api->GetDimensionsCount(tsi, &nd));
    info.dims.resize(nd);
    check(api->GetDimensions(tsi, info.dims.data(), nd));
    std::vector<const char*> sym(nd, nullptr);
    check(api->GetSymbolicDimensions(tsi, sym.data(), nd));
    for (auto p : sym) info.sym.push_back(p ? p : "");
    api->ReleaseTypeInfo(ti);
    out.inputs.push_back(info);
  }
  check(api->SessionGetOutputCount(s, &n));
  for (size_t i = 0; i < n; i++) {
    char* name = nullptr;
    check(api->SessionGetOutputName(s, i, alloc, &name));
    out.outputs.push_back(name);
    api->AllocatorFree(alloc, name);
  }
  OrtModelMetadata* md = nullptr;
  if (!api->SessionGetModelMetadata(s, &md) && md) {
    char* v = nullptr;
    if (!api->ModelMetadataLookupCustomMetadataMap(md, alloc, "metadata", &v) && v) {
      out.meta["metadata"] = v;
      api->AllocatorFree(alloc, v);
    }
    api->ReleaseModelMetadata(md);
  }
}

// Tiny JSON value lookup for flat metadata ({"samplingRate": 40000, "f0": true, ...}).
std::string metaValue(const std::string& json, const std::string& key) {
  auto p = json.find("\"" + key + "\"");
  if (p == std::string::npos) return "";
  p = json.find(':', p);
  if (p == std::string::npos) return "";
  p++;
  while (p < json.size() && (json[p] == ' ' || json[p] == '"')) p++;
  auto e = p;
  while (e < json.size() && json[e] != ',' && json[e] != '}' && json[e] != '"') e++;
  return json.substr(p, e - p);
}

// PULSE_MODELS_DIR overrides the bundled ai\models folder (CML installs the weights as a separate add-on).
std::wstring modelsDir() {
  wchar_t buf[1024];
  const DWORD n = GetEnvironmentVariableW(L"PULSE_MODELS_DIR", buf, 1024);
  if (n > 0 && n < 1024) {
    std::wstring d(buf, n);
    if (d.back() != L'\\' && d.back() != L'/') d += L'\\';
    return d;
  }
  return moduleDirW() + L"ai\\models\\";
}

bool fileExists(const std::wstring& p) {
  DWORD a = GetFileAttributesW(p.c_str());
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

}  // namespace

// ============================================================ pipeline

struct AiVoice::Impl {
  std::shared_ptr<Session> hubert, rmvpe, gen;  // shared with the session cache
  OrtMemoryInfo* mem = nullptr;
  int T = 0;            // generator frames per step (10 ms each)
  int blockF = 0, fadeF = 0, marginF = 2;
  int upp = 400;        // model samples per frame
  int rate = 40000, speakers = 1;
  bool genHasRnd = false, featsHalf = false;
  std::vector<float> rnd;
  std::vector<float> melFb;  // 128 x 513
  std::vector<float> window;  // hann 1024
  Resampler up;               // model rate -> 48k
  std::string provider, providerLabel, modelPath;
  int blockMs = 200, extraMs = 300;

  ~Impl() {
    if (mem) ort().api->ReleaseMemoryInfo(mem);
  }
};

static constexpr int kHubertLen = 32000;   // fixed 2 s input of the bundled HuBERT
static constexpr int kMelFrames = 128;     // RMVPE window (1.28 s), multiple of 32
static constexpr int kMelLen = (kMelFrames - 1) * 160;
static constexpr int kHist = kHubertLen;
static constexpr size_t kMaxCachedGenerators = 5;  // each fixed-T generator session costs ~100-300 MB VRAM
static constexpr uint64_t kPrewarmMinVramMB = 6000;  // only pre-compile presets on cards with room to spare

AiVoice::AiVoice() : out48_(48000 * 4) {
  down_.init(kRate, 16000);
  hist16_.assign(kHist, 0.f);
  loader_ = std::thread([this] { loaderLoop(); });
}

AiVoice::~AiVoice() {
  {
    std::lock_guard<std::mutex> lk(loadMu_);
    quit_ = true;
  }
  loadCv_.notify_all();
  if (loader_.joinable()) loader_.join();
  stopWorker_ = true;
  cv_.notify_all();
  if (worker_.joinable()) worker_.join();
  std::lock_guard<std::mutex> lk(mu_);
  impl_.reset();
  cache_.clear();
}

void AiVoice::setState(int s, const std::string& err) {
  state_.store(s);
  {
    std::lock_guard<std::mutex> lk(mu_);
    error_ = err;
  }
  std::string j = statusJson();
  emit(PN_EV_VC_STATUS, s, 0, j.data(), static_cast<int32_t>(j.size()));
}

std::string AiVoice::statusJson() {
  std::lock_guard<std::mutex> lk(mu_);
  return "{\"state\":" + std::to_string(state_.load()) + ",\"provider\":\"" + jsonEscape(providerId_) +
         "\",\"providerLabel\":\"" + jsonEscape(providerLabel_) + "\",\"model\":\"" + jsonEscape(modelPath_) +
         "\",\"sampleRate\":" + std::to_string(modelRate_) + ",\"speakers\":" + std::to_string(speakers_) +
         ",\"latencyMs\":" + std::to_string(latencyMs_.load()) + ",\"inferMs\":" + std::to_string(inferMs_.load()) +
         ",\"underruns\":" + std::to_string(underruns_.load()) + ",\"blockMs\":" + std::to_string(blockMs_) +
         ",\"extraMs\":" + std::to_string(extraMs_) + ",\"switching\":" + (switching_.load() ? "true" : "false") +
         ",\"error\":\"" + jsonEscape(error_) + "\"}";
}

int AiVoice::configure(const std::string& provider, const std::string& model, int blockMs, int extraMs, int speaker) {
  speaker_.store(speaker);
  {
    std::lock_guard<std::mutex> lk(loadMu_);
    pending_ = {provider, model, blockMs, extraMs};
    havePending_ = true;
    unloadPending_ = false;
  }
  loadCv_.notify_all();
  return 0;
}

void AiVoice::unload() {
  {
    std::lock_guard<std::mutex> lk(loadMu_);
    havePending_ = false;
    unloadPending_ = true;
  }
  loadCv_.notify_all();
}

std::shared_ptr<Session> AiVoice::cached(const std::string& key, const std::function<std::shared_ptr<Session>()>& make) {
  auto it = cache_.find(key);
  if (it != cache_.end()) {
    if (key.rfind("gen|", 0) == 0) {
      genLru_.erase(std::remove(genLru_.begin(), genLru_.end(), key), genLru_.end());
      genLru_.push_back(key);
    }
    return it->second;
  }
  auto s = make();
  cache_[key] = s;
  if (key.rfind("gen|", 0) == 0) {
    genLru_.push_back(key);
    while (genLru_.size() > kMaxCachedGenerators) {
      cache_.erase(genLru_.front());  // still alive while a running Impl references it
      genLru_.erase(genLru_.begin());
    }
  }
  return s;
}

void AiVoice::resetBuffersLocked(const Impl& im) {
  hist16_.assign(kHist, 0.f);
  newSamples_ = 0;
  prevTail_.assign(static_cast<size_t>(im.fadeF) * im.upp, 0.f);
  primed_ = false;
  out48_.clear();
  down_.reset();
}

// "auto" → DirectML on the D3D12 hardware adapter with the most dedicated VRAM (else CPU).
static std::string resolveProvider(const std::string& provider) {
  if (provider != "auto" && !provider.empty()) return provider;
  int best = -1;
  uint64_t vram = 0;
  for (auto& a : enumerateAdapters()) {
    if (!a.software && a.d3d12 && (best < 0 || a.vramMB > vram)) {
      best = a.index;
      vram = a.vramMB;
    }
  }
  return best >= 0 && ort().dml ? "dml:" + std::to_string(best) : "cpu";
}

static OrtSession* createSession(const std::wstring& path, const std::string& provider, int fixedT,
                                 const std::vector<std::string>& timeDims, std::string& label) {
  auto& o = ort();
  auto* api = o.api;
  OrtSessionOptions* so = nullptr;
  check(api->CreateSessionOptions(&so));
  struct Guard {
    OrtSessionOptions* so;
    ~Guard() { ort().api->ReleaseSessionOptions(so); }
  } g{so};
  check(api->SetSessionGraphOptimizationLevel(so, ORT_ENABLE_ALL));
  check(api->SetSessionLogSeverityLevel(so, 3));
  // Fixed shapes let DirectML compile one optimized graph (dynamic shapes are ~10x slower).
  for (auto& d : timeDims) {
    if (!d.empty()) check(api->AddFreeDimensionOverrideByName(so, d.c_str(), fixedT));
  }
  std::string p = resolveProvider(provider);
  if (p.rfind("dml:", 0) == 0) {
    if (!o.dml) throw std::runtime_error("this onnxruntime build has no DirectML support");
    check(api->DisableMemPattern(so));
    check(api->SetSessionExecutionMode(so, ORT_SEQUENTIAL));
    int dev = std::stoi(p.substr(4));
    check(o.dml->SessionOptionsAppendExecutionProvider_DML(so, dev));
    label = "DirectML";
    for (auto& a : enumerateAdapters()) {
      if (a.index == dev) label = "DirectML · " + a.name;
    }
  } else if (p.rfind("cuda:", 0) == 0) {
    OrtCUDAProviderOptionsV2* cu = nullptr;
    check(api->CreateCUDAProviderOptions(&cu));
    std::string id = p.substr(5);
    const char* k[] = {"device_id", "cudnn_conv_algo_search"};
    const char* v[] = {id.c_str(), "HEURISTIC"};
    OrtStatus* st = api->UpdateCUDAProviderOptions(cu, k, v, 2);
    if (!st) st = api->SessionOptionsAppendExecutionProvider_CUDA_V2(so, cu);
    api->ReleaseCUDAProviderOptions(cu);
    check(st);
    label = "CUDA · GPU " + id;
  } else if (p.rfind("ep:", 0) == 0) {
    const OrtEpDevice* dev = nullptr;
    for (auto& d : epDevices()) {
      if (d.id == p) {
        dev = d.dev;
        label = d.label;
      }
    }
    if (!dev) throw std::runtime_error("execution provider device " + p + " not found");
    check(api->SessionOptionsAppendExecutionProvider_V2(so, o.env, &dev, 1, nullptr, nullptr, 0));
  } else {
    check(api->SetIntraOpNumThreads(so, 4));
    label = "CPU";
  }
  OrtSession* s = nullptr;
  check(api->CreateSession(o.env, path.c_str(), so, &s));
  return s;
}

// Cache key of the generator session for a config (same T ⇒ same compiled graph).
std::string AiVoice::genKey(const Config& c) {
  const int blockMs = std::clamp(c.blockMs / 10 * 10, 50, 500);
  const int fadeMs = std::min(40, blockMs / 2);
  const int extraMs = std::clamp(c.extraMs / 10 * 10, 50, 1200 - blockMs - fadeMs - 20);
  const int T = (extraMs + blockMs + fadeMs) / 10 + 2;
  const std::wstring genPath = c.model.empty() ? modelsDir() + L"rvc_base_40k.onnx" : widen(c.model);
  return "gen|" + resolveProvider(c.provider) + "|" + narrow(genPath) + "|" + std::to_string(T);
}

uint64_t AiVoice::vramOf(const std::string& provider) {
  if (provider.rfind("dml:", 0) != 0) return provider.rfind("cpu", 0) == 0 ? 0 : kPrewarmMinVramMB;  // CUDA / plugin EPs: assume dGPU
  const int idx = std::atoi(provider.c_str() + 4);
  for (auto& a : enumerateAdapters()) {
    if (a.index == idx) return a.vramMB;
  }
  return 0;
}

void AiVoice::setPrewarm(const std::vector<std::pair<int, int>>& presets) {
  std::lock_guard<std::mutex> lk(loadMu_);
  prewarm_ = presets;
}

void AiVoice::emitStatus() {
  std::string j = statusJson();
  emit(PN_EV_VC_STATUS, state_.load(), 0, j.data(), static_cast<int32_t>(j.size()));
}

// Single loader thread: always applies only the newest request (slider drags coalesce),
// builds the new pipeline while the old one keeps converting, then swaps without a gap.
void AiVoice::loaderLoop() {
  for (;;) {
    Config c;
    bool doUnload = false;
    {
      std::unique_lock<std::mutex> lk(loadMu_);
      // idle: pre-compile preset shapes so switching between them is instant
      while (!quit_ && !havePending_ && !unloadPending_ && !prewarmQueue_.empty() && state_.load() == PN_VC_STATE_RUNNING) {
        auto [b, e] = prewarmQueue_.front();
        prewarmQueue_.erase(prewarmQueue_.begin());
        Config pc = lastConfig_;
        pc.blockMs = b;
        pc.extraMs = e;
        if (cache_.count(genKey(pc))) continue;  // already compiled
        lk.unlock();
        std::shared_ptr<Impl> tmp;
        std::string perr;
        const auto t0 = std::chrono::steady_clock::now();
        if (build(pc, tmp, perr)) {
          logi("AI voice preset " + std::to_string(b) + "/" + std::to_string(e) + " ms pre-compiled in " +
               std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count()) + " ms");
        }
        lk.lock();
      }
      loadCv_.wait(lk, [&] { return quit_ || havePending_ || unloadPending_; });
      if (quit_) return;
      if (unloadPending_) {
        unloadPending_ = false;
        doUnload = true;
      } else {
        // debounce: wait until requests stop arriving for 150 ms (slider drags, typing)
        for (;;) {
          c = pending_;
          havePending_ = false;
          if (!loadCv_.wait_for(lk, std::chrono::milliseconds(150), [&] { return quit_ || havePending_ || unloadPending_; })) break;
          if (quit_ || unloadPending_) break;
        }
        if (quit_) return;
        if (unloadPending_) continue;
      }
    }
    if (doUnload) {
      state_.store(PN_VC_STATE_OFF);  // audio thread stops calling push/pull first
      stopWorker_ = true;
      cv_.notify_all();
      if (worker_.joinable()) worker_.join();
      stopWorker_ = false;
      {
        std::lock_guard<std::mutex> lk(mu_);
        impl_.reset();
        out48_.clear();
        primed_ = false;
      }
      cache_.clear();  // release GPU memory
      genLru_.clear();
      setState(PN_VC_STATE_OFF);
      continue;
    }
    const bool hot = state_.load() == PN_VC_STATE_RUNNING;
    switching_ = hot;
    if (hot) {
      emitStatus();
    } else {
      setState(PN_VC_STATE_LOADING);
    }
    std::shared_ptr<Impl> next;
    std::string err;
    auto t0 = std::chrono::steady_clock::now();
    const bool ok = build(c, next, err);
    switching_ = false;
    {
      std::lock_guard<std::mutex> lk(loadMu_);
      if (havePending_ || unloadPending_) continue;  // superseded while building
    }
    if (!ok) {
      loge("AI voice load failed: " + err);
      if (!hot) {
        std::lock_guard<std::mutex> lk(mu_);
        impl_.reset();
      }
      // a failed hot switch keeps the working pipeline and only reports the error
      setState(hot ? PN_VC_STATE_RUNNING : PN_VC_STATE_ERROR, err);
      continue;
    }
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    {
      std::lock_guard<std::mutex> lk(mu_);
      const bool keepHistory = impl_ != nullptr;  // hot swap: keep the 16 kHz history, only shapes changed
      impl_ = next;
      providerId_ = next->provider;
      providerLabel_ = next->providerLabel;
      modelPath_ = next->modelPath;
      modelRate_ = next->rate;
      speakers_ = next->speakers;
      blockMs_ = next->blockMs;
      extraMs_ = next->extraMs;
      if (keepHistory) {
        prevTail_.assign(static_cast<size_t>(next->fadeF) * next->upp, 0.f);
        newSamples_ = std::min(newSamples_, static_cast<size_t>(next->blockF) * 160);
      } else {
        resetBuffersLocked(*next);
      }
    }
    extraLatMs_.store((next->fadeF + next->marginF) * 10);
    {
      // queue the other presets for background compilation (same provider + model)
      std::lock_guard<std::mutex> lk(loadMu_);
      lastConfig_ = c;
      prewarmQueue_.clear();
      if (vramOf(next->provider) >= kPrewarmMinVramMB) {
        for (auto& pr : prewarm_) {
          if (pr.first != c.blockMs || pr.second != c.extraMs) prewarmQueue_.push_back(pr);
        }
      }
    }
    logi("AI voice " + std::string(hot ? "switched" : "ready") + " on " + next->providerLabel + " in " + std::to_string(ms) +
         " ms (block " + std::to_string(next->blockMs) + " ms, context " + std::to_string(next->extraMs) + " ms)");
    underruns_ = 0;
    if (!inline_ && !worker_.joinable()) worker_ = std::thread([this] { workerLoop(); });
    setState(PN_VC_STATE_RUNNING);
  }
}

bool AiVoice::build(const Config& c, std::shared_ptr<Impl>& out, std::string& err) {
  try {
    if (!loadOrt()) throw std::runtime_error(ort().error);
    auto* api = ort().api;
    auto im = std::make_shared<Impl>();
    check(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &im->mem));

    const int blockMs = std::clamp(c.blockMs / 10 * 10, 50, 500);
    const int fadeMs = std::min(40, blockMs / 2);
    // generator context: extra + block + fade + margin must fit the 1.28 s pitch window
    const int extraMs = std::clamp(c.extraMs / 10 * 10, 50, 1200 - blockMs - fadeMs - 20);
    im->blockF = blockMs / 10;
    im->fadeF = fadeMs / 10;
    im->T = (extraMs + blockMs + fadeMs) / 10 + im->marginF;
    im->blockMs = blockMs;
    im->extraMs = extraMs;
    im->provider = resolveProvider(c.provider);

    const std::wstring mdir = modelsDir();
    const std::wstring hubertPath = mdir + L"hubert_base_l12.onnx", rmvpePath = mdir + L"rmvpe.onnx";
    const std::wstring genPath = c.model.empty() ? mdir + L"rvc_base_40k.onnx" : widen(c.model);
    for (auto& p : {hubertPath, rmvpePath, genPath}) {
      if (!fileExists(p)) throw std::runtime_error("model file missing: " + narrow(p));
    }
    im->modelPath = narrow(genPath);

    // generator description: names, dtypes, symbolic dims, metadata (cached per model file)
    auto info = cached("info|" + im->modelPath, [&] {
      auto s = std::make_shared<Session>();
      std::string l;
      OrtSession* tmp = createSession(genPath, "cpu", 1, {}, l);
      try {
        introspect(tmp, *s);
      } catch (...) {
        api->ReleaseSession(tmp);
        throw;
      }
      api->ReleaseSession(tmp);
      return s;
    });
    std::string meta = info->meta["metadata"];
    int rate = std::atoi(metaValue(meta, "samplingRate").c_str());
    if (rate <= 0) rate = 40000;
    if (rate % 100 != 0) throw std::runtime_error("unsupported model sample rate " + std::to_string(rate));
    const std::string emb = metaValue(meta, "embChannels");
    if (!emb.empty() && emb != "768") throw std::runtime_error("only RVC v2 models (768-dim HuBERT features) are supported");
    if (metaValue(meta, "f0") == "false" || !info->input("pitchf")) {
      throw std::runtime_error("model has no pitch (f0) input; only f0 RVC models are supported");
    }
    for (auto n : {"feats", "p_len", "pitch", "sid"}) {
      if (!info->input(n)) throw std::runtime_error(std::string("model is missing input '") + n + "'");
    }
    const int spk = std::atoi(metaValue(meta, "speakers").c_str());
    im->rate = rate;
    im->speakers = spk > 0 ? spk : 1;
    im->upp = rate / 100;
    im->genHasRnd = info->input("rnd") != nullptr;
    im->featsHalf = info->input("feats")->type == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16;
    std::vector<std::string> timeDims;
    for (auto& in : info->inputs) {
      if (in.name == "p_len" || in.name == "sid") continue;
      for (size_t d = 0; d < in.sym.size(); d++) {
        // feats [1,T,768], pitch/pitchf [1,T], rnd [1,192,T]
        if (in.dims[d] < 0 && !in.sym[d].empty() && d > 0) timeDims.push_back(in.sym[d]);
      }
    }

    auto make = [&](const std::wstring& path, int fixedT, const std::vector<std::string>& dims) {
      auto s = std::make_shared<Session>();
      s->s = createSession(path, im->provider, fixedT, dims, s->label);
      return s;
    };
    // HuBERT / RMVPE shapes never change: one session per provider, shared by every config.
    im->hubert = cached("hubert|" + im->provider, [&] { return make(hubertPath, 0, {}); });
    im->rmvpe = cached("rmvpe|" + im->provider, [&] { return make(rmvpePath, kMelFrames, {"time"}); });
    bool fresh = false;
    im->gen = cached(genKey(c), [&] {
      fresh = true;
      auto s = make(genPath, im->T, timeDims);
      s->inputs = info->inputs;
      s->outputs = info->outputs;
      return s;
    });
    im->providerLabel = im->gen->label;

    // mel filterbank (librosa: htk=True, norm='slaney'), sr 16k, n_fft 1024, fmin 30, fmax 8000
    {
      const int nMels = 128, nBins = 513;
      auto hz2mel = [](double f) { return 2595.0 * std::log10(1.0 + f / 700.0); };
      auto mel2hz = [](double m) { return 700.0 * (std::pow(10.0, m / 2595.0) - 1.0); };
      std::vector<double> pts(nMels + 2);
      const double lo = hz2mel(30), hi = hz2mel(8000);
      for (int i = 0; i < nMels + 2; i++) pts[i] = mel2hz(lo + (hi - lo) * i / (nMels + 1));
      im->melFb.assign(nMels * nBins, 0.f);
      for (int m = 0; m < nMels; m++) {
        const double enorm = 2.0 / (pts[m + 2] - pts[m]);
        for (int b = 0; b < nBins; b++) {
          const double f = 8000.0 * b / (nBins - 1);
          const double lower = (f - pts[m]) / (pts[m + 1] - pts[m]);
          const double upper = (pts[m + 2] - f) / (pts[m + 2] - pts[m + 1]);
          im->melFb[m * nBins + b] = static_cast<float>(std::max(0.0, std::min(lower, upper)) * enorm);
        }
      }
      im->window.resize(1024);
      for (int i = 0; i < 1024; i++) im->window[i] = static_cast<float>(0.5 - 0.5 * std::cos(2 * 3.14159265358979 * i / 1024));
    }
    std::mt19937 rng(1234);
    std::normal_distribution<float> nd(0.f, 1.f);
    im->rnd.resize(192 * static_cast<size_t>(im->T));
    for (auto& x : im->rnd) x = nd(rng);
    im->up.init(rate, kRate);

    // warm-up on silence: the first DirectML run of a new shape compiles kernels
    if (fresh) {
      std::vector<float> silence(kHist, 0.f), tail(static_cast<size_t>(im->fadeF) * im->upp, 0.f), o;
      Resampler up(rate, kRate);
      infer(*im, silence, tail, up, o, 0.f, 0);
    }
    out = im;
    return true;
  } catch (const std::exception& e) {
    err = e.what();
    return false;
  }
}

void AiVoice::push(const float* in48, int n) {
  if (state_.load() != PN_VC_STATE_RUNNING) return;
  std::vector<float> tmp;
  tmp.reserve(n / 3 + 4);
  {
    std::lock_guard<std::mutex> lk(mu_);
    if (resetRequested_.exchange(false) && impl_) resetBuffersLocked(*impl_);
    down_.process(in48, n, tmp);
    if (tmp.size() >= hist16_.size()) {
      std::copy(tmp.end() - hist16_.size(), tmp.end(), hist16_.begin());
    } else {
      std::move(hist16_.begin() + tmp.size(), hist16_.end(), hist16_.begin());
      std::copy(tmp.begin(), tmp.end(), hist16_.end() - tmp.size());
    }
    newSamples_ += tmp.size();
  }
  if (inline_) {
    while (step()) {
    }
  } else {
    cv_.notify_one();
  }
}

bool AiVoice::pull(float* out48, int n) {
  if (state_.load() != PN_VC_STATE_RUNNING) return false;
  const size_t block48 = static_cast<size_t>(blockMs_) * 48;
  if (!primed_) {
    if (out48_.size() < static_cast<size_t>(n) + block48 / 4) return false;
    primed_ = true;
  }
  const size_t got = out48_.read(out48, n);
  if (got < static_cast<size_t>(n)) {
    std::fill(out48 + got, out48 + n, 0.f);
    underruns_++;
    primed_ = false;
  }
  // keep latency bounded after stalls (e.g. GPU busy with a game)
  while (out48_.size() > block48 * 2 + 4800) {
    float junk[480];
    out48_.read(junk, 480);
  }
  latencyMs_.store(blockMs_ + static_cast<int>(out48_.size() / 48) + extraLatMs_.load() + inferMs_.load());
  return true;
}

void AiVoice::workerLoop() {
#ifdef _WIN32
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
#endif
  while (!stopWorker_) {
    {
      std::unique_lock<std::mutex> lk(mu_);
      cv_.wait_for(lk, std::chrono::milliseconds(100), [&] {
        return stopWorker_ || (impl_ && newSamples_ >= static_cast<size_t>(impl_->blockF) * 160);
      });
    }
    if (stopWorker_) break;
    while (!stopWorker_ && step()) {
    }
  }
}

namespace {

struct Tensor {
  OrtValue* v = nullptr;
  ~Tensor() {
    if (v) ort().api->ReleaseValue(v);
  }
};

void makeTensor(OrtMemoryInfo* mem, void* data, size_t bytes, std::vector<int64_t> shape, ONNXTensorElementDataType t,
                Tensor& out) {
  check(ort().api->CreateTensorWithDataAsOrtValue(mem, data, bytes, shape.data(), shape.size(), t, &out.v));
}

// Runs a session with the given inputs, returning the first output as float.
std::vector<float> run1(OrtSession* s, const std::vector<const char*>& names, const std::vector<OrtValue*>& vals,
                        const char* outName, std::vector<int64_t>* outShape = nullptr) {
  auto* api = ort().api;
  OrtValue* out = nullptr;
  check(api->Run(s, nullptr, names.data(), vals.data(), vals.size(), &outName, 1, &out));
  Tensor guard{out};
  OrtTensorTypeAndShapeInfo* ti = nullptr;
  check(api->GetTensorTypeAndShape(out, &ti));
  size_t count = 0, nd = 0;
  ONNXTensorElementDataType et;
  api->GetTensorShapeElementCount(ti, &count);
  api->GetTensorElementType(ti, &et);
  api->GetDimensionsCount(ti, &nd);
  if (outShape) {
    outShape->resize(nd);
    api->GetDimensions(ti, outShape->data(), nd);
  }
  api->ReleaseTensorTypeAndShapeInfo(ti);
  void* p = nullptr;
  check(api->GetTensorMutableData(out, &p));
  std::vector<float> r(count);
  if (et == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16) {
    auto* h = static_cast<uint16_t*>(p);
    for (size_t i = 0; i < count; i++) r[i] = h2f(h[i]);
  } else {
    memcpy(r.data(), p, count * sizeof(float));
  }
  return r;
}

}  // namespace

bool AiVoice::step() {
  std::shared_ptr<Impl> im;
  std::vector<float> win(kHist);
  {
    std::lock_guard<std::mutex> lk(mu_);
    im = impl_;
    if (!im) return false;
    const size_t block16 = static_cast<size_t>(im->blockF) * 160;
    if (newSamples_ < block16) return false;
    // window ends exactly at the block boundary even if the worker is behind
    const size_t ahead = std::min(newSamples_ - block16, win.size());
    std::fill(win.begin(), win.begin() + ahead, 0.f);
    std::copy(hist16_.begin(), hist16_.end() - ahead, win.begin() + ahead);
    newSamples_ -= block16;
  }
  const auto t0 = std::chrono::steady_clock::now();
  std::vector<float> out;
  try {
    std::vector<float> tail;
    {
      std::lock_guard<std::mutex> lk(mu_);
      if (impl_ != im) return true;  // swapped while we copied the window: next round uses the new pipeline
      tail = prevTail_;
    }
    infer(*im, win, tail, im->up, out, pitch_.load(), speaker_.load());
    std::lock_guard<std::mutex> lk(mu_);
    if (impl_ != im) return true;  // a hot swap happened during inference: drop this block
    prevTail_ = std::move(tail);
    out48_.write(out.data(), out.size());
  } catch (const std::exception& e) {
    loge(std::string("AI voice inference failed: ") + e.what());
    stopWorker_ = true;
    setState(PN_VC_STATE_ERROR, e.what());
    return false;
  }
  const int ms = static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count());
  inferMs_.store(inferMs_.load() == 0 ? ms : (inferMs_.load() * 7 + ms * 3) / 10);
  return true;
}

// One block of the RVC pipeline on a 2 s 16 kHz window. Updates [tail] (crossfade
// state) and appends 48 kHz output to [out]. Throws on inference errors.
void AiVoice::infer(Impl& rim, const std::vector<float>& win, std::vector<float>& prevTail, Resampler& up, std::vector<float>& out48,
                    float pitch, int speaker) {
  Impl* im = &rim;
  const int T = im->T;
  {
    // ---- HuBERT content features: 2 s window -> 99 frames @50 fps -> repeat x2 -> last T
    std::vector<float> feats(static_cast<size_t>(T) * 768);
    {
      Tensor x;
      makeTensor(im->mem, const_cast<float*>(win.data()), win.size() * 4, {1, kHubertLen}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, x);
      std::vector<int64_t> shp;
      auto h = run1(im->hubert->s, {"source"}, {x.v}, "features", &shp);
      int nf = static_cast<int>(shp.size() >= 2 ? shp[1] : 99);
      // frames at 100 fps aligned to the end of the window
      int total = nf * 2;
      for (int t = 0; t < T; t++) {
        int f100 = total - T + t + 2;  // +2: hubert covers 1.98 s of the 2 s window
        int src = std::clamp(f100 / 2, 0, nf - 1);
        memcpy(&feats[static_cast<size_t>(t) * 768], &h[static_cast<size_t>(src) * 768], 768 * 4);
      }
    }
    // ---- RMVPE pitch on the last 1.28 s
    std::vector<float> f0(T, 0.f);
    {
      const int nBins = 513;
      std::vector<float> seg(win.end() - kMelLen, win.end());
      // reflect pad 512 (center=True)
      std::vector<float> padded(kMelLen + 1024);
      for (int i = 0; i < 512; i++) {
        padded[i] = seg[512 - i];
        padded[kMelLen + 512 + i] = seg[kMelLen - 2 - i];
      }
      std::copy(seg.begin(), seg.end(), padded.begin() + 512);
      std::vector<float> mel(static_cast<size_t>(128) * kMelFrames);
      std::vector<std::complex<float>> buf(1024);
      std::vector<float> mag(nBins);
      for (int fr = 0; fr < kMelFrames; fr++) {
        for (int i = 0; i < 1024; i++) buf[i] = {padded[fr * 160 + i] * im->window[i], 0.f};
        fft(buf, false);
        for (int b = 0; b < nBins; b++) mag[b] = std::abs(buf[b]);
        for (int m = 0; m < 128; m++) {
          const float* w = &im->melFb[static_cast<size_t>(m) * nBins];
          float acc = 0;
          for (int b = 0; b < nBins; b++) acc += w[b] * mag[b];
          mel[static_cast<size_t>(m) * kMelFrames + fr] = std::log(std::max(acc, 1e-5f));
        }
      }
      Tensor x;
      makeTensor(im->mem, mel.data(), mel.size() * 4, {1, 128, kMelFrames}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, x);
      auto sal = run1(im->rmvpe->s, {"input"}, {x.v}, "output");  // [1, frames, 360]
      const float key = std::pow(2.f, pitch / 12.f);
      for (int t = 0; t < T; t++) {
        int fr = kMelFrames - 1 - T + t;  // mel frame 127 is centred on the window end
        const float* s = &sal[static_cast<size_t>(fr) * 360];
        int am = static_cast<int>(std::max_element(s, s + 360) - s);
        if (s[am] <= 0.03f) continue;
        float num = 0, den = 0;
        for (int k = std::max(0, am - 4); k <= std::min(359, am + 4); k++) {
          num += s[k] * (20.f * k + 1997.3794f);
          den += s[k];
        }
        float hz = 10.f * std::pow(2.f, (num / den) / 1200.f);
        f0[t] = hz * key;
      }
    }
    // coarse pitch (RVC mel mapping)
    std::vector<int64_t> coarse(T);
    {
      const float mmin = 1127.f * std::log(1.f + 50.f / 700.f), mmax = 1127.f * std::log(1.f + 1100.f / 700.f);
      for (int t = 0; t < T; t++) {
        float m = 1127.f * std::log(1.f + f0[t] / 700.f);
        if (m > 0) m = (m - mmin) * 254.f / (mmax - mmin) + 1.f;
        coarse[t] = std::clamp<int64_t>(static_cast<int64_t>(std::lround(m)), 1, 255);
      }
    }
    // ---- generator
    std::vector<float> audio;
    {
      std::vector<const char*> names;
      std::vector<OrtValue*> vals;
      std::vector<Tensor> ts(6);
      std::vector<uint16_t> featsH;
      int64_t plen = T;
      int64_t sid = std::clamp(speaker, 0, std::max(0, im->speakers - 1));
      if (im->featsHalf) {
        featsH.resize(feats.size());
        for (size_t i = 0; i < feats.size(); i++) featsH[i] = f2h(feats[i]);
        makeTensor(im->mem, featsH.data(), featsH.size() * 2, {1, T, 768}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16, ts[0]);
      } else {
        makeTensor(im->mem, feats.data(), feats.size() * 4, {1, T, 768}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, ts[0]);
      }
      makeTensor(im->mem, &plen, 8, {1}, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, ts[1]);
      makeTensor(im->mem, coarse.data(), coarse.size() * 8, {1, T}, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, ts[2]);
      makeTensor(im->mem, f0.data(), f0.size() * 4, {1, T}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, ts[3]);
      makeTensor(im->mem, &sid, 8, {1}, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, ts[4]);
      names = {"feats", "p_len", "pitch", "pitchf", "sid"};
      for (int i = 0; i < 5; i++) vals.push_back(ts[i].v);
      if (im->genHasRnd) {
        makeTensor(im->mem, im->rnd.data(), im->rnd.size() * 4, {1, 192, T}, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, ts[5]);
        names.push_back("rnd");
        vals.push_back(ts[5].v);
      }
      audio = run1(im->gen->s, names, vals, im->gen->outputs[0].c_str());
    }
    // ---- assemble: region [T - margin - block - fade, T - margin) frames
    const int upp = im->upp;
    const int startF = T - im->marginF - im->blockF - im->fadeF;
    const int nF = im->blockF + im->fadeF;
    if (static_cast<int>(audio.size()) < (startF + nF) * upp) throw std::runtime_error("generator output too short");
    std::vector<float> seg(audio.begin() + static_cast<size_t>(startF) * upp, audio.begin() + static_cast<size_t>(startF + nF) * upp);
    // envelope: follow the input loudness per 10 ms frame (also gates hallucinated noise in silence)
    std::vector<float> g(nF + 1);
    const size_t winStart16 = win.size() - static_cast<size_t>(T) * 160;
    for (int f = 0; f < nF; f++) {
      const float* xi = &win[winStart16 + static_cast<size_t>(startF + f) * 160];
      float ei = 0, eo = 0;
      for (int i = 0; i < 160; i++) ei += xi[i] * xi[i];
      for (int i = 0; i < upp; i++) eo += seg[static_cast<size_t>(f) * upp + i] * seg[static_cast<size_t>(f) * upp + i];
      float ri = std::sqrt(ei / 160), ro = std::sqrt(eo / upp);
      float gain = ri < 2e-4f ? 0.f : std::pow(ri / std::max(ro, 1e-4f), 0.8f) * std::pow(ri, 0.2f) * 1.2f;
      g[f] = std::min(gain, 6.f);
    }
    g[nF] = g[nF - 1];
    for (int f = 0; f < nF; f++) {
      for (int i = 0; i < upp; i++) {
        float a = static_cast<float>(i) / upp;
        float gg = (f == 0 ? g[0] : g[f - 1] + (g[f] - g[f - 1]) * a);
        seg[static_cast<size_t>(f) * upp + i] *= gg;
      }
    }
    // crossfade with the previous tail
    const size_t fade = static_cast<size_t>(im->fadeF) * upp, blk = static_cast<size_t>(im->blockF) * upp;
    for (size_t i = 0; i < fade; i++) {
      float a = 0.5f - 0.5f * std::cos(3.14159265f * (i + 0.5f) / fade);
      seg[i] = (i < prevTail.size() ? prevTail[i] : 0.f) * (1 - a) + seg[i] * a;
    }
    prevTail.resize(fade, 0.f);
    std::copy(seg.begin() + blk, seg.begin() + blk + fade, prevTail.begin());
    const size_t before = out48.size();
    up.process(seg.data(), blk, out48);
    for (size_t i = before; i < out48.size(); i++) out48[i] = clampf(out48[i], -1.f, 1.f);
  }
}

}  // namespace pn
