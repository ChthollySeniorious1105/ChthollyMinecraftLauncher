import 'dart:math';

import 'package:aurora_shared/games/race/battleship.dart';
import 'package:aurora_shared/games/race/checkers.dart';
import 'package:aurora_shared/games/race/davinci.dart';
import 'package:aurora_shared/games/race/defs.dart';
import 'package:aurora_shared/games/race/ludo.dart';
import 'package:aurora_shared/games/race/quoridor.dart';
import 'package:aurora_shared/games/race/tictactoe.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int players, [Map<String, dynamic> opts = const {}, int seed = 1]) => GameSetup(
      players: players,
      options: opts,
      names: [for (var i = 0; i < players; i++) 'P$i'],
      bots: List.filled(players, false),
      rng: Random(seed),
    );

void main() {
  test('race games: bots finish every variant', () {
    expect(runSims(raceGames, n: 30), 0);
  });

  group('quoridor', () {
    test('wall blocks movement and cannot overlap/cross', () {
      final q = Quoridor(_setup(2))..start();
      q.handle(0, {'t': 'wall', 'r': 7, 'c': 3, 'o': 'h'}); // below row 7, cols 3-4
      expect(q.blocked(7, 4, 1, 0), isTrue);
      expect(q.blocked(8, 4, -1, 0), isTrue);
      expect(q.blocked(8, 5, -1, 0), isFalse);
      expect(q.wallError(7, 3, 'v'), isNotNull); // cross
      expect(q.wallError(7, 4, 'h'), isNotNull); // overlap
      expect(q.wallError(7, 5, 'h'), isNull);
      expect(q.wallsLeft[0], 9);
    });

    test('cannot seal a pawn off from its goal', () {
      final q = Quoridor(_setup(2))..start();
      // Box pawn 0 at (8,4) in: walls across row 7/8 for cols 0..7 except last column.
      q.walls.addAll(['7,0,h', '7,2,h', '7,4,h', '7,6,h']);
      // column 8 still open; a vertical wall between col 7/8 at rows 7-8 would seal it.
      expect(q.dist(0, q.pawn[0]), greaterThan(0));
      expect(q.wallError(7, 7, 'v'), '不能完全堵死任何棋子的去路');
    });

    test('jump over adjacent pawn and diagonal when blocked', () {
      final q = Quoridor(_setup(2))..start();
      q.pawn[0] = (5, 4);
      q.pawn[1] = (4, 4);
      expect(q.pawnMoves(0), contains((3, 4)));
      q.walls.add('3,3,h'); // wall behind pawn 1 (between rows 3 and 4)
      final m = q.pawnMoves(0);
      expect(m, isNot(contains((3, 4))));
      expect(m, containsAll([(4, 3), (4, 5)]));
    });
  });

  group('battleship', () {
    test('plane shape and bounds', () {
      final cells = PlaneGeo.cells(0, 2, 0);
      expect(cells.length, 10);
      expect(cells.first, (0, 2));
      expect(PlaneGeo.inBounds(0, 2, 0), isTrue);
      expect(PlaneGeo.inBounds(0, 1, 0), isFalse); // wing out of bounds
      expect(PlaneGeo.inBounds(7, 5, 0), isFalse); // tail out of bounds
      for (final (r, c, d) in PlaneGeo.all) {
        expect(PlaneGeo.cells(r, c, d).toSet().length, 10);
      }
    });

    test('layout validation', () {
      expect(PlaneGeo.validate([(0, 2, 0), (0, 7, 0), (5, 4, 0)], 3), isNull);
      expect(PlaneGeo.validate([(0, 2, 0), (1, 2, 0), (5, 4, 0)], 3), '飞机不能重叠');
      expect(PlaneGeo.validate([(0, 0, 0), (0, 7, 0), (5, 4, 0)], 3), '飞机超出边界');
      expect(PlaneGeo.validate([(0, 2, 0)], 3), isNotNull);
    });

    test('shots report miss/hit/head and hide opponent layout', () {
      final b = Battleship(_setup(2))..start();
      b.handle(0, {'t': 'place', 'planes': [[0, 2, 0], [0, 7, 0], [5, 4, 0]]});
      expect(b.view(1)['mine'], isEmpty);
      expect(b.view(1)['planes'], isNull);
      b.handle(1, {'t': 'place', 'planes': [[0, 2, 0], [0, 7, 0], [5, 4, 0]]});
      final s = b.turn;
      b.handle(s, {'t': 'shoot', 'cell': 2}); // head (0,2)
      expect(b.shots[s][2], 2);
      b.handle(1 - s, {'t': 'shoot', 'cell': 12}); // wing (1,2)
      expect(b.shots[1 - s][12], 1);
      b.handle(s, {'t': 'shoot', 'cell': 99});
      expect(b.shots[s][99], 0);
    });
  });

  group('davinci', () {
    test('hands stay sorted, black before white for equal numbers', () {
      for (var seed = 1; seed <= 30; seed++) {
        final d = DaVinci(_setup(3, {}, seed))..start();
        for (final h in d.hand) {
          expect(DaVinci.ordered(h), isTrue);
        }
      }
      final h = <int>[];
      for (final t in [7, 6, 22, 0, 1]) {
        h.insert(DaVinci.insertPos(h, t), t);
      }
      expect(h, [0, 1, 6, 7, 22]); // 黑0 白0 黑3 白3 黑11
    });

    test('views hide opponents tiles', () {
      final d = DaVinci(_setup(2))..start();
      final v = d.view(0)['hands'] as List;
      expect((v[0] as List).every((t) => t['v'] != null), isTrue);
      expect((v[1] as List).every((t) => t['v'] == null), isTrue);
      final spec = d.view(-1)['hands'] as List;
      expect((spec[0] as List).every((t) => t['v'] == null), isTrue);
    });

    test('deduction candidates respect ordering', () {
      final d = DaVinci(_setup(2))..start();
      d.hand[0]
        ..clear()
        ..addAll([0, 2, 4, 6]);
      d.hand[1]
        ..clear()
        ..addAll([8, 10, 12]); // 黑4 黑5 黑6
      d.revealed.addAll([8, 12]);
      final c = d.candidates(0, 1);
      expect(c[1], {5});
    });
  });

  group('ludo', () {
    test('same-colour jump and flying shortcut', () {
      final l = Ludo(_setup(2, {'launch': 6, 'bounce': true, 'triple6': true}))..start();
      l.pos[0][0] = 2;
      expect(l.path(0, 0, 2), [4, 8]); // land on own colour → jump 4
      l.pos[0][0] = 18;
      expect(l.path(0, 0, 2), [20, 28]); // flying square
      l.pos[0][0] = 13;
      expect(l.path(0, 0, 3), [16, 20, 28]); // jump onto flying square then fly
      l.pos[0][0] = -1;
      expect(l.path(0, 0, 5), isNull);
      expect(l.path(0, 0, 6), [0]);
      l.pos[0][0] = 54;
      expect(l.path(0, 0, 4), [54]); // bounce back from finish
    });
  });

  group('chinese checkers', () {
    test('board has 121 holes and 10 per corner', () {
      expect(CCGeo.cells.length, 121);
      for (final c in CCGeo.corners) {
        expect(c.length, 10);
      }
    });

    test('jump chains are reachable', () {
      final g = ChineseCheckers(_setup(2))..start();
      g.board.fillRange(0, g.board.length, -1);
      final a = CCGeo.at(0, 0)!, b = CCGeo.at(1, 0)!, c = CCGeo.at(3, 0)!;
      g.board[a] = 0;
      g.board[b] = 1;
      g.board[c] = 1;
      final r = g.reach(a);
      expect(r.containsKey(CCGeo.at(2, 0)), isTrue); // jump over b
      expect(r.containsKey(CCGeo.at(4, 0)), isTrue); // chained jump over c
      expect(r.containsKey(CCGeo.at(0, 1)), isTrue); // single step
      expect(r.containsKey(CCGeo.at(0, 2)), isFalse);
    });
  });

  group('v3: placings / resign / draw', () {
    test('tictactoe win, resign, draw', () {
      final t = TicTacToe(_setup(2))..start();
      expect(t.placings, isNull);
      expect(t.canResign, isTrue);
      expect(t.canDraw, isTrue);
      final a = t.turn, b = 1 - a;
      for (final (s, c) in [(a, 0), (b, 3), (a, 1), (b, 4), (a, 2)]) {
        t.handle(s, {'cell': c});
      }
      expect(t.isOver, isTrue);
      expect(t.placings![a], 1);
      expect(t.placings![b], 2);
      expect(t.canResign, isFalse);

      final r = TicTacToe(_setup(2))..start();
      r.resign(0);
      expect(r.isOver, isTrue);
      expect(r.placings, [2, 1]);

      final d = TicTacToe(_setup(2))..start();
      d.agreeDraw();
      expect(d.isOver, isTrue);
      expect(d.placings, [1, 1]);
    });

    test('tictactoe hard bot never loses', () {
      for (var seed = 1; seed <= 20; seed++) {
        final setup = GameSetup(players: 2, options: const {}, names: const ['a', 'b'], bots: const [true, true],
            rng: Random(seed), botLevel: 2, botRng: Random(seed + 99));
        final t = TicTacToe(setup)..start();
        while (!t.isOver) {
          t.handle(t.turn, t.runBot(t.turn)!);
        }
        expect(t.winner, 2);
      }
    });

    test('quoridor 2p resign and 3p resign drops the seat', () {
      final q = Quoridor(_setup(2))..start();
      q.resign(1);
      expect(q.isOver, isTrue);
      expect(q.placings, [1, 2]);

      final q3 = Quoridor(_setup(3))..start();
      q3.resign(0);
      expect(q3.isOver, isFalse);
      expect(q3.turn, 1);
      expect(q3.waitingFor, [1]);
      q3.handle(1, {'t': 'wall', 'r': 0, 'c': 0, 'o': 'h'});
      expect(q3.turn, 2);
      q3.handle(2, {'t': 'wall', 'r': 2, 'c': 0, 'o': 'h'});
      expect(q3.turn, 1); // seat 0 skipped
      q3.resign(2);
      expect(q3.isOver, isTrue);
      expect(q3.placings, [3, 1, 2]);

      final qd = Quoridor(_setup(4))..start();
      qd.agreeDraw();
      expect(qd.placings, [1, 1, 1, 1]);
    });

    test('chinese checkers resign removes marbles', () {
      final g = ChineseCheckers(_setup(3))..start();
      final t0 = g.turn;
      g.resign(t0);
      expect(g.board.contains(t0), isFalse);
      expect(g.turn, isNot(t0));
      expect(g.isOver, isFalse);
      g.resign(g.turn);
      expect(g.isOver, isTrue);
      final p = g.placings!;
      expect(p[g.winner], 1);
      expect(p[t0], 3);
    });

    test('battleship resign', () {
      final b = Battleship(_setup(2))..start();
      b.resign(0);
      expect(b.isOver, isTrue);
      expect(b.placings, [2, 1]);
      expect(b.view(0)['planes'], isNotNull);
    });

    test('davinci resign: 2p opponent wins, 3p ranks by knock-out order', () {
      final d = DaVinci(_setup(2))..start();
      d.resign(1 - d.turn);
      expect(d.isOver, isTrue);
      expect(d.placings![d.turn], 1);

      final d3 = DaVinci(_setup(3))..start();
      final first = d3.turn;
      final other = (first + 1) % 3;
      d3.resign(other);
      expect(d3.isOver, isFalse);
      d3.resign(first);
      expect(d3.isOver, isTrue);
      final w = 3 - first - other;
      expect(d3.winner, w);
      expect(d3.placings![w], 1);
      expect(d3.placings![first], 2);
      expect(d3.placings![other], 3);
      expect(d3.waitingFor, isEmpty);
    });

    test('ludo resign skips seat and ends when one remains', () {
      final l = Ludo(_setup(3))..start();
      final t0 = l.turn;
      l.resign(t0);
      expect(l.turn, isNot(t0));
      expect(l.isOver, isFalse);
      l.resign(l.turn);
      expect(l.isOver, isTrue);
      expect(l.placings![l.winner], 1);
      expect(l.placings![t0], 3);
    });
  });
}
