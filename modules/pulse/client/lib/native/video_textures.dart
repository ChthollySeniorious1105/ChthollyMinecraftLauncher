import 'package:flutter/services.dart';

/// Flutter textures for screen-share video, backed by pulse.exe's "pulse/video"
/// plugin (windows/runner/video_textures.cpp) which reads frames from the
/// native decoders. Missing in tests: calls return null / do nothing.
class VideoTextures {
  static const _ch = MethodChannel('pulse/video');

  /// Texture id showing the decoded frames of stream [id], or null.
  Future<int?> create(int id) async {
    try {
      final r = await _ch.invokeMethod<Object>('create', id);
      return r is int ? r : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose(int id) async {
    try {
      await _ch.invokeMethod<void>('dispose', id);
    } catch (_) {}
  }
}
