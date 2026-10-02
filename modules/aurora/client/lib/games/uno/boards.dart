import '../../widgets/common.dart';
import 'rummikub_board.dart';
import 'uno_board.dart';

/// UNO/拉密
final Map<String, BoardBuilder> unoBoards = {
  'uno': (g) => UnoBoard(g),
  'rummikub': (g) => RummikubBoard(g),
};
