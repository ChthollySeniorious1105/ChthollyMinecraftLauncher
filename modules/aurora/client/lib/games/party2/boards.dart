import '../../widgets/common.dart';
import 'bullscows_board.dart';
import 'decrypto_board.dart';
import 'halligalli_board.dart';
import 'turtlesoup_board.dart';

/// 德国心脏病/猜数字1A2B/海龟汤/截码战
final Map<String, BoardBuilder> party2Boards = {
  'halligalli': (g) => HalliGalliBoard(g),
  'bullscows': (g) => BullsCowsBoard(g),
  'turtlesoup': (g) => TurtleSoupBoard(g),
  'decrypto': (g) => DecryptoBoard(g),
};
