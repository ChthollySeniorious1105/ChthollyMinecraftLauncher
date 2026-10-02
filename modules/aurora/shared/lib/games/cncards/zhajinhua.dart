import '../../src/engine.dart';
import 'cards.dart';
import 'zjh_rules.dart';

/// 炸金花。2-9 人，筹码制；闷牌下注减半，比牌花费加倍。
class Zhajinhua extends GameEngine {
  Zhajinhua(super.setup);

  static const int base = 10;
  static const List<int> levels = [1, 2, 3, 5, 10]; // 单注档位（闷牌价，×底注）

  late int handsLimit;
  late int capRounds;
  late bool rule235;
  int handNo = 0;
  late List<int> chips;
  late List<List<String>> cards;
  late List<bool> seen, folded, out, lost;
  late List<int> put; // chips put into this hand
  late List<String> lastAct;
  late List<Set<int>> known; // known[s] = seats whose cards s has seen via 比牌
  int dealer = -1;
  int turn = -1;
  int unit = base; // current blind stake; seen players pay 2×
  int pot = 0;
  int betRound = 1;
  String phase = 'bet'; // bet | handEnd | over
  Map<String, dynamic>? result;
  Map<String, dynamic>? lastCompare;
  late List<bool> ready;

  int resigned = -1;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(chips);
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    phase = 'over';
    turn = -1;
    host.log('${name(seat)} 认输');
    host.log('游戏结束！${name(1 - seat)} 获胜');
  }

  @override
  List<int> get waitingFor {
    if (phase == 'bet') return [turn];
    if (phase == 'handEnd') return [for (var s = 0; s < players; s++) if (!ready[s] && !out[s]) s];
    return const [];
  }

  @override
  void start() {
    handsLimit = setup.opt<int>('hands', 10);
    capRounds = setup.opt<int>('cap', 10);
    rule235 = setup.opt<bool>('r235', true);
    chips = List.filled(players, 1000);
    out = List.filled(players, false);
    host.log('炸金花开始：每人 1000 筹码，底注 $base，共 $handsLimit 局，封顶 $capRounds 轮');
    _deal();
  }

  int get _starter => _nextIn(dealer);

  int _nextIn(int s) {
    for (var i = 1; i <= players; i++) {
      final n = (s + i) % players;
      if (!out[n]) return n;
    }
    return s;
  }

  List<int> get active => [for (var s = 0; s < players; s++) if (!out[s] && !folded[s]) s];

  void _deal() {
    handNo++;
    dealer = _nextIn(dealer < 0 ? players - 1 : dealer);
    final deck = shuffled(cnDeck(), rng);
    cards = [for (var s = 0; s < players; s++) out[s] ? <String>[] : deck.sublist(s * 3, s * 3 + 3)];
    seen = List.filled(players, false);
    folded = List.filled(players, false);
    lost = List.filled(players, false);
    put = List.filled(players, 0);
    lastAct = List.filled(players, '');
    known = [for (var s = 0; s < players; s++) <int>{}];
    unit = base;
    pot = 0;
    betRound = 1;
    result = null;
    lastCompare = null;
    ready = List.filled(players, false);
    for (var s = 0; s < players; s++) {
      if (out[s]) continue;
      final a = chips[s] < base ? chips[s] : base;
      chips[s] -= a;
      put[s] += a;
      pot += a;
    }
    phase = 'bet';
    turn = _starter;
    host.log('第 $handNo 局开始，${name(dealer)} 坐庄');
  }

  int _pos(int s) => (s - _starter + players) % players;

  /// Cost for [s] to call.
  int callCost(int s) => seen[s] ? unit * 2 : unit;
  int compareCost(int s) => callCost(s) * 2;
  bool canCompare(int s) => betRound >= 2 || chips[s] < callCost(s);

  void _pay(int s, int amount) {
    final a = amount > chips[s] ? chips[s] : amount;
    chips[s] -= a;
    put[s] += a;
    pot += a;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'handEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (waitingFor.isEmpty) _afterHand();
      return;
    }
    if (phase != 'bet') throw GameError('游戏已结束');
    if (out[seat] || folded[seat]) throw GameError('你已不在本局中');
    if (type == 'look') {
      if (seen[seat]) throw GameError('你已经看过牌了');
      seen[seat] = true;
      lastAct[seat] = '看牌';
      host.log('${name(seat)} 看牌');
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    switch (type) {
      case 'fold':
        folded[seat] = true;
        lastAct[seat] = '弃牌';
        host.log('${name(seat)} 弃牌');
        break;
      case 'call':
        final c = callCost(seat);
        if (chips[seat] < c) throw GameError('筹码不足，只能比牌或弃牌');
        _pay(seat, c);
        lastAct[seat] = seen[seat] ? '跟注 $c' : '闷跟 $c';
        break;
      case 'raise':
        final to = asInt(a['unit']);
        if (!levels.map((l) => l * base).contains(to) || to <= unit) throw GameError('加注档位无效');
        final c = seen[seat] ? to * 2 : to;
        if (chips[seat] < c) throw GameError('筹码不足');
        unit = to;
        _pay(seat, c);
        lastAct[seat] = seen[seat] ? '加注 $c' : '闷加 $c';
        host.log('${name(seat)} 加注到 $to/${to * 2}');
        break;
      case 'compare':
        if (!canCompare(seat)) throw GameError('第一轮不能比牌');
        final t = asInt(a['target']);
        if (t == seat || t < 0 || t >= players || out[t] || folded[t]) throw GameError('比牌对象无效');
        _pay(seat, compareCost(seat));
        // 发起者平局算输
        final r = zjhCompare(cards[seat], cards[t], rule235: rule235);
        final winner = r > 0 ? seat : t;
        final loser = winner == seat ? t : seat;
        folded[loser] = true;
        lost[loser] = true;
        known[seat].add(t);
        known[t].add(seat);
        lastAct[seat] = '比牌';
        lastAct[loser] = '比牌输';
        lastCompare = {'a': seat, 'b': t, 'winner': winner};
        host.log('${name(seat)} 与 ${name(t)} 比牌，${name(winner)} 胜');
        break;
      default:
        throw GameError('未知操作');
    }
    _advance();
  }

  void _advance() {
    final act = active;
    if (act.length <= 1) {
      _finish(act, false);
      return;
    }
    final prev = turn;
    var n = prev;
    for (var i = 1; i <= players; i++) {
      final c = (prev + i) % players;
      if (!out[c] && !folded[c]) {
        n = c;
        break;
      }
    }
    if (_pos(n) <= _pos(prev)) betRound++;
    if (betRound > capRounds) {
      host.log('达到封顶 $capRounds 轮，强制开牌');
      _finish(act, true);
      return;
    }
    turn = n;
  }

  void _finish(List<int> act, bool showdown) {
    var winners = <int>[act.first];
    if (showdown) {
      for (final s in act.skip(1)) {
        final r = zjhCompare(cards[s], cards[winners.first], rule235: rule235);
        if (r > 0) {
          winners = [s];
        } else if (r == 0) {
          winners.add(s);
        }
      }
    }
    final delta = [for (var s = 0; s < players; s++) -put[s]];
    final share = pot ~/ winners.length;
    for (var i = 0; i < winners.length; i++) {
      final w = winners[i];
      final amt = share + (i == 0 ? pot - share * winners.length : 0);
      chips[w] += amt;
      delta[w] += amt;
    }
    result = {
      'winners': winners,
      'pot': pot,
      'delta': delta,
      'showdown': showdown,
      'hands': [for (var s = 0; s < players; s++) cards[s]],
      'names': [for (var s = 0; s < players; s++) cards[s].length == 3 ? zjhName(zjhEval(cards[s])) : ''],
    };
    host.log('${winners.map(name).join('、')} 赢得底池 $pot');
    pot = 0;
    turn = -1;
    for (var s = 0; s < players; s++) {
      if (!out[s] && chips[s] <= 0) {
        out[s] = true;
        host.log('${name(s)} 筹码输光，出局');
      }
    }
    final alive = [for (var s = 0; s < players; s++) if (!out[s]) s];
    phase = (handNo >= handsLimit || alive.length <= 1) ? 'over' : 'handEnd';
    ready = List.filled(players, false);
  }

  void _afterHand() => _deal();

  List<int> get ranking {
    final r = List.generate(players, (i) => i);
    r.sort((a, b) => chips[b] - chips[a]);
    return r;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final ended = phase != 'bet';
    final hs = <List<String>>[];
    for (var s = 0; s < players; s++) {
      final show = ended || (seat >= 0 && ((s == seat && seen[seat]) || known[seat].contains(s)));
      hs.add(show ? cards[s] : [for (final _ in cards[s]) 'back']);
    }
    Map<String, dynamic>? me;
    if (seat >= 0 && phase == 'bet' && !out[seat] && !folded[seat]) {
      me = {
        'seen': seen[seat],
        'call': callCost(seat),
        'compare': compareCost(seat),
        'canCompare': canCompare(seat),
        'canCall': chips[seat] >= callCost(seat),
        'raises': [
          for (final l in levels)
            if (l * base > unit && chips[seat] >= (seen[seat] ? l * base * 2 : l * base)) l * base
        ],
        'hand': seen[seat] ? zjhName(zjhEval(cards[seat])) : null,
      };
    }
    return {
      'phase': phase,
      'hand': handNo,
      'hands': handsLimit,
      'cap': capRounds,
      'round': betRound,
      'r235': rule235,
      'dealer': dealer,
      'turn': phase == 'bet' ? turn : -1,
      'unit': unit,
      'pot': pot,
      'chips': chips,
      'put': put,
      'seen': seen,
      'folded': folded,
      'out': out,
      'lost': lost,
      'lastAct': lastAct,
      'cards': hs,
      'me': me,
      'lastCompare': lastCompare,
      'result': ended ? result : null,
      'ready': phase == 'handEnd' ? ready : null,
      'ranking': phase == 'over' ? ranking : null,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'handEnd') return ready[seat] || out[seat] ? null : {'type': 'continue'};
    if (phase != 'bet' || seat != turn) return null;
    if (botLevel <= 0 && rng.nextDouble() < 0.45) return _botRandom(seat);
    if (botLevel >= 2) return _botHard(seat);
    return _botNormal(seat);
  }

  /// 简单：随机选一个合法动作（偏向跟注）。
  Map<String, dynamic> _botRandom(int seat) {
    final opps = [for (final s in active) if (s != seat) s];
    final opts = <Map<String, dynamic>>[
      {'type': 'fold'},
      if (chips[seat] >= callCost(seat)) ...[{'type': 'call'}, {'type': 'call'}],
      if (canCompare(seat)) {'type': 'compare', 'target': opps[rng.nextInt(opps.length)]},
      if (!seen[seat]) {'type': 'look'},
    ];
    return opts[rng.nextInt(opts.length)];
  }

  /// Fraction of all 3-card hands that [cards] beats (ties count half).
  static List<int>? _allScores;
  double _percentile(List<String> cards) {
    final all = _allScores ??= () {
      final deck = cnDeck();
      final l = <int>[for (final i in cnCombos(52, 3)) zjhEval([for (final k in i) deck[k]])]..sort();
      return l;
    }();
    final e = zjhEval(cards);
    var lo = 0, hi = all.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (all[m] < e) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    var eq = lo;
    while (eq < all.length && all[eq] == e) {
      eq++;
    }
    var p = (lo + (eq - lo) / 2) / all.length;
    if (rule235 && zjhIs235(cards)) p = 0.05; // only good against 豹子
    return p;
  }

  /// 困难：按牌力百分位（对全部 22100 种三张牌）与在局对手人数决定跟/加/比/弃。
  Map<String, dynamic> _botHard(int seat) {
    final opps = [for (final s in active) if (s != seat) s];
    final cc = callCost(seat);
    final canCall = chips[seat] >= cc;
    if (!seen[seat]) {
      // 闷牌便宜：前两轮倾向闷跟，之后看牌
      if (betRound <= 2 && canCall && rng.nextDouble() < 0.6) return {'type': 'call'};
      return {'type': 'look'};
    }
    final p = _percentile(cards[seat]);
    var w = 1.0;
    for (var i = 0; i < opps.length; i++) {
      w *= p;
    }
    // opponents who looked and still keep paying after round 2 are likely stronger
    final strongSignals = betRound >= 3 ? [for (final s in opps) if (seen[s]) s].length : 0;
    w *= 1 - 0.08 * strongSignals;
    int target() {
      // prefer a blind opponent (random hand), otherwise the one who put in least
      final blind = [for (final s in opps) if (!seen[s]) s];
      if (blind.isNotEmpty) return blind[rng.nextInt(blind.length)];
      final l = List.of(opps)..sort((a, b) => put[a] - put[b]);
      return l.first;
    }

    if (!canCall) {
      if (canCompare(seat) && p > 0.5) return {'type': 'compare', 'target': target()};
      return {'type': 'fold'};
    }
    final bluff = rng.nextDouble() < 0.06;
    if (!bluff && (p < 0.3 || (w < 0.12 && betRound >= 2))) return {'type': 'fold'};
    if (canCompare(seat) && p > 0.55 && (opps.length == 1 ? betRound >= 3 : betRound >= 4 && w < 0.5)) {
      if (opps.length == 1 && w > 0.85 && betRound < capRounds - 1) {
        // 很强：继续加注榨取筹码
      } else {
        return {'type': 'compare', 'target': target()};
      }
    }
    if (w > 0.55 || bluff) {
      final r = [
        for (final l in levels)
          if (l * base > unit && chips[seat] >= l * base * 2 && l * base <= unit * 3) l * base
      ];
      if (r.isNotEmpty && rng.nextDouble() < 0.7) return {'type': 'raise', 'unit': r.last};
    }
    if (w < 0.25 && betRound >= 3 && unit >= 30) return {'type': 'fold'};
    return {'type': 'call'};
  }

  Map<String, dynamic> _botNormal(int seat) {
    final opps = [for (final s in active) if (s != seat) s];
    final cc = callCost(seat);
    if (!seen[seat]) {
      // 闷牌：前两轮有一定概率继续闷
      if (betRound <= 2 && chips[seat] >= cc && rng.nextDouble() < 0.55) {
        return {'type': 'call'};
      }
      return {'type': 'look'};
    }
    final st = zjhStrength(cards[seat]);
    final canCall = chips[seat] >= cc;
    // pick a compare target: prefer opponents that have looked (known weaker info is not available)
    int target() => opps[rng.nextInt(opps.length)];
    if (!canCall) {
      if (canCompare(seat) && st > 0.45) return {'type': 'compare', 'target': target()};
      return {'type': 'fold'};
    }
    if (st < 0.22 && rng.nextDouble() < 0.8) return {'type': 'fold'};
    if (st < 0.4 && betRound >= 3 && rng.nextDouble() < 0.6) return {'type': 'fold'};
    if (canCompare(seat) && betRound >= 3 && st >= 0.45 && rng.nextDouble() < (opps.length == 1 ? 0.45 : 0.25)) {
      return {'type': 'compare', 'target': target()};
    }
    if (st > 0.8 && rng.nextDouble() < 0.5) {
      final r = [
        for (final l in levels)
          if (l * base > unit && chips[seat] >= l * base * 2) l * base
      ];
      if (r.isNotEmpty) return {'type': 'raise', 'unit': r.first};
    }
    return {'type': 'call'};
  }
}
