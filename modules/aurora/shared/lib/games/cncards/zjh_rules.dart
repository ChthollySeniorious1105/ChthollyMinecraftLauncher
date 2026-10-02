import 'cards.dart';

/// 炸金花 hand evaluation (3 cards).
/// categories: 5 豹子, 4 同花顺, 3 同花(金花), 2 顺子, 1 对子, 0 散牌.
const List<String> zjhNames = ['散牌', '对子', '顺子', '金花', '顺金', '豹子'];

int zjhEval(List<String> cards) {
  final r = [for (final c in cards) cnRank(c)]..sort((a, b) => b - a);
  final flush = cards.every((c) => cnSuit(c) == cnSuit(cards.first));
  if (r[0] == r[2]) return cnPack(5, [r[0]]);
  var top = 0;
  if (r[0] - r[1] == 1 && r[1] - r[2] == 1) top = r[0];
  if (r[0] == 14 && r[1] == 3 && r[2] == 2) top = 3; // A23 最小顺子
  if (top > 0) return cnPack(flush ? 4 : 2, [top]);
  if (flush) return cnPack(3, r);
  if (r[0] == r[1]) return cnPack(1, [r[0], r[2]]);
  if (r[1] == r[2]) return cnPack(1, [r[1], r[0]]);
  return cnPack(0, r);
}

String zjhName(int score) => zjhNames[cnCategory(score)];

/// 杂色 2-3-5 (不同花色的 235 散牌)
bool zjhIs235(List<String> cards) {
  final r = [for (final c in cards) cnRank(c)]..sort();
  if (!(r[0] == 2 && r[1] == 3 && r[2] == 5)) return false;
  return !cards.every((c) => cnSuit(c) == cnSuit(cards.first));
}

/// Compare hand a vs hand b: >0 a wins, <0 b wins, 0 tie.
/// With [rule235], 杂色235 beats 豹子 (but loses to everything else).
int zjhCompare(List<String> a, List<String> b, {bool rule235 = false}) {
  final ea = zjhEval(a), eb = zjhEval(b);
  if (rule235) {
    if (zjhIs235(a) && cnCategory(eb) == 5) return 1;
    if (zjhIs235(b) && cnCategory(ea) == 5) return -1;
  }
  return ea.compareTo(eb);
}

/// Rough hand strength 0..1 used by bots.
double zjhStrength(List<String> cards) {
  final e = zjhEval(cards);
  final cat = cnCategory(e);
  final hi = (e >> 16) & 15;
  switch (cat) {
    case 5:
      return 0.99;
    case 4:
      return 0.96;
    case 3:
      return 0.85 + hi / 14 * 0.08;
    case 2:
      return 0.78 + hi / 14 * 0.06;
    case 1:
      return 0.5 + hi / 14 * 0.25;
    default:
      return hi / 14 * 0.45;
  }
}
