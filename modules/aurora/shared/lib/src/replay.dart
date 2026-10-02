import 'dart:convert';

/// 对局回放.
///
/// A replay stores the *views* the server sent (one track per game seat plus
/// the spectator track), not the actions, so it reproduces every game exactly
/// — including real-time, timed and AI-driven games. Each frame of a track is
/// a structural diff against the previous frame of that track (see
/// [jsonDiff]), which keeps files small (typically 20–200 KB gzipped).
///
/// File layout (JSON, gzip on disk and on the wire):
/// ```
/// {v:1, meta:{…ReplayMeta}, tracks:[[{t:ms, d:diff}, …] × (players+1)], logs:[[ms, text], …]}
/// ```
/// Track index = game seat; the last track is the spectator (seat -1) view.
class ReplayMeta {
  final String id;
  final String game;
  final String gameName;
  final int startedAt; // ms since epoch
  final int durationMs;
  final List<String> names;
  final List<int> avatars;
  final List<bool> bots;
  final Map<String, dynamic> options;

  /// Hashed player ids (for "my replays"); '' for bots.
  final List<String> uids;
  final List<int>? ranking;
  final String room;

  const ReplayMeta({
    required this.id,
    required this.game,
    required this.gameName,
    required this.startedAt,
    required this.durationMs,
    required this.names,
    required this.avatars,
    required this.bots,
    required this.options,
    required this.uids,
    required this.ranking,
    required this.room,
  });

  Map<String, dynamic> toJson({bool withUids = false}) => {
        'id': id,
        'game': game,
        'gameName': gameName,
        'startedAt': startedAt,
        'durationMs': durationMs,
        'names': names,
        'avatars': avatars,
        'bots': bots,
        'options': options,
        if (withUids) 'uids': uids,
        'ranking': ranking,
        'room': room,
      };

  static ReplayMeta fromJson(Map<String, dynamic> j) => ReplayMeta(
        id: '${j['id']}',
        game: '${j['game']}',
        gameName: '${j['gameName'] ?? j['game']}',
        startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        names: [for (final n in (j['names'] as List? ?? const [])) '$n'],
        avatars: [for (final n in (j['avatars'] as List? ?? const [])) (n as num).toInt()],
        bots: [for (final n in (j['bots'] as List? ?? const [])) n == true],
        options: (j['options'] as Map?)?.cast<String, dynamic>() ?? const {},
        uids: [for (final n in (j['uids'] as List? ?? const [])) '$n'],
        ranking: (j['ranking'] as List?)?.map((e) => (e as num).toInt()).toList(),
        room: '${j['room'] ?? ''}',
      );
}

/// Records views while a game runs.
class ReplayRecorder {
  final int players;
  final int startedAt;

  /// Frames closer together than this are merged (real-time games tick fast).
  final int minGapMs;
  final List<List<Map<String, dynamic>>> tracks;
  final List<Object?> _last;
  final List<int> _lastT;
  final List<Object?> _pending;
  final List<List<Object>> logs = [];
  int _bytes = 0;

  /// Stop recording beyond this many (uncompressed) diff bytes.
  static const maxBytes = 24 * 1024 * 1024;
  bool get full => _bytes > maxBytes;

  ReplayRecorder(this.players, {int? startedAt, this.minGapMs = 200})
      : startedAt = startedAt ?? DateTime.now().millisecondsSinceEpoch,
        tracks = List.generate(players + 1, (_) => []),
        _last = List.filled(players + 1, null),
        _lastT = List.filled(players + 1, -1 << 30),
        _pending = List.filled(players + 1, null);

  int get _now => DateTime.now().millisecondsSinceEpoch - startedAt;

  /// Track index for a game seat (-1 = spectator).
  int trackOf(int seat) => seat < 0 ? players : seat;

  /// Record [view] for [seat]. Views are JSON-encoded immediately (the engine
  /// may mutate the maps it returned later).
  void add(int seat, Map<String, dynamic> view, {bool force = false}) {
    if (full) return;
    final i = trackOf(seat);
    final v = jsonDecode(jsonEncode(view));
    final t = _now;
    if (!force && t - _lastT[i] < minGapMs && tracks[i].isNotEmpty) {
      _pending[i] = v; // flushed by the next frame or finish()
      return;
    }
    _push(i, t, v);
  }

  void _push(int i, int t, Object? v) {
    _pending[i] = null;
    final d = jsonDiff(_last[i], v);
    if (identical(d, jsonSame) && tracks[i].isNotEmpty) return;
    final f = {'t': t, 'd': identical(d, jsonSame) ? v : d};
    _bytes += jsonEncode(f).length;
    tracks[i].add(f);
    _last[i] = v;
    _lastT[i] = t;
  }

  void log(String text) {
    if (logs.length < 5000) logs.add([_now, text]);
  }

  /// Flush merged frames and build the replay document.
  Map<String, dynamic> finish(ReplayMeta Function(int durationMs) meta) {
    final t = _now;
    for (var i = 0; i < tracks.length; i++) {
      if (_pending[i] != null) _push(i, t, _pending[i]);
    }
    return {'v': 1, 'meta': meta(t).toJson(withUids: true), 'tracks': tracks, 'logs': logs};
  }
}

/// Decoded replay ready for playback.
class Replay {
  final ReplayMeta meta;
  final List<List<Map<String, dynamic>>> _tracks;
  final List<List<Object>> logs;
  final List<List<(int, Map<String, dynamic>)>?> _cache;

  Replay._(this.meta, this._tracks, this.logs) : _cache = List.filled(_tracks.length, null);

  static Replay fromJson(Map<String, dynamic> j) {
    final tracks = [
      for (final t in (j['tracks'] as List? ?? const []))
        [for (final f in (t as List)) (f as Map).cast<String, dynamic>()]
    ];
    final logs = [for (final l in (j['logs'] as List? ?? const [])) List<Object>.from(l as List)];
    return Replay._(ReplayMeta.fromJson((j['meta'] as Map).cast<String, dynamic>()), tracks, logs);
  }

  int get players => meta.names.length;
  int get durationMs => meta.durationMs;

  /// Track for a game seat, -1 = spectator.
  List<(int, Map<String, dynamic>)> frames(int seat) {
    final i = seat < 0 || seat >= _tracks.length - 1 ? _tracks.length - 1 : seat;
    final c = _cache[i];
    if (c != null) return c;
    final out = <(int, Map<String, dynamic>)>[];
    Object? cur;
    for (final f in _tracks[i]) {
      cur = jsonPatch(cur, f['d']);
      if (cur is Map) out.add(((f['t'] as num).toInt(), cur.cast<String, dynamic>()));
    }
    return _cache[i] = out;
  }

  /// Index of the last frame at or before [ms] (binary search).
  static int frameAt(List<(int, Map<String, dynamic>)> fr, int ms) {
    var lo = 0, hi = fr.length - 1, ans = 0;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (fr[m].$1 <= ms) {
        ans = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    return ans;
  }
}

// ------------------------------------------------------------ JSON diff

/// Sentinel: "no change".
const Object jsonSame = _Same();

class _Same {
  const _Same();
}

/// Structural diff b relative to a. Result encoding:
/// * any non-map value → replace with it
/// * `{"\$": {k: diff…}, "\$x": [removed keys]}` → patch a map
/// * `{"\$a": [items]}` → append items to a list
/// * `{"\$l": {"i": diff…}, "\$n": len}` → patch list elements, set length
/// * a real map value is wrapped as `{"\$v": map}`
Object? jsonDiff(Object? a, Object? b) {
  if (a is Map && b is Map) {
    final ch = <String, Object?>{};
    final rm = <String>[];
    for (final e in b.entries) {
      final k = e.key as String;
      if (!a.containsKey(k)) {
        ch[k] = _wrap(e.value);
        continue;
      }
      final d = jsonDiff(a[k], e.value);
      if (!identical(d, jsonSame)) ch[k] = d;
    }
    for (final k in a.keys) {
      if (!b.containsKey(k)) rm.add(k as String);
    }
    if (ch.isEmpty && rm.isEmpty) return jsonSame;
    return {r'$': ch, if (rm.isNotEmpty) r'$x': rm};
  }
  if (a is List && b is List) {
    var same = 0;
    final n = a.length < b.length ? a.length : b.length;
    final changed = <String, Object?>{};
    for (var i = 0; i < n; i++) {
      final d = jsonDiff(a[i], b[i]);
      if (identical(d, jsonSame)) {
        same++;
      } else {
        changed['$i'] = d;
      }
    }
    if (changed.isEmpty && a.length == b.length) return jsonSame;
    if (changed.isEmpty && b.length > a.length) return {r'$a': [for (final x in b.sublist(a.length)) x]};
    // many changes: plain replacement is smaller and simpler
    if (same < n ~/ 2) return _wrap(b);
    return {r'$l': changed, r'$n': b.length, if (b.length > a.length) r'$a': [for (final x in b.sublist(a.length)) x]};
  }
  if (a == b && a is! Map && a is! List) return jsonSame;
  return _wrap(b);
}

Object? _wrap(Object? v) => v is Map ? {r'$v': v} : v;

/// Apply a diff produced by [jsonDiff].
Object? jsonPatch(Object? a, Object? d) {
  if (d is! Map) return d is List ? List.of(d) : d;
  if (d.containsKey(r'$v')) return _deepCopy(d[r'$v']);
  if (d.containsKey(r'$')) {
    final out = a is Map ? Map<String, dynamic>.of(a.cast<String, dynamic>()) : <String, dynamic>{};
    for (final e in (d[r'$'] as Map).entries) {
      out[e.key as String] = jsonPatch(out[e.key], e.value);
    }
    for (final k in (d[r'$x'] as List? ?? const [])) {
      out.remove(k);
    }
    return out;
  }
  if (d.containsKey(r'$l') || d.containsKey(r'$a')) {
    final out = a is List ? List<dynamic>.of(a) : <dynamic>[];
    final l = d[r'$l'] as Map?;
    if (l != null) {
      for (final e in l.entries) {
        final i = int.parse(e.key as String);
        if (i < out.length) out[i] = jsonPatch(out[i], e.value);
      }
    }
    final n = d[r'$n'];
    if (n is int && n < out.length) out.length = n;
    final add = d[r'$a'] as List?;
    if (add != null) {
      final base = n is int ? n - add.length : out.length;
      if (out.length > base && base >= 0) out.length = base;
      out.addAll(add);
    }
    return out;
  }
  return _deepCopy(d);
}

Object? _deepCopy(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
  if (v is List) return [for (final x in v) _deepCopy(x)];
  return v;
}
