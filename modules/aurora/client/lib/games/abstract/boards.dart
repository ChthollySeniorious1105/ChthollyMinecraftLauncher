import '../../widgets/common.dart';
import 'backgammon_board.dart';
import 'connect6_board.dart';
import 'hex_board.dart';
import 'mancala_board.dart';
import 'ninemen_board.dart';

/// 西洋双陆/曼卡拉/六子棋/六角棋/九子棋
final Map<String, BoardBuilder> abstractBoards = {
  'backgammon': (g) => BackgammonBoardView(g),
  'mancala': (g) => MancalaBoardView(g),
  'connect6': (g) => Connect6BoardView(g),
  'hex': (g) => HexBoardView(g),
  'ninemen': (g) => NineMenBoardView(g),
};
