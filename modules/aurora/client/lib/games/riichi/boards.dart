import '../../widgets/common.dart';
import 'board.dart';

/// 日本麻将 + 雀魂模式
final Map<String, BoardBuilder> riichiBoards = {
  for (final id in const [
    'riichi4',
    'riichi3',
    'majsoul_shura',
    'majsoul_wanxiang',
    'majsoul_mingjing',
    'majsoul_anye',
  ])
    id: (g) => RiichiBoard(g),
};
