import '../../widgets/common.dart';
import 'blackjack_board.dart';
import 'holdem_board.dart';
import 'paodekuai_board.dart';

/// 德州扑克/21点/跑得快
final Map<String, BoardBuilder> pokerplusBoards = {
  'texasholdem': (g) => HoldemBoard(g),
  'blackjack': (g) => BlackjackBoard(g),
  'paodekuai': (g) => PaodekuaiBoard(g),
};
