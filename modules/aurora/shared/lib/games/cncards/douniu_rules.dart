import 'cards.dart';

/// 斗牛 hand evaluation (5 cards).
/// Card points: A=1, 2-9 face, 10/J/Q/K = 10.
int dnPoint(String c) {
  final r = cnRank(c);
  if (r == 14) return 1;
  return r >= 10 ? 10 : r;
}

/// Natural rank for comparison with A low: A=1 … K=13.
int dnRankLow(String c) {
  final r = cnRank(c);
  return r == 14 ? 1 : r;
}

/// Suit order for ties: ♠>♥>♣>♦.
int dnSuitOrder(String c) => const {'D': 0, 'C': 1, 'H': 2, 'S': 3}[cnSuit(c)]!;

class DnResult {
  /// 0 = 没牛, 1..9 = 牛1..牛9, 10 = 牛牛, 11 = 五花牛, 12 = 炸弹牛, 13 = 五小牛
  final int level;

  /// Indices of the 3 cards summing to a multiple of 10 (empty when 没牛 or special).
  final List<int> three;
  final int maxCard; // tie-break: rank*4 + suit
  const DnResult(this.level, this.three, this.maxCard);

  int get score => level * 100 + maxCard;
}

const List<String> dnLevelNames = [
  '没牛', '牛一', '牛二', '牛三', '牛四', '牛五', '牛六', '牛七', '牛八', '牛九', '牛牛', '五花牛', '炸弹牛', '五小牛'
];

String dnName(int level) => dnLevelNames[level];

/// Evaluates [cards] (5 cards). [specials] enables 五花牛/炸弹牛/五小牛.
DnResult dnEval(List<String> cards, {bool specials = true}) {
  var maxCard = 0;
  for (final c in cards) {
    final k = dnRankLow(c) * 4 + dnSuitOrder(c);
    if (k > maxCard) maxCard = k;
  }
  final pts = [for (final c in cards) dnPoint(c)];
  if (specials) {
    final sum = pts.fold(0, (a, b) => a + b);
    if (cards.every((c) => dnRankLow(c) < 5) && sum <= 10) return DnResult(13, const [], maxCard);
    final cnt = <int, int>{};
    for (final c in cards) {
      cnt[dnRankLow(c)] = (cnt[dnRankLow(c)] ?? 0) + 1;
    }
    for (final e in cnt.entries) {
      if (e.value == 4) return DnResult(12, const [], e.key * 4 + 3);
    }
    if (cards.every((c) => dnRankLow(c) >= 11)) return DnResult(11, const [], maxCard);
  }
  var best = -1;
  List<int> bestThree = const [];
  for (final t in cnCombos(5, 3)) {
    final s3 = pts[t[0]] + pts[t[1]] + pts[t[2]];
    if (s3 % 10 != 0) continue;
    var rest = 0;
    for (var i = 0; i < 5; i++) {
      if (!t.contains(i)) rest += pts[i];
    }
    final lv = rest % 10 == 0 ? 10 : rest % 10;
    if (lv > best) {
      best = lv;
      bestThree = t;
    }
  }
  if (best < 0) return DnResult(0, const [], maxCard);
  return DnResult(best, bestThree, maxCard);
}

/// Payout multiplier for a hand level.
/// table 'std': 没牛~牛六 ×1, 牛七~牛九 ×2, 牛牛 ×3, 五花 ×4, 炸弹 ×5, 五小 ×6
/// table 'high': 牛几 ×几 (没牛 ×1), 牛牛 ×10, specials ×10 (疯狂模式)
int dnMult(int level, String table) {
  if (table == 'high') {
    if (level <= 1) return 1;
    if (level >= 10) return 10;
    return level;
  }
  if (level >= 13) return 6;
  if (level == 12) return 5;
  if (level == 11) return 4;
  if (level == 10) return 3;
  if (level >= 7) return 2;
  return 1;
}

/// Compare player vs banker: >0 player wins. Ties go by highest card.
int dnCompare(DnResult p, DnResult b) => p.score.compareTo(b.score);
