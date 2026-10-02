/// 港式麻将 番数计算 + 半辣上 payout table.
library;

import 'shapes.dart';
import 'tiles.dart';

/// Marker value for 满贯 (limit) items.
const int hkLimit = -1;

class HkCtx {
  final int winTile;
  final bool selfDrawn;
  final int seatWind; // 0 东 .. 3 北
  final int roundWind;
  final bool lastTile; // 海底捞月 (self-drawn last tile)
  final bool kongDraw; // 杠上开花
  final bool robKong; // 抢杠
  final bool heaven; // 天和
  final bool earth; // 地和
  final List<int> flowers; // flower tile ids (34..41)
  final int maxFan; // 满贯番数
  final bool xiaosixiLimit; // 小四喜算满贯 (otherwise 6番)
  const HkCtx(this.winTile,
      {this.selfDrawn = false,
      this.seatWind = 0,
      this.roundWind = 0,
      this.lastTile = false,
      this.kongDraw = false,
      this.robKong = false,
      this.heaven = false,
      this.earth = false,
      this.flowers = const [],
      this.maxFan = 10,
      this.xiaosixiLimit = false});
}

class HkResult {
  /// (name, fan) — fan == [hkLimit] means 满贯.
  final List<(String, int)> items;
  final int maxFan;
  const HkResult(this.items, this.maxFan);
  bool get limit => items.any((e) => e.$2 == hkLimit);
  int get raw => items.fold(0, (a, e) => a + (e.$2 > 0 ? e.$2 : 0));

  /// Counted fan (capped at 满贯).
  int get fan => limit ? maxFan : (raw > maxFan ? maxFan : raw);
  List<String> get names => [for (final e in items) e.$1];
  bool has(String n) => names.contains(n);
  @override
  String toString() => '${[for (final (n, f) in items) '$n${f == hkLimit ? '满' : f}'].join(' ')} = $fan';
}

/// Flower fans: 正花 (own-seat flower) 1 each, 一台花 (full set of 4 seasons or
/// 4 plants) 2 instead of its 正花, 无花 1, 八仙过海 (all 8) 满贯.
List<(String, int)> flowerItems(List<int> flowers, int seatWind) {
  if (flowers.isEmpty) return [('无花', 1)];
  if (flowers.toSet().length >= 8) return [('八仙过海', hkLimit)];
  final out = <(String, int)>[];
  for (var set = 0; set < 2; set++) {
    final base = kFlowerBase + set * 4;
    final full = [for (var i = 0; i < 4; i++) base + i].every(flowers.contains);
    if (full) {
      out.add((set == 0 ? '一台花（春夏秋冬）' : '一台花（梅兰竹菊）', 2));
    } else if (flowers.contains(base + seatWind)) {
      out.add(('正花', 1));
    }
  }
  return out;
}

bool _isNineGates(List<int> c) {
  if (countTotal(c) != 14) return false;
  final kinds = [for (var k = 0; k < kKinds; k++) if (c[k] > 0) k];
  if (kinds.any((k) => k >= 27)) return false;
  final suit = suitOf(kinds.first);
  if (kinds.any((k) => suitOf(k) != suit)) return false;
  final b = suit * 9;
  if (c[b] < 3 || c[b + 8] < 3) return false;
  for (var r = 1; r < 8; r++) {
    if (c[b + r] < 1) return false;
  }
  return true;
}

/// Evaluate a HK win. [concealed] includes the winning tile. Null if not a win shape.
HkResult? evaluateHk(List<int> concealed, List<Meld> melds, HkCtx ctx) {
  final total = countTotal(concealed);
  if (total % 3 != 2) return null;
  if (!isWinShape(concealed, melds.length)) return null;
  final all = List.of(concealed);
  for (final m in melds) {
    for (final t in m.tiles) {
      all[t]++;
    }
  }
  final menqing = melds.every((m) => m.concealed);
  final kinds = [for (var k = 0; k < kKinds; k++) if (all[k] > 0) k];
  final suits = {for (final k in kinds) if (k < 27) suitOf(k)};
  final hasHonor = kinds.any(isHonor);

  final extras = <(String, int)>[
    if (ctx.heaven) ('天和', hkLimit),
    if (ctx.earth) ('地和', hkLimit),
    if (menqing) ('门前清', 1),
    if (ctx.selfDrawn) ('自摸', 1),
    if (ctx.lastTile && ctx.selfDrawn) ('海底捞月', 1),
    if (ctx.kongDraw && ctx.selfDrawn) ('杠上开花', 1),
    if (ctx.robKong) ('抢杠', 1),
    ...flowerItems(ctx.flowers, ctx.seatWind),
  ];

  HkResult? best;
  void consider(List<(String, int)> items) {
    final its = [...items, ...extras];
    final patternFan = items.fold(0, (a, e) => a + (e.$2 > 0 ? e.$2 : 0));
    if (patternFan == 0 && !items.any((e) => e.$2 == hkLimit)) its.insert(0, ('鸡和', 0));
    final r = HkResult(its, ctx.maxFan);
    if (best == null || r.fan > best!.fan || (r.fan == best!.fan && r.raw > best!.raw)) best = r;
  }

  List<(String, int)> colour() {
    if (suits.isEmpty) return [('字一色', hkLimit)];
    if (suits.length == 1) return hasHonor ? [('混一色', 3)] : [('清一色', 7)];
    return [];
  }

  if (melds.isEmpty && isThirteenOrphans(concealed)) consider([('十三幺', hkLimit)]);
  if (menqing && melds.isEmpty && _isNineGates(concealed)) consider([('九莲宝灯', hkLimit)]);

  for (final (pair, hand) in standardDecomps(concealed)) {
    // for a discard win, the set completed by the winning tile is not concealed
    final handSets = List.of(hand);
    if (!ctx.selfDrawn && pair != ctx.winTile && !hand.any((s) => s.chow && s.contains(ctx.winTile))) {
      final i = handSets.indexWhere((s) => s.pung && s.tile == ctx.winTile);
      if (i >= 0) handSets[i] = handSets[i].withConcealed(false);
    }
    final sets = [...handSets, for (final m in melds) setFromMeld(m)];
    final items = <(String, int)>[];
    final pungs = sets.where((s) => s.pung).toList();
    final windP = pungs.where((p) => isWind(p.tile)).length;
    final dragP = pungs.where((p) => isDragon(p.tile)).length;
    final concealedPungs = pungs.where((p) => p.concealed).length;
    var sixi = false, sanyuan = false;
    if (windP == 4) {
      items.add(('大四喜', hkLimit));
      sixi = true;
    } else if (windP == 3 && isWind(pair)) {
      items.add(('小四喜', ctx.xiaosixiLimit ? hkLimit : 6));
      sixi = true;
    }
    if (dragP == 3) {
      items.add(('大三元', 8));
      sanyuan = true;
    } else if (dragP == 2 && isDragon(pair)) {
      items.add(('小三元', 5));
      sanyuan = true;
    }
    if (concealedPungs == 4) items.add(('坎坎和', hkLimit));
    items.addAll(colour());
    if (pungs.length == 4) {
      items.add(('对对和', 3));
    } else if (pungs.isEmpty) {
      items.add(('平和', 1));
    }
    // 番子
    if (!sanyuan) {
      for (final p in pungs) {
        if (isDragon(p.tile)) items.add(('${honorNames[p.tile - 27]}刻', 1));
      }
    }
    if (!sixi) {
      for (final p in pungs) {
        if (!isWind(p.tile)) continue;
        final w = p.tile - 27;
        if (w == ctx.seatWind) items.add(('门风${windNames[w]}', 1));
        if (w == ctx.roundWind) items.add(('圈风${windNames[w]}', 1));
      }
    }
    consider(items);
  }
  return best;
}

/// 半辣上 table: amount the discarder pays (放铳) for [fan] 番 (already capped).
/// 0:2 1:4 2:8 3:16 4:32 | 5:48 6:64 7:96 8:128 9:192 10:256 11:384 12:512 13:768.
/// On 自摸 each of the other three pays half.
int hkPoints(int fan) {
  if (fan <= 0) return 2;
  if (fan <= 4) return 2 << fan;
  final k = fan - 4; // 1.. : 48, 64, 96, 128 ...
  final pow = 32 << ((k) ~/ 2);
  return k.isOdd ? pow * 3 ~/ 2 : pow;
}
