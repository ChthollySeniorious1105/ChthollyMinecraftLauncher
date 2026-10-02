#ifndef RUNNER_VIDEO_TEXTURES_H_
#define RUNNER_VIDEO_TEXTURES_H_

#include <flutter/flutter_engine.h>

// Flutter texture plugin for screen-share video (MethodChannel "pulse/video").
//   create(int streamId) -> int64 textureId   (refcounted per stream id)
//   dispose(int streamId)
// Frames come from pulse_native.dll's decoders (pn_video_lock_frame, RGBA8888);
// the DLL is loaded by Dart, so the functions are resolved lazily on `create`.
void RegisterVideoTextures(flutter::FlutterEngine* engine);

#endif  // RUNNER_VIDEO_TEXTURES_H_
