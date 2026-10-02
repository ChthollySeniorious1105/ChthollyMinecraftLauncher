import '../../src/engine.dart';
import 'chengyu.dart';
import 'feihualing.dart';
import 'justone.dart';
import 'p3_turns.dart';
import 'p3_util.dart';
import 'rules.dart';
import 'wavelength.dart';

const _time = OptionDef('time', '限时', [OptionChoice(0, '不限时'), OptionChoice(60, '60 秒'), OptionChoice(90, '90 秒'), OptionChoice(120, '120 秒')], 0);
const _turnTime = OptionDef('time', '每回合限时', [OptionChoice(0, '不限时'), OptionChoice(15, '15 秒'), OptionChoice(30, '30 秒'), OptionChoice(60, '60 秒')], 30);
const _words = OptionDef('words', '词库', [OptionChoice('both', '内置+自定义'), OptionChoice('builtin', '仅内置'), OptionChoice('custom', '仅自定义')], 'both');

/// Just One / 频率猜心 / 成语接龙 / 飞花令
final List<GameDef> party3Games = [
  GameDef(
    id: 'justone',
    name: 'Just One 合作猜词',
    category: '派对',
    description: '合作游戏：大家各写一个提示词帮猜词者猜出神秘词，但相同的提示会互相抵消！13 张牌，猜中越多越好。',
    playerRange: (o) => (3, 7),
    options: const [
      OptionDef('cards', '牌数', [OptionChoice(7, '7 张'), OptionChoice(13, '13 张'), OptionChoice(20, '20 张')], 13),
      _time,
      _words,
      kAiOption,
    ],
    rules: justoneRules,
    create: JustOne.new,
  ),
  GameDef(
    id: 'wavelength',
    name: '频率猜心',
    category: '派对',
    description: '通灵者看到光谱（如 冷—热）上的秘密位置并给出线索，队友转动指针猜位置。合作或两队对抗。',
    playerRange: (o) => (o['mode'] == 'team' ? 4 : 2, 12),
    options: const [
      OptionDef('mode', '模式', [OptionChoice('coop', '合作'), OptionChoice('team', '团队对抗')], 'coop'),
      OptionDef('cards', '轮数（合作）', [OptionChoice(5, '5 轮'), OptionChoice(7, '7 轮'), OptionChoice(10, '10 轮')], 7),
      OptionDef('goal', '目标分（团队）', [OptionChoice(7, '7 分'), OptionChoice(10, '10 分'), OptionChoice(15, '15 分')], 10),
      _time,
      OptionDef('words', '光谱', [OptionChoice('both', '内置+自定义'), OptionChoice('builtin', '仅内置'), OptionChoice('custom', '仅自定义')], 'both'),
      kAiOption,
    ],
    rules: wavelengthRules,
    create: Wavelength.new,
  ),
  GameDef(
    id: 'chengyu',
    name: '成语接龙',
    category: '派对',
    description: '轮流说四字成语，首字接上一个的尾字（可选同音）。说不出来失去一条命，最后存活者获胜。',
    playerRange: (o) => (2, 8),
    options: const [
      OptionDef('match', '模式', [OptionChoice('char', '同字'), OptionChoice('sound', '同音')], 'char'),
      kLivesOption,
      _turnTime,
      kAiOption,
    ],
    rules: chengyuRules,
    create: ChengyuGame.new,
  ),
  GameDef(
    id: 'feihualing',
    name: '飞花令',
    category: '派对',
    description: '选定一个令字（花、月、春……），轮流说出含有这个字的古诗词句，不能重复。说不出来失去一条命。',
    playerRange: (o) => (2, 8),
    options: [
      OptionDef('key', '令字', [const OptionChoice('random', '随机'), for (final k in kFeihuaOptionKeys) OptionChoice(k, k)], 'random'),
      const OptionDef('check', '校验', [OptionChoice('strict', '严格（诗词库）'), OptionChoice('loose', '宽松（投票）')], 'strict'),
      kLivesOption,
      _turnTime,
      kAiOption,
    ],
    rules: feihualingRules,
    create: Feihualing.new,
  ),
];
