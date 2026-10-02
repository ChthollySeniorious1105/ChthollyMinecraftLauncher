/// Hand-shape helpers for 16-tile mahjong: decompositions (5 sets + pair), win check, waits, shanten.
library;

import 'tiles.dart';

/// Number of sets in a complete 16-tile hand (5 sets + 1 pair = 17 tiles).
const int kSets = 5;

/// A set in a decomposition.
class TSet {
  final bool chow;
  final int tile; // chow: lowest tile
  const TSet(this.chow, this.tile);
  bool contains(int t) => chow ? (t >= tile && t <= tile + 2) : t == tile;
}

/// Enumerate all ways to split [c] (34 counts) into sets only (no pair).
void decomposeSets(List<int> c, int i, List<TSet> cur, List<List<TSet>> out) {
  while (i < kKinds && c[i] == 0) {
    i++;
  }
  if (i >= kKinds) {
    out.add(List.of(cur));
    return;
  }
  if (c[i] >= 3) {
    c[i] -= 3;
    cur.add(TSet(false, i));
    decomposeSets(c, i, cur, out);
    cur.removeLast();
    c[i] += 3;
  }
  if (i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
    c[i]--;
    c[i + 1]--;
    c[i + 2]--;
    cur.add(TSet(true, i));
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
List<(int pair, List<TSet> sets)> standardDecomps(List<int> concealed) {
  final out = <(int, List<TSet>)>[];
  final w = List.of(concealed);
  for (var p = 0; p < kKinds; p++) {
    if (w[p] < 2) continue;
    w[p] -= 2;
    final res = <List<TSet>>[];
    decomposeSets(w, 0, [], res);
    w[p] += 2;
    for (final r in res) {
      out.add((p, r));
    }
  }
  return out;
}

bool isWinShape(List<int> c) {
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

/// Kinds completing a 3n+1 concealed hand. [used] = copies visible elsewhere is ignored:
/// a kind is a wait unless the hand itself holds all 4 copies.
List<int> waitsOf(List<int> c) {
  final out = <int>[];
  for (var k = 0; k < kKinds; k++) {
    if (c[k] >= 4) continue;
    c[k]++;
    final ok = isWinShape(c);
    c[k]--;
    if (ok) out.add(k);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Shanten for 5 sets + pair. Table index = pair * 6 + sets (sets capped at 5),
// value = max partial sets (taatsu) for that combination.
// ---------------------------------------------------------------------------

const int _m = kSets + 1;
final Map<int, List<int>> _suitCache = {};

List<int> _suitTable(List<int> c, int offset) {
  var key = 0;
  for (var i = 0; i < 9; i++) {
    key = key * 6 + c[offset + i];
  }
  final cached = _suitCache[key];
  if (cached != null) return cached;
  final a = [for (var i = 0; i < 9; i++) c[offset + i]];
  final table = List<int>.filled(2 * _m, -1);
  void dfs(int i, int m, int t, int p) {
    while (i < 9 && a[i] == 0) {
      i++;
    }
    if (i >= 9) {
      final idx = p * _m + (m > kSets ? kSets : m);
      final tt = t > 10 ? 10 : t;
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
  final table = List<int>.filled(2 * _m, -1);
  var m = 0, pairs = 0;
  for (var k = 27; k < 34; k++) {
    if (c[k] >= 3) {
      m++;
    } else if (c[k] == 2) {
      pairs++;
    }
  }
  final mm = m > kSets ? kSets : m;
  table[mm] = pairs;
  if (pairs > 0) table[_m + mm] = pairs - 1;
  return table;
}

List<int> _merge(List<int> a, List<int> b) {
  final r = List<int>.filled(2 * _m, -1);
  for (var pa = 0; pa < 2; pa++) {
    for (var ma = 0; ma < _m; ma++) {
      final ta = a[pa * _m + ma];
      if (ta < 0) continue;
      for (var pb = 0; pb + pa < 2; pb++) {
        for (var mb = 0; mb < _m; mb++) {
          final tb = b[pb * _m + mb];
          if (tb < 0) continue;
          final m = ma + mb > kSets ? kSets : ma + mb;
          final idx = (pa + pb) * _m + m;
          final t = ta + tb;
          if (r[idx] < t) r[idx] = t;
        }
      }
    }
  }
  return r;
}

/// Shanten of concealed counts [c] with [melds] declared melds; -1 = complete.
int shanten(List<int> c, int melds) {
  var t = _merge(_suitTable(c, 0), _suitTable(c, 9));
  t = _merge(t, _suitTable(c, 18));
  t = _merge(t, _honorTable(c));
  var best = 2 * kSets;
  final need = kSets - melds;
  for (var p = 0; p < 2; p++) {
    for (var m = 0; m < _m; m++) {
      final tt = t[p * _m + m];
      if (tt < 0) continue;
      final mm = m > need ? need : m;
      var ta = tt;
      if (ta > need - mm) ta = need - mm;
      final s = 2 * kSets - 2 * (mm + melds) - ta - p;
      if (s < best) best = s;
    }
  }
  return best;
}
