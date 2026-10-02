// Small DSP building blocks used by the capture chain and the voice changer.
#pragma once
#include <complex>
#include <vector>

#include "common.h"

namespace pn {

// Streaming windowed-sinc resampler for mono float (arbitrary ratio, fixed per instance).
// Quality is sufficient for speech; latency = taps/2 input samples.
class Resampler {
 public:
  Resampler() = default;
  Resampler(int inRate, int outRate) { init(inRate, outRate); }
  void init(int inRate, int outRate);
  // Appends converted samples of `in` to `out`.
  void process(const float* in, size_t n, std::vector<float>& out);
  void reset();
  int inRate() const { return in_; }
  int outRate() const { return out_; }

 private:
  int in_ = 0, out_ = 0;
  double step_ = 1.0;  // input samples per output sample
  double pos_ = 0.0;   // position in hist_ of the next output sample
  std::vector<float> hist_;
  std::vector<float> table_;  // kPhases x kTaps
  static constexpr int kTaps = 32, kPhases = 256;
};

// In-place radix-2 complex FFT (n = power of two).
void fft(std::vector<std::complex<float>>& a, bool inverse);

// Real-time pitch shifter for the DSP voice changer: two overlapping read heads
// on a delay line (granular / "Doppler" shifter) — cheap, ~40 ms latency.
class PitchShifter {
 public:
  void setSemitones(float st);
  void process(float* x, int n);
  void reset();

 private:
  std::vector<float> buf_ = std::vector<float>(8192, 0.f);
  int w_ = 0;
  double phase_ = 0.0;
  float ratio_ = 1.f;
  static constexpr int kWindow = 1920;  // 40 ms @ 48 kHz
};

// Ring modulator ("robot") + mild bitcrush.
class Robot {
 public:
  void process(float* x, int n);

 private:
  double ph_ = 0.0;
};

// Simple one-pole high-pass (DC / rumble removal).
class HighPass {
 public:
  void init(float cutoffHz, int rate) {
    float rc = 1.f / (2.f * 3.14159265f * cutoffHz);
    float dt = 1.f / rate;
    a_ = rc / (rc + dt);
  }
  float process(float x) {
    float y = a_ * (y_ + x - x_);
    x_ = x;
    y_ = y;
    return y;
  }

 private:
  float a_ = 0.99f, x_ = 0.f, y_ = 0.f;
};

}  // namespace pn
