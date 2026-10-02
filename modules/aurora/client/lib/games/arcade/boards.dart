import '../../widgets/common.dart';
import 'battle2048_board.dart';
import 'minesweeper_board.dart';
import 'snake_board.dart';
import 'sudoku_board.dart';
import 'tetris_board.dart';

/// 俄罗斯方块/贪吃蛇/扫雷/2048/数独 对战
final Map<String, BoardBuilder> arcadeBoards = {
  'tetrisbattle': (g) => TetrisBoard(g),
  'snakebattle': (g) => SnakeBoard(g),
  'minesweeper': (g) => MinesweeperBoard(g),
  'battle2048': (g) => Battle2048Board(g),
  'sudokurace': (g) => SudokuBoard(g),
};
