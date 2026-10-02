import '../../widgets/common.dart';
import 'baccarat_board.dart';
import 'gongzhu_board.dart';
import 'shed_games.dart';

/// 干瞪眼/五十K/争上游/拱猪/百家乐
final Map<String, BoardBuilder> cards3Boards = {
  'gandengyan': gandengyanBoard,
  'wushik': wushikBoard,
  'zhengshangyou': zhengshangyouBoard,
  'gongzhu': (g) => GongzhuBoard(g),
  'baccarat': (g) => BaccaratBoard(g),
};
