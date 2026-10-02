// Runtime-loaded libopus (opus.dll ships next to the executable; only the
// handful of functions Pulse needs are resolved, so no headers are required).
#pragma once
#include <cstdint>
#include <string>

namespace pn {

struct OpusEncoder;
struct OpusDecoder;

constexpr int OPUS_APPLICATION_VOIP = 2048;
constexpr int OPUS_SET_BITRATE_REQUEST = 4002;
constexpr int OPUS_SET_COMPLEXITY_REQUEST = 4010;
constexpr int OPUS_SET_INBAND_FEC_REQUEST = 4012;
constexpr int OPUS_SET_PACKET_LOSS_PERC_REQUEST = 4014;
constexpr int OPUS_SET_DTX_REQUEST = 4016;
constexpr int OPUS_SET_SIGNAL_REQUEST = 4024;
constexpr int OPUS_SIGNAL_VOICE = 3001;

struct OpusLib {
  OpusEncoder* (*encoder_create)(int32_t fs, int channels, int application, int* error) = nullptr;
  int32_t (*encode_float)(OpusEncoder* st, const float* pcm, int frame_size, unsigned char* data, int32_t max_data_bytes) = nullptr;
  int (*encoder_ctl)(OpusEncoder* st, int request, ...) = nullptr;
  void (*encoder_destroy)(OpusEncoder* st) = nullptr;
  OpusDecoder* (*decoder_create)(int32_t fs, int channels, int* error) = nullptr;
  int (*decode_float)(OpusDecoder* st, const unsigned char* data, int32_t len, float* pcm, int frame_size, int decode_fec) = nullptr;
  void (*decoder_destroy)(OpusDecoder* st) = nullptr;
  const char* (*get_version_string)() = nullptr;
  bool ok = false;
  std::string error;
};

// Loads opus.dll from `dir` (falls back to the normal DLL search path).
OpusLib& opus();
bool loadOpus(const std::wstring& dir);

}  // namespace pn
