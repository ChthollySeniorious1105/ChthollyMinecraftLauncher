import '../../src/engine.dart';
import 'backgammon.dart';
import 'connect6.dart';
import 'hex.dart';
import 'mancala.dart';
import 'ninemen.dart';
import 'rules.dart';

const _onOff = [OptionChoice(true, '开启'), OptionChoice(false, '关闭')];

/// 西洋双陆/曼卡拉/六子棋/六角棋/九子棋
final List<GameDef> abstractGames = [
  GameDef(
    id: 'backgammon',
    name: '西洋双陆',
    category: '桌游',
    description: '掷骰移动15枚棋子绕盘一周并全部移出，可打散子、用加倍骰加注，先达目标分者胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('match', '比赛分数', [
        OptionChoice(1, '1 分'),
        OptionChoice(3, '3 分'),
        OptionChoice(5, '5 分'),
        OptionChoice(7, '7 分'),
      ], 3),
      OptionDef('cube', '加倍骰', _onOff, true),
      OptionDef('crawford', '克劳福德规则', _onOff, true),
    ],
    create: Backgammon.new,
    rules: backgammonRules,
  ),
  GameDef(
    id: 'mancala',
    name: '曼卡拉',
    category: '棋类',
    description: '播种石子：最后一颗落入己仓可再走，落入己方空坑可吃对面，仓中石子多者胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('seeds', '每坑石子', [OptionChoice(3, '3 颗'), OptionChoice(4, '4 颗'), OptionChoice(6, '6 颗')], 4),
      OptionDef('capture', '吃子规则', _onOff, true),
    ],
    create: Mancala.new,
    rules: mancalaRules,
    undo: true,
  ),
  GameDef(
    id: 'connect6',
    name: '六子棋',
    category: '棋类',
    description: '19路棋盘，黑方首手一子，此后每回合落两子，先连成六子者胜。',
    playerRange: (_) => (2, 2),
    create: Connect6.new,
    rules: connect6Rules,
    undo: true,
  ),
  GameDef(
    id: 'hex',
    name: '六角棋',
    category: '棋类',
    description: '菱形六角格棋盘，红方连接上下、蓝方连接左右，先连通者胜，永无和棋。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('size', '棋盘大小', [OptionChoice(11, '11×11'), OptionChoice(13, '13×13')], 11),
      OptionDef('swap', '交换规则', _onOff, true),
    ],
    create: Hex.new,
    rules: hexRules,
    undo: true,
  ),
  GameDef(
    id: 'ninemen',
    name: '九子棋',
    category: '棋类',
    description: '先轮流放下9子，再沿线移动；连成三子可吃对方一子，对方只剩两子或无法移动即获胜。',
    playerRange: (_) => (2, 2),
    options: const [OptionDef('flying', '剩三子可飞', _onOff, true)],
    create: NineMensMorris.new,
    rules: ninemenRules,
    undo: true,
  ),
];
