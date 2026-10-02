/// 长沙麻将 hand evaluation: 小胡 / 大胡 / 起手胡.
library;

import 'tiles.dart';

/// Situational context for a 长沙 win.
class CsCtx {
  final bool selfDrawn;
  final bool haidi; // won with the last wall tile (海底捞月 / 海底炮)
  final bool kaiGang; // won with a 开杠 tile of your own (杠上开花)
  final bool gangPao; // won with another player's 开杠 tile (杠上炮)
  final bool rob; // 抢杠胡
  final bool tian; // 天胡
  final bool di; // 地胡
  const CsCtx({
    this.selfDrawn = false,
    this.haidi = false,
    this.kaiGang = false,
    this.gangPao = false,
    this.rob = false,
    this.tian = false,
    this.di = false,
  });
}

class CsResult {
  /// 大胡 items: (name, count). Empty = 小胡.
  final List<(String, int)> big;
  const CsResult(this.big);
  int get bigCount => big.fold(0, (a, e) => a + e.$2);
  bool get isBig => big.isNotEmpty;
  List<List<Object>> toJson() => isBig ? [for (final (n, k) in big) [n, k]] : [['小胡', 0]];
  String get label => isBig ? [for (final (n, k) in big) k > 1 ? '$n×$k' : n].join(' ') : '小胡';
}

List<int> _allCounts(List<int> concealed, List<Meld> melds) {
  final all = List.of(concealed);
  for (final m in melds) {
    for (final t in m.tiles) {
      all[t]++;
    }
  }
  return all;
}

bool _allJiang(List<int> all) {
  for (var t = 0; t < kKinds; t++) {
    if (all[t] > 0 && !is258(t)) return false;
  }
  return true;
}

/// Any 长沙 hand shape (not yet checking 2-5-8 将): standard, 七小对 or 将将胡.
bool csShape(List<int> concealed, List<Meld> melds) {
  if (countTotal(concealed) % 3 != 2) return false;
  if (isStandardWin(concealed)) return true;
  if (melds.isEmpty && isSevenPairs(concealed)) return true;
  return _allJiang(_allCounts(concealed, melds));
}

/// Evaluate a complete 长沙 hand ([concealed] includes the winning tile).
/// Returns null when it is not a legal win (e.g. 小胡 without a 2-5-8 将).
CsResult? csEvaluate(List<int> concealed, List<Meld> melds, CsCtx ctx) {
  if (!csShape(concealed, melds)) return null;
  final all = _allCounts(concealed, melds);
  final big = <(String, int)>[];
  final std = standardDecomps(concealed);
  final seven = melds.isEmpty && isSevenPairs(concealed);

  // 清一色
  final suits = <int>{for (var t = 0; t < 27; t++) if (all[t] > 0) suitOf(t)};
  if (suits.length == 1 && (std.isNotEmpty || seven)) big.add(('清一色', 1));
  // 将将胡
  if (_allJiang(all)) big.add(('将将胡', 1));
  // 碰碰胡
  if (melds.every((m) => !m.isChi) && std.any((d) => d.$2.every((s) => !s.chow))) big.add(('碰碰胡', 1));
  // 七小对 / 豪华七小对
  if (seven) {
    final quads = concealed.where((x) => x == 4).length;
    if (quads >= 2) {
      big.add(('双豪华七小对', 3));
    } else if (quads == 1) {
      big.add(('豪华七小对', 2));
    } else {
      big.add(('七小对', 1));
    }
  }
  // 全求人: everything called, single-tile wait won on a discard
  if (!ctx.selfDrawn && melds.length == 4 && melds.every((m) => m.kind != 'agang') && countTotal(concealed) == 2) {
    big.add(('全求人', 1));
  }
  if (ctx.tian) big.add(('天胡', 1));
  if (ctx.di) big.add(('地胡', 1));
  if (ctx.haidi) big.add((ctx.selfDrawn ? '海底捞月' : '海底炮', 1));
  if (ctx.kaiGang) big.add(('杠上开花', 1));
  if (ctx.gangPao) big.add(('杠上炮', 1));
  if (ctx.rob) big.add(('抢杠胡', 1));

  if (big.isNotEmpty) return CsResult(big);
  // 小胡 needs a standard shape with a 2-5-8 pair
  if (std.any((d) => is258(d.$1))) return const CsResult([]);
  return null;
}

/// True if the hand could win on [t] in *some* situation (used for 开杠 听牌 checks
/// and bots): any shape counts, since 杠上开花 is itself a 大胡.
bool csAnyShapeWith(List<int> concealed, List<Meld> melds, int t) {
  concealed[t]++;
  final ok = csShape(concealed, melds);
  concealed[t]--;
  return ok;
}

/// Tiles completing a 3n+1 hand as a legal (plain, no situational bonus) win.
List<int> csWaits(List<int> concealed, List<Meld> melds, {bool anyShape = false}) {
  final out = <int>[];
  for (var t = 0; t < 27; t++) {
    concealed[t]++;
    final ok = anyShape ? csShape(concealed, melds) : csEvaluate(concealed, melds, const CsCtx()) != null;
    concealed[t]--;
    if (ok) out.add(t);
  }
  return out;
}

/// 起手胡 types for a freshly dealt hand: (name, count).
List<(String, int)> csQishou(List<int> c) {
  final out = <(String, int)>[];
  final quads = [for (var t = 0; t < 27; t++) if (c[t] == 4) t];
  if (quads.isNotEmpty) out.add(('大四喜', quads.length));
  var any258 = false;
  for (var t = 0; t < 27; t++) {
    if (c[t] > 0 && is258(t)) any258 = true;
  }
  if (!any258) out.add(('板板胡', 1));
  final suits = <int>{for (var t = 0; t < 27; t++) if (c[t] > 0) suitOf(t)};
  if (suits.length < 3) out.add(('缺一色', 1));
  final trips = [for (var t = 0; t < 27; t++) if (c[t] >= 3) t].length;
  if (trips >= 2) out.add(('六六顺', trips >= 4 ? 2 : 1));
  return out;
}

/// Tiles to show for a 起手胡 declaration.
List<int> csQishouShow(List<int> c, String kind) {
  switch (kind) {
    case '大四喜':
      return [for (var t = 0; t < 27; t++) if (c[t] == 4) ...[t, t, t, t]];
    case '六六顺':
      final ts = [for (var t = 0; t < 27; t++) if (c[t] >= 3) t];
      return [for (final t in ts.take(4)) ...[t, t, t]];
    default:
      return [for (var t = 0; t < 27; t++) for (var k = 0; k < c[t]; k++) t];
  }
}
