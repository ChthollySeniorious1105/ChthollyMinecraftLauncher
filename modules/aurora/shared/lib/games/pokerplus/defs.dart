import '../../src/engine.dart';
import 'blackjack.dart';
import 'holdem.dart';
import 'paodekuai.dart';
import 'rules.dart';

/// 德州扑克/21点/跑得快
final List<GameDef> pokerplusGames = [
  GameDef(
    id: 'texasholdem',
    name: '德州扑克',
    category: '牌类',
    description: '无限注德州扑克：两张底牌配五张公共牌组成最大的牌，下注、加注、诈唬，赢光对手筹码。',
    playerRange: (_) => (2, 9),
    options: const [
      OptionDef('chips', '初始筹码', [OptionChoice(1000, '1000'), OptionChoice(2000, '2000'), OptionChoice(5000, '5000')], 1000),
      OptionDef('blinds', '盲注', [OptionChoice(10, '10/20'), OptionChoice(25, '25/50'), OptionChoice(50, '50/100')], 10),
      OptionDef('escalate', '盲注递增', [OptionChoice('off', '关'), OptionChoice('double10', '每10手翻倍')], 'off'),
      OptionDef('end', '结束条件', [OptionChoice('elim', '淘汰至一人'), OptionChoice('fixed', '固定30手')], 'elim'),
    ],
    rules: holdemRules,
    create: TexasHoldem.new,
  ),
  GameDef(
    id: 'blackjack',
    name: '21点',
    category: '牌类',
    description: '与庄家比大小，点数接近21且不爆牌者胜。支持加倍、分牌、保险，黑杰克赔3:2。',
    playerRange: (_) => (1, 7),
    options: const [
      OptionDef('h17', '庄家软17', [OptionChoice(false, '停牌'), OptionChoice(true, '要牌')], false),
      OptionDef('rounds', '局数', [OptionChoice(10, '10局'), OptionChoice(20, '20局'), OptionChoice(0, '直到破产')], 10),
    ],
    rules: blackjackRules,
    create: Blackjack.new,
  ),
  GameDef(
    id: 'paodekuai',
    name: '跑得快',
    category: '牌类',
    description: '三人跑得快：♠3先出，单、对、连对、三带二、飞机、顺子、炸弹，先出完者赢，剩牌越多输越多。',
    playerRange: (_) => (3, 3),
    options: const [
      OptionDef('cards', '手牌数', [OptionChoice(16, '16张'), OptionChoice(15, '15张')], 16),
      OptionDef('must', '必须管', [OptionChoice(true, '有牌必管'), OptionChoice(false, '可以不管')], true),
      OptionDef('rounds', '局数', [OptionChoice(5, '5局'), OptionChoice(10, '10局')], 5),
    ],
    rules: paodekuaiRules,
    create: Paodekuai.new,
  ),
];
