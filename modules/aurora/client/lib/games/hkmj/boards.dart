import '../../widgets/common.dart';
import 'hk_board.dart';

/// 港式麻将
final Map<String, BoardBuilder> hkmjBoards = {
  'hkmj': (g) => HkBoard(g),
};
