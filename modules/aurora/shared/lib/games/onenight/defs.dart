import '../../src/engine.dart';
import 'onenight.dart';
import 'resistance.dart';
import 'rules.dart';
import 'spyfall.dart';

/// 一夜终极狼人/抵抗组织/谁是间谍
final List<GameDef> onenightGames = [
  GameDef(
    id: 'onenight',
    name: '一夜终极狼人',
    category: '派对',
    description: '只有一个夜晚：狼人、预言家、强盗、捣蛋鬼等依次秘密行动，身份可能被偷换。白天讨论后同时投票，投出一名狼人好人即胜。',
    playerRange: (o) => (3, 10),
    options: [
      OptionDef('preset', '角色配置', [for (final e in onPresetNames.entries) OptionChoice(e.key, e.value)], 'standard'),
      const OptionDef('day', '讨论时间', [OptionChoice(3, '3 分钟'), OptionChoice(5, '5 分钟'), OptionChoice(8, '8 分钟')], 5),
      const OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: onenightRules,
    create: OneNight.new,
  ),
  GameDef(
    id: 'resistance',
    name: '抵抗组织',
    category: '派对',
    description: '抵抗组织与潜伏的间谍。队长组队、全员投票，队员秘密出任务牌，间谍可以让任务失败。先赢得三次任务的一方获胜。',
    playerRange: (o) => (5, 10),
    options: const [
      OptionDef('plot', '计划卡', [OptionChoice(false, '关闭'), OptionChoice(true, '开启')], false),
    ],
    rules: resistanceRules,
    create: Resistance.new,
  ),
  GameDef(
    id: 'spyfall',
    name: '谁是间谍',
    category: '派对',
    description: '除间谍外人人都知道同一个词条（地点、食物、动物、交通工具、运动或节日）。轮流提问回答找出间谍；间谍要隐藏身份并猜出词条。',
    playerRange: (o) => (3, 10),
    options: const [
      OptionDef('pack', '词库', [
        OptionChoice('location', '地点'),
        OptionChoice('food', '食物'),
        OptionChoice('animal', '动物'),
        OptionChoice('vehicle', '交通工具'),
        OptionChoice('sport', '运动'),
        OptionChoice('event', '节日与活动'),
        OptionChoice('mix', '混合（全部）'),
      ], 'location'),
      OptionDef('minutes', '每轮时间', [OptionChoice(6, '6 分钟'), OptionChoice(8, '8 分钟'), OptionChoice(10, '10 分钟')], 8),
      OptionDef('rounds', '轮数', [OptionChoice(1, '1 轮'), OptionChoice(3, '3 轮'), OptionChoice(5, '5 轮')], 3),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: spyfallRules,
    create: Spyfall.new,
  ),
];
