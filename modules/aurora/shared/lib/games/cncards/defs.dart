import '../../src/engine.dart';
import 'bigtwo.dart';
import 'douniu.dart';
import 'rules.dart';
import 'shisanshui.dart';
import 'zhajinhua.dart';

/// 锄大地/炸金花/斗牛/十三水
final List<GameDef> cncardsGames = [
  GameDef(
    id: 'bigtwo',
    name: '锄大地',
    category: '牌类',
    description: '持♦3者先出，单张、对子、三条、五张牌型（顺子<同花<葫芦<铁支<同花顺）轮流压牌，先出完者赢，剩牌越多扣分越多。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(4, '4局'), OptionChoice(8, '8局'), OptionChoice(1, '1局')], 4),
      OptionDef('double', '剩牌翻倍', [OptionChoice(true, '10张×2 / 13张×3'), OptionChoice(false, '不翻倍')], true),
    ],
    rules: bigtwoRules,
    create: BigTwo.new,
  ),
  GameDef(
    id: 'zhajinhua',
    name: '炸金花',
    category: '牌类',
    description: '每人三张牌，可闷牌或看牌，跟注、加注、比牌、弃牌。豹子>顺金>金花>顺子>对子>散牌，最后留下者赢得底池。',
    playerRange: (_) => (2, 9),
    options: const [
      OptionDef('hands', '局数', [OptionChoice(10, '10局'), OptionChoice(20, '20局'), OptionChoice(5, '5局')], 10),
      OptionDef('cap', '封顶轮数', [OptionChoice(10, '10轮'), OptionChoice(5, '5轮'), OptionChoice(20, '20轮')], 10),
      OptionDef('r235', '235吃豹子', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
    ],
    rules: zhajinhuaRules,
    create: Zhajinhua.new,
  ),
  GameDef(
    id: 'douniu',
    name: '斗牛',
    category: '牌类',
    description: '每人五张牌，任选三张凑成10的倍数，剩余两张点数定牛几；闲家与庄家比牌，牛牛、五花牛、炸弹牛、五小牛赔率更高。',
    playerRange: (_) => (2, 8),
    options: const [
      OptionDef('banker', '坐庄方式', [OptionChoice('grab', '抢庄'), OptionChoice('rotate', '轮流坐庄')], 'grab'),
      OptionDef('mingpai', '明牌', [OptionChoice(true, '先看四张'), OptionChoice(false, '不看牌')], true),
      OptionDef('specials', '特殊牌型', [OptionChoice(true, '五花/炸弹/五小牛'), OptionChoice(false, '关闭')], true),
      OptionDef('pay', '赔率', [OptionChoice('std', '经典（牛牛×3）'), OptionChoice('high', '疯狂（牛几×几）')], 'std'),
      OptionDef('hands', '局数', [OptionChoice(10, '10局'), OptionChoice(20, '20局'), OptionChoice(5, '5局')], 10),
    ],
    rules: douniuRules,
    create: Douniu.new,
  ),
  GameDef(
    id: 'shisanshui',
    name: '十三水',
    category: '牌类',
    description: '十三张牌摆成前墩3张、中墩5张、后墩5张，须后≥中≥前（否则倒水）。与每位对手逐墩比较，三墩全胜为打枪翻倍。',
    playerRange: (_) => (2, 4),
    options: const [
      OptionDef('rounds', '局数', [OptionChoice(5, '5局'), OptionChoice(10, '10局'), OptionChoice(1, '1局')], 5),
      OptionDef('specials', '特殊牌型', [OptionChoice(true, '一条龙/六对半/三同花/三顺子'), OptionChoice(false, '关闭')], true),
      OptionDef('homerun', '全垒打', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
    ],
    rules: shisanshuiRules,
    create: Shisanshui.new,
  ),
];
