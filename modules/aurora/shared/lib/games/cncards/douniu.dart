import 'dart:math';

import '../../src/engine.dart';
import 'cards.dart';
import 'douniu_rules.dart';

/// 斗牛/牛牛。2-8 人，与庄家比牌。
class Douniu extends GameEngine {
  Douniu(super.setup);

  late int handsLimit;
  late String bankerMode; // grab | rotate
  late bool mingpai;
  late bool specials;
  late String payTable;
  int handNo = 0;
  late List<int> scores;
  late List<List<String>> cards;
  late List<int> grab; // -1 = not yet, 0 = 不抢, 1..4
  late List<int> bets; // 0 = not yet
  late List<bool> shown;
  int banker = -1;
  int bankerMult = 1;
  String phase = 'grab'; // grab | bet | show | handEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;

  int resigned = -1;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(scores);
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
    host.log('游戏结束！${name(1 - seat)} 获胜');
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'grab':
        return [for (var s = 0; s < players; s++) if (grab[s] < 0) s];
      case 'bet':
        return [for (var s = 0; s < players; s++) if (s != banker && bets[s] == 0) s];
      case 'show':
        return [for (var s = 0; s < players; s++) if (!shown[s]) s];
      case 'handEnd':
        return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    }
    return const [];
  }

  @override
  void start() {
    handsLimit = setup.opt<int>('hands', 10);
    bankerMode = setup.opt<String>('banker', 'grab');
    mingpai = setup.opt<bool>('mingpai', true);
    specials = setup.opt<bool>('specials', true);
    payTable = setup.opt<String>('pay', 'std');
    scores = List.filled(players, 0);
    host.log('斗牛开始：${bankerMode == 'grab' ? (mingpai ? "明牌抢庄" : "自由抢庄") : "轮流坐庄"}，共 $handsLimit 局');
    _deal();
  }

  void _deal() {
    handNo++;
    final deck = shuffled(cnDeck(), rng);
    cards = [for (var s = 0; s < players; s++) deck.sublist(s * 5, s * 5 + 5)];
    grab = List.filled(players, -1);
    bets = List.filled(players, 0);
    shown = List.filled(players, false);
    ready = List.filled(players, false);
    result = null;
    bankerMult = 1;
    if (bankerMode == 'rotate') {
      banker = (banker + 1) % players;
      phase = 'bet';
      host.log('第 $handNo 局：${name(banker)} 坐庄');
    } else {
      banker = -1;
      phase = 'grab';
    }
  }

  /// How many of [s]'s cards are visible to [s] right now.
  int visibleCount(int s) {
    if (phase == 'show' || phase == 'handEnd' || phase == 'over') return 5;
    return mingpai ? 4 : 0;
  }

  void _resolveGrab() {
    var best = 0;
    for (final g in grab) {
      if (g > best) best = g;
    }
    final cands = [for (var s = 0; s < players; s++) if (grab[s] == best) s];
    banker = cands[rng.nextInt(cands.length)];
    bankerMult = best == 0 ? 1 : best;
    host.log('${name(banker)} ${best == 0 ? "（无人抢庄，随机）" : "抢庄 ×$best"} 成为庄家');
    phase = 'bet';
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'grab':
        if (type != 'grab') throw GameError('请选择抢庄倍数');
        if (grab[seat] >= 0) throw GameError('你已经选择过了');
        final m = asInt(a['mult']);
        if (m < 0 || m > 4) throw GameError('抢庄倍数无效');
        grab[seat] = m;
        if (waitingFor.isEmpty) _resolveGrab();
        return;
      case 'bet':
        if (type != 'bet') throw GameError('请选择下注倍数');
        if (seat == banker) throw GameError('庄家不用下注');
        if (bets[seat] > 0) throw GameError('你已经下注了');
        final b = asInt(a['mult']);
        if (b < 1 || b > 5) throw GameError('下注倍数无效');
        bets[seat] = b;
        if (waitingFor.isEmpty) phase = 'show';
        return;
      case 'show':
        if (type != 'show') throw GameError('请点击摊牌');
        if (shown[seat]) throw GameError('你已经摊牌了');
        shown[seat] = true;
        final r = dnEval(cards[seat], specials: specials);
        host.log('${name(seat)} 摊牌：${dnName(r.level)}');
        if (waitingFor.isEmpty) _settle();
        return;
      case 'handEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (waitingFor.isEmpty) _deal();
        return;
    }
    throw GameError('游戏已结束');
  }

  void _settle() {
    final ev = [for (final c in cards) dnEval(c, specials: specials)];
    final delta = List.filled(players, 0);
    final win = List.filled(players, false);
    for (var s = 0; s < players; s++) {
      if (s == banker) continue;
      final pWins = dnCompare(ev[s], ev[banker]) > 0;
      final m = dnMult(pWins ? ev[s].level : ev[banker].level, payTable);
      final amt = m * bets[s] * bankerMult;
      if (pWins) {
        delta[s] += amt;
        delta[banker] -= amt;
        win[s] = true;
      } else {
        delta[s] -= amt;
        delta[banker] += amt;
      }
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    win[banker] = delta[banker] > 0;
    result = {
      'delta': delta,
      'win': win,
      'levels': [for (final e in ev) e.level],
      'names': [for (final e in ev) dnName(e.level)],
      'three': [for (final e in ev) e.three],
    };
    phase = handNo >= handsLimit ? 'over' : 'handEnd';
  }

  List<int> get ranking {
    final r = List.generate(players, (i) => i);
    r.sort((a, b) => scores[b] - scores[a]);
    return r;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final ended = phase == 'handEnd' || phase == 'over';
    final hs = <List<String>>[];
    for (var s = 0; s < players; s++) {
      if (ended || (phase == 'show' && shown[s])) {
        hs.add(cards[s]);
      } else if (s == seat) {
        final n = visibleCount(s);
        hs.add([for (var i = 0; i < 5; i++) i < n ? cards[s][i] : 'back']);
      } else {
        hs.add(List.filled(5, 'back'));
      }
    }
    // shown hands' evaluation (public), and my own when I can see all 5
    final evals = <Map<String, dynamic>?>[];
    for (var s = 0; s < players; s++) {
      final vis = ended || (phase == 'show' && (shown[s] || s == seat));
      if (!vis) {
        evals.add(null);
        continue;
      }
      final e = dnEval(cards[s], specials: specials);
      evals.add({'level': e.level, 'name': dnName(e.level), 'three': e.three, 'mult': dnMult(e.level, payTable)});
    }
    return {
      'phase': phase,
      'hand': handNo,
      'hands': handsLimit,
      'bankerMode': bankerMode,
      'mingpai': mingpai,
      'banker': banker,
      'bankerMult': bankerMult,
      'grab': [for (var s = 0; s < players; s++) phase == 'grab' && s != seat ? (grab[s] >= 0 ? -2 : -1) : grab[s]],
      'bets': bets,
      'shown': shown,
      'scores': scores,
      'cards': hs,
      'evals': evals,
      'pay': payTable,
      'result': ended ? result : null,
      'ready': phase == 'handEnd' ? ready : null,
      'ranking': phase == 'over' ? ranking : null,
    };
  }

  /// Bot estimate of strength from visible cards only.
  double _strength(int seat) {
    final n = visibleCount(seat);
    if (n == 0) return 0.4;
    final vis = cards[seat].sublist(0, n);
    if (n == 5) return dnEval(vis, specials: specials).level / 13;
    // 4 known cards: average level over plausible 5th cards
    final known = {...vis};
    var sum = 0.0, cnt = 0;
    for (final c in cnDeck()) {
      if (known.contains(c)) continue;
      sum += dnEval([...vis, c], specials: specials).level;
      cnt++;
    }
    return sum / cnt / 10;
  }

  /// Probability of each hand level for a random 5-card hand (sampled once
  /// with a fixed seed, so it never touches game randomness).
  static final Map<bool, List<double>> _levelDist = {};
  List<double> _dist() => _levelDist.putIfAbsent(specials, () {
        final r = Random(12345);
        final deck = cnDeck();
        final d = List<double>.filled(14, 0);
        const n = 20000;
        for (var i = 0; i < n; i++) {
          deck.shuffle(r);
          d[dnEval(deck.sublist(0, 5), specials: specials).level] += 1.0 / n;
        }
        return d;
      });

  /// 困难：4 张已知时枚举第 5 张，按随机对手牌型分布算每单位下注的期望输赢
  /// （庄闲对称，同一数值也用于抢庄）。
  double _expectedMult(int seat) {
    final n = visibleCount(seat);
    if (n != 4) return 0;
    final vis = cards[seat].sublist(0, n);
    final dist = _dist();
    final known = {...vis};
    var sum = 0.0, cnt = 0;
    for (final c in cnDeck()) {
      if (known.contains(c)) continue;
      final lv = dnEval([...vis, c], specials: specials).level;
      var ev = 0.0;
      for (var l = 0; l < 14; l++) {
        if (l < lv) ev += dist[l] * dnMult(lv, payTable);
        if (l > lv) ev -= dist[l] * dnMult(l, payTable);
      }
      sum += ev;
      cnt++;
    }
    return sum / cnt;
  }

  Map<String, dynamic>? _botHard(int seat) {
    if (!mingpai) return null;
    final ev = _expectedMult(seat);
    switch (phase) {
      case 'grab':
        if (grab[seat] >= 0) return null;
        final m = ev > 0.9 ? 4 : ev > 0.5 ? 3 : ev > 0.2 ? 2 : ev > 0.05 ? 1 : 0;
        return {'type': 'grab', 'mult': m};
      case 'bet':
        if (seat == banker || bets[seat] > 0) return null;
        final b = ev > 0.6 ? 5 : ev > 0.3 ? 4 : ev > 0.1 ? 3 : ev > 0 ? 2 : 1;
        return {'type': 'bet', 'mult': b};
    }
    return null;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (botLevel <= 0 && (phase == 'grab' || phase == 'bet') && rng.nextDouble() < 0.5) {
      // 简单：随便抢庄 / 下注
      if (phase == 'grab' && grab[seat] < 0) return {'type': 'grab', 'mult': rng.nextInt(5)};
      if (phase == 'bet' && seat != banker && bets[seat] == 0) return {'type': 'bet', 'mult': 1 + rng.nextInt(5)};
    }
    if (botLevel >= 2 && (phase == 'grab' || phase == 'bet')) {
      final a = _botHard(seat);
      if (a != null) return a;
    }
    switch (phase) {
      case 'grab':
        if (grab[seat] >= 0) return null;
        final st = _strength(seat);
        var m = st > 0.75 ? 4 : st > 0.6 ? 3 : st > 0.5 ? 2 : st > 0.4 ? 1 : 0;
        if (!mingpai) m = rng.nextInt(3);
        return {'type': 'grab', 'mult': m};
      case 'bet':
        if (seat == banker || bets[seat] > 0) return null;
        final st = _strength(seat);
        final b = !mingpai ? 1 + rng.nextInt(2) : (st > 0.75 ? 5 : st > 0.6 ? 3 : st > 0.5 ? 2 : 1);
        return {'type': 'bet', 'mult': b};
      case 'show':
        return shown[seat] ? null : {'type': 'show'};
      case 'handEnd':
        return ready[seat] ? null : {'type': 'continue'};
    }
    return null;
  }

  @override
  int get botDelayMs => 600;
}
