import '../../src/engine.dart';
import 'cards.dart';

/// 牌七 / 接龙 (Sevens, Fan Tan) with the Chinese 扣牌 variant.
class Sevens extends GameEngine {
  Sevens(super.setup);

  static const String starter = '7H'; // 红桃7先出

  late String mode; // cover | pass
  late List<List<String>> hands;
  late List<List<String>> covered; // face-down penalty cards per seat
  /// Per suit (index in fmSuits): lowest / highest value laid, 0 = row not started.
  final List<int> lo = [0, 0, 0, 0];
  final List<int> hi = [0, 0, 0, 0];
  int turn = 0;
  bool first = true;
  String phase = 'play'; // play | over
  final List<int> finishOrder = [];
  int resigned = -1;
  int winner = -1; // pass mode
  late List<Map<String, dynamic>?> acts; // last action per seat (public)
  Map<String, dynamic>? last;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => phase == 'play' ? [turn] : const [];

  @override
  void start() {
    mode = setup.opt<String>('mode', 'cover');
    final deck = shuffled(fmDeck(), rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[i % players].add(deck[i]);
    }
    for (final h in hands) {
      h.sort(fmBySuit);
    }
    covered = List.generate(players, (_) => <String>[]);
    acts = List.filled(players, null);
    turn = [for (var s = 0; s < players; s++) s].firstWhere((s) => hands[s].contains(starter));
    host.log('牌七开始：${name(turn)} 持有红桃7，先出。${mode == 'cover' ? '没牌可出必须扣一张牌，扣牌点数越少越好' : '没牌可出就过，先出完者胜'}');
  }

  static int suitIdx(String c) => fmSuits.indexOf(fmSuit(c));

  bool isPlayable(String c) {
    if (first) return c == starter;
    final v = fmVal(c), si = suitIdx(c);
    if (v == 7) return true;
    if (lo[si] == 0) return false;
    return v == lo[si] - 1 || v == hi[si] + 1;
  }

  List<String> legal(int s) => [for (final c in hands[s]) if (isPlayable(c)) c];

  static int points(Iterable<String> cs) => cs.fold(0, (a, c) => a + fmVal(c));

  List<int> get penalties => [for (var s = 0; s < players; s++) points(covered[s])];

  int _nextWithCards(int s) {
    for (var k = 1; k <= players; k++) {
      final t = (s + k) % players;
      if (hands[t].isNotEmpty && t != resigned) return t;
    }
    return -1;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = a['type'];
    final can = legal(seat);
    if (type == 'play') {
      final c = asStr(a['card']);
      if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
      if (!isPlayable(c)) throw GameError(first ? '第一手必须出红桃7' : '这张牌接不上：只能出7，或紧挨着桌上同花色的两端');
      hands[seat].remove(c);
      final si = suitIdx(c), v = fmVal(c);
      if (v == 7) {
        lo[si] = 7;
        hi[si] = 7;
      } else if (v < lo[si]) {
        lo[si] = v;
      } else {
        hi[si] = v;
      }
      first = false;
      acts[seat] = {'type': 'play', 'card': c};
      last = {'seat': seat, 'type': 'play', 'card': c};
    } else if (type == 'cover') {
      if (mode != 'cover') throw GameError('本局规则不扣牌，没牌可出请选择“过”');
      if (can.isNotEmpty) throw GameError('你有牌可以出，不能扣牌');
      final c = asStr(a['card']);
      if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
      hands[seat].remove(c);
      covered[seat].add(c);
      acts[seat] = {'type': 'cover'};
      last = {'seat': seat, 'type': 'cover'};
      host.log('${name(seat)} 没牌可出，扣了一张牌');
    } else if (type == 'pass') {
      if (mode != 'pass') throw GameError('没牌可出时必须扣一张牌');
      if (can.isNotEmpty) throw GameError('你有牌可以出，不能过');
      acts[seat] = {'type': 'pass'};
      last = {'seat': seat, 'type': 'pass'};
    } else {
      throw GameError('未知操作');
    }
    if (hands[seat].isEmpty && !finishOrder.contains(seat)) {
      finishOrder.add(seat);
      if (mode == 'pass') {
        winner = seat;
        phase = 'over';
        host.log('${name(seat)} 最先出完，获胜！');
        return;
      }
      host.log('${name(seat)} 手牌已出完');
    }
    final nt = _nextWithCards(seat);
    if (nt < 0) {
      phase = 'over';
      final p = penalties;
      final best = p.reduce((x, y) => x < y ? x : y);
      host.log('游戏结束：${[for (var s = 0; s < players; s++) if (p[s] == best) name(s)].join('、')} 扣牌最少（$best 点）获胜');
      return;
    }
    turn = nt;
  }

  @override
  bool get canResign => phase == 'play';

  @override
  void resign(int seat) {
    if (phase != 'play' || seat < 0 || seat >= players) return;
    resigned = seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
  }

  /// Score used for ranking (lower is better).
  List<int> get _rankScore {
    if (mode == 'cover') {
      // unfinished hands (only after a resign) count as covered
      return [for (var s = 0; s < players; s++) points(covered[s]) + points(hands[s])];
    }
    return [for (var s = 0; s < players; s++) s == winner ? -1 : points(hands[s])];
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    final sc = _rankScore;
    if (resigned >= 0) sc[resigned] = 1 << 20;
    return rankByScore(sc, lowWins: true);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final over = phase == 'over';
    return {
      'phase': phase,
      'mode': mode,
      'turn': turn,
      'first': first,
      'lo': lo,
      'hi': hi,
      'counts': [for (final h in hands) h.length],
      'coverCounts': [for (final c in covered) c.length],
      'hand': seat >= 0 ? hands[seat] : const <String>[],
      'myCovered': seat >= 0 ? covered[seat] : const <String>[],
      'legal': seat >= 0 && seat == turn && !over ? legal(seat) : const <String>[],
      'acts': acts,
      'last': last,
      'finish': finishOrder,
      'resigned': resigned,
      'winner': winner,
      'covered': over ? covered : null,
      'hands': over ? hands : null,
      'scores': over ? _rankScore : null,
      'result': over ? {'placings': placings} : null,
    };
  }

  // ---------------------------------------------------------------------------
  // Bot: uses only its own hand + the public table.
  // ---------------------------------------------------------------------------
  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    final can = legal(seat);
    if (can.isNotEmpty) {
      if (botLevel == 0) return {'type': 'play', 'card': can[rng.nextInt(can.length)]};
      String best = can.first;
      var bestSc = -1e9;
      for (final c in can) {
        final sc = _playScore(seat, c) + rng.nextDouble() * (botLevel >= 2 ? 0.1 : 1.0);
        if (sc > bestSc) {
          bestSc = sc;
          best = c;
        }
      }
      return {'type': 'play', 'card': best};
    }
    if (mode == 'pass') return {'type': 'pass'};
    if (hand.isEmpty) return null;
    if (botLevel == 0) {
      // easy: usually the lowest card, sometimes random
      if (rng.nextDouble() < 0.4) return {'type': 'cover', 'card': hand[rng.nextInt(hand.length)]};
    }
    String best = hand.first;
    var bestSc = 1e9;
    for (final c in hand) {
      var sc = fmVal(c).toDouble();
      if (botLevel >= 2) {
        // covering also strands my own cards beyond it; reward blocking others
        final mine = _beyond(seat, c, true);
        final others = _beyond(seat, c, false);
        sc += points(mine) * 0.6 - others.length * 0.8;
      }
      if (sc < bestSc) {
        bestSc = sc;
        best = c;
      }
    }
    return {'type': 'cover', 'card': best};
  }

  /// Cards of the same suit further from 7 than [c] (in c's direction), mine or not.
  List<String> _beyond(int seat, String c, bool mine) {
    final v = fmVal(c), s = fmSuit(c);
    final out = <String>[];
    final range = v < 7 ? [for (var x = v - 1; x >= 1; x--) x] : (v > 7 ? [for (var x = v + 1; x <= 13; x++) x] : <int>[]);
    for (final x in range) {
      final code = '${fmRanks[x - 1]}$s';
      if (hands[seat].contains(code) == mine) out.add(code);
    }
    return out;
  }

  /// Higher = better play. Prefers opening lines I can continue myself, keeps
  /// blocks that hold back opponents, and dumps high cards in 扣牌 mode.
  double _playScore(int seat, String c) {
    final v = fmVal(c), s = fmSuit(c);
    final hand = hands[seat];
    bool mineAt(int x) => hand.contains('${fmRanks[x - 1]}$s');
    double side(int dir, int from) {
      // cards unlocked for others before reaching one of mine
      var sc = 0.0;
      var gift = 0;
      var my = 0;
      for (var x = from; x >= 1 && x <= 13; x += dir) {
        if (mineAt(x)) {
          my++;
        } else if (my == 0) {
          gift++;
        }
      }
      sc += my * 2.0;
      // the next card is mine: free follow-up
      final nx = from;
      if (nx >= 1 && nx <= 13 && mineAt(nx)) sc += 2;
      sc -= gift * (my == 0 ? 0.8 : 0.4);
      return sc;
    }

    var sc = 0.0;
    if (v == 7) {
      sc += side(-1, 6) + side(1, 8);
      sc -= 1.0; // 7s are flexible: keep them a bit
    } else if (v < 7) {
      sc += side(-1, v - 1);
    } else {
      sc += side(1, v + 1);
    }
    if (mode == 'cover') sc += (v - 7).abs() * 0.15 + v * 0.05;
    return sc;
  }
}
