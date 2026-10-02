import '../../src/engine.dart';
import 'engine.dart';
import 'rules.dart';

const _winds = OptionDef('length', '局数', [OptionChoice(1, '东风战'), OptionChoice(2, '半庄战')], 2);
const _aka = OptionDef('aka', '赤宝牌', [OptionChoice(true, '有'), OptionChoice(false, '无')], true);
const _kuitan = OptionDef('kuitan', '食断', [OptionChoice(true, '有'), OptionChoice(false, '无')], true);

const _nagashi = OptionDef('nagashi', '流局满贯', [OptionChoice(true, '开'), OptionChoice(false, '关')], true);
const _triple = OptionDef('tripleRon', '三家和了流局', [OptionChoice(true, '开'), OptionChoice(false, '关')], false);
const _uma4 = OptionDef('uma', '马点',
    [OptionChoice('none', '无'), OptionChoice('5-10', '5-10'), OptionChoice('10-20', '10-20'), OptionChoice('10-30', '10-30')],
    '10-20');
const _uma3 = OptionDef('uma', '马点', [OptionChoice('none', '无'), OptionChoice('15', '15（+15/0/-15）')], '15');

List<int> _umaOf(String v, bool sanma) {
  if (sanma) return v == '15' ? const [15, 0, -15] : const [0, 0, 0];
  switch (v) {
    case '5-10':
      return const [10, 5, -5, -10];
    case '10-30':
      return const [30, 10, -10, -30];
    case 'none':
      return const [0, 0, 0, 0];
  }
  return const [20, 10, -10, -20];
}

GameEngine _riichi4(GameSetup s) => RiichiGame(
    s,
    RiichiRules(
      mode: 'riichi4',
      winds: s.opt<int>('length', 2),
      aka: s.opt<bool>('aka', true),
      kuitan: s.opt<bool>('kuitan', true),
      abortive: true,
      tripleRonAbort: s.opt<bool>('tripleRon', false),
      nagashi: s.opt<bool>('nagashi', true),
      pao: true,
      uma: _umaOf(s.opt<String>('uma', '10-20'), false),
      returnPoints: 30000,
    ));

GameEngine _riichi3(GameSetup s) => RiichiGame(
    s,
    RiichiRules(
      mode: 'riichi3',
      sanma: true,
      startPoints: 35000,
      winds: s.opt<int>('length', 2),
      aka: s.opt<bool>('aka', true),
      kuitan: s.opt<bool>('kuitan', true),
      abortive: true,
      nagashi: s.opt<bool>('nagashi', true),
      pao: true,
      uma: _umaOf(s.opt<String>('uma', '15'), true),
      returnPoints: 40000,
    ));

/// 日本麻将 + 雀魂模式
final List<GameDef> riichiGames = [
  GameDef(
    id: 'riichi4',
    rules: riichi4Rules,
    name: '日本麻将（四人）',
    category: '麻将',
    description: '标准立直麻将：一番起和，宝牌/里宝牌/赤宝牌，振听、食替禁止，25000 点起 30000 点返，飞人即结束。'
        '含途中流局（九种九牌/四风连打/四家立直/四杠散了）、流局满贯、大三元/大四喜包牌与马点。',
    playerRange: (_) => (4, 4),
    options: const [_winds, _aka, _kuitan, _nagashi, _triple, _uma4],
    create: _riichi4,
  ),
  GameDef(
    id: 'riichi3',
    rules: riichi3Rules,
    name: '日本麻将（三人）',
    category: '麻将',
    description: '三麻：去掉 2~8 万，不能吃，北可拔北当宝牌（从岭上补牌），自摸损（北家那份不付），35000 点起 40000 点返。'
        '含九种九牌/四杠散了、流局满贯、包牌与马点。',
    playerRange: (_) => (3, 3),
    options: const [_winds, _aka, _kuitan, _nagashi, _uma3],
    create: _riichi3,
  ),
  GameDef(
    id: 'majsoul_shura',
    rules: shuraRules,
    name: '修罗之战',
    category: '麻将',
    description: '雀魂修罗之战（东风战）：开局换三张（任选 3 张，方向随机），血战到底——和牌者退出本局，'
        '其余人继续，三家和牌或荒牌才结束；已和牌者不付自摸（自摸损），流局未听者向每位听牌者付 1000 点；无连庄/本场。',
    playerRange: (_) => (4, 4),
    create: (s) => RiichiGame(
        s, const RiichiRules(mode: 'shura', winds: 1, bloodbath: true, exchange: true, renchan: false)),
  ),
  GameDef(
    id: 'majsoul_wanxiang',
    rules: wanxiangRules,
    name: '万象修罗',
    category: '麻将',
    description: '在修罗之战基础上：牌山之外额外加入 4 张百搭牌（专属图案），开局每人配 1 张，可当任意牌使用且取最高打点；'
        '百搭牌不能打出或交换，本身不算宝牌。',
    playerRange: (_) => (4, 4),
    create: (s) => RiichiGame(
        s, const RiichiRules(mode: 'wanxiang', winds: 1, bloodbath: true, exchange: true, wild: true, renchan: false)),
  ),
  GameDef(
    id: 'majsoul_mingjing',
    rules: mingjingRules,
    name: '明镜之战',
    category: '麻将',
    description: '鹫巢麻将：每种牌 4 张中有 3 张透明牌（所有人可见，包括他人手牌和牌山），1 张为普通暗牌；东风战，无连庄。',
    playerRange: (_) => (4, 4),
    create: (s) => RiichiGame(s, const RiichiRules(mode: 'mingjing', winds: 1, mirror: true, renchan: false)),
  ),
  GameDef(
    id: 'majsoul_anye',
    rules: anyeRules,
    name: '暗夜之战',
    category: '麻将',
    description: '东风战。打牌时可付 1000 点盖牌打出（暗牌，暗牌立直需 2000 点以上），暗牌不能被吃碰杠荣和、不算振听；'
        '其他人可付 2000 点开牌将其翻开（多人时离打牌者下家最近者付），此时打牌者可再付 4000 点锁定。所付点数进入供托，由下一位和牌者获得。',
    playerRange: (_) => (4, 4),
    create: (s) => RiichiGame(s, const RiichiRules(mode: 'anye', winds: 1, dark: true)),
  ),
];
