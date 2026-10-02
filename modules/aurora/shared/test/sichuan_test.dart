import 'package:aurora_shared/games/sichuan/sichuan.dart';
import 'package:aurora_shared/src/engine.dart';
import 'dart:math';

import 'package:aurora_shared/games/sichuan/defs.dart';
import 'package:aurora_shared/games/sichuan/tiles.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<int> hand(String s) {
  // e.g. "123m456p" style
  final out = <int>[];
  final digits = <int>[];
  for (final ch in s.split('')) {
    if ('mps'.contains(ch)) {
      for (final d in digits) {
        out.add(tileFromCode('$d$ch'));
      }
      digits.clear();
    } else {
      digits.add(int.parse(ch));
    }
  }
  return countsOf(out);
}

FanResult? ev(String s, [List<Meld> melds = const [], int que = -1]) => evaluateHand(hand(s), melds, que: que);
List<String> names(FanResult r) => [for (final (n, _) in r.items) n];

void main() {
  // rule tests step engines synchronously; the timing cover is tested in the sims
  claimCoverEnabled = false;
  group('fan', () {
    test('平胡', () {
      final r = ev('123456m789p22s345s')!;
      expect(r.fan, 0);
      expect(names(r), ['平胡']);
    });
    test('对对胡', () {
      expect(ev('111m333m555p777s99s')!.fan, 1);
    });
    test('清一色', () {
      final r = ev('11123456789999m')!;
      // 1112345678999 + 9 : contains 4x9 -> 根
      expect(names(r), containsAll(['清一色', '根']));
      expect(r.fan, 3);
      expect(evaluateHand(hand('12345678999m'), [Meld('peng', 0, 1)])!.fan, 3); // 清一色 + 根(1m)
    });
    test('七对 / 龙七对 / 清七对 / 清龙七对', () {
      expect(names(ev('113355m7799p2244s')!), ['七对']);
      expect(ev('113355m7799p2244s')!.fan, 2);
      expect(ev('111155m7799p2244s')!.fan, 3);
      expect(names(ev('111155m7799p2244s')!), ['龙七对']);
      expect(ev('11335577992244m')!.fan, 4);
      expect(ev('11115577992244m')!.fan, 5);
      expect(ev('11115555992244m')!.fan, 6); // 清龙七对 + 1 根
    });
    test('清对', () {
      expect(ev('11122233355566p')!.fan, 3);
    });
    test('将对', () {
      expect(names(ev('222m555m888p222s55s')!), ['将对']);
      expect(ev('222m555m888p222s55s')!.fan, 3);
    });
    test('带幺九', () {
      final r = ev('123m789m123p999s11s')!;
      expect(names(r), ['带幺九']);
      expect(r.fan, 2);
    });
    test('melds count toward 对对胡 and 根', () {
      final m = [Meld('peng', tileFromCode('3m'), 1), Meld('agang', tileFromCode('7p'), -1)];
      final r = evaluateHand(hand('555s888s11s'), m)!;
      expect(names(r), containsAll(['对对胡', '根']));
      expect(r.fan, 2);
      final m2 = [Meld('peng', tileFromCode('3m'), 1)];
      final r2 = evaluateHand(hand('345m456m888s11s'), m2)!; // 3m in hand + peng = 根
      expect(r2.fan, 1);
    });
    test('缺门 blocks win', () {
      expect(ev('123m456m789p22s345s', const [], 0), isNull);
      expect(ev('123m456m789p22s345s', const [], 1), isNull);
      expect(ev('123m456m789m22s345s', const [], 1), isNotNull);
    });
    test('not a win', () {
      expect(ev('123m456m789p22s346s'), isNull);
    });
  });

  group('tenpai', () {
    test('waits', () {
      final c = hand('1112345678999m');
      expect(waitingTiles(c, const [], que: 1).length, 9);
      expect(shanten(c, 0), 0);
      expect(shanten(hand('11123456789999m'), 0), -1);
    });
  });

  test('sichuan: bots finish every variant', () {
    expect(runSims(sichuanGames, n: 30), 0);
  });

  test('血战: a winner still at the table only shows the winning tile', () {
    for (var seed = 1; seed < 40; seed++) {
      final def = sichuanGames.first;
      final e = def.create(GameSetup(
          players: 4,
          options: def.defaultOptions(),
          names: ['a', 'b', 'c', 'd'],
          bots: List.filled(4, true),
          rng: Random(seed)));
      final host = SimHost();
      e.host = host;
      e.start();
      for (var steps = 0; steps < 3000 && !e.isOver; steps++) {
        final w = e.waitingFor;
        if (w.isEmpty) {
          if (!host.runPending()) break;
          continue;
        }
        e.handle(w.first, e.bot(w.first)!);
        final v = e.view(0);
        if (v['phase'] == 'settle' || v['phase'] == 'over') break;
        for (var s = 1; s < 4; s++) {
          final sv = (v['seats'] as List)[s] as Map;
          if ((sv['won'] as int) > 0) {
            expect(sv['hand'], isNull, reason: 'seed $seed seat $s');
            expect(sv['winTile'], isNotNull);
            return;
          }
        }
      }
    }
    fail('no mid-hand winner found');
  });

  group('v3 placings', () {
    for (final def in sichuanGames) {
      for (final lvl in const [0, 1, 2]) {
        test('${def.id} botLevel $lvl: placings follow final score', () {
          _checkPlacings(def, (e) => (e as SichuanGame).scores, level: lvl, seed: 3 + lvl);
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
