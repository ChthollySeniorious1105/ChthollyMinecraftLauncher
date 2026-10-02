import '../../widgets/common.dart';
import 'chess_board.dart';
import 'go_board.dart';
import 'xiangqi_board.dart';

/// 围棋/国际象棋/中国象棋/军棋/斗兽棋
final Map<String, BoardBuilder> chessBoards = {
  'go': (g) => GoBoardView(g),
  'chess': (g) => ChessBoard(g),
  'xiangqi': (g) => XiangqiBoard(g),
};
