import 'dart:math';

import '../../src/engine.dart';
import 'common.dart';

/// 蟑螂扑克 (Kakerlakenpoker / Cockroach Poker).
const cockroachNames = ['蟑螂', '老鼠', '蝙蝠', '苍蝇', '蝎子', '蟾蜍', '蜘蛛', '臭虫'];
const cockroachEmoji = ['🪳', '🐀', '🦇', '🪰', '🦂', '🐸', '🕷️', '🐞'];

String _cn(int c) => c >= 0 && c < 8 ? cockroachNames[c] : '?';

const cockroachRules = '''
# 概述
蟑螂扑克（Kakerlakenpoker）是 3~6 人的虚张声势小游戏。牌堆共 64 张：蟑螂、老鼠、蝙蝠、苍蝇、蝎子、蟾蜍、蜘蛛、臭虫 8 种害虫各 8 张。开局把所有牌发完（人数除不尽时有人多一张）。手牌对他人保密，每人面前亮出的害虫牌是公开的。

# 回合流程
- 当前玩家从手牌选一张，暗面递给另一名玩家，同时宣称“这是一只××”。宣称可以是真话也可以是谎话。
- 收到牌的玩家有两种选择：
- 1. 判断：说“真”（宣称属实）或“假”（宣称是谎话），然后翻开这张牌。猜对了，递牌的人把这张牌正面朝上放在自己面前；猜错了，判断者自己收下这张牌。
- 2. 偷看并转手：偷偷看一眼这张牌，然后把它暗面递给一名还没看过这张牌的玩家，并重新宣称（可以和上一个宣称相同，也可以不同）。
- 当其他所有玩家都已经看过这张牌时，最后拿到牌的人必须判断，不能再转手。
- 收下这张惩罚牌的玩家开始下一回合。

# 失败与名次
- 任何人面前同一种害虫达到 4 张，立即输掉游戏，游戏结束。
- 选项“无牌即输”开启时（默认）：轮到某人开始新回合但他手里已经没有牌了，他也输掉。关闭时跳过没有手牌的玩家；若所有人都没有手牌，面前牌最多的人输。
- 输家排在最后一名；其他人按选项决定：并列第一，或按面前公开牌的数量从少到多排名。

# 信息
- 一张牌的真面目只有递出它的人和偷看过它的人知道；判断后会对所有人翻开。
- 每个人的手牌数量、面前公开的害虫、以及本轮的宣称链对所有人可见。

# 电脑玩家
电脑只根据自己的手牌、场上公开的牌、各玩家过往宣称的真假记录来判断（不会偷看自己没看过的牌）。难度越高，越会把对手逼向第 4 张同种害虫，也越会利用“这种害虫已经几乎出完”的信息来识破谎言。
''';

class Cockroach extends GameEngine with BangLog {
  Cockroach(super.setup);

  late List<List<int>> hands = [for (var i = 0; i < players; i++) <int>[]];
  late List<List<int>> faceUp = [for (var i = 0; i < players; i++) List.filled(8, 0)];

  /// pass / respond / repass / over
  String phase = 'pass';
  int turn = 0;
  int card = -1;
  int from = -1;
  int holder = -1;
  int claim = -1;
  Set<int> seen = {};
  List<Map<String, dynamic>> chain = [];
  Map<String, dynamic>? lastResult;
  List<int> losers = [];

  /// Public record of each seat's revealed claims: [truths, lies].
  late List<List<int>> claimStats = [for (var i = 0; i < players; i++) [0, 0]];

  bool get noCardsLose => setup.opt<bool>('nocards', true);
  bool get rankByCount => setup.opt<String>('rank', 'count') == 'count';

  @override
  void start() {
    final deck = [for (var c = 0; c < 8; c++) for (var k = 0; k < 8; k++) c]..shuffle(rng);
    for (var i = 0; i < deck.length; i++) {
      hands[i % players].add(deck[i]);
    }
    for (final h in hands) {
      h.sort();
    }
    turn = rng.nextInt(players);
    say('蟑螂扑克开始！${name(turn)} 先出牌');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => switch (phase) {
        'pass' => [turn],
        'respond' || 'repass' => [holder],
        _ => const [],
      };

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (!rankByCount) return rankWinners(players, [for (var i = 0; i < players; i++) if (!losers.contains(i)) i]);
    return rankByScore([for (var i = 0; i < players; i++) faceTotal(i) + (losers.contains(i) ? 1000 : 0)], lowWins: true);
  }

  int faceTotal(int s) => faceUp[s].fold(0, (a, b) => a + b);

  /// Seats [holder] may still pass the current card to.
  List<int> get eligible => [for (var i = 0; i < players; i++) if (!seen.contains(i) && i != holder) i];

  void _end(List<int> l, String why) {
    losers = l;
    phase = 'over';
    say('游戏结束：${l.map(name).join('、')} $why');
  }

  void _beginTurn(int s) {
    card = -1;
    from = -1;
    holder = -1;
    claim = -1;
    seen = {};
    chain = [];
    if (hands[s].isEmpty) {
      if (noCardsLose) {
        _end([s], '轮到出牌却没有手牌，输了');
        return;
      }
      var t = s;
      for (var k = 0; k < players; k++) {
        t = (t + 1) % players;
        if (hands[t].isNotEmpty) break;
      }
      if (hands[t].isEmpty) {
        final mx = [for (var i = 0; i < players; i++) faceTotal(i)].reduce(max);
        _end([for (var i = 0; i < players; i++) if (faceTotal(i) == mx) i], '面前的害虫最多，输了');
        return;
      }
      say('${name(s)} 没有手牌，由 ${name(t)} 出牌');
      s = t;
    }
    turn = s;
    phase = 'pass';
  }

  void _give(int target, int c, int k) {
    if (target < 0 || target >= players || target == holder || seen.contains(target)) {
      throw GameError('只能递给还没看过这张牌的其他玩家');
    }
    if (k < 0 || k >= 8) throw GameError('请选择要宣称的害虫');
    from = holder;
    holder = target;
    claim = k;
    card = c;
    chain.add({'from': from, 'to': target, 'claim': k});
    phase = 'respond';
    say('${name(from)} 把一张牌递给 ${name(target)}：“这是${_cn(k)}”');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (!waitingFor.contains(seat)) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    switch (phase) {
      case 'pass':
        if (type != 'pass') throw GameError('请选择一张牌递出');
        final c = asInt(a['card']);
        if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
        final t = asInt(a['to']);
        holder = seat;
        seen = {seat};
        try {
          _give(t, c, asInt(a['claim']));
        } catch (_) {
          holder = -1;
          seen = {};
          rethrow;
        }
        hands[seat].remove(c);
      case 'respond':
        if (type == 'peek') {
          if (eligible.isEmpty) throw GameError('所有人都看过这张牌了，你必须判断真假');
          seen.add(seat);
          phase = 'repass';
          say('${name(seat)} 偷看了这张牌，准备转手');
        } else if (type == 'call') {
          _call(seat, asBool(a['truth']));
        } else {
          throw GameError('请判断真假或偷看转手');
        }
      case 'repass':
        if (type != 'pass') throw GameError('请选择转给谁并宣称');
        _give(asInt(a['to']), card, asInt(a['claim']));
      default:
        throw GameError('请稍候');
    }
  }

  void _call(int seat, bool saysTrue) {
    final isTrue = card == claim;
    final right = saysTrue == isTrue;
    final taker = right ? from : seat;
    claimStats[from][isTrue ? 0 : 1]++;
    faceUp[taker][card]++;
    say('${name(seat)} 判断“${saysTrue ? '真' : '假'}”，翻开是${_cn(card)}，${right ? '猜对了' : '猜错了'}！${name(taker)} 收下${_cn(card)}');
    lastResult = {'caller': seat, 'passer': from, 'claim': claim, 'card': card, 'said': saysTrue, 'right': right, 'taker': taker};
    if (faceUp[taker][card] >= 4) {
      _end([taker], '面前已有 4 张${_cn(card)}，输了');
      return;
    }
    _beginTurn(taker);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'players': players,
      'phase': phase,
      'turn': turn,
      'from': from,
      'holder': holder,
      'claim': claim,
      'card': (me && seen.contains(seat)) || isOver ? card : -1,
      'seen': seen.toList(),
      'eligible': phase == 'respond' || phase == 'repass' ? eligible : <int>[],
      'chain': chain,
      'hand': me ? hands[seat] : <int>[],
      'handCounts': [for (final h in hands) h.length],
      'faceUp': faceUp,
      'stats': claimStats,
      'lastResult': lastResult,
      'losers': losers,
      'placings': placings,
      'hands': isOver ? hands : null,
      'waiting': waitingFor,
      'log': recentLogs(12),
    };
  }

  // ---------------------------------------------------------------- bot

  /// Probability, from [me]'s knowledge, that the current card is [claim].
  double _probTrue(int me) {
    var known = hands[me].where((c) => c == claim).length;
    for (final f in faceUp) {
      known += f[claim];
    }
    final left = 8 - known;
    if (left <= 0) return 0;
    // the passer's public record of honesty (with a neutral prior)
    final st = claimStats[from];
    final honesty = (st[0] + 2) / (st[0] + st[1] + 4);
    // the fewer copies still unaccounted for, the less likely a truthful claim was possible
    final pt = honesty * min(1.0, left / 4.0);
    final pf = 1 - honesty;
    return pt / max(1e-9, pt + pf);
  }

  /// Pick a victim and a claim for passing [c] (or any card when c == null).
  Map<String, dynamic> _choosePass(int me, int? fixed) {
    final lvl = botLevel;
    final targets = fixed == null ? [for (var i = 0; i < players; i++) if (i != me) i] : eligible;
    final myHand = hands[me];
    if (lvl == 0) {
      final c = fixed ?? myHand[rng.nextInt(myHand.length)];
      final t = targets[rng.nextInt(targets.length)];
      final k = rng.nextBool() ? c : rng.nextInt(8);
      return {'type': 'pass', if (fixed == null) 'card': c, 'to': t, 'claim': k};
    }
    // score each (card, target): push targets towards a 4th copy
    var best = -1e9;
    var bc = -1, bt = -1;
    final cards = fixed != null ? [fixed] : myHand.toSet().toList();
    for (final c in cards) {
      for (final t in targets) {
        final n = faceUp[t][c];
        var sc = n * n * 3.0 + faceTotal(t) * 0.4 + rng.nextDouble() * 2;
        if (fixed == null) sc += myHand.where((x) => x == c).length * 0.8; // dump duplicates
        if (lvl == 2 && n >= 3) sc += 10;
        if (sc > best) {
          best = sc;
          bc = c;
          bt = t;
        }
      }
    }
    final truth = rng.nextDouble() < (lvl == 2 ? 0.4 : 0.5);
    var k = bc;
    if (!truth) {
      // lie with a creature the victim fears (has many of) or random
      final fear = List.generate(8, (i) => i)..remove(bc);
      fear.sort((a, b) => faceUp[bt][b].compareTo(faceUp[bt][a]));
      k = rng.nextDouble() < 0.5 ? fear.first : fear[rng.nextInt(fear.length)];
    }
    return {'type': 'pass', if (fixed == null) 'card': bc, 'to': bt, 'claim': k};
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (!waitingFor.contains(seat)) return null;
    switch (phase) {
      case 'pass':
        return _choosePass(seat, null);
      case 'repass':
        return _choosePass(seat, card);
      case 'respond':
        final canPeek = eligible.isNotEmpty;
        if (botLevel == 0) {
          if (canPeek && rng.nextDouble() < 0.3) return {'type': 'peek'};
          return {'type': 'call', 'truth': rng.nextBool()};
        }
        final p = _probTrue(seat);
        final danger = faceUp[seat][claim] >= 3 || faceUp[seat].any((x) => x >= 3);
        final unsure = (p - 0.5).abs() < (botLevel == 2 ? 0.2 : 0.12);
        if (canPeek && (danger ? rng.nextDouble() < 0.75 : (unsure && rng.nextDouble() < 0.45))) return {'type': 'peek'};
        final truth = botLevel == 2 ? p >= 0.5 : rng.nextDouble() < p;
        return {'type': 'call', 'truth': truth};
    }
    return null;
  }
}
