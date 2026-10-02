import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

/// Saved replays: `<dir>/<id>.json.gz` + `<dir>/index.jsonl` (one meta per line,
/// oldest first). Only finished games are ever saved.
class ReplayStore {
  final Directory? dir;
  final int keep;
  final List<Map<String, dynamic>> _index = [];
  final Random _rng = Random.secure();
  static const chunkBytes = 150 * 1024;

  ReplayStore(this.dir, {this.keep = 2000}) {
    _load();
  }

  int get count => _index.length;
  String _sep() => Platform.pathSeparator;
  File _file(String id) => File('${dir!.path}${_sep()}$id.json.gz');
  File get _indexFile => File('${dir!.path}${_sep()}index.jsonl');

  static bool validId(String id) => RegExp(r'^[0-9a-z]{4,32}$').hasMatch(id);

  void _load() {
    final d = dir;
    if (d == null) return;
    try {
      if (!_indexFile.existsSync()) return;
      for (final l in _indexFile.readAsLinesSync()) {
        if (l.trim().isEmpty) continue;
        try {
          final m = jsonDecode(l);
          if (m is Map<String, dynamic> && validId('${m['id']}') && _file('${m['id']}').existsSync()) _index.add(m);
        } catch (_) {}
      }
    } catch (e) {
      stderr.writeln('读取回放索引失败：$e');
    }
  }

  String newId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    const cs = '0123456789abcdefghijklmnopqrstuvwxyz';
    return t + String.fromCharCodes(List.generate(4, (_) => cs.codeUnitAt(_rng.nextInt(cs.length))));
  }

  /// Save a finished replay document (from ReplayRecorder.finish). The meta
  /// inside must contain the id.
  Future<void> save(Map<String, dynamic> doc) async {
    final d = dir;
    if (d == null) return;
    final meta = (doc['meta'] as Map).cast<String, dynamic>();
    final id = '${meta['id']}';
    if (!validId(id)) return;
    final bytes = await Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(doc))));
    await d.create(recursive: true);
    final tmp = File('${_file(id).path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file(id).path);
    final m = Map<String, dynamic>.of(meta)..['size'] = bytes.length;
    _index.add(m);
    await _indexFile.writeAsString('${jsonEncode(m)}\n', mode: FileMode.append, flush: true);
    await _prune();
  }

  Future<void> _prune() async {
    if (keep <= 0 || _index.length <= keep) return;
    final drop = _index.sublist(0, _index.length - keep);
    _index.removeRange(0, _index.length - keep);
    for (final m in drop) {
      try {
        await _file('${m['id']}').delete();
      } catch (_) {}
    }
    try {
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(_index.map((m) => '${jsonEncode(m)}\n').join(), flush: true);
      await tmp.rename(_indexFile.path);
    } catch (e) {
      stderr.writeln('重写回放索引失败：$e');
    }
  }

  /// Newest first, max [limit]. [pid] non-null → only replays with that uid.
  List<Map<String, dynamic>> list({String? pid, int limit = 100}) {
    final out = <Map<String, dynamic>>[];
    for (var i = _index.length - 1; i >= 0 && out.length < limit; i--) {
      final m = _index[i];
      if (pid != null) {
        final uids = m['uids'];
        if (pid.isEmpty || uids is! List || !uids.contains(pid)) continue;
      }
      out.add({for (final e in m.entries) if (e.key != 'uids') e.key: e.value});
    }
    return out;
  }

  bool has(String id) => _index.any((m) => m['id'] == id);

  /// Base64 chunks of the gzip file, or null if unknown.
  Future<List<String>?> chunks(String id) async {
    if (dir == null || !validId(id) || !has(id)) return null;
    try {
      final bytes = await _file(id).readAsBytes();
      return [
        for (var o = 0; o < bytes.length || o == 0; o += chunkBytes)
          base64.encode(bytes.sublist(o, min(o + chunkBytes, bytes.length)))
      ];
    } catch (_) {
      return null;
    }
  }

  int get totalBytes {
    var n = 0;
    for (final m in _index) {
      n += (m['size'] as num?)?.toInt() ?? 0;
    }
    return n;
  }
}
