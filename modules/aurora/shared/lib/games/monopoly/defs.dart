import '../../src/engine.dart';
import 'monopoly.dart';
import 'rules_text.dart';

/// 大富翁
final List<GameDef> monopolyGames = [
  GameDef(
    id: 'monopoly',
    name: '大富翁',
    category: '桌游',
    description: '掷骰绕城，买地收租、建房盖酒店，让对手破产或在限定回合内成为首富。',
    playerRange: (opts) => (2, 6),
    options: const [
      OptionDef('cash', '起始资金', [OptionChoice(1500, '¥1500'), OptionChoice(2000, '¥2000')], 1500),
      OptionDef('end', '结束条件', [
        OptionChoice(0, '破产到最后一人'),
        OptionChoice(30, '限时 30 回合'),
        OptionChoice(60, '限时 60 回合'),
        OptionChoice(100, '限时 100 回合'),
      ], 60),
      OptionDef('auction', '拍卖', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
      OptionDef('parking', '免费停车奖池', [OptionChoice(false, '关闭'), OptionChoice(true, '开启')], false),
    ],
    create: MonopolyGame.new,
    rules: monopolyRulesText,
  ),
];
