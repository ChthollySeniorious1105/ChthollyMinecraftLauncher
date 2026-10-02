import '../../src/engine.dart';
import 'rules.dart';
import 'sichuan.dart';

/// 四川麻将
final List<GameDef> sichuanGames = [
  GameDef(
    id: 'sichuan',
    rules: sichuanRules,
    name: '四川麻将',
    category: '麻将',
    description: '血战到底：108张万筒条，换三张、定缺，只能碰杠，胡牌后离场，直到三家胡牌或牌墙摸完。',
    playerRange: (opts) => (4, 4),
    options: const [
      OptionDef('hands', '局数', [OptionChoice(4, '4局'), OptionChoice(8, '8局'), OptionChoice(16, '16局')], 8),
      OptionDef('swap', '换三张', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
      OptionDef('cap', '封顶', [OptionChoice(3, '3番'), OptionChoice(4, '4番'), OptionChoice(5, '5番'), OptionChoice(6, '6番')], 4),
      OptionDef('zimo', '自摸', [OptionChoice('di', '自摸加底'), OptionChoice('fan', '自摸加番')], 'di'),
    ],
    create: SichuanGame.new,
  ),
];
