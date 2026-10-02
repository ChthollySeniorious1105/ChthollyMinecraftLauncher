import '../../widgets/common.dart';
import 'connect4_board.dart';
import 'dotsboxes_board.dart';
import 'draughts_board.dart';
import 'gomoku_board.dart';
import 'othello_board.dart';

/// 五子棋/黑白棋/四子棋/点格棋/国际跳棋
final Map<String, BoardBuilder> classicBoards = {
  'gomoku': (g) => GomokuBoardView(g),
  'othello': (g) => OthelloBoardView(g),
  'connect4': (g) => Connect4BoardView(g),
  'dotsboxes': (g) => DotsBoxesBoardView(g),
  'draughts': (g) => DraughtsBoardView(g),
};
