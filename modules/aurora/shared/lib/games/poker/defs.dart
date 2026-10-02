import '../../src/engine.dart';
import 'cabo.dart';
import 'doudizhu.dart';
import 'exploding.dart';
import 'rules.dart';

/// 斗地主/爆炸猫/CABO
final List<GameDef> pokerGames = [
  GameDef(
    id: 'doudizhu',
    name: '斗地主',
    category: '牌类',
    description: '一人当地主对抗其余农民，先出完手牌的一方获胜。支持一副牌三人、两副牌四人。',
    playerRange: (o) => o['decks'] == 2 ? (4, 4) : (3, 3),
    options: const [
      OptionDef('decks', '牌数', [OptionChoice(1, '一副牌（3人）'), OptionChoice(2, '两副牌（4人）')], 1),
      OptionDef('rounds', '局数', [OptionChoice(1, '1局'), OptionChoice(3, '3局'), OptionChoice(5, '5局'), OptionChoice(10, '10局')], 3),
      OptionDef('bid', '叫地主', [OptionChoice('score', '叫分（1-3分）'), OptionChoice('grab', '抢地主')], 'score'),
    ],
    rules: doudizhuRules,
    create: Doudizhu.new,
  ),
  GameDef(
    id: 'explodingkittens',
    name: '爆炸猫',
    category: '桌游',
    description: '轮流摸牌，摸到爆炸猫又没有拆除就出局；用各种功能牌躲避危险，活到最后者胜。',
    playerRange: (_) => (2, 5),
    options: const [
      OptionDef('hand', '初始手牌', [OptionChoice(4, '4张+拆除'), OptionChoice(7, '7张+拆除')], 7),
    ],
    rules: explodingRules,
    create: ExplodingKittens.new,
  ),
  GameDef(
    id: 'cabo',
    name: 'CABO',
    category: '牌类',
    description: '记住自己面前扣着的牌，通过交换与技能让总点数最小，觉得够低就喊 CABO！',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(50, '50分'), OptionChoice(100, '100分')], 100),
    ],
    rules: caboRules,
    create: Cabo.new,
  ),
];
