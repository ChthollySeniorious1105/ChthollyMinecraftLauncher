import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pulse_shared/pulse_shared.dart';

/// Custom avatar images: in-memory + on-disk cache keyed by content hash
/// (`%APPDATA%\Pulse\avatars\<sha256>.img`), fetched from the server on demand.
class AvatarCache extends ChangeNotifier {
  final Directory dir;
  final void Function(int uid, String hash) request;
  AvatarCache(this.dir, this.request);

  final Map<String, Uint8List> _mem = {};
  final Set<String> _inflight = {};

  static final _hashRe = RegExp(r'^[0-9a-f]{64}$');

  File _file(String h) => File('${dir.path}${Platform.pathSeparator}$h.img');

  /// Bytes for [hash], or null (then a download is started and listeners are notified later).
  Uint8List? get(int uid, String hash) {
    if (!_hashRe.hasMatch(hash)) return null;
    final m = _mem[hash];
    if (m != null) return m;
    try {
      final f = _file(hash);
      if (f.existsSync()) return _mem[hash] = f.readAsBytesSync();
    } catch (_) {}
    if (_inflight.add(hash)) request(uid, hash);
    return null;
  }

  /// Server reply: verify the content hash before trusting / caching it.
  void put(String hash, Uint8List bytes) {
    _inflight.remove(hash);
    if (!_hashRe.hasMatch(hash) || validateAvatar(bytes) != null) return;
    if (sha256Hex(bytes) != hash) return;
    _mem[hash] = bytes;
    try {
      dir.createSync(recursive: true);
      _file(hash).writeAsBytesSync(bytes, flush: true);
    } catch (_) {}
    notifyListeners();
  }

  /// Forget pending requests (reconnect): they will be asked again.
  void resetInflight() => _inflight.clear();
}

/// Square-crops, resizes and encodes a picked image for upload (PNG; falls back to
/// JPEG when the PNG would exceed the size limit). Animated GIFs use the first frame.
/// Runs in a background isolate.
Future<(Uint8List?, String?)> prepareAvatar(Uint8List input, {double cx = 0.5, double cy = 0.5, double zoom = 1}) =>
    compute(_prepare, (input, cx, cy, zoom));

(Uint8List?, String?) _prepare((Uint8List, double, double, double) a) {
  final (input, cx, cy, zoom) = a;
  if (input.length > 20 * 1024 * 1024) return (null, '图片太大（最多 20 MB）');
  final decoded = img.decodeImage(input);
  if (decoded == null) return (null, '无法识别的图片格式（支持 PNG / JPEG / WebP / GIF / BMP）');
  final src = decoded.frames.isNotEmpty ? decoded.frames.first : decoded;
  // centred square crop, optionally zoomed in around (cx, cy)
  final side = (src.width < src.height ? src.width : src.height) / zoom.clamp(1.0, 4.0);
  final x = ((src.width - side) * cx).clamp(0, src.width - side).round();
  final y = ((src.height - side) * cy).clamp(0, src.height - side).round();
  final crop = img.copyCrop(src, x: x, y: y, width: side.round(), height: side.round());
  final sized = img.copyResize(crop, width: kAvatarUploadSize, height: kAvatarUploadSize, interpolation: img.Interpolation.average);
  var out = Uint8List.fromList(img.encodePng(sized, level: 9));
  if (out.length > kMaxAvatarBytes) {
    for (final q in [90, 80, 70, 55, 40]) {
      out = Uint8List.fromList(img.encodeJpg(sized, quality: q));
      if (out.length <= kMaxAvatarBytes) break;
    }
  }
  final err = validateAvatar(out);
  return err == null ? (out, null) : (null, err);
}

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
