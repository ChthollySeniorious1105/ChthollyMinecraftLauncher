#include "dsp.h"

#include <algorithm>
#include <cmath>

namespace pn {

static constexpr double kPi = 3.14159265358979323846;

void Resampler::init(int inRate, int outRate) {
  in_ = inRate;
  out_ = outRate;
  step_ = static_cast<double>(inRate) / outRate;
  // Kaiser-windowed sinc, cutoff at the lower Nyquist with a little guard band.
  double cutoff = std::min(1.0, 1.0 / step_) * 0.92;
  table_.assign(kPhases * kTaps, 0.f);
  const double beta = 7.0;
  auto bessel0 = [](double x) {
    double s = 1, t = 1;
    for (int k = 1; k < 25; k++) {
      t *= (x / (2 * k)) * (x / (2 * k));
      s += t;
    }
    return s;
  };
  const double i0b = bessel0(beta);
  for (int p = 0; p < kPhases; p++) {
    double frac = static_cast<double>(p) / kPhases;
    double sum = 0;
    for (int k = 0; k < kTaps; k++) {
      double x = (k - (kTaps / 2 - 1)) - frac;  // distance from the output point
      double s = std::abs(x) < 1e-9 ? 1.0 : std::sin(kPi * cutoff * x) / (kPi * cutoff * x);
      double r = x / (kTaps / 2.0);
      double w = std::abs(r) >= 1 ? 0 : bessel0(beta * std::sqrt(1 - r * r)) / i0b;
      double v = cutoff * s * w;
      table_[p * kTaps + k] = static_cast<float>(v);
      sum += v;
    }
    for (int k = 0; k < kTaps; k++) table_[p * kTaps + k] = static_cast<float>(table_[p * kTaps + k] / sum);
  }
  reset();
}

void Resampler::reset() {
  hist_.assign(kTaps, 0.f);
  pos_ = kTaps / 2 - 1;
}

void Resampler::process(const float* in, size_t n, std::vector<float>& out) {
  if (in_ == out_) {
    out.insert(out.end(), in, in + n);
    return;
  }
  hist_.insert(hist_.end(), in, in + n);
  // produce while the full kernel window fits
  while (pos_ + kTaps / 2 + 1 < hist_.size()) {
    size_t base = static_cast<size_t>(pos_);
    double frac = pos_ - base;
    int ph = static_cast<int>(frac * kPhases);
    const float* t = &table_[ph * kTaps];
    const float* h = &hist_[base - (kTaps / 2 - 1)];
    float acc = 0.f;
    for (int k = 0; k < kTaps; k++) acc += t[k] * h[k];
    out.push_back(acc);
    pos_ += step_;
  }
  // drop consumed history, keep kTaps of context
  size_t keep_from = static_cast<size_t>(pos_) - (kTaps / 2 - 1);
  if (keep_from > 0 && keep_from <= hist_.size()) {
    hist_.erase(hist_.begin(), hist_.begin() + keep_from);
    pos_ -= keep_from;
  }
}

void fft(std::vector<std::complex<float>>& a, bool inverse) {
  const size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; i++) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    double ang = 2 * kPi / len * (inverse ? 1 : -1);
    std::complex<float> wl(static_cast<float>(std::cos(ang)), static_cast<float>(std::sin(ang)));
    for (size_t i = 0; i < n; i += len) {
      std::complex<float> w(1.f, 0.f);
      for (size_t j = 0; j < len / 2; j++) {
        auto u = a[i + j], v = a[i + j + len / 2] * w;
        a[i + j] = u + v;
        a[i + j + len / 2] = u - v;
        w *= wl;
      }
    }
  }
  if (inverse) {
    for (auto& x : a) x /= static_cast<float>(n);
  }
}

void PitchShifter::setSemitones(float st) { ratio_ = std::pow(2.f, clampf(st, -24.f, 24.f) / 12.f); }

void PitchShifter::reset() {
  std::fill(buf_.begin(), buf_.end(), 0.f);
  w_ = 0;
  phase_ = 0;
}

void PitchShifter::process(float* x, int n) {
  if (std::abs(ratio_ - 1.f) < 1e-3f) return;
  const int N = static_cast<int>(buf_.size());
  const double inc = (1.0 - ratio_) / kWindow;  // phase advance per sample
  for (int i = 0; i < n; i++) {
    buf_[w_] = x[i];
    double out = 0;
    for (int head = 0; head < 2; head++) {
      double ph = phase_ + head * 0.5;
      ph -= std::floor(ph);
      double delay = ph * kWindow + 4;  // samples behind the write head
      double rp = w_ - delay;
      while (rp < 0) rp += N;
      int i0 = static_cast<int>(rp);
      double fr = rp - i0;
      float s0 = buf_[i0 % N], s1 = buf_[(i0 + 1) % N];
      double v = s0 + (s1 - s0) * fr;
      double win = std::sin(kPi * ph);  // sin^2 crossfade sums to 1 for two heads
      out += v * win * win;
    }
    x[i] = static_cast<float>(out);
    phase_ += inc;
    phase_ -= std::floor(phase_);
    w_ = (w_ + 1) % N;
  }
}

void Robot::process(float* x, int n) {
  const double f = 70.0 / kRate;
  for (int i = 0; i < n; i++) {
    float m = static_cast<float>(std::sin(2 * kPi * ph_));
    ph_ += f;
    if (ph_ >= 1) ph_ -= 1;
    float v = x[i] * (0.35f + 0.65f * m);
    v = std::round(v * 96.f) / 96.f;
    x[i] = v * 1.3f;
  }
}

}  // namespace pn
