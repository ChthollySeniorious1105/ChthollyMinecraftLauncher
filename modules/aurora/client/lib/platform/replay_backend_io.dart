import 'dart:io';

import 'package:path_provider/path_provider.dart';

const int keep = 200;
const bool hasFiles = true;
const _ext = '.aurora-replay.gz';

Future<Directory> _dir(String? override) async {
  final base = Directory(override ?? '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}aurora_replays');
  if (!base.existsSync()) base.createSync(recursive: true);
  return base;
}

File _side(String path) => File('${path.substring(0, path.length - _ext.length)}.meta.json');

Future<String> save(String? override, String id, String metaJson, List<int> gz) async {
  final d = await _dir(override);
  final f = File('${d.path}${Platform.pathSeparator}$id$_ext');
  await f.writeAsBytes(gz, flush: true);
  await _side(f.path).writeAsString(metaJson);
  _prune(d);
  return f.path;
}

Future<bool> exists(String? override, String id) async {
  final d = await _dir(override);
  return File('${d.path}${Platform.pathSeparator}$id$_ext').existsSync();
}

/// (path, sidecar meta JSON or null).
Future<List<(String, String?)>> list(String? override) async {
  final d = await _dir(override);
  return [
    for (final e in d.listSync())
      if (e is File && e.path.endsWith(_ext)) (e.path, _side(e.path).existsSync() ? _side(e.path).readAsStringSync() : null)
  ];
}

Future<List<int>> read(String path) => File(path).readAsBytes();

Future<void> delete(String path) async {
  try {
    File(path).deleteSync();
    final side = _side(path);
    if (side.existsSync()) side.deleteSync();
  } catch (_) {}
}

void _prune(Directory d) {
  try {
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith(_ext)).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in files.skip(keep)) {
      f.deleteSync();
      final side = _side(f.path);
      if (side.existsSync()) side.deleteSync();
    }
  } catch (_) {}
}
