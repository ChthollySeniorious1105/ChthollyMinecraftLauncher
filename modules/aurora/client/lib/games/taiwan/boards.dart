import '../../widgets/common.dart';
import 'tw_board.dart';

/// 台湾十六张麻将
final Map<String, BoardBuilder> taiwanBoards = {
  'taiwan16': (g) => TaiwanBoard(g),
};
