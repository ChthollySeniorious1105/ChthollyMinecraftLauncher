import 'dart:convert';

import 'package:web/web.dart' as web;

/// localStorage is ~5 MB per site; replays are typically 20–200 KB gzipped.
const int keep = 20;
const bool hasFiles = false;

const _indexKey = 'aurora_replays';
const _prefix = 'aurora_replay:';

/// Index: newest first, [id, metaJson].
List<List<String>> _index() {
  try {
    final raw = web.window.localStorage.getItem(_indexKey);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        if (e is List && e.length == 2) [e[0].toString(), e[1].toString()]
    ];
  } catch (_) {
    return [];
  }
}

void _writeIndex(List<List<String>> idx) => web.window.localStorage.setItem(_indexKey, jsonEncode(idx));

void _remove(String id) => web.window.localStorage.removeItem('$_prefix$id');

Future<String> save(String? override, String id, String metaJson, List<int> gz) async {
  final idx = _index()..removeWhere((e) => e[0] == id);
  idx.insert(0, [id, metaJson]);
  while (idx.length > keep) {
    _remove(idx.removeLast()[0]);
  }
  final data = base64.encode(gz);
  // out of quota: drop the oldest replays until it fits
  for (;;) {
    try {
      web.window.localStorage.setItem('$_prefix$id', data);
      break;
    } catch (_) {
      if (idx.length <= 1) rethrow;
      _remove(idx.removeLast()[0]);
    }
  }
  _writeIndex(idx);
  return id;
}

Future<bool> exists(String? override, String id) async => web.window.localStorage.getItem('$_prefix$id') != null;

Future<List<(String, String?)>> list(String? override) async => [
      for (final e in _index())
        if (web.window.localStorage.getItem('$_prefix${e[0]}') != null) (e[0], e[1])
    ];

Future<List<int>> read(String path) async {
  final s = web.window.localStorage.getItem('$_prefix$path');
  if (s == null) throw StateError('回放不存在');
  return base64.decode(s);
}

Future<void> delete(String path) async {
  _remove(path);
  _writeIndex(_index()..removeWhere((e) => e[0] == path));
}
