import '../../src/engine.dart';
import 'baohuang.dart';
import 'ginrummy.dart';
import 'gouji.dart';
import 'shuangkou.dart';

/// 够级 / 保皇 / 双扣 / Gin Rummy
final List<GameDef> cards4Games = [
  GameDef(
    id: 'gouji',
    name: '够级',
    category: '牌类',
    description: '山东六人 3v3 隔位组队，四副牌只出同点数的牌、王可挂；够级牌只有对头能管，其他人须挂王烧牌；'
        '开点前不能出 4、憋三最后出；按头科/二科…/大落计分，一队包揽前三为“闷”。',
    playerRange: (_) => (6, 6),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(4, '4局'), OptionChoice(8, '8局'), OptionChoice(2, '2局')], 4),
      OptionDef('tribute', '进贡', [OptionChoice(true, '落贡/点贡'), OptionChoice(false, '不进贡')], true),
    ],
    rules: goujiRules,
    create: Gouji.new,
  ),
  GameDef(
    id: 'baohuang',
    name: '保皇',
    category: '牌类',
    description: '五人四副牌加皇帝牌：皇帝公开，持侍卫牌的保子隐藏身份，1+1 对 3；只出同点数的牌、王当任意点数，'
        '4 张以上为炸弹；可独保（1 打 4）或暴保，分数翻倍。',
    playerRange: (_) => (5, 5),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(5, '5局'), OptionChoice(10, '10局'), OptionChoice(3, '3局')], 5),
      OptionDef('du', '独保', [OptionChoice(true, '允许独保'), OptionChoice(false, '不允许')], true),
      OptionDef('bao', '暴保', [OptionChoice(true, '允许暴保'), OptionChoice(false, '不允许')], true),
      OptionDef('bombs', '炸弹', [OptionChoice(true, '4张以上同点为炸弹'), OptionChoice(false, '无炸弹')], true),
    ],
    rules: baohuangRules,
    create: Baohuang.new,
  ),
  GameDef(
    id: 'shuangkou',
    name: '双扣',
    category: '牌类',
    description: '四人对家两副牌，出单/对/三/顺子/连对/三顺压过上家，炸弹按张数比大小，四王天王炸最大；'
        '双扣 3 分、单扣 2 分、平扣 1 分，先到目标分的一方获胜。',
    playerRange: (_) => (4, 4),
    options: const [
      OptionDef('target', '目标分', [OptionChoice(10, '10分'), OptionChoice(6, '6分'), OptionChoice(16, '16分')], 10),
      OptionDef('bombBonus', '炸弹奖励', [OptionChoice(true, '6张以上炸弹/天王炸 +1'), OptionChoice(false, '无')], true),
    ],
    rules: shuangkouRules,
    create: Shuangkou.new,
  ),
  GameDef(
    id: 'ginrummy',
    name: 'Gin Rummy',
    category: '牌类',
    description: '两人摸一弃一组成同点或同花顺组合，散牌 ≤10 点可敲牌，0 点为 Gin；对手可贴牌，反敲（Undercut）+25，先到目标分者胜。',
    playerRange: (_) => (2, 2),
    options: const [
      OptionDef('target', '目标', [OptionChoice(100, '先到100分'), OptionChoice(50, '先到50分'), OptionChoice(0, '单手决胜')], 100),
      OptionDef('knock', '敲牌上限', [OptionChoice(10, '10点'), OptionChoice(5, '5点（Oklahoma 风格）'), OptionChoice(0, '只能 Gin')], 10),
      OptionDef('layoff', '贴牌', [OptionChoice(true, '允许贴牌'), OptionChoice(false, '不允许')], true),
    ],
    rules: ginRummyRules,
    create: GinRummy.new,
  ),
];
