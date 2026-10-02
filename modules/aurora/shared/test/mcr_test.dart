import 'package:aurora_shared/games/mcr/mcr_game.dart';
import 'package:aurora_shared/src/engine.dart';
import 'dart:math';
import 'package:aurora_shared/games/mcr/defs.dart';
import 'package:aurora_shared/games/mcr/gd_fans.dart';
import 'package:aurora_shared/games/mcr/mcr_fans.dart';
import 'package:aurora_shared/games/mcr/shapes.dart';
import 'package:aurora_shared/games/mcr/tiles.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int t(String code) => tileFromCode(code);
Meld peng(String c) => Meld('peng', t(c), claimed: t(c), from: 0);
Meld chi(String lo) => Meld('chi', t(lo), claimed: t(lo), from: 0);
Meld agang(String c) => Meld('agang', t(c));
Meld mgang(String c) => Meld('mgang', t(c), claimed: t(c), from: 0);

/// [hand] = concealed tiles EXCLUDING the winning tile [win].
McrResult? mcr(String hand, String win,
    {List<Meld> melds = const [],
    bool tsumo = false,
    int seat = 0,
    int round = 0,
    bool last = false,
    bool kong = false,
    bool rob = false,
    bool lastCopy = false,
    int flowers = 0}) {
  final c = countsOf([...parseTiles(hand), t(win)]);
  return evaluateMcr(
      c,
      melds,
      WinCtx(t(win),
          selfDrawn: tsumo,
          seatWind: seat,
          roundWind: round,
          lastTile: last,
          kongDraw: kong,
          robKong: rob,
          lastCopy: lastCopy,
          flowers: flowers));
}

GdResult? gd(String hand, {List<Meld> melds = const [], bool tsumo = false, bool kong = false, bool qidui = true}) =>
    evaluateGd(countsOf(parseTiles(hand)), melds, GdCtx(selfDrawn: tsumo, kongDraw: kong, sevenPairs: qidui));

void expectFan(McrResult? r, int total, {List<String> has = const [], List<String> not = const []}) {
  expect(r, isNotNull);
  for (final n in has) {
    expect(r!.names, contains(n), reason: '$r');
  }
  for (final n in not) {
    expect(r!.names, isNot(contains(n)), reason: '$r');
  }
  expect(r!.total, total, reason: '$r');
}

void main() {
  // rule tests step engines synchronously; the timing cover is tested in the sims
  claimCoverEnabled = false;
  group('MCR fans', () {
    test('81 fans defined', () {
      expect(mcrFanValues.keys.where((k) => k != '幺九刻(风)').length, 81);
    });
    test('清一色+一色三同顺 不计一般高', () {
      expectFan(mcr('1237895m', '5m', melds: [chi('1m'), chi('1m')]), 52,
          has: ['一色三同顺', '清一色', '平和', '老少副', '单钓将'], not: ['一般高', '无字']);
    });
    test('大四喜 暗刻 不计风刻/碰碰和/幺九刻', () {
      expectFan(mcr('111222333444z5m', '5m'), 159,
          has: ['大四喜', '四暗刻', '混一色', '单钓将'],
          not: ['圈风刻', '门风刻', '三风刻', '碰碰和', '幺九刻', '门前清']);
    });
    test('大四喜 全求人', () {
      expectFan(mcr('5m', '5m', melds: [peng('1z'), peng('2z'), peng('3z'), peng('4z')]), 100,
          has: ['大四喜', '混一色', '全求人'], not: ['单钓将', '碰碰和', '幺九刻']);
    });
    test('七对 不计门前清/单钓将', () {
      expectFan(mcr('1122m3344p5566s7z', '7z'), 24, has: ['七对'], not: ['门前清', '单钓将', '不求人']);
    });
    test('七对 自摸 不计不求人', () {
      expectFan(mcr('1122m3344p5566s7z', '7z', tsumo: true), 25, has: ['七对', '自摸'], not: ['不求人']);
    });
    test('十三幺', () {
      expectFan(mcr('19m19p19s1234567z', '1m'), 88, has: ['十三幺'], not: ['五门齐', '混幺九', '门前清', '单钓将']);
    });
    test('全不靠', () {
      expectFan(mcr('147m25p369s12345z', '6z'), 12, has: ['全不靠'], not: ['五门齐', '门前清', '组合龙']);
    });
    test('全不靠+组合龙', () {
      expectFan(mcr('147m258p369s1234z', '5z'), 24, has: ['全不靠', '组合龙']);
    });
    test('七星不靠 不计全不靠', () {
      expectFan(mcr('147m25p36s123456z', '7z'), 24, has: ['七星不靠'], not: ['全不靠', '五门齐', '门前清']);
    });
    test('组合龙+平和', () {
      expectFan(mcr('147m258p369s23s55m', '4s'), 16, has: ['组合龙', '平和', '门前清'], not: ['无字']);
    });
    test('清龙+平和+单钓将', () {
      expectFan(mcr('123456789m234p5s', '5s'), 21, has: ['清龙', '平和', '门前清', '单钓将']);
    });
    test('碰碰和+三暗刻', () {
      expectFan(mcr('555p777s999m8s', '8s', melds: [peng('2m')]), 24,
          has: ['碰碰和', '三暗刻', '幺九刻', '无字'], not: ['单钓将', '双暗刻']);
    });
    test('一色四同顺 不计四归一/一般高', () {
      expectFan(mcr('1112223333p9s1p2p', '9s'), 65,
          has: ['一色四同顺', '推不倒', '全带幺', '平和', '门前清', '单钓将'],
          not: ['四归一', '一般高', '一色三同顺', '缺一门']);
    });
    test('大三元 不计箭刻', () {
      expectFan(mcr('234m9p', '9p', melds: [peng('5z'), peng('6z'), peng('7z')]), 90,
          has: ['大三元', '缺一门', '单钓将'], not: ['箭刻', '双箭刻']);
    });
    test('小三元+混一色+连六', () {
      expectFan(mcr('77z12345m', '6m', melds: [peng('5z'), peng('6z')]), 71,
          has: ['小三元', '混一色', '连六'], not: ['箭刻', '双箭刻']);
    });
    test('不足8番', () {
      final r = mcr('234m234p567s67s55m', '8s')!;
      expect(r.total, 7, reason: '$r');
      expect(r.names, containsAll(['平和', '断幺', '门前清', '喜相逢']));
    });
    test('花牌不计起和番', () {
      final r = mcr('234m234p567s67s55m', '8s', flowers: 2)!;
      expect(r.total, 9);
      expect(r.base, 7);
    });
    test('抢杠和 不计和绝张', () {
      expectFan(mcr('234m234p567s67s55m', '8s', rob: true, lastCopy: true), 15, has: ['抢杠和'], not: ['和绝张']);
    });
    test('妙手回春 不计自摸, 不求人', () {
      expectFan(mcr('234m234p567s67s55m', '8s', tsumo: true, last: true), 17,
          has: ['妙手回春', '不求人'], not: ['自摸', '门前清']);
    });
    test('杠上开花', () {
      expectFan(mcr('234m234p567s67s55m', '8s', tsumo: true, kong: true), 17, has: ['杠上开花'], not: ['自摸']);
    });
    test('三色三同顺 不计喜相逢', () {
      expectFan(mcr('234m234p234s78s55p', '9s'), 12, has: ['三色三同顺', '平和', '门前清'], not: ['喜相逢']);
    });
    test('花龙', () {
      expectFan(mcr('123m456p789s555m8p', '8p'), 12, has: ['花龙', '门前清', '单钓将', '无字']);
    });
    test('连七对 计断幺', () {
      expectFan(mcr('2233445566778m', '8m'), 90, has: ['连七对', '断幺'], not: ['七对', '清一色', '门前清']);
    });
    test('九莲宝灯 不计清一色', () {
      final r = mcr('1112345678999m', '5m')!;
      expect(r.names, contains('九莲宝灯'));
      expect(r.names, isNot(contains('清一色')));
      expect(r.total, greaterThanOrEqualTo(88));
    });
    test('绿一色 不计混一色', () {
      expectFan(mcr('223344s666s888s6z', '6z'), 94,
          has: ['绿一色', '一般高', '双暗刻', '门前清', '单钓将'], not: ['混一色']);
    });
    test('双暗杠 不求人', () {
      expectFan(mcr('234s567s8s', '8s', melds: [agang('1m'), agang('9p')], tsumo: true), 14,
          has: ['双暗杠', '不求人', '幺九刻', '连六'], not: ['双暗刻', '暗杠', '自摸', '单钓将']);
    });
    test('三风刻 + 门风刻 不计风幺九刻', () {
      expectFan(mcr('123m5m', '5m', melds: [peng('2z'), peng('3z'), peng('4z')], seat: 1), 21,
          has: ['三风刻', '门风刻', '混一色', '单钓将'], not: ['幺九刻', '圈风刻']);
    });
    test('全小+三色三同顺+一般高+边张', () {
      expectFan(mcr('123m123p12s123s22m', '3s'), 38,
          has: ['全小', '三色三同顺', '一般高', '平和', '门前清', '边张'], not: ['小于五', '喜相逢', '无字']);
    });
    test('三同刻 不计双同刻', () {
      expectFan(mcr('222s456m8p', '8p', melds: [peng('2m'), peng('2p')]), 19,
          has: ['三同刻', '断幺', '单钓将'], not: ['双同刻', '无字']);
    });
    test('一色三步高', () {
      expectFan(mcr('123m234m345m78p99p', '6p'), 21, has: ['一色三步高', '平和', '门前清', '缺一门']);
    });
    test('四杠', () {
      final r = mcr('5m', '5m', melds: [mgang('1m'), mgang('2p'), mgang('3s'), agang('4z')])!;
      expect(r.names, contains('四杠'));
      expect(r.names, isNot(contains('碰碰和')));
      expect(r.names, isNot(contains('单钓将')));
    });
    test('win shape detection', () {
      expect(isWinShape(countsOf(parseTiles('147m258p369s12345z')), 0), isTrue);
      expect(isWinShape(countsOf(parseTiles('147m258p369s11234z')), 0), isFalse);
    });
  });

  group('广东推倒胡', () {
    test('鸡胡', () => expect(gd('123m456p789s111z55s')!.fan, 0));
    test('平胡', () => expect(gd('123m456p789s234s55s')!.fan, 1));
    test('碰碰胡+混一色', () {
      final r = gd('111m222m555m111z99m')!;
      expect(r.names, containsAll(['碰碰胡', '混一色']));
      expect(r.fan, 4);
    });
    test('清一色碰碰胡', () => expect(gd('111m222m555m777m99m')!.fan, 6));
    test('七对选项', () {
      expect(gd('1122m3344p5566s77z')!.fan, 4);
      expect(gd('1122m3344p5566s77z', qidui: false), isNull);
    });
    test('十三幺/字一色/大三元 满贯', () {
      expect(gd('19m19p19s12345677z')!.limit, isTrue);
      expect(gd('111222333444z55z')!.limit, isTrue);
      expect(gd('555666777z123m99p')!.limit, isTrue);
    });
    test('自摸加倍+杠上开花', () => expect(gd('123m456p789s234s55s', tsumo: true, kong: true)!.fan, 3));
    test('封顶', () {
      expect(gdPoints(2, 16), 4);
      expect(gdPoints(5, 16), 16);
      expect(gdPoints(gdLimit, 8), 8);
    });
    test('买马', () {
      // tsumo, 1 horse hit: each of 3 payers pays 4 * 2
      expect(gdSettle(4, 1, [0, 2, 3], 4, 1), [-8, 24, -8, -8]);
      // discard, no hit
      expect(gdSettle(4, 1, [2], 4, 0), [0, 4, -4, 0]);
      // 抢杠胡 包三家
      expect(gdSettle(4, 1, [0, 2, 3], 2, 0, robbedFrom: 2), [0, 6, -6, 0]);
      expect(horseTarget(t('1m')), 0);
      expect(horseTarget(t('2p')), 1);
      expect(horseTarget(t('4s')), 3);
      expect(horseTarget(t('7z')), 0);
    });
  });

  test('bot simulations', () {
    expect(runSims(mcrGames, n: 30, maxSteps: 200000), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('v3 placings', () {
    for (final def in mcrGames) {
      for (final lvl in const [0, 1, 2]) {
        test('${def.id} botLevel $lvl: placings follow final score', () {
          _checkPlacings(def, (e) => (e as McrGame).scores, level: lvl, seed: 3 + lvl);
        }, timeout: const Timeout(Duration(minutes: 5)));
      }
    }
  });
}


/// v3: plays [def] to the end with bots at [level] and checks placings follow the final scores.
void _checkPlacings(GameDef def, List<int> Function(GameEngine) scoresOf, {int seed = 5, int level = 1, Map<String, dynamic> opts = const {}}) {
  final o = {...def.defaultOptions(), ...opts};
  final n = def.playerRange(o).$1;
  final e = def.create(GameSetup(
      players: n,
      options: o,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
      botLevel: level));
  final host = SimHost();
  e.host = host;
  e.start();
  host.runPending();
  var steps = 0;
  while (!e.isOver && steps++ < 200000) {
    expect(e.placings, isNull);
    final w = e.waitingFor;
    if (w.isEmpty) {
      expect(host.runPending(), isTrue);
      continue;
    }
    e.handle(w.first, e.runBot(w.first)!);
    host.runPending();
  }
  expect(e.isOver, isTrue);
  final p = e.placings!;
  final sc = scoresOf(e);
  expect(p.length, n);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (sc[i] > sc[j]) expect(p[i], lessThan(p[j]), reason: 'scores $sc placings $p');
      if (sc[i] == sc[j] && !def.id.startsWith('riichi') && !def.id.startsWith('majsoul')) {
        expect(p[i], p[j], reason: 'ties share a rank: $sc $p');
      }
    }
  }
  expect(def.rules.length, greaterThan(300));
}
