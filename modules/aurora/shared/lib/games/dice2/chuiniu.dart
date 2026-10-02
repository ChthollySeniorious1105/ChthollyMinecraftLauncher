import '../../src/engine.dart';
import 'util.dart';

/// Face order for bids: 2 < 3 < 4 < 5 < 6 < 1.
int cnFaceRank(int f) => f == 1 ? 7 : f;

/// Count dice matching a bid. 1s are wild unless [zhai] or face == 1.
int cnCount(List<List<int>> allDice, int face, bool zhai) {
  var n = 0;
  for (final d in allDice) {
    for (final x in d) {
      if (x == face || (!zhai && face != 1 && x == 1)) n++;
    }
  }
  return n;
}

/// Is new bid (q, f, z) a legal raise over previous (pq, pf, pz)? prevQty 0 = opening.
/// Bidding on 1s is always 斋. 斋→飞 needs at least double the quantity.
/// Same mode: more dice, or same dice and higher face. 飞→斋: same quantity or more.
String? cnBidError(int q, int f, bool z, int pq, int pf, bool pz, {required int minFly, required int minZhai, required int total}) {
  if (f < 1 || f > 6) return '点数无效';
  if (f == 1) z = true;
  if (q < 1 || q > total) return '数量无效（场上共 $total 颗骰子）';
  if (pq == 0) {
    if (z && q < minZhai) return '斋 至少叫 $minZhai 个';
    if (!z && q < minFly) return '至少叫 $minFly 个';
    return null;
  }
  if (pz && !z) return q >= pq * 2 ? null : '从斋改回飞，数量至少翻倍（${pq * 2} 个）';
  if (z && !pz) return q >= pq ? null : '改叫斋 数量不能少于 $pq';
  if (q > pq) return null;
  if (q == pq && cnFaceRank(f) > cnFaceRank(pf)) return null;
  return '必须比上家叫得大';
}

class ChuiNiu extends GameEngine {
  ChuiNiu(super.setup);

  late final int maxLives = setup.opt<int>('lives', 3);
  late final bool allowPi = setup.opt<bool>('pi', true);
  late final D2Log log = D2Log(() => host);

  String phase = 'bid'; // bid / pi / reveal / over
  int round = 0;
  int turn = 0;
  List<int> lives = [];
  List<List<int>> dice = [];
  int bidQty = 0, bidFace = 0, bidder = -1;
  bool zhai = false;
  int stake = 1;
  int challenger = -1;
  List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? reveal;
  int winner = -1;

  /// Seats knocked out (0 lives or 认输), in order.
  final List<int> outOrder = [];

  List<int> get alive => [for (var s = 0; s < players; s++) if (lives[s] > 0) s];
  int get totalDice => alive.length * 5;
  int get minFly => alive.length + 1;
  int get minZhai => alive.length;

  @override
  void start() {
    lives = List.filled(players, maxLives);
    _newRound(rng.nextInt(players));
  }

  int _nextAlive(int s) {
    for (var i = 1; i <= players; i++) {
      final t = (s + i) % players;
      if (lives[t] > 0) return t;
    }
    return s;
  }

  void _newRound(int starter) {
    round++;
    phase = 'bid';
    dice = [for (var s = 0; s < players; s++) lives[s] > 0 ? [for (var i = 0; i < 5; i++) d2Roll(rng)] : <int>[]];
    bidQty = 0;
    bidFace = 0;
    bidder = -1;
    zhai = false;
    stake = 1;
    challenger = -1;
    history = [];
    reveal = null;
    turn = lives[starter] > 0 ? starter : _nextAlive(starter);
    log.add('第 $round 轮，摇骰！${name(turn)} 先叫', chat: false);
  }

  void _resolve() {
    final count = cnCount(dice, bidFace, zhai);
    final truth = count >= bidQty;
    final loser = truth ? challenger : bidder;
    lives[loser] = (lives[loser] - stake).clamp(0, maxLives);
    if (lives[loser] <= 0 && !outOrder.contains(loser)) outOrder.add(loser);
    final bidText = '$bidQty 个 $bidFace${zhai ? '（斋）' : ''}';
    final why = '开！场上共 $count 个 $bidFace${zhai || bidFace == 1 ? '' : '（含 1）'}，叫 $bidText ${truth ? '成立' : '不成立'}，'
        '${name(loser)} 输${stake > 1 ? ' ×$stake' : ''}${lives[loser] <= 0 ? '，出局！' : '（剩 ${lives[loser]} 条命）'}';
    log.add(why);
    reveal = {
      'dice': [for (final d in dice) List.of(d)],
      'count': count,
      'truth': truth,
      'loser': loser,
      'stake': stake,
      'why': why,
    };
    phase = 'reveal';
    host.schedule(4000, () {
      if (phase == 'over') return;
      if (alive.length <= 1) {
        phase = 'over';
        winner = alive.isEmpty ? -1 : alive.first;
        log.add('游戏结束，${winner >= 0 ? name(winner) : '无人'} 获胜！');
      } else {
        _newRound(loser);
      }
    });
  }

  @override
  List<int>? get placings => isOver ? d2Placings(lives, outOrder, winner: winner) : null;

  @override
  bool get canResign => !isOver;

  /// 认输 = 立即出局；当前这一轮作废，由下一位存活玩家重新摇骰开叫。
  @override
  void resign(int seat) {
    if (isOver) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || lives[seat] <= 0) throw GameError('你已出局');
    lives[seat] = 0;
    outOrder.add(seat);
    log.add('${name(seat)} 认输');
    if (phase == 'reveal') return; // the scheduled callback continues the game
    if (alive.length <= 1) {
      phase = 'over';
      winner = alive.isEmpty ? -1 : alive.first;
      log.add('游戏结束，${winner >= 0 ? name(winner) : '无人'} 获胜！');
      return;
    }
    _newRound(_nextAlive(seat));
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    final type = asStr(a['type']);
    if (phase == 'pi') {
      if (seat != bidder) throw GameError('等待 ${name(bidder)} 回应劈');
      if (type == 'accept') {
        log.add('${name(seat)} 接受劈，开！');
      } else if (type == 'repi') {
        stake *= 2;
        log.add('${name(seat)} 反劈！赌注 ×$stake');
      } else {
        throw GameError('请选择接受或反劈');
      }
      _resolve();
      return;
    }
    if (phase != 'bid') throw GameError('请稍候');
    if (seat != turn) throw GameError('还没轮到你');
    switch (type) {
      case 'bid':
        final q = asInt(a['qty']);
        final f = asInt(a['face']);
        final z = asBool(a['zhai']) || f == 1;
        final err = cnBidError(q, f, z, bidQty, bidFace, zhai, minFly: minFly, minZhai: minZhai, total: totalDice);
        if (err != null) throw GameError(err);
        bidQty = q;
        bidFace = f;
        zhai = z;
        bidder = seat;
        history.add({'seat': seat, 'qty': q, 'face': f, 'zhai': z});
        if (history.length > 30) history.removeAt(0);
        log.add('${name(seat)} 叫 $q 个 $f${z ? '（斋）' : ''}', chat: false);
        turn = _nextAlive(seat);
      case 'open':
        if (bidder < 0) throw GameError('还没有人叫，不能开');
        challenger = seat;
        stake = 1;
        log.add('${name(seat)} 开 ${name(bidder)}！', chat: false);
        _resolve();
      case 'pi':
        if (!allowPi) throw GameError('本局未开启劈');
        if (bidder < 0) throw GameError('还没有人叫，不能劈');
        challenger = seat;
        stake = 2;
        phase = 'pi';
        log.add('${name(seat)} 劈 ${name(bidder)}！赌注 ×2');
      default:
        throw GameError('未知操作');
    }
  }

  @override
  List<int> get waitingFor => switch (phase) { 'bid' => [turn], 'pi' => [bidder], _ => <int>[] };

  @override
  bool get isOver => phase == 'over';

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': phase,
        'round': round,
        'turn': turn,
        'lives': lives,
        'maxLives': maxLives,
        'allowPi': allowPi,
        'dice': seat >= 0 && seat < players ? dice[seat] : <int>[],
        'diceCounts': [for (final d in dice) d.length],
        'bidQty': bidQty,
        'bidFace': bidFace,
        'bidder': bidder,
        'zhai': zhai,
        'stake': stake,
        'challenger': challenger,
        'history': history.length > 8 ? history.sublist(history.length - 8) : history,
        'totalDice': totalDice,
        'minFly': minFly,
        'minZhai': minZhai,
        'reveal': reveal,
        'winner': winner,
        'log': log.tail(),
      };

  // ---------------- bot: uses only its own dice ----------------
  /// P(bid is true) given only [own] dice and [unknown] hidden dice.
  static double truthProb(List<int> own, int unknown, int q, int f, bool z) {
    final mine = cnCount([own], f, z);
    final p = (z || f == 1) ? 1 / 6 : 1 / 3;
    return d2BinomAtLeast(unknown, p, q - mine);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final own = dice[seat];
    final unknown = totalDice - own.length;
    if (phase == 'pi') {
      if (seat != bidder) return null;
      final pr = truthProb(own, unknown, bidQty, bidFace, zhai);
      if (botLevel <= 0) return {'type': rng.nextInt(4) == 0 ? 'repi' : 'accept'};
      return {'type': pr > (botLevel >= 2 ? 0.6 : 0.7) && stake < 4 ? 'repi' : 'accept'};
    }
    if (phase != 'bid' || seat != turn) return null;
    if (botLevel <= 0) return _botEasy(seat, own, unknown);
    if (botLevel >= 2) return _botHard(seat, own, unknown);
    double cur = 1;
    if (bidder >= 0) {
      cur = truthProb(own, unknown, bidQty, bidFace, zhai);
      // the bidder probably holds some of that face: soften a bit
      cur = (cur + 0.15).clamp(0.0, 1.0);
    }
    // best raise
    Map<String, dynamic>? best;
    var bestP = -1.0;
    for (var z = 0; z < 2; z++) {
      for (var f = 1; f <= 6; f++) {
        final zz = z == 1 || f == 1;
        if (z == 0 && f == 1) continue;
        for (var q = 1; q <= totalDice; q++) {
          if (cnBidError(q, f, zz, bidQty, bidFace, zhai, minFly: minFly, minZhai: minZhai, total: totalDice) != null) continue;
          final pr = truthProb(own, unknown, q, f, zz) + rng.nextDouble() * 0.04;
          if (pr > bestP) {
            bestP = pr;
            best = {'type': 'bid', 'qty': q, 'face': f, 'zhai': zz};
          }
          break; // smallest legal qty for this face/mode is the safest
        }
      }
    }
    if (bidder >= 0 && (best == null || cur < 0.3 || (bestP < 0.35 && cur < 0.55))) {
      if (allowPi && cur < 0.08) return {'type': 'pi'};
      return {'type': 'open'};
    }
    return best ?? {'type': 'open'};
  }

  /// All legal raises (smallest quantity per face/mode first).
  List<Map<String, dynamic>> _raises({int extra = 0}) {
    final out = <Map<String, dynamic>>[];
    for (var z = 0; z < 2; z++) {
      for (var f = 1; f <= 6; f++) {
        final zz = z == 1 || f == 1;
        if (z == 0 && f == 1) continue;
        var found = 0;
        for (var q = 1; q <= totalDice && found <= extra; q++) {
          if (cnBidError(q, f, zz, bidQty, bidFace, zhai, minFly: minFly, minZhai: minZhai, total: totalDice) != null) continue;
          out.add({'type': 'bid', 'qty': q, 'face': f, 'zhai': zz});
          found++;
        }
      }
    }
    return out;
  }

  /// 简单: often a random legal raise, opens only on very unlikely bids.
  Map<String, dynamic> _botEasy(int seat, List<int> own, int unknown) {
    final raises = _raises();
    if (bidder >= 0) {
      final cur = truthProb(own, unknown, bidQty, bidFace, zhai);
      if (raises.isEmpty || cur < 0.15 || rng.nextInt(6) == 0) return {'type': 'open'};
    }
    if (raises.isEmpty) return {'type': 'open'};
    if (rng.nextInt(2) == 0) return raises[rng.nextInt(raises.length)];
    raises.sort((a, b) => truthProb(own, unknown, b['qty'] as int, b['face'] as int, b['zhai'] as bool)
        .compareTo(truthProb(own, unknown, a['qty'] as int, a['face'] as int, a['zhai'] as bool)));
    return raises.first;
  }

  /// 困难: reads the bidding history (a player who bid a face probably holds
  /// some of it), weighs open vs. raise vs. 劈 by estimated probabilities and
  /// occasionally bluffs with a face it holds.
  Map<String, dynamic> _botHard(int seat, List<int> own, int unknown) {
    // estimated extra dice of each face "promised" by opponents' bids
    final hint = List.filled(7, 0.0);
    for (final h in history) {
      final s = h['seat'] as int;
      if (s == seat) continue;
      hint[h['face'] as int] += 0.6;
    }
    double prob(int q, int f, bool z) {
      final mine = cnCount([own], f, z);
      final p = (z || f == 1) ? 1 / 6 : 1 / 3;
      final bonus = hint[f].clamp(0.0, 2.0).floor();
      return d2BinomAtLeast(unknown, p, q - mine - bonus);
    }

    final cur = bidder >= 0 ? prob(bidQty, bidFace, zhai) : 1.0;
    Map<String, dynamic>? best;
    var bestP = -1.0;
    for (final r in _raises(extra: 1)) {
      final q = r['qty'] as int, f = r['face'] as int, z = r['zhai'] as bool;
      var pr = prob(q, f, z) + rng.nextDouble() * 0.03;
      // slight preference for faces we hold (keeps opponents honest)
      if (cnCount([own], f, z) >= 2) pr += 0.03;
      if (pr > bestP) {
        bestP = pr;
        best = r;
      }
    }
    if (bidder >= 0) {
      // expected lives lost: open loses with prob cur; raise loses roughly with (1 - bestP)
      // open wins when the bid is false (1 - cur); a raise survives with ~bestP
      if (best == null || cur < 0.25 || (1 - cur) > bestP) {
        if (allowPi && cur < 0.12) return {'type': 'pi'};
        return {'type': 'open'};
      }
    }
    return best ?? {'type': 'open'};
  }
}
