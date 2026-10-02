/// Gin Rummy meld / deadwood logic.
///
/// Cards: rank in "A23456789TJQK" (A low) + suit "SHDC". Deadwood: A=1,
/// 2..9 face value, T/J/Q/K = 10. Melds: 3-4 of a rank, or 3+ consecutive of a suit.
library;

const String grRanks = 'A23456789TJQK';

int grRank(String c) => grRanks.indexOf(c[0]) + 1; // 1..13
String grSuit(String c) => c[1];
int grValue(String c) {
  final r = grRank(c);
  return r >= 10 ? 10 : r;
}

List<String> grDeck() => [for (final s in 'SHDC'.split('')) for (final r in grRanks.split('')) '$r$s'];

/// Sort by suit then rank (display order).
void grSort(List<String> cards) => cards.sort((a, b) {
      final s = 'SHCD'.indexOf(grSuit(a)) - 'SHCD'.indexOf(grSuit(b));
      return s != 0 ? s : grRank(a) - grRank(b);
    });

bool grIsMeld(List<String> m) {
  if (m.length < 3) return false;
  final r = m.map(grRank).toSet();
  if (r.length == 1) return m.length <= 4 && m.map(grSuit).toSet().length == m.length;
  if (m.map(grSuit).toSet().length != 1) return false;
  final rs = m.map(grRank).toList()..sort();
  for (var i = 1; i < rs.length; i++) {
    if (rs[i] != rs[i - 1] + 1) return false;
  }
  return true;
}

/// All melds formable from [cards] (as index lists).
List<List<int>> _allMelds(List<String> cards) {
  final out = <List<int>>[];
  final byRank = <int, List<int>>{};
  final bySuit = <String, List<int>>{};
  for (var i = 0; i < cards.length; i++) {
    (byRank[grRank(cards[i])] ??= []).add(i);
    (bySuit[grSuit(cards[i])] ??= []).add(i);
  }
  for (final g in byRank.values) {
    if (g.length >= 3) {
      if (g.length == 4) {
        out.add(List.of(g));
        for (var skip = 0; skip < 4; skip++) {
          out.add([for (var k = 0; k < 4; k++) if (k != skip) g[k]]);
        }
      } else {
        out.add(List.of(g));
      }
    }
  }
  for (final g in bySuit.values) {
    g.sort((a, b) => grRank(cards[a]) - grRank(cards[b]));
    for (var s = 0; s < g.length; s++) {
      for (var e = s + 2; e < g.length; e++) {
        if (grRank(cards[g[e]]) - grRank(cards[g[s]]) != e - s) break;
        out.add(g.sublist(s, e + 1));
      }
    }
  }
  return out;
}

class GrArrangement {
  final List<List<String>> melds;
  final List<String> deadwood;
  const GrArrangement(this.melds, this.deadwood);
  int get points => deadwood.fold(0, (a, c) => a + grValue(c));
}

/// Arrangement of [cards] with minimal deadwood points.
GrArrangement grBest(List<String> cards) {
  final n = cards.length;
  final melds = _allMelds(cards);
  final masks = [for (final m in melds) m.fold<int>(0, (a, i) => a | (1 << i))];
  final memo = <int, (int, int)>{}; // mask -> (points, chosen meld idx or -1-cardIdx)
  int solve(int mask) {
    if (mask == 0) return 0;
    final hit = memo[mask];
    if (hit != null) return hit.$1;
    var i = 0;
    while ((mask & (1 << i)) == 0) {
      i++;
    }
    var best = grValue(cards[i]) + solve(mask & ~(1 << i));
    var choice = -1 - i;
    for (var k = 0; k < melds.length; k++) {
      final mm = masks[k];
      if ((mm & (1 << i)) == 0 || (mm & mask) != mm) continue;
      final v = solve(mask & ~mm);
      if (v < best) {
        best = v;
        choice = k;
      }
    }
    memo[mask] = (best, choice);
    return best;
  }

  final full = (1 << n) - 1;
  solve(full);
  final outM = <List<String>>[];
  final dead = <String>[];
  var mask = full;
  while (mask != 0) {
    final ch = memo[mask]!.$2;
    if (ch < 0) {
      final i = -1 - ch;
      dead.add(cards[i]);
      mask &= ~(1 << i);
    } else {
      outM.add([for (final i in melds[ch]) cards[i]]..sort((a, b) => grRank(a) - grRank(b)));
      mask &= ~masks[ch];
    }
  }
  grSort(dead);
  return GrArrangement(outM, dead);
}

/// Lays [cards] off onto [melds] greedily (runs first). Returns the cards
/// that could be laid off and the extended melds, or null if not all fit.
(List<List<String>>, List<String>)? _layAll(List<List<String>> melds, List<String> cards) {
  final ms = [for (final m in melds) List.of(m)];
  final left = List.of(cards);
  var changed = true;
  while (left.isNotEmpty && changed) {
    changed = false;
    for (final c in List.of(left)) {
      for (final m in ms) {
        if (grIsMeld([...m, c])) {
          m.add(c);
          m.sort((a, b) => grRank(a) - grRank(b));
          left.remove(c);
          changed = true;
          break;
        }
      }
    }
  }
  return left.isEmpty ? (ms, cards) : null;
}

class GrLayoff {
  final GrArrangement own;
  final List<String> laid;
  final List<List<String>> knockerMelds;
  const GrLayoff(this.own, this.laid, this.knockerMelds);
}

/// Defender's best result against [knockerMelds]: own melds + layoffs minimising deadwood.
GrLayoff grDefend(List<String> hand, List<List<String>> knockerMelds, {bool allowLayoff = true}) {
  var best = GrLayoff(grBest(hand), const [], knockerMelds);
  if (!allowLayoff) return best;
  // only cards that could ever extend some knocker meld matter
  final cand = [
    for (final c in hand)
      if (knockerMelds.any((m) => grIsMeld([...m, c])) || _nearRun(knockerMelds, c)) c
  ];
  final n = cand.length;
  for (var mask = 1; mask < (1 << n); mask++) {
    final sub = [for (var i = 0; i < n; i++) if ((mask & (1 << i)) != 0) cand[i]];
    final lay = _layAll(knockerMelds, sub);
    if (lay == null) continue;
    final rest = List.of(hand);
    for (final c in sub) {
      rest.remove(c);
    }
    final arr = grBest(rest);
    if (arr.points < best.own.points) best = GrLayoff(arr, sub, lay.$1);
  }
  return best;
}

bool _nearRun(List<List<String>> melds, String c) {
  for (final m in melds) {
    if (m.map(grRank).toSet().length == 1) continue;
    if (grSuit(m.first) != grSuit(c)) continue;
    final lo = grRank(m.first), hi = grRank(m.last);
    final r = grRank(c);
    if (r >= lo - 2 && r <= hi + 2) return true;
  }
  return false;
}
