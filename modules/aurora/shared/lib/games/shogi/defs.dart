import '../../src/engine.dart';
import 'jieqi_game.dart';
import 'rules.dart';
import 'shogi_game.dart';

/// 将棋/揭棋
final List<GameDef> shogiGames = [
  GameDef(
    id: 'shogi',
    name: '将棋',
    category: '棋类',
    description: '日本将棋：吃掉的棋子可以打入己方使用，进入敌阵可升变；禁二步、打步诘，将死对方玉将获胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('handicap', '让子', [
        OptionChoice(0, '平手'),
        OptionChoice(1, '让香'),
        OptionChoice(2, '让角'),
        OptionChoice(3, '让飞'),
        OptionChoice(4, '让二枚（飞角）'),
      ], 0),
    ],
    rules: shogiRulesText,
    undo: true,
    create: ShogiGame.new,
  ),
  GameDef(
    id: 'jieqi',
    name: '揭棋',
    category: '棋类',
    description: '暗子象棋：除帅将外全部棋子背面朝上随机摆放，按所在位置的兵种走第一步并翻开，之后按真实身份行棋；仕相翻开后可出宫过河。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('publicCaptures', '被吃暗子', [OptionChoice(false, '仅吃子方可见'), OptionChoice(true, '公开')], false),
    ],
    rules: jieqiRulesText,
    create: JieqiGame.new,
  ),
];
