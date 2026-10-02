import '../../widgets/common.dart';
import 'avalon_board.dart';
import 'catan_board.dart';
import 'codenames_board.dart';
import 'codenames_duet_board.dart';

/// 卡坦岛/阿瓦隆/行动代号
final Map<String, BoardBuilder> socialBoards = {
  'catan': (g) => CatanBoard(g),
  'avalon': (g) => AvalonBoard(g),
  'codenames': (g) => CodenamesBoard(g),
  'codenames_duet': (g) => CodenamesDuetBoard(g),
};
