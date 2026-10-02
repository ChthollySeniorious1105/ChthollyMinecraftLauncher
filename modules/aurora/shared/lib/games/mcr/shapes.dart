/// Hand-shape helpers: decompositions, special forms, win check, waits, shanten.
library;

import 'tiles.dart';

/// A set in a decomposition (from the concealed hand or from a meld).
class MSet {
  final bool chow;
  final int tile; // chow: lowest tile
  final bool kong;

  /// Concealed pung/kong (暗刻/暗杠). Chows: true when from the concealed hand.
  final bool concealed;

  /// Comes from a called meld (chi/peng/明杠/暗杠 declared).
  final bool melded;
  const MSet(this.chow, this.tile, {this.kong = false, this.concealed = true, this.melded = false});

  MSet withConcealed(bool c) => MSet(chow, tile, kong: kong, concealed: c, melded: melded);
  bool contains(int t) => chow ? (t >= tile && t <= tile + 2) : t == tile;
  bool get pung => !chow;
  int get rank => rankOf(tile);
  int get suit => suitOf(tile);

  /// Tiles of the set (kong = 4).
  List<int> get tiles => chow ? [tile, tile + 1, tile + 2] : List.filled(kong ? 4 : 3, tile);
}

MSet setFromMeld(Meld m) =>
    MSet(m.isChi, m.tile, kong: m.isKong, concealed: m.kind == 'agang', melded: true);

/// Enumerate all ways to split [c] (34 counts) into sets only (no pair).
void decomposeSets(List<int> c, int i, List<MSet> cur, List<List<MSet>> out) {
  while (i < kKinds && c[i] == 0) {
    i++;
  }
  if (i >= kKinds) {
    out.add(List.of(cur));
    return;
  }
  if (c[i] >= 3) {
    c[i] -= 3;
    cur.add(MSet(false, i));
    decomposeSets(c, i, cur, out);
    cur.removeLast();
    c[i] += 3;
  }
  if (i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
    c[i]--;
    c[i + 1]--;
    c[i + 2]--;
    cur.add(MSet(true, i));
    decomposeSets(c, i, cur, out);
    cur.removeLast();
    c[i]++;
    c[i + 1]++;
    c[i + 2]++;
  }
}

bool _canSets(List<int> c, int i) {
  while (i < kKinds && c[i] == 0) {
    i++;
  }
  if (i >= kKinds) return true;
  if (c[i] >= 3) {
    c[i] -= 3;
    final ok = _canSets(c, i);
    c[i] += 3;
    if (ok) return true;
  }
  if (i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
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

/// Standard decompositions (pair + sets) of the concealed counts.
List<(int pair, List<MSet> sets)> standardDecomps(List<int> concealed) {
  final out = <(int, List<MSet>)>[];
  final w = List.of(concealed);
  for (var p = 0; p < kKinds; p++) {
    if (w[p] < 2) continue;
    w[p] -= 2;
    final res = <List<MSet>>[];
    decomposeSets(w, 0, [], res);
    w[p] += 2;
    for (final r in res) {
      out.add((p, r));
    }
  }
  return out;
}

bool isStandardWin(List<int> c) {
  final total = countTotal(c);
  if (total % 3 != 2) return false;
  final w = List.of(c);
  for (var p = 0; p < kKinds; p++) {
    if (w[p] >= 2) {
      w[p] -= 2;
      final ok = _canSets(w, 0);
      w[p] += 2;
      if (ok) return true;
    }
  }
  return false;
}

bool isSevenPairs(List<int> c) {
  if (countTotal(c) != 14) return false;
  for (final x in c) {
    if (x.isOdd) return false;
  }
  return true;
}

bool isThirteenOrphans(List<int> c) {
  if (countTotal(c) != 14) return false;
  var pair = false;
  for (final k in yaojiuKinds) {
    if (c[k] == 0) return false;
    if (c[k] == 2) pair = true;
  }
  return pair;
}

/// 全不靠 (incl. 七星不靠): 14 distinct tiles, numbers fit one knitted pattern.
bool isHonorsAndKnitted(List<int> c) {
  if (countTotal(c) != 14) return false;
  for (final x in c) {
    if (x > 1) return false;
  }
  for (final pat in knittedPatterns) {
    final set = pat.toSet();
    var ok = true;
    for (var t = 0; t < 27; t++) {
      if (c[t] > 0 && !set.contains(t)) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

/// 组合龙 decompositions: (pattern index, pair, rest sets).
List<(int, int, List<MSet>)> knittedDecomps(List<int> concealed) {
  final out = <(int, int, List<MSet>)>[];
  final total = countTotal(concealed);
  if (total != 14 && total != 11) return out;
  for (var i = 0; i < knittedPatterns.length; i++) {
    final pat = knittedPatterns[i];
    if (pat.any((t) => concealed[t] == 0)) continue;
    final w = List.of(concealed);
    for (final t in pat) {
      w[t]--;
    }
    for (final (p, sets) in standardDecomps(w)) {
      out.add((i, p, sets));
    }
  }
  return out;
}

bool isKnittedWin(List<int> c) => knittedDecomps(c).isNotEmpty;

/// Any MCR winning shape for the concealed tiles (3n+2) with [meldCount] melds.
bool isWinShape(List<int> c, int meldCount) {
  final total = countTotal(c);
  if (total % 3 != 2) return false;
  if (isStandardWin(c)) return true;
  if (meldCount == 0 && (isSevenPairs(c) || isThirteenOrphans(c) || isHonorsAndKnitted(c))) return true;
  if (meldCount <= 1 && isKnittedWin(c)) return true;
  return false;
}

/// Kinds completing a 3n+1 concealed hand.
List<int> waitsOf(List<int> c, int meldCount, {bool special = true}) {
  final out = <int>[];
  for (var k = 0; k < kKinds; k++) {
    if (c[k] >= 4) continue;
    c[k]++;
    final ok = special ? isWinShape(c, meldCount) : isStandardWin(c);
    c[k]--;
    if (ok) out.add(k);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Shanten (standard / 七对 / 十三幺 / 全不靠), adapted for 34 kinds.
// ---------------------------------------------------------------------------

final Map<int, List<int>> _suitCache = {};

List<int> _suitTable(List<int> c, int offset) {
  var key = 0;
  for (var i = 0; i < 9; i++) {
    key = key * 6 + c[offset + i];
  }
  final cached = _suitCache[key];
  if (cached != null) return cached;
  final a = [for (var i = 0; i < 9; i++) c[offset + i]];
  final table = List<int>.filled(10, -1);
  void dfs(int i, int m, int t, int p) {
    while (i < 9 && a[i] == 0) {
      i++;
    }
    if (i >= 9) {
      final idx = p * 5 + (m > 4 ? 4 : m);
      final tt = t > 8 ? 8 : t;
      if (table[idx] < tt) table[idx] = tt;
      return;
    }
    if (a[i] >= 3) {
      a[i] -= 3;
      dfs(i, m + 1, t, p);
      a[i] += 3;
    }
    if (i <= 6 && a[i + 1] > 0 && a[i + 2] > 0) {
      a[i]--;
      a[i + 1]--;
      a[i + 2]--;
      dfs(i, m + 1, t, p);
      a[i]++;
      a[i + 1]++;
      a[i + 2]++;
    }
    if (a[i] >= 2) {
      a[i] -= 2;
      if (p == 0) dfs(i, m, t, 1);
      dfs(i, m, t + 1, p);
      a[i] += 2;
    }
    if (i <= 7 && a[i + 1] > 0) {
      a[i]--;
      a[i + 1]--;
      dfs(i, m, t + 1, p);
      a[i]++;
      a[i + 1]++;
    }
    if (i <= 6 && a[i + 2] > 0) {
      a[i]--;
      a[i + 2]--;
      dfs(i, m, t + 1, p);
      a[i]++;
      a[i + 2]++;
    }
    a[i]--;
    dfs(i, m, t, p);
    a[i]++;
  }

  dfs(0, 0, 0, 0);
  if (_suitCache.length > 400000) _suitCache.clear();
  _suitCache[key] = table;
  return table;
}

List<int> _honorTable(List<int> c) {
  final table = List<int>.filled(10, -1);
  var m = 0, pairs = 0;
  for (var k = 27; k < 34; k++) {
    if (c[k] >= 3) {
      m++;
    } else if (c[k] == 2) {
      pairs++;
    }
  }
  final mm = m > 4 ? 4 : m;
  table[mm] = pairs;
  if (pairs > 0) table[5 + mm] = pairs - 1;
  return table;
}

List<int> _merge(List<int> a, List<int> b) {
  final r = List<int>.filled(10, -1);
  for (var pa = 0; pa < 2; pa++) {
    for (var ma = 0; ma < 5; ma++) {
      final ta = a[pa * 5 + ma];
      if (ta < 0) continue;
      for (var pb = 0; pb + pa < 2; pb++) {
        for (var mb = 0; mb < 5; mb++) {
          final tb = b[pb * 5 + mb];
          if (tb < 0) continue;
          final m = ma + mb > 4 ? 4 : ma + mb;
          final idx = (pa + pb) * 5 + m;
          final t = ta + tb;
          if (r[idx] < t) r[idx] = t;
        }
      }
    }
  }
  return r;
}

int standardShanten(List<int> c, int melds) {
  var t = _merge(_suitTable(c, 0), _suitTable(c, 9));
  t = _merge(t, _suitTable(c, 18));
  t = _merge(t, _honorTable(c));
  var best = 8;
  final need = 4 - melds;
  for (var p = 0; p < 2; p++) {
    for (var m = 0; m < 5; m++) {
      final tt = t[p * 5 + m];
      if (tt < 0) continue;
      final mm = m > need ? need : m;
      var ta = tt;
      if (ta > need - mm) ta = need - mm;
      final s = 8 - 2 * (mm + melds) - ta - p;
      if (s < best) best = s;
    }
  }
  return best;
}

int sevenPairsShanten(List<int> c) {
  var pairs = 0, kinds = 0;
  for (var k = 0; k < kKinds; k++) {
    if (c[k] > 0) kinds++;
    if (c[k] >= 2) pairs++;
  }
  return 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
}

int orphansShanten(List<int> c) {
  var kinds = 0;
  var pair = false;
  for (final k in yaojiuKinds) {
    if (c[k] > 0) kinds++;
    if (c[k] >= 2) pair = true;
  }
  return 13 - kinds - (pair ? 1 : 0);
}

int knittedHonorsShanten(List<int> c) {
  var best = 13;
  var honors = 0;
  for (var k = 27; k < 34; k++) {
    if (c[k] > 0) honors++;
  }
  for (final pat in knittedPatterns) {
    var n = 0;
    for (final t in pat) {
      if (c[t] > 0) n++;
    }
    final s = 13 - n - honors;
    if (s < best) best = s;
  }
  return best;
}

/// Overall shanten; -1 = complete.
int shanten(List<int> c, int melds, {bool special = true}) {
  var s = standardShanten(c, melds);
  if (special && melds == 0) {
    final a = sevenPairsShanten(c);
    if (a < s) s = a;
    final b = orphansShanten(c);
    if (b < s) s = b;
    final d = knittedHonorsShanten(c);
    if (d < s) s = d;
  }
  return s;
}
