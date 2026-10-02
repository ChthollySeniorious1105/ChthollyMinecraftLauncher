import '../../widgets/common.dart';
import 'guandan_board.dart';
import 'shengji_board.dart';

/// 掼蛋/升级(拖拉机)
final Map<String, BoardBuilder> teamcardsBoards = {
  'guandan': (g) => GuandanBoard(g),
  'shengji': (g) => ShengjiBoard(g),
};
