import 'dart:math';

import '../../src/engine.dart';

/// Card code: colour * 12 + k, k = 0..2 investment (handshake), k = 3..11 → value 2..10.
const List<String> lcColorNames = ['黄', '蓝', '白', '绿', '红'];
const int lcColors = 5;
int lcColor(int c) => c ~/ 12;
int lcValue(int c) => c % 12 < 3 ? 0 : c % 12 - 1; // 0 = investment
bool lcInvest(int c) => c % 12 < 3;
String lcName(int c) => '${lcColorNames[lcColor(c)]}${lcInvest(c) ? '投资' : '${lcValue(c)}'}';

int lcScore(List<int> exp) {
  if (exp.isEmpty) return 0;
  var sum = 0, inv = 0;
  for (final c in exp) {
    if (lcInvest(c)) {
      inv++;
    } else {
      sum += lcValue(c);
    }
  }
  return (sum - 20) * (1 + inv) + (exp.length >= 8 ? 20 : 0);
}

class LostCities extends GameEngine {
  LostCities(super.setup);

  int get totalRounds => setup.opt<int>('rounds', 1);

  String phase = 'play'; // play / draw / roundEnd / over
  int turn = 0;
  int round = 0;
  int starter = 0;
  List<int> deck = [];
  final List<List<int>> hand = [[], []];
  final List<List<List<int>>> exped = [
    [for (var i = 0; i < lcColors; i++) <int>[]],
    [for (var i = 0; i < lcColors; i++) <int>[]],
  ];
  final List<List<int>> discard = [for (var i = 0; i < lcColors; i++) <int>[]];
  int justDiscarded = -1;
  final List<int> total = [0, 0];
  final List<bool> ready = [false, false];
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? roundResult;
  Map<String, dynamic>? last;
  int resigned = -1;
  final List<String> recent = [];

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 8) recent.removeAt(0);
  }

  @override
  void start() {
    starter = rng.nextInt(2);
    _newRound();
  }

  void _newRound() {
    round++;
    deck = shuffled(List.generate(60, (i) => i), rng);
    for (var s = 0; s < 2; s++) {
      hand[s]
        ..clear()
        ..addAll([for (var i = 0; i < 8; i++) deck.removeLast()])
        ..sort();
      for (final e in exped[s]) {
        e.clear();
      }
    }
    for (final d in discard) {
      d.clear();
    }
    turn = starter;
    phase = 'play';
    justDiscarded = -1;
    last = null;
    roundResult = null;
    ready[0] = ready[1] = false;
    _log('第 $round 局开始，${name(turn)} 先手');
  }

  bool canPlay(int seat, int card) {
    final e = exped[seat][lcColor(card)];
    if (e.isEmpty) return true;
    final top = e.last;
    if (lcInvest(card)) return lcInvest(top);
    return lcValue(card) > lcValue(top);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'over') throw GameError('游戏已结束');
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      if (seat < 0 || seat > 1) throw GameError('无效座位');
      ready[seat] = true;
      if (ready[0] && ready[1]) {
        starter = 1 - starter;
        _newRound();
      }
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    if (phase == 'play') {
      final card = asInt(a['card']);
      if (!hand[seat].contains(card)) throw GameError('你没有这张牌');
      if (type == 'play') {
        if (!canPlay(seat, card)) throw GameError('必须按从小到大的顺序出牌（投资牌只能在数字牌之前）');
        hand[seat].remove(card);
        exped[seat][lcColor(card)].add(card);
        justDiscarded = -1;
        last = {'seat': seat, 'type': 'play', 'card': card};
        _log('${name(seat)} 在${lcColorNames[lcColor(card)]}色探险打出 ${lcName(card)}');
      } else if (type == 'discard') {
        hand[seat].remove(card);
        discard[lcColor(card)].add(card);
        justDiscarded = lcColor(card);
        last = {'seat': seat, 'type': 'discard', 'card': card};
        _log('${name(seat)} 弃掉 ${lcName(card)}');
      } else {
        throw GameError('请先出牌或弃牌');
      }
      phase = 'draw';
      return;
    }
    // draw
    if (type != 'draw') throw GameError('请摸牌');
    final from = asInt(a['from']);
    int card;
    if (from == -1) {
      if (deck.isEmpty) throw GameError('牌堆已空');
      card = deck.removeLast();
      last = {...?last, 'drew': -1};
    } else {
      if (from < 0 || from >= lcColors) throw GameError('无效弃牌堆');
      if (discard[from].isEmpty) throw GameError('该弃牌堆是空的');
      if (from == justDiscarded) throw GameError('不能立刻拿回刚弃掉的牌');
      card = discard[from].removeLast();
      last = {...?last, 'drew': from, 'drewCard': card};
      _log('${name(seat)} 从弃牌堆拿走 ${lcName(card)}');
    }
    hand[seat]
      ..add(card)
      ..sort();
    justDiscarded = -1;
    if (deck.isEmpty) {
      _endRound();
    } else {
      turn = 1 - turn;
      phase = 'play';
    }
  }

  void _endRound() {
    final sc = [for (var s = 0; s < 2; s++) [for (final e in exped[s]) lcScore(e)]];
    final rs = [for (var s = 0; s < 2; s++) sc[s].fold(0, (a, b) => a + b)];
    for (var s = 0; s < 2; s++) {
      total[s] += rs[s];
    }
    roundResult = {
      'round': round,
      'exp': sc,
      'score': rs,
      'total': List.of(total),
    };
    history.add(roundResult!);
    _log('第 $round 局结束：${name(0)} ${rs[0]} 分，${name(1)} ${rs[1]} 分');
    if (round >= totalRounds) {
      phase = 'over';
      final w = winner;
      _log(w < 0 ? '比赛平局！' : '${name(w)} 获胜！（${total[0]} : ${total[1]}）');
    } else {
      phase = 'roundEnd';
      ready[0] = ready[1] = false;
    }
  }

  int get winner {
    if (phase != 'over') return -1;
    if (resigned >= 0) return 1 - resigned;
    if (total[0] == total[1]) return -2;
    return total[0] > total[1] ? 0 : 1;
  }

  @override
  List<int> get waitingFor {
    if (phase == 'play' || phase == 'draw') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < 2; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    final w = winner;
    return w == -2 ? [1, 1] : rankWinners(2, [w]);
  }

  @override
  bool get canResign => phase != 'over';

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    if (seat < 0 || seat > 1) throw GameError('无效座位');
    resigned = seat;
    phase = 'over';
    _log('${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < 2;
    return {
      'phase': phase,
      'turn': turn,
      'round': round,
      'rounds': totalRounds,
      'deck': deck.length,
      'hand': me ? List.of(hand[seat]) : null,
      'handCount': [hand[0].length, hand[1].length],
      'exped': [for (final p in exped) [for (final e in p) List.of(e)]],
      'discard': [for (final d in discard) List.of(d)],
      'justDiscarded': justDiscarded,
      'scores': [for (var s = 0; s < 2; s++) [for (final e in exped[s]) lcScore(e)]],
      'total': List.of(total),
      'last': last,
      'recent': List.of(recent),
      'roundResult': roundResult,
      'history': history,
      'ready': List.of(ready),
      'resigned': resigned,
      'winner': winner,
      'placings': placings,
    };
  }

  // ------------------------------------------------------------------ bot
  // Only uses: own hand, all expeditions, discard piles, deck size.

  /// Estimated final value of expedition [col] for [seat] if it holds [cards]
  /// plus the playable cards from [h] of that colour.
  double _expValue(int seat, int col, List<int> cards, List<int> h, int turnsLeft) {
    final playable = [for (final c in h) if (lcColor(c) == col) c]..sort();
    final all = [...cards];
    final topV = cards.isEmpty ? -1 : (lcInvest(cards.last) ? 0 : lcValue(cards.last));
    var budget = max(1, turnsLeft);
    for (final c in playable) {
      if (budget <= 0) break;
      if (lcInvest(c)) {
        if (all.every(lcInvest)) {
          all.add(c);
          budget--;
        }
      } else if (lcValue(c) > topV) {
        all.add(c);
        budget--;
      }
    }
    if (all.isEmpty) return 0;
    final inv = all.where(lcInvest).length;
    var sum = all.fold(0, (a, c) => a + lcValue(c)).toDouble();
    // some expected future draws of this colour if many turns remain
    sum += min(turnsLeft / 12.0, 1.0) * 4;
    return (sum - 20) * (1 + inv) + (all.length >= 8 ? 20 : 0);
  }

  double _evalHand(int seat, List<int> h, List<List<int>> myExp) {
    final turnsLeft = deck.length ~/ 2;
    var v = 0.0;
    for (var col = 0; col < lcColors; col++) {
      final ev = _expValue(seat, col, myExp[col], h, turnsLeft);
      v += myExp[col].isEmpty ? max(0, ev) : ev;
    }
    return v;
  }

  /// How useful [card] would be to the opponent (if they could pick it up).
  double _oppUse(int seat, int card) {
    final o = 1 - seat;
    final e = exped[o][lcColor(card)];
    if (e.isEmpty) return lcInvest(card) ? 0.5 : lcValue(card) / 6;
    if (!canPlay(o, card)) return 0;
    final inv = e.where(lcInvest).length;
    return (lcInvest(card) ? 3 : lcValue(card).toDouble()) * (1 + inv) / 2;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if ((phase != 'play' && phase != 'draw') || seat != turn) return null;
    final h = hand[seat];
    final noise = botLevel == 0 ? 6.0 : (botLevel == 1 ? 1.5 : 0.3);
    if (phase == 'play') {
      if (botLevel == 0 && rng.nextDouble() < 0.3) {
        final c = h[rng.nextInt(h.length)];
        return {'type': canPlay(seat, c) && rng.nextBool() ? 'play' : 'discard', 'card': c};
      }
      final base = _evalHand(seat, h, exped[seat]);
      Map<String, dynamic>? best;
      var bv = -double.infinity;
      for (final c in h) {
        final col = lcColor(c);
        final nh = List.of(h)..remove(c);
        if (canPlay(seat, c)) {
          final ne = [for (var i = 0; i < lcColors; i++) i == col ? [...exped[seat][i], c] : exped[seat][i]];
          var v = _evalHand(seat, nh, ne) - base;
          // playing a card skips the ones between: penalise gaps
          final topV = exped[seat][col].isEmpty ? (lcInvest(c) ? -1 : 1) : lcValue(exped[seat][col].last);
          final gap = [for (final x in h) if (lcColor(x) == col && !lcInvest(x) && lcValue(x) > topV && lcValue(x) < lcValue(c)) x].length;
          if (!lcInvest(c)) v -= gap * 3;
          if (exped[seat][col].isEmpty) {
            final mine = [for (final x in h) if (lcColor(x) == col) x];
            final s = mine.fold(0, (a, x) => a + lcValue(x));
            if (s < 18 && deck.length > 10) v -= 6; // not enough to start
            if (deck.length < 12 && s < 20) v -= 10;
          }
          v += 0.5; // tempo: playing keeps cards out of the discard
          v += rng.nextDouble() * noise;
          if (v > bv) {
            bv = v;
            best = {'type': 'play', 'card': c};
          }
        }
        var dv = _evalHand(seat, nh, exped[seat]) - base - _oppUse(seat, c) * 1.5;
        if (!canPlay(seat, c) && exped[seat][col].isNotEmpty) dv += 1; // dead card
        dv -= 1.0;
        dv += rng.nextDouble() * noise;
        if (dv > bv) {
          bv = dv;
          best = {'type': 'discard', 'card': c};
        }
      }
      return best;
    }
    // draw phase
    var bestFrom = -1;
    var bv = 0.0;
    final base = _evalHand(seat, h, exped[seat]);
    for (var col = 0; col < lcColors; col++) {
      if (col == justDiscarded || discard[col].isEmpty) continue;
      final c = discard[col].last;
      var v = _evalHand(seat, [...h, c], exped[seat]) - base;
      if (!canPlay(seat, c) && exped[seat][col].isNotEmpty) v -= 5;
      if (exped[seat][col].isEmpty) v -= 2;
      v += _oppUse(seat, c) * 0.4; // deny the opponent
      // late game: drawing from discard stalls the clock — good when ahead
      if (botLevel >= 2 && deck.length < 8) v += 0.8;
      v += rng.nextDouble() * noise - 1.5;
      if (v > bv) {
        bv = v;
        bestFrom = col;
      }
    }
    return {'type': 'draw', 'from': bestFrom};
  }
}

const String lostCitiesRules = '''
# 概述
失落的城市是两人卡牌游戏。你们各自组织五支探险队（黄、蓝、白、绿、红），把同色卡牌按从小到大的顺序打出来推进探险。探险一旦启动就要先付出 20 点的成本，卡牌不够多就会亏分，所以什么时候出发、押多少注是关键。

# 配件
60 张牌：每种颜色 12 张——3 张投资牌（握手图案）和数字 2~10 各一张。

# 准备
每人 8 张手牌，剩余为牌堆。桌面中间每种颜色有一个公共弃牌堆。

# 回合
每回合先做第一步、再做第二步：
- 第一步（出牌或弃牌）：把一张手牌打到自己该颜色的探险队上，必须比该队最后一张牌更大；投资牌只能在该颜色还没有数字牌时打出（可以连续打多张投资）。或者，把一张手牌正面朝上弃到对应颜色的弃牌堆顶。
- 第二步（摸牌）：从牌堆顶摸一张，或者拿走任意一个弃牌堆最上面的那张牌。不能拿回本回合刚弃掉的那一堆的牌。
手牌始终保持 8 张。

# 结束与计分
牌堆最后一张牌被摸走时本局立即结束（手牌不计分）。每支已启动（至少有 1 张牌）的探险单独计分：
- 数字牌总和减 20；
- 再乘以（1 + 投资牌张数），亏分也会被放大；
- 该探险有 8 张或以上牌时，额外 +20（不受投资倍数影响）。
没打过牌的颜色不计分。所有探险分数相加为本局得分（可能为负）。

# 策略提示
- 不要轻易启动手里牌不多的颜色；投资牌风险和回报都翻倍。
- 弃牌时注意对手的探险——别把对手需要的牌喂给他。
- 从弃牌堆摸牌可以拖慢牌堆耗尽的速度。

# 选项
- 局数：1 局，或 3 局累计总分（每局轮换先手）。总分高者获胜，同分为平局。
''';
