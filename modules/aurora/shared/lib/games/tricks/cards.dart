import 'dart:math';

/// Shared helpers for trick-taking games (桥牌 / 红心大战 / 黑桃王).
/// Card code = rank + suit, rank in 23456789TJQKA, suit in CDHS.

const String trRanks = '23456789TJQKA';
const String trSuits = 'CDHS';
const Map<String, String> trSuitSym = {'C': '♣', 'D': '♦', 'H': '♥', 'S': '♠', 'N': 'NT'};
const Map<String, String> trSuitName = {'C': '梅花', 'D': '方块', 'H': '红心', 'S': '黑桃', 'N': '无将'};

int trRank(String c) => trRanks.indexOf(c[0]);
String trSuit(String c) => c[1];

/// Human readable card, e.g. "♠A", "♥10".
String trCardName(String c) => '${trSuitSym[trSuit(c)]}${c[0] == 'T' ? '10' : c[0]}';

List<String> trDeck() => [for (final s in trSuits.split('')) for (final r in trRanks.split('')) '$r$s'];

/// Deal 4 hands of 13.
List<List<String>> trDeal(Random rng) {
  final d = trDeck()..shuffle(rng);
  return [for (var i = 0; i < 4; i++) trSort(d.sublist(i * 13, i * 13 + 13))];
}

/// Display order: ♠ ♥ ♣ ♦ (alternating colours), high to low inside a suit.
const Map<String, int> _dispOrder = {'S': 0, 'H': 1, 'C': 2, 'D': 3};

List<String> trSort(Iterable<String> cards) => cards.toList()
  ..sort((a, b) {
    final s = _dispOrder[trSuit(a)]!.compareTo(_dispOrder[trSuit(b)]!);
    return s != 0 ? s : trRank(b).compareTo(trRank(a));
  });

List<String> trOfSuit(Iterable<String> cards, String suit) => [for (final c in cards) if (trSuit(c) == suit) c];

/// Cards that may legally be played when [lead] suit was led (null = leading).
List<String> trFollow(List<String> hand, String? lead) {
  if (lead == null) return List.of(hand);
  final f = trOfSuit(hand, lead);
  return f.isEmpty ? List.of(hand) : f;
}

/// Index (into [cards]) of the winning card. [cards] are in play order, first is the lead.
int trWinner(List<String> cards, String? trump) {
  var best = 0;
  for (var i = 1; i < cards.length; i++) {
    if (trBeats(cards[i], cards[best], trSuit(cards[0]), trump)) best = i;
  }
  return best;
}

/// Does [a] beat current winner [b] given led suit and trump?
bool trBeats(String a, String b, String lead, String? trump) {
  final sa = trSuit(a), sb = trSuit(b);
  if (sa == sb) return trRank(a) > trRank(b);
  if (trump != null && sa == trump) return true;
  return false;
}

String? trLowest(Iterable<String> cards) {
  String? best;
  for (final c in cards) {
    if (best == null || trRank(c) < trRank(best)) best = c;
  }
  return best;
}

String? trHighest(Iterable<String> cards) {
  String? best;
  for (final c in cards) {
    if (best == null || trRank(c) > trRank(best)) best = c;
  }
  return best;
}

/// Is [c] the highest card of its suit not yet played (and not in [alsoKnown] ... excluded from outstanding)?
/// [gone] = cards already played or otherwise known to be out of the running.
bool trIsTop(String c, Set<String> gone) {
  final s = trSuit(c);
  for (var r = trRank(c) + 1; r < 13; r++) {
    if (!gone.contains('${trRanks[r]}$s')) return false;
  }
  return true;
}

List<String> trStrList(Object? v) => v is List ? [for (final e in v) '$e'] : <String>[];
