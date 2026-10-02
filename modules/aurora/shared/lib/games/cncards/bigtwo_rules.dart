import 'cards.dart';

/// 锄大地 rules. Ranks 3<4<…<K<A<2, suits ♦<♣<♥<♠.
const String b2Ranks = '3456789TJQKA2';
const String b2Suits = 'DCHS';

int b2RankIdx(String c) => b2Ranks.indexOf(c[0]);
int b2SuitIdx(String c) => b2Suits.indexOf(cnSuit(c));

/// Unique card value 0..51 (♦3 = 0, ♠2 = 51).
int b2Value(String c) => b2RankIdx(c) * 4 + b2SuitIdx(c);

void b2Sort(List<String> cards) => cards.sort((a, b) => b2Value(a) - b2Value(b));

class B2Combo {
  /// single / pair / triple / five
  final String type;
  final int len;

  /// Comparable within the same [len].
  final int key;

  /// Display name, e.g. 顺子.
  final String label;
  const B2Combo(this.type, this.len, this.key, this.label);

  bool beats(B2Combo o) => len == o.len && key > o.key;

  Map<String, dynamic> toJson() => {'type': type, 'len': len, 'key': key, 'label': label};
  static B2Combo fromJson(Map m) => B2Combo('${m['type']}', (m['len'] as num).toInt(), (m['key'] as num).toInt(), '${m['label']}');
}

const List<String> b2FiveNames = ['', '顺子', '同花', '葫芦', '铁支', '同花顺'];

/// Natural-rank straight top (A2345 → 5, TJQKA → 14), or 0.
int _straightTop(List<int> nat) {
  final s = nat.toSet();
  if (s.length != 5) return 0;
  final l = s.toList()..sort();
  if (l[4] - l[0] == 4) return l[4];
  if (l[4] == 14 && l[0] == 2 && l[3] == 5) return 5; // A2345
  return 0;
}

/// Classifies [cards] or returns null if not a legal combo.
B2Combo? b2Classify(List<String> cards) {
  final n = cards.length;
  if (n == 0) return null;
  final vals = [for (final c in cards) b2Value(c)]..sort();
  final ranks = [for (final c in cards) b2RankIdx(c)];
  final sameRank = ranks.every((r) => r == ranks.first);
  switch (n) {
    case 1:
      return B2Combo('single', 1, vals.first, '单张');
    case 2:
      return sameRank ? B2Combo('pair', 2, vals.last, '对子') : null;
    case 3:
      return sameRank ? B2Combo('triple', 3, ranks.first, '三条') : null;
    case 5:
      final flush = cards.every((c) => cnSuit(c) == cnSuit(cards.first));
      final nat = [for (final c in cards) cnRank(c)];
      final top = _straightTop(nat);
      final cnt = <int, int>{};
      for (final r in ranks) {
        cnt[r] = (cnt[r] ?? 0) + 1;
      }
      int type, sub;
      if (top > 0) {
        // suit of the card holding the top natural rank
        final topCard = cards.firstWhere((c) => cnRank(c) == (top == 5 ? 5 : top));
        sub = top * 4 + b2SuitIdx(topCard);
        type = flush ? 5 : 1;
      } else if (cnt.values.contains(4)) {
        type = 4;
        sub = cnt.entries.firstWhere((e) => e.value == 4).key;
      } else if (cnt.values.contains(3) && cnt.values.contains(2)) {
        type = 3;
        sub = cnt.entries.firstWhere((e) => e.value == 3).key;
      } else if (flush) {
        type = 2;
        // compare by highest card, then next ones
        final d = vals.reversed.toList();
        sub = ((d[0] * 52 + d[1]) * 52 + d[2]);
      } else {
        return null;
      }
      return B2Combo('five', 5, type * 1000000 + sub, b2FiveNames[type]);
    default:
      return null;
  }
}

/// All legal plays from [hand] (each a list of cards) that beat [table]
/// (any combo if [table] is null). If [mustInclude] is set, plays must contain it.
List<List<String>> b2Candidates(List<String> hand, B2Combo? table, {String? mustInclude}) {
  final out = <List<String>>[];
  final lens = table == null ? const [1, 2, 3, 5] : [table.len];
  for (final len in lens) {
    if (len > hand.length) continue;
    for (final idx in cnCombos(hand.length, len)) {
      final cs = [for (final i in idx) hand[i]];
      if (mustInclude != null && !cs.contains(mustInclude)) continue;
      final c = b2Classify(cs);
      if (c == null) continue;
      if (table != null && !c.beats(table)) continue;
      out.add(cs);
    }
  }
  return out;
}

/// Sorted candidates for hints: same-length plays ordered from weakest to strongest.
List<List<String>> b2Hints(List<String> hand, B2Combo? table, {String? mustInclude}) {
  final c = b2Candidates(hand, table, mustInclude: mustInclude);
  c.sort((a, b) {
    if (table == null && a.length != b.length) return b.length - a.length;
    return b2Classify(a)!.key - b2Classify(b)!.key;
  });
  return c;
}
