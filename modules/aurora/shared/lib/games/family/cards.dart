/// Card helpers for 抽乌龟 / 钓鱼 / 牌七.
///
/// Codes follow PlayingCard: rank in "A23456789TJQK" + suit in "SHCD";
/// 'RJ' is the big joker (抽乌龟 joker variant only).
library;

const String fmRanks = 'A23456789TJQK';
const String fmSuits = 'SHCD';
const Map<String, String> fmSuitSym = {'S': '♠', 'H': '♥', 'C': '♣', 'D': '♦'};

/// The 52-card deck (no jokers).
List<String> fmDeck() => [for (final s in fmSuits.split('')) for (final r in fmRanks.split('')) '$r$s'];

/// Rank letter of a card ('R' for the joker).
String fmRank(String c) => c[0];
String fmSuit(String c) => c[c.length - 1];

/// A=1 .. K=13 (joker 14).
int fmVal(String c) => c == 'RJ' || c == 'BJ' ? 14 : fmRanks.indexOf(c[0]) + 1;

/// Display name of a rank letter: 'T' -> '10'.
String fmRankName(String r) => r == 'T' ? '10' : r;

/// Display name of a card, e.g. ♠10, 大王.
String fmCardName(String c) {
  if (c == 'RJ') return '大王';
  if (c == 'BJ') return '小王';
  return '${fmSuitSym[fmSuit(c)] ?? ''}${fmRankName(fmRank(c))}';
}

/// Sort by rank then suit (jokers last).
int fmByRank(String a, String b) {
  final d = fmVal(a) - fmVal(b);
  if (d != 0) return d;
  return fmSuits.indexOf(fmSuit(a)) - fmSuits.indexOf(fmSuit(b));
}

/// Sort by suit (♠♥♣♦) then rank.
int fmBySuit(String a, String b) {
  final d = fmSuits.indexOf(fmSuit(a)) - fmSuits.indexOf(fmSuit(b));
  if (d != 0) return d;
  return fmVal(a) - fmVal(b);
}
