/// 广东推倒胡 fan evaluation.
library;

import 'shapes.dart';
import 'tiles.dart';

/// Marker value for 爆胡 (limit) hands: always paid at the cap.
const int gdLimit = 99;

class GdCtx {
  final bool selfDrawn;
  final bool kongDraw; // 杠上开花
  final bool robKong; // 抢杠胡
  final bool lastTile; // 海底捞月
  final bool sevenPairs; // 七对 allowed
  final int flowers;
  const GdCtx(
      {this.selfDrawn = false,
      this.kongDraw = false,
      this.robKong = false,
      this.lastTile = false,
      this.sevenPairs = true,
      this.flowers = 0});
}

class GdResult {
  final List<(String, int)> items;
  const GdResult(this.items);
  bool get limit => items.any((e) => e.$2 >= gdLimit);
  int get fan => limit ? gdLimit : items.fold(0, (a, e) => a + e.$2);
  List<String> get names => [for (final e in items) e.$1];
  @override
  String toString() => '${[for (final (n, f) in items) '$n$f'].join(' ')} = $fan';
}

/// Evaluate a Guangdong win. [concealed] includes the winning tile. Null if not a win.
GdResult? evaluateGd(List<int> concealed, List<Meld> melds, GdCtx ctx) {
  final total = countTotal(concealed);
  if (total % 3 != 2) return null;
  final all = List.of(concealed);
  for (final m in melds) {
    for (final t in m.tiles) {
      all[t]++;
    }
  }
  final kinds = [for (var k = 0; k < kKinds; k++) if (all[k] > 0) k];
  final suits = {for (final k in kinds) if (k < 27) suitOf(k)};
  final hasHonor = kinds.any(isHonor);
  final extras = <(String, int)>[
    if (ctx.kongDraw) ('杠上开花', 1),
    if (ctx.robKong) ('抢杠胡', 1),
    if (ctx.lastTile) ('海底捞月', 1),
    if (ctx.selfDrawn) ('自摸加倍', 1),
    if (ctx.flowers > 0) ('花牌×${ctx.flowers}', ctx.flowers),
  ];
  GdResult? best;
  void consider(List<(String, int)> items) {
    final r = GdResult([...items, ...extras]);
    if (best == null || r.fan > best!.fan) best = r;
  }

  List<(String, int)> colour() {
    if (suits.isEmpty) return [('字一色', gdLimit)];
    if (suits.length == 1) return hasHonor ? [('混一色', 2)] : [('清一色', 4)];
    return [];
  }

  if (melds.isEmpty && isThirteenOrphans(concealed)) consider([('十三幺', gdLimit)]);
  if (melds.isEmpty && ctx.sevenPairs && isSevenPairs(concealed)) {
    consider([('七对', 4), ...colour()]);
  }
  for (final (pair, hand) in standardDecomps(concealed)) {
    final sets = [...hand, for (final m in melds) setFromMeld(m)];
    final items = <(String, int)>[];
    final pungs = sets.where((s) => s.pung).toList();
    final windP = pungs.where((p) => isWind(p.tile)).length;
    final dragP = pungs.where((p) => isDragon(p.tile)).length;
    if (windP == 4) items.add(('大四喜', gdLimit));
    if (dragP == 3) items.add(('大三元', gdLimit));
    if (windP == 3 && isWind(pair)) items.add(('小四喜', 6));
    if (dragP == 2 && isDragon(pair)) items.add(('小三元', 4));
    final allPung = pungs.length == 4;
    final allChow = pungs.isEmpty;
    items.addAll(colour());
    if (allPung) {
      items.add(('碰碰胡', 2));
    } else if (allChow && !hasHonor) {
      items.add(('平胡', 1));
    }
    if (items.isEmpty) items.add(('鸡胡', 0));
    consider(items);
  }
  return best;
}

/// Seat (relative to dealer: 0 庄, 1 下家, 2 对家, 3 上家) a 马 tile points to.
int horseTarget(int t) {
  if (t < 27) return (rankOf(t) - 1) % 4;
  if (t <= 30) return t - 27; // 东南西北
  if (t < 34) return const [2, 1, 0][t - 31]; // 白→对家 发→下家 中→庄
  return (t - 34) % 4; // flowers
}

/// Payment per payer for a Guangdong win: base × 2^fan, capped.
int gdPoints(int fan, int cap, {int base = 1}) {
  var v = base;
  for (var i = 0; i < fan && v < cap; i++) {
    v *= 2;
  }
  if (fan >= gdLimit || v > cap) v = cap;
  return v;
}

/// Settlement of a Guangdong win: seat -> delta.
///
/// [payers] = seats paying [pts] each (for 抢杠胡 the robbed seat pays for everyone).
/// Every 马 that points to the winner makes each payer pay [pts] once more.
List<int> gdSettle(int players, int winner, List<int> payers, int pts, int horseHits,
    {int robbedFrom = -1}) {
  final d = List.filled(players, 0);
  final each = pts * (1 + horseHits);
  for (final p in payers) {
    final who = robbedFrom >= 0 ? robbedFrom : p;
    d[who] -= each;
    d[winner] += each;
  }
  return d;
}
