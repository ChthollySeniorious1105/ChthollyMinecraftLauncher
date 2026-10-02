import '../../src/engine.dart';
import 'bullscows.dart';
import 'decrypto.dart';
import 'halligalli.dart';
import 'rules.dart';
import 'turtlesoup.dart';

/// 德国心脏病/猜数字1A2B/海龟汤/截码战
final List<GameDef> party2Games = [
  GameDef(
    id: 'halligalli',
    name: '德国心脏病',
    category: '派对',
    description: '轮流翻开水果牌，桌面上某种水果恰好 5 个时抢先拍铃收走所有翻开的牌；拍错罚每人 1 张。牌最多者获胜。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('botSpeed', '电脑反应', [OptionChoice('slow', '慢'), OptionChoice('normal', '普通'), OptionChoice('fast', '快')], 'normal'),
      OptionDef('maxFlips', '翻牌上限', [OptionChoice(300, '300 次'), OptionChoice(600, '600 次')], 600),
    ],
    rules: halligalliRules,
    create: HalliGalli.new,
  ),
  GameDef(
    id: 'bullscows',
    name: '猜数字1A2B',
    category: '派对',
    description: '每人设定一个各位互不相同的密码，轮流猜下家的密码；A=数字和位置都对，B=数字对位置不对。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('digits', '位数', [OptionChoice(3, '3 位'), OptionChoice(4, '4 位'), OptionChoice(5, '5 位')], 4),
      OptionDef('mode', '模式', [OptionChoice('race', '抢先破解'), OptionChoice('elim', '淘汰接力')], 'race'),
    ],
    rules: bullscowsRules,
    create: BullsCows.new,
  ),
  GameDef(
    id: 'turtlesoup',
    name: '海龟汤',
    category: '派对',
    description: '主持人（房主）掌握汤底，其他人只能问“是/否”问题来还原真相。支持内置题库、服务器自定义题库与主持人自拟。',
    playerRange: (o) => (3, 12),
    options: const [
      OptionDef('source', '来源', [OptionChoice('builtin', '内置'), OptionChoice('custom', '自定义'), OptionChoice('gm', 'GM自拟')], 'builtin'),
      OptionDef('rounds', '题数', [OptionChoice(1, '1 题'), OptionChoice(2, '2 题'), OptionChoice(3, '3 题')], 1),
      OptionDef('cap', '每题提问上限', [OptionChoice(30, '30 问'), OptionChoice(40, '40 问'), OptionChoice(60, '60 问')], 40),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: turtlesoupRules,
    create: TurtleSoup.new,
  ),
  GameDef(
    id: 'decrypto',
    name: '截码战',
    category: '派对',
    description: '两队各有 4 个秘密关键词。加密者根据 3 位密码给出线索，队友解码、对手拦截。拦截 2 次获胜，失误 2 次落败。',
    playerRange: (o) => (4, 8),
    options: const [
      OptionDef('words', '词库', [OptionChoice('both', '内置+自定义'), OptionChoice('builtin', '仅内置'), OptionChoice('custom', '仅自定义')], 'both'),
      OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false),
    ],
    rules: decryptoRules,
    create: Decrypto.new,
  ),
];
