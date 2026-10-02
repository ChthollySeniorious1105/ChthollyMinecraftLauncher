import '../../src/engine.dart';
import 'cards.dart';
import 'gdy_rules.dart';

/// 干瞪眼（四川玩法）。2-6 人，54 张，庄家 6 张其余 5 张。
/// 跟牌必须同牌型且恰好大一级；2 可管任意同型单张/对子；大小王为百搭；
/// 三张及以上同点为炸弹，可管一切。一轮无人能管时，赢家摸一张牌后领出。
class Gandengyan extends GameEngine {
  Gandengyan(super.setup);

  late int rounds;
  int round = 0;
  int dealer = 0;
  late List<int> scores;
  late List<List<String>> hands;
  late List<int> played; // cards played this round per seat
  List<String> pile = [];
  late List<Map<String, dynamic>?> acts;
  GdyCombo? table;
  List<String> tableCards = [];
  int tableSeat = -1;
  int turn = 0;
  int bombs = 0;
  String phase = 'play'; // play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  String lastDraw = '';
  List<String> seen = []; // cards played this round (public)
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
    lastDraw = '${name(seat)} 认输，${name(1 - seat)} 获胜';
    result ??= {
      'winner': 1 - seat,
      'delta': List.filled(players, 0),
      'left': [for (final h in hands) h.length],
      'closed': List.filled(players, false),
      'bombs': bombs,
      'mult': multiplier(bombs),
      'hands': [for (final h in hands) List.of(h)],
    };
    host.log('${name(seat)} 认输');
  }

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 6);
    scores = List.filled(players, 0);
    dealer = rng.nextInt(players);
    host.log('干瞪眼开始：$players 人，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = c3Shuffled(c3Deck(), rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var s = 0; s < players; s++) {
      final n = s == dealer ? 6 : 5;
      for (var i = 0; i < n; i++) {
        hands[s].add(deck.removeLast());
      }
      c3Sort(hands[s]);
    }
    pile = deck;
    played = List.filled(players, 0);
    seen = [];
    acts = List.filled(players, null);
    table = null;
    tableCards = [];
    tableSeat = -1;
    turn = dealer;
    bombs = 0;
    result = null;
    lastDraw = '';
    phase = 'play';
    ready = List.filled(players, false);
    host.log('第 $round 局：${name(dealer)} 坐庄先出');
  }

  int _next(int s) => (s + 1) % players;
  bool get leading => table == null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _deal();
      return;
    }
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'pass') {
      if (leading) throw GameError('你是首家，必须出牌');
      acts[seat] = {'pass': true};
      _advance();
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final hand = hands[seat];
    final cards = c3TakeCards(a['cards'], hand, max: 20);
    final combo = leading ? gdyBestLead(cards) : gdyFollowAs(cards, table!);
    if (combo == null) {
      if (leading || gdyInterpret(cards).isEmpty) {
        throw GameError('不是合法牌型（单张、对子、顺子、连对、炸弹；王可百搭）');
      }
      throw GameError('管不上：必须出同牌型且恰好大一级（${table!.label}），或用2/炸弹');
    }
    c3Remove(hand, cards);
    c3Sort(cards);
    played[seat] += cards.length;
    seen.addAll(cards);
    if (combo.isBomb) {
      bombs++;
      host.log('${name(seat)} 打出${combo.label}！');
    }
    table = combo;
    tableCards = cards;
    tableSeat = seat;
    acts[seat] = {'cards': cards, 'label': combo.label};
    if (hand.isEmpty) {
      _endRound(seat);
      return;
    }
    _advance();
  }

  void _advance() {
    turn = _next(turn);
    if (turn == tableSeat) {
      // 没人管得上：赢家摸一张再领出
      table = null;
      tableCards = [];
      acts = List.filled(players, null);
      if (pile.isNotEmpty) {
        hands[turn].add(pile.removeLast());
        c3Sort(hands[turn]);
        lastDraw = '${name(turn)} 摸了一张牌';
      } else {
        lastDraw = '牌堆已空';
      }
    }
  }

  static int multiplier(int bombs) => 1 << (bombs > 10 ? 10 : bombs);

  void _endRound(int winner) {
    final mult = multiplier(bombs);
    final delta = List.filled(players, 0);
    final left = [for (final h in hands) h.length];
    final closed = List.filled(players, false);
    for (var s = 0; s < players; s++) {
      if (s == winner) continue;
      closed[s] = played[s] == 0; // 一张没出：闷，再翻倍
      final pay = left[s] * mult * (closed[s] ? 2 : 1);
      delta[s] -= pay;
      delta[winner] += pay;
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    result = {
      'winner': winner,
      'delta': delta,
      'left': left,
      'closed': closed,
      'bombs': bombs,
      'mult': mult,
      'hands': [for (final h in hands) List.of(h)],
    };
    host.log('第 $round 局 ${name(winner)} 出完获胜（炸弹$bombs个，×$mult）');
    dealer = winner;
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final ended = phase != 'play';
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'dealer': dealer,
      'turn': phase == 'play' ? turn : -1,
      'lead': leading,
      'hand': seat >= 0 && seat < players ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'scores': scores,
      'acts': acts,
      'table': table?.toJson(),
      'tableCards': tableCards,
      'tableSeat': tableSeat,
      'pile': pile.length,
      'bombs': bombs,
      'mult': multiplier(bombs),
      'lastDraw': lastDraw,
      'result': ended ? result : null,
      'ready': phase == 'roundEnd' ? ready : null,
      'resigned': resigned,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    final plays = gdyPlays(hand, table);
    if (botLevel == 0 && rng.nextDouble() < 0.45) {
      // 简单：随便出一手合法牌，或者干脆不要
      if (!leading && (plays.isEmpty || rng.nextDouble() < 0.35)) return {'type': 'pass'};
      if (plays.isEmpty) return {'type': 'play', 'cards': [hand.first]};
      return {'type': 'play', 'cards': plays[rng.nextInt(plays.length)].$1};
    }
    if (botLevel >= 2) return _hardBot(seat, hand, plays);
    if (leading) {
      if (plays.isEmpty) return {'type': 'play', 'cards': [hand.first]};
      // 能一次出完就出完
      final all = plays.where((p) => p.$1.length == hand.length);
      if (all.isNotEmpty) return {'type': 'play', 'cards': all.first.$1};
      // 优先出多张的非炸弹组合，否则最小单张
      final nonBomb = plays.where((p) => !p.$2.isBomb && !p.$1.any(c3IsJoker)).toList();
      final pool = nonBomb.isNotEmpty ? nonBomb : plays;
      pool.sort((a, b) {
        final la = a.$1.length, lb = b.$1.length;
        if (la != lb) return lb - la;
        return gdyCost(a.$1, a.$2) - gdyCost(b.$1, b.$2);
      });
      return {'type': 'play', 'cards': pool.first.$1};
    }
    if (plays.isEmpty) return {'type': 'pass'};
    final all = plays.where((p) => p.$1.length == hand.length);
    if (all.isNotEmpty) return {'type': 'play', 'cards': all.first.$1};
    final p = plays.first;
    final danger = [for (var s = 0; s < players; s++) if (s != seat) hands[s].length].any((n) => n <= 2);
    // 不轻易动用炸弹/王/2，除非有人快出完
    final expensive = p.$2.isBomb || p.$1.any(c3IsJoker) || p.$2.key == 15;
    if (expensive && !danger && hand.length > 3) return {'type': 'pass'};
    return {'type': 'play', 'cards': p.$1};
  }

  /// 困难：记牌（只用公开信息：自己的手牌 + 本局已出的牌），
  /// 领出时优先出别人“恰好大一级”接不上的牌，保留 2/王/炸弹到关键时刻。
  Map<String, dynamic> _hardBot(int seat, List<String> hand, List<(List<String>, GdyCombo)> plays) {
    final unseen = c3Deck();
    for (final c in [...hand, ...seen]) {
      unseen.remove(c);
    }
    final ug = c3Groups(unseen);
    final wildsOut = ug.containsKey(16) || ug.containsKey(17);
    int hidden(int v) => ug[v]?.length ?? 0;
    final oppMin = [for (var s = 0; s < players; s++) if (s != seat) hands[s].length].reduce((a, b) => a < b ? a : b);
    // How likely others can follow [c] (0 = impossible from public info).
    int followRisk(GdyCombo c) {
      if (c.isBomb) return 0;
      var r = 0;
      final per = c.type == 'single' ? 1 : (c.type == 'pair' ? 2 : (c.type == 'pairs' ? 2 : 1));
      final width = c.type == 'straight' ? c.len : (c.type == 'pairs' ? c.len ~/ 2 : 1);
      // 恰好大一级的那组牌
      if (c.key < 14 || (c.key == 14 && (c.type == 'single' || c.type == 'pair'))) {
        final lo = c.key + 1 - width + 1;
        var missing = 0;
        for (var v = lo; v <= c.key + 1; v++) {
          final need = per - hidden(v);
          if (need > 0) missing += need;
        }
        if (missing == 0) r += 3;
        if (missing == 1 && wildsOut) r += 1;
      }
      if ((c.type == 'single' || c.type == 'pair') && c.key != 15 && hidden(15) >= per) r += 2;
      return r;
    }

    int restPlays(List<String> cards) {
      final rest = List.of(hand);
      c3Remove(rest, cards);
      return gdyMinPlays(rest);
    }

    if (leading) {
      if (plays.isEmpty) return {'type': 'play', 'cards': [hand.first]};
      final all = plays.where((p) => p.$1.length == hand.length);
      if (all.isNotEmpty) return {'type': 'play', 'cards': all.first.$1};
      final nonBomb = plays.where((p) => !p.$2.isBomb && !p.$1.any(c3IsJoker)).toList();
      final pool = nonBomb.isNotEmpty ? nonBomb : plays;
      int score((List<String>, GdyCombo) p) {
        // 多张优先（和普通一致），再按代价；记牌估计别人接得上的风险作为次要因素
        var sc = gdyCost(p.$1, p.$2) - p.$1.length * 30 + followRisk(p.$2);
        // 对手快出完：别给他送能接的小单张/小对子
        if (oppMin <= p.$1.length && followRisk(p.$2) > 0) sc += 40;
        return sc;
      }

      pool.sort((a, b) => score(a) - score(b));
      return {'type': 'play', 'cards': pool.first.$1};
    }
    if (plays.isEmpty) return {'type': 'pass'};
    final all = plays.where((p) => p.$1.length == hand.length);
    if (all.isNotEmpty) return {'type': 'play', 'cards': all.first.$1};
    final now = gdyMinPlays(hand);
    final danger = oppMin <= 2;
    int fcost((List<String>, GdyCombo) p) => (restPlays(p.$1) - now + 1) * 25 + gdyCost(p.$1, p.$2);
    final sorted = List.of(plays)..sort((a, b) => fcost(a) - fcost(b));
    final best = sorted.first;
    final rest = restPlays(best.$1);
    if (rest <= 1) return {'type': 'play', 'cards': best.$1}; // 抢到出牌权就能走完
    final expensive = best.$2.isBomb || best.$1.any(c3IsJoker) || best.$2.key == 15;
    if (expensive && !danger && hand.length > 3) return {'type': 'pass'};
    return {'type': 'play', 'cards': best.$1};
  }
}
