import '../../src/engine.dart';
import 'azul.dart';
import 'duel.dart';
import 'kingdomino.dart';
import 'patchwork.dart';

const _onOff = [OptionChoice(false, '关闭'), OptionChoice(true, '开启')];

/// 花砖物语 / 王国骨牌 / 拼布艺术 / 七大奇迹·对决
final List<GameDef> euro2Games = [
  GameDef(
    id: 'azul',
    name: '花砖物语',
    category: '桌游',
    description: '从工厂挑选同色瓷砖填满图案行，再铺到宫殿墙上按相连得分；溢出落地会扣分，终局奖励整行、整列和同色。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('wall', '墙面', [OptionChoice('color', '标准彩色墙'), OptionChoice('grey', '灰墙（自由摆放）')], 'color'),
    ],
    create: Azul.new,
    rules: azulRules,
  ),
  GameDef(
    id: 'kingdomino',
    name: '王国骨牌',
    category: '桌游',
    description: '轮流挑选地形骨牌拼进 5×5 王国，相连同地形 × 皇冠数得分；选好牌的代价是下一轮后手。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('mighty', '巨人对决（2 人 7×7）', _onOff, false),
      OptionDef('middle', '中央王国 +10', _onOff, false),
      OptionDef('harmony', '和谐 +5', _onOff, false),
    ],
    create: Kingdomino.new,
    rules: kingdominoRules,
  ),
  GameDef(
    id: 'patchwork',
    name: '拼布艺术',
    category: '桌游',
    description: '两人用纽扣购买形状各异的布片拼被子，时间轨落后者行动；终局纽扣减空格罚分，拼满 7×7 再得 7 分。',
    playerRange: (_) => (2, 2),
    create: Patchwork.new,
    rules: patchworkRules,
    undo: true,
  ),
  GameDef(
    id: '7wonders_duel',
    name: '七大奇迹·对决',
    category: '桌游',
    description: '两人经历三个时代，从卡牌结构中拿卡建设文明与奇迹，以军事压制、集齐科技或终局分数取胜。',
    playerRange: (_) => (2, 2),
    create: Duel.new,
    rules: duelRules,
  ),
];
