import '../../src/engine.dart';

/// Quarto 四连棋。棋子 0..15 的四个二进制位代表四种属性：
/// bit0 高/矮，bit1 深/浅，bit2 方/圆，bit3 空心/实心。
class QuartoRules {
  static const attrNames = [
    ['矮', '高'],
    ['浅色', '深色'],
    ['圆', '方'],
    ['实心', '空心'],
  ];

  static String pieceName(int p) =>
      '${attrNames[0][p & 1]}${attrNames[1][(p >> 1) & 1]}${attrNames[2][(p >> 2) & 1]}${attrNames[3][(p >> 3) & 1]}';

  static final List<List<int>> _rows = [
    for (var y = 0; y < 4; y++) [for (var x = 0; x < 4; x++) y * 4 + x],
    for (var x = 0; x < 4; x++) [for (var y = 0; y < 4; y++) y * 4 + x],
    [0, 5, 10, 15],
    [3, 6, 9, 12],
  ];
  static final List<List<int>> _squares = [
    for (var y = 0; y < 3; y++)
      for (var x = 0; x < 3; x++) [y * 4 + x, y * 4 + x + 1, y * 4 + x + 4, y * 4 + x + 5],
  ];

  static List<List<int>> lines(bool squares) => squares ? [..._rows, ..._squares] : _rows;

  /// Lines through each cell (precomputed).
  static final List<List<List<int>>> _through = [
    for (var c = 0; c < 16; c++) [for (final l in _rows) if (l.contains(c)) l]
  ];
  static final List<List<List<int>>> _throughSq = [
    for (var c = 0; c < 16; c++) [for (final l in [..._rows, ..._squares]) if (l.contains(c)) l]
  ];

  /// Shared attribute mask of a full line (bits set = shared "1" attribute,
  /// bits 4..7 = shared "0" attribute), 0 = none / not full.
  static int sharedMask(List<int> board, List<int> line) {
    var and = 15, nor = 15;
    for (final c in line) {
      final p = board[c];
      if (p < 0) return 0;
      and &= p;
      nor &= ~p & 15;
    }
    return and | (nor << 4);
  }

  /// A winning line through [cell] or null.
  static List<int>? winThrough(List<int> board, int cell, bool squares) {
    for (final l in (squares ? _throughSq : _through)[cell]) {
      if (sharedMask(board, l) != 0) return l;
    }
    return null;
  }

  static String sharedText(int mask) {
    final out = <String>[];
    for (var i = 0; i < 4; i++) {
      if (mask & (1 << i) != 0) out.add(attrNames[i][1]);
      if (mask & (1 << (i + 4)) != 0) out.add(attrNames[i][0]);
    }
    return out.join('、');
  }
}

/// Minimax 搜索（带 alpha-beta 与时间限制）。
class QuartoAI {
  final bool squares;
  final Stopwatch _sw = Stopwatch();
  int _limit = 300;
  bool _timeout = false;
  QuartoAI(this.squares);

  bool _winsWith(List<int> b, int piece) {
    for (var c = 0; c < 16; c++) {
      if (b[c] >= 0) continue;
      b[c] = piece;
      final w = QuartoRules.winThrough(b, c, squares) != null;
      b[c] = -1;
      if (w) return true;
    }
    return false;
  }

  /// Negamax for the player about to place [piece]. Returns score.
  int _search(List<int> b, int piece, int avail, int depth, int alpha, int beta) {
    if (_sw.elapsedMilliseconds > _limit) {
      _timeout = true;
      return 0;
    }
    final empties = [for (var c = 0; c < 16; c++) if (b[c] < 0) c];
    // immediate win
    for (final c in empties) {
      b[c] = piece;
      final w = QuartoRules.winThrough(b, c, squares) != null;
      b[c] = -1;
      if (w) return 1000 + empties.length;
    }
    if (avail == 0) return 0; // board full after this placement: draw
    if (depth <= 0) return 0;
    var best = -100000;
    for (final c in empties) {
      b[c] = piece;
      var anySafe = false;
      for (var g = 0; g < 16; g++) {
        if (avail & (1 << g) == 0) continue;
        if (_winsWith(b, g)) continue;
        anySafe = true;
        final v = -_search(b, g, avail & ~(1 << g), depth - 1, -beta, -alpha);
        if (_timeout) {
          b[c] = -1;
          return 0;
        }
        if (v > best) best = v;
        if (v > alpha) alpha = v;
        if (alpha >= beta) break;
      }
      if (!anySafe) {
        // every piece we could give lets the opponent win
        final v = -(1000 + empties.length - 1);
        if (v > best) best = v;
      }
      b[c] = -1;
      if (alpha >= beta) break;
    }
    return best;
  }

  /// Best (cell, give) for the player holding [piece]; give = -1 if the game ends.
  (int, int) bestPlace(List<int> board, int piece, int avail, {int maxDepth = 3, int limitMs = 300}) {
    final b = List.of(board);
    _limit = limitMs;
    _sw
      ..reset()
      ..start();
    final empties = [for (var c = 0; c < 16; c++) if (b[c] < 0) c];
    for (final c in empties) {
      b[c] = piece;
      final w = QuartoRules.winThrough(b, c, squares) != null;
      b[c] = -1;
      if (w) return (c, -1);
    }
    if (avail == 0) return (empties.first, -1);
    var best = (empties.first, _firstBit(avail));
    // safe fallback first
    outer:
    for (final c in empties) {
      b[c] = piece;
      for (var g = 0; g < 16; g++) {
        if (avail & (1 << g) != 0 && !_winsWith(b, g)) {
          best = (c, g);
          b[c] = -1;
          break outer;
        }
      }
      b[c] = -1;
    }
    for (var d = 1; d <= maxDepth; d++) {
      _timeout = false;
      var alpha = -100000;
      (int, int)? bm;
      for (final c in empties) {
        b[c] = piece;
        for (var g = 0; g < 16; g++) {
          if (avail & (1 << g) == 0) continue;
          if (_winsWith(b, g)) continue;
          final v = -_search(b, g, avail & ~(1 << g), d - 1, -100000, -alpha);
          if (_timeout) break;
          if (v > alpha || bm == null) {
            alpha = v;
            bm = (c, g);
          }
        }
        b[c] = -1;
        if (_timeout) break;
      }
      if (_timeout) break;
      if (bm != null) best = bm;
      if (alpha >= 1000) break;
    }
    return best;
  }

  /// Best piece to give at the very first move (nothing on board): any.
  static int _firstBit(int m) {
    for (var i = 0; i < 16; i++) {
      if (m & (1 << i) != 0) return i;
    }
    return -1;
  }

  /// Score (for the player about to place [piece]) of the position.
  int scoreFor(List<int> board, int piece, int avail, int depth, int limitMs) {
    _limit = limitMs;
    _sw
      ..reset()
      ..start();
    _timeout = false;
    final v = _search(List.of(board), piece, avail, depth, -100000, 100000);
    return _timeout ? 0 : v;
  }

  List<int> safeGives(List<int> board, int avail) =>
      [for (var g = 0; g < 16; g++) if (avail & (1 << g) != 0 && !_winsWith(List.of(board), g)) g];

  bool winsWith(List<int> board, int piece) => _winsWith(List.of(board), piece);
}

class Quarto extends GameEngine {
  Quarto(super.setup);

  List<int> board = List.filled(16, -1);
  int avail = 0xFFFF;
  int hand = -1; // piece the current player must place
  String phase = 'give'; // give | place | over
  int turn = 0; // seat to act
  int firstSeat = 0;
  int last = -1;
  List<int> winLine = [];
  int winner = -1; // seat, 2 = draw
  String result = '';
  String lastText = '';
  int moves = 0;

  bool get squares => setup.opt<bool>('squares', false);
  bool get over => phase == 'over';

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    firstSeat = rng.nextInt(2);
    turn = firstSeat;
    host.log('Quarto：${name(firstSeat)} 先为对手挑选棋子');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') return resign(seat);
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    if (seat != turn) throw GameError('还没轮到你');
    final type = a['type'];
    if (phase == 'give') {
      if (type != 'give') throw GameError('现在需要为对手挑选一枚棋子');
      final p = asInt(a['piece']);
      if (p < 0 || p > 15 || avail & (1 << p) == 0) throw GameError('这枚棋子不可用');
      avail &= ~(1 << p);
      hand = p;
      turn = 1 - turn;
      phase = 'place';
      lastText = '${name(seat)} 把「${QuartoRules.pieceName(p)}」交给 ${name(turn)}';
      return;
    }
    if (type != 'place') throw GameError('请先把手中的棋子放到棋盘上');
    final c = asInt(a['cell']);
    if (c < 0 || c > 15 || board[c] >= 0) throw GameError('这里不能放');
    board[c] = hand;
    last = c;
    moves++;
    final placed = hand;
    hand = -1;
    lastText = '${name(seat)} 把「${QuartoRules.pieceName(placed)}」放在 ${_cellName(c)}';
    final w = QuartoRules.winThrough(board, c, squares);
    if (w != null) {
      winLine = w;
      winner = seat;
      phase = 'over';
      result = '${name(seat)} 连成 Quarto（共同属性：${QuartoRules.sharedText(QuartoRules.sharedMask(board, w))}）获胜';
      host.log(result);
      return;
    }
    if (avail == 0) {
      winner = 2;
      phase = 'over';
      result = '棋盘已满，和棋';
      host.log(result);
      return;
    }
    phase = 'give';
  }

  static String _cellName(int c) => '${String.fromCharCode(65 + c % 4)}${c ~/ 4 + 1}';

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    winner = 1 - seat;
    phase = 'over';
    result = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;
  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    winner = 2;
    phase = 'over';
    result = '双方同意和棋';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'board': board,
        'avail': [for (var p = 0; p < 16; p++) if (avail & (1 << p) != 0) p],
        'hand': hand,
        'phase': phase,
        'turn': turn,
        'firstSeat': firstSeat,
        'last': last,
        'winLine': winLine,
        'winner': winner,
        'result': result,
        'lastText': lastText,
        'squares': squares,
        'moves': moves,
        'over': over,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final ai = QuartoAI(squares);
    final lvl = botLevel;
    if (phase == 'give') {
      final all = [for (var p = 0; p < 16; p++) if (avail & (1 << p) != 0) p];
      final safe = ai.safeGives(board, avail);
      if (lvl == 0) {
        final pool = safe.isNotEmpty && rng.nextDouble() < 0.6 ? safe : all;
        return {'type': 'give', 'piece': pool[rng.nextInt(pool.length)]};
      }
      if (safe.isEmpty) return {'type': 'give', 'piece': all[rng.nextInt(all.length)]};
      // Opening: nothing to think about.
      if (moves < 3 || lvl == 1 && moves < 5) return {'type': 'give', 'piece': safe[rng.nextInt(safe.length)]};
      // Choose the give that minimises the opponent's best reply.
      var best = safe.first;
      var bestV = 1 << 30;
      final sw = Stopwatch()..start();
      final limit = lvl >= 2 ? 900 : 250;
      for (final g in safe) {
        final left = avail & ~(1 << g);
        final per = ((limit - sw.elapsedMilliseconds) ~/ (safe.length)).clamp(20, 400);
        final v = QuartoAI(squares).scoreFor(board, g, left, lvl >= 2 ? 4 : 2, per);
        if (v < bestV) {
          bestV = v;
          best = g;
        }
      }
      return {'type': 'give', 'piece': best};
    }
    // place
    final empties = [for (var c = 0; c < 16; c++) if (board[c] < 0) c];
    if (lvl == 0 && rng.nextDouble() < 0.5) {
      // still takes an obvious win half the time
      return {'type': 'place', 'cell': empties[rng.nextInt(empties.length)]};
    }
    final (c, _) = moves < 4 && lvl < 2
        ? _cheapPlace(ai, empties)
        : ai.bestPlace(board, hand, avail, maxDepth: lvl >= 2 ? 5 : 2, limitMs: lvl >= 2 ? 900 : 250);
    return {'type': 'place', 'cell': c};
  }

  (int, int) _cheapPlace(QuartoAI ai, List<int> empties) {
    final b = List.of(board);
    for (final c in empties) {
      b[c] = hand;
      if (QuartoRules.winThrough(b, c, squares) != null) return (c, -1);
      b[c] = -1;
    }
    // prefer a cell that keeps safe gives available
    final order = shuffled(empties, rng);
    for (final c in order) {
      b[c] = hand;
      final ok = ai.safeGives(b, avail).isNotEmpty;
      b[c] = -1;
      if (ok) return (c, -1);
    }
    return (order.first, -1);
  }
}
