import 'dart:math';
import '../games/arcade/sudoku.dart';
import '../games/arcade/battle2048.dart';
import '../games/party4/games.dart';
import 'engine.dart';

const dailyKinds = {
  'sudoku': '每日数独',
  'mines': '每日扫雷',
  '2048': '每日 2048',
  'lights': '每日熄灯',
};

/// Pure Dart puzzle logic. The server alone owns mines, solutions and the RNG.
class DailyPuzzle {
  final String kind;
  final Random rng;
  List<int> board = [], givens = [], solution = [], mines = [];
  final Set<int> revealed = {}, flagged = {};
  int moves = 0, mistakes = 0, score = 0;
  bool done = false, won = false;
  DailyPuzzle(this.kind, int seed) : rng = Random(seed) {
    if (!dailyKinds.containsKey(kind)) throw GameError('未知每日挑战');
    switch (kind) {
      case 'sudoku':
        final p = Sudoku.generate(rng, 42);
        board = List.of(p.$1);
        givens = List.of(p.$1);
        solution = p.$2;
      case 'mines':
        board = List.filled(36, 0);
        final cells = List.generate(
          36,
          (i) => i,
        ).where((i) => ![0, 1, 6, 7].contains(i)).toList()..shuffle(rng);
        mines = cells.take(6).toList();
        _reveal(0);
      case '2048':
        board = List.filled(16, 0);
        _spawn();
        _spawn();
      case 'lights':
        board = List.filled(16, 0);
        for (var i = 0; i < 16; i++) {
          if (rng.nextBool()) LightsOut.toggle(board, 4, i);
        }
        if (board.every((x) => x == 0)) LightsOut.toggle(board, 4, 0);
    }
  }
  List<int> neighbors(int i) => [
    for (var r = max(0, i ~/ 6 - 1); r <= min(5, i ~/ 6 + 1); r++)
      for (var c = max(0, i % 6 - 1); c <= min(5, i % 6 + 1); c++)
        if (r * 6 + c != i) r * 6 + c,
  ];
  void _reveal(int start) {
    final queue = [start];
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      if (revealed.contains(i) || mines.contains(i) || flagged.contains(i))
        continue;
      revealed.add(i);
      board[i] = neighbors(i).where(mines.contains).length;
      if (board[i] == 0)
        queue.addAll(neighbors(i).where((j) => !revealed.contains(j)));
    }
  }

  void _spawn() {
    final free = [
      for (var i = 0; i < 16; i++)
        if (board[i] == 0) i,
    ];
    if (free.isNotEmpty)
      board[free[rng.nextInt(free.length)]] = rng.nextInt(10) == 0 ? 4 : 2;
  }

  void act(Map<String, dynamic> a) {
    if (done) throw GameError('今日这次挑战已结束，可以重新练习');
    if (asInt(a['revision']) != moves) throw GameError('棋盘已更新，请重试');
    final i = asInt(a['cell']);
    if (kind != '2048' && (i < 0 || i >= board.length)) throw GameError('无效位置');
    switch (kind) {
      case 'sudoku':
        final digit = asInt(a['digit']);
        if (givens[i] != 0 || board[i] != 0 || digit < 1 || digit > 9)
          throw GameError('请选择空格与数字');
        if (digit == solution[i]) {
          board[i] = digit;
        } else {
          mistakes++;
        }
        won = board.every((x) => x != 0);
        done = won || mistakes >= 5;
        score = max(
          0,
          (List.generate(
                    81,
                    (j) => j,
                  ).where((j) => givens[j] == 0 && board[j] > 0).length *
                  10) -
              mistakes * 5,
        );
      case 'mines':
        if (revealed.contains(i)) throw GameError('这里已经翻开');
        if (a['flag'] == true) {
          if (!flagged.add(i)) flagged.remove(i);
        } else {
          if (flagged.contains(i)) throw GameError('请先取消标记');
          if (mines.contains(i)) {
            done = true;
          } else {
            _reveal(i);
          }
        }
        won = revealed.length == 30;
        done = done || won;
        score = revealed.length * 10;
      case '2048':
        final dir = asStr(a['dir']);
        if (!Battle2048.dirs.contains(dir)) throw GameError('无效方向');
        final r = Battle2048.move(board, dir);
        if (r == null) throw GameError('这个方向不能移动');
        board = r.$1;
        score += r.$2;
        _spawn();
        won = board.any((x) => x >= 2048);
        done = !Battle2048.canMove(board);
      case 'lights':
        LightsOut.toggle(board, 4, i);
        won = board.every((x) => x == 0);
        done = won;
        score = won ? max(1, 1000 - (moves + 1) * 10) : 0;
    }
    moves++;
    if (moves >= 500) done = true;
  }

  Map<String, dynamic> view() => {
    'kind': kind,
    'board': kind == 'mines'
        ? [
            for (var i = 0; i < 36; i++)
              if (done && mines.contains(i))
                -2
              else if (revealed.contains(i))
                board[i]
              else
                -1,
          ]
        : board,
    'givens': givens,
    'flagged': flagged.toList(),
    'moves': moves,
    'mistakes': mistakes,
    'score': score,
    'done': done,
    'won': won,
  };
}
