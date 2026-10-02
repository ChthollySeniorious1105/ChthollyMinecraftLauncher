import '../../widgets/common.dart';
import 'azul_board.dart';
import 'duel_board.dart';
import 'kingdomino_board.dart';
import 'patchwork_board.dart';

/// 花砖物语 / 王国骨牌 / 拼布艺术 / 七大奇迹·对决
final Map<String, BoardBuilder> euro2Boards = {
  'azul': (g) => AzulBoard(g),
  'kingdomino': (g) => KingdominoBoard(g),
  'patchwork': (g) => PatchworkBoard(g),
  '7wonders_duel': (g) => DuelBoard(g),
};
