import 'dart:math';

/// Card helpers shared by 德州扑克 / 21点 / 跑得快.
///
/// String codes follow PlayingCard: rank in "23456789TJQKA" + suit in "SHDC".
/// Integer cards (fast path for the hold'em evaluator): rank(2..14) * 4 + suit(0..3).

const String kRanks = '23456789TJQKA';
const String kSuits = 'SHDC';

int cardRank(String code) => kRanks.indexOf(code[0]) + 2;
String cardSuit(String code) => code[code.length - 1];

int toInt(String code) => cardRank(code) * 4 + kSuits.indexOf(cardSuit(code));
String toCode(int c) => '${kRanks[(c >> 2) - 2]}${kSuits[c & 3]}';

List<String> fullDeck() => [for (final r in kRanks.split('')) for (final s in kSuits.split('')) '$r$s'];

List<int> fullIntDeck() => [for (var r = 2; r <= 14; r++) for (var s = 0; s < 4; s++) r * 4 + s];

// ---------------------------------------------------------------------------
// Hold'em hand evaluator (5..7 cards). Higher score = better hand.
// score = category << 20 | k1 << 16 | k2 << 12 | k3 << 8 | k4 << 4 | k5
// categories: 8 同花顺, 7 四条, 6 葫芦, 5 同花, 4 顺子, 3 三条, 2 两对, 1 一对, 0 高牌
// ---------------------------------------------------------------------------

const List<String> kHandNames = ['高牌', '一对', '两对', '三条', '顺子', '同花', '葫芦', '四条', '同花顺'];

int handCategory(int score) => score >> 20;

String handName(int score) {
  final cat = handCategory(score);
  if (cat == 8 && ((score >> 16) & 15) == 14) return '皇家同花顺';
  return kHandNames[cat];
}

int _pack(int cat, List<int> ks) {
  var v = cat;
  for (var i = 0; i < 5; i++) {
    v = (v << 4) | (i < ks.length ? ks[i] : 0);
  }
  return v;
}

/// Highest straight top card in a rank bitmask (bit r = rank r present), 0 if none.
int straightHigh(int m) {
  if (m & (1 << 14) != 0) m |= 2; // ace plays low (bit 1)
  for (var h = 14; h >= 5; h--) {
    if ((m >> (h - 4)) & 31 == 31) return h;
  }
  return 0;
}

final List<int> _cnt = List<int>.filled(15, 0);
final List<int> _sMask = List<int>.filled(4, 0);
final List<int> _sCnt = List<int>.filled(4, 0);

/// Evaluates the best 5-card poker hand out of [cards] (5..7 int cards).
int evalHand(List<int> cards) {
  for (var i = 0; i < 15; i++) {
    _cnt[i] = 0;
  }
  for (var i = 0; i < 4; i++) {
    _sMask[i] = 0;
    _sCnt[i] = 0;
  }
  var mask = 0;
  for (final c in cards) {
    final r = c >> 2, s = c & 3;
    _cnt[r]++;
    _sMask[s] |= 1 << r;
    _sCnt[s]++;
    mask |= 1 << r;
  }
  // Flush / straight flush. (With ≤7 cards a flush can't coexist with quads or a full house.)
  for (var s = 0; s < 4; s++) {
    if (_sCnt[s] >= 5) {
      final sf = straightHigh(_sMask[s]);
      if (sf > 0) return _pack(8, [sf]);
      final ks = <int>[];
      for (var r = 14; r >= 2 && ks.length < 5; r--) {
        if (_sMask[s] & (1 << r) != 0) ks.add(r);
      }
      return _pack(5, ks);
    }
  }
  var quad = 0;
  final trips = <int>[], pairs = <int>[], singles = <int>[];
  for (var r = 14; r >= 2; r--) {
    switch (_cnt[r]) {
      case 4:
        quad = r;
      case 3:
        trips.add(r);
      case 2:
        pairs.add(r);
      case 1:
        singles.add(r);
    }
  }
  int highestExcept(List<int> ex) {
    for (var r = 14; r >= 2; r--) {
      if (_cnt[r] > 0 && !ex.contains(r)) return r;
    }
    return 0;
  }

  if (quad > 0) return _pack(7, [quad, highestExcept([quad])]);
  if (trips.isNotEmpty && (trips.length >= 2 || pairs.isNotEmpty)) {
    final second = trips.length >= 2 ? (pairs.isNotEmpty ? max(trips[1], pairs[0]) : trips[1]) : pairs[0];
    return _pack(6, [trips[0], second]);
  }
  final st = straightHigh(mask);
  if (st > 0) return _pack(4, [st]);
  if (trips.isNotEmpty) {
    final ks = <int>[trips[0]];
    for (var r = 14; r >= 2 && ks.length < 3; r--) {
      if (_cnt[r] > 0 && r != trips[0]) ks.add(r);
    }
    return _pack(3, ks);
  }
  if (pairs.length >= 2) {
    return _pack(2, [pairs[0], pairs[1], highestExcept([pairs[0], pairs[1]])]);
  }
  if (pairs.length == 1) {
    final ks = <int>[pairs[0]];
    for (var r = 14; r >= 2 && ks.length < 4; r--) {
      if (_cnt[r] > 0 && r != pairs[0]) ks.add(r);
    }
    return _pack(1, ks);
  }
  return _pack(0, singles.take(5).toList());
}

int evalCodes(List<String> codes) => evalHand([for (final c in codes) toInt(c)]);

/// The best 5 cards (as codes) out of 5..7 codes, for highlighting at showdown.
List<String> bestFive(List<String> codes) {
  if (codes.length <= 5) return List.of(codes);
  final ints = [for (final c in codes) toInt(c)];
  var best = -1;
  var bestSet = <int>[];
  final n = ints.length;
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      for (var c = b + 1; c < n; c++) {
        for (var d = c + 1; d < n; d++) {
          for (var e = d + 1; e < n; e++) {
            final h = [ints[a], ints[b], ints[c], ints[d], ints[e]];
            final v = evalHand(h);
            if (v > best) {
              best = v;
              bestSet = h;
            }
          }
        }
      }
    }
  }
  return [for (final c in bestSet) toCode(c)];
}

// ---------------------------------------------------------------------------
// Pre-flop hand strength (Chen formula), roughly -1..20.
// ---------------------------------------------------------------------------
double chenScore(String c1, String c2) {
  var r1 = cardRank(c1), r2 = cardRank(c2);
  if (r2 > r1) {
    final t = r1;
    r1 = r2;
    r2 = t;
  }
  double base(int r) => switch (r) { 14 => 10, 13 => 8, 12 => 7, 11 => 6, _ => r / 2 };
  var s = base(r1);
  if (r1 == r2) {
    s = max(5, s * 2);
    if (r1 == 5) s = 6; // 55 counts as 6
    return s;
  }
  if (cardSuit(c1) == cardSuit(c2)) s += 2;
  final gap = r1 - r2 - 1;
  s -= switch (gap) { 0 => 0, 1 => 1, 2 => 2, 3 => 4, _ => 5 };
  if (gap <= 1 && r1 < 12) s += 1;
  return s;
}

/// Monte-Carlo equity of [hole] vs [opponents] random hands given [board].
/// Only uses the bot's own cards and public cards.
double monteCarloEquity(List<String> hole, List<String> board, int opponents, Random rng, {int iterations = 150}) {
  if (opponents <= 0) return 1;
  final known = {for (final c in [...hole, ...board]) toInt(c)};
  final deck = [for (final c in fullIntDeck()) if (!known.contains(c)) c];
  final my = [for (final c in hole) toInt(c)];
  final bd = [for (final c in board) toInt(c)];
  final need = 5 - bd.length;
  final draw = need + opponents * 2;
  var score = 0.0;
  final mine = List<int>.filled(7, 0);
  final opp = List<int>.filled(7, 0);
  for (var it = 0; it < iterations; it++) {
    // partial Fisher-Yates
    for (var i = 0; i < draw; i++) {
      final j = i + rng.nextInt(deck.length - i);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    mine[0] = my[0];
    mine[1] = my[1];
    for (var i = 0; i < bd.length; i++) {
      mine[2 + i] = bd[i];
      opp[2 + i] = bd[i];
    }
    for (var i = 0; i < need; i++) {
      mine[2 + bd.length + i] = deck[i];
      opp[2 + bd.length + i] = deck[i];
    }
    final me = evalHand(mine);
    var best = 0, ties = 0;
    var lost = false;
    for (var o = 0; o < opponents; o++) {
      opp[0] = deck[need + o * 2];
      opp[1] = deck[need + o * 2 + 1];
      final v = evalHand(opp);
      if (v > me) {
        lost = true;
        break;
      }
      if (v == me) ties++;
      if (v > best) best = v;
    }
    if (!lost) score += ties == 0 ? 1 : 1 / (ties + 1);
  }
  return score / iterations;
}
