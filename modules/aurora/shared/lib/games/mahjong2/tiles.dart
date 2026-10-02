/// Tile helpers shared by 长沙麻将 and 二人麻将 (private to the mahjong2 package).
///
/// Tiles are ints: 0..26 numbers (suit = t ~/ 9: 0 万 m, 1 筒 p, 2 条 s; rank = t % 9 + 1),
/// 27..30 东南西北, 31 白 32 发 33 中, 34..41 flowers 春夏秋冬梅兰竹菊.
library;

const int kKinds = 34;
const int kFlowerBase = 34;

const List<String> suitNames = ['万', '筒', '条'];
const String _suitLetters = 'mps';
const List<String> honorNames = ['东', '南', '西', '北', '白', '发', '中'];
const List<String> flowerNames = ['春', '夏', '秋', '冬', '梅', '兰', '竹', '菊'];
const List<String> windNames = ['东', '南', '西', '北'];

bool isFlower(int t) => t >= kFlowerBase && t < kFlowerBase + 8;
bool isHonor(int t) => t >= 27 && t < 34;
bool isWind(int t) => t >= 27 && t <= 30;
bool isDragon(int t) => t >= 31 && t <= 33;
bool isNumber(int t) => t >= 0 && t < 27;
int suitOf(int t) => t < 27 ? t ~/ 9 : 3;
int rankOf(int t) => t < 27 ? t % 9 + 1 : 0;
bool isTerminal(int t) => t < 27 && (t % 9 == 0 || t % 9 == 8);
bool isYaojiu(int t) => isTerminal(t) || isHonor(t);
bool is258(int t) => t < 27 && (t % 9 == 1 || t % 9 == 4 || t % 9 == 7);

String tileCode(int t) {
  if (t < 0) return 'back';
  if (t < 27) return '${t % 9 + 1}${_suitLetters[t ~/ 9]}';
  if (t < 34) return '${t - 26}z';
  if (t < 42) return '${t - 33}f';
  return 'back';
}

int tileFromCode(Object? c) {
  if (c is! String || c.length != 2) return -1;
  final r = int.tryParse(c[0]);
  if (r == null) return -1;
  final s = _suitLetters.indexOf(c[1]);
  if (s >= 0) return r >= 1 && r <= 9 ? s * 9 + r - 1 : -1;
  if (c[1] == 'z') return r >= 1 && r <= 7 ? 26 + r : -1;
  if (c[1] == 'f') return r >= 1 && r <= 8 ? 33 + r : -1;
  return -1;
}

String tileName(int t) {
  if (t < 0) return '?';
  if (t < 27) return '${'一二三四五六七八九'[t % 9]}${suitNames[t ~/ 9]}';
  if (t < 34) return honorNames[t - 27];
  if (t < 42) return flowerNames[t - 34];
  return '?';
}

/// Parse "123m456p11z" style strings into tile ids (tests / debugging).
List<int> parseTiles(String s) {
  final out = <int>[];
  final digits = <int>[];
  for (final ch in s.split('')) {
    if ('mpszf'.contains(ch)) {
      for (final d in digits) {
        out.add(tileFromCode('$d$ch'));
      }
      digits.clear();
    } else if (ch.trim().isNotEmpty) {
      digits.add(int.parse(ch));
    }
  }
  return out;
}

List<int> countsOf(Iterable<int> tiles) {
  final c = List<int>.filled(kKinds, 0);
  for (final t in tiles) {
    if (t >= 0 && t < kKinds) c[t]++;
  }
  return c;
}

int countTotal(List<int> c) {
  var n = 0;
  for (final x in c) {
    n += x;
  }
  return n;
}

List<String> codesOfCounts(List<int> c) => [
      for (var t = 0; t < kKinds; t++)
        for (var k = 0; k < c[t]; k++) tileCode(t)
    ];

/// A called / declared meld.
class Meld {
  /// 'chi' 吃, 'peng' 碰, 'mgang' 直杠(明杠), 'bgang' 补杠(明杠), 'agang' 暗杠
  String kind;

  /// For chi: the lowest tile of the sequence; otherwise the tile.
  final int tile;

  /// The tile taken from another player (-1 for 暗杠).
  final int claimed;

  /// Seat the tile came from (-1 for 暗杠).
  final int from;

  /// 长沙麻将 开杠 (as opposed to 补张).
  bool open;
  Meld(this.kind, this.tile, {this.claimed = -1, this.from = -1, this.open = false});

  bool get isKong => kind == 'mgang' || kind == 'bgang' || kind == 'agang';
  bool get isChi => kind == 'chi';
  bool get concealed => kind == 'agang';
  int get size => isKong ? 4 : 3;
  List<int> get tiles => isChi ? [tile, tile + 1, tile + 2] : List.filled(size, tile);

  Map<String, dynamic> toJson({bool hide = false}) => {
        'kind': kind,
        'tiles': hide ? const ['back', 'back', 'back', 'back'] : [for (final t in tiles) tileCode(t)],
        'claimed': claimed >= 0 ? tileCode(claimed) : null,
        'from': from,
        'open': open,
      };
}

// ---------------------------------------------------------------------------
// Decomposition
// ---------------------------------------------------------------------------

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
}

MSet setFromMeld(Meld m) => MSet(m.isChi, m.tile, kong: m.isKong, concealed: m.kind == 'agang', melded: true);

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
  if (countTotal(concealed) % 3 != 2) return out;
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
  if (countTotal(c) % 3 != 2) return false;
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

// ---------------------------------------------------------------------------
// Shanten (standard / 七对) for bots
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

/// Overall shanten (standard + 七对); -1 = complete.
int shanten(List<int> c, int melds) {
  var s = standardShanten(c, melds);
  if (melds == 0) {
    final a = sevenPairsShanten(c);
    if (a < s) s = a;
  }
  return s;
}

/// Heuristic "usefulness" of a tile in hand (lower = better discard).
int tileValue(List<int> c, int t) {
  var v = (c[t] - 1) * 4;
  if (t < 27) {
    final r = rankOf(t);
    for (var d = -2; d <= 2; d++) {
      if (d == 0) continue;
      final rr = r + d;
      if (rr < 1 || rr > 9) continue;
      if (c[t + d] > 0) v += d.abs() == 1 ? 3 : 2;
    }
    if (r == 1 || r == 9) {
      v -= 1;
    } else if (r >= 3 && r <= 7) {
      v += 1;
    }
  } else {
    v -= 1;
  }
  return v;
}
