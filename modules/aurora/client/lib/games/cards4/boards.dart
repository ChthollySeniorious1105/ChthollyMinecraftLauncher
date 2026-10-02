import '../../widgets/common.dart';
import 'ginrummy_board.dart';
import 'shed_games.dart';

/// 够级 / 保皇 / 双扣 / Gin Rummy
final Map<String, BoardBuilder> cards4Boards = {
  'gouji': goujiBoard,
  'baohuang': baohuangBoard,
  'shuangkou': shuangkouBoard,
  'ginrummy': (g) => GinRummyBoard(g),
};
