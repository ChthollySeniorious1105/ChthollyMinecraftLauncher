/// 四川麻将 tile helpers (private to the sichuan package).
///
/// Tiles are ints 0..26: suit = t ~/ 9 (0 万 m, 1 筒 p, 2 条 s), rank = t % 9 + 1.
library;

const List<String> suitNames = ['万', '筒', '条'];
const String _suitLetters = 'mps';

String tileCode(int t) => '${t % 9 + 1}${_suitLetters[t ~/ 9]}';

int tileFromCode(Object? c) {
  if (c is! String || c.length != 2) return -1;
  final r = int.tryParse(c[0]);
  final s = _suitLetters.indexOf(c[1]);
  if (r == null || r < 1 || r > 9 || s < 0) return -1;
  return s * 9 + r - 1;
}

String tileName(int t) => '${'一二三四五六七八九'[t % 9]}${suitNames[t ~/ 9]}';

int suitOf(int t) => t ~/ 9;
int rankOf(int t) => t % 9 + 1;

List<int> countsOf(Iterable<int> tiles) {
  final c = List<int>.filled(27, 0);
  for (final t in tiles) {
    c[t]++;
  }
  return c;
}

/// A called / declared meld.
class Meld {
  /// 'peng' 碰, 'mgang' 直杠(明杠), 'bgang' 补杠, 'agang' 暗杠
  String kind;
  final int tile;
  final int from; // seat the tile came from (-1 for 暗杠)
  Meld(this.kind, this.tile, this.from);
  bool get isKong => kind != 'peng';
  int get size => isKong ? 4 : 3;
}

// ---------------------------------------------------------------------------
// Complete-hand decomposition
// ---------------------------------------------------------------------------

/// A set inside a decomposition: triplet (seq=false) or sequence starting at tile.
class _Set {
  final int tile;
  final bool seq;
  const _Set(this.tile, this.seq);
}

void _decomp(List<int> c, int i, List<_Set> cur, List<List<_Set>> out) {
  while (i < 27 && c[i] == 0) {
    i++;
  }
  if (i >= 27) {
    out.add(List.of(cur));
    return;
  }
  if (c[i] >= 3) {
    c[i] -= 3;
    cur.add(_Set(i, false));
    _decomp(c, i, cur, out);
    cur.removeLast();
    c[i] += 3;
  }
  if (i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
    c[i]--;
    c[i + 1]--;
    c[i + 2]--;
    cur.add(_Set(i, true));
    _decomp(c, i, cur, out);
    cur.removeLast();
    c[i]++;
    c[i + 1]++;
    c[i + 2]++;
  }
}

bool _canSets(List<int> c, int i) {
  while (i < 27 && c[i] == 0) {
    i++;
  }
  if (i >= 27) return true;
  if (c[i] >= 3) {
    c[i] -= 3;
    final ok = _canSets(c, i);
    c[i] += 3;
    if (ok) return true;
  }
  if (i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
    c[i]--;
    c[i + 1]--;
    c[i + 2]--;
    final ok = _canSets(c, i);
    c[i]++;
    c[i + 1]++;
    c[i + 2]++;
    if (ok) return true;
  }
  return false;
}

/// True if the concealed counts (3n+2 tiles) form a complete hand
/// (n sets + pair, or 七对 when [meldCount]==0), with no tiles of suit [que].
bool isWinningCounts(List<int> c, int meldCount, {int que = -1}) {
  var total = 0;
  for (var t = 0; t < 27; t++) {
    if (c[t] > 0 && suitOf(t) == que) return false;
    total += c[t];
  }
  if (total % 3 != 2) return false;
  if (meldCount == 0 && total == 14 && c.every((x) => x.isEven)) return true;
  final w = List.of(c);
  for (var t = 0; t < 27; t++) {
    if (w[t] >= 2) {
      w[t] -= 2;
      final ok = _canSets(w, 0);
      w[t] += 2;
      if (ok) return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Fan (番) evaluation
// ---------------------------------------------------------------------------

class FanResult {
  final int fan;

  /// (name, fan) items, e.g. [('清对', 3), ('根', 1)]
  final List<(String, int)> items;
  const FanResult(this.fan, this.items);

  List<List<Object>> toJson() => [for (final (n, f) in items) [n, f]];
}

/// Pattern fan of a complete hand (no situational extras).
/// [concealed] counts include the winning tile. Returns null if not a win.
FanResult? evaluateHand(List<int> concealed, List<Meld> melds, {int que = -1}) {
  if (!isWinningCounts(concealed, melds.length, que: que)) return null;
  final all = List.of(concealed);
  for (final m in melds) {
    all[m.tile] += m.size;
  }
  final suits = <int>{for (var t = 0; t < 27; t++) if (all[t] > 0) suitOf(t)};
  final qing = suits.length == 1;
  final gen = all.where((x) => x == 4).length;

  FanResult? best;
  void consider(FanResult r) {
    if (best == null || r.fan > best!.fan) best = r;
  }

  // 七对
  final total = concealed.fold<int>(0, (a, b) => a + b);
  if (melds.isEmpty && total == 14 && concealed.every((x) => x.isEven)) {
    final items = <(String, int)>[];
    var extraGen = gen;
    if (qing && gen > 0) {
      items.add(('清龙七对', 5));
      extraGen--;
    } else if (qing) {
      items.add(('清七对', 4));
    } else if (gen > 0) {
      items.add(('龙七对', 3));
      extraGen--;
    } else {
      items.add(('七对', 2));
    }
    if (extraGen > 0) items.add(('根', extraGen));
    consider(FanResult(items.fold(0, (a, e) => a + e.$2), items));
  }

  // standard decompositions
  final w = List.of(concealed);
  for (var p = 0; p < 27; p++) {
    if (w[p] < 2) continue;
    w[p] -= 2;
    final outs = <List<_Set>>[];
    _decomp(w, 0, [], outs);
    w[p] += 2;
    for (final sets in outs) {
      final allTrip = sets.every((s) => !s.seq);
      bool term(int t) => rankOf(t) == 1 || rankOf(t) == 9;
      final yaojiu = term(p) &&
          melds.every((m) => term(m.tile)) &&
          sets.every((s) => s.seq ? (rankOf(s.tile) == 1 || rankOf(s.tile) == 7) : term(s.tile));
      bool j258(int t) => const [2, 5, 8].contains(rankOf(t));
      final jiang = allTrip && j258(p) && melds.every((m) => j258(m.tile)) && sets.every((s) => j258(s.tile));
      final items = <(String, int)>[];
      if (jiang) {
        items.add(('将对', 3));
        if (qing) items.add(('清一色', 2));
      } else if (allTrip && qing) {
        items.add(('清对', 3));
      } else if (allTrip) {
        items.add(('对对胡', 1));
      } else if (qing) {
        items.add(('清一色', 2));
      }
      if (yaojiu) items.add(('带幺九', 2));
      if (items.isEmpty) items.add(('平胡', 0));
      if (gen > 0) items.add(('根', gen));
      consider(FanResult(items.fold(0, (a, e) => a + e.$2), items));
    }
  }
  return best;
}

/// Tiles that would complete a 3n+1 concealed hand.
List<int> waitingTiles(List<int> concealed, List<Meld> melds, {int que = -1}) {
  final out = <int>[];
  for (var t = 0; t < 27; t++) {
    if (suitOf(t) == que) continue;
    concealed[t]++;
    if (isWinningCounts(concealed, melds.length, que: que)) out.add(t);
    concealed[t]--;
  }
  return out;
}

/// Max pattern fan over all waits, or -1 when not tenpai.
int maxWaitFan(List<int> concealed, List<Meld> melds, {int que = -1}) {
  var best = -1;
  for (final t in waitingTiles(concealed, melds, que: que)) {
    concealed[t]++;
    final r = evaluateHand(concealed, melds, que: que);
    concealed[t]--;
    if (r != null && r.fan > best) best = r.fan;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Shanten (向听数) for bots — per-suit memoised
// ---------------------------------------------------------------------------

final Map<int, List<(int, int, int)>> _suitMemo = {};

/// For a single suit (9 counts), the pareto list of (pair, mentsu, taatsu).
List<(int, int, int)> _suitOptions(List<int> c9) {
  var key = 0;
  for (final x in c9) {
    key = key * 5 + x;
  }
  final hit = _suitMemo[key];
  if (hit != null) return hit;
  // best[p*5+m] = max taatsu
  final best = List<int>.filled(10, -1);
  final c = List.of(c9);
  void rec(int i, int p, int m, int t) {
    while (i < 9 && c[i] == 0) {
      i++;
    }
    if (i >= 9) {
      final k = p * 5 + m;
      if (t > best[k]) best[k] = t;
      return;
    }
    if (m < 4 && c[i] >= 3) {
      c[i] -= 3;
      rec(i, p, m + 1, t);
      c[i] += 3;
    }
    if (m < 4 && i <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
      c[i]--;
      c[i + 1]--;
      c[i + 2]--;
      rec(i, p, m + 1, t);
      c[i]++;
      c[i + 1]++;
      c[i + 2]++;
    }
    if (c[i] >= 2) {
      c[i] -= 2;
      if (p == 0) rec(i, 1, m, t);
      rec(i, p, m, t + 1);
      c[i] += 2;
    }
    if (i <= 7 && c[i + 1] > 0) {
      c[i]--;
      c[i + 1]--;
      rec(i, p, m, t + 1);
      c[i]++;
      c[i + 1]++;
    }
    if (i <= 6 && c[i + 2] > 0) {
      c[i]--;
      c[i + 2]--;
      rec(i, p, m, t + 1);
      c[i]++;
      c[i + 2]++;
    }
    c[i]--;
    rec(i, p, m, t);
    c[i]++;
  }

  rec(0, 0, 0, 0);
  final out = <(int, int, int)>[];
  for (var p = 0; p < 2; p++) {
    for (var m = 0; m < 5; m++) {
      final t = best[p * 5 + m];
      if (t < 0) continue;
      // drop dominated entries
      var dominated = false;
      for (var m2 = m; m2 < 5 && !dominated; m2++) {
        for (var p2 = p; p2 < 2; p2++) {
          if ((m2 != m || p2 != p) && best[p2 * 5 + m2] >= t) {
            dominated = true;
            break;
          }
        }
      }
      if (!dominated) out.add((p, m, t));
    }
  }
  _suitMemo[key] = out;
  return out;
}

/// Shanten number (-1 = complete). Tiles of suit [que] are treated as useless.
int shanten(List<int> c, int meldCount, {int que = -1}) {
  final opts = <List<(int, int, int)>>[];
  for (var s = 0; s < 3; s++) {
    if (s == que) {
      opts.add(const [(0, 0, 0)]);
    } else {
      opts.add(_suitOptions(c.sublist(s * 9, s * 9 + 9)));
    }
  }
  var best = 8;
  for (final a in opts[0]) {
    for (final b in opts[1]) {
      final p2 = a.$1 + b.$1;
      if (p2 > 1) continue;
      for (final d in opts[2]) {
        final p = p2 + d.$1;
        if (p > 1) continue;
        var m = meldCount + a.$2 + b.$2 + d.$2;
        if (m > 4) m = 4;
        var t = a.$3 + b.$3 + d.$3;
        if (m + t > 4) t = 4 - m;
        final sh = 8 - 2 * m - t - p;
        if (sh < best) best = sh;
      }
    }
  }
  if (meldCount == 0) {
    var pairs = 0;
    for (var t = 0; t < 27; t++) {
      if (suitOf(t) != que) pairs += c[t] ~/ 2;
    }
    if (pairs > 7) pairs = 7;
    final sh7 = 6 - pairs;
    if (sh7 < best) best = sh7;
  }
  return best;
}

/// Heuristic "usefulness" of a tile in hand (lower = better discard).
int tileValue(List<int> c, int t) {
  final r = t % 9;
  var v = (c[t] - 1) * 4;
  for (final d in const [-2, -1, 1, 2]) {
    final r2 = r + d;
    if (r2 < 0 || r2 > 8) continue;
    if (c[t + d] > 0) v += d.abs() == 1 ? 3 : 2;
  }
  if (r == 0 || r == 8) {
    v -= 1;
  } else if (r >= 2 && r <= 6) {
    v += 1;
  }
  return v;
}
