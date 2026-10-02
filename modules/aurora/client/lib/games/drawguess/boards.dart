import '../../widgets/common.dart';
import 'drawguess_board.dart';
import 'telephone_board.dart';

/// 你画我猜 / 传话画画
final Map<String, BoardBuilder> drawguessBoards = {
  'drawguess': (g) => DrawGuessBoard(g),
  'telephone': (g) => TelephoneBoard(g),
};
