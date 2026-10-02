import '../../widgets/common.dart';
import 'monopoly_board.dart';

/// 大富翁
final Map<String, BoardBuilder> monopolyBoards = {
  'monopoly': (g) => MonopolyBoard(g),
};
