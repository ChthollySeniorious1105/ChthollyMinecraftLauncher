import '../../widgets/common.dart';
import 'liarsbar_board.dart';
import 'loveletter_board.dart';
import 'splendor_board.dart';
import 'yahtzee_board.dart';

/// 情书/快艇骰子/璀璨宝石/骗子酒馆
final Map<String, BoardBuilder> tabletopBoards = {
  'loveletter': (g) => LoveLetterBoard(g),
  'yahtzee': (g) => YahtzeeBoard(g),
  'splendor': (g) => SplendorBoard(g),
  'liarsbar': (g) => LiarsBarBoard(g),
};
