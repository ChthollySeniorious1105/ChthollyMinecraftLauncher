import '../../src/engine.dart';
import 'cards.dart';
import 'shed_base.dart';
import 'shed_rules.dart';

/// 五十K：一副牌+大小王。四人对家组队（或 3-5 人各自为战）。
/// 5 = 5 分，10、K = 10 分，每墩的分归赢墩者；510K 为特殊炸弹（杂 < 纯，纯按 ♠>♥>♣>♦），
/// 4 张及以上同点为炸弹，王炸最大。本局剩牌中的分归头游。
int wsPoints(String c) {
  final v = c3Val(c);
  if (v == 5) return 5;
  if (v == 10 || v == 13) return 10;
  return 0;
}

int wsSum(Iterable<String> cards) => cards.fold(0, (a, c) => a + wsPoints(c));

class Wushik extends ShedBase {
  Wushik(super.setup);

  static const _rules = ShedRules(k510: true, rocketLen: 2);
  @override
  ShedRules get rules => _rules;

  late int rounds;
  late bool teams;
  int round = 0;
  late List<int> pts; // points captured this round
  String phase = 'play';
  Map<String, dynamic>? result;
  late List<bool> ready;
  int firstLead = 0;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (!teams) return rankByScore(scores);
    final a = scores[0], b = scores[1];
    if (a == b) return List.filled(players, 1);
    return rankWinners(players, [for (var s = 0; s < 4; s++) if ((a > b) == (s % 2 == 0)) s]);
  }

  int team(int s) => teams ? s % 2 : s;
  int partner(int s) => (s + 2) % 4;

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 4);
    teams = players == 4 && setup.opt<String>('mode', 'team') == 'team';
    scores = List.filled(players, 0);
    firstLead = rng.nextInt(players);
    host.log('五十K开始：$players 人${teams ? '（对家组队）' : '（各自为战）'}，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = c3Shuffled(c3Deck(), rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[(firstLead + i) % players].add(deck[i]);
    }
    for (final h in hands) {
      c3Sort(h);
    }
    pts = List.filled(players, 0);
    finish = [];
    seen = [];
    resetTrickState();
    turn = firstLead;
    result = null;
    phase = 'play';
    ready = List.filled(players, false);
    host.log('第 $round 局：${name(turn)} 先出');
  }

  @override
  bool get roundDone {
    if (activeCount <= 1) return true;
    if (teams) {
      for (final t in [0, 1]) {
        if (!active(t) && !active(t + 2)) return true;
      }
    }
    return false;
  }

  @override
  void onTrickWon(int seat, List<String> cards) {
    final p = wsSum(cards);
    if (p > 0) {
      pts[seat] += p;
      host.log('${name(seat)} 拿下 $p 分');
    }
  }

  @override
  int leaderAfter(int winner) {
    if (active(winner)) return winner;
    if (teams && active(partner(winner))) return partner(winner); // 接风
    return nextActive(winner);
  }

  @override
  void endRound() {
    final head = finish.first;
    final leftover = [for (var s = 0; s < players; s++) wsSum(hands[s])];
    final carry = leftover.fold(0, (a, b) => a + b);
    pts[head] += carry;
    final delta = List.filled(players, 0);
    String title;
    if (teams) {
      final tp = [pts[0] + pts[2], pts[1] + pts[3]];
      for (var s = 0; s < 4; s++) {
        delta[s] = tp[s % 2];
      }
      title = tp[0] == tp[1]
          ? '双方各得 ${tp[0]} 分，平局'
          : '${tp[0] > tp[1] ? '${name(0)}/${name(2)}' : '${name(1)}/${name(3)}'} 一方获胜 ${tp[0]}:${tp[1]}';
    } else {
      for (var s = 0; s < players; s++) {
        delta[s] = pts[s];
      }
      var best = 0;
      for (var s = 1; s < players; s++) {
        if (pts[s] > pts[best]) best = s;
      }
      title = '${name(best)} 本局得分最高（${pts[best]}分）';
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    result = {
      'title': title,
      'head': head,
      'carry': carry,
      'pts': List.of(pts),
      'delta': delta,
      'finish': List.of(finish),
      'hands': [for (final h in hands) List.of(h)],
    };
    host.log('第 $round 局结束：$title');
    firstLead = head;
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _deal();
      return;
    }
    if (phase != 'play') throw GameError('游戏已结束');
    handlePlay(seat, a);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...baseView(seat),
        'phase': phase,
        'turn': phase == 'play' ? turn : -1,
        'round': round,
        'rounds': rounds,
        'teams': teams,
        'scores': scores,
        'pts': pts,
        'trickPts': wsSum(trickCards),
        'result': phase == 'play' ? null : result,
        'ready': phase == 'roundEnd' ? ready : null,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    final trickPts = wsSum(trickCards);
    bool opp(int s) => teams ? team(s) != team(seat) : s != seat;
    final oppCounts = [for (var s = 0; s < players; s++) if (opp(s) && active(s)) hands[s].length];
    final oppMin = oppCounts.isEmpty ? 99 : oppCounts.reduce((a, b) => a < b ? a : b);
    final oppLow = oppMin <= 3;
    final easy = easyMove(seat);
    if (easy != null) return easy;
    if (!leading && teams && tableSeat == partner(seat) && !oppLow) {
      // 对家的牌不压（除非能直接出完）
      final whole = shedBotPick(hand, table, rules);
      if (whole != null && whole.length == hand.length) return {'type': 'play', 'cards': whole};
      return {'type': 'pass'};
    }
    List<String>? pick;
    if (botLevel >= 2) {
      // 困难：记牌；分多的墩或对手快走完时才动炸弹；手里的分牌尽量跟着自己赢的墩走
      pick = hardPick(seat, unseenBy(seat, c3Deck()), oppMin: oppMin, valuable: trickPts >= 15, cardPts: wsPoints);
    } else {
      pick = shedBotPick(hand, table, rules, urgent: oppLow || trickPts >= 15);
    }
    if (pick == null) {
      if (leading) return {'type': 'play', 'cards': [hand.first]};
      return {'type': 'pass'};
    }
    return {'type': 'play', 'cards': pick};
  }
}
