import 'dart:math';

import '../../src/engine.dart';

/// Goods: 0 钻石 1 黄金 2 白银 3 布料 4 香料 5 皮革, 6 = 骆驼.
const int jpCamel = 6;
const List<String> jpNames = ['钻石', '黄金', '白银', '布料', '香料', '皮革', '骆驼'];
const List<int> jpDeckCounts = [6, 6, 6, 8, 8, 10];
const int jpCamelCount = 11;
const List<List<int>> jpTokenInit = [
  [7, 7, 5, 5, 5],
  [6, 6, 5, 5, 5],
  [5, 5, 5, 5, 5],
  [5, 3, 3, 2, 2, 1, 1],
  [5, 3, 3, 2, 2, 1, 1],
  [4, 3, 2, 1, 1, 1, 1, 1, 1],
];

/// Bonus bags for selling 3 / 4 / 5+ cards (values hidden until the round ends).
const List<List<int>> jpBonusInit = [
  [1, 1, 2, 2, 2, 3, 3],
  [4, 4, 5, 5, 6, 6],
  [8, 8, 9, 10, 10],
];
const List<double> jpBonusAvg = [2.0, 5.0, 9.0];
const int jpHandLimit = 7;

class Jaipur extends GameEngine {
  Jaipur(super.setup);

  bool get single => setup.opt<String>('rounds', 'bo3') == 'single';
  int get sealsToWin => single ? 1 : 2;

  String phase = 'play'; // play / roundEnd / over
  int turn = 0;
  int round = 0;
  int starter = 0;
  List<int> deck = [];
  List<int> market = [];
  final List<List<int>> hand = [[], []];
  final List<int> herd = [0, 0];
  List<List<int>> tokens = [];
  List<List<int>> bonus = [];
  final List<List<int>> goodsTaken = [[], []];
  final List<List<int>> bonusTaken = [[], []];
  final List<int> seals = [0, 0];
  final List<bool> ready = [false, false];
  int resigned = -1;
  Map<String, dynamic>? last;
  Map<String, dynamic>? roundResult;
  final List<Map<String, dynamic>> history = [];
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
    deck = shuffled([
      for (var g = 0; g < 6; g++)
        for (var i = 0; i < jpDeckCounts[g]; i++) g,
      for (var i = 0; i < jpCamelCount - 3; i++) jpCamel,
    ], rng);
    market = [jpCamel, jpCamel, jpCamel, deck.removeLast(), deck.removeLast()];
    for (var s = 0; s < 2; s++) {
      hand[s].clear();
      herd[s] = 0;
      goodsTaken[s].clear();
      bonusTaken[s].clear();
      for (var i = 0; i < 5; i++) {
        final c = deck.removeLast();
        if (c == jpCamel) {
          herd[s]++;
        } else {
          hand[s].add(c);
        }
      }
      hand[s].sort();
    }
    market.sort();
    tokens = [for (final t in jpTokenInit) List.of(t)];
    bonus = [for (final b in jpBonusInit) shuffled(b, rng)];
    turn = starter;
    phase = 'play';
    last = null;
    roundResult = null;
    ready[0] = ready[1] = false;
    _log('第 $round 局开始，${name(turn)} 先手');
  }

  int get emptyPiles => tokens.where((t) => t.isEmpty).length;

  void _refill() {
    while (market.length < 5 && deck.isNotEmpty) {
      market.add(deck.removeLast());
    }
    market.sort();
  }

  List<int> _ints(Object? v) => asIntList(v);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'over') throw GameError('游戏已结束');
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      if (seat < 0 || seat > 1) throw GameError('无效座位');
      ready[seat] = true;
      if (ready[0] && ready[1]) _newRound();
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    final h = hand[seat];
    switch (type) {
      case 'take':
        final i = asInt(a['idx']);
        if (i < 0 || i >= market.length) throw GameError('无效的市场位置');
        final c = market[i];
        if (c == jpCamel) throw GameError('骆驼要用“拿走全部骆驼”');
        if (h.length >= jpHandLimit) throw GameError('手牌已满 7 张，不能再拿货物');
        market.removeAt(i);
        h.add(c);
        h.sort();
        _refill();
        last = {'seat': seat, 'type': 'take', 'cards': [c]};
        _log('${name(seat)} 拿取 1 张${jpNames[c]}');
      case 'camels':
        final n = market.where((c) => c == jpCamel).length;
        if (n == 0) throw GameError('市场上没有骆驼');
        market.removeWhere((c) => c == jpCamel);
        herd[seat] += n;
        _refill();
        last = {'seat': seat, 'type': 'camels', 'n': n};
        _log('${name(seat)} 拿走全部 $n 头骆驼');
      case 'exchange':
        final mi = _ints(a['market']);
        final hi = _ints(a['hand']);
        final nc = asInt(a['camels'], 0);
        if (mi.toSet().length != mi.length || hi.toSet().length != hi.length) throw GameError('选择重复');
        if (mi.any((i) => i < 0 || i >= market.length) || hi.any((i) => i < 0 || i >= h.length)) throw GameError('无效选择');
        if (nc < 0 || nc > herd[seat]) throw GameError('骆驼数量不对');
        if (mi.length < 2) throw GameError('交换至少要 2 张牌');
        if (mi.length != hi.length + nc) throw GameError('拿入与换出的牌数必须相同');
        final takeCards = [for (final i in mi) market[i]];
        if (takeCards.contains(jpCamel)) throw GameError('交换时不能拿骆驼');
        final giveCards = [for (final i in hi) h[i]];
        if (giveCards.any(takeCards.contains)) throw GameError('不能用同种货物交换');
        if (h.length - hi.length + mi.length > jpHandLimit) throw GameError('交换后手牌会超过 7 张');
        for (final i in (List.of(mi)..sort((x, y) => y - x))) {
          market.removeAt(i);
        }
        for (final i in (List.of(hi)..sort((x, y) => y - x))) {
          h.removeAt(i);
        }
        h.addAll(takeCards);
        h.sort();
        market.addAll(giveCards);
        for (var k = 0; k < nc; k++) {
          market.add(jpCamel);
        }
        herd[seat] -= nc;
        market.sort();
        last = {'seat': seat, 'type': 'exchange', 'cards': takeCards, 'gave': [...giveCards, for (var k = 0; k < nc; k++) jpCamel]};
        _log('${name(seat)} 用 ${giveCards.length + nc} 张牌交换了 ${takeCards.map((c) => jpNames[c]).join('、')}');
      case 'sell':
        final g = asInt(a['good']);
        if (g < 0 || g > 5) throw GameError('无效货物');
        final have = h.where((c) => c == g).length;
        final n = asInt(a['count'], have);
        if (n < 1 || n > have) throw GameError('数量不对');
        if (g < 3 && n < 2) throw GameError('${jpNames[g]}至少要一次卖 2 张');
        for (var k = 0; k < n; k++) {
          h.remove(g);
        }
        final got = <int>[];
        for (var k = 0; k < n && tokens[g].isNotEmpty; k++) {
          got.add(tokens[g].removeAt(0));
        }
        goodsTaken[seat].addAll(got);
        var gotBonus = false;
        if (n >= 3) {
          final bag = bonus[min(n, 5) - 3];
          if (bag.isNotEmpty) {
            bonusTaken[seat].add(bag.removeLast());
            gotBonus = true;
          }
        }
        last = {'seat': seat, 'type': 'sell', 'good': g, 'n': n, 'tokens': got, 'bonus': gotBonus};
        _log('${name(seat)} 出售 $n 张${jpNames[g]}，获得 ${got.fold(0, (x, y) => x + y)} 分货物币${gotBonus ? ' + 1 枚奖励币' : ''}');
      default:
        throw GameError('未知操作');
    }
    if (emptyPiles >= 3 || market.length < 5) {
      _endRound(emptyPiles >= 3 ? '三种货物币已售罄' : '牌堆耗尽，无法补满市场');
    } else {
      turn = 1 - turn;
    }
  }

  int goodsSum(int s) => goodsTaken[s].fold(0, (a, b) => a + b);
  int bonusSum(int s) => bonusTaken[s].fold(0, (a, b) => a + b);

  void _endRound(String why) {
    final camel = herd[0] > herd[1] ? 0 : (herd[1] > herd[0] ? 1 : -1);
    final score = [for (var s = 0; s < 2; s++) goodsSum(s) + bonusSum(s) + (camel == s ? 5 : 0)];
    int w;
    String tie = '';
    if (score[0] != score[1]) {
      w = score[0] > score[1] ? 0 : 1;
    } else if (bonusTaken[0].length != bonusTaken[1].length) {
      w = bonusTaken[0].length > bonusTaken[1].length ? 0 : 1;
      tie = '（同分，奖励币多者胜）';
    } else if (goodsTaken[0].length != goodsTaken[1].length) {
      w = goodsTaken[0].length > goodsTaken[1].length ? 0 : 1;
      tie = '（同分，货物币多者胜）';
    } else {
      w = 1 - starter;
      tie = '（完全平局，后手胜）';
    }
    seals[w]++;
    roundResult = {
      'round': round,
      'why': why,
      'camel': camel,
      'winner': w,
      'tie': tie,
      'rows': [
        for (var s = 0; s < 2; s++)
          {
            'goods': goodsSum(s),
            'bonus': List.of(bonusTaken[s]),
            'bonusSum': bonusSum(s),
            'herd': herd[s],
            'camel': camel == s ? 5 : 0,
            'score': score[s],
          }
      ],
    };
    history.add(roundResult!);
    _log('第 $round 局结束（$why）：${name(0)} ${score[0]} 分，${name(1)} ${score[1]} 分，${name(w)} 获得优秀印章$tie');
    starter = 1 - w;
    if (seals[w] >= sealsToWin) {
      phase = 'over';
      _log('${name(w)} 赢得比赛！');
    } else {
      phase = 'roundEnd';
      ready[0] = ready[1] = false;
    }
  }

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < 2; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  bool get isOver => phase == 'over';

  int get winner {
    if (phase != 'over') return -1;
    if (resigned >= 0) return 1 - resigned;
    return seals[0] > seals[1] ? 0 : 1;
  }

  @override
  List<int>? get placings => phase == 'over' ? rankWinners(2, [winner]) : null;

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
    final reveal = phase != 'play';
    return {
      'phase': phase,
      'turn': turn,
      'round': round,
      'single': single,
      'seals': List.of(seals),
      'market': List.of(market),
      'deck': deck.length,
      'hand': me ? List.of(hand[seat]) : null,
      'handCount': [hand[0].length, hand[1].length],
      'herd': List.of(herd),
      'tokens': [for (final t in tokens) List.of(t)],
      'bonusLeft': [for (final b in bonus) b.length],
      'goods': [for (final g in goodsTaken) List.of(g)],
      'bonusCount': [bonusTaken[0].length, bonusTaken[1].length],
      'bonusValues': [
        for (var s = 0; s < 2; s++) (reveal || s == seat) ? List.of(bonusTaken[s]) : null,
      ],
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
  // Uses only: own hand, herd counts, market, public token piles, bag sizes,
  // opponent hand count, deck size and own bonus values.

  double _bonusExp(int n) {
    if (n < 3) return 0;
    final b = min(n, 5) - 3;
    return bonus[b].isEmpty ? 0 : jpBonusAvg[b];
  }

  double _topSum(int g, int n) {
    var s = 0;
    for (var k = 0; k < n && k < tokens[g].length; k++) {
      s += tokens[g][k];
    }
    return s.toDouble();
  }

  double _potential(List<int> h, int myHerd, int oppHerd) {
    var v = 0.0;
    for (var g = 0; g < 6; g++) {
      final c = h.where((x) => x == g).length;
      if (c == 0) continue;
      var t = _topSum(g, c) * 0.72;
      if (g < 3 && c == 1) t *= 0.45;
      t += _bonusExp(c) * 0.55;
      v += t;
    }
    v += myHerd * 0.45 + (myHerd > oppHerd ? 2.2 : (myHerd == oppHerd ? 1.0 : 0));
    if (h.length >= jpHandLimit) v -= 1.5;
    if (h.length == jpHandLimit - 1) v -= 0.4;
    return v;
  }

  /// What the market offers the opponent next turn (they move after us).
  double _gift(List<int> m, int unknown, int oppHand) {
    var best = 0.0;
    if (oppHand < jpHandLimit) {
      for (final c in m) {
        if (c != jpCamel && tokens[c].isNotEmpty) best = max(best, tokens[c].first.toDouble());
      }
    }
    final camels = m.where((c) => c == jpCamel).length;
    best = max(best, camels * 0.9);
    return best + unknown * 0.35;
  }

  List<(Map<String, dynamic>, double)> _candidates(int seat) {
    final h = hand[seat];
    final o = 1 - seat;
    final oppHand = hand[o].length;
    final base = _potential(h, herd[seat], herd[o]);
    final out = <(Map<String, dynamic>, double)>[];
    final urgency = emptyPiles >= 2 || deck.length <= 6;

    // sell
    for (var g = 0; g < 6; g++) {
      final c = h.where((x) => x == g).length;
      if (c == 0 || (g < 3 && c < 2)) continue;
      final nh = List.of(h);
      for (var k = 0; k < c; k++) {
        nh.remove(g);
      }
      var val = _topSum(g, c) + _bonusExp(c) + _potential(nh, herd[seat], herd[o]) - base;
      if (tokens[g].isNotEmpty && tokens[g].first >= 5 && c >= 2) val += 1.2;
      if (h.length >= jpHandLimit) val += 1.5;
      if (tokens[g].isEmpty) val -= 1;
      if (botLevel >= 2 && urgency) val += 1.5;
      out.add(({'type': 'sell', 'good': g, 'count': c}, val));
    }
    // take one good
    if (h.length < jpHandLimit) {
      final seen = <int>{};
      for (var i = 0; i < market.length; i++) {
        final c = market[i];
        if (c == jpCamel || !seen.add(c)) continue;
        final nm = List.of(market)..removeAt(i);
        final val = _potential([...h, c], herd[seat], herd[o]) - base - 0.5 * _gift(nm, 1, oppHand);
        out.add(({'type': 'take', 'idx': i}, val));
      }
    }
    // take camels
    final camels = market.where((c) => c == jpCamel).length;
    if (camels > 0) {
      final nm = market.where((c) => c != jpCamel).toList();
      var val = _potential(h, herd[seat] + camels, herd[o]) - base - 0.5 * _gift(nm, camels, oppHand);
      if (h.length >= jpHandLimit - 1) val += 0.5;
      out.add(({'type': 'camels'}, val));
    }
    // exchanges
    final goodsIdx = [for (var i = 0; i < market.length; i++) if (market[i] != jpCamel) i];
    final seenSets = <String>{};
    for (var mask = 1; mask < (1 << goodsIdx.length); mask++) {
      final sel = [for (var b = 0; b < goodsIdx.length; b++) if (mask & (1 << b) != 0) goodsIdx[b]];
      if (sel.length < 2) continue;
      final take = [for (final i in sel) market[i]]..sort();
      final key = take.join(',');
      if (!seenSets.add(key)) continue;
      final k = sel.length;
      final minHand = max(0, h.length + k - jpHandLimit);
      // hand cards that may be given: types not taken
      final giveable = [for (var i = 0; i < h.length; i++) if (!take.contains(h[i])) i];
      for (final preferCamels in const [true, false]) {
        var nCam = preferCamels ? min(herd[seat], k - minHand) : max(0, k - giveable.length);
        nCam = min(nCam, herd[seat]);
        final nHand = k - nCam;
        if (nHand < minHand || nHand > giveable.length || nCam < 0) continue;
        // greedily give the cheapest hand cards
        final remaining = List.of(giveable);
        final give = <int>[];
        for (var t = 0; t < nHand; t++) {
          var bestI = -1;
          var bestV = double.infinity;
          for (final i in remaining) {
            final trial = [for (var j = 0; j < h.length; j++) if (j != i && !give.contains(j)) h[j]];
            final v = -_potential(trial, herd[seat], herd[o]);
            if (v < bestV) {
              bestV = v;
              bestI = i;
            }
          }
          give.add(bestI);
          remaining.remove(bestI);
        }
        final nh = [for (var j = 0; j < h.length; j++) if (!give.contains(j)) h[j], ...take];
        final nm = [
          for (var i = 0; i < market.length; i++) if (!sel.contains(i)) market[i],
          for (final i in give) h[i],
          for (var t = 0; t < nCam; t++) jpCamel,
        ];
        final val = _potential(nh, herd[seat] - nCam, herd[o]) - base - 0.5 * _gift(nm, 0, oppHand) - 0.3;
        out.add(({'type': 'exchange', 'market': sel, 'hand': give, 'camels': nCam}, val));
        if (nCam == 0 && preferCamels) break;
      }
    }
    return out;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    final cands = _candidates(seat);
    if (cands.isEmpty) return null; // cannot happen: a legal action always exists
    if (botLevel == 0 && rng.nextDouble() < 0.5) return cands[rng.nextInt(cands.length)].$1;
    final noise = botLevel == 0 ? 3.0 : (botLevel == 1 ? 1.2 : 0.2);
    var best = cands.first;
    var bv = -double.infinity;
    for (final c in cands) {
      final v = c.$2 + rng.nextDouble() * noise;
      if (v > bv) {
        bv = v;
        best = c;
      }
    }
    return best.$1;
  }
}

const String jaipurRules = '''
# 概述
斋浦尔是两人对战的交易卡牌游戏。你们是印度斋浦尔的商人，从市场上收购货物、卖出换取货物币，并争取在本轮结束时拥有更多卢比。每轮得分更高的一方获得一枚“优秀印章”，先拿到 2 枚印章者获胜（选项“单局”时一局定胜负）。

# 配件
- 44 张货物牌：钻石 6、黄金 6、白银 6、布料 8、香料 8、皮革 10。
- 11 张骆驼牌（共 55 张）。
- 货物币：每种货物一叠，越早卖出面值越高（钻石 7 7 5 5 5，黄金 6 6 5 5 5，白银 5×5，布料/香料 5 3 3 2 2 1 1，皮革 4 3 2 1 1 1 1 1 1）。
- 奖励币：一次卖 3 张 / 4 张 / 5 张以上分别抽取一枚，面值分别为 1~3 / 4~6 / 8~10，面值保密直到本轮结束（自己能看到自己的）。
- 骆驼币：本轮结束时骆驼较多者得 5 分。

# 准备
市场摆 3 头骆驼，再从牌堆翻 2 张。每人发 5 张牌，手中的骆驼立即放到自己面前的驼群里（驼群公开，不占手牌）。

# 回合
轮到你时必须且只能做以下一件事：
- 拿取一张货物：从市场拿 1 张货物入手（手牌不得超过 7 张），然后从牌堆补满市场。
- 拿走全部骆驼：把市场上所有骆驼放进驼群，然后补满市场。
- 交换：从市场拿 2 张或以上货物，同时放回相同张数的牌（手中的货物和/或驼群中的骆驼）。不能从市场拿骆驼，也不能拿入与放回同一种货物；交换后手牌不超过 7 张。
- 出售：从手中卖出任意张同一种货物，按顺序拿取该货物最上面的货物币（币不够就只拿剩下的）。钻石、黄金、白银每次至少卖 2 张。卖 3、4、5 张及以上时额外获得一枚对应的奖励币。

# 本轮结束
满足其一立即结束：三种货物币全部卖光；或者需要补充市场时牌堆已空。结算：货物币 + 奖励币 + 骆驼币（骆驼多者 5 分，相同则无人得）。分高者获得印章；同分时奖励币枚数多者胜，再同则货物币枚数多者胜。输家下一局先手。

# 隐藏信息
对手手牌只显示张数；牌堆顺序未知；对手奖励币只显示枚数，本轮结束时才公开。电脑玩家同样只根据可见信息决策。

# 选项
- 赛制：三局两胜（默认）或单局决胜。
''';
