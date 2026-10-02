/// 国标麻将 81 番 calculator.
///
/// Searches every decomposition (standard / 组合龙 / 七对 / 十三幺 / 全不靠) and every
/// placement of the winning tile, applies the exclusion principles and returns the maximum.
library;

import 'shapes.dart';
import 'tiles.dart';

/// Fan values (all 81 fans). '幺九刻(风)' is an internal alias for wind 幺九刻.
const Map<String, int> mcrFanValues = {
  '大四喜': 88, '大三元': 88, '绿一色': 88, '九莲宝灯': 88, '四杠': 88, '连七对': 88, '十三幺': 88,
  '清幺九': 64, '小四喜': 64, '小三元': 64, '字一色': 64, '四暗刻': 64, '一色双龙会': 64,
  '一色四同顺': 48, '一色四节高': 48,
  '一色四步高': 32, '三杠': 32, '混幺九': 32,
  '七对': 24, '七星不靠': 24, '全双刻': 24, '清一色': 24, '一色三同顺': 24, '一色三节高': 24,
  '全大': 24, '全中': 24, '全小': 24,
  '清龙': 16, '三色双龙会': 16, '一色三步高': 16, '全带五': 16, '三同刻': 16, '三暗刻': 16,
  '全不靠': 12, '组合龙': 12, '大于五': 12, '小于五': 12, '三风刻': 12,
  '花龙': 8, '推不倒': 8, '三色三同顺': 8, '三色三节高': 8, '无番和': 8, '妙手回春': 8,
  '海底捞月': 8, '杠上开花': 8, '抢杠和': 8,
  '碰碰和': 6, '混一色': 6, '三色三步高': 6, '五门齐': 6, '全求人': 6, '双暗杠': 6, '双箭刻': 6,
  '全带幺': 4, '不求人': 4, '双明杠': 4, '和绝张': 4,
  '箭刻': 2, '圈风刻': 2, '门风刻': 2, '门前清': 2, '平和': 2, '四归一': 2, '双同刻': 2,
  '双暗刻': 2, '暗杠': 2, '断幺': 2,
  '一般高': 1, '喜相逢': 1, '连六': 1, '老少副': 1, '幺九刻': 1, '明杠': 1, '缺一门': 1,
  '无字': 1, '边张': 1, '坎张': 1, '单钓将': 1, '自摸': 1, '花牌': 1,
  '幺九刻(风)': 1,
};

/// Exclusion principle: a fan in the key suppresses the listed fans.
const Map<String, List<String>> mcrExclusions = {
  '大四喜': ['圈风刻', '门风刻', '三风刻', '碰碰和', '幺九刻', '幺九刻(风)', '小四喜'],
  '大三元': ['双箭刻', '箭刻', '小三元'],
  '绿一色': ['混一色'],
  '九莲宝灯': ['清一色', '门前清', '不求人', '无字', '幺九刻'],
  '四杠': ['三杠', '双明杠', '明杠', '双暗杠', '暗杠', '单钓将', '碰碰和'],
  '连七对': ['清一色', '七对', '单钓将', '门前清', '不求人', '无字'],
  '十三幺': ['五门齐', '门前清', '不求人', '单钓将', '混幺九', '全带幺'],
  '清幺九': ['混幺九', '碰碰和', '全带幺', '幺九刻', '无字', '双同刻'],
  '小四喜': ['三风刻', '幺九刻(风)'],
  '三风刻': ['幺九刻(风)'],
  '小三元': ['双箭刻', '箭刻'],
  '字一色': ['碰碰和', '全带幺', '幺九刻', '幺九刻(风)', '混幺九'],
  '四暗刻': ['门前清', '碰碰和', '三暗刻', '双暗刻', '不求人'],
  '一色双龙会': ['平和', '七对', '清一色', '一般高', '老少副', '缺一门', '无字'],
  '一色四同顺': ['一色三同顺', '一般高', '四归一', '一色三节高'],
  '一色四节高': ['一色三同顺', '一色三节高', '碰碰和'],
  '一色四步高': ['一色三步高'],
  '三杠': ['双明杠', '明杠', '双暗杠', '暗杠'],
  '混幺九': ['碰碰和', '幺九刻', '幺九刻(风)', '全带幺'],
  '七对': ['门前清', '单钓将', '不求人'],
  '七星不靠': ['五门齐', '门前清', '不求人', '单钓将', '全不靠'],
  '全双刻': ['碰碰和', '断幺', '无字'],
  '清一色': ['无字'],
  '一色三同顺': ['一色三节高', '一般高'],
  '一色三节高': ['一色三同顺'],
  '全大': ['大于五', '无字'],
  '全中': ['断幺', '无字'],
  '全小': ['小于五', '无字'],
  '清龙': ['连六', '老少副'],
  '三色双龙会': ['喜相逢', '老少副', '无字', '平和'],
  '全带五': ['断幺', '无字'],
  '三同刻': ['双同刻'],
  '三暗刻': ['双暗刻'],
  '全不靠': ['五门齐', '门前清', '不求人', '单钓将'],
  '大于五': ['无字'],
  '小于五': ['无字'],
  '推不倒': ['缺一门'],
  '三色三同顺': ['喜相逢'],
  '妙手回春': ['自摸'],
  '杠上开花': ['自摸'],
  '抢杠和': ['和绝张'],
  '全求人': ['单钓将'],
  '双暗杠': ['双暗刻', '暗杠'],
  '双箭刻': ['箭刻'],
  '不求人': ['自摸', '门前清'],
  '双明杠': ['明杠'],
  '平和': ['无字'],
  '断幺': ['无字'],
};

/// Situation of a win.
class WinCtx {
  final int winTile;
  final bool selfDrawn;
  final int seatWind; // 0..3 东南西北
  final int roundWind;
  final bool lastTile; // 妙手回春 / 海底捞月
  final bool kongDraw; // 杠上开花
  final bool robKong; // 抢杠和
  final bool lastCopy; // 和绝张
  final int flowers;
  const WinCtx(this.winTile,
      {this.selfDrawn = false,
      this.seatWind = 0,
      this.roundWind = 0,
      this.lastTile = false,
      this.kongDraw = false,
      this.robKong = false,
      this.lastCopy = false,
      this.flowers = 0});
}

class FanItem {
  final String name;
  final int value;
  final int count;
  const FanItem(this.name, this.value, this.count);
  int get total => value * count;
  List<Object> toJson() => [name, value, count];
  @override
  String toString() => count > 1 ? '$name$value×$count' : '$name$value';
}

class McrResult {
  final List<FanItem> items;
  const McrResult(this.items);
  int get total => items.fold(0, (a, e) => a + e.total);

  /// Total excluding 花牌 (used for 8番起和).
  int get base => items.where((e) => e.name != '花牌').fold(0, (a, e) => a + e.total);
  List<String> get names => [for (final e in items) e.name];
  int count(String n) => items.where((e) => e.name == n).fold(0, (a, e) => a + e.count);
  bool has(String n) => items.any((e) => e.name == n);
  @override
  String toString() => '${items.join(' ')} = $total';
}

// ---------------------------------------------------------------------------

McrResult _finish(Map<String, int> f, WinCtx ctx) {
  // exclusions, strongest fans first
  final keys = f.keys.toList()..sort((a, b) => mcrFanValues[b]!.compareTo(mcrFanValues[a]!));
  for (final k in keys) {
    if (!f.containsKey(k)) continue;
    for (final x in mcrExclusions[k] ?? const <String>[]) {
      f.remove(x);
    }
  }
  if (f.isEmpty) f['无番和'] = 1;
  if (ctx.flowers > 0) f['花牌'] = ctx.flowers;
  // merge wind 幺九刻
  final w = f.remove('幺九刻(风)');
  if (w != null) f['幺九刻'] = (f['幺九刻'] ?? 0) + w;
  final items = [for (final e in f.entries) FanItem(e.key, mcrFanValues[e.key]!, e.value)];
  items.sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.name.compareTo(b.name));
  return McrResult(items);
}

void _add(Map<String, int> f, String n, [int c = 1]) {
  if (c <= 0) return;
  f[n] = (f[n] ?? 0) + c;
}

/// Fans that depend only on the multiset of all tiles.
void _globalFans(Map<String, int> f, List<int> all, List<Meld> melds) {
  final kinds = [for (var k = 0; k < kKinds; k++) if (all[k] > 0) k];
  final suits = <int>{for (final k in kinds) if (k < 27) suitOf(k)};
  final hasHonor = kinds.any(isHonor);
  final hasWind = kinds.any(isWind);
  final hasDragon = kinds.any(isDragon);
  if (!kinds.any(isNumber)) {
    _add(f, '字一色');
  } else if (suits.length == 1) {
    _add(f, hasHonor ? '混一色' : '清一色');
  }
  const green = {19, 20, 21, 23, 25, 32};
  if (kinds.every(green.contains)) _add(f, '绿一色');
  const tbd = {9, 10, 11, 12, 13, 16, 17, 19, 21, 22, 23, 25, 26, 31};
  if (kinds.every(tbd.contains)) _add(f, '推不倒');
  if (kinds.every(isTerminal)) {
    _add(f, '清幺九');
  } else if (kinds.every(isYaojiu) && hasHonor && kinds.any(isTerminal)) {
    _add(f, '混幺九');
  }
  if (!hasHonor) {
    final ranks = {for (final k in kinds) rankOf(k)};
    if (ranks.every((r) => r >= 7)) {
      _add(f, '全大');
    } else if (ranks.every((r) => r >= 4 && r <= 6)) {
      _add(f, '全中');
    } else if (ranks.every((r) => r <= 3)) {
      _add(f, '全小');
    }
    if (ranks.every((r) => r >= 6)) _add(f, '大于五');
    if (ranks.every((r) => r <= 4)) _add(f, '小于五');
    _add(f, '无字');
  }
  if (!kinds.any(isYaojiu)) _add(f, '断幺');
  if (suits.length == 2) _add(f, '缺一门');
  if (suits.length == 3 && hasWind && hasDragon) _add(f, '五门齐');
  var gui = 0;
  for (final k in kinds) {
    if (all[k] == 4 && !melds.any((m) => m.isKong && m.tile == k)) gui++;
  }
  _add(f, '四归一', gui);
}

void _situational(Map<String, int> f, WinCtx ctx) {
  if (ctx.selfDrawn) _add(f, '自摸');
  if (ctx.lastTile) _add(f, ctx.selfDrawn ? '妙手回春' : '海底捞月');
  if (ctx.kongDraw) _add(f, '杠上开花');
  if (ctx.robKong) _add(f, '抢杠和');
  if (ctx.lastCopy) _add(f, '和绝张');
}

void _concealment(Map<String, int> f, List<Meld> melds, WinCtx ctx) {
  final open = melds.where((m) => m.kind != 'agang').length;
  if (open == 0) {
    _add(f, ctx.selfDrawn ? '不求人' : '门前清');
  } else if (open == 4 && !ctx.selfDrawn) {
    _add(f, '全求人');
  }
}

void _kongFans(Map<String, int> f, List<Meld> melds) {
  final an = melds.where((m) => m.kind == 'agang').length;
  final ming = melds.where((m) => m.isKong).length - an;
  final n = an + ming;
  if (n == 4) {
    _add(f, '四杠');
  } else if (n == 3) {
    _add(f, '三杠');
  } else if (n == 2) {
    if (an == 2) {
      _add(f, '双暗杠');
    } else if (ming == 2) {
      _add(f, '双明杠');
    } else {
      _add(f, '明杠');
      _add(f, '暗杠');
    }
  } else if (n == 1) {
    _add(f, an == 1 ? '暗杠' : '明杠');
  }
}

/// Pair relation between two chows (一般高/喜相逢/连六/老少副).
String? _chowRel(MSet a, MSet b) {
  if (a.suit == b.suit) {
    if (a.tile == b.tile) return '一般高';
    final d = (a.rank - b.rank).abs();
    if (d == 3) return '连六';
    if (d == 6) return '老少副';
    return null;
  }
  return a.rank == b.rank ? '喜相逢' : null;
}

String? _chowTriple(List<MSet> c) {
  final s = [...c]..sort((a, b) => a.tile.compareTo(b.tile));
  final suits = {for (final x in s) x.suit};
  final ranks = [for (final x in s) x.rank]..sort();
  if (suits.length == 1) {
    if (ranks[0] == ranks[1] && ranks[1] == ranks[2]) return '一色三同顺';
    if (ranks[0] == 1 && ranks[1] == 4 && ranks[2] == 7) return '清龙';
    final d1 = ranks[1] - ranks[0], d2 = ranks[2] - ranks[1];
    if (d1 == d2 && (d1 == 1 || d1 == 2)) return '一色三步高';
    return null;
  }
  if (suits.length == 3) {
    if (ranks[0] == ranks[1] && ranks[1] == ranks[2]) return '三色三同顺';
    if (ranks[0] == 1 && ranks[1] == 4 && ranks[2] == 7) return '花龙';
    if (ranks[1] - ranks[0] == 1 && ranks[2] - ranks[1] == 1) return '三色三步高';
  }
  return null;
}

String? _pungTriple(List<MSet> p) {
  if (p.any((x) => !isNumber(x.tile))) return null;
  final suits = {for (final x in p) x.suit};
  final ranks = [for (final x in p) x.rank]..sort();
  if (suits.length == 1) {
    return ranks[1] - ranks[0] == 1 && ranks[2] - ranks[1] == 1 ? '一色三节高' : null;
  }
  if (suits.length == 3) {
    if (ranks[0] == ranks[1] && ranks[1] == ranks[2]) return '三同刻';
    if (ranks[1] - ranks[0] == 1 && ranks[2] - ranks[1] == 1) return '三色三节高';
  }
  return null;
}

String? _pungRel(MSet a, MSet b) =>
    isNumber(a.tile) && isNumber(b.tile) && a.suit != b.suit && a.rank == b.rank ? '双同刻' : null;

List<List<int>> _triples(int n) => [
      for (var i = 0; i < n; i++)
        for (var j = i + 1; j < n; j++)
          for (var k = j + 1; k < n; k++) [i, j, k]
    ];

/// Combination fans among a group (chows or pungs) honouring 不重复/不拆移/套算一次.
void _groupFans(Map<String, int> f, List<MSet> g, String? Function(List<MSet>) triple,
    String? Function(MSet, MSet) rel) {
  final n = g.length;
  if (n < 2) return;
  // best triple
  String? bestT;
  List<int>? bestIdx;
  for (final t in _triples(n)) {
    final name = triple([for (final i in t) g[i]]);
    if (name != null && (bestT == null || mcrFanValues[name]! > mcrFanValues[bestT]!)) {
      bestT = name;
      bestIdx = t;
    }
  }
  if (bestT != null) {
    _add(f, bestT);
    if (n == 4) {
      final rest = [for (var i = 0; i < 4; i++) if (!bestIdx!.contains(i)) i].first;
      final banned = mcrExclusions[bestT] ?? const <String>[];
      String? pick;
      for (final i in bestIdx!) {
        final r = rel(g[rest], g[i]);
        if (r != null && (pick == null || banned.contains(pick))) pick = r;
      }
      if (pick != null) _add(f, pick);
    }
    return;
  }
  // spanning forest of pair relations (each new set combines once)
  final parent = List.generate(n, (i) => i);
  int find(int x) => parent[x] == x ? x : (parent[x] = find(parent[x]));
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final r = rel(g[i], g[j]);
      if (r == null) continue;
      final a = find(i), b = find(j);
      if (a == b) continue;
      parent[a] = b;
      _add(f, r);
    }
  }
}

/// Fans for a standard (or 组合龙, when [knitted]) arrangement.
Map<String, int> _setFans(int pair, List<MSet> sets, List<Meld> melds, WinCtx ctx, bool knitted) {
  final f = <String, int>{};
  final chows = sets.where((s) => s.chow).toList();
  final pungs = sets.where((s) => s.pung).toList();
  if (knitted) _add(f, '组合龙');
  // winds / dragons
  final windP = pungs.where((p) => isWind(p.tile)).length;
  final dragP = pungs.where((p) => isDragon(p.tile)).length;
  if (windP == 4) {
    _add(f, '大四喜');
  } else if (windP == 3) {
    _add(f, isWind(pair) ? '小四喜' : '三风刻');
  }
  if (dragP == 3) {
    _add(f, '大三元');
  } else if (dragP == 2) {
    _add(f, isDragon(pair) ? '小三元' : '双箭刻');
  }
  for (final p in pungs) {
    final t = p.tile;
    if (isDragon(t)) {
      _add(f, '箭刻');
    } else if (isWind(t)) {
      final w = t - 27;
      final special = w == ctx.roundWind || w == ctx.seatWind;
      if (w == ctx.roundWind) _add(f, '圈风刻');
      if (w == ctx.seatWind) _add(f, '门风刻');
      if (!special) _add(f, '幺九刻(风)');
    } else if (isTerminal(t)) {
      _add(f, '幺九刻');
    }
  }
  if (!knitted && pungs.length == 4) _add(f, '碰碰和');
  // concealed pungs
  final an = pungs.where((p) => p.concealed).length;
  if (an == 4) {
    _add(f, '四暗刻');
  } else if (an == 3) {
    _add(f, '三暗刻');
  } else if (an == 2) {
    _add(f, '双暗刻');
  }
  _kongFans(f, melds);
  if (!knitted) {
    bool yj(MSet s) => s.chow ? (s.rank == 1 || s.rank == 7) : isYaojiu(s.tile);
    if (isYaojiu(pair) && sets.every(yj)) _add(f, '全带幺');
    bool five(MSet s) => isNumber(s.tile) && (s.chow ? s.rank >= 3 && s.rank <= 5 : s.rank == 5);
    if (isNumber(pair) && rankOf(pair) == 5 && sets.every(five)) _add(f, '全带五');
    if (pungs.length == 4 && isNumber(pair) && rankOf(pair).isEven &&
        pungs.every((p) => isNumber(p.tile) && p.rank.isEven)) {
      _add(f, '全双刻');
    }
  }
  if (chows.length == sets.length && isNumber(pair)) _add(f, '平和');
  // 双龙会
  var dragonMeet = false;
  if (chows.length == 4 && isNumber(pair) && rankOf(pair) == 5) {
    final low = chows.where((c) => c.rank == 1).toList();
    final high = chows.where((c) => c.rank == 7).toList();
    if (low.length == 2 && high.length == 2) {
      final ls = {for (final c in low) c.suit}, hs = {for (final c in high) c.suit};
      if (ls.length == 1 && hs.length == 1 && ls.first == hs.first && suitOf(pair) == ls.first) {
        _add(f, '一色双龙会');
        dragonMeet = true;
      } else if (ls.length == 2 && hs.length == 2 && ls.containsAll(hs) && !ls.contains(suitOf(pair))) {
        _add(f, '三色双龙会');
        dragonMeet = true;
      }
    }
  }
  // 4-chow / 4-pung fans
  var fourChow = false;
  if (chows.length == 4 && {for (final c in chows) c.suit}.length == 1) {
    final r = [for (final c in chows) c.rank]..sort();
    if (r.every((x) => x == r[0])) {
      _add(f, '一色四同顺');
      fourChow = true;
    } else {
      final d = r[1] - r[0];
      if ((d == 1 || d == 2) && r[2] - r[1] == d && r[3] - r[2] == d) {
        _add(f, '一色四步高');
        fourChow = true;
      }
    }
  }
  if (!fourChow && !dragonMeet) _groupFans(f, chows, _chowTriple, _chowRel);
  var fourPung = false;
  if (pungs.length == 4 && pungs.every((p) => isNumber(p.tile)) && {for (final p in pungs) p.suit}.length == 1) {
    final r = [for (final p in pungs) p.rank]..sort();
    if (r[1] - r[0] == 1 && r[2] - r[1] == 1 && r[3] - r[2] == 1) {
      _add(f, '一色四节高');
      fourPung = true;
    }
  }
  if (!fourPung) _groupFans(f, pungs, _pungTriple, _pungRel);
  return f;
}

bool _ninegates(List<int> pre, List<Meld> melds) {
  if (melds.isNotEmpty || countTotal(pre) != 13) return false;
  for (var s = 0; s < 3; s++) {
    const need = [3, 1, 1, 1, 1, 1, 1, 1, 3];
    var ok = true;
    for (var r = 0; r < 9 && ok; r++) {
      if (pre[s * 9 + r] != need[r]) ok = false;
    }
    if (ok) return true;
  }
  return false;
}

/// Evaluate a winning hand. [concealed] = 34 counts of concealed tiles INCLUDING the
/// winning tile. Returns the best result, or null if the tiles don't form a win.
McrResult? evaluateMcr(List<int> concealed, List<Meld> melds, WinCtx ctx) {
  if (!isWinShape(concealed, melds.length)) return null;
  final all = List.of(concealed);
  for (final m in melds) {
    for (final t in m.tiles) {
      all[t]++;
    }
  }
  final pre = List.of(concealed);
  pre[ctx.winTile]--;
  final uniqueWait = pre[ctx.winTile] >= 0 && waitsOf(pre, melds.length).length == 1;
  final nine = _ninegates(pre, melds);
  McrResult? best;
  void consider(Map<String, int> f) {
    final r = _finish(f, ctx);
    if (best == null || r.total > best!.total) best = r;
  }

  Map<String, int> common(Map<String, int> f) {
    _globalFans(f, all, melds);
    _situational(f, ctx);
    _concealment(f, melds, ctx);
    return f;
  }

  final meldSets = [for (final m in melds) setFromMeld(m)];

  void arrangement(int pair, List<MSet> hand, bool knitted, bool winInKnit) {
    // choose which concealed element takes the winning tile
    final slots = <int>[
      if (!winInKnit)
        for (var i = 0; i < hand.length; i++)
          if (hand[i].contains(ctx.winTile)) i,
      if (!winInKnit && pair == ctx.winTile) -1,
      if (winInKnit) -2,
    ];
    for (final slot in slots) {
      final sets = <MSet>[
        for (var i = 0; i < hand.length; i++)
          i == slot && hand[i].pung && !ctx.selfDrawn ? hand[i].withConcealed(false) : hand[i],
        ...meldSets,
      ];
      final f = _setFans(pair, sets, melds, ctx, knitted);
      if (uniqueWait) {
        if (slot == -1) {
          _add(f, '单钓将');
        } else if (slot >= 0 && hand[slot].chow) {
          final c = hand[slot];
          if (ctx.winTile == c.tile + 1) {
            _add(f, '坎张');
          } else if ((c.rank == 1 && ctx.winTile == c.tile + 2) || (c.rank == 7 && ctx.winTile == c.tile)) {
            _add(f, '边张');
          }
        }
      }
      if (nine) _add(f, '九莲宝灯');
      consider(common(f));
    }
  }

  for (final (p, sets) in standardDecomps(concealed)) {
    arrangement(p, sets, false, false);
  }
  if (melds.length <= 1) {
    for (final (pi, p, sets) in knittedDecomps(concealed)) {
      final inKnit = knittedPatterns[pi].contains(ctx.winTile);
      arrangement(p, sets, true, false);
      if (inKnit) arrangement(p, sets, true, true);
    }
  }
  if (melds.isEmpty) {
    if (isSevenPairs(concealed)) {
      final f = <String, int>{};
      final kinds = [for (var k = 0; k < kKinds; k++) if (concealed[k] > 0) k];
      final seven = kinds.length == 7 &&
          kinds.every(isNumber) &&
          {for (final k in kinds) suitOf(k)}.length == 1 &&
          kinds.last - kinds.first == 6;
      _add(f, seven ? '连七对' : '七对');
      if (uniqueWait) _add(f, '单钓将');
      consider(common(f));
    }
    if (isThirteenOrphans(concealed)) {
      final f = <String, int>{'十三幺': 1};
      consider(common(f));
    }
    if (isHonorsAndKnitted(concealed)) {
      final f = <String, int>{};
      final honors = [for (var k = 27; k < 34; k++) if (concealed[k] > 0) k].length;
      _add(f, honors == 7 ? '七星不靠' : '全不靠');
      if (knittedPatterns.any((p) => p.every((t) => concealed[t] > 0))) _add(f, '组合龙');
      consider(common(f));
    }
  }
  return best;
}
