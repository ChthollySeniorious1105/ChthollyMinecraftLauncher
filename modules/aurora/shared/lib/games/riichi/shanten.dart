/// Shanten calculation (standard / chiitoitsu / kokushi), waits and ukeire.
///
/// All functions work on a 34-length count array of the *concealed* tiles.
/// [melds] = number of called/declared melds (including ankan).
library;

import 'tiles.dart';

final Map<int, List<int>> _suitCache = {};

/// For one suit's 9 counts returns table[p*5+m] = max taatsu count (or -1),
/// p = pair taken as head (0/1), m = mentsu count (0..4).
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
    // triplet
    if (a[i] >= 3) {
      a[i] -= 3;
      dfs(i, m + 1, t, p);
      a[i] += 3;
    }
    // sequence
    if (i <= 6 && a[i + 1] > 0 && a[i + 2] > 0) {
      a[i]--;
      a[i + 1]--;
      a[i + 2]--;
      dfs(i, m + 1, t, p);
      a[i]++;
      a[i + 1]++;
      a[i + 2]++;
    }
    // pair (head or taatsu)
    if (a[i] >= 2) {
      a[i] -= 2;
      if (p == 0) dfs(i, m, t, 1);
      dfs(i, m, t + 1, p);
      a[i] += 2;
    }
    // ryanmen / penchan
    if (i <= 7 && a[i + 1] > 0) {
      a[i]--;
      a[i + 1]--;
      dfs(i, m, t + 1, p);
      a[i]++;
      a[i + 1]++;
    }
    // kanchan
    if (i <= 6 && a[i + 2] > 0) {
      a[i]--;
      a[i + 2]--;
      dfs(i, m, t + 1, p);
      a[i]++;
      a[i + 2]++;
    }
    // isolated
    a[i]--;
    dfs(i, m, t, p);
    a[i]++;
  }

  dfs(0, 0, 0, 0);
  // Monotone fill: fewer mentsu achievable implies at least same taatsu is fine
  // (not needed for correctness of max, keep raw).
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

int chiitoiShanten(List<int> c) {
  var pairs = 0, kinds = 0;
  for (var k = 0; k < 34; k++) {
    if (c[k] > 0) kinds++;
    if (c[k] >= 2) pairs++;
  }
  return 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
}

int kokushiShanten(List<int> c) {
  var kinds = 0;
  var pair = false;
  for (final k in yaochuKinds) {
    if (c[k] > 0) kinds++;
    if (c[k] >= 2) pair = true;
  }
  return 13 - kinds - (pair ? 1 : 0);
}

/// Overall shanten; -1 = complete hand.
int shanten(List<int> c, int melds) {
  var s = standardShanten(c, melds);
  if (melds == 0) {
    final a = chiitoiShanten(c);
    if (a < s) s = a;
    final b = kokushiShanten(c);
    if (b < s) s = b;
  }
  return s;
}

bool isAgariCounts(List<int> c, int melds) => shanten(c, melds) == -1;

/// Kinds that complete a 3n+1 hand. Waiting on a tile whose 4 copies are all
/// in the hand is not counted (karaten).
List<int> waitsOf(List<int> c, int melds, {bool Function(int k)? allowed}) {
  final out = <int>[];
  for (var k = 0; k < 34; k++) {
    if (allowed != null && !allowed(k)) continue;
    if (c[k] >= 4) continue;
    c[k]++;
    final ok = shanten(c, melds) == -1;
    c[k]--;
    if (ok) out.add(k);
  }
  return out;
}

/// Tiles (count) that reduce shanten of a 3n+1 hand. [visible] = counts of
/// tiles the player can see (own hand included), used to compute remaining.
int ukeire(List<int> c, int melds, List<int> visible, {bool Function(int k)? allowed}) {
  final base = shanten(c, melds);
  var total = 0;
  for (var k = 0; k < 34; k++) {
    if (allowed != null && !allowed(k)) continue;
    final left = 4 - visible[k];
    if (left <= 0) continue;
    c[k]++;
    final s = shanten(c, melds);
    c[k]--;
    if (s < base) total += left;
  }
  return total;
}
