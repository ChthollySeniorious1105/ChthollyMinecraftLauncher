import '../../src/engine.dart';
import 'util.dart';

/// 骰子扑克 hand ranks (higher is better).
const dpRankNames = ['散牌', '一对', '两对', '三条', '小顺', '大顺', '葫芦', '四条', '五条'];

/// Comparable score: rank * 10^6 + tiebreak digits. Higher wins.
int dpScore(List<int> dice) {
  final c = d2Counts(dice);
  // groups sorted by (count desc, face desc)
  final faces = [for (var f = 6; f >= 1; f--) if (c[f] > 0) f]
    ..sort((a, b) => c[b] != c[a] ? c[b] - c[a] : b - a);
  final counts = [for (final f in faces) c[f]];
  int rank;
  if (counts[0] == 5) {
    rank = 8;
  } else if (counts[0] == 4) {
    rank = 7;
  } else if (counts[0] == 3 && counts.length == 2) {
    rank = 6;
  } else if (faces.length == 5 && c[1] == 0) {
    rank = 5; // 2-6
  } else if (faces.length == 5 && c[6] == 0) {
    rank = 4; // 1-5
  } else if (counts[0] == 3) {
    rank = 3;
  } else if (counts[0] == 2 && counts[1] == 2) {
    rank = 2;
  } else if (counts[0] == 2) {
    rank = 1;
  } else {
    rank = 0;
  }
  var tb = 0;
  for (var i = 0; i < 5; i++) {
    tb = tb * 7 + (i < faces.length ? faces[i] : 0);
  }
  return rank * 100000 + tb;
}

int dpRank(List<int> dice) => dpScore(dice) ~/ 100000;

class DicePoker extends GameEngine {
  DicePoker(super.setup);

  late final int rounds = setup.opt<int>('rounds', 5);
  late final D2Log log = D2Log(() => host);

  String phase = 'play'; // play / result / over
  int round = 0;
  int starter = 0;
  int turn = 0;
  int turnsTaken = 0;
  List<int> dice = List.filled(5, 1);
  List<bool> held = List.filled(5, false);
  int rollsUsed = 0;
  List<List<int>?> finals = [];
  List<int> points = [];
  List<int> roundWinners = [];

  /// Seats that resigned, in order (skipped from then on, ranked last).
  final List<int> resigned = [];

  List<int> get _alive => [for (var s = 0; s < players; s++) if (!resigned.contains(s)) s];

  int _nextAlive(int s) {
    for (var i = 1; i <= players; i++) {
      final t = (s + i) % players;
      if (!resigned.contains(t)) return t;
    }
    return s;
  }

  @override
  void start() {
    points = List.filled(players, 0);
    starter = rng.nextInt(players);
    _newRound();
  }

  void _newRound() {
    round++;
    phase = 'play';
    finals = List<List<int>?>.filled(players, null);
    roundWinners = [];
    turnsTaken = 0;
    turn = (starter + round - 1) % players;
    if (resigned.contains(turn)) turn = _nextAlive(turn);
    _resetTurn();
    log.add('第 $round 局开始，${name(turn)} 先掷');
  }

  void _resetTurn() {
    dice = List.filled(5, 1);
    held = List.filled(5, false);
    rollsUsed = 0;
  }

  void _finishTurn() {
    finals[turn] = List.of(dice);
    log.add('${name(turn)}：${dice.join(' ')} → ${dpRankNames[dpRank(dice)]}');
    turnsTaken++;
    _advance();
  }

  void _advance() {
    if (_alive.every((s) => finals[s] != null)) {
      _settle();
    } else {
      turn = _nextAlive(turn);
      _resetTurn();
    }
  }

  void _settle() {
    phase = 'result';
    final scores = [for (var s = 0; s < players; s++) finals[s] == null || resigned.contains(s) ? -1 : dpScore(finals[s]!)];
    final best = scores.reduce((a, b) => a > b ? a : b);
    roundWinners = [for (var s = 0; s < players; s++) if (scores[s] == best) s];
    for (final w in roundWinners) {
      points[w]++;
    }
    log.add('第 $round 局 ${roundWinners.map(name).join('、')} 以 ${dpRankNames[best ~/ 100000]} 获胜');
    host.schedule(3000, () {
      if (phase == 'over') return;
      if (round >= rounds) {
        phase = 'over';
        log.add('游戏结束，${winners.map(name).join('、')} 获胜');
      } else {
        _newRound();
      }
    });
  }

  List<int> get winners {
    final alive = _alive;
    if (alive.isEmpty) return const [];
    final best = alive.map((s) => points[s]).reduce((a, b) => a > b ? a : b);
    return [for (final s in alive) if (points[s] == best) s];
  }

  @override
  List<int>? get placings => isOver ? d2Placings(points, resigned) : null;

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || resigned.contains(seat)) throw GameError('你不在游戏中');
    resigned.add(seat);
    log.add('${name(seat)} 认输');
    if (_alive.length <= 1) {
      phase = 'over';
      log.add('游戏结束，${winners.map(name).join('、')} 获胜');
      return;
    }
    if (phase == 'play' && turn == seat) _advance();
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    if (phase != 'play') throw GameError('请稍候');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'roll') {
      if (rollsUsed >= 3) throw GameError('已经掷满 3 次');
      final hold = rollsUsed == 0 ? List.filled(5, false) : d2Mask(a['hold'], 5);
      if (hold.every((h) => h)) throw GameError('全部保留了，请直接停手');
      held = hold;
      for (var i = 0; i < 5; i++) {
        if (!held[i]) dice[i] = d2Roll(rng);
      }
      rollsUsed++;
      if (rollsUsed >= 3) _finishTurn();
    } else if (type == 'stand') {
      if (rollsUsed == 0) throw GameError('至少要掷一次');
      _finishTurn();
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
        'round': round,
        'rounds': rounds,
        'turn': turn,
        'dice': dice,
        'held': held,
        'rollsUsed': rollsUsed,
        'finals': finals,
        'finalRanks': [for (final f in finals) f == null ? null : dpRankNames[dpRank(f)]],
        'current': rollsUsed > 0 ? dpRankNames[dpRank(dice)] : null,
        'points': points,
        'roundWinners': roundWinners,
        'winners': phase == 'over' ? winners : <int>[],
        'resigned': resigned,
        'log': log.tail(),
      };

  // ---------------- bot ----------------
  /// Hold mask aiming for the best hand given current dice.
  static List<bool> botHold(List<int> dice) {
    final c = d2Counts(dice);
    final maxC = c.reduce((a, b) => a > b ? a : b);
    final r = dpRank(dice);
    if (r >= 4) return List.filled(5, true); // straight or better (full house, 4/5 kind handled below)
    // four distinct in a straight window -> chase straight
    if (r <= 1) {
      for (final win in const [
        [2, 3, 4, 5],
        [3, 4, 5, 6],
        [1, 2, 3, 4],
      ]) {
        if (win.every((f) => c[f] > 0)) {
          final used = <int>{};
          return [for (final d in dice) win.contains(d) && used.add(d)];
        }
      }
    }
    if (maxC == 1) {
      // keep highest die
      final hi = dice.reduce((a, b) => a > b ? a : b);
      final i = dice.indexOf(hi);
      return [for (var k = 0; k < 5; k++) k == i];
    }
    // keep all dice that belong to a group of size >= 2
    return [for (final d in dice) c[d] >= 2];
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    if (rollsUsed == 0) return {'type': 'roll'};
    if (botLevel <= 0) {
      // 简单: stops early or rerolls at random a good part of the time
      if (rng.nextInt(3) == 0) {
        if (rng.nextBool()) return {'type': 'stand'};
        final hold = [for (var i = 0; i < 5; i++) rng.nextBool()];
        if (hold.every((h) => h)) hold[rng.nextInt(5)] = false;
        return {'type': 'roll', 'hold': hold};
      }
    } else if (botLevel >= 2) {
      return _botHard();
    }
    final r = dpRank(dice);
    // compare with best finished hand so far
    final done = [for (final f in finals) if (f != null) dpScore(f)];
    final best = done.isEmpty ? 0 : done.reduce((a, b) => a > b ? a : b);
    if (r >= 6 || (dpScore(dice) > best && r >= 4)) return {'type': 'stand'};
    final hold = botHold(dice);
    if (hold.every((h) => h)) return {'type': 'stand'};
    return {'type': 'roll', 'hold': hold};
  }

  /// 困难: Monte-Carlo over all 32 hold masks, maximising the chance of
  /// beating the best finished hand this round (or the expected rank when
  /// nobody has finished yet).
  Map<String, dynamic> _botHard() {
    final done = [for (final f in finals) if (f != null) dpScore(f)];
    final best = done.isEmpty ? -1 : done.reduce((a, b) => a > b ? a : b);
    final left = 3 - rollsUsed;
    double eval(List<int> d) {
      final s = dpScore(d);
      if (best >= 0) return s > best ? 1.0 : (s == best ? 0.5 : 0.0);
      return s / 100000.0;
    }

    final cur = eval(dice);
    var bestV = cur;
    List<bool>? bestMask;
    const samples = 160;
    for (var m = 0; m < 31; m++) {
      final hold = [for (var i = 0; i < 5; i++) m & (1 << i) != 0];
      var total = 0.0;
      for (var k = 0; k < samples; k++) {
        final d = List.of(dice);
        for (var i = 0; i < 5; i++) {
          if (!hold[i]) d[i] = d2Roll(rng);
        }
        // remaining extra roll (if any) follows the normal heuristic
        if (left >= 2 && eval(d) < 1.0) {
          final h2 = botHold(d);
          if (!h2.every((h) => h)) {
            for (var i = 0; i < 5; i++) {
              if (!h2[i]) d[i] = d2Roll(rng);
            }
          }
        }
        total += eval(d);
      }
      final v = total / samples;
      if (v > bestV + 0.01) {
        bestV = v;
        bestMask = hold;
      }
    }
    if (bestMask == null) return {'type': 'stand'};
    return {'type': 'roll', 'hold': bestMask};
  }
}
