import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:path_provider/path_provider.dart';

/// Decode a gzip-compressed replay document.
Replay decodeReplayGz(List<int> gz) {
  final j = jsonDecode(utf8.decode(gzip.decode(gz)));
  return Replay.fromJson((j as Map).cast<String, dynamic>());
}

Uint8List encodeReplayGz(Map<String, dynamic> doc) => Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(doc))));

/// A replay file saved on this device.
class LocalReplay {
  final File file;
  final ReplayMeta meta;
  LocalReplay(this.file, this.meta);
}

/// Replays saved in the app documents dir (`aurora_replays/*.aurora-replay.gz`,
/// with a small `*.meta.json` sidecar so listing doesn't decode every file).
class ReplayStore {
  /// Tests set this to a temp dir (path_provider has no plugin under test).
  static Directory? dirOverride;
  static const ext = '.aurora-replay.gz';
  static const keep = 200;

  static Future<Directory> dir() async {
    final base = dirOverride ?? Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}aurora_replays');
    if (!base.existsSync()) base.createSync(recursive: true);
    return base;
  }

  static File _side(FileSystemEntity f) => File('${f.path.substring(0, f.path.length - ext.length)}.meta.json');

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// Save gzip bytes of a replay; returns the file.
  static Future<File> saveGz(ReplayMeta meta, List<int> gz) async {
    final d = await dir();
    final id = _safe(meta.id);
    final f = File('${d.path}${Platform.pathSeparator}$id$ext');
    await f.writeAsBytes(gz, flush: true);
    await File('${d.path}${Platform.pathSeparator}$id.meta.json').writeAsString(jsonEncode(meta.toJson(withUids: true)));
    await _prune(d);
    return f;
  }

  static Future<File> saveDoc(Map<String, dynamic> doc) async {
    final meta = ReplayMeta.fromJson((doc['meta'] as Map).cast<String, dynamic>());
    return saveGz(meta, encodeReplayGz(doc));
  }

  static Future<bool> exists(String id) async {
    final d = await dir();
    return File('${d.path}${Platform.pathSeparator}${_safe(id)}$ext').existsSync();
  }

  static Future<List<LocalReplay>> list() async {
    final out = <LocalReplay>[];
    try {
      final d = await dir();
      for (final e in d.listSync()) {
        if (e is! File || !e.path.endsWith(ext)) continue;
        final side = _side(e);
        ReplayMeta? meta;
        try {
          if (side.existsSync()) {
            meta = ReplayMeta.fromJson((jsonDecode(side.readAsStringSync()) as Map).cast<String, dynamic>());
          } else {
            meta = decodeReplayGz(e.readAsBytesSync()).meta;
          }
        } catch (_) {
          continue;
        }
        out.add(LocalReplay(e, meta));
      }
    } catch (_) {}
    out.sort((a, b) => b.meta.startedAt.compareTo(a.meta.startedAt));
    return out;
  }

  static Future<Replay> load(File f) async => decodeReplayGz(await f.readAsBytes());

  static Future<void> delete(LocalReplay r) async {
    try {
      r.file.deleteSync();
      final side = _side(r.file);
      if (side.existsSync()) side.deleteSync();
    } catch (_) {}
  }

  static Future<void> _prune(Directory d) async {
    try {
      final files = d.listSync().whereType<File>().where((f) => f.path.endsWith(ext)).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in files.skip(keep)) {
        f.deleteSync();
        final side = _side(f);
        if (side.existsSync()) side.deleteSync();
      }
    } catch (_) {}
  }
}

/// Short unique id: base36 timestamp + 4 random chars.
String newReplayId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  final r = Random();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${[for (var i = 0; i < 4; i++) chars[r.nextInt(36)]].join()}';
}
