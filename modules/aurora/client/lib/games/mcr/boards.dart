import '../../widgets/common.dart';
import 'mcr_board.dart';

/// 国标麻将/广东推倒胡
final Map<String, BoardBuilder> mcrBoards = {
  'mcr': (g) => McrBoard(g),
  'guangdong': (g) => McrBoard(g),
};
