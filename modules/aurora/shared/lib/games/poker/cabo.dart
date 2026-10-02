import '../../src/engine.dart';

/// CABO：记忆型卡牌游戏，让自己面前 4 张牌总点数尽量小。
class Cabo extends GameEngine {
  Cabo(super.setup);

  late final int target = setup.opt<int>('target', 100);

  List<int> deck = []; // last = top
  List<int> discard = [];
  List<List<int>> cards = []; // per seat, 4 slots (can grow on penalty)
  /// known[viewer][owner] = set of slot indexes the viewer knows.
  List<List<Set<int>>> known = [];
  List<int> scores = [];
  int round = 0;
  int turn = 0;
  int starter = 0;
  String phase = 'peek'; // peek / turn / drawn / power / roundEnd / over
  List<bool> peekDone = [];
  int? drawn; // card in hand (drawn from deck)
  bool drawnFromDiscard = false;
  String power = ''; // peek / spy / swap
  int caboCaller = -1;
  int finalTurns = 0;
  int turnCount = 0;
  Map<String, dynamic>? lastAction;
  Map<String, dynamic>? result;
  List<bool> ready = [];
  // temporary reveal for the acting seat: {'owner': s, 'slot': i, 'value': v}
  Map<int, Map<String, dynamic>> reveal = {};

  @override
  void start() {
    scores = List.filled(players, 0);
    starter = rng.nextInt(players);
    _deal();
  }

  void _deal() {
    final d = <int>[0, 0, 13, 13];
    for (var v = 1; v <= 12; v++) {
      for (var i = 0; i < 4; i++) {
        d.add(v);
      }
    }
    deck = shuffled(d, rng);
    cards = [
      for (var s = 0; s < players; s++) [for (var i = 0; i < 4; i++) deck.removeLast()],
    ];
    known = [
      for (var v = 0; v < players; v++) [for (var o = 0; o < players; o++) <int>{}],
    ];
    discard = [deck.removeLast()];
    phase = 'peek';
    peekDone = List.filled(players, false);
    drawn = null;
    caboCaller = -1;
    finalTurns = 0;
    turnCount = 0;
    lastAction = null;
    result = null;
    reveal = {};
    turn = starter;
    host.log('第 ${round + 1} 局开始，请每人偷看自己的两张牌');
  }

  @override
  bool get isOver => phase == 'over';

  /// Lowest cumulative score wins; a resigned seat is last.
  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(scores, lowWins: true);
  }

  int resigned = -1;

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    phase = 'over';
    drawn = null;
    host.log('${name(seat)} 认输');
    host.log('游戏结束！${name(1 - seat)} 获胜');
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'peek':
        return [for (var s = 0; s < players; s++) if (!peekDone[s]) s];
      case 'roundEnd':
        return [for (var s = 0; s < players; s++) if (!ready[s]) s];
      case 'turn':
      case 'drawn':
      case 'power':
        return [turn];
    }
    return const [];
  }

  void _checkSlot(int owner, int slot) {
    if (owner < 0 || owner >= players || slot < 0 || slot >= cards[owner].length) throw GameError('无效的牌位');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'over') throw GameError('游戏已结束');
    if (phase == 'peek') {
      if (type != 'peek') throw GameError('请先偷看两张牌');
      if (peekDone[seat]) throw GameError('你已经看过了');
      final slots = asIntList(a['slots']).toSet();
      if (slots.length != 2 || slots.any((i) => i < 0 || i > 3)) throw GameError('请选择自己的两张牌');
      known[seat][seat].addAll(slots);
      peekDone[seat] = true;
      if (peekDone.every((d) => d)) {
        phase = 'turn';
        host.log('${name(turn)} 先行动');
      }
      return;
    }
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) {
        round++;
        starter = (starter + 1) % players;
        _deal();
      }
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    switch (phase) {
      case 'turn':
        if (type != 'cabo' && type != 'draw' && type != 'take') throw GameError('请选择摸牌、拿弃牌或喊 CABO');
        if (type == 'cabo' && caboCaller >= 0) throw GameError('已经有人喊过 CABO 了');
        if (type == 'take' && discard.isEmpty) throw GameError('弃牌堆为空');
        reveal.remove(seat);
        if (type == 'cabo') {
          caboCaller = seat;
          finalTurns = players - 1;
          lastAction = {'seat': seat, 'text': '喊了 CABO！'};
          host.log('${name(seat)} 喊了 CABO！其他人各还有一回合');
          _nextTurn();
          return;
        }
        if (type == 'draw') {
          if (deck.isEmpty) _reshuffle();
          drawn = deck.removeLast();
          drawnFromDiscard = false;
          phase = 'drawn';
          lastAction = {'seat': seat, 'text': '从牌堆摸了一张牌'};
          return;
        }
        if (type == 'take') {
          if (discard.isEmpty) throw GameError('弃牌堆为空');
          drawn = discard.removeLast();
          drawnFromDiscard = true;
          phase = 'drawn';
          lastAction = {'seat': seat, 'text': '拿走了弃牌堆顶的 $drawn'};
          return;
        }
        throw GameError('请选择摸牌、拿弃牌或喊 CABO');
      case 'drawn':
        if (type == 'discard') {
          if (drawnFromDiscard) throw GameError('从弃牌堆拿的牌必须交换');
          final v = drawn!;
          discard.add(v);
          drawn = null;
          lastAction = {'seat': seat, 'text': '弃掉了 $v'};
          if (v == 7 || v == 8) {
            power = 'peek';
          } else if (v == 9 || v == 10) {
            power = 'spy';
          } else if (v == 11 || v == 12) {
            power = 'swap';
          } else {
            power = '';
          }
          if (power.isNotEmpty) {
            phase = 'power';
            return;
          }
          _nextTurn();
          return;
        }
        if (type == 'swap') {
          final slots = asIntList(a['slots']).toSet().toList()..sort();
          if (slots.isEmpty) throw GameError('请选择要替换的牌');
          for (final i in slots) {
            _checkSlot(seat, i);
          }
          final v = drawn!;
          drawn = null;
          final vals = [for (final i in slots) cards[seat][i]];
          if (slots.length > 1 && vals.toSet().length != 1) {
            // penalty: keep all, add drawn card as a new slot
            cards[seat].add(v);
            known[seat][seat].add(cards[seat].length - 1);
            for (final i in slots) {
              known[seat][seat].add(i);
            }
            _publicReveal(seat, slots);
            lastAction = {'seat': seat, 'text': '多张交换失败（${vals.join(",")}），罚一张牌'};
            host.log('${name(seat)} 多张交换失败，罚一张牌');
            _nextTurn();
            return;
          }
          final keep = slots.first;
          cards[seat][keep] = v;
          for (var k = 1; k < slots.length; k++) {
            cards[seat][slots[k]] = -1;
          }
          for (var i = 0; i < slots.length; i++) {
            discard.add(vals[i]);
          }
          // remove emptied slots (from the back)
          final remap = _compact(seat);
          for (var o = 0; o < players; o++) {
            final ks = known[o][seat];
            final nk = <int>{};
            for (final i in ks) {
              if (slots.contains(i) && i != keep) continue;
              if (i == keep && o != seat && !drawnFromDiscard) continue;
              final ni = remap[i];
              if (ni != null) nk.add(ni);
            }
            known[o][seat] = nk;
          }
          // everybody saw a card taken from discard
          final nKeep = remap[keep]!;
          known[seat][seat].add(nKeep);
          if (drawnFromDiscard) {
            for (var o = 0; o < players; o++) {
              known[o][seat].add(nKeep);
            }
          }
          lastAction = {
            'seat': seat,
            'text': slots.length > 1 ? '用一张牌替换了 ${slots.length} 张 ${vals.first}' : '换下了一张 ${vals.first}',
          };
          _nextTurn();
          return;
        }
        throw GameError('请选择交换或弃掉');
      case 'power':
        if (type == 'skipPower') {
          _nextTurn();
          return;
        }
        if (power == 'peek') {
          if (type != 'peek') throw GameError('请选择自己的一张牌偷看');
          final slot = asInt(a['slot']);
          _checkSlot(seat, slot);
          known[seat][seat].add(slot);
          reveal[seat] = {'owner': seat, 'slot': slot, 'value': cards[seat][slot]};
          lastAction = {'seat': seat, 'text': '偷看了自己的一张牌'};
          _nextTurn();
          return;
        }
        if (power == 'spy') {
          if (type != 'spy') throw GameError('请选择对手的一张牌');
          final owner = asInt(a['owner']);
          final slot = asInt(a['slot']);
          if (owner == seat) throw GameError('请选择对手的牌');
          _checkSlot(owner, slot);
          known[seat][owner].add(slot);
          reveal[seat] = {'owner': owner, 'slot': slot, 'value': cards[owner][slot]};
          lastAction = {'seat': seat, 'text': '偷看了 ${name(owner)} 的一张牌'};
          _nextTurn();
          return;
        }
        if (type != 'blind') throw GameError('请选择自己的一张牌和对手的一张牌交换');
        final mySlot = asInt(a['slot']);
        final owner = asInt(a['owner']);
        final oSlot = asInt(a['oslot']);
        if (owner == seat) throw GameError('请选择对手的牌');
        if (owner == caboCaller) throw GameError('不能和喊 CABO 的玩家交换');
        _checkSlot(seat, mySlot);
        _checkSlot(owner, oSlot);
        final t = cards[seat][mySlot];
        cards[seat][mySlot] = cards[owner][oSlot];
        cards[owner][oSlot] = t;
        for (var o = 0; o < players; o++) {
          final kMine = known[o][seat].contains(mySlot);
          final kTheirs = known[o][owner].contains(oSlot);
          known[o][seat].remove(mySlot);
          known[o][owner].remove(oSlot);
          if (kTheirs) known[o][seat].add(mySlot);
          if (kMine) known[o][owner].add(oSlot);
        }
        lastAction = {'seat': seat, 'text': '与 ${name(owner)} 盲换了一张牌', 'swap': [seat, mySlot, owner, oSlot]};
        _nextTurn();
        return;
    }
    throw GameError('无效操作');
  }

  void _publicReveal(int seat, List<int> slots) {
    for (var o = 0; o < players; o++) {
      known[o][seat].addAll(slots);
    }
  }

  Map<int, int> _compact(int seat) {
    final remap = <int, int>{};
    final nl = <int>[];
    for (var i = 0; i < cards[seat].length; i++) {
      if (cards[seat][i] >= 0) {
        remap[i] = nl.length;
        nl.add(cards[seat][i]);
      }
    }
    cards[seat] = nl;
    return remap;
  }

  void _reshuffle() {
    final top = discard.removeLast();
    deck = shuffled(discard, rng);
    discard = [top];
    host.log('牌堆用完，弃牌堆重新洗入');
  }

  void _nextTurn() {
    phase = 'turn';
    power = '';
    drawn = null;
    turnCount++;
    if (caboCaller >= 0 && turn != caboCaller) {
      finalTurns--;
      if (finalTurns <= 0) {
        _score();
        return;
      }
    }
    turn = (turn + 1) % players;
    if (deck.isEmpty && discard.length <= 1) {
      _score();
    }
  }

  int _sum(int s) => cards[s].fold(0, (a, b) => a + b);

  void _score() {
    final sums = [for (var s = 0; s < players; s++) _sum(s)];
    final low = sums.reduce((a, b) => a < b ? a : b);
    final delta = List.filled(players, 0);
    for (var s = 0; s < players; s++) {
      if (sums[s] == low) {
        delta[s] = 0;
      } else {
        delta[s] = sums[s] + (s == caboCaller ? 10 : 0);
      }
    }
    if (caboCaller >= 0 && sums[caboCaller] != low) {
      // caller not lowest: penalty already added
    }
    final reset = <int>[];
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
      if (scores[s] == target) {
        scores[s] = target ~/ 2;
        reset.add(s);
      }
    }
    result = {'sums': sums, 'delta': delta, 'reset': reset, 'caller': caboCaller, 'cards': cards};
    host.log('本局结算：${[for (var s = 0; s < players; s++) '${name(s)} ${sums[s]}点(+${delta[s]})'].join('，')}');
    for (final s in reset) {
      host.log('${name(s)} 恰好 $target 分，重置为 ${target ~/ 2}！');
    }
    if (scores.any((x) => x > target)) {
      phase = 'over';
      final order = List.generate(players, (i) => i)..sort((a, b) => scores[a] - scores[b]);
      host.log('游戏结束！${name(order.first)} 以 ${scores[order.first]} 分获胜');
    } else {
      phase = 'roundEnd';
      ready = List.filled(players, false);
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final showAll = phase == 'roundEnd' || phase == 'over';
    return {
      'phase': phase,
      'turn': turn,
      'round': round,
      'target': target,
      'scores': scores,
      'deck': deck.length,
      'discardTop': discard.isEmpty ? null : discard.last,
      'discardCount': discard.length,
      'grid': [
        for (var o = 0; o < players; o++)
          [
            for (var i = 0; i < cards[o].length; i++)
              showAll || (me && known[seat][o].contains(i)) ? cards[o][i] : -1,
          ],
      ],
      'peekDone': peekDone,
      'drawn': me && seat == turn && phase != 'turn' ? drawn : null,
      'hasDrawn': phase == 'drawn',
      'fromDiscard': drawnFromDiscard,
      'power': phase == 'power' ? power : '',
      'caller': caboCaller,
      'last': lastAction,
      'reveal': me ? reveal[seat] : null,
      'result': result,
      'resigned': resigned,
      'ready': phase == 'roundEnd' ? ready : null,
      'over': isOver,
    };
  }

  // ---------------- bot ----------------
  /// Estimated value of an unknown card.
  static const double _unknown = 6.5;

  double _est(int seat, int owner) {
    var s = 0.0;
    for (var i = 0; i < cards[owner].length; i++) {
      s += known[seat][owner].contains(i) ? cards[owner][i] : _unknown;
    }
    return s;
  }

  /// Slot to replace with value v, or -1.
  int _replaceSlot(int seat, int v, {bool must = false}) {
    var best = -1;
    var bestGain = 0.0;
    for (var i = 0; i < cards[seat].length; i++) {
      final cur = known[seat][seat].contains(i) ? cards[seat][i].toDouble() : _unknown;
      final gain = cur - v;
      if (gain > bestGain || (must && best < 0)) {
        best = i;
        bestGain = gain;
      }
      if (must && gain > bestGain) {
        best = i;
        bestGain = gain;
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'peek':
        if (botLevel == 0) {
          final a = rng.nextInt(4);
          return {'type': 'peek', 'slots': [a, (a + 1 + rng.nextInt(3)) % 4]};
        }
        return {'type': 'peek', 'slots': [0, 1]};
      case 'roundEnd':
        return {'type': 'continue'};
      case 'over':
        return null;
    }
    if (seat != turn) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.45) {
      final e = _easyMove(seat);
      if (e != null) return e;
    }
    if (phase == 'turn') {
      final est = _est(seat, seat);
      if (botLevel >= 2 && caboCaller < 0) {
        // 困难：与对手的估计点数比较后再喊
        final known0 = known[seat][seat].length;
        final opp = [for (var o = 0; o < players; o++) if (o != seat) _est(seat, o)];
        final minOpp = opp.reduce((a, b) => a < b ? a : b);
        if (known0 == cards[seat].length && est <= 12 && est + 2 < minOpp) return {'type': 'cabo'};
        if (known0 == cards[seat].length && est <= 4) return {'type': 'cabo'};
      }
      final allKnown = known[seat][seat].length == cards[seat].length;
      final patience = turnCount ~/ players;
      if (caboCaller < 0 && ((allKnown && est <= 8 + patience) || est <= 5 + patience)) {
        return {'type': 'cabo'};
      }
      final top = discard.isEmpty ? 99 : discard.last;
      if (top <= 4 && _replaceSlot(seat, top) >= 0) return {'type': 'take'};
      return {'type': 'draw'};
    }
    if (phase == 'drawn') {
      final v = drawn!;
      if (drawnFromDiscard) {
        return {'type': 'swap', 'slots': [_replaceSlot(seat, v, must: true)]};
      }
      final slot = _replaceSlot(seat, v);
      final isPower = v >= 7 && v <= 12;
      if (slot >= 0) {
        final cur = known[seat][seat].contains(slot) ? cards[seat][slot].toDouble() : _unknown;
        // prefer using the power if the gain is small
        if (!(isPower && cur - v < 2)) {
          // multi-swap: known duplicates of same value
          final dup = [
            for (var i = 0; i < cards[seat].length; i++)
              if (known[seat][seat].contains(i) &&
                  known[seat][seat].contains(slot) &&
                  cards[seat][i] == cards[seat][slot])
                i,
          ];
          if (dup.length >= 2 && cards[seat][slot] > v) return {'type': 'swap', 'slots': dup};
          return {'type': 'swap', 'slots': [slot]};
        }
      }
      return {'type': 'discard'};
    }
    if (phase == 'power') {
      if (power == 'peek') {
        for (var i = 0; i < cards[seat].length; i++) {
          if (!known[seat][seat].contains(i)) return {'type': 'peek', 'slot': i};
        }
        return {'type': 'skipPower'};
      }
      final opps = [for (var s = 0; s < players; s++) if (s != seat) s];
      if (power == 'spy') {
        for (final o in opps) {
          for (var i = 0; i < cards[o].length; i++) {
            if (!known[seat][o].contains(i)) return {'type': 'spy', 'owner': o, 'slot': i};
          }
        }
        return {'type': 'skipPower'};
      }
      // blind swap: give my highest known card for a known low opponent card (or unknown)
      var mySlot = -1;
      var myVal = -1.0;
      for (var i = 0; i < cards[seat].length; i++) {
        final v = known[seat][seat].contains(i) ? cards[seat][i].toDouble() : _unknown;
        if (v > myVal) {
          myVal = v;
          mySlot = i;
        }
      }
      var bo = -1, bs = -1;
      var bv = 99.0;
      for (final o in opps) {
        if (o == caboCaller) continue;
        for (var i = 0; i < cards[o].length; i++) {
          final v = known[seat][o].contains(i) ? cards[o][i].toDouble() : _unknown;
          if (v < bv) {
            bv = v;
            bo = o;
            bs = i;
          }
        }
      }
      if (bo >= 0 && mySlot >= 0 && bv < myVal - 1) {
        return {'type': 'blind', 'slot': mySlot, 'owner': bo, 'oslot': bs};
      }
      return {'type': 'skipPower'};
    }
    return null;
  }

  /// 简单：随手的合法操作（不考虑已知牌）。
  Map<String, dynamic>? _easyMove(int seat) {
    final n = cards[seat].length;
    switch (phase) {
      case 'turn':
        if (caboCaller < 0 && turnCount >= players * 3 && rng.nextDouble() < 0.15) return {'type': 'cabo'};
        return {'type': discard.isNotEmpty && rng.nextBool() ? 'take' : 'draw'};
      case 'drawn':
        if (!drawnFromDiscard && rng.nextBool()) return {'type': 'discard'};
        return {'type': 'swap', 'slots': [rng.nextInt(n)]};
      case 'power':
        return {'type': 'skipPower'};
    }
    return null;
  }

  @override
  int get botDelayMs => 900;
}
