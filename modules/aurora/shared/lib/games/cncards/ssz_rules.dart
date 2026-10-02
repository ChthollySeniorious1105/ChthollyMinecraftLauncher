import 'dart:math';

import 'cards.dart';

/// 十三水 lane evaluation. Categories (shared by 3- and 5-card lanes so lanes can be compared):
/// 0 乌龙, 1 对子, 2 两对, 3 三条, 4 顺子, 5 同花, 6 葫芦, 7 铁支, 8 同花顺.
const List<String> ssNames = ['乌龙', '对子', '两对', '三条', '顺子', '同花', '葫芦', '铁支', '同花顺'];

int _top5(List<int> r) {
  // r sorted desc, distinct required
  if (r.toSet().length != 5) return 0;
  if (r[0] - r[4] == 4) return r[0];
  if (r[0] == 14 && r[1] == 5 && r[4] == 2) return 5; // A2345
  return 0;
}

/// Evaluate a lane of 3 or 5 cards. Higher = stronger.
int ssEval(List<String> cards) {
  final r = [for (final c in cards) cnRank(c)]..sort((a, b) => b - a);
  final cnt = <int, int>{};
  for (final x in r) {
    cnt[x] = (cnt[x] ?? 0) + 1;
  }
  // groups ordered by (count desc, rank desc)
  final groups = cnt.entries.toList()
    ..sort((a, b) => a.value != b.value ? b.value - a.value : b.key - a.key);
  final ks = [for (final g in groups) g.key];
  if (cards.length == 3) {
    if (groups.first.value == 3) return cnPack(3, ks);
    if (groups.first.value == 2) return cnPack(1, ks);
    return cnPack(0, ks);
  }
  final flush = cards.every((c) => cnSuit(c) == cnSuit(cards.first));
  final top = _top5(r);
  if (top > 0 && flush) return cnPack(8, [top]);
  if (groups.first.value == 4) return cnPack(7, ks);
  if (groups.first.value == 3 && groups[1].value == 2) return cnPack(6, ks);
  if (flush) return cnPack(5, r);
  if (top > 0) return cnPack(4, [top]);
  if (groups.first.value == 3) return cnPack(3, ks);
  if (groups.first.value == 2 && groups[1].value == 2) return cnPack(2, ks);
  if (groups.first.value == 2) return cnPack(1, ks);
  return cnPack(0, ks);
}

String ssName(int score) => ssNames[cnCategory(score)];

/// Valid when 后墩 ≥ 中墩 ≥ 前墩 (otherwise 倒水).
bool ssValid(List<String> front, List<String> mid, List<String> back) {
  final f = ssEval(front), m = ssEval(mid), b = ssEval(back);
  return b >= m && m >= f;
}

/// Points a lane is worth when won with [score] in lane [lane] (0 前, 1 中, 2 后).
int ssLaneValue(int lane, int score) {
  final cat = cnCategory(score);
  if (lane == 0) return cat == 3 ? 3 : 1;
  if (lane == 1) {
    if (cat == 8) return 10;
    if (cat == 7) return 8;
    if (cat == 6) return 2;
    return 1;
  }
  if (cat == 8) return 5;
  if (cat == 7) return 4;
  return 1;
}

// ---------------------------------------------------------------------------
// Whole-hand specials
// ---------------------------------------------------------------------------

class SsSpecial {
  final String name;
  final int value;
  const SsSpecial(this.name, this.value);
}

bool _isStraight3(List<int> r) {
  final s = List.of(r)..sort();
  if (s[0] == s[1] || s[1] == s[2]) return false;
  if (s[2] - s[0] == 2) return true;
  return s[0] == 2 && s[1] == 3 && s[2] == 14; // A23
}

bool _isStraight5(List<int> r) => _top5(List.of(r)..sort((a, b) => b - a)) > 0;

/// Detects whole-hand special types: 一条龙 13, 三同花 3, 三顺子 3, 六对半 3.
SsSpecial? ssSpecial(List<String> hand) {
  if (hand.length != 13) return null;
  final ranks = [for (final c in hand) cnRank(c)];
  final cnt = <int, int>{};
  for (final r in ranks) {
    cnt[r] = (cnt[r] ?? 0) + 1;
  }
  if (cnt.length == 13) {
    final flush = hand.every((c) => cnSuit(c) == cnSuit(hand.first));
    return SsSpecial(flush ? '至尊清龙' : '一条龙', flush ? 26 : 13);
  }
  final pairs = cnt.values.fold(0, (a, v) => a + v ~/ 2);
  if (pairs == 6) return const SsSpecial('六对半', 3);
  // 三同花: suits split into counts {3,5,5} / {3,10} / {8,5} / {13}
  final sc = <String, int>{};
  for (final c in hand) {
    sc[cnSuit(c)] = (sc[cnSuit(c)] ?? 0) + 1;
  }
  if (_splits(sc.values.toList())) return const SsSpecial('三同花', 3);
  if (_threeStraights(ranks)) return const SsSpecial('三顺子', 3);
  return null;
}

/// Can suit counts be partitioned into groups of 3, 5, 5?
bool _splits(List<int> counts) {
  bool go(List<int> c, List<int> need) {
    if (need.isEmpty) return c.every((x) => x == 0);
    final n = need.first;
    for (var i = 0; i < c.length; i++) {
      if (c[i] >= n) {
        c[i] -= n;
        final ok = go(c, need.sublist(1));
        c[i] += n;
        if (ok) return true;
      }
    }
    return false;
  }

  return go(List.of(counts), [5, 5, 3]);
}

bool _threeStraights(List<int> ranks) {
  final n = ranks.length;
  for (final f in cnCombos(n, 3)) {
    final fr = [for (final i in f) ranks[i]];
    if (!_isStraight3(fr)) continue;
    final rest = [for (var i = 0; i < n; i++) if (!f.contains(i)) ranks[i]];
    for (final m in cnCombos(10, 5)) {
      if (m.first != 0) break; // symmetry: first remaining card in mid
      final mr = [for (final i in m) rest[i]];
      if (!_isStraight5(mr)) continue;
      final br = [for (var i = 0; i < 10; i++) if (!m.contains(i)) rest[i]];
      if (_isStraight5(br)) return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Arrangement search (自动理牌 / bot)
// ---------------------------------------------------------------------------

const List<double> _backP = [0.0, 0.1, 0.3, 0.5, 0.62, 0.72, 0.85, 0.97, 0.99, 1.0];
const List<double> _midP = [0.05, 0.25, 0.55, 0.75, 0.83, 0.9, 0.95, 0.99, 1.0, 1.0];

double _laneStrength(int lane, int score) {
  final cat = cnCategory(score);
  final hi = ((score >> 16) & 15) - 2; // 0..12
  if (lane == 0) {
    if (cat == 3) return 0.97 + hi * 0.002;
    if (cat == 1) return 0.45 + hi * 0.04;
    return 0.02 + hi * 0.025;
  }
  final p = lane == 1 ? _midP : _backP;
  return p[cat] + (p[cat + 1] - p[cat]) * hi / 13;
}

class SsArrangement {
  final List<String> front, mid, back;
  const SsArrangement(this.front, this.mid, this.back);
  Map<String, dynamic> toJson() => {'front': front, 'mid': mid, 'back': back};
}

double ssArrangementValue(List<String> f, List<String> m, List<String> b) {
  final fs = ssEval(f), ms = ssEval(m), bs = ssEval(b);
  return _valueOf(fs, ms, bs);
}

double _valueOf(int fs, int ms, int bs) {
  var v = 0.0;
  final scores = [fs, ms, bs];
  for (var l = 0; l < 3; l++) {
    final p = _laneStrength(l, scores[l]);
    v += (2 * p - 1) * ssLaneValue(l, scores[l]);
  }
  return v;
}

/// Finds a strong valid arrangement of a 13-card hand (exhaustive search).
/// [level] 0: a random valid arrangement (needs [rng]); 1: lane-strength
/// heuristic; 2: re-ranks the best heuristic candidates by simulating them
/// against random opponent hands drawn from the unseen cards (needs [rng]).
SsArrangement ssBestArrangement(List<String> hand, {int level = 1, Random? rng}) {
  if (level >= 2 && rng != null) return _hardArrangement(hand, rng);
  final top = _search(hand, 1, level <= 0 ? (fs, ms, bs) => rng?.nextDouble() ?? 0 : _valueOf);
  return top.first;
}

/// All valid arrangements scored by [value]; returns the best [keep], best first.
List<SsArrangement> _search(List<String> hand, int keep, double Function(int fs, int ms, int bs) value) {
  final n = hand.length;
  final five = <int, int>{};
  for (final idx in cnCombos(n, 5)) {
    var m = 0;
    for (final i in idx) {
      m |= 1 << i;
    }
    five[m] = ssEval([for (final i in idx) hand[i]]);
  }
  final three = <int, int>{};
  for (final idx in cnCombos(n, 3)) {
    var m = 0;
    for (final i in idx) {
      m |= 1 << i;
    }
    three[m] = ssEval([for (final i in idx) hand[i]]);
  }
  final full = (1 << n) - 1;
  // keep the best [keep] (value, back mask, mid mask), with distinct lane scores
  final best = <(double, int, int, int)>[]; // value, bb, bm, laneKey hash
  for (final be in five.entries) {
    final bs = be.value;
    final rest = full ^ be.key;
    final restIdx = [for (var i = 0; i < n; i++) if (rest & (1 << i) != 0) i];
    for (final mi in cnCombos(restIdx.length, 5)) {
      var mm = 0;
      for (final i in mi) {
        mm |= 1 << restIdx[i];
      }
      final ms = five[mm]!;
      if (ms > bs) continue;
      final fs = three[rest ^ mm]!;
      if (fs > ms) continue;
      final v = value(fs, ms, bs);
      if (best.length >= keep && v <= best.last.$1) continue;
      final key = Object.hash(fs, ms, bs);
      final dup = best.indexWhere((x) => x.$4 == key);
      if (dup >= 0) {
        if (best[dup].$1 >= v) continue;
        best.removeAt(dup);
      }
      best.add((v, be.key, mm, key));
      best.sort((a, b) => b.$1.compareTo(a.$1));
      if (best.length > keep) best.removeLast();
    }
  }
  List<String> pick(int m) => [for (var i = 0; i < n; i++) if (m & (1 << i) != 0) hand[i]];
  return [for (final x in best) SsArrangement(pick(full ^ x.$2 ^ x.$3), pick(x.$3), pick(x.$2))];
}

SsArrangement _hardArrangement(List<String> hand, Random rng) {
  final cands = _search(hand, 6, _valueOf);
  if (cands.length == 1) return cands.first;
  final mine = [for (final c in cands) [ssEval(c.front), ssEval(c.mid), ssEval(c.back)]];
  final unseen = [for (final c in cnDeck()) if (!hand.contains(c)) c];
  final total = List<double>.filled(cands.length, 0);
  const samples = 16;
  for (var k = 0; k < samples; k++) {
    unseen.shuffle(rng);
    final opp = _search(unseen.sublist(0, 13), 1, _valueOf).first;
    final o = [ssEval(opp.front), ssEval(opp.mid), ssEval(opp.back)];
    for (var i = 0; i < cands.length; i++) {
      total[i] += ssComparePair(mine[i], o, aFoul: false, bFoul: false).total;
    }
  }
  var bi = 0;
  for (var i = 1; i < cands.length; i++) {
    if (total[i] > total[bi]) bi = i;
  }
  return cands[bi];
}

/// Pairwise result between two players' lanes (from a's perspective).
/// Returns per-lane points (positive = a wins that lane) and whether it's a sweep.
({List<int> lanes, int total, bool sweep}) ssComparePair(
    List<int> a, List<int> b, {required bool aFoul, required bool bFoul}) {
  final lanes = [0, 0, 0];
  if (aFoul && bFoul) return (lanes: lanes, total: 0, sweep: false);
  for (var l = 0; l < 3; l++) {
    int c;
    if (aFoul) {
      c = -1;
    } else if (bFoul) {
      c = 1;
    } else {
      c = a[l].compareTo(b[l]);
    }
    if (c > 0) lanes[l] = aFoul ? 1 : ssLaneValue(l, a[l]);
    if (c < 0) lanes[l] = -(bFoul ? 1 : ssLaneValue(l, b[l]));
  }
  final wins = lanes.where((x) => x > 0).length, losses = lanes.where((x) => x < 0).length;
  final sweep = wins == 3 || losses == 3;
  var total = lanes.fold(0, (s, x) => s + x);
  if (sweep) total *= 2;
  return (lanes: lanes, total: total, sweep: sweep);
}
