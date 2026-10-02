import '../../src/engine.dart';
import 'bridge.dart';
import 'hearts.dart';
import 'rules.dart';
import 'spades.dart';

/// 桥牌/红心大战/黑桃王
final List<GameDef> tricksGames = [
  GameDef(
    id: 'bridge',
    name: '桥牌',
    category: '牌类',
    description: '四人两两搭档（南北 vs 东西）。先叫牌定约，再由庄家打自己和明手两手牌，完成定约墩数得分。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('scoring', '计分', [OptionChoice('rubber', '盘式（先胜两局）'), OptionChoice('chicago', '芝加哥（4副）')], 'rubber'),
      OptionDef('cap', '副数上限（盘式）', [OptionChoice(0, '不限'), OptionChoice(4, '4副'), OptionChoice(8, '8副')], 0),
    ],
    rules: bridgeRules,
    create: Bridge.new,
  ),
  GameDef(
    id: 'hearts',
    name: '红心大战',
    category: '牌类',
    description: '四人各自为战。每局先传 3 张牌，尽量不要吃进红心（每张 1 分）和黑桃 Q（13 分），有人到达目标分时分数最低者获胜。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(100, '100 分'), OptionChoice(50, '50 分')], 100),
      OptionDef('moon', '射月（全收）', [OptionChoice(true, '开启：其他人 +26'), OptionChoice(false, '关闭')], true),
      OptionDef('firstClean', '第一墩', [OptionChoice(true, '不能出分牌'), OptionChoice(false, '无限制')], true),
      OptionDef('cap', '局数上限', [OptionChoice(0, '不限'), OptionChoice(4, '4局'), OptionChoice(8, '8局')], 0),
    ],
    rules: heartsRules,
    create: Hearts.new,
  ),
  GameDef(
    id: 'spades',
    name: '黑桃王',
    category: '牌类',
    description: '四人对家搭档，黑桃永远是将牌。每局先叫墩数（可叫零墩），完成叫墩得分，多余墩数累积 10 袋扣 100 分，先到目标分获胜。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(500, '500 分'), OptionChoice(250, '250 分')], 500),
      OptionDef('blindNil', '盲零', [OptionChoice(false, '关闭'), OptionChoice(true, '开启（落后 100 分以上可叫）')], false),
      OptionDef('cap', '局数上限', [OptionChoice(0, '不限'), OptionChoice(5, '5局'), OptionChoice(10, '10局')], 0),
    ],
    rules: spadesRules,
    create: Spades.new,
  ),
];
