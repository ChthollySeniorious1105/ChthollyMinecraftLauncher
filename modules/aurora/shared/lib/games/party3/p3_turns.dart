import '../../src/engine.dart';
import 'p3_util.dart';

/// Shared turn / lives / elimination skeleton for 成语接龙 and 飞花令.
///
/// Phases: `play` (the current player answers or passes) → optional
/// game-specific phases (e.g. `vote`) → `over`. A pass, a rejected answer or
/// a timeout costs a life; at 0 lives the player is out. The game ends when
/// at most one player is left (2+ players) or after [maxTurns] answers.
abstract class P3LifeGame extends GameEngine {
  P3LifeGame(super.setup);

  late List<int> lives;
  late List<int> score;
  late int maxLives;
  late int timeSec;
  final List<int> eliminated = []; // seats in elimination order
  int turn = 0;
  int answers = 0;
  String phase = 'play';
  int endsAt = 0;
  bool _over = false;
  final List<Map<String, dynamic>> history = [];
  final P3Timers timers = P3Timers();

  /// Total accepted answers before the game ends on points.
  int get maxTurns => 150;

  bool alive(int s) => lives[s] > 0;
  List<int> get aliveSeats => [for (var s = 0; s < players; s++) if (alive(s)) s];

  @override
  bool get isOver => _over;

  @override
  bool get canResign => true;

  @override
  void resign(int seat) {
    if (_over || seat < 0 || seat >= players || !alive(seat)) return;
    lives[seat] = 0;
    eliminated.add(seat);
    host.log('${name(seat)} 认输出局');
    history.add({'s': seat, 'k': 'out', 'why': '认输'});
    onResign(seat);
    if (_checkEnd()) return;
    if (seat == turn && phase == 'play') {
      _advance();
      beginTurn();
    }
  }

  /// Hook for subclasses (e.g. drop a pending vote by that player).
  void onResign(int seat) {}

  @override
  List<int>? get placings {
    if (!_over) return null;
    // survivors first (more lives, then more points); then by how late they fell
    num key(int s) {
      final out = eliminated.indexOf(s);
      return (out < 0 ? 100000 + lives[s] * 1000 : (out + 1) * 1000) + score[s];
    }

    return rankByScore([for (var s = 0; s < players; s++) key(s)]);
  }

  void startLives() {
    maxLives = setup.opt<int>('lives', 3);
    timeSec = setup.opt<int>('time', 30);
    lives = List.filled(players, maxLives);
    score = List.filled(players, 0);
    turn = rng.nextInt(players);
  }

  /// Arm the per-turn timer for the current player.
  void beginTurn() {
    phase = 'play';
    armTimer(() {
      if (phase == 'play' && !_over) fail(turn, '超时');
    });
  }

  void armTimer(void Function() fn) {
    timers.cancel();
    if (timeSec <= 0) {
      endsAt = 0;
      return;
    }
    endsAt = p3Now() + timeSec * 1000;
    timers.countdown(host, timeSec * 1000, fn);
  }

  void _advance() {
    for (var i = 1; i <= players; i++) {
      final s = (turn + i) % players;
      if (alive(s)) {
        turn = s;
        return;
      }
    }
  }

  /// [seat] failed this turn (pass / timeout / rejected): lose a life.
  void fail(int seat, String why) {
    timers.cancel();
    lives[seat]--;
    final out = lives[seat] <= 0;
    if (out) eliminated.add(seat);
    history.add({'s': seat, 'k': 'fail', 'why': why, 'lives': lives[seat]});
    host.log('${name(seat)} $why，失去 1 条命${out ? '，出局！' : '（剩 ${lives[seat]}）'}');
    onFail(seat);
    if (_checkEnd()) return;
    _advance();
    beginTurn();
  }

  /// Called after a failure (chengyu restarts the chain here).
  void onFail(int seat) {}

  /// [seat] answered correctly; [entry] goes into the history feed.
  void succeed(int seat, Map<String, dynamic> entry, {int points = 1}) {
    timers.cancel();
    score[seat] += points;
    answers++;
    history.add({'s': seat, 'k': 'ok', ...entry});
    if (_checkEnd()) return;
    _advance();
    beginTurn();
  }

  bool _checkEnd() {
    final left = aliveSeats.length;
    if ((players >= 2 && left <= 1) || left == 0 || answers >= maxTurns) {
      finish();
      return true;
    }
    return false;
  }

  void finish() {
    timers.cancel();
    _over = true;
    phase = 'over';
    endsAt = 0;
    final pl = placings!;
    final win = [for (var s = 0; s < players; s++) if (pl[s] == 1) name(s)];
    host.log('游戏结束！${answers >= maxTurns ? '（达到 $maxTurns 回合上限）' : ''}获胜：${win.join('、')}');
  }

  /// Common view fields.
  Map<String, dynamic> baseView() => {
        'phase': phase,
        'turn': turn,
        'lives': lives,
        'maxLives': maxLives,
        'score': score,
        'eliminated': eliminated,
        'answers': answers,
        'maxTurns': maxTurns,
        'history': history.length > 80 ? history.sublist(history.length - 80) : history,
        'placings': placings,
        'timeSec': timeSec,
        'endsAt': endsAt,
        'now': p3Now(),
      };

  void guardPlayer(int seat) {
    if (_over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    if (!alive(seat)) throw GameError('你已经出局了');
  }
}

const OptionDef kLivesOption =
    OptionDef('lives', '生命', [OptionChoice(1, '1 条'), OptionChoice(3, '3 条'), OptionChoice(5, '5 条')], 3);
