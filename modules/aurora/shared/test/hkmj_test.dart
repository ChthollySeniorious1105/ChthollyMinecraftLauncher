import 'dart:math';

import 'package:aurora_shared/games/hkmj/defs.dart';
import 'package:aurora_shared/games/hkmj/hk_fans.dart';
import 'package:aurora_shared/games/hkmj/hk_game.dart';
import 'package:aurora_shared/games/hkmj/tiles.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int t(String code) => tileFromCode(code);
Meld peng(String c) => Meld('peng', t(c), claimed: t(c), from: 0);
Meld chi(String lo) => Meld('chi', t(lo), claimed: t(lo), from: 0);
Meld agang(String c) => Meld('agang', t(c));

/// [hand] = concealed tiles EXCLUDING the winning tile [win].
HkResult? hk(String hand, String win,
    {List<Meld> melds = const [],
    bool tsumo = false,
    int seat = 1,
    int round = 0,
    List<int> flowers = const [34 + 2], // one non-seat flower by default (no 无花/正花)
    bool last = false,
    bool kong = false,
    bool rob = false,
    bool heaven = false,
    int maxFan = 10,
    bool xiaosixiLimit = false}) {
  final c = countsOf([...parseTiles(hand), t(win)]);
  return evaluateHk(
      c,
      melds,
      HkCtx(t(win),
          selfDrawn: tsumo,
          seatWind: seat,
          roundWind: round,
          lastTile: last,
          kongDraw: kong,
          robKong: rob,
          heaven: heaven,
          flowers: flowers,
          maxFan: maxFan,
          xiaosixiLimit: xiaosixiLimit));
}

void expectFan(HkResult? r, int fan, {List<String> has = const [], List<String> not = const []}) {
  expect(r, isNotNull);
  for (final n in has) {
    expect(r!.names, contains(n), reason: '$r');
  }
  for (final n in not) {
    expect(r!.names, isNot(contains(n)), reason: '$r');
  }
  expect(r!.fan, fan, reason: '$r');
}

void main() {
  group('HK fans', () {
    final open = [chi('4s')];
    test('鸡和 (open, mixed)', () {
      expectFan(hk('123m456p999s1z', '1z', melds: [chi('4m')]), 0, has: ['鸡和']);
    });
    test('平和 + 门前清', () {
      expectFan(hk('123m456m789p23s55p', '4s'), 2, has: ['平和', '门前清']);
    });
    test('对对和', () {
      expectFan(hk('111m999p5s', '5s', melds: [peng('3p'), peng('7s')]), 3, has: ['对对和']);
    });
    test('混一色', () {
      expectFan(hk('123m456m999m3z', '3z', melds: [chi('1m')]), 3, has: ['混一色'], not: ['门前清']);
    });
    test('清一色 + 平和 + 门前清 + 自摸', () {
      expectFan(hk('123456789m1134m', '2m', tsumo: true), 10, has: ['清一色', '平和', '门前清', '自摸']);
    });
    test('字一色 满贯', () {
      expectFan(hk('111z222z555z7z', '7z', melds: [peng('6z')]), 10, has: ['字一色']);
    });
    test('小三元', () {
      expectFan(hk('555z666z77z23m', '4m', melds: [chi('4p')]), 5, has: ['小三元'], not: ['白刻']);
    });
    test('大三元 8番', () {
      expectFan(hk('555z666z777z1m', '1m', melds: [chi('4p')]), 8, has: ['大三元'], not: ['中刻']);
    });
    test('小四喜 6番 / 满贯 option', () {
      expectFan(hk('222z333z44z23m', '4m', melds: [peng('1z')], seat: 3, round: 3), 9, has: ['小四喜', '混一色'], not: ['门风北']);
      expectFan(hk('222z333z44z23m', '4m', melds: [peng('1z')], xiaosixiLimit: true), 10, has: ['小四喜']);
    });
    test('大四喜 满贯', () {
      expectFan(hk('111z222z333z5m', '5m', melds: [peng('4z')]), 10, has: ['大四喜']);
    });
    test('十三幺', () {
      expectFan(hk('19m19p19s1234567z', '1m'), 10, has: ['十三幺']);
    });
    test('九莲宝灯', () {
      expectFan(hk('1112345678999m', '5m'), 10, has: ['九莲宝灯']);
    });
    test('坎坎和 (自摸) vs 对对和 (食糊 on shanpon)', () {
      expectFan(hk('111m333p555s77z99s', '9s', tsumo: true), 10, has: ['坎坎和']);
      final d = hk('111m333p555s77z99s', '9s');
      expect(d!.names, isNot(contains('坎坎和')));
      expectFan(d, 4, has: ['对对和', '门前清']);
    });
    test('三元牌刻 / 门风 / 圈风 番子', () {
      expectFan(hk('555z222z123m456p7p', '7p', seat: 1, round: 1), 4, has: ['白刻', '门风南', '圈风南', '门前清']);
    });
    test('flowers: 无花, 正花, 一台花, 八仙过海', () {
      expectFan(hk('23m456p999s11z', '1m', melds: open, flowers: []), 1, has: ['无花']);
      expectFan(hk('23m456p999s11z', '1m', melds: open, flowers: [34 + 1], seat: 1), 1, has: ['正花']);
      expectFan(hk('23m456p999s11z', '1m', melds: open, flowers: [34, 35, 36, 37], seat: 1), 2,
          has: ['一台花（春夏秋冬）'], not: ['正花']);
      expect(flowerItems([for (var i = 34; i < 42; i++) i], 0).first.$1, '八仙过海');
    });
    test('海底捞月 / 杠上开花 / 抢杠', () {
      expectFan(hk('23m456p999s11z', '1m', melds: open, tsumo: true, last: true), 2, has: ['海底捞月', '自摸']);
      expectFan(hk('23m456p999s11z', '1m', melds: open, tsumo: true, kong: true), 2, has: ['杠上开花']);
      expectFan(hk('23m456p999s11z', '1m', melds: open, rob: true), 1, has: ['抢杠']);
    });
    test('天和 满贯', () {
      expectFan(hk('23m456p789s11z999s', '1m', tsumo: true, heaven: true), 10, has: ['天和']);
    });
    test('满贯 cap option', () {
      expectFan(hk('19m19p19s1234567z', '1m', maxFan: 13), 13);
      expectFan(hk('123456789m1134m', '2m', tsumo: true, maxFan: 8), 8);
    });
    test('concealed kong keeps 门前清', () {
      expectFan(hk('123m456p789s1z', '1z', melds: [agang('9m')]), 1, has: ['门前清']);
    });
    test('not a win', () {
      expect(hk('123m456p789s11z2z', '3z'), isNull);
    });
    test('半辣上 table', () {
      expect([for (var f = 0; f <= 13; f++) hkPoints(f)], [2, 4, 8, 16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768]);
    });
  });

  group('HK engine', () {
    test('claim-cover pause happens with empty waitingFor', () {
      final setup = GameSetup(
          players: 4, options: hkmjGames.first.defaultOptions(), names: ['a', 'b', 'c', 'd'],
          bots: List.filled(4, true), rng: Random(3));
      final e = HkGame(setup);
      final host = SimHost();
      e.host = host;
      e.start();
      var pauses = 0, steps = 0;
      while (!e.isOver && steps < 3000) {
        final w = e.waitingFor;
        if (w.isEmpty) {
          if (!host.runPending()) fail('deadlock');
          continue;
        }
        e.handle(w.first, e.bot(w.first)!);
        steps++;
        if (e.phase == 'pause') {
          pauses++;
          expect(e.waitingFor, isEmpty);
          expect(e.view(0)['phase'], isNot('pause'));
          expect(e.bot(0), isNull);
        }
        host.runPending();
        expect(e.phase, isNot('pause'));
      }
      expect(pauses, greaterThan(0));
    });

    test('claim windows do not reveal other seats', () {
      final setup = GameSetup(
          players: 4, options: hkmjGames.first.defaultOptions(), names: ['a', 'b', 'c', 'd'],
          bots: List.filled(4, true), rng: Random(11));
      final e = HkGame(setup);
      final host = SimHost();
      e.host = host;
      e.start();
      var checked = 0;
      for (var steps = 0; steps < 2000 && !e.isOver; steps++) {
        final w = e.waitingFor;
        if (w.isEmpty) {
          host.runPending();
          continue;
        }
        if (e.phase == 'claim') {
          for (var s = -1; s < 4; s++) {
            final v = e.view(s);
            expect((v['waiting'] as List).every((x) => x == s), isTrue);
            for (var o = 0; o < 4; o++) {
              if (o != s) expect(((v['seats'] as List)[o] as Map)['hand'], isNull);
            }
          }
          checked++;
        }
        e.handle(w.first, e.bot(w.first)!);
        host.runPending();
      }
      expect(checked, greaterThan(0));
    });

    test('bot sims', () {
      expect(runSims(hkmjGames, n: 30, maxSteps: 60000), 0);
    }, timeout: const Timeout(Duration(minutes: 20)));
  });

  group('v3 placings', () {
    for (final def in hkmjGames) {
      for (final lvl in const [0, 1, 2]) {
        test('${def.id} botLevel $lvl: placings follow final score', () {
          _checkPlacings(def, (e) => (e as HkGame).scores, level: lvl, seed: 3 + lvl);
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
