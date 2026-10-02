import '../../widgets/common.dart';
import 'm2_board.dart';

/// 长沙麻将 / 二人麻将
final Map<String, BoardBuilder> mahjong2Boards = {
  'changsha': (g) => M2Board(g),
  'mahjong2p': (g) => M2Board(g),
};
