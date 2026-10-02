import '../../widgets/common.dart';
import 'chuiniu_board.dart';
import 'dicepoker_board.dart';
import 'farkle_board.dart';
import 'pig_board.dart';
import 'shidianban_board.dart';

/// 十点半 / 骰子扑克 / 猪骰 / 快乐骰 / 吹牛骰
final Map<String, BoardBuilder> dice2Boards = {
  'shidianban': (g) => ShiDianBanBoard(g),
  'dicepoker': (g) => DicePokerBoard(g),
  'pigdice': (g) => PigBoard(g),
  'farkle': (g) => FarkleBoard(g),
  'chuiniu': (g) => ChuiNiuBoard(g),
};
