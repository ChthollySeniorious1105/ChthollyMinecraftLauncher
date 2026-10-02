import 'dart:math';

import 'package:aurora_shared/games/cards4/baohuang.dart';
import 'package:aurora_shared/games/cards4/defs.dart';
import 'package:aurora_shared/games/cards4/ginrummy.dart';
import 'package:aurora_shared/games/cards4/gouji.dart';
import 'package:aurora_shared/games/cards4/gr_rules.dart';
import 'package:aurora_shared/games/cards4/sets.dart';
import 'package:aurora_shared/games/cards4/shuangkou.dart';
import 'package:aurora_shared/games/cards4/sk_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<String> cs(String s) => s.split(' ');

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

void main() {
  group('sets', () {
    test('classify with wild jokers', () {
      expect(classifySet(cs('8S 8H BJ'))!.rank, 8);
      expect(classifySet(cs('8S 8H BJ'))!.jokers, 1);
      expect(classifySet(cs('8S 9H')), isNull);
      expect(classifySet(cs('BJ RJ'))!.rank, 16);
      expect(classifySet(cs('EJ')), isNotNull);
      expect(classifySet(cs('EJ 8S')), isNull);
    });
    test('candidates', () {
      final c = setCandidates(cs('5S 5H 9D BJ'), size: 2, above: 5);
      expect(c.first, cs('9D BJ'));
    });
  });

  group('够级', () {
    test('够级牌 thresholds', () {
      expect(Gouji.isGouji(classifySet(cs('TS TS TH TD TC'))!), isTrue);
      expect(Gouji.isGouji(classifySet(cs('TS TS TH TD'))!), isFalse);
      expect(Gouji.isGouji(classifySet(cs('JS JS JH JD'))!), isTrue);
      expect(Gouji.isGouji(classifySet(cs('QS QH QD'))!), isTrue);
      expect(Gouji.isGouji(classifySet(cs('KS KH'))!), isTrue);
      expect(Gouji.isGouji(classifySet(cs('AS'))!), isFalse);
      expect(Gouji.isGouji(classifySet(cs('2S'))!), isTrue);
      expect(Gouji.isGouji(classifySet(cs('5S BJ'))!), isTrue);
    });
    test('only 对头 can beat 够级牌 without jokers; 3 last; 4 locked', () {
      final e = Gouji(_setup(6, {'rounds': 1, 'tribute': false}))..start();
      e.hands = [
        cs('KS KH 7S 7H 7D 5C'),
        cs('AS AH 8S 3C'),
        cs('AD AC 9S'),
        cs('2S 2H 6S'),
        cs('4S 4H 6C'),
        cs('AS AH BJ 6D'),
      ];
      e.turn = 0;
      e.resetTrick();
      expect(() => e.handle(0, {'type': 'play', 'cards': ['5C', '7S']}), throwsA(isA<GameError>()));
      expect(() => e.handle(4, {'type': 'play', 'cards': ['4S']}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'play', 'cards': cs('KS KH')});
      expect(e.tableInfo!['gouji'], isTrue);
      // 对头 (seat 3) answers first
      expect(e.turn, 3);
      e.handle(3, {'type': 'pass'});
      expect(e.opened[0], isTrue);
      // then seat 1 (enemy, not 对头): must 挂王 to 烧
      expect(e.turn, 1);
      expect(() => e.handle(1, {'type': 'play', 'cards': cs('AS AH')}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'pass'});
      expect(e.turn, 5);
      e.handle(5, {'type': 'play', 'cards': cs('AS BJ')});
      expect(e.tableInfo!['burn'], isTrue);
      // 3 can't be played early
      expect(() => e.handle(e.turn, {'type': 'play', 'cards': ['3C']}), throwsA(isA<GameError>()));
    });
    test('bot game completes, placings team-aware', () {
      final e = Gouji(_setup(6, {'rounds': 1}, seed: 3));
      e.start();
      var n = 0;
      while (!e.isOver && n++ < 5000) {
        final s = e.waitingFor.first;
        e.handle(s, e.runBot(s)!);
      }
      expect(e.isOver, isTrue);
      final p = e.placings!;
      expect(p[0], p[2]);
      expect(p[1], p[3]);
    });
  });

  group('保皇', () {
    test('deal: 217 cards, emperor has EJ + 底牌', () {
      final e = Baohuang(_setup(5, {'rounds': 1}))..start();
      expect(e.hands.fold<int>(0, (a, h) => a + h.length), 217);
      expect(e.hands[e.emperor].contains('EJ'), isTrue);
      expect(e.hands[e.emperor].length, 45);
      final g = e.guard;
      final other = [0, 1, 2, 3, 4].firstWhere((s) => s != g && s != e.emperor);
      if (g >= 0) {
        expect(e.view(other)['guard'], -2);
        expect(e.view(g)['guard'], g);
      }
    });
    test('bombs beat fewer cards, sets need same size', () {
      final e = Baohuang(_setup(5, {'rounds': 1, 'du': false, 'bao': false}))..start();
      final t = e.turn;
      final n = (t + 1) % 5;
      e.hands[t] = cs('9S 9H 9D KS');
      e.hands[n] = cs('5S 5H 5D 5C TS TH QS');
      e.resetTrick();
      e.handle(t, {'type': 'play', 'cards': cs('9S 9H 9D')});
      expect(() => e.handle(n, {'type': 'play', 'cards': cs('TS TH')}), throwsA(isA<GameError>()));
      e.handle(n, {'type': 'play', 'cards': cs('5S 5H 5D 5C')});
      expect(e.tableInfo!['bomb'], isTrue);
    });
  });

  group('双扣', () {
    test('combos', () {
      expect(skClassify(cs('3S 4S 5H 6D 7C'))!.type, 'straight');
      expect(skClassify(cs('3S 3H 4S 4H')), isNull); // 连对至少三对
      expect(skClassify(cs('3S 3H 4S 4H 5S 5D'))!.type, 'pairs');
      expect(skClassify(cs('BJ BJ RJ RJ'))!.type, 'kings');
      final b4 = skClassify(cs('KS KH KD KC'))!, b5 = skClassify(cs('3S 3H 3D 3C 3S'))!;
      expect(b5.beats(b4), isTrue);
      expect(b4.beats(skClassify(cs('2S 2H'))!), isTrue);
      expect(skClassify(cs('BJ BJ RJ RJ'))!.beats(skClassify(cs('3S 3H 3D 3C 3S 3H 3D 3C'))!), isTrue);
    });
    test('双扣 ends when partners finish 1-2', () {
      final e = Shuangkou(_setup(4, {'target': 3}))..start();
      e.hands = [cs('3S'), cs('9S 9H'), cs('4S'), cs('TS TH')];
      e.turn = 0;
      e.resetTrick();
      e.handle(0, {'type': 'play', 'cards': ['3S']});
      e.handle(1, {'type': 'pass'});
      e.handle(2, {'type': 'play', 'cards': ['4S']});
      expect(e.result!['kind'], '双扣');
      expect(e.teamScores[0], greaterThanOrEqualTo(3));
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 1, 2]);
    });
  });

  group('Gin Rummy', () {
    test('deadwood', () {
      final a = grBest(cs('AS 2S 3S 7H 7D 7C KH QD 9C 5S'));
      expect(a.points, 10 + 10 + 9 + 5);
      final g = grBest(cs('AS 2S 3S 4S 7H 7D 7C 9H TH JH'));
      expect(g.points, 0);
      // overlapping: 4S can be in the run or the set
      final o = grBest(cs('2S 3S 4S 4H 4D'));
      expect(o.points, 5);
    });
    test('layoff and undercut', () {
      final d = grDefend(cs('5S KC KD'), [cs('2S 3S 4S')]);
      expect(d.laid, ['5S']);
      expect(d.own.points, 20);
      final e = GinRummy(_setup(2, {'target': 100}))..start();
      e.hands = [cs('2S 3S 4S 7H 7D 7C 9H TH JH AC 2C'), cs('AD AH 5C 5D 5H 6S 6H 6C 8D 8S')];
      e.turn = 0;
      e.phase = 'discard';
      expect(() => e.handle(0, {'type': 'knock', 'card': 'AC'}), returnsNormally);
      expect(e.result!['kind'], anyOf('knock', 'undercut'));
    });
    test('knock limit enforced; resign', () {
      final e = GinRummy(_setup(2, {}))..start();
      e.hands[0] = cs('KS KH QD QC JS JH TD TC 9S 9H 8D');
      e.turn = 0;
      e.phase = 'discard';
      e.takenDiscard = null;
      expect(() => e.handle(0, {'type': 'knock', 'card': '8D'}), throwsA(isA<GameError>()));
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
    });
  });

  test('bot simulations', () {
    expect(runSims(cards4Games, n: 30), 0);
  });
}
