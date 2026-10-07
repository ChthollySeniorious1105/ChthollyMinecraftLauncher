import '../../src/engine.dart';
import 'banqi.dart';
import 'jaipur.dart';
import 'lostcities.dart';

/// 斋浦尔 / 失落的城市 / 暗棋 — two-player duels.
final List<GameDef> duel2Games = [
  GameDef(
    id: 'jaipur',
    name: '斋浦尔',
    category: '桌游',
    description: '两位商人在斋浦尔市场收购、交换和出售货物，赶在价格下跌前卖出，用骆驼控制市场，三局两胜赢得优秀印章。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('rounds', '赛制', [OptionChoice('bo3', '三局两胜'), OptionChoice('single', '单局')], 'bo3'),
    ],
    create: Jaipur.new,
    rules: jaipurRules,
  ),
  GameDef(
    id: 'lostcities',
    name: '失落的城市',
    category: '桌游',
    description: '两人各组五支探险队，按顺序打出同色卡牌；启动探险要付 20 点成本，投资牌让输赢翻倍。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(1, '1 局'), OptionChoice(3, '3 局累计')], 1),
    ],
    create: LostCities.new,
    rules: lostCitiesRules,
  ),
  GameDef(
    id: 'banqi',
    name: '暗棋',
    category: '棋类',
    description: '32 枚象棋棋子背面朝上随机摆在半张棋盘上，翻棋定颜色，按大小吃子，兵能吃帅，炮隔子打。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('drawRule', '和棋规则', [OptionChoice(30, '30 步无吃子/翻棋'), OptionChoice(50, '50 步无吃子/翻棋'), OptionChoice(100, '100 步无吃子/翻棋')], 50),
    ],
    create: Banqi.new,
    rules: banqiRules,
  ),
];
