import '../../src/engine.dart';

/// 井字棋 — reference implementation of the GameEngine contract.
class TicTacToe extends GameEngine {
  TicTacToe(super.setup);

  final List<int> cells = List.filled(9, -1);
  int turn = 0;
  int winner = -1; // -1 none, 0/1 seat, 2 draw
  List<int> line = [];

  /// How the game ended early: '' normal, 'resign', 'draw' (agreed).
  String endReason = '';

  static const _lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  @override
  void start() {
    turn = rng.nextInt(2);
    host.log('${name(turn)} 执 ${turn == 0 ? "X" : "O"} 先手');
  }

  @override
  bool get isOver => winner != -1;

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  @override
  List<int>? get placings => !isOver ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat > 1) return;
    winner = 1 - seat;
    endReason = 'resign';
    host.log('${name(seat)} 认输');
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) return;
    winner = 2;
    endReason = 'draw';
    host.log('双方同意和棋');
  }

  @override
  void handle(int seat, Map<String, dynamic> action) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final i = asInt(action['cell']);
    if (i < 0 || i > 8 || cells[i] != -1) throw GameError('无效位置');
    cells[i] = seat;
    for (final l in _lines) {
      if (l.every((c) => cells[c] == seat)) {
        winner = seat;
        line = l;
        host.log('${name(seat)} 获胜！');
        return;
      }
    }
    if (!cells.contains(-1)) {
      winner = 2;
      host.log('平局');
      return;
    }
    turn = 1 - turn;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'cells': cells,
        'turn': turn,
        'winner': winner,
        'line': line,
        'over': isOver,
        'end': endReason,
      };

  int? _lineWin(List<int> b) {
    for (final l in _lines) {
      final v = b[l[0]];
      if (v >= 0 && b[l[1]] == v && b[l[2]] == v) return v;
    }
    return null;
  }

  /// Negamax score for [who] to move on [b]: +1 win, 0 draw, -1 loss.
  int _negamax(List<int> b, int who) {
    final w = _lineWin(b);
    if (w != null) return w == who ? 1 : -1;
    if (!b.contains(-1)) return 0;
    var best = -2;
    for (var i = 0; i < 9; i++) {
      if (b[i] != -1) continue;
      b[i] = who;
      final s = -_negamax(b, 1 - who);
      b[i] = -1;
      if (s > best) best = s;
      if (best == 1) break;
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final free = [for (var i = 0; i < 9; i++) if (cells[i] == -1) i]..shuffle(rng);
    if (free.isEmpty) return null;
    // 简单: often just a random square
    if (botLevel <= 0 && rng.nextDouble() < 0.5) return {'cell': free.first};
    if (botLevel >= 2) {
      // 困难: perfect play (full negamax, 9! at most — instant)
      final b = List.of(cells);
      var best = free.first, bs = -2;
      for (final i in free) {
        b[i] = seat;
        final s = -_negamax(b, 1 - seat);
        b[i] = -1;
        if (s > bs) {
          bs = s;
          best = i;
        }
      }
      return {'cell': best};
    }
    // 普通: win > block > center > random
    int? find(int who) {
      for (final l in _lines) {
        final mine = l.where((c) => cells[c] == who).length;
        final empty = l.where((c) => cells[c] == -1).toList();
        if (mine == 2 && empty.length == 1) return empty.first;
      }
      return null;
    }

    return {'cell': find(seat) ?? find(1 - seat) ?? (cells[4] == -1 ? 4 : free.first)};
  }
}
