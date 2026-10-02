import '../../widgets/common.dart';
import 'carcassonne_board.dart';
import 'hanabi_board.dart';

/// 卡卡颂/花火
final Map<String, BoardBuilder> euroBoards = {
  'carcassonne': (g) => CarcassonneBoard(g),
  'hanabi': (g) => HanabiBoard(g),
};
