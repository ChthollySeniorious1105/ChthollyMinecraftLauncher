import '../../src/engine.dart';
import 'roles.dart';
import 'rules.dart';
import 'werewolf.dart';

/// 狼人杀
final List<GameDef> werewolfGames = [
  GameDef(
    id: 'werewolf',
    name: '狼人杀',
    category: '派对',
    description: '法官由系统担任。狼人每晚刀人，好人靠预言家、女巫、猎人等神职和发言投票找出狼人。',
    playerRange: (o) => werewolfRange('${o['board'] ?? 'auto'}'),
    options: [
      OptionDef('board', '板子', [for (final e in werewolfBoards.entries) OptionChoice(e.key, e.value)], 'auto'),
      const OptionDef('win', '胜利条件', [OptionChoice('edge', '屠边'), OptionChoice('city', '屠城')], 'edge'),
      const OptionDef('selfSave', '女巫自救',
          [OptionChoice('first', '仅首夜'), OptionChoice('never', '不可自救'), OptionChoice('always', '每夜可自救')], 'first'),
      const OptionDef('sheriff', '警长竞选', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
      const OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: werewolfRules,
    create: Werewolf.new,
  ),
];
