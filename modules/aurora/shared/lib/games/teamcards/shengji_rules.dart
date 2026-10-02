/// 升级（拖拉机）规则：主牌判定、牌序、牌型分解、跟牌合法性、比较。
///
/// 自然点数：2..14 = 2..A，16 = 小王，17 = 大王。
/// trump suit: 'S' 'H' 'D' 'C' 或 'N'（无主）。
library;

const _sjRanks = '23456789TJQKA';
const sjSuits = ['S', 'H', 'C', 'D'];
const sjSuitNames = {'S': '♠黑桃', 'H': '♥红桃', 'C': '♣梅花', 'D': '♦方块', 'N': '无主'};

int sjNat(String c) {
  if (c == 'BJ') return 16;
  if (c == 'RJ') return 17;
  return _sjRanks.indexOf(c[0]) + 2;
}

String sjSuit(String c) => (c == 'BJ' || c == 'RJ') ? 'J' : c[1];

String sjRankChar(int r) => _sjRanks[r - 2];

String sjRankName(int r) {
  if (r == 16) return '小王';
  if (r == 17) return '大王';
  if (r == 14) return 'A';
  if (r == 13) return 'K';
  if (r == 12) return 'Q';
  if (r == 11) return 'J';
  return '$r';
}

int sjPoints(String c) {
  final n = sjNat(c);
  if (n == 5) return 5;
  if (n == 10 || n == 13) return 10;
  return 0;
}

int sjPointsOf(Iterable<String> cards) => cards.fold(0, (a, c) => a + sjPoints(c));

List<String> sjDeck() {
  final out = <String>[];
  for (var d = 0; d < 2; d++) {
    for (final r in _sjRanks.split('')) {
      for (final s in sjSuits) {
        out.add('$r$s');
      }
    }
    out
      ..add('BJ')
      ..add('RJ');
  }
  return out;
}

/// Trump context for one deal.
class SjTrump {
  final int level;

  /// 'S','H','C','D' or 'N' (无主). May be '' while still undecided (declare phase).
  final String suit;
  const SjTrump(this.level, this.suit);

  bool isTrump(String c) {
    final n = sjNat(c);
    if (n >= 16 || n == level) return true;
    return suit.isNotEmpty && suit != 'N' && sjSuit(c) == suit;
  }

  /// 'T' for trumps, otherwise the suit letter.
  String cls(String c) => isTrump(c) ? 'T' : sjSuit(c);

  /// Order inside the card's class; equal-strength cards share a value.
  int order(String c) {
    final n = sjNat(c);
    if (n == 17) return 15;
    if (n == 16) return 14;
    if (n == level) return (suit == 'N' || sjSuit(c) == suit) ? 13 : 12;
    return n < level ? n - 2 : n - 3; // 0..11 skipping the level rank
  }

  /// Global sort key (bigger = stronger/left in hand).
  int sortKey(String c) {
    if (isTrump(c)) return 1000 + order(c) * 4 + (sjSuit(c) == 'J' ? 0 : 3 - sjSuits.indexOf(sjSuit(c)));
    final si = sjSuits.indexOf(sjSuit(c));
    return (4 - si) * 100 + order(c);
  }

  List<String> sort(Iterable<String> cards) {
    final l = List<String>.of(cards)..sort((a, b) => sortKey(b) - sortKey(a));
    return l;
  }
}

/// One structural unit: single (size 1), pair (size 2), tractor (size 2*k, k>=2).
class SjComp {
  final int size; // number of cards
  final int top; // order of the highest card
  final List<String> cards;
  const SjComp(this.size, this.top, this.cards);
  int get pairs => size >= 2 ? size ~/ 2 : 0;
  bool get isTractor => size >= 4;
  String get label => size == 1 ? '单张' : (size == 2 ? '对子' : '拖拉机');
}

/// Pairs among [cards] (identical codes), as (order, code) — sorted by order desc.
List<(int, String)> _pairs(List<String> cards, SjTrump t) {
  final cnt = <String, int>{};
  for (final c in cards) {
    cnt[c] = (cnt[c] ?? 0) + 1;
  }
  final out = <(int, String)>[];
  for (final e in cnt.entries) {
    for (var i = 0; i < e.value ~/ 2; i++) {
      out.add((t.order(e.key), e.key));
    }
  }
  out.sort((a, b) => b.$1 - a.$1);
  return out;
}

/// Longest tractor length (in pairs) available among [cards] (single class assumed).
int sjLongestTractor(List<String> cards, SjTrump t) {
  final orders = _pairs(cards, t).map((p) => p.$1).toSet().toList()..sort();
  var best = orders.isEmpty ? 0 : 1, run = 1;
  for (var i = 1; i < orders.length; i++) {
    if (orders[i] == orders[i - 1] + 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

int sjPairCount(List<String> cards) {
  final cnt = <String, int>{};
  for (final c in cards) {
    cnt[c] = (cnt[c] ?? 0) + 1;
  }
  return cnt.values.fold(0, (a, v) => a + v ~/ 2);
}

/// Greedy decomposition into tractors (longest first), pairs, singles. Sorted big to small.
List<SjComp> sjDecompose(List<String> cards, SjTrump t) {
  final pairs = _pairs(cards, t);
  final rest = List<String>.of(cards);
  final comps = <SjComp>[];
  // pool of pairs by order
  final pool = <int, List<String>>{};
  for (final (o, c) in pairs) {
    (pool[o] ??= []).add(c);
  }
  while (true) {
    final orders = pool.keys.where((o) => pool[o]!.isNotEmpty).toList()..sort();
    var bestLen = 1, bestEnd = -1, run = 1;
    for (var i = 1; i < orders.length; i++) {
      if (orders[i] == orders[i - 1] + 1) {
        run++;
        if (run >= bestLen && run >= 2) {
          bestLen = run;
          bestEnd = orders[i];
        }
      } else {
        run = 1;
      }
    }
    if (bestEnd < 0) break;
    final cs = <String>[];
    for (var o = bestEnd - bestLen + 1; o <= bestEnd; o++) {
      final c = pool[o]!.removeLast();
      cs
        ..add(c)
        ..add(c);
      rest
        ..remove(c)
        ..remove(c);
    }
    comps.add(SjComp(bestLen * 2, bestEnd, cs));
  }
  for (final e in pool.entries) {
    for (final c in e.value) {
      comps.add(SjComp(2, e.key, [c, c]));
      rest
        ..remove(c)
        ..remove(c);
    }
  }
  for (final c in rest) {
    comps.add(SjComp(1, t.order(c), [c]));
  }
  comps.sort((a, b) => a.size != b.size ? b.size - a.size : b.top - a.top);
  return comps;
}

/// Checks that a lead is one class. Returns the class or null.
String? sjLeadClass(List<String> cards, SjTrump t) {
  final s = cards.map(t.cls).toSet();
  return s.length == 1 ? s.first : null;
}

/// Whether [comp] (from a lead of class [cls]) can be beaten by someone holding [hand].
bool sjCompBeatable(SjComp comp, String cls, List<String> hand, SjTrump t) {
  final mine = hand.where((c) => t.cls(c) == cls).toList();
  if (comp.size == 1) return mine.any((c) => t.order(c) > comp.top);
  if (comp.size == 2) return _pairs(mine, t).any((p) => p.$1 > comp.top);
  final k = comp.size ~/ 2;
  final orders = _pairs(mine, t).map((p) => p.$1).toSet();
  for (final top in orders) {
    if (top <= comp.top) continue;
    var ok = true;
    for (var o = top - k + 1; o <= top; o++) {
      if (!orders.contains(o)) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

/// Follow legality. Returns an error message or null if [play] is legal against [lead].
String? sjFollowError(List<String> lead, List<String> play, List<String> hand, SjTrump t) {
  if (play.length != lead.length) return '需要出 ${lead.length} 张牌';
  final cls = t.cls(lead.first);
  final have = hand.where((c) => t.cls(c) == cls).toList();
  final inPlay = play.where((c) => t.cls(c) == cls).toList();
  final need = have.length < lead.length ? have.length : lead.length;
  if (inPlay.length < need) return '必须跟出同花色（${cls == 'T' ? "主牌" : sjSuitNames[cls]}）的牌';
  if (have.length <= lead.length) return null; // all of that suit is played
  final comps = sjDecompose(lead, t);
  final leadPairs = comps.fold<int>(0, (a, c) => a + c.pairs);
  if (leadPairs > 0) {
    final handPairs = sjPairCount(have);
    final req = leadPairs < handPairs ? leadPairs : handPairs;
    if (sjPairCount(inPlay) < req) return '有对子必须跟对子';
  }
  final longest = comps.isEmpty ? 0 : comps.map((c) => c.isTractor ? c.size ~/ 2 : 0).reduce((a, b) => a > b ? a : b);
  if (longest >= 2) {
    final hk = sjLongestTractor(have, t);
    if (hk >= 2) {
      final want = hk < longest ? hk : longest;
      if (sjLongestTractor(inPlay, t) < want) return '有拖拉机必须跟拖拉机';
    }
  }
  return null;
}

/// Strength of [play] against a lead of shape [leadComps] / class [cls].
/// Returns -1 if the play cannot win; trumps ruffing a side suit get +100.
int sjPower(List<String> play, List<SjComp> leadComps, String cls, SjTrump t, {bool isLead = false}) {
  final pc = play.map(t.cls).toSet();
  if (pc.length != 1) return -1;
  final pcls = pc.first;
  if (pcls != cls && pcls != 'T') return -1;
  final ruff = pcls != cls;
  if (!isLead && leadComps.length > 1 && !ruff) return -1; // a thrown set cannot be beaten in suit
  final top = sjCover(play, leadComps, t);
  if (top < 0) return -1;
  return top + (ruff ? 100 : 0);
}

/// Tries to split [play] into the same structure as [leadComps] (sorted big to small).
/// Returns the top order of the first (largest) component, or -1 if impossible.
int sjCover(List<String> play, List<SjComp> leadComps, SjTrump t) {
  final pool = <int, List<String>>{}; // order -> list of pair codes
  for (final (o, c) in _pairs(play, t)) {
    (pool[o] ??= []).add(c);
  }
  var firstTop = -1;
  var usedPairs = 0;
  for (final comp in leadComps) {
    if (comp.size == 1) {
      if (firstTop < 0) {
        firstTop = play.map(t.order).reduce((a, b) => a > b ? a : b);
      }
      continue;
    }
    final k = comp.size ~/ 2;
    var found = -1;
    final orders = pool.keys.where((o) => pool[o]!.isNotEmpty).toList()..sort((a, b) => b - a);
    for (final top in orders) {
      var ok = true;
      for (var o = top - k + 1; o <= top; o++) {
        if ((pool[o]?.isEmpty ?? true)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        found = top;
        break;
      }
    }
    if (found < 0) return -1;
    for (var o = found - k + 1; o <= found; o++) {
      pool[o]!.removeLast();
    }
    usedPairs += k;
    if (firstTop < 0) firstTop = found;
  }
  if (usedPairs * 2 > play.length) return -1;
  return firstTop;
}

/// Build a legal follow. [high]: try to win with big cards; otherwise dump low.
List<String> sjBuildFollow(SjTrump t, List<String> hand, String cls, List<SjComp> leadComps, bool high, bool givePoints) {
  final n = leadComps.fold<int>(0, (a, c) => a + c.size);
  final mine = hand.where((c) => t.cls(c) == cls).toList();
  double val(String c) => t.order(c) * 1.0 + (givePoints ? -sjPoints(c) * 1.2 : sjPoints(c) * 1.2);
  if (mine.length <= n) {
    final others = hand.where((c) => t.cls(c) != cls).toList()
      ..sort((a, b) {
        final ta = t.isTrump(a) ? 100 : 0, tb = t.isTrump(b) ? 100 : 0;
        return (val(a) + ta).compareTo(val(b) + tb);
      });
    return [...mine, ...others.take(n - mine.length)];
  }
  final pool = List.of(mine);
  final out = <String>[];
  // pair pool by order
  List<(int, String)> pairsIn(List<String> cards) {
    final cnt = <String, int>{};
    for (final c in cards) {
      cnt[c] = (cnt[c] ?? 0) + 1;
    }
    final l = <(int, String)>[for (final e in cnt.entries) if (e.value >= 2) (t.order(e.key), e.key)];
    l.sort((a, b) => high ? b.$1 - a.$1 : a.$1 - b.$1);
    return l;
  }

  void takePair(String c) {
    pool
      ..remove(c)
      ..remove(c);
    out
      ..add(c)
      ..add(c);
  }

  var singlesNeeded = 0;
  for (final comp in leadComps) {
    if (comp.size == 1) {
      singlesNeeded++;
      continue;
    }
    var k = comp.size ~/ 2;
    // try tractor of length k, then shorter
    for (var len = k; len >= 2 && k > 0; len--) {
      final ps = pairsIn(pool);
      final orders = {for (final p in ps) p.$1: p.$2};
      String? found;
      final keys = orders.keys.toList()..sort((a, b) => high ? b - a : a - b);
      for (final top in keys) {
        var ok = true;
        for (var o = top - len + 1; o <= top; o++) {
          if (!orders.containsKey(o)) {
            ok = false;
            break;
          }
        }
        if (ok) {
          found = '$top';
          for (var o = top - len + 1; o <= top; o++) {
            takePair(orders[o]!);
          }
          break;
        }
      }
      if (found != null) {
        k -= len;
        break;
      }
    }
    while (k > 0) {
      final ps = pairsIn(pool);
      if (ps.isEmpty) break;
      takePair(ps.first.$2);
      k--;
    }
    singlesNeeded += k * 2;
  }
  // singles: prefer cards that don't break pairs
  final cnt = <String, int>{};
  for (final c in pool) {
    cnt[c] = (cnt[c] ?? 0) + 1;
  }
  pool.sort((a, b) {
    final pa = (cnt[a] ?? 0) >= 2 ? 50 : 0, pb = (cnt[b] ?? 0) >= 2 ? 50 : 0;
    final va = val(a), vb = val(b);
    return high ? ((vb - pb).compareTo(va - pa)) : ((va + pa).compareTo(vb + pb));
  });
  out.addAll(pool.take(singlesNeeded));
  return out;
}
