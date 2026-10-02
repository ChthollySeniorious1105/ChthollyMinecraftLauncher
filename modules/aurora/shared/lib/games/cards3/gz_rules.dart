/// 拱猪 scoring.
library;

import 'cards.dart';

const String gzPig = 'QS';
const String gzSheep = 'JD';
const String gzTrans = 'TC';
const String gzHeartA = 'AH';
const List<String> gzExposable = [gzPig, gzSheep, gzTrans, gzHeartA];

/// Base heart value (negative): A-50 K-40 Q-30 J-20 10..5 = -10, 4..2 = 0.
int gzHeart(String c) {
  if (c3Suit(c) != 'H') return 0;
  final v = c3Trick(c);
  if (v == 14) return -50;
  if (v == 13) return -40;
  if (v == 12) return -30;
  if (v == 11) return -20;
  if (v >= 5) return -10;
  return 0;
}

bool gzIsScoring(String c) => c3Suit(c) == 'H' || c == gzPig || c == gzSheep || c == gzTrans;

/// Score of the scoring cards [taken] by one player.
/// [exposed]: cards that were 亮 (each doubles its own value; 变压器 ×4 instead of ×2).
int gzScore(List<String> taken, {Set<String> exposed = const {}}) {
  final hearts = taken.where((c) => c3Suit(c) == 'H').toList();
  final heartsExposed = exposed.contains(gzHeartA);
  final allHearts = hearts.length == 13;
  var heartSum = 0;
  if (allHearts) {
    heartSum = 200; // 全红
  } else {
    for (final c in hearts) {
      heartSum += gzHeart(c);
    }
  }
  if (heartsExposed) heartSum *= 2;
  var total = heartSum;
  final hasPig = taken.contains(gzPig);
  final hasSheep = taken.contains(gzSheep);
  final hasTrans = taken.contains(gzTrans);
  if (hasPig) {
    total += exposed.contains(gzPig) ? -200 : -100;
  }
  if (hasSheep) total += exposed.contains(gzSheep) ? 200 : 100;
  if (hasTrans) {
    final m = exposed.contains(gzTrans) ? 4 : 2;
    final others = hearts.isNotEmpty || hasPig || hasSheep;
    total = others ? total * m : 50 * m ~/ 2; // 只有变压器：+50（亮 +100）
  }
  return total;
}
