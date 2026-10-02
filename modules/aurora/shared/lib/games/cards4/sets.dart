/// Same-rank "set" combos used by 够级 and 保皇: N cards of one rank, with
/// 王 (小王/大王/侍卫牌) as wild fillers (挂王 / 配牌).
library;

import 'cards.dart';

class SetCombo {
  /// Rank of the naturals (3..15); for an all-joker set the smallest joker value.
  final int rank;
  final int size;

  /// Number of jokers used as fillers.
  final int jokers;
  const SetCombo(this.rank, this.size, this.jokers);

  bool get allJokers => jokers == size;

  String get label {
    final n = size == 1 ? '单张' : '$size张';
    final r = allJokers ? (rank == 16 && size > 1 ? '王' : c4ValName(rank)) : c4ValName(rank);
    return '$n$r${jokers > 0 && !allJokers ? '（挂$jokers王）' : ''}';
  }

  Map<String, dynamic> toJson() => {'rank': rank, 'size': size, 'jokers': jokers, 'label': label};
  static SetCombo? fromJson(Object? j) {
    if (j is! Map || j['rank'] is! num || j['size'] is! num) return null;
    return SetCombo((j['rank'] as num).toInt(), (j['size'] as num).toInt(), ((j['jokers'] as num?) ?? 0).toInt());
  }
}

/// Wild jokers for set games (皇帝牌 is never wild).
bool setWild(String c) => c == 'BJ' || c == 'RJ' || c == 'GJ';

/// Classifies [cards] as a set, or null. 皇帝牌 is only legal alone.
SetCombo? classifySet(List<String> cards) {
  if (cards.isEmpty) return null;
  if (cards.contains('EJ')) return cards.length == 1 ? const SetCombo(18, 1, 0) : null;
  final nat = cards.where((c) => !setWild(c)).toList();
  final j = cards.length - nat.length;
  if (nat.isEmpty) {
    final m = cards.map(c4Val).reduce((a, b) => a < b ? a : b);
    return SetCombo(m, cards.length, j);
  }
  final v = c4Val(nat.first);
  if (nat.any((c) => c4Val(c) != v)) return null;
  return SetCombo(v, cards.length, j);
}

/// Every distinct set of exactly [size] cards (or any size when null) that
/// can be formed from [hand] with rank above [above], using the fewest jokers
/// for each (rank, size). [allowed] filters natural ranks. Results are sorted
/// cheapest first: fewer jokers, then lower rank.
List<List<String>> setCandidates(List<String> hand,
    {int? size, int above = 0, bool Function(int rank)? allowed, int maxSize = 99, bool allowJokerOnly = true}) {
  final g = c4Groups(hand.where((c) => !setWild(c) && c != 'EJ'));
  final wild = hand.where(setWild).toList()..sort((a, b) => c4Val(a) - c4Val(b));
  final out = <(int, int, List<String>)>[];
  for (final e in g.entries) {
    final v = e.key;
    if (v <= above) continue;
    if (allowed != null && !allowed(v)) continue;
    final n = e.value.length;
    final sizes = size != null ? [size] : [for (var k = 1; k <= n && k <= maxSize; k++) k];
    for (final k in sizes) {
      final nat = n < k ? n : k;
      final need = k - nat;
      if (need > wild.length) continue;
      out.add((need, v, [...e.value.sublist(0, nat), ...wild.sublist(0, need)]));
    }
  }
  if (allowJokerOnly && wild.isNotEmpty) {
    // all-joker sets: use the biggest jokers so the rank (min) is as high as needed
    final sizes = size != null ? [size] : [for (var k = 1; k <= wild.length && k <= maxSize; k++) k];
    for (final k in sizes) {
      if (k > wild.length) continue;
      // choose k jokers whose minimum value > above, preferring the smallest such
      for (final minV in const [16, 17]) {
        if (minV <= above) continue;
        final pool = wild.where((c) => c4Val(c) >= minV).toList();
        if (pool.length < k) continue;
        out.add((k * 10, minV, pool.sublist(0, k)));
        break;
      }
    }
  }
  if (hand.contains('EJ') && (size == null || size == 1) && 18 > above) out.add((50, 18, ['EJ']));
  out.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final o in out) o.$3];
}
