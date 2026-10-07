import '../../widgets/common.dart';
import 'gofish_board.dart';
import 'oldmaid_board.dart';
import 'sevens_board.dart';

/// 抽乌龟 / 钓鱼 / 牌七
final Map<String, BoardBuilder> familyBoards = {
  'oldmaid': (g) => OldMaidBoard(g),
  'gofish': (g) => GoFishBoard(g),
  'sevens': (g) => SevensBoard(g),
};
