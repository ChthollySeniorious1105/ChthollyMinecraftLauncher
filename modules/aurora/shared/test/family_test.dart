import 'dart:math';

import 'package:aurora_shared/games/family/cards.dart';
import 'package:aurora_shared/games/family/defs.dart';
import 'package:aurora_shared/games/family/gofish.dart';
import 'package:aurora_shared/games/family/oldmaid.dart';
import 'package:aurora_shared/games/family/sevens.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

void main() {
  group('抽乌龟', () {
    test('hidden mode: 51 cards, no pairs left in hands at start', () {
      final e = OldMaid(_setup(4, {'mode': 'hidden'}))..start();
      expect(e.removed, isNotEmpty);
      final all = [...e.hands.expand((h) => h), ...e.discards.expand((p) => p)];
      expect(all.length, 51);
      expect(all.contains(e.removed), isFalse);
      for (final h in e.hands) {
        final ranks = h.map(fmRank).toList();
        expect(ranks.toSet().length, ranks.length);
      }
    });
    test('joker mode keeps 大王 until the end and its holder loses', () {
      for (var seed = 1; seed <= 5; seed++) {
        final e = OldMaid(_setup(3, {'mode': 'joker'}, seed: seed))..start();
        while (!e.isOver) {
          final s = e.waitingFor.first;
          e.handle(s, e.runBot(s)!);
        }
        expect(e.hands[e.loser], ['RJ']);
        expect(e.placings![e.loser], 3);
        expect(e.placings!.toSet().length, 3);
      }
    });
    test('drawing from the next player and errors', () {
      final e = OldMaid(_setup(3, {'mode': 'hidden'}))..start();
      final s = e.turn;
      final t = e.targetOf(s);
      expect(t, (s + 1) % 3);
      expect(() => e.handle((s + 1) % 3, {'type': 'draw', 'index': 0}), throwsA(isA<GameError>()));
      expect(() => e.handle(s, {'type': 'draw', 'index': 99}), throwsA(isA<GameError>()));
      final before = e.hands[t].length;
      e.handle(s, {'type': 'draw', 'index': 0});
      expect(e.hands[t].length, before - 1);
    });
    test('views hide other hands', () {
      final e = OldMaid(_setup(3, {'mode': 'hidden'}))..start();
      final v = e.view(1);
      expect(v['hand'], e.hands[1]);
      expect(v['hands'], isNull);
      expect(v['removed'], isNull);
    });
  });

  group('钓鱼', () {
    test('deal sizes', () {
      expect(((GoFish(_setup(3, {}))..start()).hands.map((h) => h.length + 0)).every((n) => n <= 7), isTrue);
      final e = GoFish(_setup(4, {}))..start();
      expect(e.pond.length + e.hands.fold<int>(0, (a, h) => a + h.length) + e.totalBooks * 4, 52);
      expect(e.pond.length, 32);
    });
    test('ask rules: must hold the rank, transfer all, go again', () {
      final e = GoFish(_setup(2, {}))..start();
      e.hands[0] = ['7S', '2H'];
      e.hands[1] = ['7H', '7D', '9C'];
      e.turn = 0;
      expect(() => e.handle(0, {'type': 'ask', 'target': 1, 'rank': '9'}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'ask', 'target': 0, 'rank': '7'}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'ask', 'target': 1, 'rank': '7'});
      expect(e.hands[0].where((c) => c[0] == '7').length, 3);
      expect(e.hands[1], ['9C']);
      expect(e.turn, 0);
      expect(e.log.last['got'], 2);
    });
    test('go fish: lucky draw goes again, otherwise next player', () {
      final e = GoFish(_setup(2, {}))..start();
      e.hands[0] = ['7S', '2H'];
      e.hands[1] = ['9C'];
      e.pond = ['4D', '7H'];
      e.turn = 0;
      e.handle(0, {'type': 'ask', 'target': 1, 'rank': '7'});
      expect(e.log.last['fish'], 'lucky');
      expect(e.turn, 0);
      e.handle(0, {'type': 'ask', 'target': 1, 'rank': '2'});
      expect(e.log.last['fish'], 'miss');
      expect(e.turn, 1);
    });
    test('four of a kind becomes a book', () {
      final e = GoFish(_setup(2, {}))..start();
      e.hands[0] = ['7S', '7C', '7D', '2H'];
      e.hands[1] = ['7H', '9C'];
      for (final b in e.books) {
        b.clear();
      }
      e.turn = 0;
      e.handle(0, {'type': 'ask', 'target': 1, 'rank': '7'});
      expect(e.books[0], ['7']);
      expect(e.hands[0], ['2H']);
    });
  });

  group('牌七', () {
    test('♥7 holder starts and must play it', () {
      final e = Sevens(_setup(4, {'mode': 'cover'}))..start();
      expect(e.hands[e.turn].contains('7H'), isTrue);
      expect(e.legal(e.turn), ['7H']);
      final other = e.hands[e.turn].firstWhere((c) => c != '7H');
      expect(() => e.handle(e.turn, {'type': 'play', 'card': other}), throwsA(isA<GameError>()));
    });
    test('extending rows and cover rules', () {
      final e = Sevens(_setup(4, {'mode': 'cover'}))..start();
      e.first = false;
      e.lo[1] = 6; // hearts 6..8
      e.hi[1] = 8;
      expect(e.isPlayable('5H'), isTrue);
      expect(e.isPlayable('9H'), isTrue);
      expect(e.isPlayable('4H'), isFalse);
      expect(e.isPlayable('6S'), isFalse);
      expect(e.isPlayable('7C'), isTrue);
      e.hands[e.turn] = ['5H', 'KS'];
      expect(() => e.handle(e.turn, {'type': 'cover', 'card': 'KS'}), throwsA(isA<GameError>()));
      e.hands[e.turn] = ['3S', 'KS'];
      final s = e.turn;
      e.handle(s, {'type': 'cover', 'card': 'KS'});
      expect(e.covered[s], ['KS']);
      expect(e.penalties[s], 13);
    });
    test('pass mode: cannot pass with a legal play', () {
      final e = Sevens(_setup(3, {'mode': 'pass'}))..start();
      expect(() => e.handle(e.turn, {'type': 'pass'}), throwsA(isA<GameError>()));
      expect(() => e.handle(e.turn, {'type': 'cover', 'card': e.hands[e.turn].first}), throwsA(isA<GameError>()));
    });
    test('full game: all 52 cards end on table or covered; lowest penalty wins', () {
      final e = Sevens(_setup(5, {'mode': 'cover'}, seed: 3))..start();
      while (!e.isOver) {
        final s = e.waitingFor.first;
        e.handle(s, e.runBot(s)!);
      }
      final laid = [for (var i = 0; i < 4; i++) e.lo[i] == 0 ? 0 : e.hi[i] - e.lo[i] + 1].fold<int>(0, (a, b) => a + b);
      expect(laid + e.covered.fold<int>(0, (a, c) => a + c.length), 52);
      final p = e.penalties;
      final best = p.reduce(min);
      for (var s = 0; s < 5; s++) {
        if (p[s] == best) expect(e.placings![s], 1);
      }
      expect(e.view(0)['hands'], isNotNull);
    });
  });

  test('simulations', () {
    expect(runSims(familyGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
