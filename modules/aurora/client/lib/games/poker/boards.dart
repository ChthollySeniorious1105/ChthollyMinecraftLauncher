import '../../widgets/common.dart';
import 'cabo_board.dart';
import 'doudizhu_board.dart';
import 'exploding_board.dart';

/// 斗地主/爆炸猫/CABO
final Map<String, BoardBuilder> pokerBoards = {
  'doudizhu': (g) => DoudizhuBoard(g),
  'explodingkittens': (g) => ExplodingBoard(g),
  'cabo': (g) => CaboBoard(g),
};
