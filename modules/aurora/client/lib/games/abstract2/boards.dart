import '../../widgets/common.dart';
import 'blokus_board.dart';
import 'hive_board.dart';
import 'onitama_board.dart';
import 'quarto_board.dart';

/// 蜂巢 / 格格不入 / 师徒棋 / Quarto
final Map<String, BoardBuilder> abstract2Boards = {
  'hive': (g) => HiveBoardView(g),
  'blokus': (g) => BlokusBoardView(g),
  'onitama': (g) => OnitamaBoardView(g),
  'quarto': (g) => QuartoBoardView(g),
};
