import '../../src/engine.dart';
import 'liarsbar.dart';
import 'loveletter.dart';
import 'rules.dart';
import 'splendor.dart';
import 'yahtzee.dart';

/// 情书/快艇骰子/璀璨宝石/骗子酒馆
final List<GameDef> tabletopGames = [
  GameDef(
    id: 'loveletter',
    name: '情书',
    category: '桌游',
    description: '每回合摸一张、打一张，用卡牌效果淘汰对手，把情书送到公主手中。2019 版 21 张牌。',
    playerRange: (_) => (2, 6),
    create: LoveLetter.new,
    rules: loveLetterRules,
  ),
  GameDef(
    id: 'yahtzee',
    name: '快艇骰子',
    category: '桌游',
    description: '5 颗骰子每回合最多掷 3 次，填满 13 个计分项，总分最高者获胜。',
    playerRange: (_) => (1, 6),
    create: Yahtzee.new,
    rules: yahtzeeRules,
  ),
  GameDef(
    id: 'splendor',
    name: '璀璨宝石',
    category: '桌游',
    description: '收集宝石、购买发展卡、吸引贵族，率先达到 15 声望分的玩家触发终局。',
    playerRange: (_) => (2, 4),
    create: Splendor.new,
    rules: splendorRules,
  ),
  GameDef(
    id: 'liarsbar',
    name: '骗子酒馆',
    category: '派对',
    description: '出牌或叫骰时虚张声势，被识破就要对自己开一枪。最后的幸存者获胜。',
    playerRange: (_) => (2, 6),
    options: [
      OptionDef('mode', '玩法', [
        OptionChoice('deck', '骗子牌桌'),
        OptionChoice('dice', '骗子骰子'),
        OptionChoice('devil', '恶魔牌'),
        OptionChoice('chaos', '混沌模式'),
        OptionChoice('classic', '经典吹牛骰（失败减骰子）'),
      ], 'deck'),
      OptionDef('wild', '骰子 1 点万能', [OptionChoice(true, '是'), OptionChoice(false, '否')], true),
    ],
    create: LiarsBar.new,
    rules: liarsBarRules,
  ),
];
