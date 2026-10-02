import '../../src/engine.dart';
import 'util.dart';

/// Result of one Pig roll: what happens to turn points / bank.
enum PigOutcome { add, loseTurn, loseAll }

/// Classic Pig: one die; 1 loses turn points.
/// 双骰猪: two dice; a single 1 loses turn points, snake eyes (1+1) lose ALL banked points.
PigOutcome pigOutcome(List<int> roll) {
  final ones = roll.where((d) => d == 1).length;
  if (roll.length >= 2 && ones >= 2) return PigOutcome.loseAll;
  if (ones >= 1) return PigOutcome.loseTurn;
  return PigOutcome.add;
}

class PigDice extends GameEngine {
  PigDice(super.setup);

  late final int target = setup.opt<int>('target', 100);
  late final bool two = setup.opt<String>('variant', 'one') == 'two';
  late final D2Log log = D2Log(() => host);

  String phase = 'play'; // play / over
  int turn = 0;
  List<int> scores = [];
  int turnPoints = 0;
  int turnRolls = 0;
  List<int> lastRoll = [];
  String lastEvent = '';
  int rollCount = 0; // total rolls, lets the UI animate on change
  int winner = -1;

  /// Seats that resigned, in order.
  final List<int> resigned = [];

  @override
  void start() {
    scores = List.filled(players, 0);
    turn = rng.nextInt(players);
    log.add('${name(turn)} 先开始，目标 $target 分${two ? '（双骰猪）' : ''}');
  }

  void _pass() {
    do {
      turn = (turn + 1) % players;
    } while (resigned.contains(turn));
    turnPoints = 0;
    turnRolls = 0;
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || resigned.contains(seat)) throw GameError('你不在游戏中');
    resigned.add(seat);
    log.add('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (!resigned.contains(s)) s];
    if (left.length <= 1) {
      winner = left.isEmpty ? -1 : left.first;
      phase = 'over';
      if (winner >= 0) log.add('${name(winner)} 获胜！');
      return;
    }
    if (turn == seat) _pass();
  }

  @override
  List<int>? get placings => isOver ? d2Placings(scores, resigned, winner: winner) : null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'roll') {
      lastRoll = [for (var i = 0; i < (two ? 2 : 1); i++) d2Roll(rng)];
      rollCount++;
      turnRolls++;
      switch (pigOutcome(lastRoll)) {
        case PigOutcome.loseAll:
          lastEvent = '${name(seat)} 掷出蛇眼（双 1）！总分清零';
          scores[seat] = 0;
          log.add(lastEvent);
          _pass();
        case PigOutcome.loseTurn:
          lastEvent = '${name(seat)} 掷出 1，本回合 $turnPoints 分作废';
          log.add(lastEvent);
          _pass();
        case PigOutcome.add:
          final sum = lastRoll.fold(0, (x, y) => x + y);
          turnPoints += sum;
          lastEvent = '${name(seat)} 掷出 ${lastRoll.join('+')}，本回合累计 $turnPoints';
          if (scores[seat] + turnPoints >= target) {
            scores[seat] += turnPoints;
            winner = seat;
            phase = 'over';
            log.add('${name(seat)} 达到 ${scores[seat]} 分，获胜！');
          }
      }
    } else if (type == 'hold') {
      if (turnRolls == 0) throw GameError('至少要掷一次');
      scores[seat] += turnPoints;
      lastEvent = '${name(seat)} 存入 $turnPoints 分，总分 ${scores[seat]}';
      log.add(lastEvent);
      _pass();
    } else {
      throw GameError('未知操作');
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
        'two': two,
        'scores': scores,
        'turnPoints': turnPoints,
        'turnRolls': turnRolls,
        'lastRoll': lastRoll,
        'lastEvent': lastEvent,
        'rollCount': rollCount,
        'winner': winner,
        'resigned': resigned,
        'log': log.tail(),
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    if (turnRolls == 0) return {'type': 'roll'};
    final mine = scores[seat];
    if (mine + turnPoints >= target) return {'type': 'hold'};
    final lead = [for (var s = 0; s < players; s++) if (s != seat && !resigned.contains(s)) scores[s]]
        .fold(0, (a, b) => a > b ? a : b);
    if (botLevel <= 0) {
      // 简单: short-sighted, erratic stopping point
      if (rng.nextInt(4) == 0) return {'type': rng.nextBool() ? 'hold' : 'roll'};
      return {'type': turnPoints >= 8 + rng.nextInt(10) ? 'hold' : 'roll'};
    }
    if (botLevel >= 2) {
      // 困难: "keep pace and end race" — adapt the hold point to the score gap
      // and bank whatever is needed once the goal is within reach.
      final need = target - mine;
      var limit = 21 + ((lead - mine) / 8).round();
      if (two) limit = (limit * 0.9).round() - (mine >= 50 ? 4 : 0);
      if (lead >= target - (two ? 20 : 15)) limit = need; // an opponent is about to win
      if (need <= limit + 4 && need > limit) limit = need; // one more push finishes it
      limit = limit.clamp(two ? 12 : 15, target);
      return {'type': turnPoints >= limit ? 'hold' : 'roll'};
    }
    // "hold at 20", pushed harder when an opponent is close to winning
    var limit = two ? 22 : 20;
    if (lead >= target - 15) limit = target; // go for it
    if (two && mine >= 40) limit = 16; // protect bank from snake eyes
    return {'type': turnPoints >= limit ? 'hold' : 'roll'};
  }
}
