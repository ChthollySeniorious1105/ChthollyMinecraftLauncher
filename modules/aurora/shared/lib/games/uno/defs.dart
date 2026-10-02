import '../../src/engine.dart';
import 'rules.dart';
import 'rummikub.dart';
import 'uno.dart';

/// UNO/拉密
final List<GameDef> unoGames = [
  GameDef(
    id: 'uno',
    name: 'UNO',
    category: '牌类',
    description: '同色或同数字/符号接龙出牌，功能牌捣乱，最先出完手牌者胜。支持经典 / FLIP 翻转 / NO MERCY 无情模式。',
    playerRange: (_) => (2, 10),
    options: const [
      OptionDef('mode', '模式', [
        OptionChoice('classic', '经典'),
        OptionChoice('flip', 'FLIP 翻转'),
        OptionChoice('nomercy', 'NO MERCY'),
      ], 'classic'),
      OptionDef('stack', '叠加+2/+4', [OptionChoice(false, '关闭'), OptionChoice(true, '开启')], false),
      OptionDef('target', '胜负', [OptionChoice(0, '单局决胜负'), OptionChoice(500, '先到500分')], 0),
    ],
    rules: unoRules,
    create: UnoGame.new,
  ),
  GameDef(
    id: 'rummikub',
    name: '拉密',
    category: '桌游',
    description: '用数字牌组成顺子或同数组，可自由重组桌面，最先出完手牌者胜。首次出牌需≥30分。',
    playerRange: (_) => (2, 4),
    rules: rummikubRules,
    create: RummikubGame.new,
  ),
];
