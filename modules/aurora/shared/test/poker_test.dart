import 'dart:math';

import 'package:aurora_shared/games/poker/cabo.dart';
import 'package:aurora_shared/games/poker/ddz_rules.dart';
import 'package:aurora_shared/games/poker/defs.dart';
import 'package:aurora_shared/games/poker/doudizhu.dart';
import 'package:aurora_shared/games/poker/exploding.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<int> r(String s) => [
      for (final t in s.split(' '))
        t == 'b' ? 16 : (t == 'r' ? 17 : ddzRank(t == '10' ? 'TS' : '${t}S')),
    ];

String? type(String s, {bool two = false}) => ddzPick(r(s), null, two)?.type;

void main() {
  group('斗地主 一副牌', () {
    test('基本牌型', () {
      expect(type('3'), 'single');
      expect(type('5 5'), 'pair');
      expect(type('7 7 7'), 'triple');
      expect(type('7 7 7 3'), 'triple1');
      expect(type('7 7 7 3 3'), 'triple2');
      expect(type('3 4 5 6 7'), 'straight');
      expect(type('10 J Q K A'), 'straight');
      expect(type('J Q K A 2'), isNull);
      expect(type('3 3 4 4 5 5'), 'pairs');
      expect(type('3 3 4 4'), isNull);
      expect(type('3 3 3 4 4 4'), 'plane');
      expect(type('3 3 3 4 4 4 7 9'), 'plane1');
      expect(type('3 3 3 4 4 4 7 7 9 9'), 'plane2');
      expect(type('K K K A A A 2 2 2'), isNull);
      expect(type('9 9 9 9 3 5'), 'four2');
      expect(type('9 9 9 9 3 3 5 5'), 'four22');
      expect(type('9 9 9 9'), 'bomb');
      expect(type('b r'), 'rocket');
      expect(type('3 4'), isNull);
      expect(type('9 9 9 9 b r'), isNull);
    });
    test('比较', () {
      final t = ddzPick(r('3 4 5 6 7'), null, false);
      expect(ddzPick(r('4 5 6 7 8'), t, false)?.type, 'straight');
      expect(ddzPick(r('4 5 6 7 8 9'), t, false), isNull);
      expect(ddzPick(r('3 3 3 3'), t, false)?.type, 'bomb');
      final bomb = ddzPick(r('5 5 5 5'), null, false);
      expect(ddzPick(r('3 3 3 3'), bomb, false), isNull);
      expect(ddzPick(r('6 6 6 6'), bomb, false)?.type, 'bomb');
      expect(ddzPick(r('b r'), bomb, false)?.type, 'rocket');
      final pair = ddzPick(r('2 2'), null, false);
      expect(ddzPick(r('b b'), pair, true)?.type, 'pair');
    });
    test('候选出牌', () {
      final table = ddzPick(r('8'), null, false);
      final c = ddzCandidates(r('3 5 9 9 K 2 b r'), table, false);
      expect(c.first, [9]);
      expect(c.any((x) => x.length == 2 && x.contains(16)), isTrue);
    });
  });

  group('斗地主 两副牌', () {
    test('炸弹张数', () {
      expect(type('5 5 5 5 5', two: true), 'bomb');
      expect(type('5 5 5 5 5 5 5 5', two: true), 'bomb');
      expect(type('b b r r', two: true), 'rocket');
      expect(type('b r', two: true), isNull);
      expect(type('9 9 9 9 3 5', two: true), isNull);
      final four = ddzPick(r('A A A A'), null, true);
      final five = ddzPick(r('3 3 3 3 3'), null, true);
      expect(ddzBeats(five!, four!, true), isTrue);
      expect(ddzBeats(four, five, true), isFalse);
      final rocket = ddzPick(r('b b r r'), null, true)!;
      final eight = ddzPick(r('2 2 2 2 2 2 2 2'), null, true)!;
      expect(ddzBeats(rocket, eight, true), isTrue);
      expect(type('3 3 4 4 5 5', two: true), 'pairs');
      expect(type('3 3 3 4 4 4 5 5 6 6', two: true), 'plane2');
    });
  });

  test('poker games: bots finish every variant', () {
    expect(runSims(pokerGames, n: 30), 0);
  });

  GameDef def(String id) => pokerGames.firstWhere((d) => d.id == id);
  GameSetup setup(int p, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
        players: p,
        options: opts,
        names: [for (var i = 0; i < p; i++) 'P$i'],
        bots: List.filled(p, true),
        rng: Random(seed),
        botRng: Random(seed + 99),
      );
  GameEngine playOut(GameDef d, GameSetup st) {
    final e = d.create(st);
    final host = SimHost();
    e.host = host;
    e.start();
    host.runPending();
    var steps = 0;
    while (!e.isOver && steps++ < 20000) {
      expect(e.placings, isNull);
      var acted = false;
      for (final s in e.waitingFor) {
        final a = e.runBot(s);
        if (a == null) continue;
        e.handle(s, a);
        acted = true;
        break;
      }
      if (!host.runPending() && !acted) fail('stuck');
    }
    expect(e.isOver, isTrue);
    return e;
  }

  group('placings', () {
    test('斗地主 单局：地主与农民分出 1/2 名', () {
      for (var seed = 1; seed <= 5; seed++) {
        final d = def('doudizhu');
        final e = playOut(d, setup(3, d.normalizeOptions({'rounds': 1}), seed: seed)) as Doudizhu;
        final p = e.placings!;
        final lw = e.result!['landlordWin'] as bool;
        for (var s = 0; s < 3; s++) {
          final win = (s == e.landlord) == lw;
          expect(p[s], win ? 1 : (lw ? 2 : 3), reason: 'seat $s');
        }
      }
    });
    test('斗地主 多局：按累计积分排名', () {
      final d = def('doudizhu');
      final e = playOut(d, setup(4, d.normalizeOptions({'decks': 2, 'rounds': 3}))) as Doudizhu;
      expect(e.placings, rankByScore(e.scores));
    });
    test('爆炸猫：胜者第 1，越晚出局名次越好', () {
      final d = def('explodingkittens');
      for (var seed = 1; seed <= 5; seed++) {
        final e = playOut(d, setup(4, d.defaultOptions(), seed: seed)) as ExplodingKittens;
        final p = e.placings!;
        expect(p[e.winner], 1);
        expect(e.outOrder.length, 3);
        expect([for (final s in e.outOrder) p[s]], [4, 3, 2]);
      }
    });
    test('CABO：总分最低者第 1', () {
      final d = def('cabo');
      final e = playOut(d, setup(3, d.normalizeOptions({'target': 50}))) as Cabo;
      expect(e.placings, rankByScore(e.scores, lowWins: true));
      final best = e.scores.reduce(min);
      for (var s = 0; s < 3; s++) {
        if (e.scores[s] == best) expect(e.placings![s], 1);
      }
    });
  });

  group('认输', () {
    test('斗地主不支持认输', () {
      final d = def('doudizhu');
      final e = d.create(setup(3, d.defaultOptions()))..start();
      expect(e.canResign, isFalse);
    });
    for (final id in ['explodingkittens', 'cabo']) {
      test('$id 两人可认输，多人不可', () {
        final d = def(id);
        final multi = d.create(setup(3, d.defaultOptions()))..start();
        expect(multi.canResign, isFalse);
        final e = d.create(setup(2, d.defaultOptions()));
        final host = SimHost();
        e.host = host;
        e.start();
        expect(e.canResign, isTrue);
        e.resign(0);
        expect(e.isOver, isTrue);
        expect(e.placings, [2, 1]);
        expect(e.canResign, isFalse);
        expect(host.logs, contains('P0 认输'));
        expect(e.waitingFor, isEmpty);
        e.view(0);
        e.view(-1);
      });
    }
  });
}
