import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:aurora_shared/aurora_shared.dart';

import 'replay_backend_io.dart' if (dart.library.js_interop) 'replay_backend_web.dart' as backend;

/// Decode a gzip-compressed replay document.
Replay decodeReplayGz(List<int> gz) {
  final j = jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(gz)));
  return Replay.fromJson((j as Map).cast<String, dynamic>());
}

Uint8List encodeReplayGz(Map<String, dynamic> doc) => const GZipEncoder().encodeBytes(utf8.encode(jsonEncode(doc)));

/// A replay saved on this device. [path] is a file path natively and a
/// storage key in the browser; show it to users only when [ReplayStore.hasFiles].
class LocalReplay {
  final String path;
  final ReplayMeta meta;
  LocalReplay(this.path, this.meta);
}

/// Replays saved on this device: natively in the app documents dir
/// (`aurora_replays/*.aurora-replay.gz` + `*.meta.json` sidecars), in the
/// browser in localStorage (fewer kept, it is only a few MB).
class ReplayStore {
  /// Tests set this to a temp dir path (path_provider has no plugin under test).
  static String? dirOverride;
  static const ext = '.aurora-replay.gz';
  static int get keep => backend.keep;

  /// False in the browser: there is no file path worth showing.
  static bool get hasFiles => backend.hasFiles;

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// Save gzip bytes of a replay; returns its path / key.
  static Future<String> saveGz(ReplayMeta meta, List<int> gz) =>
      backend.save(dirOverride, _safe(meta.id), jsonEncode(meta.toJson(withUids: true)), gz);

  static Future<String> saveDoc(Map<String, dynamic> doc) {
    final meta = ReplayMeta.fromJson((doc['meta'] as Map).cast<String, dynamic>());
    return saveGz(meta, encodeReplayGz(doc));
  }

  static Future<bool> exists(String id) => backend.exists(dirOverride, _safe(id));

  static Future<List<LocalReplay>> list() async {
    final out = <LocalReplay>[];
    try {
      for (final (path, metaJson) in await backend.list(dirOverride)) {
        ReplayMeta meta;
        try {
          meta = metaJson != null
              ? ReplayMeta.fromJson((jsonDecode(metaJson) as Map).cast<String, dynamic>())
              : decodeReplayGz(await backend.read(path)).meta;
        } catch (_) {
          continue;
        }
        out.add(LocalReplay(path, meta));
      }
    } catch (_) {}
    out.sort((a, b) => b.meta.startedAt.compareTo(a.meta.startedAt));
    return out;
  }

  static Future<Replay> load(String path) async => decodeReplayGz(await backend.read(path));

  static Future<void> delete(LocalReplay r) => backend.delete(r.path);
}

/// Short unique id: base36 timestamp + 4 random chars.
String newReplayId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  final r = Random();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${[for (var i = 0; i < 4; i++) chars[r.nextInt(36)]].join()}';
}
