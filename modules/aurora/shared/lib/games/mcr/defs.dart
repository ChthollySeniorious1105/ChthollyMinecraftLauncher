import '../../src/engine.dart';
import 'mcr_game.dart';
import 'rules.dart';

/// 国标麻将/广东推倒胡
final List<GameDef> mcrGames = [
  GameDef(
    id: 'mcr',
    rules: mcrRules,
    name: '国标麻将',
    category: '麻将',
    description: '中国麻将竞赛规则：144张含花牌，可吃碰杠，81种番型，8番起和（花牌不计），点和者付8+番、其余各付8。',
    playerRange: (opts) => (4, 4),
    options: const [
      OptionDef('hands', '局数', [OptionChoice(4, '4局（东风圈）'), OptionChoice(8, '8局'), OptionChoice(16, '16局（全庄）')], 4),
    ],
    create: (s) => McrGame(s, 'mcr'),
  ),
  GameDef(
    id: 'guangdong',
    rules: guangdongRules,
    name: '广东推倒胡',
    category: '麻将',
    description: '广东鸡胡/推倒胡：可吃碰杠，胡牌即可推倒，碰碰胡/清一色/七对等加番，买马、跟庄，底分×2^番封顶。',
    playerRange: (opts) => (4, 4),
    options: const [
      OptionDef('hands', '局数', [OptionChoice(4, '4局'), OptionChoice(8, '8局'), OptionChoice(16, '16局')], 8),
      OptionDef('minFan', '起胡', [OptionChoice(0, '鸡胡可胡'), OptionChoice(1, '1番起胡'), OptionChoice(3, '3番起胡')], 0),
      OptionDef('horses', '买马', [OptionChoice(0, '不买马'), OptionChoice(2, '2马'), OptionChoice(4, '4马'), OptionChoice(6, '6马')], 2),
      OptionDef('cap', '封顶', [OptionChoice(8, '8分'), OptionChoice(16, '16分'), OptionChoice(32, '32分')], 16),
      OptionDef('qidui', '七对', [OptionChoice(true, '可胡七对'), OptionChoice(false, '不可胡七对')], true),
      OptionDef('gen', '跟庄', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
      OptionDef('flowers', '花牌', [OptionChoice(false, '不带花'), OptionChoice(true, '带花（每花1番）')], false),
    ],
    create: (s) => McrGame(s, 'gd'),
  ),
];
