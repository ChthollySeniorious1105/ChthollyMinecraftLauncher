/// 台数计算 for 台湾十六张麻将.
///
/// Values used (常见台湾标准):
///   庄家1 · 连N拉N 2N · 门清1 · 自摸1 · 门清自摸3(取代门清/自摸) · 正花1(每组) · 花槓2(春夏秋冬或梅兰竹菊齐)
///   八仙过海8 · 七抢一8 · 圈风刻1 · 门风刻1 · 三元刻1 · 小三元4 · 大三元8 · 小四喜8 · 大四喜16
///   碰碰胡4 · 混一色4 · 清一色8 · 字一色16 · 平胡2 · 全求人2 · 海底捞月1 · 河底捞鱼1 · 杠上开花1 · 抢杠1
///   天胡16 · 地胡16 · 人胡8 · 独听(边张/中洞/单钓)1 · 三暗刻2 · 四暗刻5 · 五暗刻8
library;

import 'shapes.dart';
import 'tiles.dart';

class TaiCtx {
  final int winTile;
  final bool tsumo;
  final int seatWind; // 0..3 (庄家 = 东)
  final int roundWind; // 0..3
  final bool lastTile; // 海底捞月 (tsumo) / 河底捞鱼 (discard)
  final bool kongDraw; // 杠上开花
  final bool robKong; // 抢杠
  final bool tian, di, ren;
  final List<int> flowers; // flower tile ids 34..41
  const TaiCtx(this.winTile,
      {this.tsumo = false,
      this.seatWind = 0,
      this.roundWind = 0,
      this.lastTile = false,
      this.kongDraw = false,
      this.robKong = false,
      this.tian = false,
      this.di = false,
      this.ren = false,
      this.flowers = const []});
}

class TaiResult {
  /// (名称, 台数)
  final List<(String, int)> items;
  TaiResult(this.items);
  int get total => items.fold(0, (a, e) => a + e.$2);
  List<String> get names => [for (final e in items) e.$1];
  int of(String n) => items.where((e) => e.$1 == n).fold(0, (a, e) => a + e.$2);
  @override
  String toString() => '${items.map((e) => '${e.$1}${e.$2}').join(' ')} = $total';
}

/// Flower 台 for a seat: 正花 1 per group containing the seat's flower, 花槓 2 for a complete group,
/// 八仙过海 8 for all eight (replaces the rest).
List<(String, int)> flowerTai(List<int> flowers, int seatWind) {
  final set = flowers.toSet();
  if (set.length >= 8) return const [('八仙过海', 8)];
  final out = <(String, int)>[];
  const groupNames = ['春夏秋冬', '梅兰竹菊'];
  for (var g = 0; g < 2; g++) {
    final base = kFlowerBase + g * 4;
    final full = [for (var i = 0; i < 4; i++) base + i].every(set.contains);
    if (full) {
      out.add(('花槓(${groupNames[g]})', 2));
    } else if (set.contains(base + seatWind)) {
      out.add(('正花(${flowerNames[base + seatWind - kFlowerBase]})', 1));
    }
  }
  return out;
}

/// A set in a full-hand decomposition.
class _Set {
  final bool chow;
  final int tile;
  final bool open; // from a called meld (暗杠 counts as closed)
  final bool concealedPung; // 暗刻 / 暗杠
  const _Set(this.chow, this.tile, {this.open = false, this.concealedPung = false});
}

/// Evaluate a complete hand. [concealed] = concealed counts INCLUDING the winning tile (3n+2 tiles).
/// Returns null if the shape is not a win.
TaiResult? evaluateTai(List<int> concealed, List<Meld> melds, TaiCtx ctx) {
  if (!isWinShape(concealed)) return null;
  final w = ctx.winTile;
  final before = List.of(concealed);
  before[w]--;
  final waitKinds = waitsOf(before).length;
  TaiResult? best;
  for (final (pair, sets) in standardDecomps(concealed)) {
    // choose which element holds the winning tile: -1 = pair, i = sets[i]
    final slots = <int>[
      if (pair == w) -1,
      for (var i = 0; i < sets.length; i++)
        if (sets[i].contains(w)) i,
    ];
    for (final slot in slots) {
      final r = _evalOne(pair, sets, slot, melds, ctx, waitKinds);
      if (best == null || r.total > best.total) best = r;
    }
  }
  return best;
}

TaiResult _evalOne(int pair, List<TSet> hs, int slot, List<Meld> melds, TaiCtx ctx, int waitKinds) {
  final w = ctx.winTile;
  final sets = <_Set>[
    for (var i = 0; i < hs.length; i++)
      _Set(hs[i].chow, hs[i].tile,
          // a pung completed by a discard is 明刻
          concealedPung: !hs[i].chow && !(i == slot && !ctx.tsumo)),
    for (final m in melds) _Set(m.isChi, m.tile, open: m.kind != 'agang', concealedPung: m.kind == 'agang'),
  ];
  final items = <(String, int)>[];
  void add(String n, int v) => items.add((n, v));

  final openMelds = melds.where((m) => m.kind != 'agang').length;
  final menqing = openMelds == 0;
  final special = ctx.tian || ctx.di;

  // --- 天/地/人胡
  if (ctx.tian) add('天胡', 16);
  if (ctx.di) add('地胡', 16);
  if (ctx.ren) add('人胡', 8);

  // --- 门清 / 自摸
  if (!special) {
    if (menqing && ctx.tsumo) {
      add('门清自摸', 3);
    } else {
      if (menqing && !ctx.ren) add('门清', 1);
      if (ctx.tsumo) add('自摸', 1);
    }
  }

  // --- 全求人
  if (openMelds == kSets && !ctx.tsumo) add('全求人', 2);

  // --- 特殊时机
  if (ctx.lastTile) add(ctx.tsumo ? '海底捞月' : '河底捞鱼', 1);
  if (ctx.kongDraw && ctx.tsumo) add('杠上开花', 1);
  if (ctx.robKong) add('抢杠', 1);

  // --- 花牌
  items.addAll(flowerTai(ctx.flowers, ctx.seatWind));

  // --- 字牌
  final pungs = [for (final s in sets) if (!s.chow) s.tile];
  final windPungs = pungs.where(isWind).toList();
  final dragonPungs = pungs.where(isDragon).toList();
  if (windPungs.length == 4) {
    add('大四喜', 16);
  } else if (windPungs.length == 3 && isWind(pair)) {
    add('小四喜', 8);
  } else {
    for (final t in windPungs) {
      if (t - 27 == ctx.roundWind) add('圈风(${windNames[t - 27]})', 1);
      if (t - 27 == ctx.seatWind) add('门风(${windNames[t - 27]})', 1);
    }
  }
  if (dragonPungs.length == 3) {
    add('大三元', 8);
  } else if (dragonPungs.length == 2 && isDragon(pair)) {
    add('小三元', 4);
  } else {
    for (final t in dragonPungs) {
      add('三元牌(${honorNames[t - 27]})', 1);
    }
  }

  // --- 花色
  final suits = <int>{};
  var honors = isHonor(pair);
  if (!isHonor(pair)) suits.add(suitOf(pair));
  for (final s in sets) {
    if (isHonor(s.tile)) {
      honors = true;
    } else {
      suits.add(suitOf(s.tile));
    }
  }
  final allPung = sets.every((s) => !s.chow);
  if (suits.isEmpty) {
    add('字一色', 16);
  } else {
    if (allPung) add('碰碰胡', 4);
    if (suits.length == 1) add(honors ? '混一色' : '清一色', honors ? 4 : 8);
  }

  // --- 暗刻
  final anke = sets.where((s) => s.concealedPung).length;
  if (anke >= 5) {
    add('五暗刻', 8);
  } else if (anke == 4) {
    add('四暗刻', 5);
  } else if (anke == 3) {
    add('三暗刻', 2);
  }

  // --- 听牌形
  String? waitName;
  var ryanmen = false;
  if (slot < 0) {
    waitName = '单钓';
  } else if (hs[slot].chow) {
    final lo = hs[slot].tile;
    final r = rankOf(lo);
    if (w == lo + 1) {
      waitName = '中洞';
    } else if ((w == lo + 2 && r == 1) || (w == lo && r == 7)) {
      waitName = '边张';
    } else {
      ryanmen = true;
    }
  }
  if (waitKinds == 1 && !special) add(waitName ?? '独听', 1);

  // --- 平胡: 无花无字、五组皆顺、胡两面、非自摸
  if (ctx.flowers.isEmpty &&
      !honors &&
      sets.every((s) => s.chow) &&
      !ctx.tsumo &&
      ryanmen &&
      waitKinds >= 2) {
    add('平胡', 2);
  }
  return TaiResult(items);
}
