import '../../src/engine.dart';
import 'chess_game.dart';
import 'go_game.dart';
import 'rules.dart';
import 'xiangqi_game.dart';

/// 围棋/国际象棋/中国象棋/军棋/斗兽棋
final List<GameDef> chessGames = [
  GameDef(
    id: 'go',
    name: '围棋',
    category: '棋类',
    description: '黑白交替落子围地，提子、打劫、禁自杀；双方停着后数子（中国规则），子多者胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('size', '棋盘', [OptionChoice(19, '19 路'), OptionChoice(13, '13 路'), OptionChoice(9, '9 路')], 19),
      OptionDef('komi', '贴目', [OptionChoice('7.5', '7.5 目（中国）'), OptionChoice('6.5', '6.5 目（日韩）'), OptionChoice('0.5', '0.5 目')], '7.5'),
      OptionDef('handicap', '让子', [
        OptionChoice(0, '不让子'),
        OptionChoice(2, '让 2 子'),
        OptionChoice(3, '让 3 子'),
        OptionChoice(4, '让 4 子'),
        OptionChoice(5, '让 5 子'),
        OptionChoice(6, '让 6 子'),
        OptionChoice(7, '让 7 子'),
        OptionChoice(8, '让 8 子'),
        OptionChoice(9, '让 9 子'),
      ], 0),
    ],
    rules: goRules,
    undo: true,
    create: GoGame.new,
  ),
  GameDef(
    id: 'chess',
    name: '国际象棋',
    category: '棋类',
    description: '完整国际象棋规则：王车易位、吃过路兵、升变、将杀、逼和、50 回合与三次重复和棋。',
    playerRange: (_) => (2, 2),
    rules: chessRules,
    undo: true,
    create: ChessGame.new,
  ),
  GameDef(
    id: 'xiangqi',
    name: '中国象棋',
    category: '棋类',
    description: '楚河汉界，红先黑后；马蹩腿、象塞眼、炮隔山、将帅不照面，将死或困毙对方获胜。',
    playerRange: (_) => (2, 2),
    rules: xiangqiRules,
    undo: true,
    create: XiangqiGame.new,
  ),
];
