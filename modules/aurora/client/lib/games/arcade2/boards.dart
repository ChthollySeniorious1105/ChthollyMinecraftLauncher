import '../../widgets/common.dart';
import 'bomberman_board.dart';
import 'dobble_board.dart';

/// 炸弹人 / 眼疾手快
final Map<String, BoardBuilder> arcade2Boards = {
  'bomberman': (g) => BombermanBoard(g),
  'dobble': (g) => DobbleBoard(g),
};
