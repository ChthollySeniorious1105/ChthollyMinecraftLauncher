import '../../src/engine.dart';
import 'coup.dart';
import 'nothanks.dart';
import 'sixnimmt.dart';
import 'skull.dart';
import 'sushigo.dart';
import 'themind.dart';

/// 谁是牛头王 / No Thanks! / 寿司狗 / 政变 / 心灵同步 / 骷髅与玫瑰
final List<GameDef> lightGames = [
  GameDef(
    id: '6nimmt',
    name: '谁是牛头王',
    category: '派对',
    description: '所有人同时出牌，按大小依次接到 4 列末尾，第 6 张要吃下整列牛头。牛头最少者获胜。',
    playerRange: (_) => (2, 10),
    options: [
      OptionDef('end', '结束条件', [
        OptionChoice(66, '有人达到 66 牛头'),
        OptionChoice(1, '只打 1 局'),
        OptionChoice(3, '固定 3 局'),
        OptionChoice(5, '固定 5 局'),
      ], 66),
      OptionDef('pro', '专业变体', [OptionChoice(false, '关'), OptionChoice(true, '开（只用 1~10×人数+4 号牌）')], false),
    ],
    create: SixNimmt.new,
    rules: sixNimmtRules,
  ),
  GameDef(
    id: 'nothanks',
    name: 'No Thanks!',
    category: '派对',
    description: '不想要这张牌？放一枚筹码推给下家。连号只算最小的一张，筹码抵分，得分最低者获胜。',
    playerRange: (_) => (3, 7),
    create: NoThanks.new,
    rules: noThanksRules,
  ),
  GameDef(
    id: 'sushigo',
    name: '寿司狗',
    category: '派对',
    description: '同时选一张寿司、把手牌传给下家的轮抽游戏。凑天妇罗、刺身、饺子、卷寿司，3 轮后总分最高者获胜。',
    playerRange: (_) => (2, 5),
    create: SushiGo.new,
    rules: sushiGoRules,
  ),
  GameDef(
    id: 'coup',
    name: '政变',
    category: '派对',
    description: '暗藏两张角色牌，宣称任意角色来收钱、刺杀、勒索，也可以质疑别人的谎言。最后保有影响力的人获胜。',
    playerRange: (_) => (2, 6),
    options: [
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    create: Coup.new,
    rules: coupRules,
  ),
  GameDef(
    id: 'themind',
    name: '心灵同步',
    category: '派对',
    description: '合作闯关：不许交流，全队凭默契把手牌从小到大依次打出。失误扣生命，通过全部关卡即胜利。',
    playerRange: (_) => (2, 4),
    create: TheMind.new,
    rules: theMindRules,
  ),
  GameDef(
    id: 'skull',
    name: '骷髅与玫瑰',
    category: '派对',
    description: '暗放玫瑰或骷髅，竞价敢翻开几朵玫瑰。翻到骷髅就要失去圆牌，两次挑战成功者获胜。',
    playerRange: (_) => (3, 6),
    create: Skull.new,
    rules: skullRules,
  ),
];
