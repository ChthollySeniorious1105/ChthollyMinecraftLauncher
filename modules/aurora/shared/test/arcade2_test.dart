import 'dart:math';

import 'package:aurora_shared/games/arcade2/bomberman.dart';
import 'package:aurora_shared/games/arcade2/defs.dart';
import 'package:aurora_shared/games/arcade2/dobble.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 3, bool bots = false}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, bots),
      hostSeat: 0,
      rng: Random(seed),
    );

void main() {
  group('炸弹人', () {
    Bomberman mk(int n) {
      final e = Bomberman(_setup(n, {'time': 120}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      // empty arena (pillars only)
      for (var i = 0; i < e.grid.length; i++) {
        if (e.grid[i] == '+') e.grid[i] = '.';
      }
      return e;
    }

    void tick(Bomberman e, [int k = 1]) {
      for (var i = 0; i < k && !e.isOver; i++) {
        (e.host as SimHost).runPending();
      }
    }

    test('arena layout: pillars on even cells, spawn corners clear', () {
      final e = Bomberman(_setup(4, {}))..host = SimHost();
      e.start();
      expect(e.grid[Bomberman.cell(2, 2)], '#');
      expect(e.grid[Bomberman.cell(0, 5)], '#');
      for (final (x, y) in Bomberman.spawns) {
        expect(e.grid[Bomberman.cell(x, y)], '.');
      }
      expect(e.grid[Bomberman.cell(2, 1)], '.');
      expect(e.grid[Bomberman.cell(1, 2)], '.');
      expect(e.grid.where((g) => g == '+').length, greaterThan(30));
    });

    test('bomb explodes after fuse in a + shape and kills', () {
      final e = mk(2);
      final p0 = e.ps[0], p1 = e.ps[1];
      p0.cell = Bomberman.cell(1, 1);
      p1.cell = Bomberman.cell(3, 1); // range 2 reaches it
      e.handle(0, {'type': 'bomb'});
      tick(e);
      expect(e.bombs.containsKey(Bomberman.cell(1, 1)), isTrue);
      // p0 walks away down the column
      e.handle(0, {'type': 'dir', 'dir': 'down'});
      tick(e, 20);
      e.handle(0, {'type': 'dir', 'dir': 'none'});
      expect(p0.cell, Bomberman.cell(1, 5));
      tick(e, Bomberman.fuseTicks);
      expect(p1.alive, isFalse);
      expect(p0.alive, isTrue);
      expect(p0.kills, 1);
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2]);
    });

    test('blast stops at pillars and bricks, destroys first brick, chains bombs', () {
      final e = mk(2);
      e.ps[0].cell = Bomberman.cell(13, 11);
      e.ps[1].cell = Bomberman.cell(13, 9);
      final c = Bomberman.cell(3, 1);
      e.grid[Bomberman.cell(5, 1)] = '+';
      e.grid[Bomberman.cell(6, 1)] = '+';
      final cells = e.blast(c, 5);
      expect(cells.contains(Bomberman.cell(5, 1)), isTrue);
      expect(cells.contains(Bomberman.cell(6, 1)), isFalse);
      expect(cells.contains(Bomberman.cell(3, 2)), isTrue);
      expect(cells.contains(Bomberman.cell(3, 0)), isFalse); // wall
      // chain: bomb at (1,1) fuse 1 reaches bomb at (1,3) with long fuse
      e.bombs[Bomberman.cell(1, 1)] = BombermanBomb(0, 1, 2);
      e.bombs[Bomberman.cell(1, 3)] = BombermanBomb(1, 40, 2);
      e.ps[0].placed = 1;
      e.ps[1].placed = 1;
      tick(e);
      expect(e.bombs, isEmpty);
      expect(e.flames.containsKey(Bomberman.cell(1, 5)), isTrue);
      expect(e.ps[0].placed, 0);
      expect(e.ps[1].placed, 0);
    });

    test('power-ups are picked up', () {
      final e = mk(2);
      e.ps[0].cell = Bomberman.cell(1, 1);
      e.ps[1].cell = Bomberman.cell(13, 11);
      e.items[Bomberman.cell(2, 1)] = 'b';
      e.items[Bomberman.cell(3, 1)] = 'r';
      e.handle(0, {'type': 'dir', 'dir': 'right'});
      tick(e, 12);
      expect(e.ps[0].bombs, 2);
      expect(e.ps[0].range, 3);
      expect(e.items, isEmpty);
    });

    test('bombs block movement and bomb limit applies', () {
      final e = mk(2);
      e.ps[0].cell = Bomberman.cell(1, 1);
      e.ps[1].cell = Bomberman.cell(3, 1);
      e.handle(0, {'type': 'bomb'});
      tick(e);
      e.handle(0, {'type': 'bomb'});
      tick(e);
      expect(e.bombs.length, 1); // limit 1
      e.handle(1, {'type': 'dir', 'dir': 'left'});
      tick(e, 10);
      expect(e.ps[1].cell, Bomberman.cell(2, 1)); // can't enter the bomb cell
    });

    test('time limit: survivors ahead, ranked by kills', () {
      final e = mk(3);
      e.ps[0].kills = 1;
      e.ps[2].alive = false;
      e.ps[2].deathNo = 1;
      e.maxTicks = e.tick - Bomberman.countdownTicks; // next tick ends the game
      tick(e);
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 3]);
    });

    test('resign ranks last', () {
      final e = Bomberman(_setup(3, {}))..host = SimHost();
      e.start();
      e.resign(1);
      expect(e.isOver, isFalse);
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 3, 1]);
    });

    test('bot never walks into its own bomb blast (danger map)', () {
      final e = Bomberman(_setup(2, {}, bots: true))..host = SimHost();
      e.start();
      final d = e.dangerMap();
      expect(d, isEmpty);
      e.bombs[Bomberman.cell(1, 1)] = BombermanBomb(0, 10, 2);
      final d2 = e.dangerMap();
      expect(d2[Bomberman.cell(1, 3)], (10, 10 + Bomberman.flameTicks));
      expect(d2.containsKey(Bomberman.cell(1, 4)), isFalse);
    });

    test('input validation', () {
      final e = Bomberman(_setup(2, {}))..host = SimHost();
      e.start();
      expect(() => e.handle(0, {'type': 'dir', 'dir': 'jump'}), throwsA(isA<GameError>()));
      expect(() => e.handle(-1, {'type': 'bomb'}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'fly'}), throwsA(isA<GameError>()));
    });
  });

  group('眼疾手快', () {
    test('deck: 57 cards × 8 symbols, every pair shares exactly one', () {
      final cards = Dobble.cards;
      expect(cards.length, 57);
      expect(Dobble.symbols.length, 57);
      expect(Dobble.symbols.toSet().length, 57);
      for (final c in cards) {
        expect(c.length, 8);
        expect(c.toSet().length, 8);
        expect(c.every((x) => x >= 0 && x < 57), isTrue);
      }
      for (var a = 0; a < 57; a++) {
        for (var b = a + 1; b < 57; b++) {
          expect(cards[a].toSet().intersection(cards[b].toSet()).length, 1, reason: '$a/$b');
        }
      }
    });

    Dobble mk(int n, String mode) {
      final e = Dobble(_setup(n, {'mode': mode}));
      e.host = SimHost();
      e.start();
      while (e.countdown > 0) {
        (e.host as SimHost).runPending();
      }
      return e;
    }

    test('tower: correct tap takes the centre card', () {
      final e = mk(3, 'tower');
      final c = e.centreCard!;
      final n = e.centre.length;
      final sym = Dobble.common(e.topOf(1)!, c);
      e.handle(1, {'type': 'tap', 'sym': sym, 'ver': e.round});
      expect(e.topOf(1), c);
      expect(e.piles[1].length, 2);
      expect(e.centre.length, n - 1);
      expect(e.waitingFor, isEmpty); // reveal pause
      // late tap is rejected without penalty
      final s0 = Dobble.common(e.topOf(0)!, e.centreCard!);
      expect(() => e.handle(0, {'type': 'tap', 'sym': s0, 'ver': e.round}), throwsA(isA<GameError>()));
      expect(e.ps[0].wrong, 0);
    });

    test('wrong tap locks out for 1.5 s (ticks)', () {
      final e = mk(2, 'tower');
      final c = e.centreCard!;
      final right = Dobble.common(e.topOf(0)!, c);
      final wrong = Dobble.cards[e.topOf(0)!].firstWhere((x) => x != right);
      e.handle(0, {'type': 'tap', 'sym': wrong, 'ver': e.round});
      expect(e.ps[0].wrong, 1);
      expect(() => e.handle(0, {'type': 'tap', 'sym': right, 'ver': e.round}), throwsA(isA<GameError>()));
      for (var i = 0; i < Dobble.penaltyTicks; i++) {
        (e.host as SimHost).runPending();
      }
      e.handle(0, {'type': 'tap', 'sym': right, 'ver': e.round});
      expect(e.piles[0].length, 2);
      // symbol not on your card
      final notMine = List.generate(57, (i) => i).firstWhere((x) => !Dobble.cards[e.topOf(1)!].contains(x));
      while (e.reveal > 0) {
        (e.host as SimHost).runPending();
      }
      expect(() => e.handle(1, {'type': 'tap', 'sym': notMine, 'ver': e.round}), throwsA(isA<GameError>()));
    });

    test('tower ends when the pile is empty, most cards wins', () {
      final e = mk(2, 'tower');
      while (!e.isOver) {
        while (e.reveal > 0) {
          (e.host as SimHost).runPending();
        }
        e.handle(0, {'type': 'tap', 'sym': Dobble.common(e.topOf(0)!, e.centreCard!), 'ver': e.round});
      }
      expect(e.piles[0].length, 56);
      expect(e.placings, [1, 2]);
    });

    test('well: playing your card to the centre, first to empty wins', () {
      final e = mk(3, 'well');
      expect(e.piles[0].length, 18);
      final mine = e.topOf(2)!;
      e.handle(2, {'type': 'tap', 'sym': Dobble.common(mine, e.centreCard!), 'ver': e.round});
      expect(e.centreCard, mine);
      expect(e.piles[2].length, 17);
      while (!e.isOver) {
        while (e.reveal > 0) {
          (e.host as SimHost).runPending();
        }
        e.handle(2, {'type': 'tap', 'sym': Dobble.common(e.topOf(2)!, e.centreCard!), 'ver': e.round});
      }
      expect(e.piles[2], isEmpty);
      expect(e.placings![2], 1);
      expect(e.placings![0], 2);
    });

    test('resign', () {
      final e = mk(3, 'tower');
      e.resign(0);
      expect(() => e.handle(0, {'type': 'tap', 'sym': 0}), throwsA(isA<GameError>()));
      e.resign(1);
      expect(e.isOver, isTrue);
      expect(e.placings, [3, 2, 1]);
    });

    test('bot level changes reaction speed', () {
      int roundsFor(int lvl) {
        final setup = GameSetup(
          players: 2,
          options: {'mode': 'tower'},
          names: ['A', 'B'],
          bots: [true, false],
          rng: Random(5),
          botLevel: lvl,
          botRng: Random(9),
        );
        final e = Dobble(setup)..host = SimHost();
        e.start();
        var ticks = 0;
        while (e.piles[0].length < 6 && ticks < 5000) {
          (e.host as SimHost).runPending();
          ticks++;
        }
        return ticks;
      }

      expect(roundsFor(2), lessThan(roundsFor(0)));
    });
  });

  test('bot simulations', () {
    final sw = Stopwatch()..start();
    expect(runSims(arcade2Games, n: 30), 0);
    print('sims took ${sw.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
