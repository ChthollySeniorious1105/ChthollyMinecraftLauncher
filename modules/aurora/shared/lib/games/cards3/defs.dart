import '../../src/engine.dart';
import 'baccarat.dart';
import 'gandengyan.dart';
import 'gongzhu.dart';
import 'rules.dart';
import 'wushik.dart';
import 'zhengshangyou.dart';

/// 干瞪眼/五十K/争上游/拱猪/百家乐
final List<GameDef> cards3Games = [
  GameDef(
    id: 'gandengyan',
    name: '干瞪眼',
    category: '牌类',
    description: '每人5张（庄家6张），跟牌须同牌型且恰好大一级，2可管任意单张/对子，大小王百搭，三张以上同点为炸弹；'
        '一轮无人能管时赢家摸一张再出，先出完者赢，其余人按剩牌数赔付，每个炸弹翻倍。',
    playerRange: (_) => (2, 6),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(6, '6局'), OptionChoice(10, '10局'), OptionChoice(3, '3局')], 6),
    ],
    rules: gandengyanRules,
    create: Gandengyan.new,
  ),
  GameDef(
    id: 'wushik',
    name: '五十K',
    category: '牌类',
    description: '一副牌加大小王，出单/对/三/顺子/连对/飞机，炸弹与510K（杂<纯，纯按♠♥♣♦）可压一切；'
        '5算5分、10和K算10分，赢墩者得分。四人对家组队，分多者胜。',
    playerRange: (o) => o['mode'] == 'free' ? (3, 5) : (4, 4),
    options: const [
      OptionDef('mode', '模式', [OptionChoice('team', '四人对家组队'), OptionChoice('free', '各自为战（3-5人）')], 'team'),
      OptionDef('rounds', '局数', [OptionChoice(4, '4局'), OptionChoice(8, '8局'), OptionChoice(1, '1局')], 4),
    ],
    rules: wushikRules,
    create: Wushik.new,
  ),
  GameDef(
    id: 'zhengshangyou',
    name: '争上游',
    category: '牌类',
    description: '出单/对/三/顺子/连对/飞机/炸弹压过上家，先出完为上游、最后为下游；'
        '下一局下游向上游进贡最大的牌，上游还一张，由下游先出。',
    playerRange: (_) => (3, 6),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(6, '6局'), OptionChoice(10, '10局'), OptionChoice(3, '3局')], 6),
      OptionDef('decks', '牌数', [OptionChoice(0, '自动（5人以上两副）'), OptionChoice(1, '一副牌'), OptionChoice(2, '两副牌')], 0),
    ],
    rules: zhengshangyouRules,
    create: Zhengshangyou.new,
  ),
  GameDef(
    id: 'gongzhu',
    name: '拱猪',
    category: '牌类',
    description: '四人吃墩，须跟花色。猪♠Q -100，羊♦J +100，变压器♣10 使分数翻倍，红心 A-50 K-40 Q-30 J-20 5~10各-10，'
        '收全红心 +200；可亮牌加倍。有人累计到负分上限时结束，分高者胜。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('limit', '结束分数', [OptionChoice(1000, '-1000'), OptionChoice(500, '-500'), OptionChoice(2000, '-2000')], 1000),
      OptionDef('expose', '亮牌', [OptionChoice(true, '允许亮牌'), OptionChoice(false, '不亮牌')], true),
    ],
    rules: gongzhuRules,
    create: Gongzhu.new,
  ),
  GameDef(
    id: 'baccarat',
    name: '百家乐',
    category: '牌类',
    description: '八副牌牌靴，押庄、闲、和或对子，按标准补牌规则开牌，点数接近9者胜。庄赢赔0.95，和赔8倍，对子赔11倍。',
    playerRange: (_) => (1, 8),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(20, '20局'), OptionChoice(40, '40局'), OptionChoice(10, '10局')], 20),
      OptionDef('pairs', '对子', [OptionChoice(true, '开放对子下注'), OptionChoice(false, '关闭')], true),
    ],
    rules: baccaratRules,
    create: Baccarat.new,
  ),
];
