import '../../src/engine.dart';
import 'avalon.dart';
import 'catan.dart';
import 'codenames.dart';
import 'codenames_duet.dart';
import 'rules.dart';

/// 卡坦岛/阿瓦隆/行动代号
final List<GameDef> socialGames = [
  GameDef(
    id: 'catan',
    name: '卡坦岛',
    category: '桌游',
    description: '在卡坦岛上采集资源、修路、建村庄与城市，率先达到胜利分者获胜。',
    playerRange: (_) => (3, 4),
    options: const [
      OptionDef('map', '地图', [OptionChoice('fixed', '标准固定'), OptionChoice('random', '随机')], 'fixed'),
      OptionDef('vp', '胜利分', [OptionChoice(10, '10 分'), OptionChoice(8, '8 分'), OptionChoice(12, '12 分')], 10),
    ],
    rules: catanRules,
    create: Catan.new,
  ),
  GameDef(
    id: 'avalon',
    name: '阿瓦隆',
    category: '派对',
    description: '正义与邪恶的隐藏身份推理：组队、投票、执行任务，梅林要小心刺客。',
    playerRange: (_) => (5, 10),
    options: const [
      OptionDef('percival', '派西维尔+莫甘娜', [OptionChoice(true, '启用'), OptionChoice(false, '不启用')], true),
      OptionDef('mordred', '莫德雷德', [OptionChoice(false, '不启用'), OptionChoice(true, '启用')], false),
      OptionDef('oberon', '奥伯伦', [OptionChoice(false, '不启用'), OptionChoice(true, '启用')], false),
    ],
    rules: avalonRules,
    create: Avalon.new,
  ),
  GameDef(
    id: 'codenames',
    name: '行动代号',
    category: '派对',
    description: '红蓝两队，队长用一个词加数字提示队友找出己方特工，千万别碰刺客。',
    playerRange: (_) => (4, 10),
    options: const [
      OptionDef('assign', '分组方式', [OptionChoice('alternate', '按座位交替'), OptionChoice('random', '随机分配')], 'alternate'),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: codenamesRules,
    create: Codenames.new,
  ),
  GameDef(
    id: 'codenames_duet',
    name: '代号：合作版',
    category: '派对',
    description: '两方合作：各看一面钥匙卡，轮流用一个词加数字提示对方，在计时用尽前找出全部 15 名特工，别碰刺客。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('tokens', '难度（计时回合）', [OptionChoice(9, '标准 9'), OptionChoice(11, '简单 11'), OptionChoice(7, '困难 7')], 9),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: codenamesDuetRules,
    create: CodenamesDuet.new,
  ),
];
