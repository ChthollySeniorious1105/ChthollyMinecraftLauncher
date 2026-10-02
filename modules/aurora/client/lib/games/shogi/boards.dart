import '../../widgets/common.dart';
import 'jieqi_board.dart';
import 'shogi_board.dart';

/// 将棋/揭棋
final Map<String, BoardBuilder> shogiBoards = {
  'shogi': (g) => ShogiBoard(g),
  'jieqi': (g) => JieqiBoard(g),
};
