import '../../src/engine.dart';
import 'cards.dart';
import 'shed_base.dart';
import 'shed_rules.dart';

/// 争上游：3-6 人，一副牌（5-6 人可用两副），单/对/三/顺/连对/飞机/炸弹，
/// 先出完为上游，最后为下游。下一局下游向上游进贡最大的一张牌，上游任选一张还贡，
/// 由下游先出。
class Zhengshangyou extends ShedBase {
  Zhengshangyou(super.setup);

  late ShedRules _rules;
  @override
  ShedRules get rules => _rules;

  late int rounds;
  late int decks;
  int round = 0;
  String phase = 'play'; // tribute | play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  List<int> lastFinish = [];
  int upSeat = -1, downSeat = -1;
  String? tributeCard; // card given by 下游
  String? returnCard; // card given back by 上游
  int starter = 0;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'tribute') return [upSeat];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 6);
    final d = setup.opt<int>('decks', 0);
    decks = d == 0 ? (players >= 5 ? 2 : 1) : d;
    _rules = ShedRules(rocketLen: decks * 2, planes: true);
    scores = List.filled(players, 0);
    starter = rng.nextInt(players);
    host.log('争上游开始：$players 人，$decks 副牌，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = c3Shuffled([for (var i = 0; i < decks; i++) ...c3Deck()], rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[(starter + i) % players].add(deck[i]);
    }
    for (final h in hands) {
      c3Sort(h);
    }
    finish = [];
    seen = [];
    resetTrickState();
    result = null;
    ready = List.filled(players, false);
    tributeCard = null;
    returnCard = null;
    if (lastFinish.length == players) {
      upSeat = lastFinish.first;
      downSeat = lastFinish.last;
      // 进贡：下游交出最大的一张
      final dh = hands[downSeat];
      final best = dh.last;
      dh.remove(best);
      hands[upSeat].add(best);
      c3Sort(hands[upSeat]);
      tributeCard = best;
      host.log('第 $round 局：下游 ${name(downSeat)} 向上游 ${name(upSeat)} 进贡 ${c3CardName(best)}');
      phase = 'tribute';
      turn = downSeat;
    } else {
      upSeat = downSeat = -1;
      phase = 'play';
      turn = starter;
      host.log('第 $round 局：${name(turn)} 先出');
    }
  }

  @override
  bool get roundDone => activeCount <= 1;

  @override
  void endRound() {
    for (var s = 0; s < players; s++) {
      if (active(s)) finish.add(s);
    }
    final delta = List.filled(players, 0);
    delta[finish.first] += 2;
    delta[finish.last] -= 2;
    if (players >= 4) {
      delta[finish[1]] += 1;
      delta[finish[players - 2]] -= 1;
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    result = {
      'finish': List.of(finish),
      'delta': delta,
      'hands': [for (final h in hands) List.of(h)],
    };
    host.log('第 $round 局结束：上游 ${name(finish.first)}，下游 ${name(finish.last)}');
    lastFinish = List.of(finish);
    starter = finish.first;
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  void _giveBack(String card) {
    hands[upSeat].remove(card);
    hands[downSeat].add(card);
    c3Sort(hands[downSeat]);
    returnCard = card;
    host.log('上游 ${name(upSeat)} 还贡一张牌，下游 ${name(downSeat)} 先出');
    phase = 'play';
    turn = downSeat;
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
    if (phase == 'tribute') {
      if (seat != upSeat) throw GameError('等待上游还贡');
      if (type != 'return') throw GameError('请选择一张牌还给下游');
      final cards = c3TakeCards(a['cards'], hands[seat], max: 1);
      if (cards.length != 1) throw GameError('只能还一张牌');
      _giveBack(cards.first);
      return;
    }
    if (phase != 'play') throw GameError('游戏已结束');
    handlePlay(seat, a);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...baseView(seat),
        'phase': phase,
        'turn': phase == 'play' ? turn : (phase == 'tribute' ? upSeat : -1),
        'round': round,
        'rounds': rounds,
        'decks': decks,
        'scores': scores,
        'up': upSeat,
        'down': downSeat,
        'lastFinish': lastFinish,
        // 贡牌公开，还贡只有双方可见
        'tribute': tributeCard,
        'returned': (seat == upSeat || seat == downSeat) ? returnCard : (returnCard == null ? null : 'back'),
        'result': phase == 'play' || phase == 'tribute' ? null : result,
        'ready': phase == 'roundEnd' ? ready : null,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase == 'tribute') {
      if (seat != upSeat) return null;
      // 还最小的单张（尽量不拆对子/炸弹）
      final h = hands[seat];
      if (botLevel == 0 && rng.nextBool()) return {'type': 'return', 'cards': [h[rng.nextInt(h.length)]]};
      final g = c3Groups(h);
      final singles = h.where((c) => g[c3Val(c)]!.length == 1 && c3Val(c) < 15).toList();
      return {'type': 'return', 'cards': [singles.isNotEmpty ? singles.first : h.first]};
    }
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    final others = [for (var s = 0; s < players; s++) if (s != seat && active(s)) hands[s].length];
    final oppMin = others.isEmpty ? 99 : others.reduce((a, b) => a < b ? a : b);
    final easy = easyMove(seat);
    if (easy != null) return easy;
    final pick = botLevel >= 2
        ? hardPick(seat, unseenBy(seat, [for (var i = 0; i < decks; i++) ...c3Deck()]), oppMin: oppMin)
        : shedBotPick(hand, table, rules, urgent: oppMin <= 3);
    if (pick == null) {
      if (leading) return {'type': 'play', 'cards': [hand.first]};
      return {'type': 'pass'};
    }
    return {'type': 'play', 'cards': pick};
  }
}
