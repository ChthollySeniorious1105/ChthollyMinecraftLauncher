import '../../src/engine.dart';
import 'draughts_rules.dart';

/// 国际跳棋（10×10）/ 英式跳棋（8×8）。
class Draughts extends GameEngine {
  Draughts(super.setup);

  late final bool intl = setup.opt<String>('variant', 'intl') != 'english';
  late final int n = intl ? 10 : 8;
  late final DraughtsRules rules = DraughtsRules(n, intl);
  late List<int> board = rules.initial();

  /// Seat playing side 1 (light, moves first, at the bottom).
  int firstSeat = 0;
  int side = 1; // side to move
  int ply = 0;
  int quiet = 0; // plies since last capture or man move
  List<int> lastPath = [];
  List<int> lastCaps = [];
  int winner = -1; // seat, 2 = draw
  String result = '';
  int drawOffer = -1;
  final Map<String, int> _reps = {};
  final List<String> moveLog = [];
  List<DMove> _legal = [];

  static const maxPly = 300;

  int seatOf(int s) => s == 1 ? firstSeat : 1 - firstSeat;
  int sideOf(int seat) => seat == firstSeat ? 1 : -1;
  int get turn => seatOf(side);
  bool get over => winner != -1;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    firstSeat = rng.nextInt(2);
    host.log('${intl ? '国际跳棋 10×10' : '英式跳棋 8×8'}：${name(firstSeat)} 执白先行');
    _legal = rules.legal(board, side);
    _reps[_key()] = 1;
  }

  /// Test/debug helper: replace the position.
  void setPosition(List<int> b, int sideToMove) {
    board = List.of(b);
    side = sideToMove;
    _legal = rules.legal(board, side);
  }

  String _key() => '$side:${board.join(',')}';

  void _end(int w, String why) {
    winner = w;
    result = why;
    host.log(why);
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    _end(1 - seat, '${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  @override
  bool get canDraw => !over;

  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    _end(2, '双方同意和棋');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    switch (a['type']) {
      case 'resign':
        resign(seat);
        return;
      case 'offerDraw':
        if (drawOffer == seat) return;
        drawOffer = seat;
        host.log('${name(seat)} 提议和棋');
        return;
      case 'acceptDraw':
        if (drawOffer != 1 - seat) throw GameError('对方没有提和');
        _end(2, '双方同意和棋');
        return;
      case 'declineDraw':
        if (drawOffer == 1 - seat) drawOffer = -1;
        return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    final path = asIntList(a['path']);
    if (path.length < 2) throw GameError('请选择棋子和落点');
    DMove? m;
    for (final x in _legal) {
      if (x.path.length == path.length && _same(x.path, path)) {
        m = x;
        break;
      }
    }
    if (m == null) {
      if (_legal.any((x) => x.isCapture)) {
        throw GameError(intl ? '必须吃子，且必须选择吃子最多的走法' : '有子可吃时必须吃子（连跳须跳完）');
      }
      throw GameError('这步棋不合法');
    }
    _apply(m);
  }

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _apply(DMove m) {
    final man = board[m.from].abs() == 1;
    final crowned = rules.apply(board, m);
    lastPath = m.path;
    lastCaps = m.caps;
    moveLog.add([for (final p in m.path) rules.notation(p)].join(m.isCapture ? 'x' : '-'));
    ply++;
    if (drawOffer == turn) drawOffer = -1;
    quiet = (man || m.isCapture) ? 0 : quiet + 1;
    if (crowned) host.log('${name(turn)} 的棋子升王');
    side = -side;
    _legal = rules.legal(board, side);
    if (_legal.isEmpty) {
      _end(seatOf(-side), '${name(seatOf(side))} 无子可走，${name(seatOf(-side))} 获胜');
      return;
    }
    final k = _key();
    final r = (_reps[k] ?? 0) + 1;
    _reps[k] = r;
    if (r >= 3) {
      _end(2, '同一局面重复三次，和棋');
    } else if (quiet >= (intl ? 50 : 80)) {
      _end(2, intl ? '双方连续 25 回合只走王且无吃子，和棋' : '40 回合无吃子且无兵移动，和棋');
    } else if (ply >= maxPly) {
      _end(2, '达到 $maxPly 步上限，和棋');
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final mine = seat == turn && !over;
    return {
      'size': n,
      'variant': intl ? 'intl' : 'english',
      'board': board,
      'firstSeat': firstSeat,
      'turn': turn,
      'ply': ply,
      'quiet': quiet,
      'lastPath': lastPath,
      'lastCaps': lastCaps,
      // legal paths are public information (no hidden info); send to everyone
      // so spectators can also see forced captures.
      'moves': [for (final m in _legal) m.path],
      'mustCapture': !over && _legal.isNotEmpty && _legal.first.isCapture,
      'myTurn': mine,
      'counts': [
        board.where((v) => v > 0).length,
        board.where((v) => v < 0).length,
      ],
      'drawOffer': drawOffer,
      'log': moveLog.length > 40 ? moveLog.sublist(moveLog.length - 40) : moveLog,
      'winner': winner,
      'result': result,
      'over': over,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over) return null;
    if (drawOffer == 1 - seat) return {'type': 'declineDraw'};
    if (seat != turn) return null;
    if (_legal.isEmpty) return null;
    if (botLevel <= 0 && rng.nextDouble() < 0.5) return {'type': 'move', 'path': _legal[rng.nextInt(_legal.length)].path};
    final m = switch (botLevel) {
      <= 0 => DraughtsAI(rules).best(board, side, _legal, rng.nextInt(1 << 20), maxDepth: 2),
      1 => DraughtsAI(rules).best(board, side, _legal, rng.nextInt(1 << 20)),
      _ => DraughtsAI(rules).best(board, side, _legal, rng.nextInt(1 << 20), maxDepth: 12, limitMs: 1000),
    };
    return {'type': 'move', 'path': m.path};
  }
}

class DraughtsAI {
  final DraughtsRules r;
  DraughtsAI(this.r);

  late Stopwatch _sw;
  bool _to = false;
  int _limit = 300;

  DMove best(List<int> board, int side, List<DMove> legal, int seed, {int maxDepth = 6, int limitMs = 300}) {
    if (legal.length == 1) return legal.first;
    _sw = Stopwatch()..start();
    _limit = limitMs;
    var bestM = legal[seed % legal.length];
    for (var d = 1; d <= maxDepth; d++) {
      _to = false;
      var alpha = -1 << 30;
      DMove? bm;
      for (final m in [bestM, ...legal.where((x) => x != bestM)]) {
        final b = List.of(board);
        r.apply(b, m);
        final v = -_neg(b, -side, d - 1, -(1 << 30), -alpha);
        if (_to) break;
        if (bm == null || v > alpha) {
          alpha = v;
          bm = m;
        }
      }
      if (_to) break;
      if (bm != null) bestM = bm;
    }
    return bestM;
  }

  int _neg(List<int> b, int side, int depth, int alpha, int beta) {
    if (_sw.elapsedMilliseconds > _limit) {
      _to = true;
      return 0;
    }
    final moves = r.legal(b, side);
    if (moves.isEmpty) return -100000 - depth;
    // quiescence-ish: extend forced captures a little
    if (depth <= 0 && !(moves.first.isCapture && depth > -2)) return _eval(b, side);
    for (final m in moves) {
      final nb = List.of(b);
      r.apply(nb, m);
      final v = -_neg(nb, -side, depth - 1, -beta, -alpha);
      if (_to) return 0;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return alpha;
  }

  int _eval(List<int> b, int side) {
    final n = r.n;
    var s = 0;
    for (var p = 0; p < n * n; p++) {
      final v = b[p];
      if (v == 0) continue;
      final row = p ~/ n, col = p % n;
      int val;
      if (v.abs() == 2) {
        val = r.intl ? 330 : 250;
      } else {
        final adv = v > 0 ? n - 1 - row : row; // rows advanced
        val = 100 + adv * 4;
        if (col == 0 || col == n - 1) val -= 3;
        if ((v > 0 && row == n - 1) || (v < 0 && row == 0)) val += 6; // back rank guard
      }
      if (col >= 2 && col <= n - 3 && row >= 2 && row <= n - 3) val += 3;
      s += v > 0 ? val : -val;
    }
    return s * side;
  }
}
