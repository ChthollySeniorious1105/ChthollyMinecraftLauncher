import '../../src/engine.dart';
import 'chuiniu.dart';
import 'dicepoker.dart';
import 'farkle.dart';
import 'pig.dart';
import 'rules.dart';
import 'shidianban.dart';

/// 十点半 / 骰子扑克 / 猪骰 / 快乐骰 / 吹牛骰
final List<GameDef> dice2Games = [
  GameDef(
    id: 'shidianban',
    name: '十点半',
    category: '桌游',
    description: 'A 算 1 点，2~10 按点数，JQK 算半点。闲家与庄家比谁更接近 10.5 点而不爆；五小、人五小、天王、十点半有加倍赔率。',
    playerRange: (o) => (2, 8),
    options: const [
      OptionDef('banker', '坐庄', [OptionChoice('rotate', '轮庄'), OptionChoice('grab', '抢庄')], 'rotate'),
      OptionDef('payout', '赔率', [
        OptionChoice('standard', '标准（十点半×2 五小×3 天王×4 人五小×5）'),
        OptionChoice('high', '高倍（×3 / ×5 / ×6 / ×8）'),
        OptionChoice('flat', '平赔（一律×1）'),
      ], 'standard'),
      OptionDef('rounds', '局数', [OptionChoice(6, '6 局'), OptionChoice(10, '10 局'), OptionChoice(16, '16 局')], 10),
    ],
    create: ShiDianBan.new,
    rules: shiDianBanRules,
  ),
  GameDef(
    id: 'dicepoker',
    name: '骰子扑克',
    category: '桌游',
    description: '5 颗骰子最多掷 3 次，可保留任意骰子。五条>四条>葫芦>大顺>小顺>三条>两对>一对>散牌，每局牌型最大者得 1 分。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(5, '5 局'), OptionChoice(10, '10 局')], 5),
    ],
    create: DicePoker.new,
    rules: dicePokerRules,
  ),
  GameDef(
    id: 'pigdice',
    name: '猪骰',
    category: '桌游',
    description: '不停掷骰累积本回合分数，掷出 1 则本回合分数作废；随时可以停手存分，先到目标分者胜。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(50, '50 分'), OptionChoice(100, '100 分')], 100),
      OptionDef('variant', '玩法', [OptionChoice('one', '单骰猪'), OptionChoice('two', '双骰猪（蛇眼清零）')], 'one'),
    ],
    create: PigDice.new,
    rules: pigRules,
  ),
  GameDef(
    id: 'farkle',
    name: '快乐骰',
    category: '桌游',
    description: 'Farkle：掷 6 颗骰子，每次必须留下计分骰（1=100、5=50、三条、顺子、三对…），可继续掷或存分；掷不出分则本回合清零。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(5000, '5000 分'), OptionChoice(10000, '10000 分')], 10000),
    ],
    create: Farkle.new,
    rules: farkleRules,
  ),
  GameDef(
    id: 'chuiniu',
    name: '吹牛骰',
    category: '桌游',
    description: '经典大话骰：每人 5 颗骰子扣在骰盅下，轮流叫“几个几”，1 点万能（叫斋除外），不信就开！输家扣一条命，最后存活者胜。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('lives', '生命', [OptionChoice(3, '3 条命'), OptionChoice(5, '5 条命')], 3),
      OptionDef('pi', '劈（双倍）', [OptionChoice(true, '允许劈'), OptionChoice(false, '不允许')], true),
    ],
    create: ChuiNiu.new,
    rules: chuiNiuRules,
  ),
];
