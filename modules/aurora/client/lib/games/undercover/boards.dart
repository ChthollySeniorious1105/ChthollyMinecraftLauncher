import '../../widgets/common.dart';
import 'undercover_board.dart';

/// 谁是卧底
final Map<String, BoardBuilder> undercoverBoards = {
  'undercover': (g) => UndercoverBoard(g),
};
