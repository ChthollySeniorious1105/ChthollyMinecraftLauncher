import 'dart:math';

import 'package:aurora_shared/games/arcade/battle2048.dart';
import 'package:aurora_shared/games/arcade/defs.dart';
import 'package:aurora_shared/games/arcade/minesweeper.dart';
import 'package:aurora_shared/games/arcade/snake.dart';
import 'package:aurora_shared/games/arcade/sudoku.dart';
import 'package:aurora_shared/games/arcade/tetris.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 3}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      hostSeat: 0,
      rng: Random(seed),
    );

void main() {
  group('俄罗斯方块', () {
    test('line clear', () {
      final b = List.filled(200, 0);
      for (var x = 0; x < 10; x++) {
        b[19 * 10 + x] = 1;
        b[18 * 10 + x] = 2;
      }
      b[17 * 10 + 3] = 5;
      expect(TetrisBattle.clearLines(b), 2);
      expect(b[19 * 10 + 3], 5);
      expect(b.where((v) => v != 0).length, 1);
    });

    test('garbage table (TETR.IO)', () {
      expect(TetrisBattle.attackFor(1, 0), 0);
      expect(TetrisBattle.attackFor(2, 0), 1);
      expect(TetrisBattle.attackFor(3, 0), 2);
      expect(TetrisBattle.attackFor(4, 0), 4);
      expect(TetrisBattle.attackFor(2, 3), 1); // 1 × 1.75
      expect(TetrisBattle.attackFor(2, 4), 2); // 1 × 2
      expect(TetrisBattle.attackFor(1, 0, spin: 2), 2); // TSS
      expect(TetrisBattle.attackFor(2, 0, spin: 2), 4); // TSD
      expect(TetrisBattle.attackFor(3, 0, spin: 2), 6); // TST
      expect(TetrisBattle.attackFor(2, 0, spin: 1), 1); // mini double
      expect(TetrisBattle.attackFor(4, 0, b2b: 1), 5); // B2B quad
      expect(TetrisBattle.attackFor(1, 0, pc: true), 10);
      expect(TetrisBattle.attackFor(2, 0, mult: 1.5), 1);
      final b = List.filled(200, 0);
      expect(TetrisBattle.addGarbage(b, 2, 4), isTrue);
      expect(b[19 * 10 + 4], 0);
      expect(b[18 * 10 + 5], 8);
      expect(b.where((v) => v == 8).length, 18);
    });

    test('tetris sends 4 garbage to the opponent', () {
      final e = TetrisBattle(_setup(2, {'level': 1}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      final p = e.ps[0];
      // fill 4 rows except column 9, then drop a vertical I there
      for (var y = TetrisBattle.rows - 4; y < TetrisBattle.rows; y++) {
        for (var x = 0; x < 9; x++) {
          p.board[y * 10 + x] = 1;
        }
      }
      p.board[(TetrisBattle.rows - 5) * 10] = 1; // keep one block: no all clear
      p
        ..cur = 'I'
        ..r = 1
        ..x = 7
        ..y = TetrisBattle.buffer;
      e.handle(0, {'type': 'input', 'keys': ['hard']});
      expect(p.lines, 4);
      expect(e.ps[1].incoming.fold<int>(0, (a, g) => a + g.lines), 4);
      expect(p.board.where((v) => v != 0).length, 1);
    });

    test('T-Spin Double via rotation sends 4', () {
      final e = TetrisBattle(_setup(2, {'level': 1}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      final p = e.ps[0];
      const b = TetrisBattle.rows - 1; // bottom row
      for (var x = 0; x < 10; x++) {
        if (x != 4) p.board[b * 10 + x] = 1;
        if (x < 3 || x > 5) p.board[(b - 1) * 10 + x] = 1;
      }
      p.board[(b - 2) * 10 + 3] = 1; // overhang
      p
        ..cur = 'T'
        ..r = 1
        ..x = 3
        ..y = b - 2;
      e.handle(0, {'type': 'input', 'keys': ['cw', 'hard']});
      expect(p.lines, 2);
      expect(p.ev?['sp'], 2);
      expect(e.ps[1].incoming.fold<int>(0, (a, g) => a + g.lines), 4);
    });

    test('T without rotation is no spin; garbage cancels incoming first', () {
      final e = TetrisBattle(_setup(2, {'level': 1}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      final p = e.ps[0];
      const b = TetrisBattle.rows - 1;
      for (var x = 0; x < 10; x++) {
        if (x != 4) p.board[b * 10 + x] = 1;
      }
      p.incoming.add(Garbage(3, 0, 0, 1));
      p
        ..cur = 'T'
        ..r = 2
        ..x = 3
        ..y = TetrisBattle.buffer;
      // T pointing down plugs column 4 of the bottom row (single, no spin)
      e.handle(0, {'type': 'input', 'keys': ['hard']});
      expect(p.lines, 1);
      expect(p.ev?['sp'], 0);
      expect(p.incoming.fold<int>(0, (a, g) => a + g.lines), 3); // single sends 0: nothing cancelled
    });

    test('180 rotation and SRS kicks', () {
      final e = TetrisBattle(_setup(2, {}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      final p = e.ps[0]..cur = 'T'..r = 0;
      e.handle(0, {'type': 'input', 'keys': ['r180']});
      expect(p.r, 2);
      e.handle(0, {'type': 'input', 'keys': ['ccw']});
      expect(p.r, 1);
      expect(TetrisBattle.kicksFor('I', 0, 1).length, 5);
      expect(TetrisBattle.kicksFor('T', 0, 2).length, 6);
    });

    test('input validation', () {
      final e = TetrisBattle(_setup(2, {}))..start();
      expect(() => e.handle(0, {'type': 'input', 'keys': ['jump']}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'input', 'keys': List.filled(50, 'left')}), throwsA(isA<GameError>()));
      expect(() => e.handle(-1, {'type': 'input', 'keys': ['left']}), throwsA(isA<GameError>()));
    });
  });

  group('贪吃蛇', () {
    SnakeBattle mk(int n) {
      final e = SnakeBattle(_setup(n, {'time': 120}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      e.food.clear();
      e.foodCount = 0;
      for (final p in e.ps) {
        p.body.clear();
      }
      return e;
    }

    void tick(SnakeBattle e) {
      (e.host as SimHost).runPending();
    }

    test('wall kills', () {
      final e = mk(2);
      e.ps[0]
        ..body.addAll([0 * 30 + 29, 0 * 30 + 28])
        ..dir = 'right';
      e.ps[1]
        ..body.addAll([15 * 30 + 15, 15 * 30 + 14])
        ..dir = 'right';
      tick(e);
      expect(e.ps[0].alive, isFalse);
      expect(e.ps[1].alive, isTrue);
      expect(e.isOver, isTrue);
    });

    test('head-on both die', () {
      final e = mk(3);
      e.ps[0]
        ..body.addAll([5 * 30 + 5, 5 * 30 + 4])
        ..dir = 'right';
      e.ps[1]
        ..body.addAll([5 * 30 + 7, 5 * 30 + 8])
        ..dir = 'left';
      e.ps[2]
        ..body.addAll([20 * 30 + 5, 20 * 30 + 4])
        ..dir = 'right';
      tick(e);
      expect(e.ps[0].alive, isFalse);
      expect(e.ps[1].alive, isFalse);
      expect(e.ps[2].alive, isTrue);
    });

    test('hitting a body kills, chasing a tail is fine, food grows', () {
      final e = mk(3);
      // snake 1 vertical wall at x=10
      e.ps[1]
        ..body.addAll([for (var y = 5; y < 10; y++) y * 30 + 10])
        ..dir = 'up';
      e.ps[0]
        ..body.addAll([7 * 30 + 9, 7 * 30 + 8])
        ..dir = 'right';
      e.ps[2]
        ..body.addAll([20 * 30 + 5, 20 * 30 + 4])
        ..dir = 'right';
      e.food.add(20 * 30 + 6);
      tick(e);
      expect(e.ps[0].alive, isFalse);
      expect(e.ps[1].alive, isTrue);
      expect(e.ps[2].body.length, 3);
      expect(() => e.handle(1, {'type': 'turn', 'dir': 'sideways'}), throwsA(isA<GameError>()));
    });
  });

  group('扫雷', () {
    test('first click is safe and flood fills', () {
      for (var seed = 1; seed <= 20; seed++) {
        final e = MinesweeperRace(_setup(2, {'level': 'easy', 'hit': 'out'}, seed: seed));
        e.host = SimHost();
        e.start();
        final x = seed % 9, y = (seed * 7) % 9;
        e.handle(0, {'type': 'reveal', 'x': x, 'y': y});
        final p = e.ps[0];
        expect(p.out, isFalse);
        expect(p.mines.where((m) => m).length, 10);
        // first click opens a zero cell → region > 1
        expect(e.count(p.mines, y * 9 + x), 0);
        expect(p.opened, greaterThan(1));
        // flood fill invariant: every revealed zero has all neighbours revealed
        for (var i = 0; i < 81; i++) {
          if (p.state[i] == 1 && e.count(p.mines, i) == 0) {
            expect(e.neighbors(i).every((n) => p.state[n] == 1), isTrue);
          }
        }
        // the other player's board is untouched and hidden from seat 0
        expect(e.ps[1].opened, 0);
        expect(e.view(1)['board'], '.' * 81);
      }
    });

    test('mine hit eliminates; penalty mode adds time', () {
      final e = MinesweeperRace(_setup(2, {'level': 'easy', 'hit': 'penalty'}));
      e.host = SimHost();
      e.start();
      e.handle(0, {'type': 'reveal', 'x': 4, 'y': 4});
      final p = e.ps[0];
      final m = [for (var i = 0; i < 81; i++) if (p.mines[i]) i].first;
      e.handle(0, {'type': 'reveal', 'x': m % 9, 'y': m ~/ 9});
      expect(p.penalty, 10);
      expect(p.out, isFalse);
      expect(() => e.handle(0, {'type': 'reveal', 'x': 99, 'y': 0}), throwsA(isA<GameError>()));
    });
  });

  group('2048', () {
    test('merge rules', () {
      expect(Battle2048.slideLine([2, 2, 2, 2]).$1, [4, 4, 0, 0]);
      expect(Battle2048.slideLine([2, 2, 4, 0]).$1, [4, 4, 0, 0]);
      expect(Battle2048.slideLine([0, 4, 4, 8]).$1, [8, 8, 0, 0]);
      expect(Battle2048.slideLine([2, 0, 0, 2]).$1, [4, 0, 0, 0]);
      expect(Battle2048.slideLine([4, 2, 2, 0]).$2, 4);
      expect(Battle2048.slideLine([-2, 2, 0, 0]).$1, [4, 0, 0, 0]);
      final b = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
      expect(Battle2048.canMove(b), isFalse);
      expect(Battle2048.move(b, 'left'), isNull);
    });

    test('same tile sequence for everyone', () {
      final e = Battle2048(_setup(3, {'attack': true, 'time': 180}));
      e.host = SimHost();
      e.start();
      expect(e.ps[0].b, e.ps[1].b);
      expect(e.ps[1].b, e.ps[2].b);
    });
  });

  group('数独', () {
    test('generator gives unique solution', () {
      final rng = Random(5);
      for (final clues in [40, 32, 25]) {
        final (p, s) = Sudoku.generate(rng, clues);
        expect(Sudoku.solve(p, limit: 2), 1);
        for (var i = 0; i < 81; i++) {
          if (p[i] != 0) expect(p[i], s[i]);
        }
        final out = List.filled(81, 0);
        Sudoku.solve(p, out: out);
        expect(out, s);
        expect(p.where((v) => v != 0).length, greaterThanOrEqualTo(clues));
      }
    });

    test('mistakes eliminate', () {
      final e = SudokuRace(_setup(2, {'diff': 'easy', 'mistakes': 3}));
      e.host = SimHost();
      e.start();
      final i = e.puzzle.indexOf(0);
      final wrong = e.solution[i] % 9 + 1;
      for (var k = 0; k < 3; k++) {
        e.handle(0, {'type': 'fill', 'i': i, 'd': wrong});
      }
      expect(e.ps[0].out, isTrue);
      expect(() => e.handle(1, {'type': 'fill', 'i': e.puzzle.indexWhere((v) => v != 0), 'd': 1}), throwsA(isA<GameError>()));
      expect(e.view(1)['sol'], isNull);
    });
  });

  group('v3: placings / 认输 / rules', () {
    test('every def has rules', () {
      for (final d in arcadeGames) {
        expect(d.rules.trim().length, inInclusiveRange(300, 1500), reason: d.id);
        expect(d.undo, isFalse, reason: d.id);
      }
    });

    test('tetris: placings null until over; resign ends a 2p game', () {
      final e = TetrisBattle(_setup(2, {'level': 1}));
      e.host = SimHost();
      e.start();
      expect(e.placings, isNull);
      expect(e.canResign, isTrue);
      e.resign(1);
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2]);
      expect(e.canResign, isFalse);
      expect((e.host as SimHost).logs.any((l) => l.contains('P1 认输')), isTrue);
    });

    test('tetris: resign in 3p drops the seat, ranked last', () {
      final e = TetrisBattle(_setup(3, {'level': 1}));
      e.host = SimHost();
      e.start();
      e.resign(0);
      expect(e.isOver, isFalse);
      expect(e.waitingFor, isNot(contains(0)));
      expect(() => e.handle(0, {'type': 'input', 'keys': ['left']}), throwsA(isA<GameError>()));
      expect(() => e.resign(0), throwsA(isA<GameError>()));
      e.resign(2);
      expect(e.isOver, isTrue);
      expect(e.placings, [3, 1, 2]);
    });

    test('tetris: bot() does not touch the piece sequence', () {
      final e = TetrisBattle(_setup(2, {'level': 1}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      e.tick = 100;
      final before = e.seq.length;
      for (final lvl in [0, 1, 2]) {
        final ee = TetrisBattle(GameSetup(players: 2, options: {'level': 1}, names: ['a', 'b'], bots: [true, true], rng: Random(3), botLevel: lvl));
        ee.host = SimHost();
        ee.start();
        ee.countdown = 0;
        ee.tick = 100;
        final n = ee.seq.length;
        final a = ee.runBot(0)!;
        expect(a['type'], 'input');
        expect(ee.seq.length, n);
      }
      expect(e.seq.length, before);
    });

    test('snake: placings by survival, resign ranks last', () {
      final e = SnakeBattle(_setup(3, {'time': 120}));
      e.host = SimHost();
      e.start();
      expect(e.placings, isNull);
      e.resign(1);
      expect(e.ps[1].alive, isFalse);
      expect(e.isOver, isFalse);
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 3, 1]);
    });

    test('snake: head-on draw shares first place', () {
      final e = SnakeBattle(_setup(2, {'time': 120}));
      e.host = SimHost();
      e.start();
      e.countdown = 0;
      e.food.clear();
      e.foodCount = 0;
      e.ps[0].body
        ..clear()
        ..addAll([5 * 30 + 5, 5 * 30 + 4]);
      e.ps[0].dir = 'right';
      e.ps[1].body
        ..clear()
        ..addAll([5 * 30 + 7, 5 * 30 + 8]);
      e.ps[1].dir = 'left';
      (e.host as SimHost).runPending();
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1]);
    });

    test('minesweeper: finisher first, resign ranked last', () {
      final e = MinesweeperRace(_setup(3, {'level': 'easy', 'hit': 'out'}));
      e.host = SimHost();
      e.start();
      expect(e.placings, isNull);
      e.handle(0, {'type': 'reveal', 'x': 4, 'y': 4});
      e.resign(2);
      expect(e.isOver, isFalse);
      expect(() => e.handle(2, {'type': 'reveal', 'x': 0, 'y': 0}), throwsA(isA<GameError>()));
      final p = e.ps[0];
      for (var i = 0; i < 81 && !e.isOver; i++) {
        if (!p.mines[i] && p.state[i] == 0) e.handle(0, {'type': 'reveal', 'x': i % 9, 'y': i ~/ 9});
      }
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 3]);
    });

    test('minesweeper: 2p resign ends the game', () {
      final e = MinesweeperRace(_setup(2, {'level': 'easy', 'hit': 'out'}));
      e.host = SimHost();
      e.start();
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
    });

    test('2048: placings by score, resign', () {
      final e = Battle2048(_setup(3, {'attack': true, 'time': 180}));
      e.host = SimHost();
      e.start();
      expect(e.placings, isNull);
      e.ps[0].score = 100;
      e.ps[1].score = 100;
      e.ps[0].best = 8;
      e.ps[1].best = 8;
      e.ps[2].score = 500;
      e.resign(2);
      expect(e.isOver, isFalse);
      expect(e.waitingFor, isNot(contains(2)));
      e.resign(1);
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 3]);
    });

    test('2048: time up ranks by score with ties', () {
      final e = Battle2048(_setup(2, {'attack': true, 'time': 120}));
      e.host = SimHost();
      e.start();
      e.ps[0]
        ..score = 64
        ..best = 16;
      e.ps[1]
        ..score = 64
        ..best = 16;
      e.sec = 119;
      (e.host as SimHost).runPending();
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1]);
    });

    test('sudoku: solo resign ends; 2p resign gives the other the win', () {
      final solo = SudokuRace(_setup(1, {'diff': 'easy', 'mistakes': 3}));
      solo.host = SimHost();
      solo.start();
      expect(solo.placings, isNull);
      solo.resign(0);
      expect(solo.isOver, isTrue);
      expect(solo.placings, [1]);

      final e = SudokuRace(_setup(2, {'diff': 'easy', 'mistakes': 3}));
      e.host = SimHost();
      e.start();
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
      expect(e.view(0)['sol'], isNotNull);
    });

    test('sudoku: finisher first, others by progress', () {
      final e = SudokuRace(_setup(3, {'diff': 'easy', 'mistakes': 0}));
      e.host = SimHost();
      e.start();
      final empties = [for (var i = 0; i < 81; i++) if (e.puzzle[i] == 0) i];
      e.handle(2, {'type': 'fill', 'i': empties[0], 'd': e.solution[empties[0]]});
      for (final i in empties) {
        e.handle(1, {'type': 'fill', 'i': i, 'd': e.solution[i]});
      }
      expect(e.isOver, isTrue);
      expect(e.placings, [3, 1, 2]);
    });

    test('bot levels 0/2 think fast', () {
      for (final def in arcadeGames) {
        for (final lvl in [0, 2]) {
          final sw = Stopwatch()..start();
          final r = simulate(def, 2, seed: 4, botLevel: lvl);
          expect(r.finished, isTrue, reason: '${def.id} lvl $lvl: ${r.error}');
          if (r.steps > 0) expect(sw.elapsedMilliseconds / r.steps, lessThan(1500), reason: def.id);
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  test('bot simulations', () {
    final sw = Stopwatch()..start();
    expect(runSims(arcadeGames, n: 30), 0);
    print('sims took ${sw.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
