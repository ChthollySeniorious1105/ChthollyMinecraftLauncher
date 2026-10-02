import '../../widgets/common.dart';
import 'animalchess_board.dart';
import 'junqi_board.dart';

/// 军棋/斗兽棋
final Map<String, BoardBuilder> militaryBoards = {
  'junqi': (g) => JunqiBoard(g),
  'animalchess': (g) => AnimalChessBoard(g),
};
