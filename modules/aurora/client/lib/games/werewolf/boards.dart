import '../../widgets/common.dart';
import 'werewolf_board.dart';

/// 狼人杀
final Map<String, BoardBuilder> werewolfBoards = {
  'werewolf': (g) => WerewolfBoard(g),
};
