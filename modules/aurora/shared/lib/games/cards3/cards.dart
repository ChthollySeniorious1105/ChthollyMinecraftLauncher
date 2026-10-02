/// Card helpers shared by the cards3 games (干瞪眼/五十K/争上游/拱猪/百家乐).
///
/// Codes follow PlayingCard: rank in "23456789TJQKA" + suit in "SHDC"
/// (e.g. 'TH' = ♥10), plus 'BJ' 小王 / 'RJ' 大王.
library;

import 'dart:math';

import '../../src/engine.dart';

const String c3Ranks = '3456789TJQKA2';
const String c3Suits = 'SHDC';
const Map<String, String> c3SuitSym = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

/// Shedding value: 3..10, J=11, Q=12, K=13, A=14, 2=15, 小王=16, 大王=17.
int c3Val(String c) {
  if (c == 'BJ') return 16;
  if (c == 'RJ') return 17;
  final i = c3Ranks.indexOf(c[0]);
  return i < 0 ? 0 : i + 3;
}

/// Trick-taking value (2 low, A high): 2..14. Jokers 0.
int c3Trick(String c) {
  if (c.length != 2 || c[1] == 'J') return 0;
  final r = c3Val(c);
  return r == 15 ? 2 : r;
}

bool c3IsJoker(String c) => c == 'BJ' || c == 'RJ';
String c3Suit(String c) => c3IsJoker(c) ? '' : c[1];

/// Suit order used for sorting / 纯510K: ♠ > ♥ > ♣ > ♦.
int c3SuitRank(String s) => switch (s) { 'S' => 4, 'H' => 3, 'C' => 2, 'D' => 1, _ => 0 };

String c3ValName(int v) => switch (v) {
      11 => 'J',
      12 => 'Q',
      13 => 'K',
      14 => 'A',
      15 => '2',
      16 => '小王',
      17 => '大王',
      _ => '$v',
    };

String c3CardName(String c) {
  if (c == 'BJ') return '小王';
  if (c == 'RJ') return '大王';
  return '${c3SuitSym[c3Suit(c)] ?? ''}${c3ValName(c3Val(c))}';
}

/// One 52-card deck, optionally with the two jokers.
List<String> c3Deck({bool jokers = true}) => [
      for (final r in c3Ranks.split('')) for (final s in c3Suits.split('')) '$r$s',
      if (jokers) ...['BJ', 'RJ'],
    ];

/// Sort ascending by shedding value, then suit.
void c3Sort(List<String> cards) => cards.sort((a, b) {
      final d = c3Val(a) - c3Val(b);
      return d != 0 ? d : c3SuitRank(c3Suit(a)) - c3SuitRank(c3Suit(b));
    });

List<String> c3Shuffled(List<String> cards, Random rng) => shuffled(cards, rng);

/// Parses a client-supplied card list and checks the player holds all of them.
/// Throws [GameError] before anything is mutated.
List<String> c3TakeCards(Object? raw, List<String> hand, {int max = 40}) {
  if (raw is! List) throw GameError('请选择要出的牌');
  if (raw.isEmpty) throw GameError('请选择要出的牌');
  if (raw.length > max || raw.length > hand.length) throw GameError('出牌数量不对');
  final pool = List.of(hand);
  final out = <String>[];
  for (final c in raw) {
    if (c is! String || c.length != 2) throw GameError('无效的牌');
    if (!pool.remove(c)) throw GameError('你没有这张牌');
    out.add(c);
  }
  return out;
}

/// Removes [cards] from [hand] (all must be present — call after [c3TakeCards]).
void c3Remove(List<String> hand, List<String> cards) {
  for (final c in cards) {
    hand.remove(c);
  }
}

/// Per-value counts of naturals (3..17).
Map<int, List<String>> c3Groups(List<String> hand) {
  final m = <int, List<String>>{};
  for (final c in hand) {
    (m[c3Val(c)] ??= []).add(c);
  }
  return m;
}
