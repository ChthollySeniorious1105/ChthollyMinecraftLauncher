// H.264 decoding of remote screen shares (Media Foundation software decoder) into
// RGBA8888 frames for pulse.exe's Flutter texture plugin.
//
// One decoder thread per stream id with a bounded input queue: when more than ~10 access
// units pile up (slow machine / burst) everything is dropped until the next keyframe.
// Frames are double buffered: the decoder writes the back buffer, then swaps under the
// lock; pn_video_lock_frame holds the lock while the texture callback copies the front.
#pragma once
#include "common.h"

namespace pn::video {
int open(uint32_t id);
void close(uint32_t id);
void push(uint32_t id, const uint8_t* data, int len, bool keyframe);
std::string statsJson(uint32_t id);
void setFrameCallback(pn_frame_cb cb);
bool lockFrame(uint32_t id, const uint8_t** rgba, int* w, int* h);
void unlockFrame(uint32_t id);
void shutdown();

// NV12 (BT.709 limited range) -> RGBA8888. Exposed for tests.
void nv12ToRgba(const uint8_t* y, int yPitch, const uint8_t* uv, int uvPitch, int w, int h, uint8_t* out);
}  // namespace pn::video
