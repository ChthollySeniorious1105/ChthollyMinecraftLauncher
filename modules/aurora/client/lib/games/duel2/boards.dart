import '../../widgets/common.dart';
import 'banqi_board.dart';
import 'jaipur_board.dart';
import 'lostcities_board.dart';

/// 斋浦尔 / 失落的城市 / 暗棋
final Map<String, BoardBuilder> duel2Boards = {
  'jaipur': (g) => JaipurBoard(g),
  'lostcities': (g) => LostCitiesBoard(g),
  'banqi': (g) => BanqiBoard(g),
};
