import '../../src/engine.dart';
import 'util.dart';

/// Score of a SET-ASIDE selection where every die must count.
/// Returns 0 if some die in [dice] doesn't score.
/// 1=100, 5=50, three of a kind = face×100 (1s = 1000), four = ×2, five = ×4, six = ×8,
/// straight 1-6 = 1500, three pairs (incl. four-of-a-kind + pair) = 750.
int farkleScore(List<int> dice) {
  if (dice.isEmpty) return 0;
  final c = d2Counts(dice);
  var best = 0;
  if (dice.length == 6) {
    if (c.sublist(1).every((x) => x == 1)) best = 1500;
    final nz = [for (var f = 1; f <= 6; f++) if (c[f] > 0) c[f]];
    if (nz.every((x) => x.isEven) && (nz.length == 3 || (nz.length == 2 && nz.contains(4)))) {
      if (best < 750) best = 750;
    }
  }
  var sum = 0;
  for (var f = 1; f <= 6; f++) {
    final n = c[f];
    if (n == 0) continue;
    if (n >= 3) {
      final base = f == 1 ? 1000 : f * 100;
      sum += base * (1 << (n - 3));
    } else if (f == 1) {
      sum += 100 * n;
    } else if (f == 5) {
      sum += 50 * n;
    } else {
      sum = -1;
      break;
    }
  }
  if (sum > best) best = sum;
  return best;
}

/// Best (score, indices) among all fully-scoring subsets of [roll].
(int, List<int>) farkleBest(List<int> roll) {
  var best = 0;
  var bestIdx = <int>[];
  for (var m = 1; m < (1 << roll.length); m++) {
    final idx = [for (var i = 0; i < roll.length; i++) if (m & (1 << i) != 0) i];
    final s = farkleScore([for (final i in idx) roll[i]]);
    if (s > best || (s == best && s > 0 && idx.length > bestIdx.length)) {
      best = s;
      bestIdx = idx;
    }
  }
  return (best, bestIdx);
}

bool farkleIsBust(List<int> roll) => farkleBest(roll).$1 == 0;

class Farkle extends GameEngine {
  Farkle(super.setup);

  late final int target = setup.opt<int>('target', 10000);
  late final D2Log log = D2Log(() => host);

  String phase = 'play'; // play / over
  int turn = 0;
  List<int> scores = [];
  int turnPoints = 0;
  List<int> roll = []; // dice available to set aside ([] = must roll)
  List<int> setAside = []; // dice set aside this turn (for display)
  List<int> lastFarkle = [];
  int rollCount = 0;
  String lastEvent = '';
  int finalTrigger = -1; // seat that reached target
  List<bool> finalDone = [];
  List<int> winners = [];

  /// Seats that resigned, in order.
  final List<int> resigned = [];

  int get _diceLeft => 6 - setAside.length % 6;

  @override
  void start() {
    scores = List.filled(players, 0);
    finalDone = List.filled(players, false);
    turn = rng.nextInt(players);
    log.add('${name(turn)} 先开始，目标 $target 分');
  }

  void _endTurn() {
    if (finalTrigger >= 0) finalDone[turn] = true;
    if (finalTrigger < 0 && scores[turn] >= target) {
      finalTrigger = turn;
      finalDone[turn] = true;
      log.add('${name(turn)} 达到 ${scores[turn]} 分！其他玩家各有最后一回合');
    }
    turnPoints = 0;
    roll = [];
    setAside = [];
    if (finalTrigger >= 0 && [for (var s = 0; s < players; s++) finalDone[s] || resigned.contains(s)].every((d) => d)) {
      _finish();
      return;
    }
    do {
      turn = (turn + 1) % players;
    } while (resigned.contains(turn));
  }

  void _finish() {
    phase = 'over';
    final alive = [for (var s = 0; s < players; s++) if (!resigned.contains(s)) s];
    if (alive.isEmpty) return;
    final best = alive.map((s) => scores[s]).reduce((a, b) => a > b ? a : b);
    winners = [for (final s in alive) if (scores[s] == best) s];
    log.add('游戏结束，${winners.map(name).join('、')} 以 $best 分获胜');
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || resigned.contains(seat)) throw GameError('你不在游戏中');
    resigned.add(seat);
    log.add('${name(seat)} 认输');
    final alive = [for (var s = 0; s < players; s++) if (!resigned.contains(s)) s];
    if (alive.length <= 1) {
      _finish();
      return;
    }
    if (turn == seat) {
      // forfeit this turn: nothing banked
      turnPoints = 0;
      roll = [];
      setAside = [];
      if (finalTrigger >= 0 && [for (var s = 0; s < players; s++) finalDone[s] || resigned.contains(s)].every((d) => d)) {
        _finish();
        return;
      }
      do {
        turn = (turn + 1) % players;
      } while (resigned.contains(turn));
    } else if (finalTrigger >= 0 && [for (var s = 0; s < players; s++) finalDone[s] || resigned.contains(s)].every((d) => d)) {
      _finish();
    }
  }

  @override
  List<int>? get placings => isOver ? d2Placings(scores, resigned, winner: winners.length == 1 ? winners.first : -1) : null;

  void _doRoll() {
    final n = setAside.length >= 6 ? 6 : 6 - setAside.length;
    if (setAside.length >= 6) setAside = [];
    roll = [for (var i = 0; i < n; i++) d2Roll(rng)];
    rollCount++;
    if (farkleIsBust(roll)) {
      lastFarkle = List.of(roll);
      lastEvent = '${name(turn)} 掷出 ${roll.join(' ')}，Farkle！本回合 $turnPoints 分作废';
      log.add(lastEvent);
      _endTurn();
    } else {
      lastFarkle = [];
      lastEvent = '${name(turn)} 掷出 ${roll.join(' ')}';
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'roll' && roll.isEmpty) {
      _doRoll();
      return;
    }
    if (type != 'keep') throw GameError(roll.isEmpty ? '请先掷骰' : '请选择要留下的计分骰');
    if (roll.isEmpty) throw GameError('请先掷骰');
    final idx = d2Indices(a['dice'], roll.length);
    if (idx.isEmpty) throw GameError('至少留下一颗计分骰');
    final kept = [for (final i in idx) roll[i]];
    final pts = farkleScore(kept);
    if (pts == 0) throw GameError('所选骰子中有不计分的骰子');
    final then = asStr(a['then'], 'roll');
    if (then != 'roll' && then != 'bank') throw GameError('未知操作');
    turnPoints += pts;
    setAside = [...setAside, ...kept];
    roll = [];
    final hot = setAside.length >= 6;
    if (then == 'bank') {
      scores[seat] += turnPoints;
      lastEvent = '${name(seat)} 留下 ${kept.join(' ')}（+$pts），存入 $turnPoints 分，总分 ${scores[seat]}';
      log.add(lastEvent);
      _endTurn();
    } else {
      lastEvent = '${name(seat)} 留下 ${kept.join(' ')}（+$pts）${hot ? '，满堂骰！六颗重掷' : ''}，继续掷';
      log.add(lastEvent, chat: hot);
      _doRoll();
    }
  }

  @override
  List<int> get waitingFor => phase == 'play' ? [turn] : [];

  @override
  bool get isOver => phase == 'over';

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': phase,
        'turn': turn,
        'target': target,
        'scores': scores,
        'turnPoints': turnPoints,
        'roll': roll,
        'setAside': setAside.length >= 6 && roll.isNotEmpty ? <int>[] : setAside,
        'lastFarkle': lastFarkle,
        'rollCount': rollCount,
        'lastEvent': lastEvent,
        'finalRound': finalTrigger >= 0,
        'finalTrigger': finalTrigger,
        'winners': winners,
        'resigned': resigned,
        'diceLeft': _diceLeft,
        'log': log.tail(),
      };

  // ---------------- bot ----------------
  /// Bank threshold by dice that would remain.
  static int bankAt(int remaining) => const {1: 300, 2: 300, 3: 400, 4: 1000, 5: 2000}[remaining] ?? 3000;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    if (roll.isEmpty) return {'type': 'roll'};
    if (botLevel <= 0) return _botEasy(seat);
    final (bestPts, bestIdx) = farkleBest(roll);
    var idx = bestIdx;
    var pts = bestPts;
    var remain = roll.length - idx.length;
    // if not taking all dice, consider keeping just one 1 (or 5) to reroll more dice
    if (remain > 0 && idx.length > 1) {
      final one = roll.indexOf(1);
      final five = roll.indexOf(5);
      final single = one >= 0 ? one : five;
      final kc = d2Counts([for (final i in idx) roll[i]]);
      final onlySingles = kc[1] < 3 && kc[5] < 3 && kc[1] + kc[5] == idx.length;
      if (single >= 0 && onlySingles && turnPoints + bestPts < (botLevel >= 2 ? bankAtHard(remain) : bankAt(remain))) {
        idx = [single];
        pts = roll[single] == 1 ? 100 : 50;
        remain = roll.length - 1;
      }
    }
    final total = turnPoints + pts;
    final left = remain == 0 ? 6 : remain;
    bool bank;
    if (finalTrigger >= 0) {
      final best = [for (var s = 0; s < players; s++) if (s != seat) scores[s]].fold(0, (a, b) => a > b ? a : b);
      bank = scores[seat] + total > best;
    } else if (scores[seat] + total >= target) {
      bank = true;
    } else if (botLevel >= 2) {
      // 困难: thresholds tuned to dice left, pushed when far behind the leader
      final lead = [for (var s = 0; s < players; s++) if (s != seat && !resigned.contains(s)) scores[s]]
          .fold(0, (a, b) => a > b ? a : b);
      var at = bankAtHard(left);
      if (lead - scores[seat] > target ~/ 4) at += 300;
      if (lead >= target - 1000) at += 400;
      bank = total >= at;
    } else {
      bank = total >= bankAt(left);
    }
    return {'type': 'keep', 'dice': idx, 'then': bank ? 'bank' : 'roll'};
  }

  /// 困难 thresholds (closer to expected-value play than [bankAt]).
  static int bankAtHard(int remaining) => const {1: 350, 2: 300, 3: 400, 4: 700, 5: 2000}[remaining] ?? 3000;

  /// 简单: keeps some scoring dice (not always the best) and banks at a random point.
  Map<String, dynamic> _botEasy(int seat) {
    var (pts, idx) = farkleBest(roll);
    if (rng.nextInt(3) == 0) {
      final singles = [for (var i = 0; i < roll.length; i++) if (roll[i] == 1 || roll[i] == 5) i];
      if (singles.isNotEmpty) {
        final i = singles[rng.nextInt(singles.length)];
        idx = [i];
        pts = roll[i] == 1 ? 100 : 50;
      }
    }
    final total = turnPoints + pts;
    final left = roll.length - idx.length == 0 ? 6 : roll.length - idx.length;
    var bank = total >= 250 + rng.nextInt(500) || scores[seat] + total >= target;
    if (finalTrigger >= 0) {
      final best = [for (var s = 0; s < players; s++) if (s != seat) scores[s]].fold(0, (a, b) => a > b ? a : b);
      bank = scores[seat] + total > best;
    }
    if (left >= 5 && rng.nextBool()) bank = false;
    return {'type': 'keep', 'dice': idx, 'then': bank ? 'bank' : 'roll'};
  }
}
