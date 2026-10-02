// Shared internals of pulse_native.dll.
#pragma once
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "pulse_native.h"

namespace pn {

constexpr int kRate = 48000;       // engine sample rate (mono float)
constexpr int kFrame = 480;        // 10 ms processing frame (= RNNoise frame)
constexpr int kOpusFrame = 960;    // 20 ms Opus packet

// ---- events ----
void emit(int32_t type, int32_t a, int32_t b, const void* data = nullptr, int32_t len = 0);
void log(int level, const std::string& msg);
inline void logi(const std::string& m) { log(0, m); }
inline void logw(const std::string& m) { log(1, m); }
inline void loge(const std::string& m) { log(2, m); }

// Directory containing pulse_native.dll (with trailing backslash), UTF-8 and wide.
const std::string& moduleDir();
const std::wstring& moduleDirW();
std::wstring widen(const std::string& s);
std::string narrow(const std::wstring& s);
std::string jsonEscape(const std::string& s);

// Lock-free single-producer / single-consumer float ring buffer.
class Ring {
 public:
  explicit Ring(size_t cap = 0) { reset(cap); }
  void reset(size_t cap) {
    size_t n = 1;
    while (n < cap + 1) n <<= 1;
    buf_.assign(n, 0.f);
    mask_ = n - 1;
    r_.store(0);
    w_.store(0);
  }
  size_t size() const { return (w_.load(std::memory_order_acquire) - r_.load(std::memory_order_acquire)) & mask_; }
  size_t space() const { return mask_ - size(); }
  // Writes up to n samples, returns number written (drops the rest when full).
  size_t write(const float* p, size_t n) {
    size_t w = w_.load(std::memory_order_relaxed);
    size_t sp = mask_ - ((w - r_.load(std::memory_order_acquire)) & mask_);
    if (n > sp) n = sp;
    for (size_t i = 0; i < n; i++) buf_[(w + i) & mask_] = p ? p[i] : 0.f;
    w_.store((w + n) & mask_, std::memory_order_release);
    return n;
  }
  size_t read(float* p, size_t n) {
    size_t r = r_.load(std::memory_order_relaxed);
    size_t av = (w_.load(std::memory_order_acquire) - r) & mask_;
    if (n > av) n = av;
    for (size_t i = 0; i < n; i++) p[i] = buf_[(r + i) & mask_];
    r_.store((r + n) & mask_, std::memory_order_release);
    return n;
  }
  void clear() { r_.store(w_.load()); }

 private:
  std::vector<float> buf_;
  size_t mask_ = 0;
  std::atomic<size_t> r_{0}, w_{0};
};

inline float dbToLin(float db) { return std::pow(10.f, db / 20.f); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

}  // namespace pn

namespace pn {
void setBaseDir(const char* utf8);
char* dupString(const std::string& s);  // malloc'd copy (free with pn_free)
}  // namespace pn
