import '../../widgets/common.dart';
import 'sichuan_board.dart';

/// 四川麻将
final Map<String, BoardBuilder> sichuanBoards = {
  'sichuan': (g) => SichuanBoard(g),
};
