import '../../widgets/common.dart';
import 'bridge_board.dart';
import 'hearts_board.dart';
import 'spades_board.dart';

/// 桥牌/红心大战/黑桃王
final Map<String, BoardBuilder> tricksBoards = {
  'bridge': (g) => BridgeBoard(g),
  'hearts': (g) => HeartsBoard(g),
  'spades': (g) => SpadesBoard(g),
};
