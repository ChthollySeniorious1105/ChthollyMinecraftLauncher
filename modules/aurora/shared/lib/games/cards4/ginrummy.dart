import '../../src/engine.dart';
import 'gr_rules.dart';

/// Gin Rummy：两人，每人 10 张，摸一张弃一张，组成组合（同点 3-4 张 / 同花顺 3+ 张），
/// 散牌点数 ≤ 10 时可以敲牌（knock），0 点为 Gin。见 [ginRummyRules]。
class GinRummy extends GameEngine {
  GinRummy(super.setup);

  late int target;
  late int knockLimit;
  late bool layoffOn;
  late List<List<String>> hands;
  List<String> stock = [];
  List<String> discard = [];
  String phase = 'first'; // first | draw | discard | handEnd | over
  int turn = 0;
  int dealer = 0;
  int firstPasses = 0;
  String? takenDiscard; // card just taken from the discard pile (can't be discarded this turn)
  String? lastDrawFrom; // 'stock' | 'discard'
  List<int> scores = [0, 0];
  List<int> handsWon = [0, 0];
  int hand = 0;
  Map<String, dynamic>? result;
  List<bool> ready = [false, false];
  int winner = -1; // match winner
  List<int> finalScores = [0, 0];
  bool resigned = false;
  final List<String> log = [];

  /// Public knowledge for bots: cards each player took from / refused on the discard pile.
  final List<Set<String>> picked = [{}, {}];
  final List<Set<String>> refused = [{}, {}];

  int opp(int s) => 1 - s;

  void _log(String s) {
    log.add(s);
    if (log.length > 10) log.removeAt(0);
    host.log(s);
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'first' || phase == 'draw' || phase == 'discard') return [turn];
    if (phase == 'handEnd') return [for (var s = 0; s < 2; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  List<int>? get placings => isOver ? (winner < 0 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]) : null;

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('无效座位');
    winner = opp(seat);
    resigned = true;
    finalScores = List.of(scores);
    phase = 'over';
    _log('${name(seat)} 认输，${name(winner)} 获胜');
  }

  @override
  void start() {
    target = setup.opt<int>('target', 100);
    knockLimit = setup.opt<int>('knock', 10);
    layoffOn = setup.opt<bool>('layoff', true);
    dealer = rng.nextInt(2);
    _log('Gin Rummy 开始：${target == 0 ? '单局' : '先到 $target 分'}');
    _deal();
  }

  void _deal() {
    hand++;
    final deck = shuffled(grDeck(), rng);
    hands = [deck.sublist(0, 10), deck.sublist(10, 20)];
    for (final h in hands) {
      grSort(h);
    }
    discard = [deck[20]];
    stock = deck.sublist(21);
    turn = opp(dealer);
    phase = 'first';
    firstPasses = 0;
    takenDiscard = null;
    lastDrawFrom = null;
    result = null;
    ready = [false, false];
    for (var s = 0; s < 2; s++) {
      picked[s].clear();
      refused[s].clear();
    }
    _log('第 $hand 手：${name(dealer)} 发牌，翻开 ${discard.last}');
  }

  // ---------------- actions ----------------

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat > 1) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    if (phase == 'handEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _deal();
      return;
    }
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final h = hands[seat];
    if (phase == 'first') {
      if (type == 'pass') {
        refused[seat].add(discard.last);
        firstPasses++;
        _log('${name(seat)} 不要翻开的牌');
        if (firstPasses >= 2) {
          phase = 'draw';
          turn = opp(dealer);
          _drawStock(turn);
        } else {
          turn = opp(seat);
        }
        return;
      }
      if (type != 'draw' || asStr(a['from']) != 'discard') throw GameError('请选择拿翻开的牌或不要');
      _drawDiscard(seat);
      return;
    }
    if (phase == 'draw') {
      if (type != 'draw') throw GameError('请先摸牌');
      final from = asStr(a['from']);
      if (from == 'stock') {
        refused[seat].add(discard.last);
        _drawStock(seat);
      } else if (from == 'discard') {
        if (discard.isEmpty) throw GameError('弃牌堆是空的');
        _drawDiscard(seat);
      } else {
        throw GameError('请选择从牌堆或弃牌堆摸牌');
      }
      return;
    }
    // discard phase
    if (type == 'knock' && a['card'] == null) {
      final arr = grBest(h);
      if (arr.points != 0) throw GameError('11 张全部组成组合才能 Big Gin');
      _endHand(seat, arr, big: true);
      return;
    }
    if (type != 'discard' && type != 'knock') throw GameError('请弃一张牌');
    final card = asStr(a['card']);
    if (!h.contains(card)) throw GameError('你没有这张牌');
    if (card == takenDiscard) throw GameError('刚从弃牌堆拿的牌不能马上弃掉');
    final rest = List.of(h)..remove(card);
    if (type == 'knock') {
      final arr = grBest(rest);
      if (arr.points > knockLimit) throw GameError('散牌 ${arr.points} 点，超过 $knockLimit 点不能敲牌');
      h.remove(card);
      discard.add(card);
      _endHand(seat, arr);
      return;
    }
    h.remove(card);
    discard.add(card);
    takenDiscard = null;
    if (stock.length <= 2) {
      _log('牌堆只剩 2 张，本手流局');
      result = {'kind': 'dead', 'winner': -1, 'points': 0, 'hands': [for (final x in hands) List.of(x)]};
      _afterHand(-1);
      return;
    }
    turn = opp(seat);
    phase = 'draw';
  }

  void _drawStock(int seat) {
    final c = stock.removeLast();
    hands[seat].add(c);
    grSort(hands[seat]);
    takenDiscard = null;
    lastDrawFrom = 'stock';
    phase = 'discard';
  }

  void _drawDiscard(int seat) {
    final c = discard.removeLast();
    hands[seat].add(c);
    grSort(hands[seat]);
    picked[seat].add(c);
    takenDiscard = c;
    lastDrawFrom = 'discard';
    _log('${name(seat)} 拿走弃牌 $c');
    phase = 'discard';
    turn = seat;
  }

  void _endHand(int k, GrArrangement arr, {bool big = false}) {
    final d = opp(k);
    final gin = arr.points == 0;
    final def = grDefend(hands[d], arr.melds, allowLayoff: layoffOn && !gin);
    final kp = arr.points, dp = def.own.points;
    int win, pts;
    String kind;
    if (gin) {
      win = k;
      pts = (big ? 31 : 25) + dp;
      kind = big ? 'biggin' : 'gin';
    } else if (dp > kp) {
      win = k;
      pts = dp - kp;
      kind = 'knock';
    } else {
      win = d;
      pts = 25 + kp - dp;
      kind = 'undercut';
    }
    scores[win] += pts;
    handsWon[win]++;
    result = {
      'kind': kind,
      'knocker': k,
      'winner': win,
      'points': pts,
      'knockerMelds': def.knockerMelds,
      'knockerDead': arr.deadwood,
      'knockerPts': kp,
      'defMelds': def.own.melds,
      'defDead': def.own.deadwood,
      'defPts': dp,
      'laid': def.laid,
      'hands': [for (final x in hands) List.of(x)],
    };
    final kn = {'gin': 'Gin', 'biggin': 'Big Gin', 'knock': '敲牌', 'undercut': '反敲（Undercut）'}[kind];
    _log('${name(k)} ${big ? 'Big Gin' : (gin ? 'Gin' : '敲牌（$kp 点）')}，$kn：${name(win)} +$pts');
    _afterHand(win);
  }

  void _afterHand(int win) {
    if (win >= 0) dealer = win;
    final done = target == 0 ? win >= 0 : scores.any((x) => x >= target);
    if (done) {
      final w = scores[0] == scores[1] ? (win >= 0 ? win : -1) : (scores[0] > scores[1] ? 0 : 1);
      winner = w;
      finalScores = List.of(scores);
      if (target > 0 && w >= 0) {
        finalScores[w] += 100; // 胜局奖励
        for (var s = 0; s < 2; s++) {
          finalScores[s] += 25 * handsWon[s]; // 每赢一手 +25
        }
        if (handsWon[opp(w)] == 0) finalScores[w] *= 2; // 零封翻倍
      }
      result = {...?result, 'final': finalScores};
      _log(w < 0 ? '比赛结束：平局' : '比赛结束：${name(w)} 获胜');
      phase = 'over';
    } else {
      phase = 'handEnd';
      ready = [false, false];
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat == 0 || seat == 1;
    final revealed = phase == 'handEnd' || phase == 'over';
    final myArr = me && !revealed ? grBest(hands[seat]) : null;
    return {
      'phase': phase,
      'turn': waitingFor.length == 1 && phase != 'handEnd' ? turn : -1,
      'dealer': dealer,
      'hand': me ? hands[seat] : <String>[],
      'counts': [hands[0].length, hands[1].length],
      'stock': stock.length,
      'discard': discard.length > 6 ? discard.sublist(discard.length - 6) : discard,
      'discardCount': discard.length,
      'taken': takenDiscard,
      'lastDraw': lastDrawFrom,
      'scores': scores,
      'handsWon': handsWon,
      'handNo': hand,
      'target': target,
      'knockLimit': knockLimit,
      'melds': myArr?.melds,
      'deadwood': myArr?.deadwood,
      'deadPts': myArr?.points,
      'result': revealed ? result : null,
      'ready': phase == 'handEnd' ? ready : null,
      'winner': winner,
      'final': phase == 'over' ? finalScores : null,
      'resigned': resigned,
      'log': log,
    };
  }

  // ---------------- bot ----------------

  /// Best discard for [cards] (11 cards): (card, resulting deadwood).
  (String, int) _bestDiscard(int seat, List<String> cards, {String? forbid}) {
    final foe = opp(seat);
    String? best;
    var bestScore = 1 << 30;
    var bestPts = 0;
    for (final c in cards.toSet()) {
      if (c == forbid) continue;
      final rest = List.of(cards)..remove(c);
      final arr = grBest(rest);
      var score = arr.points * 10;
      // keep near-melds: count pairs / 2-card runs among deadwood
      for (final x in arr.deadwood) {
        for (final y in arr.deadwood) {
          if (x == y) continue;
          if (grRank(x) == grRank(y) || (grSuit(x) == grSuit(y) && (grRank(x) - grRank(y)).abs() <= 2)) score -= 3;
        }
      }
      if (botLevel >= 2) {
        // don't feed the opponent: cards near what they picked up
        for (final p in picked[foe]) {
          if (grRank(p) == grRank(c) || (grSuit(p) == grSuit(c) && (grRank(p) - grRank(c)).abs() <= 2)) score += 25;
        }
        for (final r in refused[foe]) {
          if (grRank(r) == grRank(c)) score -= 5;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = c;
        bestPts = arr.points;
      }
    }
    return (best!, bestPts);
  }

  bool _wantsDiscardTop(int seat) {
    if (discard.isEmpty) return false;
    final top = discard.last;
    final h = hands[seat];
    final now = grBest(h).points;
    final (_, after) = _bestDiscard(seat, [...h, top], forbid: top);
    final inMeld = grBest([...h, top]).melds.any((m) => m.contains(top));
    return inMeld && after < now || after + 4 < now;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'handEnd') return ready[seat] ? null : {'type': 'continue'};
    if (seat != turn) return null;
    if (phase == 'first') {
      final want = botLevel == 0 ? rng.nextInt(3) == 0 : _wantsDiscardTop(seat);
      return want ? {'type': 'draw', 'from': 'discard'} : {'type': 'pass'};
    }
    if (phase == 'draw') {
      final want = botLevel == 0 ? rng.nextInt(4) == 0 : _wantsDiscardTop(seat);
      return {'type': 'draw', 'from': want && discard.isNotEmpty ? 'discard' : 'stock'};
    }
    if (phase != 'discard') return null;
    final h = hands[seat];
    if (grBest(h).points == 0) return {'type': 'knock', 'card': null};
    if (botLevel == 0) {
      final opts = h.where((c) => c != takenDiscard).toList();
      final c = rng.nextInt(2) == 0 ? opts[rng.nextInt(opts.length)] : _bestDiscard(seat, h, forbid: takenDiscard).$1;
      final pts = grBest(List.of(h)..remove(c)).points;
      return {'type': pts <= knockLimit ? 'knock' : 'discard', 'card': c};
    }
    final (c, pts) = _bestDiscard(seat, h, forbid: takenDiscard);
    var knock = pts <= knockLimit;
    if (knock && botLevel >= 2 && pts > 0) {
      // 困难：早期低散牌时尝试 Gin，后期或点数偏高时尽快敲
      final early = stock.length > 20;
      if (early && pts <= 2) knock = false;
      if (!early && stock.length > 10 && pts > 7) knock = rng.nextInt(2) == 0;
    }
    return {'type': knock ? 'knock' : 'discard', 'card': c};
  }
}

const String ginRummyRules = '''
# Gin Rummy
两人游戏，一副 52 张牌（无王）。A 最小。每人 10 张，翻开一张作为弃牌堆，其余为牌堆。
# 组合与散牌
- 组合（meld）：同点数 3~4 张（set），或同花色 3 张以上连续（run，A-2-3 可以，Q-K-A 不行）。
- 不在组合中的牌是散牌（deadwood），点数：A=1，2~9 按面值，10/J/Q/K=10。
- 系统自动按散牌点数最少的方式整理你的牌。
# 回合
- 第一轮：非发牌方可以拿翻开的牌，或不要；不要时发牌方可以拿；都不要时非发牌方从牌堆摸牌。
- 之后每回合：从牌堆顶或弃牌堆顶摸一张，然后弃一张。刚从弃牌堆拿的牌不能在同一回合弃掉。
- 牌堆只剩 2 张且无人敲牌时，本手流局，不计分。
# 敲牌（Knock）与 Gin
- 弃牌时，如果剩下 10 张的散牌 ≤ 敲牌上限（默认 10 点），可以选择“敲牌”结束本手。
- 散牌为 0 叫 Gin：得 25 分 + 对手散牌点数，对手不能贴牌。
- 摸牌后 11 张全部组成组合叫 Big Gin：得 31 分 + 对手散牌点数。
- 普通敲牌：对手亮牌，可以把散牌“贴”（lay off）到敲牌者的组合上，然后比较散牌。敲牌者更少则得到差值；
  若对手散牌 ≤ 敲牌者，叫反敲（Undercut），对手得 25 分 + 差值。
# 胜负
- 先到目标分者获胜（可选 100 / 50 分或单手决胜）。结束时胜者 +100 胜局奖励，双方每赢一手 +25，对手一手未赢（零封）胜者总分翻倍。
- 可以认输，对手直接获胜。上一手的赢家下一手发牌。
''';
