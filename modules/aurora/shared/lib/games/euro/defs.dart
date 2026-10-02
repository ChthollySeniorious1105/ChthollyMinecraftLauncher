import '../../src/engine.dart';
import 'carcassonne.dart';
import 'hanabi.dart';
import 'rules.dart';

const _onOff = [OptionChoice(true, '开启'), OptionChoice(false, '关闭')];

/// 卡卡颂/花火
final List<GameDef> euroGames = [
  GameDef(
    id: 'carcassonne',
    name: '卡卡颂',
    category: '桌游',
    description: '轮流抽取并拼接地形板块，派出跟随者占据城市、道路、修道院和草地，完成地形即可得分，总分最高者胜。',
    playerRange: (_) => (2, 5),
    options: const [
      OptionDef('farmers', '农夫（草地计分）', _onOff, true),
    ],
    rules: carcassonneRules,
    create: Carcassonne.new,
  ),
  GameDef(
    id: 'hanabi',
    name: '花火',
    category: '桌游',
    description: '合作游戏：看不到自己的手牌，只能靠队友提示颜色或数字，按 1→5 顺序打出各色烟花，共同追求高分。',
    playerRange: (_) => (2, 5),
    options: const [
      OptionDef('rainbow', '彩色烟花（第 6 种颜色）', _onOff, false),
    ],
    rules: hanabiRules,
    create: Hanabi.new,
  ),
];
