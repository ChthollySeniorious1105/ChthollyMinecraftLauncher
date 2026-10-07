import '../../src/engine.dart';
import 'bomberman.dart';
import 'dobble.dart';
import 'rules.dart';

/// 炸弹人 / 眼疾手快
final List<GameDef> arcade2Games = [
  GameDef(
    id: 'bomberman',
    name: '炸弹人',
    category: '派对',
    description: '经典炸弹人实时对战：在石柱与砖块之间放炸弹，十字火焰连锁爆炸，炸开砖块拿道具（炸弹/火力/速度），炸飞对手，最后存活者获胜。',
    playerRange: (o) => (2, 4),
    options: const [
      OptionDef('time', '时长', [OptionChoice(120, '2 分钟'), OptionChoice(180, '3 分钟'), OptionChoice(300, '5 分钟')], 180),
      OptionDef('bricks', '砖块密度', [OptionChoice('few', '稀疏'), OptionChoice('normal', '普通'), OptionChoice('many', '密集')], 'normal'),
    ],
    rules: bombermanRules,
    create: Bomberman.new,
  ),
  GameDef(
    id: 'dobble',
    name: '眼疾手快',
    category: '派对',
    description: 'Dobble / Spot It!：任意两张牌之间恰好有一个相同图案。大家同时抢答，最先点中自己的牌与中央牌相同图案的人赢下这一轮；点错会被冻结 1.5 秒。',
    playerRange: (o) => (2, 8),
    options: const [
      OptionDef('mode', '模式', [OptionChoice('tower', '塔楼（抢中央牌，最多者胜）'), OptionChoice('well', '深井（出完手牌者胜）')], 'tower'),
    ],
    rules: dobbleRules,
    create: Dobble.new,
  ),
];
