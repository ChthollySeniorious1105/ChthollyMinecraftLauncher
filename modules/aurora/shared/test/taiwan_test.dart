import 'dart:math';

import 'package:aurora_shared/games/taiwan/defs.dart';
import 'package:aurora_shared/games/taiwan/shapes.dart';
import 'package:aurora_shared/games/taiwan/tai.dart';
import 'package:aurora_shared/games/taiwan/taiwan_game.dart';
import 'package:aurora_shared/games/taiwan/tiles.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int t(String code) => tileFromCode(code);
Meld peng(String c) => Meld('peng', t(c), claimed: t(c), from: 0);
Meld chi(String lo) => Meld('chi', t(lo), claimed: t(lo), from: 0);
Meld agang(String c) => Meld('agang', t(c));

/// [hand] = concealed tiles EXCLUDING the winning tile [win].
TaiResult? tai(String hand, String win,
    {List<Meld> melds = const [],
    bool tsumo = false,
    int seat = 1,
    int round = 0,
    bool last = false,
    bool kong = false,
    bool rob = false,
    String flowers = ''}) {
  final c = countsOf([...parseTiles(hand), t(win)]);
  return evaluateTai(
      c,
      melds,
      TaiCtx(t(win),
          tsumo: tsumo,
          seatWind: seat,
          roundWind: round,
          lastTile: last,
          kongDraw: kong,
          robKong: rob,
          flowers: parseTiles(flowers)));
}

void main() {
  // rule tests step engines synchronously; the timing cover is tested in the sims
  claimCoverEnabled = false;
  group('shapes', () {
    test('16-tile win shape', () {
      expect(isWinShape(countsOf(parseTiles('123m456m789m123p456p55s'))), isTrue);
      expect(isWinShape(countsOf(parseTiles('123m456m789m123p456p56s'))), isFalse);
      expect(shanten(countsOf(parseTiles('123m456m789m123p456p5s')), 0), 0);
      expect(shanten(countsOf(parseTiles('123m456m789m123p456p55s')), 0), -1);
    });
  });

  group('台数', () {
    test('门清 + 平胡 (两面, 无花无字)', () {
      final r = tai('234m456m678m234p56p99s', '7p');
      expect(r!.names, containsAll(['门清', '平胡']));
      expect(r.total, 3);
    });
    test('平胡 needs no flowers and not 自摸', () {
      expect(tai('234m456m678m234p56p99s', '7p', flowers: '2f')!.names, isNot(contains('平胡')));
      expect(tai('234m456m678m234p56p99s', '7p', tsumo: true)!.names, isNot(contains('平胡')));
    });
    test('平胡 not on 边张 / honours pair', () {
      final r = tai('234m456m678m234p12p99s', '3p');
      expect(r!.names, containsAll(['边张']));
      expect(r.names, isNot(contains('平胡')));
      expect(tai('234m456m678m234p56p11z', '7p')!.names, isNot(contains('平胡')));
    });
    test('门清自摸 replaces 门清 and 自摸', () {
      final r = tai('234m456m678m234p56p99s', '7p', tsumo: true);
      expect(r!.names, contains('门清自摸'));
      expect(r.names, isNot(contains('门清')));
      expect(r.names, isNot(contains('自摸')));
      expect(r.of('门清自摸'), 3);
    });
    test('自摸 with open melds = 1', () {
      final r = tai('456m678m234p56p99s', '7p', melds: [chi('1m')], tsumo: true);
      expect(r!.names, contains('自摸'));
      expect(r.names, isNot(contains('门清')));
      expect(r.of('自摸'), 1);
    });
    test('中洞 / 单钓 独听', () {
      expect(tai('234m456m678m234p57p99s', '6p')!.names, contains('中洞'));
      expect(tai('234m456m678m234p567p9s', '9s')!.names, contains('单钓'));
    });
    test('正花 and 花槓', () {
      // seat 1 (南): 夏(2f) and 兰(6f) are 正花
      final r = tai('234m456m678m234p56p99s', '7p', flowers: '26f');
      expect(r!.of('正花(夏)') + r.of('正花(兰)'), 2);
      final k = tai('234m456m678m234p56p99s', '7p', flowers: '1234f');
      expect(k!.names, contains('花槓(春夏秋冬)'));
      expect(k.of('花槓(春夏秋冬)'), 2);
      expect(tai('234m456m678m234p56p99s', '7p', flowers: '13f')!.names.any((n) => n.startsWith('正花')), isFalse);
    });
    test('八仙过海 flower tai', () {
      expect(flowerTai(parseTiles('12345678f'), 0), [('八仙过海', 8)]);
    });
    test('三元刻 / 风刻', () {
      final r = tai('555z234m456m678m23p99s', '4p', seat: 1, round: 0);
      expect(r!.names, contains('三元牌(白)'));
      final w = tai('222z234m456m678m23p99s', '4p', seat: 1, round: 1);
      expect(w!.names, containsAll(['圈风(南)', '门风(南)']));
    });
    test('小三元 / 大三元', () {
      expect(tai('555z666z77z234m456m11p', '7z')!.names, contains('大三元'));
      final r = tai('555z666z7z234m456m678m', '7z');
      expect(r!.names, contains('小三元'));
      expect(r.names, isNot(contains('三元牌(白)')));
    });
    test('小四喜 / 大四喜', () {
      expect(tai('111z222z333z44z234m99p', '4z')!.names, contains('大四喜'));
      expect(tai('111z222z333z4z234m567m', '4z')!.names, contains('小四喜'));
    });
    test('碰碰胡 + 清一色 + 四暗刻', () {
      final r = tai('111m333m555m77m99m', '9m', melds: [peng('2m')]);
      expect(r!.names, containsAll(['碰碰胡', '清一色', '三暗刻']));
      // 9m completed by a discard is a 明刻; on 自摸 it is 暗刻
      final z = tai('111m333m555m77m99m', '9m', melds: [peng('2m')], tsumo: true);
      expect(z!.names, contains('四暗刻'));
      expect(z.names, contains('自摸'));
    });
    test('五暗刻 on 自摸', () {
      final r = tai('111m333m555p777s222z9m', '9m', tsumo: true);
      expect(r!.names, containsAll(['五暗刻', '碰碰胡', '门清自摸']));
    });
    test('三暗刻 and 混一色', () {
      final r = tai('111p333p555p78p11z', '9p', melds: [chi('2p')]);
      expect(r!.names, containsAll(['三暗刻', '混一色']));
    });
    test('字一色', () {
      final r = tai('111z222z333z55z66z', '6z', melds: [peng('7z')]);
      expect(r!.names, contains('字一色'));
      expect(r.names, isNot(contains('混一色')));
    });
    test('全求人', () {
      final r = tai('9s', '9s', melds: [chi('1m'), chi('4m'), chi('1p'), peng('5p'), chi('7s')]);
      expect(r!.names, containsAll(['全求人', '单钓']));
    });
    test('海底捞月 / 河底捞鱼 / 杠上开花 / 抢杠', () {
      expect(tai('234m456m678m234p56p99s', '7p', tsumo: true, last: true)!.names, contains('海底捞月'));
      expect(tai('234m456m678m234p56p99s', '7p', last: true)!.names, contains('河底捞鱼'));
      expect(tai('234m456m678m234p56p99s', '7p', tsumo: true, kong: true)!.names, contains('杠上开花'));
      expect(tai('234m456m678m234p56p99s', '7p', rob: true)!.names, contains('抢杠'));
    });
  });

  group('engine', () {
    TaiwanGame newGame([int seed = 3]) {
      final g = TaiwanGame(GameSetup(
          players: 4, options: taiwanGames.first.defaultOptions(), names: ['A', 'B', 'C', 'D'], bots: List.filled(4, true), rng: Random(seed)));
      g.host = SimHost();
      g.start();
      return g;
    }

    test('dealt 16 tiles, dealer 17', () {
      final g = newGame();
      if (g.phase != 'act') return; // 八仙过海 on deal (very unlikely)
      for (var s = 0; s < 4; s++) {
        final n = countTotal(g.hands[s]);
        expect(n, s == g.dealer ? 17 : 16);
      }
    });

    test('连庄拉庄: 连2 dealer tsumo pays base + (tai + 5)*per', () {
      final g = newGame();
      g.lian = 2;
      g.dealer = 0;
      g.handDelta = List.filled(4, 0);
      g.scores = List.filled(4, 0);
      g.phase = 'act';
      g.turn = 0;
      g.hands[0] = countsOf(parseTiles('234m456m678m234p567p99s'));
      g.melds[0] = [];
      g.flowers[0] = [];
      g.drawn[0] = t('7p');
      g.drawCount[0] = 5;
      g.discards[0] = [];
      g.anyCall = true;
      g.canTsumo = true;
      g.handle(0, {'type': 'hu'});
      final st = g.settle!;
      final names = [for (final it in st['items'] as List) (it as List)[0]];
      expect(names, containsAll(['门清自摸', '庄家', '连2拉2']));
      // 门清自摸3 + 庄家1 + 连2拉2 4 = 8 台; 100 + 8*20 = 260 from each
      final tai0 = st['tai'] as int;
      expect(tai0, 3);
      expect(g.scores[1], -(100 + (tai0 + 5) * 20));
      expect(g.scores[0], 3 * (100 + 8 * 20));
      expect(g.lian, 3); // dealer keeps
    });

    test('放枪 only the discarder pays; 庄家 台 when dealer pays', () {
      final g = newGame();
      g.lian = 0;
      g.dealer = 2;
      g.handDelta = List.filled(4, 0);
      g.scores = List.filled(4, 0);
      g.hands[1] = countsOf(parseTiles('234m456m678m234p56p99s'));
      g.melds[1] = [];
      g.flowers[1] = [];
      g.hands[2] = countsOf(parseTiles('7p'));
      g.discards[2] = [];
      g.anyCall = true;
      g.phase = 'act';
      g.turn = 2;
      g.handle(2, {'type': 'discard', 'tile': '7p'});
      expect(g.claim!.opts[1], contains('hu'));
      g.handle(1, {'type': 'hu'});
      while (g.phase == 'claim') {
        g.handle(g.claim!.pending.first, {'type': 'pass'});
      }
      // 门清1 + 平胡2 = 3, + 庄家1 = 4 台
      expect(g.scores[2], -(100 + 4 * 20));
      expect(g.scores[0], 0);
      expect(g.scores[3], 0);
      expect(g.dealer, 3); // deal passes
    });

    test('八仙过海 ends the hand, all pay 8 台', () {
      final g = newGame();
      g.dealer = 0;
      g.lian = 0;
      g.handDelta = List.filled(4, 0);
      g.scores = List.filled(4, 0);
      g.flowers[1] = parseTiles('1234567f');
      g.wall.add(t('8f'));
      g.turn = 1;
      g.hands[1] = List.filled(kKinds, 0);
      g.drawnForTest(1);
      expect(g.settle!['flowerWin'], '八仙过海');
      expect(g.scores[2], -(100 + 8 * 20));
      expect(g.scores[0], -(100 + 9 * 20)); // dealer pays +1 庄家台
    });

    test('七抢一: holder of the 8th flower pays', () {
      final g = newGame();
      g.dealer = 0;
      g.lian = 0;
      g.handDelta = List.filled(4, 0);
      g.scores = List.filled(4, 0);
      g.flowers = [[], parseTiles('1234567f'), [], []];
      g.wall.add(t('8f'));
      g.drawnForTest(3);
      expect(g.settle!['flowerWin'], '七抢一');
      expect(g.scores[3], -(100 + 8 * 20));
      expect(g.scores[0], 0);
    });
  });

  test('bot sims', () {
    expect(runSims(taiwanGames, n: 30, maxSteps: 200000), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('v3 placings', () {
    for (final def in taiwanGames) {
      for (final lvl in const [0, 1, 2]) {
        test('${def.id} botLevel $lvl: placings follow final score', () {
          _checkPlacings(def, (e) => (e as TaiwanGame).scores, level: lvl, seed: 3 + lvl);
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
