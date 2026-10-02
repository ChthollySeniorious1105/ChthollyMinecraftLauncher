import '../../src/engine.dart';
import 'drawguess.dart';
import 'rules.dart';
import 'telephone.dart';

/// 你画我猜
final List<GameDef> drawguessGames = [
  GameDef(
    id: 'drawguess',
    name: '你画我猜',
    category: '派对',
    description: '轮流作画，其他人猜词；猜得越快得分越高，画手按猜对人数得分。支持服务器自定义词库与 GM 出题。',
    playerRange: (o) => (o['mode'] == 'gm' ? 4 : 3, 12),
    options: const [
      OptionDef('mode', '出题方式', [OptionChoice('bank', '系统词库'), OptionChoice('gm', 'GM出题')], 'bank'),
      OptionDef('rounds', '轮数', [OptionChoice(1, '每人画 1 次'), OptionChoice(2, '每人画 2 次'), OptionChoice(3, '每人画 3 次')], 1),
      OptionDef('time', '每轮时间', [OptionChoice(60, '60 秒'), OptionChoice(80, '80 秒'), OptionChoice(120, '120 秒')], 80),
      OptionDef('pick', '选词', [OptionChoice('choose3', '3选1'), OptionChoice('random', '随机')], 'choose3'),
      OptionDef('hints', '提示', [OptionChoice(true, '开（逐步揭示字数/类别/一个字）'), OptionChoice(false, '关')], true),
      OptionDef('words', '词库', [OptionChoice('both', '内置+自定义'), OptionChoice('custom', '仅自定义'), OptionChoice('builtin', '仅内置')], 'both'),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: drawguessRules,
    create: DrawGuess.new,
  ),
  GameDef(
    id: 'telephone',
    name: '传话画画',
    category: '派对',
    description: '每人先写一句话，然后传给下一位：画出收到的文字、描述收到的画，交替进行。最后逐本揭晓，看看意思跑偏了多远！',
    playerRange: (o) => (3, 12),
    options: const [
      OptionDef('draw', '作画时间', [OptionChoice(60, '60 秒'), OptionChoice(90, '90 秒'), OptionChoice(120, '120 秒')], 90),
      OptionDef('write', '写字时间', [OptionChoice(30, '30 秒'), OptionChoice(45, '45 秒'), OptionChoice(60, '60 秒')], 45),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: telephoneRules,
    create: Telephone.new,
  ),
];
