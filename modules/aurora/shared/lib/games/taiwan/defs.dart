import '../../src/engine.dart';
import 'rules.dart';
import 'taiwan_game.dart';

/// 台湾十六张麻将
final List<GameDef> taiwanGames = [
  GameDef(
    id: 'taiwan16',
    rules: taiwanRules,
    name: '台湾十六张',
    category: '麻将',
    description: '台湾十六张麻将：144张含8花，手牌16张（胡牌5组+1将），可吃（仅上家）碰杠，补花，庄家连庄拉庄（连N拉N加2N台）。'
        '放枪者付 底+台×每台，自摸三家各付。台数：庄家1、门清1、自摸1、门清自摸3、正花1、花槓2、风/三元刻1、小三元4、大三元8、'
        '小四喜8、大四喜16、碰碰胡4、混一色4、清一色8、字一色16、平胡2、全求人2、海底/河底/杠上开花/抢杠1、'
        '独听(边张/中洞/单钓)1、三暗刻2、四暗刻5、五暗刻8、天胡16、地胡16、人胡8、八仙过海8、七抢一8。',
    playerRange: (opts) => (4, 4),
    options: const [
      OptionDef('rounds', '圈数', [OptionChoice(1, '一圈（东风圈）'), OptionChoice(4, '一将（四圈）')], 1),
      OptionDef('stake', '底/台', [
        OptionChoice('100/20', '底100 / 每台20'),
        OptionChoice('300/100', '底300 / 每台100'),
        OptionChoice('50/10', '底50 / 每台10'),
      ], '100/20'),
    ],
    create: TaiwanGame.new,
  ),
];
