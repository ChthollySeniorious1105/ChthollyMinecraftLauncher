import '../../src/engine.dart';
import 'hk_game.dart';
import 'rules.dart';

/// 港式麻将
final List<GameDef> hkmjGames = [
  GameDef(
    id: 'hkmj',
    rules: hkmjRules,
    name: '港式麻将',
    category: '麻将',
    description: '香港麻将：144张含花牌，13张，可吃碰杠，截糊（下家优先）。'
        '番种：鸡和0 平和1 对对和3 混一色3 清一色7 字一色满贯 小三元5 大三元8 小四喜6(可选满贯) 大四喜/十三幺/九莲宝灯/坎坎和/天和/地和/八仙过海 满贯；'
        '门前清1 自摸1 无花1 正花1 一台花2 三元牌刻1 门风/圈风刻1 海底捞月1 杠上开花1 抢杠1。'
        '半辣上计分（出铳者全付，自摸三家各付一半）：0番2 1番4 2番8 3番16 4番32 5番48 6番64 7番96 8番128 9番192 10番256 11番384 12番512 13番768，满贯封顶。'
        '包自摸：碰/杠喂出第三组三元或第四组风牌者，对方自摸大三元/大四喜时独付全部。庄家输则下庄，和牌或流局连庄。',
    playerRange: (opts) => (4, 4),
    options: const [
      OptionDef('rounds', '圈数', [OptionChoice(1, '1圈（东风圈）'), OptionChoice(4, '4圈（全庄）')], 1),
      OptionDef('minFan', '起和番', [OptionChoice(0, '鸡和可和'), OptionChoice(1, '1番起和'), OptionChoice(3, '3番起和')], 3),
      OptionDef('maxFan', '满贯番数', [OptionChoice(8, '8番'), OptionChoice(10, '10番'), OptionChoice(13, '13番')], 10),
      OptionDef('xiaosixi', '小四喜', [OptionChoice(false, '6番'), OptionChoice(true, '满贯')], false),
      OptionDef('bao', '包自摸', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
    ],
    create: HkGame.new,
  ),
];
