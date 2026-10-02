import '../../src/engine.dart';
import 'connect4.dart';
import 'dotsboxes.dart';
import 'draughts.dart';
import 'gomoku.dart';
import 'othello.dart';
import 'rules.dart';

/// 五子棋/黑白棋/四子棋/点格棋/国际跳棋
final List<GameDef> classicGames = [
  GameDef(
    id: 'gomoku',
    name: '五子棋',
    category: '棋类',
    description: '黑白轮流落子，先在横、竖、斜任一方向连成五子者胜。可选连珠禁手规则。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('size', '棋盘', [OptionChoice(15, '15 路'), OptionChoice(19, '19 路')], 15),
      OptionDef('rule', '规则', [
        OptionChoice('free', '自由（五连及以上）'),
        OptionChoice('standard', '标准（恰好五连）'),
        OptionChoice('renju', '连珠禁手（黑禁三三/四四/长连）'),
      ], 'free'),
    ],
    create: Gomoku.new,
    rules: gomokuRules,
    undo: true,
  ),
  GameDef(
    id: 'othello',
    name: '黑白棋',
    category: '棋类',
    description: '落子须夹住对方棋子并将其翻转，无处可下则停一手，终局子多者胜。',
    playerRange: (_) => (2, 2),
    create: Othello.new,
    rules: othelloRules,
    undo: true,
  ),
  GameDef(
    id: 'connect4',
    name: '四子棋',
    category: '棋类',
    description: '7 列 6 行竖直棋盘，棋子落到列底，先连成四子者胜。',
    playerRange: (_) => (2, 2),
    create: Connect4.new,
    rules: connect4Rules,
    undo: true,
  ),
  GameDef(
    id: 'dotsboxes',
    name: '点格棋',
    category: '棋类',
    description: '轮流在相邻两点间连线，围成一个格子得 1 分并再走一步，格子多者胜。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('size', '棋盘', [OptionChoice(3, '3×3 格'), OptionChoice(4, '4×4 格'), OptionChoice(5, '5×5 格')], 4),
    ],
    create: DotsBoxes.new,
    rules: dotsBoxesRules,
    undo: true,
  ),
  GameDef(
    id: 'draughts',
    name: '国际跳棋',
    category: '棋类',
    description: '斜走斜吃，有子必吃，兵到底线升王。国际规则：兵可后吃、王可飞行、须吃最多；英式规则：8×8、王只走一格。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('variant', '规则', [OptionChoice('intl', '国际 10×10'), OptionChoice('english', '英式 8×8')], 'intl'),
    ],
    create: Draughts.new,
    rules: draughtsRules,
    undo: true,
  ),
];
