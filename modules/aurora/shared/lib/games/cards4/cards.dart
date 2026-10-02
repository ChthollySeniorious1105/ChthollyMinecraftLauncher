/// Card helpers shared by the cards4 games (够级 / 保皇 / 双扣 / Gin Rummy).
///
/// Codes follow PlayingCard: rank in "23456789TJQKA" + suit in "SHDC"
/// (e.g. 'TH' = ♥10), 'BJ' 小王 / 'RJ' 大王. 保皇 adds two special cards:
/// 'EJ' 皇帝牌 (the largest card) and 'GJ' 侍卫牌 (a marked 大王).
library;

import '../../src/engine.dart';

const String c4Ranks = '3456789TJQKA2';
const String c4Suits = 'SHDC';
const Map<String, String> c4SuitSym = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

/// Shedding value: 3..10, J=11, Q=12, K=13, A=14, 2=15, 小王=16, 大王/侍卫牌=17, 皇帝牌=18.
int c4Val(String c) {
  switch (c) {
    case 'BJ':
      return 16;
    case 'RJ':
    case 'GJ':
      return 17;
    case 'EJ':
      return 18;
  }
  if (c.length != 2) return 0;
  final i = c4Ranks.indexOf(c[0]);
  return i < 0 ? 0 : i + 3;
}

bool c4IsJoker(String c) => c == 'BJ' || c == 'RJ' || c == 'GJ' || c == 'EJ';
String c4Suit(String c) => c4IsJoker(c) || c.length != 2 ? '' : c[1];
int c4SuitRank(String s) => switch (s) { 'S' => 4, 'H' => 3, 'C' => 2, 'D' => 1, _ => 0 };

String c4ValName(int v) => switch (v) {
      11 => 'J',
      12 => 'Q',
      13 => 'K',
      14 => 'A',
      15 => '2',
      16 => '小王',
      17 => '大王',
      18 => '皇帝牌',
      _ => '$v',
    };

String c4CardName(String c) {
  switch (c) {
    case 'BJ':
      return '小王';
    case 'RJ':
      return '大王';
    case 'GJ':
      return '侍卫牌';
    case 'EJ':
      return '皇帝牌';
  }
  return '${c4SuitSym[c4Suit(c)] ?? ''}${c4ValName(c4Val(c))}';
}

/// One 52-card deck, optionally with the two jokers.
List<String> c4Deck({bool jokers = true}) => [
      for (final r in c4Ranks.split('')) for (final s in c4Suits.split('')) '$r$s',
      if (jokers) ...['BJ', 'RJ'],
    ];

/// Sort ascending by shedding value, then suit.
void c4Sort(List<String> cards) => cards.sort((a, b) {
      final d = c4Val(a) - c4Val(b);
      return d != 0 ? d : c4SuitRank(c4Suit(a)) - c4SuitRank(c4Suit(b));
    });

/// Parses a client-supplied card list and checks the player holds all of them.
/// Throws [GameError] before anything is mutated.
List<String> c4Take(Object? raw, List<String> hand, {int max = 60}) {
  if (raw is! List || raw.isEmpty) throw GameError('请选择要出的牌');
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

void c4Remove(List<String> hand, List<String> cards) {
  for (final c in cards) {
    hand.remove(c);
  }
}

/// Per-value lists (value -> cards).
Map<int, List<String>> c4Groups(Iterable<String> hand) {
  final m = <int, List<String>>{};
  for (final c in hand) {
    (m[c4Val(c)] ??= []).add(c);
  }
  return m;
}
