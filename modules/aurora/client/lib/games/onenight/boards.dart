import '../../widgets/common.dart';
import 'onenight_board.dart';
import 'resistance_board.dart';
import 'spyfall_board.dart';

/// 一夜终极狼人/抵抗组织/谁是间谍
final Map<String, BoardBuilder> onenightBoards = {
  'onenight': (g) => OneNightBoard(g),
  'resistance': (g) => ResistanceBoard(g),
  'spyfall': (g) => SpyfallBoard(g),
};
