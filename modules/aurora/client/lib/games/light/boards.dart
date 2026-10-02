import '../../widgets/common.dart';
import 'coup_board.dart';
import 'nothanks_board.dart';
import 'sixnimmt_board.dart';
import 'skull_board.dart';
import 'sushigo_board.dart';
import 'themind_board.dart';

/// 谁是牛头王 / No Thanks! / 寿司狗 / 政变 / 心灵同步 / 骷髅与玫瑰
final Map<String, BoardBuilder> lightBoards = {
  '6nimmt': (g) => SixNimmtBoard(g),
  'nothanks': (g) => NoThanksBoard(g),
  'sushigo': (g) => SushiGoBoard(g),
  'coup': (g) => CoupBoard(g),
  'themind': (g) => TheMindBoard(g),
  'skull': (g) => SkullBoard(g),
};
