// H.264 encoder on Media Foundation for screen sharing: hardware encoder MFTs (async,
// NVENC / Quick Sync / AMF) first, the Microsoft software encoder (sync) as fallback.
// Low-latency settings (no B-frames, CBR, 1-in-1-out). Output is Annex-B with SPS/PPS
// in front of every IDR access unit. Not thread-safe: use from one thread.
#pragma once
#include <functional>
#include <memory>

#include "common.h"

namespace pn {

class H264Encoder {
 public:
  // Called for every encoded access unit.
  using Sink = std::function<void(const uint8_t* au, size_t len, bool key)>;
  H264Encoder();
  ~H264Encoder();
  // NV12 input of w x h (even). allowHw = try hardware MFTs first. Requires MFStartup.
  bool open(int w, int h, int fps, int kbps, bool allowHw, std::string* err);
  void close();
  // nv12 = Y plane (w*h) followed by interleaved UV (w*h/2), tightly packed; time in 100 ns.
  // A failing hardware encoder is replaced by the software one transparently.
  // Returns false only on an unrecoverable error.
  bool encode(const uint8_t* nv12, int64_t time, bool forceKey, const Sink& sink);
  void setBitrate(int kbps);
  std::string name() const;
  bool hardware() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> d_;
  int w_ = 0, h_ = 0, fps_ = 30, kbps_ = 3000;
};

// Annex-B helpers.
// Converts AVCC (4-byte big-endian lengths) to Annex-B; Annex-B input is copied as is.
void toAnnexB(const uint8_t* p, size_t n, std::vector<uint8_t>& out);
// Calls fn(nal_type, nal_ptr_including_start_code, size) for every NAL unit.
void forEachNal(const uint8_t* p, size_t n, const std::function<void(int, const uint8_t*, size_t)>& fn);

}  // namespace pn
