import 'dart:math';

import '../../src/engine.dart';
import 'cards.dart';

/// One pot (main or side) and the seats that may win it.
class PotShare {
  final int amount;
  final List<int> eligible;
  PotShare(this.amount, this.eligible);
  @override
  String toString() => 'Pot($amount, $eligible)';
}

/// Builds main + side pots from total contributions. Folded seats' chips are
/// included but they are never eligible. Consecutive pots with identical
/// eligibility are merged.
List<PotShare> buildPots(List<int> contrib, List<bool> folded) {
  final rem = List<int>.of(contrib);
  final pots = <PotShare>[];
  while (rem.any((c) => c > 0)) {
    final live = [for (var s = 0; s < rem.length; s++) if (rem[s] > 0 && !folded[s]) s];
    if (live.isEmpty) {
      // only dead money left: add to the last pot
      final extra = rem.fold<int>(0, (a, b) => a + b);
      if (pots.isEmpty) break;
      final last = pots.removeLast();
      pots.add(PotShare(last.amount + extra, last.eligible));
      break;
    }
    final level = live.map((s) => rem[s]).reduce(min);
    var amount = 0;
    for (var s = 0; s < rem.length; s++) {
      final take = min(rem[s], level);
      amount += take;
      rem[s] -= take;
    }
    if (pots.isNotEmpty && _sameSet(pots.last.eligible, live)) {
      final last = pots.removeLast();
      pots.add(PotShare(last.amount + amount, live));
    } else {
      pots.add(PotShare(amount, live));
    }
  }
  return pots;
}

bool _sameSet(List<int> a, List<int> b) => a.length == b.length && a.every(b.contains);

/// Splits [amount] between [winners]; odd chips go one at a time to the
/// winners closest to the left of the button.
Map<int, int> splitPot(int amount, List<int> winners, int dealer, int players) {
  final order = List<int>.of(winners)..sort((a, b) => ((a - dealer - 1) % players) - ((b - dealer - 1) % players));
  final share = amount ~/ winners.length;
  var odd = amount - share * winners.length;
  final out = <int, int>{};
  for (final w in order) {
    out[w] = share + (odd > 0 ? 1 : 0);
    if (odd > 0) odd--;
  }
  return out;
}

/// 德州扑克（无限注）。
class TexasHoldem extends GameEngine {
  TexasHoldem(super.setup);

  static const int fixedHands = 30;
  static const int handCap = 300;

  late List<int> stacks;
  late int sb, bb;
  late bool escalate;
  late bool fixedMode;
  int handNo = 0;
  int dealer = 0;
  late List<bool> out;
  final List<int> bustOrder = [];

  /// Hand number in which each seat busted (0 = still in).
  late List<int> bustHand;
  int resigned = -1;

  late List<List<String>> hole;
  List<String> board = [];
  List<String> deck = [];
  late List<int> bets, contrib;
  late List<bool> folded, allIn, inHand, needAct, raiseOpen, shown;
  late List<String> lastAct;
  int currentBet = 0, minRaise = 0, turn = -1, sbSeat = -1, bbSeat = -1;
  String street = 'preflop';
  String phase = 'bet'; // bet | handEnd | over
  Map<String, dynamic>? result;
  List<int> ranking = [];

  @override
  bool get isOver => phase == 'over';

  /// Survivors by chips (ties share), then busted seats by elimination order
  /// (later is better; busting in the same hand shares). A resigned seat
  /// counts as busted.
  @override
  List<int>? get placings {
    if (!isOver) return null;
    final alive = [for (var s = 0; s < players; s++) if (!out[s]) s];
    return [
      for (var s = 0; s < players; s++)
        if (!out[s])
          1 + alive.where((o) => stacks[o] > stacks[s]).length
        else
          1 + alive.length + [for (var o = 0; o < players; o++) if (out[o] && bustHand[o] > bustHand[s]) o].length,
    ];
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    if (!out[seat]) {
      out[seat] = true;
      bustOrder.add(seat);
      bustHand[seat] = handNo;
    }
    turn = -1;
    host.log('${name(seat)} 认输');
    _finish();
  }

  @override
  List<int> get waitingFor => phase == 'bet' && turn >= 0 ? [turn] : const [];

  @override
  int get botDelayMs => 900;

  int _next(int from, bool Function(int) ok) {
    for (var i = 1; i <= players; i++) {
      final s = (from + i) % players;
      if (ok(s)) return s;
    }
    return -1;
  }

  bool _live(int s) => inHand[s] && !folded[s];
  bool _active(int s) => _live(s) && !allIn[s];

  @override
  void start() {
    final chips = setup.opt<int>('chips', 1000);
    final blinds = setup.opt<int>('blinds', 10);
    sb = blinds;
    bb = blinds * 2;
    escalate = setup.opt<String>('escalate', 'double10') == 'double10';
    fixedMode = setup.opt<String>('end', 'elim') == 'fixed';
    stacks = List.filled(players, chips);
    out = List.filled(players, false);
    bustHand = List.filled(players, 0);
    dealer = rng.nextInt(players);
    host.log('德州扑克开始：每人 $chips 筹码，盲注 $sb/$bb${escalate ? "，每10手翻倍" : ""}');
    _newHand(first: true);
  }

  void _newHand({bool first = false}) {
    handNo++;
    if (escalate && handNo > 1 && (handNo - 1) % 10 == 0) {
      sb *= 2;
      bb *= 2;
      host.log('盲注升级为 $sb/$bb');
    }
    phase = 'bet';
    result = null;
    board = [];
    inHand = [for (var s = 0; s < players; s++) !out[s]];
    folded = List.filled(players, false);
    allIn = List.filled(players, false);
    bets = List.filled(players, 0);
    contrib = List.filled(players, 0);
    needAct = List.filled(players, false);
    raiseOpen = List.filled(players, true);
    shown = List.filled(players, false);
    lastAct = List.filled(players, '');
    hole = [for (var s = 0; s < players; s++) <String>[]];
    dealer = first && inHand[dealer] ? dealer : _next(dealer, (s) => inHand[s]);
    deck = shuffled(fullDeck(), rng);
    final alive = [for (var s = 0; s < players; s++) if (inHand[s]) s];
    for (var r = 0; r < 2; r++) {
      var s = dealer;
      for (var k = 0; k < alive.length; k++) {
        s = _next(s, (x) => inHand[x]);
        hole[s].add(deck.removeLast());
      }
    }
    if (alive.length == 2) {
      sbSeat = dealer;
      bbSeat = _next(dealer, (x) => inHand[x]);
    } else {
      sbSeat = _next(dealer, (x) => inHand[x]);
      bbSeat = _next(sbSeat, (x) => inHand[x]);
    }
    _put(sbSeat, min(sb, stacks[sbSeat]));
    lastAct[sbSeat] = '小盲 ${bets[sbSeat]}';
    _put(bbSeat, min(bb, stacks[bbSeat]));
    lastAct[bbSeat] = '大盲 ${bets[bbSeat]}';
    currentBet = bb;
    minRaise = bb;
    street = 'preflop';
    for (var s = 0; s < players; s++) {
      needAct[s] = _active(s);
    }
    turn = _next(bbSeat, (s) => needAct[s] && _active(s));
    if (turn < 0 || _countWhere(_active) == 0 || (_countWhere(_active) == 1 && _maxBetOthers(_firstWhere(_active)) <= bets[_firstWhere(_active)])) {
      _endStreet();
    }
  }

  int _countWhere(bool Function(int) f) {
    var c = 0;
    for (var s = 0; s < players; s++) {
      if (f(s)) c++;
    }
    return c;
  }

  int _firstWhere(bool Function(int) f) {
    for (var s = 0; s < players; s++) {
      if (f(s)) return s;
    }
    return -1;
  }

  int _maxBetOthers(int seat) {
    var m = 0;
    for (var s = 0; s < players; s++) {
      if (s != seat && bets[s] > m) m = bets[s];
    }
    return m;
  }

  void _put(int s, int amt) {
    stacks[s] -= amt;
    bets[s] += amt;
    contrib[s] += amt;
    if (stacks[s] == 0 && inHand[s]) allIn[s] = true;
  }

  int get potTotal => contrib.fold(0, (a, b) => a + b);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase != 'bet') throw GameError('现在不能操作');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    final toCall = currentBet - bets[seat];
    final maxTo = bets[seat] + stacks[seat];
    switch (type) {
      case 'fold':
        folded[seat] = true;
        lastAct[seat] = '弃牌';
      case 'check':
        if (toCall > 0) throw GameError('需要跟注 $toCall 或弃牌');
        lastAct[seat] = '过牌';
      case 'call':
        if (toCall <= 0) {
          lastAct[seat] = '过牌';
        } else {
          final amt = min(toCall, stacks[seat]);
          _put(seat, amt);
          lastAct[seat] = allIn[seat] ? '全下 ${bets[seat]}' : '跟注 ${bets[seat]}';
        }
      case 'raise':
      case 'allin':
        var to = type == 'allin' ? maxTo : asInt(a['to']);
        if (maxTo <= currentBet) {
          // can only call all-in
          _put(seat, stacks[seat]);
          lastAct[seat] = '全下 ${bets[seat]}';
          break;
        }
        if (!raiseOpen[seat]) {
          if (type == 'raise') throw GameError('对手全下不足一次加注，你只能跟注或弃牌');
          // 全下被封顶时视为跟注
          _put(seat, min(toCall, stacks[seat]));
          lastAct[seat] = allIn[seat] ? '全下 ${bets[seat]}' : '跟注 ${bets[seat]}';
          break;
        }
        if (to > maxTo) to = maxTo;
        final minTo = currentBet + minRaise;
        if (to <= currentBet) throw GameError('加注额必须大于当前注 $currentBet');
        if (to < minTo && to != maxTo) throw GameError('最少加注到 $minTo');
        final wasBet = currentBet == 0;
        _put(seat, to - bets[seat]);
        final inc = to - currentBet;
        final full = inc >= minRaise;
        if (full) minRaise = inc;
        currentBet = to;
        for (var o = 0; o < players; o++) {
          if (o == seat || !_active(o)) continue;
          if (full) {
            raiseOpen[o] = true;
          } else if (!needAct[o]) {
            raiseOpen[o] = false;
          }
          needAct[o] = true;
        }
        lastAct[seat] = allIn[seat] ? '全下 ${bets[seat]}' : (wasBet ? '下注 ${bets[seat]}' : '加注到 ${bets[seat]}');
      default:
        throw GameError('未知操作');
    }
    needAct[seat] = false;
    host.log('${name(seat)} ${lastAct[seat]}');
    _advance(seat);
  }

  void _advance(int from) {
    if (_countWhere(_live) == 1) {
      _winUncontested(_firstWhere(_live));
      return;
    }
    final nx = _next(from, (s) => needAct[s] && _active(s));
    if (nx >= 0) {
      turn = nx;
      return;
    }
    _endStreet();
  }

  void _dealStreet() {
    deck.removeLast(); // burn
    final n = board.isEmpty ? 3 : 1;
    for (var i = 0; i < n; i++) {
      board.add(deck.removeLast());
    }
  }

  void _endStreet() {
    for (var s = 0; s < players; s++) {
      bets[s] = 0;
    }
    currentBet = 0;
    minRaise = bb;
    turn = -1;
    if (_countWhere(_live) == 1) {
      _winUncontested(_firstWhere(_live));
      return;
    }
    if (board.length == 5) {
      _showdown();
      return;
    }
    if (_countWhere(_active) <= 1) {
      while (board.length < 5) {
        _dealStreet();
      }
      _showdown();
      return;
    }
    _dealStreet();
    street = switch (board.length) { 3 => 'flop', 4 => 'turn', _ => 'river' };
    for (var s = 0; s < players; s++) {
      needAct[s] = _active(s);
      raiseOpen[s] = true;
      if (_live(s) && !allIn[s]) lastAct[s] = '';
    }
    turn = _next(dealer, (s) => needAct[s] && _active(s));
  }

  void _returnUncalled() {
    var top = -1;
    for (var s = 0; s < players; s++) {
      if (top < 0 || contrib[s] > contrib[top]) top = s;
    }
    var second = 0;
    for (var s = 0; s < players; s++) {
      if (s != top && contrib[s] > second) second = contrib[s];
    }
    final diff = contrib[top] - second;
    if (diff > 0) {
      contrib[top] -= diff;
      stacks[top] += diff;
      if (stacks[top] > 0) allIn[top] = false;
      host.log('退还 ${name(top)} 未被跟注的 $diff');
    }
  }

  void _winUncontested(int w) {
    _returnUncalled();
    final pot = potTotal;
    stacks[w] += pot;
    host.log('${name(w)} 赢得底池 $pot');
    result = {
      'type': 'fold',
      'pots': [
        {'amount': pot, 'winners': [w], 'hand': ''},
      ],
      'hands': List<String?>.filled(players, null),
      'best': List<List<String>>.filled(players, const []),
      'delta': [for (var s = 0; s < players; s++) (s == w ? pot : 0) - contrib[s]],
    };
    _endHand();
  }

  void _showdown() {
    _returnUncalled();
    street = 'showdown';
    final scores = List<int>.filled(players, -1);
    final names = List<String?>.filled(players, null);
    final best = List<List<String>>.filled(players, const []);
    for (var s = 0; s < players; s++) {
      if (!_live(s)) continue;
      shown[s] = true;
      final all = [...hole[s], ...board];
      scores[s] = evalCodes(all);
      names[s] = handName(scores[s]);
      best[s] = bestFive(all);
    }
    final won = List<int>.filled(players, 0);
    final potList = <Map<String, dynamic>>[];
    for (final p in buildPots(contrib, folded)) {
      final top = p.eligible.map((s) => scores[s]).reduce(max);
      final winners = [for (final s in p.eligible) if (scores[s] == top) s];
      splitPot(p.amount, winners, dealer, players).forEach((s, v) => won[s] += v);
      potList.add({'amount': p.amount, 'winners': winners, 'hand': handName(top)});
      host.log('${winners.map(name).join('、')} 以${handName(top)}赢得${potList.length == 1 ? "主池" : "边池"} ${p.amount}');
    }
    for (var s = 0; s < players; s++) {
      stacks[s] += won[s];
    }
    result = {
      'type': 'showdown',
      'pots': potList,
      'hands': names,
      'best': best,
      'delta': [for (var s = 0; s < players; s++) won[s] - contrib[s]],
    };
    _endHand();
  }

  void _endHand() {
    phase = 'handEnd';
    turn = -1;
    for (var s = 0; s < players; s++) {
      if (!out[s] && stacks[s] <= 0) {
        out[s] = true;
        bustOrder.add(s);
        bustHand[s] = handNo;
        host.log('${name(s)} 筹码输光，出局');
      }
    }
    final alive = _countWhere((s) => !out[s]);
    if (alive <= 1 || (fixedMode && handNo >= fixedHands) || handNo >= handCap) {
      _finish();
      return;
    }
    host.schedule(result?['type'] == 'fold' ? 2500 : 5000, () {
      if (phase == 'handEnd') _newHand();
    });
  }

  void _finish() {
    phase = 'over';
    final alive = [for (var s = 0; s < players; s++) if (!out[s]) s]..sort((a, b) => stacks[b] - stacks[a]);
    ranking = [...alive, ...bustOrder.reversed];
    host.log('比赛结束，${name(ranking.first)} 获胜！');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final holes = <List<String>>[];
    for (var s = 0; s < players; s++) {
      if (s == seat || shown[s]) {
        holes.add(hole[s]);
      } else if (inHand[s] && !folded[s] && hole[s].isNotEmpty) {
        holes.add(const ['back', 'back']);
      } else {
        holes.add(const []);
      }
    }
    final collected = [for (var s = 0; s < players; s++) contrib[s] - bets[s]];
    final pots = phase == 'bet' ? [for (final p in buildPots(collected, folded)) p.amount] : <int>[];
    Map<String, dynamic>? me;
    if (phase == 'bet' && seat == turn && seat >= 0) {
      final maxTo = bets[seat] + stacks[seat];
      me = {
        'toCall': min(currentBet - bets[seat], stacks[seat]),
        'minTo': min(currentBet + minRaise, maxTo),
        'maxTo': maxTo,
        'canRaise': raiseOpen[seat] && maxTo > currentBet,
        'bet': bets[seat],
      };
    }
    String? myHand;
    if (seat >= 0 && hole[seat].length == 2 && board.length >= 3) {
      myHand = handName(evalCodes([...hole[seat], ...board]));
    }
    return {
      'phase': phase,
      'street': street,
      'hand': handNo,
      'handsLimit': fixedMode ? fixedHands : 0,
      'sb': sb,
      'bb': bb,
      'nextLevel': escalate ? 10 - ((handNo - 1) % 10) : 0,
      'dealer': dealer,
      'sbSeat': sbSeat,
      'bbSeat': bbSeat,
      'turn': turn,
      'stacks': stacks,
      'bets': bets,
      'folded': folded,
      'allIn': allIn,
      'out': out,
      'inHand': inHand,
      'holes': holes,
      'board': board,
      'pot': potTotal,
      'pots': pots,
      'lastAct': lastAct,
      'me': me,
      'myHand': myHand,
      'result': result,
      'ranking': phase == 'over' ? ranking : null,
    };
  }

  // -------------------------------------------------------------------------
  // Bot: only uses its own hole cards + public information.
  // -------------------------------------------------------------------------
  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'bet' || seat != turn) return null;
    if (botLevel == 0) return _botEasy(seat);
    if (botLevel >= 2) return _botHard(seat);
    final toCall = min(currentBet - bets[seat], stacks[seat]);
    final stack = stacks[seat];
    final pot = potTotal;
    final maxTo = bets[seat] + stack;
    final minTo = currentBet + minRaise;
    final canRaise = raiseOpen[seat] && maxTo > currentBet;
    final opp = _countWhere(_live) - 1;
    Map<String, dynamic> passive() => toCall > 0 ? {'type': 'call'} : {'type': 'check'};
    Map<String, dynamic> foldOrCheck() => toCall > 0 ? {'type': 'fold'} : {'type': 'check'};
    Map<String, dynamic> shove() => canRaise ? {'type': 'allin'} : passive();
    Map<String, dynamic> raiseTo(int to) {
      if (!canRaise) return passive();
      if (maxTo <= minTo || to >= maxTo * 0.8) return {'type': 'allin'};
      return {'type': 'raise', 'to': max(to, minTo)};
    }

    final r = rng.nextDouble();
    if (board.isEmpty) {
      final chen = chenScore(hole[seat][0], hole[seat][1]);
      final lateness = ((seat - dealer) % players + players) % players; // 0 = button
      final late = lateness == 0 || lateness == players - 1;
      final raiseChen = opp >= 4 ? 9.0 : (opp >= 2 ? 8.0 : 6.0);
      final callChen = raiseChen - (late ? 3 : 2);
      final bbs = stack / bb;
      final big = toCall > stack * 0.3 || toCall > bb * 8;
      if (bbs <= 10 && chen >= callChen) return shove();
      if (chen >= 12) return big && r < 0.5 ? shove() : raiseTo(max(currentBet * 3, bb * 3));
      if (chen >= raiseChen) {
        if (toCall <= bb * 3 && r < 0.75) return raiseTo(max(currentBet * 3, bb * 3));
        if (!big || chen >= 10) return passive();
        return foldOrCheck();
      }
      if (chen >= callChen) {
        if (toCall <= bb * 2 || (toCall <= stack * 0.05)) return passive();
        return foldOrCheck();
      }
      if (toCall == 0) return r < 0.08 && late ? raiseTo(bb * 3) : {'type': 'check'};
      if (late && currentBet == bb && r < 0.06) return raiseTo(bb * 3);
      return {'type': 'fold'};
    }
    final eq = monteCarloEquity(hole[seat], board, min(opp, 4), rng, iterations: 70);
    final odds = toCall == 0 ? 0.0 : toCall / (pot + toCall);
    if (eq > 0.82) {
      return r < 0.3 && stack < pot * 2 ? shove() : raiseTo(currentBet + (pot * (0.7 + r * 0.5)).round());
    }
    if (eq > 0.62) {
      if (r < 0.5) return raiseTo(currentBet + (pot * 0.55).round());
      return passive();
    }
    if (eq > odds + 0.04) {
      if (toCall == 0 && r < 0.2) return raiseTo((pot * 0.5).round());
      return passive();
    }
    if (toCall == 0) {
      return r < 0.1 ? raiseTo((pot * 0.5).round()) : {'type': 'check'};
    }
    return {'type': 'fold'};
  }

  // Shared bot helpers (all read only own hole cards + public state).
  ({int toCall, int stack, int pot, int maxTo, int minTo, bool canRaise, int opp}) _botCtx(int seat) {
    final stack = stacks[seat];
    final maxTo = bets[seat] + stack;
    return (
      toCall: min(currentBet - bets[seat], stack),
      stack: stack,
      pot: potTotal,
      maxTo: maxTo,
      minTo: currentBet + minRaise,
      canRaise: raiseOpen[seat] && maxTo > currentBet,
      opp: _countWhere(_live) - 1,
    );
  }

  /// 简单: often a random legal choice, never folds cheaply, rarely raises
  /// (only minimum raises), ignores pot odds.
  Map<String, dynamic> _botEasy(int seat) {
    final c = _botCtx(seat);
    Map<String, dynamic> passive() => c.toCall > 0 ? {'type': 'call'} : {'type': 'check'};
    Map<String, dynamic> minRaiseAct() =>
        !c.canRaise ? passive() : (c.maxTo <= c.minTo ? {'type': 'allin'} : {'type': 'raise', 'to': c.minTo});
    if (rng.nextDouble() < 0.45) {
      final r = rng.nextDouble();
      if (r < 0.15 && c.canRaise) return minRaiseAct();
      if (r < 0.45 && c.toCall > 0) return {'type': 'fold'};
      return passive();
    }
    if (board.isEmpty) {
      final chen = chenScore(hole[seat][0], hole[seat][1]);
      if (chen >= 11 && rng.nextDouble() < 0.5) return minRaiseAct();
      if (c.toCall == 0 || chen >= 4 || c.toCall <= bb * 2) return passive();
      return {'type': 'fold'};
    }
    final eq = monteCarloEquity(hole[seat], board, min(c.opp, 3), rng, iterations: 30);
    if (eq > 0.85 && rng.nextDouble() < 0.4) return minRaiseAct();
    if (c.toCall == 0 || eq > 0.3) return passive();
    return {'type': 'fold'};
  }

  /// 困难: Monte-Carlo equity vs random hands (own + board cards only),
  /// adjusted for bet size, compared with pot odds; position-aware steals,
  /// value sizing by pot and short-stack push/fold.
  Map<String, dynamic> _botHard(int seat) {
    final c = _botCtx(seat);
    final toCall = c.toCall;
    final pot = c.pot;
    Map<String, dynamic> passive() => toCall > 0 ? {'type': 'call'} : {'type': 'check'};
    Map<String, dynamic> foldOrCheck() => toCall > 0 ? {'type': 'fold'} : {'type': 'check'};
    Map<String, dynamic> shove() => c.canRaise ? {'type': 'allin'} : passive();
    Map<String, dynamic> raiseTo(int to) {
      if (!c.canRaise) return passive();
      if (c.maxTo <= c.minTo || to >= c.maxTo * 0.7) return {'type': 'allin'};
      return {'type': 'raise', 'to': max(to, c.minTo)};
    }

    final r = rng.nextDouble();
    final oppN = min(c.opp, 6);
    final raw = monteCarloEquity(hole[seat], board, oppN, rng, iterations: board.isEmpty ? 300 : 400);
    // a bet from an opponent narrows their range: discount random-hand equity
    final pressure = pot <= 0 ? 0.0 : min(1.0, toCall / max(1, pot - toCall));
    final eq = raw * (1 - 0.3 * pressure);
    final odds = toCall == 0 ? 0.0 : toCall / (pot + toCall);
    final fair = 1 / (c.opp + 1);
    final lateness = ((seat - dealer) % players + players) % players;
    final late = lateness == 0 || lateness == players - 1 || c.opp == 1;
    if (board.isEmpty) {
      final bbs = c.stack / bb;
      if (bbs <= 12) {
        if (raw > fair * (late ? 1.15 : 1.35)) return shove();
        if (toCall > 0 && eq > odds + 0.03) return passive();
        return foldOrCheck();
      }
      final open = currentBet <= bb;
      if (raw > fair * 1.9) {
        if (!open && toCall > c.stack * 0.35) return shove();
        return raiseTo(open ? bb * 3 + (pot - bb - sb) : currentBet * 3);
      }
      if (raw > fair * 1.35) {
        if (open && r < 0.8) return raiseTo(bb * 3 + (pot - bb - sb));
        if (eq > odds + 0.02 && toCall <= c.stack * 0.2) return passive();
        return foldOrCheck();
      }
      if (open && late && r < 0.25) return raiseTo(bb * 3);
      if (toCall > 0 && eq > odds + 0.06 && toCall <= bb * 2) return passive();
      return foldOrCheck();
    }
    final spr = c.stack / max(1, pot);
    if (eq > 0.8) {
      if (spr < 1.2) return shove();
      return raiseTo(currentBet + (pot * (0.65 + r * 0.3)).round());
    }
    if (eq > 0.6) {
      if (r < 0.65) return raiseTo(currentBet + (pot * 0.55).round());
      return passive();
    }
    if (eq > odds + 0.03) {
      // semi-bluff / probe when checked to, before the river
      if (toCall == 0 && board.length < 5 && r < 0.2) return raiseTo((pot * 0.5).round());
      return passive();
    }
    if (toCall == 0) {
      if (late && c.opp == 1 && r < 0.18) return raiseTo((pot * 0.5).round());
      return {'type': 'check'};
    }
    return {'type': 'fold'};
  }
}
