import '../../src/engine.dart';
import 'rules.dart';
import 'undercover.dart';

/// 谁是卧底
final List<GameDef> undercoverGames = [
  GameDef(
    id: 'undercover',
    name: '谁是卧底',
    category: '派对',
    description: '每人拿到一个词，卧底的词和大家略有不同。轮流描述、投票找出卧底！',
    playerRange: (o) => o['source'] == 'gm' ? (5, 12) : (3, 12),
    options: const [
      OptionDef('spies', '卧底人数', [
        OptionChoice(0, '自动'),
        OptionChoice(1, '1 人'),
        OptionChoice(2, '2 人'),
        OptionChoice(3, '3 人'),
      ], 0),
      OptionDef('blank', '白板', [OptionChoice(false, '关闭'), OptionChoice(true, '开启')], false),
      OptionDef('bank', '词库', [
        OptionChoice('mix', '内置+服务器自定义'),
        OptionChoice('custom', '仅服务器自定义'),
        OptionChoice('builtin', '仅内置'),
      ], 'mix'),
      OptionDef('source', '出题方式', [OptionChoice('bank', '系统词库'), OptionChoice('gm', '指定出题人')], 'bank'),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: undercoverRules,
    create: Undercover.new,
  ),
];
