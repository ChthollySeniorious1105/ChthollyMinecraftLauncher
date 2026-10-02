import 'dart:math';

import '../../src/engine.dart';

const _dirs8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

/// Pure othello board helpers. cells: 0 empty, 1 black, 2 white; p = y*8+x.
class OthelloBoard {
  final List<int> c;
  OthelloBoard() : c = List.filled(64, 0) {
    c[27] = 2;
    c[28] = 1;
    c[35] = 1;
    c[36] = 2;
  }
  OthelloBoard.from(List<int> cells) : c = List.of(cells);

  /// Stones flipped if [color] plays p (empty list = illegal).
  List<int> flips(int p, int color) {
    if (c[p] != 0) return const [];
    final out = <int>[];
    final x0 = p % 8, y0 = p ~/ 8;
    final opp = 3 - color;
    for (final (dx, dy) in _dirs8) {
      var x = x0 + dx, y = y0 + dy;
      final line = <int>[];
      while (x >= 0 && y >= 0 && x < 8 && y < 8 && c[y * 8 + x] == opp) {
        line.add(y * 8 + x);
        x += dx;
        y += dy;
      }
      if (line.isNotEmpty && x >= 0 && y >= 0 && x < 8 && y < 8 && c[y * 8 + x] == color) out.addAll(line);
    }
    return out;
  }

  List<int> legal(int color) => [for (var p = 0; p < 64; p++) if (c[p] == 0 && flips(p, color).isNotEmpty) p];

  List<int> play(int p, int color) {
    final f = flips(p, color);
    c[p] = color;
    for (final q in f) {
      c[q] = color;
    }
    return f;
  }

  int count(int color) => c.where((v) => v == color).length;
}

class Othello extends GameEngine {
  Othello(super.setup);

  OthelloBoard b = OthelloBoard();
  int blackSeat = 0;
  int turn = 0;
  int last = -1;
  List<int> lastFlips = [];
  int winner = -1; // seat, 2 = draw
  String result = '';
  String note = '';

  int colorOf(int seat) => seat == blackSeat ? 1 : 2;
  bool get over => winner != -1;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    blackSeat = rng.nextInt(2);
    turn = blackSeat;
    host.log('黑白棋：${name(blackSeat)} 执黑先行');
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
    final p = asInt(a['point']);
    final color = colorOf(seat);
    if (p < 0 || p >= 64 || b.flips(p, color).isEmpty) throw GameError('这里不能落子（必须夹住对方棋子）');
    lastFlips = b.play(p, color);
    last = p;
    note = '';
    final opp = 3 - color;
    if (b.legal(opp).isNotEmpty) {
      turn = 1 - turn;
    } else if (b.legal(color).isNotEmpty) {
      note = '${name(1 - seat)} 无处可下，自动停一手';
      host.log(note);
    } else {
      _finish();
    }
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

  void _finish() {
    final bl = b.count(1), wh = b.count(2);
    if (bl == wh) {
      winner = 2;
      result = '和棋 $bl : $wh';
    } else {
      winner = bl > wh ? blackSeat : 1 - blackSeat;
      result = '${name(winner)} 获胜  黑 $bl : 白 $wh';
    }
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'board': b.c,
        'blackSeat': blackSeat,
        'turn': turn,
        'last': last,
        'flips': lastFlips,
        'legal': over ? <int>[] : b.legal(colorOf(turn)),
        'counts': [b.count(1), b.count(2)],
        'winner': winner,
        'result': result,
        'note': note,
        'over': over,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final color = colorOf(seat);
    switch (botLevel) {
      case <= 0:
        final moves = b.legal(color);
        if (moves.isEmpty) return null;
        if (rng.nextDouble() < 0.5) return {'type': 'play', 'point': moves[rng.nextInt(moves.length)]};
        return {'type': 'play', 'point': OthelloAI(b.c, rng).best(color, maxDepth: 1, cornerFirst: false)};
      case 1:
        return {'type': 'play', 'point': OthelloAI(b.c, rng).best(color)};
      default:
        final empties = b.c.where((v) => v == 0).length;
        return {
          'type': 'play',
          'point': OthelloAI(b.c, rng).best(color, maxDepth: empties <= 14 ? empties : 9, limitMs: 1000),
        };
    }
  }
}

/// Iterative-deepening alpha-beta with positional + mobility evaluation.
class OthelloAI {
  final List<int> start;
  final Random? rng;
  OthelloAI(this.start, [this.rng]);

  static const _w = [
    100, -20, 10, 5, 5, 10, -20, 100, //
    -20, -50, -2, -2, -2, -2, -50, -20,
    10, -2, 1, 1, 1, 1, -2, 10,
    5, -2, 1, 0, 0, 1, -2, 5,
    5, -2, 1, 0, 0, 1, -2, 5,
    10, -2, 1, 1, 1, 1, -2, 10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5, 5, 10, -20, 100,
  ];
  static const _corners = [0, 7, 56, 63];
  static const _xSq = [9, 14, 49, 54];

  late Stopwatch _sw;
  int _limitMs = 250;
  bool _timeout = false;

  int best(int color, {int maxDepth = 5, int limitMs = 250, bool cornerFirst = true}) {
    final b = OthelloBoard.from(start);
    final moves = b.legal(color);
    if (moves.length == 1) return moves.first;
    if (cornerFirst) {
      for (final c in _corners) {
        if (moves.contains(c)) return c;
      }
    }
    if (rng != null) moves.shuffle(rng);
    _sw = Stopwatch()..start();
    _limitMs = limitMs;
    var bestMove = moves.first;
    for (var d = 1; d <= maxDepth; d++) {
      _timeout = false;
      var alpha = -1 << 30;
      int? bm;
      final order = [bestMove, ...moves.where((m) => m != bestMove)];
      for (final m in order) {
        final nb = OthelloBoard.from(b.c)..play(m, color);
        final v = -_search(nb, 3 - color, d - 1, -(1 << 30), -alpha, color);
        if (_timeout) break;
        if (v > alpha || bm == null) {
          alpha = v;
          bm = m;
        }
      }
      if (_timeout) break;
      if (bm != null) bestMove = bm;
    }
    return bestMove;
  }

  /// Negamax from the perspective of side [color] to move.
  int _search(OthelloBoard b, int color, int depth, int alpha, int beta, int root) {
    if (_sw.elapsedMilliseconds > _limitMs) {
      _timeout = true;
      return 0;
    }
    final moves = b.legal(color);
    if (moves.isEmpty) {
      final opp = b.legal(3 - color);
      if (opp.isEmpty) {
        final d = b.count(color) - b.count(3 - color);
        return d * 10000;
      }
      return -_search(b, 3 - color, depth, -beta, -alpha, root);
    }
    if (depth <= 0) return _eval(b, color, moves.length);
    moves.sort((a, c) => _w[c].compareTo(_w[a]));
    for (final m in moves) {
      final nb = OthelloBoard.from(b.c)..play(m, color);
      final v = -_search(nb, 3 - color, depth - 1, -beta, -alpha, root);
      if (_timeout) return 0;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return alpha;
  }

  int _eval(OthelloBoard b, int color, int myMob) {
    final opp = 3 - color;
    var pos = 0;
    for (var p = 0; p < 64; p++) {
      final v = b.c[p];
      if (v == 0) continue;
      var w = _w[p];
      // X/C squares are fine once the corner is taken
      if (w < 0) {
        final ci = _nearCorner(p);
        if (ci >= 0 && b.c[_corners[ci]] != 0) w = 2;
      }
      pos += v == color ? w : -w;
    }
    final oppMob = b.legal(opp).length;
    final empties = b.c.where((v) => v == 0).length;
    final disc = b.count(color) - b.count(opp);
    return pos * 4 + (myMob - oppMob) * 8 + (empties < 12 ? disc * 6 : 0);
  }

  static int _nearCorner(int p) {
    for (var i = 0; i < 4; i++) {
      final c = _corners[i];
      final cx = c % 8, cy = c ~/ 8, x = p % 8, y = p ~/ 8;
      if ((cx - x).abs() <= 1 && (cy - y).abs() <= 1) return i;
    }
    return _xSq.contains(p) ? 0 : -1;
  }
}
