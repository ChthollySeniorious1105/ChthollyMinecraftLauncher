import '../../src/engine.dart';

/// 四子棋 7 列 × 6 行。cells[r*7+c], r=0 为最上行；0 空, 1 先手(红), 2 后手(黄)。
class Connect4 extends GameEngine {
  Connect4(super.setup);

  static const cols = 7, rows = 6;
  final List<int> cells = List.filled(42, 0);
  int firstSeat = 0;
  int turn = 0;
  int last = -1;
  int moves = 0;
  int winner = -1;
  List<int> winLine = [];
  String result = '';

  int colorOf(int seat) => seat == firstSeat ? 1 : 2;
  bool get over => winner != -1;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    firstSeat = rng.nextInt(2);
    turn = firstSeat;
    host.log('四子棋：${name(firstSeat)} 执红先手');
  }

  static int dropRow(List<int> cells, int col) {
    for (var r = rows - 1; r >= 0; r--) {
      if (cells[r * cols + col] == 0) return r;
    }
    return -1;
  }

  static List<int>? lineAt(List<int> cells, int p) {
    final color = cells[p];
    if (color == 0) return null;
    final r0 = p ~/ cols, c0 = p % cols;
    for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      final pts = [p];
      for (final sg in const [1, -1]) {
        var r = r0 + dr * sg, c = c0 + dc * sg;
        while (r >= 0 && r < rows && c >= 0 && c < cols && cells[r * cols + c] == color) {
          pts.add(r * cols + c);
          r += dr * sg;
          c += dc * sg;
        }
      }
      if (pts.length >= 4) return pts..sort();
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') {
      if (seat != 0 && seat != 1) throw GameError('你不是棋手');
      resign(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    final col = asInt(a['col']);
    if (col < 0 || col >= cols) throw GameError('无效的列');
    final r = dropRow(cells, col);
    if (r < 0) throw GameError('这一列已经满了');
    final p = r * cols + col;
    cells[p] = colorOf(seat);
    last = p;
    moves++;
    final l = lineAt(cells, p);
    if (l != null) {
      winner = seat;
      winLine = l;
      result = '${name(seat)} 四子连珠获胜';
      host.log(result);
      return;
    }
    if (moves == 42) {
      winner = 2;
      result = '棋盘已满，和棋';
      host.log(result);
      return;
    }
    turn = 1 - turn;
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    winner = 1 - seat;
    result = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;

  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    winner = 2;
    result = '双方同意和棋';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'cells': cells,
        'firstSeat': firstSeat,
        'turn': turn,
        'last': last,
        'winner': winner,
        'winLine': winLine,
        'result': result,
        'over': over,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final color = colorOf(seat);
    if (botLevel <= 0) {
      if (rng.nextDouble() < 0.6) {
        final legal = [for (var c = 0; c < cols; c++) if (dropRow(cells, c) >= 0) c];
        return {'type': 'drop', 'col': legal[rng.nextInt(legal.length)]};
      }
      return {'type': 'drop', 'col': Connect4AI(cells).best(color, maxDepth: 2)};
    }
    if (botLevel >= 2) {
      return {'type': 'drop', 'col': Connect4AI(cells).best(color, maxDepth: 16, limitMs: 1000)};
    }
    return {'type': 'drop', 'col': Connect4AI(cells).best(color)};
  }
}

/// Bitboard negamax with alpha-beta, iterative deepening, time limit.
class Connect4AI {
  final List<int> cells;
  Connect4AI(this.cells);

  static const _order = [3, 2, 4, 1, 5, 0, 6];
  static final List<List<int>> _windows = _buildWindows();
  late Stopwatch _sw;
  bool _to = false;
  int _limit = 250;

  static List<List<int>> _buildWindows() {
    final out = <List<int>>[];
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 7; c++) {
        for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
          final er = r + dr * 3, ec = c + dc * 3;
          if (er < 0 || er >= 6 || ec < 0 || ec >= 7) continue;
          out.add([for (var k = 0; k < 4; k++) (r + dr * k) * 7 + c + dc * k]);
        }
      }
    }
    return out;
  }

  int best(int color, {int maxDepth = 9, int limitMs = 250}) {
    final b = List.of(cells);
    final legal = [for (final c in _order) if (Connect4.dropRow(b, c) >= 0) c];
    // immediate win / block
    for (final who in [color, 3 - color]) {
      for (final c in legal) {
        final r = Connect4.dropRow(b, c);
        b[r * 7 + c] = who;
        final w = Connect4.lineAt(b, r * 7 + c) != null;
        b[r * 7 + c] = 0;
        if (w) return c;
      }
    }
    _sw = Stopwatch()..start();
    _limit = limitMs;
    var bestCol = legal.first;
    for (var d = 2; d <= maxDepth; d++) {
      _to = false;
      var alpha = -1 << 30;
      int? bc;
      for (final c in [bestCol, ...legal.where((x) => x != bestCol)]) {
        final r = Connect4.dropRow(b, c);
        b[r * 7 + c] = color;
        final v = Connect4.lineAt(b, r * 7 + c) != null ? 100000 : -_neg(b, 3 - color, d - 1, -(1 << 30), -alpha);
        b[r * 7 + c] = 0;
        if (_to) break;
        if (bc == null || v > alpha) {
          alpha = v;
          bc = c;
        }
      }
      if (_to) break;
      if (bc != null) bestCol = bc;
      if (alpha >= 90000) break;
    }
    return bestCol;
  }

  int _neg(List<int> b, int color, int depth, int alpha, int beta) {
    if (_sw.elapsedMilliseconds > _limit) {
      _to = true;
      return 0;
    }
    var any = false;
    if (depth <= 0) return _eval(b, color);
    for (final c in _order) {
      final r = Connect4.dropRow(b, c);
      if (r < 0) continue;
      any = true;
      final p = r * 7 + c;
      b[p] = color;
      int v;
      if (Connect4.lineAt(b, p) != null) {
        v = 100000 + depth;
      } else {
        v = -_neg(b, 3 - color, depth - 1, -beta, -alpha);
      }
      b[p] = 0;
      if (_to) return 0;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    if (!any) return 0;
    return alpha;
  }

  int _eval(List<int> b, int color) {
    var s = 0;
    final opp = 3 - color;
    for (final w in _windows) {
      var m = 0, o = 0;
      for (final p in w) {
        final v = b[p];
        if (v == color) {
          m++;
        } else if (v == opp) {
          o++;
        }
      }
      if (o == 0) {
        s += const [0, 1, 8, 60, 0][m];
      } else if (m == 0) {
        s -= const [0, 1, 8, 60, 0][o];
      }
    }
    for (var r = 0; r < 6; r++) {
      final v = b[r * 7 + 3];
      if (v == color) s += 4;
      if (v == opp) s -= 4;
    }
    return s;
  }
}
