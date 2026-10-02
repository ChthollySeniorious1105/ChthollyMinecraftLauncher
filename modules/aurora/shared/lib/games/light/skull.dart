import 'dart:math';

import '../../src/engine.dart';
import 'common.dart';

const skullRules = '''
# 概述
骷髅与玫瑰（Skull）是 3~6 人的虚张声势游戏。每人有 4 张圆牌：3 朵玫瑰和 1 个骷髅。赢得 2 次挑战，或成为最后一个还有圆牌的玩家即获胜。

# 一轮的流程
- 放牌：每人先面朝下放 1 张圆牌到自己的垫子上（同时进行）。
- 然后从起始玩家开始轮流：要么再放 1 张圆牌到自己的垫子上（叠在上面），要么发起挑战（报一个数字）。
- 如果某人手里已经没有圆牌，轮到他时只能发起挑战/加注。
- 竞价：发起挑战时报一个数字（至少 1，最多为桌上所有圆牌总数），表示“我能翻开这么多张而不翻到骷髅”。之后轮流加注或放弃（放弃者本轮不能再加注）。有人报到桌上圆牌总数，或其他人都放弃时，出价最高者成为挑战者。

# 翻牌
- 挑战者必须先把自己垫子上的圆牌从上到下全部翻开，然后再从其他玩家的垫子上逐张翻开（每次选一名玩家，翻他最上面的一张），直到翻够所报的数目。
- 全部是玫瑰：挑战成功，获得 1 分（翻转垫子）。获得第 2 分者立即获胜。
- 翻到骷髅：挑战失败，挑战者失去 1 张圆牌（面朝下丢弃，其他人看不到失去的是什么）。翻到别人的骷髅时，由系统随机抽走一张（代表骷髅主人盲抽）；翻到自己的骷髅时，由挑战者自己选择丢弃玫瑰还是骷髅。
- 失去全部圆牌的玩家出局。

# 下一轮
- 挑战者成为下一轮的起始玩家；若挑战者因失败出局，则由翻出骷髅的那名玩家起始。
- 每轮开始时所有人收回自己的圆牌。

# 胜负
- 先获得 2 次成功挑战的玩家获胜；或其他人都出局时最后的幸存者获胜。
- 名次：胜者第 1，其余按分数与剩余圆牌数排名。
''';

class Skull extends GameEngine with LightLog {
  Skull(super.setup);

  /// Discs still owned: rose count and whether the skull is still owned.
  late List<int> roses = List.filled(players, 3);
  late List<bool> hasSkull = List.filled(players, true);
  late List<int> points = List.filled(players, 0);

  /// Mats: bottom → top; true = skull.
  late List<List<bool>> mats = [for (var i = 0; i < players; i++) <bool>[]];

  /// How many discs from the top of each mat have been flipped.
  late List<int> flipped = List.filled(players, 0);
  late List<bool> folded = List.filled(players, false);

  /// Who bid or raised this round (public).
  late List<bool> raised = List.filled(players, false);
  late List<int> outOrder = List.filled(players, 0);
  int _outs = 0;

  String phase = 'place'; // place (initial, simultaneous) / turn / bid / flip / discard / roundEnd / over
  int turn = 0;
  int bid = 0;
  int bidder = -1;
  int challenger = -1;
  int flips = 0;
  int round = 0;
  int winner = -1;
  Map<String, dynamic>? result;
  Map<String, dynamic>? lastFlip;
  int skullOwner = -1;

  int discs(int s) => roses[s] + (hasSkull[s] ? 1 : 0);
  bool alive(int s) => discs(s) > 0;
  int inHandRoses(int s) => roses[s] - mats[s].where((x) => !x).length;
  bool skullInHand(int s) => hasSkull[s] && !mats[s].contains(true);
  int inHand(int s) => inHandRoses(s) + (skullInHand(s) ? 1 : 0);
  int get onTable => mats.fold(0, (a, m) => a + m.length);
  List<int> get aliveSeats => [for (var i = 0; i < players; i++) if (alive(i)) i];

  @override
  void start() {
    say('骷髅与玫瑰开始！赢得 2 次挑战者获胜');
    _newRound(rng.nextInt(players));
  }

  void _newRound(int first) {
    round++;
    for (var i = 0; i < players; i++) {
      mats[i] = [];
      flipped[i] = 0;
      folded[i] = false;
      raised[i] = false;
    }
    bid = 0;
    bidder = -1;
    challenger = -1;
    flips = 0;
    result = null;
    lastFlip = null;
    var s = first % players;
    while (!alive(s)) {
      s = (s + 1) % players;
    }
    turn = s;
    phase = 'place';
    say('—— 第 $round 轮：每人先放一张圆牌，${name(turn)} 起始 ——');
  }

  int _next(int s, {bool skipFolded = false}) {
    var n = (s + 1) % players;
    while (!alive(n) || (skipFolded && folded[n])) {
      n = (n + 1) % players;
    }
    return n;
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => switch (phase) {
        'place' => [for (final s in aliveSeats) if (mats[s].isEmpty) s],
        'turn' || 'bid' => [turn],
        'flip' || 'discard' => [challenger],
        _ => const [],
      };

  @override
  List<int>? get placings {
    if (!isOver) return null;
    return rankByScore([
      for (var i = 0; i < players; i++)
        i == winner ? 10000 : (outOrder[i] > 0 ? outOrder[i] : 100 + points[i] * 10 + discs(i)),
    ]);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat >= players || !alive(seat)) throw GameError('当前不能认输');
    say('${name(seat)} 认输');
    roses[seat] = 0;
    hasSkull[seat] = false;
    mats[seat] = [];
    outOrder[seat] = ++_outs;
    if (_checkLastStanding()) return;
    // restart the round cleanly
    _newRound(seat == turn || seat == challenger || seat == bidder ? _next(seat) : turn);
  }

  bool _checkLastStanding() {
    final a = aliveSeats;
    if (a.length == 1) {
      winner = a.first;
      phase = 'over';
      say('游戏结束！${name(winner)} 是最后的幸存者');
      return true;
    }
    return false;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players || !alive(seat)) throw GameError('你已经出局了');
    final type = asStr(a['type']);
    switch (phase) {
      case 'place':
        if (mats[seat].isNotEmpty) throw GameError('你已经放好了第一张，等待其他人');
        if (type != 'place') throw GameError('请先放一张圆牌');
        _place(seat, asBool(a['skull']));
        if (aliveSeats.every((s) => mats[s].isNotEmpty)) {
          phase = 'turn';
          say('所有人已放好第一张，${name(turn)} 行动');
        }
      case 'turn':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'place') {
          if (inHand(seat) <= 0) throw GameError('你手里没有圆牌了，只能发起挑战');
          _place(seat, asBool(a['skull']));
          say('${name(seat)} 又放了一张圆牌');
          turn = _next(seat);
        } else if (type == 'bid') {
          _bid(seat, asInt(a['n']));
        } else {
          throw GameError('请放牌或发起挑战');
        }
      case 'bid':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'bid') {
          _bid(seat, asInt(a['n']));
        } else if (type == 'fold') {
          folded[seat] = true;
          say('${name(seat)} 放弃');
          final left = [for (final s in aliveSeats) if (!folded[s]) s];
          if (left.length == 1) {
            _startFlip(left.first);
          } else {
            turn = _next(seat, skipFolded: true);
          }
        } else {
          throw GameError('请加注或放弃');
        }
      case 'flip':
        if (seat != challenger) throw GameError('等待挑战者翻牌');
        if (type != 'flip') throw GameError('请选择要翻的垫子');
        final t = asInt(a['target']);
        if (flipped[challenger] < mats[challenger].length) throw GameError('必须先翻完自己的圆牌');
        if (t < 0 || t >= players || t == challenger || flipped[t] >= mats[t].length) throw GameError('这个垫子没有可翻的圆牌');
        _flipOne(t);
      case 'discard':
        if (seat != challenger) throw GameError('等待挑战者丢弃圆牌');
        if (type != 'discard') throw GameError('请选择丢弃玫瑰或骷髅');
        final sk = asBool(a['skull']);
        if (sk && !hasSkull[seat]) throw GameError('你没有骷髅');
        if (!sk && roses[seat] <= 0) throw GameError('你没有玫瑰');
        _lose(sk);
      default:
        throw GameError('请稍候');
    }
  }

  void _place(int s, bool skull) {
    if (skull) {
      if (!skullInHand(s)) throw GameError('你手里没有骷髅');
    } else {
      if (inHandRoses(s) <= 0) throw GameError('你手里没有玫瑰了');
    }
    mats[s].add(skull);
  }

  void _bid(int seat, int n) {
    final total = onTable;
    if (n <= bid || n < 1) throw GameError('出价必须大于当前的 $bid');
    if (n > total) throw GameError('出价不能超过桌上的圆牌数 $total');
    bid = n;
    bidder = seat;
    raised[seat] = true;
    if (phase == 'turn') {
      say('${name(seat)} 发起挑战：能翻开 $n 张玫瑰');
      phase = 'bid';
    } else {
      say('${name(seat)} 加注到 $n');
    }
    if (n == total) {
      _startFlip(seat);
      return;
    }
    turn = _next(seat, skipFolded: true);
    if (turn == seat) _startFlip(seat);
  }

  void _startFlip(int s) {
    challenger = s;
    phase = 'flip';
    flips = 0;
    say('${name(s)} 成为挑战者，需要翻开 $bid 张玫瑰');
    // own mat is always flipped first, automatically
    while (flipped[s] < mats[s].length && flips < bid) {
      if (_flipOne(s)) return;
    }
  }

  /// Flip the top unflipped disc of [t]. Returns true when the challenge ended.
  bool _flipOne(int t) {
    final m = mats[t];
    final idx = m.length - 1 - flipped[t];
    final skull = m[idx];
    flipped[t]++;
    flips++;
    lastFlip = {'seat': t, 'skull': skull};
    if (skull) {
      say('${name(challenger)} 翻开 ${name(t)} 的圆牌 —— 骷髅！');
      _fail(t);
      return true;
    }
    if (t != challenger) say('${name(challenger)} 翻开 ${name(t)} 的圆牌 —— 玫瑰（$flips/$bid）');
    if (flips >= bid) {
      _success();
      return true;
    }
    return false;
  }

  void _success() {
    final c = challenger;
    points[c]++;
    result = {'type': 'success', 'seat': c, 'bid': bid};
    say('${name(c)} 挑战成功！（${points[c]}/2）');
    if (points[c] >= 2) {
      winner = c;
      phase = 'over';
      say('游戏结束！${name(c)} 第二次挑战成功，获胜');
      return;
    }
    _roundEnd(c);
  }

  void _fail(int owner) {
    final c = challenger;
    skullOwner = owner;
    if (owner == c && roses[c] > 0 && hasSkull[c]) {
      phase = 'discard';
      say('${name(c)} 翻到了自己的骷髅，需要自己选择丢弃一张圆牌');
      return;
    }
    // another player's skull: its owner draws one of the challenger's discs blindly
    final pool = [for (var k = 0; k < roses[c]; k++) false, if (hasSkull[c]) true];
    _lose(pool[rng.nextInt(pool.length)]);
  }

  void _lose(bool lost) {
    final c = challenger;
    final owner = skullOwner;
    if (lost) {
      hasSkull[c] = false;
    } else {
      roses[c]--;
    }
    result = {'type': 'fail', 'seat': c, 'owner': owner, 'bid': bid};
    say('${name(c)} 挑战失败，失去 1 张圆牌（剩 ${discs(c)} 张）');
    var next = c;
    if (!alive(c)) {
      outOrder[c] = ++_outs;
      say('${name(c)} 失去全部圆牌，出局');
      if (_checkLastStanding()) return;
      next = owner == c ? _next(c) : owner;
    }
    _roundEnd(next, lostSkull: lost);
  }


  void _roundEnd(int next, {bool? lostSkull}) {
    phase = 'roundEnd';
    if (lostSkull != null) result!['lostSkullPrivate'] = lostSkull;
    host.schedule(3500, () {
      if (phase == 'roundEnd') _newRound(next);
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final pub = result == null ? null : (Map<String, dynamic>.from(result!)..remove('lostSkullPrivate'));
    if (pub != null && me && result!['seat'] == seat && result!.containsKey('lostSkullPrivate')) {
      pub['lostSkull'] = result!['lostSkullPrivate'];
    }
    return {
      'players': players,
      'phase': phase,
      'round': round,
      'turn': turn,
      'bid': bid,
      'bidder': bidder,
      'challenger': challenger,
      'flips': flips,
      'onTable': onTable,
      'points': points,
      'discs': [for (var i = 0; i < players; i++) discs(i)],
      'alive': [for (var i = 0; i < players; i++) alive(i)],
      'folded': folded,
      'raised': raised,
      'matCounts': [for (final m in mats) m.length],
      // flipped discs are public: list from top, only the flipped part
      'matFlipped': [
        for (var i = 0; i < players; i++) [for (var k = 0; k < flipped[i]; k++) mats[i][mats[i].length - 1 - k]]
      ],
      'myMat': me ? mats[seat] : <bool>[],
      'myRoses': me ? roses[seat] : 0,
      'mySkull': me ? hasSkull[seat] : false,
      'handRoses': me ? inHandRoses(seat) : 0,
      'handSkull': me ? skullInHand(seat) : false,
      'handCounts': [for (var i = 0; i < players; i++) inHand(i)],
      'result': pub,
      'lastFlip': lastFlip,
      'winner': winner,
      'log': recentLogs(),
    };
  }

  // ---------------------------------------------------------------- bot

  /// Estimated chance that [s]'s mat hides a skull (public information only).
  double _qSkull(int s) {
    if (raised[s]) return 0.18; // bid on their own roses most likely
    return mats[s].length >= 3 ? 0.55 : 0.45;
  }

  /// Chance that flipping [k] more discs of [s] (after [done] already flipped) shows only roses.
  double _safe(int s, int done, int k) {
    final m = mats[s].length;
    if (m == 0) return 1;
    final q = _qSkull(s);
    return (1 - q * (done + k) / m) / (1 - q * done / m);
  }

  /// Best probability of flipping [n] more foreign discs safely, and the first mat to flip.
  (double, int) _plan(int me, int n) {
    final extra = List.filled(players, 0);
    var p = 1.0;
    var first = -1;
    for (var i = 0; i < n; i++) {
      var best = -1;
      var bestR = -1.0;
      for (final s in aliveSeats) {
        if (s == me || flipped[s] + extra[s] >= mats[s].length) continue;
        final r = _safe(s, flipped[s] + extra[s], 1);
        if (r > bestR) {
          bestR = r;
          best = s;
        }
      }
      if (best < 0) return (0, first);
      first = first < 0 ? best : first;
      extra[best]++;
      p *= bestR;
    }
    return (p, first);
  }

  /// Largest number of foreign flips whose success chance is at least [limit].
  int _reach(int me, double limit) {
    var n = 0;
    final avail = [for (final s in aliveSeats) if (s != me) mats[s].length - flipped[s]].fold(0, (a, b) => a + b);
    while (n < avail && _plan(me, n + 1).$1 >= max(limit, 0.01)) {
      n++;
    }
    return n;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (!waitingFor.contains(seat)) return null;
    final lvl = botLevel;
    final myMat = mats[seat];
    final mySkullDown = myMat.contains(true);
    final limit = switch (lvl) { 0 => 0.3, 1 => 0.3, _ => 0.2 };
    // an opponent on match point makes us bolder
    final danger = [for (final s in aliveSeats) if (s != seat && points[s] >= 1) s].isNotEmpty;
    final lim = danger && lvl >= 1 ? limit - 0.12 : limit;
    switch (phase) {
      case 'place':
        final skullP = lvl == 0 ? 0.35 : 0.3;
        final useSkull = skullInHand(seat) && (inHandRoses(seat) == 0 || rng.nextDouble() < skullP);
        return {'type': 'place', 'skull': useSkull};
      case 'turn':
        final total = onTable;
        final own = myMat.length;
        if (mySkullDown) {
          // keep stacking so a challenger must dig; forced to bid only when empty-handed
          if (inHand(seat) > 0 && inHandRoses(seat) > 0) return {'type': 'place', 'skull': false};
          return {'type': 'bid', 'n': 1};
        }
        if (lvl == 0) {
          if (inHand(seat) > 0 && rng.nextDouble() < 0.6) {
            return {'type': 'place', 'skull': skullInHand(seat) && (inHandRoses(seat) == 0 || rng.nextBool())};
          }
          return {'type': 'bid', 'n': min(total, own + rng.nextInt(2))};
        }
        // roses only on our mat: claim early (a cheap bid everyone folds to is a free point),
        // occasionally lay a skull trap first
        if (inHand(seat) > 0 && skullInHand(seat) && rng.nextDouble() < (lvl >= 2 ? 0.2 : 0.15)) {
          return {'type': 'place', 'skull': true};
        }
        final reach = _reach(seat, lim + 0.05);
        return {'type': 'bid', 'n': (own + reach).clamp(1, total)};
      case 'bid':
        final total = onTable;
        final next = bid + 1;
        if (next > total) return {'type': 'fold'};
        if (mySkullDown) {
          // a small bluff raise keeps others guessing, but only while someone else is still in
          final others = [for (final s in aliveSeats) if (s != seat && !folded[s]) s].length;
          if (lvl >= 2 && others >= 2 && next <= 2 && rng.nextDouble() < 0.15) return {'type': 'bid', 'n': next};
          return {'type': 'fold'};
        }
        final need = next - myMat.length;
        final p = need <= 0 ? 1.0 : _plan(seat, need).$1;
        if (lvl == 0) return p >= 0.3 || rng.nextDouble() < 0.2 ? {'type': 'bid', 'n': next} : {'type': 'fold'};
        return p >= lim ? {'type': 'bid', 'n': next} : {'type': 'fold'};
      case 'discard':
        // keep the skull as a bluffing tool unless we're low on discs
        return {'type': 'discard', 'skull': lvl == 0 ? rng.nextBool() : discs(seat) <= 2};
      case 'flip':
        final cands = [for (final s in aliveSeats) if (s != seat && flipped[s] < mats[s].length) s];
        if (cands.isEmpty) return null;
        if (lvl == 0) return {'type': 'flip', 'target': cands[rng.nextInt(cands.length)]};
        final t = _plan(seat, bid - flips).$2;
        return {'type': 'flip', 'target': cands.contains(t) ? t : cands.first};
    }
    return null;
  }
}
