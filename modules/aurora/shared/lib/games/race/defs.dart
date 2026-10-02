import '../../src/engine.dart';
import 'battleship.dart';
import 'checkers.dart';
import 'davinci.dart';
import 'ludo.dart';
import 'quoridor.dart';
import 'rules.dart';
import 'tictactoe.dart';

/// 井字棋/飞行棋/跳棋/路墙棋/炸飞机/达芬奇密码
final List<GameDef> raceGames = [
  GameDef(
    id: 'tictactoe',
    name: '井字棋',
    category: '棋类',
    description: '3×3 棋盘，先连成一线者胜。',
    playerRange: (_) => (2, 2),
    create: TicTacToe.new,
    rules: tictactoeRules,
    undo: true,
  ),
  GameDef(
    id: 'ludo',
    name: '飞行棋',
    category: '桌游',
    description: '掷骰起飞，同色跳格、飞越捷径、撞落对手，率先让四架飞机全部到达终点者胜。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('launch', '起飞点数', [OptionChoice(6, '仅6起飞'), OptionChoice(5, '5或6起飞')], 6),
      OptionDef('bounce', '到达终点', [OptionChoice(true, '需要精确点数（多余倒退）'), OptionChoice(false, '点数超出也算到达')], true),
      OptionDef('triple6', '连掷三个6', [OptionChoice(true, '本轮作废'), OptionChoice(false, '无限制')], true),
    ],
    create: Ludo.new,
    rules: ludoRules,
  ),
  GameDef(
    id: 'chinesecheckers',
    name: '跳棋',
    category: '棋类',
    description: '六角星棋盘，一步走或连续跳跃，先把全部 10 颗棋子移到对面营地者胜。',
    playerRange: (_) => (2, 6),
    create: ChineseCheckers.new,
    rules: chineseCheckersRules,
    undo: true,
  ),
  GameDef(
    id: 'quoridor',
    name: '路墙棋',
    category: '棋类',
    description: '9×9 棋盘，移动棋子或放置墙挡路（不能完全堵死），先到达对边者胜。2 人各 10 墙，3 人各 7 墙，4 人各 5 墙。',
    playerRange: (_) => (2, 4),
    create: Quoridor.new,
    rules: quoridorRules,
    undo: true,
  ),
  GameDef(
    id: 'battleship',
    name: '炸飞机',
    category: '桌游',
    description: '在 10×10 格中秘密布置飞机，轮流轰炸：空/伤/毁，先炸毁对方所有飞机机头者胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('planes', '飞机数', [OptionChoice(3, '3 架'), OptionChoice(2, '2 架')], 3),
    ],
    create: Battleship.new,
    rules: battleshipRules,
  ),
  GameDef(
    id: 'davinci',
    name: '达芬奇密码',
    category: '桌游',
    description: '黑白数字牌按大小排列，轮流摸牌并猜测对手的暗牌，最后保有暗牌的玩家获胜。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('joker', '百搭牌', [OptionChoice(false, '不使用'), OptionChoice(true, '使用（黑白各一张 -）')], false),
    ],
    create: DaVinci.new,
    rules: davinciRules,
  ),
];
