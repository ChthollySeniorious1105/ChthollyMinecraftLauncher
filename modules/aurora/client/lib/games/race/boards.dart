import '../../widgets/common.dart';
import 'battleship_board.dart';
import 'checkers_board.dart';
import 'davinci_board.dart';
import 'ludo_board.dart';
import 'quoridor_board.dart';
import 'tictactoe_board.dart';

/// 井字棋/飞行棋/跳棋/路墙棋/炸飞机/达芬奇密码
final Map<String, BoardBuilder> raceBoards = {
  'tictactoe': (g) => TicTacToeBoard(g),
  'ludo': (g) => LudoBoard(g),
  'chinesecheckers': (g) => CheckersBoard(g),
  'quoridor': (g) => QuoridorBoard(g),
  'battleship': (g) => BattleshipBoard(g),
  'davinci': (g) => DaVinciBoard(g),
};
