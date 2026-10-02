import '../../src/engine.dart';
import 'backgammon_rules.dart';

/// 西洋双陆（多局比赛制，支持加倍骰与克劳福德规则）。
/// 座位0 执白，座位1 执黑。
class Backgammon extends GameEngine {
  Backgammon(super.setup);

  late final int matchTo = setup.opt<int>('match', 3);
  late final bool cubeOn = setup.opt<bool>('cube', true) && matchTo > 1;
  late final bool crawfordOn = setup.opt<bool>('crawford', true);

  BgPos pos = BgPos.initial();
  final List<int> score = [0, 0];
  int gameNo = 0;
  int turn = 0;

  /// opening / roll / double / move / gameover / over
  String phase = 'roll';
  List<int> dice = []; // 本回合掷出的骰子（双骰为4个）
  List<int> rem = []; // 剩余未用的骰子
  BgPos? turnStart;
  List<int> turnStartRem = [];
  List<BgMove> played = [];
  int cube = 1;
  int cubeOwner = -1; // -1 = 中间
  bool crawfordGame = false;
  bool crawfordUsed = false;
  int winner = -1; // 整场胜者
  String result = '';
  Map<String, dynamic>? lastGame; // 上一局结果
  Map<String, dynamic>? lastTurn; // 对手上一回合
  List<int> openingRoll = [];

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'roll':
      case 'move':
        return [turn];
      case 'double':
        return [1 - turn];
      default:
        return const [];
    }
  }

  @override
  int get botDelayMs => 700;

  int _d6() => rng.nextInt(6) + 1;

  @override
  void start() {
    host.log('西洋双陆：${name(0)} 执白，${name(1)} 执黑；$matchTo 分制${cubeOn ? '，使用加倍骰' : ''}');
    _newGame();
  }

  void _newGame() {
    gameNo++;
    pos = BgPos.initial();
    cube = 1;
    cubeOwner = -1;
    lastTurn = null;
    crawfordGame = false;
    if (crawfordOn && cubeOn && !crawfordUsed && (score[0] == matchTo - 1 || score[1] == matchTo - 1)) {
      crawfordGame = true;
      crawfordUsed = true;
      host.log('克劳福德局：本局不能加倍');
    }
    // 开局掷骰：各掷一颗，大者先行并使用这两颗骰子
    int a, b;
    do {
      a = _d6();
      b = _d6();
    } while (a == b);
    openingRoll = [a, b];
    turn = a > b ? 0 : 1;
    host.log('第 $gameNo 局：开局掷骰 ${name(0)} $a · ${name(1)} $b，${name(turn)} 先行');
    _setDice([a, b]);
  }

  bool canDouble(int s) {
    if (!cubeOn || crawfordGame) return false;
    if (cubeOwner != -1 && cubeOwner != s) return false;
    if (score[s] + cube >= matchTo) return false; // 死骰
    return true;
  }

  void _beginTurn() {
    played = [];
    if (canDouble(turn)) {
      phase = 'roll';
      dice = [];
      rem = [];
    } else {
      _roll();
    }
  }

  void _roll() {
    final a = _d6(), b = _d6();
    _setDice([a, b]);
  }

  void _setDice(List<int> two) {
    dice = two[0] == two[1] ? [two[0], two[0], two[0], two[0]] : List.of(two);
    rem = List.of(dice);
    played = [];
    turnStart = pos.clone();
    turnStartRem = List.of(rem);
    phase = 'move';
    if (pos.legalNow(turn, rem).isEmpty) {
      host.log('${name(turn)} 掷出 ${two[0]}-${two[1]}，无子可走');
      lastTurn = {'seat': turn, 'dice': List.of(dice), 'moves': <Map<String, dynamic>>[], 'noMove': true};
      _nextTurn();
    }
  }

  void _nextTurn() {
    turn = 1 - turn;
    _beginTurn();
  }

  void _endGame(int w, int points, String how) {
    score[w] += points;
    final txt = '${name(w)} 赢得第 $gameNo 局（$how，$points 分）  比分 ${score[0]} : ${score[1]}';
    host.log(txt);
    lastGame = {'winner': w, 'points': points, 'how': how, 'game': gameNo};
    dice = [];
    rem = [];
    if (score[w] >= matchTo) {
      winner = w;
      phase = 'over';
      result = '${name(w)} 以 ${score[w]} : ${score[1 - w]} 赢得比赛';
      host.log(result);
      return;
    }
    phase = 'gameover';
    host.schedule(3500, () {
      if (phase == 'gameover') _newGame();
    });
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'over') throw GameError('比赛已结束');
    if (type == 'resign') {
      resign(seat);
      return;
    }
    switch (phase) {
      case 'roll':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'roll') {
          _roll();
        } else if (type == 'double') {
          if (!canDouble(seat)) throw GameError('现在不能加倍');
          phase = 'double';
          host.log('${name(seat)} 提出加倍至 ${cube * 2}');
        } else {
          throw GameError('请掷骰或加倍');
        }
        return;
      case 'double':
        if (seat != 1 - turn) throw GameError('等待对手回应加倍');
        if (type == 'take') {
          cube *= 2;
          cubeOwner = seat;
          host.log('${name(seat)} 接受加倍，赌注 $cube');
          _roll();
        } else if (type == 'drop') {
          host.log('${name(seat)} 拒绝加倍');
          _endGame(turn, cube, '对手拒绝加倍');
        } else {
          throw GameError('请选择接受或拒绝');
        }
        return;
      case 'move':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'undo') {
          if (played.isEmpty) throw GameError('没有可撤销的步');
          pos = turnStart!.clone();
          rem = List.of(turnStartRem);
          played = [];
          return;
        }
        if (type == 'confirm') {
          if (pos.legalNow(turn, rem).isNotEmpty) throw GameError('还有骰子可以使用');
          _finishTurn();
          return;
        }
        if (type != 'move') throw GameError('无效操作');
        final from = bgRel(seat, asInt(a['from'])), to = bgRel(seat, asInt(a['to']));
        final legal = pos.legalNow(turn, rem).where((m) => m.from == from && m.to == to).toList();
        if (legal.isEmpty) throw GameError('这样走不合法');
        final die = asInt(a['die'], 0);
        legal.sort((x, y) => x.die.compareTo(y.die));
        final m = legal.firstWhere((m) => m.die == die, orElse: () => legal.first);
        pos.apply(turn, m);
        rem.remove(m.die);
        played.add(m);
        if (pos.off(turn) == 15) {
          _finishTurn();
        }
        return;
      default:
        throw GameError('请稍候');
    }
  }

  void _finishTurn() {
    lastTurn = {
      'seat': turn,
      'dice': List.of(dice),
      'moves': [
        for (final m in played) {'from': bgAbs(turn, m.from), 'to': bgAbs(turn, m.to), 'hit': m.hit}
      ],
      'noMove': played.isEmpty,
    };
    if (played.isNotEmpty) host.log('${name(turn)}：${_notation(turn, played)}');
    if (pos.off(turn) == 15) {
      final k = pos.winKind(turn);
      _endGame(turn, cube * k, const {1: '单胜', 2: '全胜', 3: '大全胜'}[k]!);
      return;
    }
    _nextTurn();
  }

  static String _notation(int s, List<BgMove> ms) => ms
      .map((m) => '${m.from == 25 ? '中柱' : m.from}/${m.to == 0 ? '出' : m.to}${m.hit ? '*' : ''}')
      .join(' ');

  @override
  Map<String, dynamic> view(int seat) {
    final legal = phase == 'move' ? pos.legalNow(turn, rem) : const <BgMove>[];
    return {
      'phase': phase,
      'board': pos.absBoard(),
      'bar': [pos.bar(0), pos.bar(1)],
      'off': [pos.off(0), pos.off(1)],
      'pip': [pos.pip(0), pos.pip(1)],
      'turn': turn,
      'dice': dice,
      'rem': rem,
      'legal': [
        for (final m in legal) {'from': bgAbs(turn, m.from), 'to': bgAbs(turn, m.to), 'die': m.die}
      ],
      'played': [
        for (final m in played) {'from': bgAbs(turn, m.from), 'to': bgAbs(turn, m.to), 'hit': m.hit}
      ],
      'canConfirm': phase == 'move' && legal.isEmpty,
      'canDouble': phase == 'roll' && canDouble(turn),
      'cubeOn': cubeOn,
      'cube': cube,
      'cubeOwner': cubeOwner,
      'crawford': crawfordGame,
      'score': score,
      'matchTo': matchTo,
      'gameNo': gameNo,
      'lastTurn': lastTurn,
      'lastGame': lastGame,
      'winner': winner,
      'result': phase == 'over' ? result : null,
      'over': phase == 'over',
    };
  }

  @override
  List<int>? get placings => phase != 'over' || winner < 0 ? null : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2];

  @override
  bool get canResign => phase != 'over';
  @override
  void resign(int seat) {
    if (phase == 'over') throw GameError('比赛已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    host.log('${name(seat)} 认输');
    winner = 1 - seat;
    phase = 'over';
    dice = [];
    rem = [];
    result = '${name(seat)} 认输，${name(winner)} 赢得比赛';
    host.log(result);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'roll':
        if (seat != turn) return null;
        if (canDouble(seat)) {
          final est = bgWinEstimate(pos, seat);
          // 简单：几乎不主动加倍
          if (botLevel <= 0 ? est > 0.9 && rng.nextInt(3) == 0 : est > 0.72 && est < 0.93) {
            return {'type': 'double'};
          }
        }
        return {'type': 'roll'};
      case 'double':
        if (seat != 1 - turn) return null;
        if (botLevel <= 0) return {'type': rng.nextInt(4) == 0 ? 'drop' : 'take'};
        return {'type': bgWinEstimate(pos, seat) >= 0.24 ? 'take' : 'drop'};
      case 'move':
        if (seat != turn) return null;
        if (pos.legalNow(turn, rem).isEmpty) return {'type': 'confirm'};
        final seqs = pos.legalSequences(turn, rem);
        final List<BgMove> best;
        if (botLevel <= 0 && rng.nextInt(2) == 0) {
          best = seqs[rng.nextInt(seqs.length)];
        } else if (botLevel >= 2) {
          best = bgLookaheadSequence(pos, turn, seqs);
        } else {
          best = bgBestSequence(pos, turn, seqs);
        }
        if (best.isEmpty) return {'type': 'confirm'};
        final m = best.first;
        return {'type': 'move', 'from': bgAbs(turn, m.from), 'to': bgAbs(turn, m.to), 'die': m.die};
    }
    return null;
  }
}
