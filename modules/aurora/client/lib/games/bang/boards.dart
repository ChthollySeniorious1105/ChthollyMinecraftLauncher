import '../../widgets/common.dart';
import 'bang_board.dart';
import 'cockroach_board.dart';

/// 蟑螂扑克 / 西部无间道
final Map<String, BoardBuilder> bangBoards = {
  'cockroach': (g) => CockroachBoard(g),
  'bang': (g) => BangBoard(g),
};
