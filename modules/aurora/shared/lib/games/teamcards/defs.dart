import '../../src/engine.dart';
import 'guandan.dart';
import 'rules.dart';
import 'shengji.dart';

/// 掼蛋/升级(拖拉机)
final List<GameDef> teamcardsGames = [
  GameDef(
    id: 'guandan',
    name: '掼蛋',
    category: '牌类',
    description: '四人两副牌，对家为队友。红桃级牌可配任意牌，按出完顺序升级，先打过 A 的一队获胜。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('target', '目标', [OptionChoice(5, '打到5'), OptionChoice(14, '打到A')], 14),
      OptionDef('cap', '局数上限', [OptionChoice(0, '不限'), OptionChoice(3, '3局'), OptionChoice(10, '10局')], 0),
    ],
    rules: guandanRules,
    create: Guandan.new,
  ),
  GameDef(
    id: 'shengji',
    name: '升级（拖拉机）',
    category: '牌类',
    description: '四人两副牌，对家为队友。亮主定将，庄家守分、闲家抓分（5/10/K），闲家得分决定升级或上台。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('target', '目标级', [OptionChoice(5, '打到5'), OptionChoice(14, '打到A')], 14),
      OptionDef('cap', '局数上限', [OptionChoice(0, '不限'), OptionChoice(3, '3局'), OptionChoice(10, '10局')], 0),
    ],
    rules: shengjiRules,
    create: Shengji.new,
  ),
];
