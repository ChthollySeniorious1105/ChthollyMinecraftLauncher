// Screen sharing: Windows Graphics Capture (monitor or window) -> GPU scale + BGRA->NV12
// (D3D11 video processor, CPU fallback) -> H.264 (Media Foundation, hardware first)
// -> PN_EV_VIDEO_PACKET. Also source enumeration and thumbnails for the picker.
//
// Threading: the WGC frame callback (system thread pool) only copies the newest frame
// into our own texture; a dedicated encoder thread converts and encodes at the requested
// fps. Nothing here touches the audio engine.
#pragma once
#include "common.h"

namespace pn::screen {
std::string sourcesJson();
uint8_t* thumbnail(const std::string& id, int maxW, int maxH, int* w, int* h);  // RGBA, malloc'd
int start(const std::string& id, int maxW, int maxH, int fps, int kbps);
void stop();
void keyframe();
void setBitrate(int kbps);
std::string statusJson();
void shutdown();
}  // namespace pn::screen
