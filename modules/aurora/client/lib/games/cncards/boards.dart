import '../../widgets/common.dart';
import 'bigtwo_board.dart';
import 'douniu_board.dart';
import 'shisanshui_board.dart';
import 'zhajinhua_board.dart';

/// 锄大地/炸金花/斗牛/十三水
final Map<String, BoardBuilder> cncardsBoards = {
  'bigtwo': (g) => BigTwoBoard(g),
  'zhajinhua': (g) => ZhajinhuaBoard(g),
  'douniu': (g) => DouniuBoard(g),
  'shisanshui': (g) => ShisanshuiBoard(g),
};
