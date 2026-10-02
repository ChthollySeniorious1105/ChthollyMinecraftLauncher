import 'dart:math';

import 'package:aurora_shared/games/classic/connect4.dart';
import 'package:aurora_shared/games/classic/defs.dart';
import 'package:aurora_shared/games/classic/dotsboxes.dart';
import 'package:aurora_shared/games/classic/draughts.dart';
import 'package:aurora_shared/games/classic/draughts_rules.dart';
import 'package:aurora_shared/games/classic/gomoku.dart';
import 'package:aurora_shared/games/classic/gomoku_rules.dart';
import 'package:aurora_shared/games/classic/othello.dart';
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

GomokuBoard _gb(List<(int, int)> black, [List<(int, int)> white = const []]) {
  final b = GomokuBoard(15);
  for (final (x, y) in black) {
    b.cells[y * 15 + x] = 1;
  }
  for (final (x, y) in white) {
    b.cells[y * 15 + x] = 2;
  }
  return b;
}

int _p(int x, int y) => y * 15 + x;

void main() {
  test('classic games: bots finish every variant', () {
    expect(runSims(classicGames, n: 10), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('v3: resign / draw / placings', () {
    for (final def in classicGames) {
      test('${def.id}: resign gives opponent the win', () {
        final g = def.create(_setup(2))
          ..host = NullHost()
          ..start();
        expect(g.placings, isNull);
        expect(g.canResign, isTrue);
        expect(g.canDraw, isTrue);
        g.resign(1);
        expect(g.isOver, isTrue);
        expect(g.placings, [1, 2]);
        expect(g.canResign, isFalse);
        expect(g.canDraw, isFalse);
        expect(() => g.resign(0), throwsA(isA<GameError>()));
      });
      test('${def.id}: agreeDraw ends as draw', () {
        final g = def.create(_setup(2))..start();
        g.agreeDraw();
        expect(g.isOver, isTrue);
        expect(g.placings, [1, 1]);
      });
      test('${def.id}: rules text and undo flag', () {
        expect(def.rules.length, inInclusiveRange(300, 1500));
        expect(def.undo, isTrue);
      });
    }
    test('resign logs the name', () {
      final host = SimHost();
      final g = Gomoku(_setup(2))
        ..host = host
        ..start();
      g.resign(0);
      expect(host.logs.last, contains('P0 认输'));
      expect(g.placings, [2, 1]);
    });
    test('connect4 natural win placings', () {
      final c = Connect4(_setup(2))..start();
      final a = c.firstSeat, b = 1 - a;
      for (var i = 0; i < 3; i++) {
        c.handle(a, {'type': 'drop', 'col': 0});
        c.handle(b, {'type': 'drop', 'col': 1});
      }
      c.handle(a, {'type': 'drop', 'col': 0});
      expect(c.placings, [a == 0 ? 1 : 2, a == 1 ? 1 : 2]);
    });
    test('dotsboxes 3 players: resign ranks resigner last, others by score', () {
      final d = DotsBoxes(_setup(3, {'size': 3}))..start();
      d.scores[0] = 2;
      d.scores[1] = 1;
      d.resign(0);
      expect(d.isOver, isTrue);
      expect(d.placings, [3, 1, 2]);
    });
    test('dotsboxes full game ranks by score', () {
      final d = DotsBoxes(_setup(2, {'size': 3}))..start();
      while (!d.isOver) {
        d.handle(d.turn, d.bot(d.turn)!);
      }
      final s = d.scores;
      expect(d.placings, s[0] == s[1] ? [1, 1] : (s[0] > s[1] ? [1, 2] : [2, 1]));
    });
    test('dotsboxes exact endgame solver takes free boxes', () {
      final d = DotsBoxes(_setup(2, {'size': 3}))..start();
      // draw every edge except box 0's right edge and a few others
      final geo = d.geo;
      final keep = {13, 3, 4};
      for (var e = 0; e < geo.edges; e++) {
        if (!keep.contains(e)) d.edges[e] = 0;
      }
      final e = DotsAI(geo, d.edges).solve(18);
      expect(e, isNot(-1));
    });
    test('draughts in-game draw offer still works', () {
      final d = Draughts(_setup(2))..start();
      d.handle(0, {'type': 'offerDraw'});
      d.handle(1, {'type': 'acceptDraw'});
      expect(d.placings, [1, 1]);
    });
  });

  group('renju forbidden', () {
    test('double three is forbidden', () {
      final b = _gb([(7, 5), (7, 6), (5, 7), (6, 7)]);
      expect(b.forbiddenType(_p(7, 7)), '三三');
    });
    test('blocked three does not count', () {
      final b = _gb([(7, 5), (7, 6), (5, 7), (6, 7)], [(4, 7), (8, 7)]);
      expect(b.isForbidden(_p(7, 7)), isFalse);
    });
    test('three whose four-point is blocked at both ends is not real', () {
      // vertical .XX?. but white caps at distance so no straight four possible
      final b = _gb([(7, 5), (7, 6), (5, 7), (6, 7)], [(7, 3), (7, 9)]);
      // vertical: y=4..8 space: 4,5,6,7,8 -> straight four needs 6 cells 3..8 or 4..9; both blocked
      expect(b.isForbidden(_p(7, 7)), isFalse);
    });
    test('double four is forbidden', () {
      final b = _gb([(4, 7), (5, 7), (6, 7), (7, 4), (7, 5), (7, 6)]);
      expect(b.forbiddenType(_p(7, 7)), '四四');
    });
    test('double four in one line is forbidden', () {
      final b = _gb([(3, 7), (5, 7), (6, 7), (9, 7)]);
      expect(b.forbiddenType(_p(7, 7)), '四四');
    });
    test('overline is forbidden, exact five is not', () {
      final b = _gb([(2, 7), (3, 7), (4, 7), (6, 7), (7, 7)]);
      expect(b.forbiddenType(_p(5, 7)), '长连');
      final c = _gb([(3, 7), (4, 7), (6, 7), (7, 7), (7, 5), (7, 6), (5, 5), (6, 6)]);
      // (5,7) makes exact five horizontally -> win even if other shapes form
      expect(c.isForbidden(_p(5, 7)), isFalse);
      expect(c.outcome(_p(5, 7), 1, GomokuRule.renju), 'win');
    });
    test('white is never restricted; overline wins for white in renju', () {
      final b = GomokuBoard(15);
      for (final x in [2, 3, 4, 6, 7]) {
        b.cells[_p(x, 7)] = 2;
      }
      expect(b.outcome(_p(5, 7), 2, GomokuRule.renju), 'win');
      expect(b.outcome(_p(5, 7), 2, GomokuRule.standard), 'none');
    });
    test('engine: black forbidden move loses', () {
      final g = Gomoku(_setup(2, {'size': 15, 'rule': 'renju'}))..start();
      final bs = g.blackSeat, ws = 1 - bs;
      final seq = [_p(7, 5), _p(0, 0), _p(7, 6), _p(14, 0), _p(5, 7), _p(0, 14), _p(6, 7), _p(14, 14)];
      for (var i = 0; i < seq.length; i++) {
        g.handle(i.isEven ? bs : ws, {'type': 'play', 'point': seq[i]});
      }
      expect(g.view(bs)['forbidden'], contains(_p(7, 7)));
      expect(GomokuAI(g.b, GomokuRule.renju).best(1, forbidden: {_p(7, 7)}), isNot(_p(7, 7)));
      g.handle(bs, {'type': 'play', 'point': _p(7, 7)});
      expect(g.isOver, isTrue);
      expect(g.winner, ws);
    });
  });

  test('othello flips and legal moves', () {
    final o = Othello(_setup(2))..start();
    expect(o.b.legal(1)..sort(), [19, 26, 37, 44]);
    o.handle(o.blackSeat, {'type': 'play', 'point': 19});
    expect(o.b.c[27], 1);
    expect(o.b.count(1), 4);
    expect(o.b.count(2), 1);
    expect(() => o.handle(1 - o.blackSeat, {'type': 'play', 'point': 0}), throwsA(isA<GameError>()));
  });

  test('connect4 vertical win', () {
    final c = Connect4(_setup(2))..start();
    final a = c.firstSeat, b = 1 - a;
    for (var i = 0; i < 3; i++) {
      c.handle(a, {'type': 'drop', 'col': 0});
      c.handle(b, {'type': 'drop', 'col': 1});
    }
    c.handle(a, {'type': 'drop', 'col': 0});
    expect(c.winner, a);
    expect(c.winLine.length, 4);
  });

  test('connect4 bot blocks and wins', () {
    final cells = List.filled(42, 0);
    for (final col in [0, 1, 2]) {
      cells[5 * 7 + col] = 2;
    }
    expect(Connect4AI(cells).best(1), 3);
    expect(Connect4AI(cells).best(2), 3);
  });

  test('dots and boxes: completing a box gives an extra turn', () {
    final d = DotsBoxes(_setup(2, {'size': 3}))..start();
    final s = d.turn, o = 1 - s;
    // box 0 edges: top 0, bottom 3, left 12, right 13
    d.handle(s, {'edge': 0});
    d.handle(o, {'edge': 3});
    d.handle(s, {'edge': 12});
    expect(d.turn, o);
    d.handle(o, {'edge': 13});
    expect(d.boxes[0], o);
    expect(d.scores[o], 1);
    expect(d.turn, o); // extra turn
    d.handle(o, {'edge': 8});
    expect(d.turn, s);
  });

  group('draughts', () {
    test('international: mandatory maximum capture', () {
      const r = DraughtsRules(10, true);
      final b = List.filled(100, 0);
      b[63] = 1; // (6,3)
      b[54] = -1; // (5,4) -> land 45, then 36 -> land 27
      b[36] = -1;
      b[52] = -1; // (5,2) -> single capture to 41
      b[99 - 1] = -1; // somewhere harmless (9,8)
      final ms = r.legal(b, 1);
      expect(ms.length, 1);
      expect(ms.first.path, [63, 45, 27]);
      expect(ms.first.caps.length, 2);
    });
    test('international men capture backwards; english men do not', () {
      const r = DraughtsRules(10, true);
      final b = List.filled(100, 0);
      b[45] = 1;
      b[56] = -1;
      expect(r.legal(b, 1).any((m) => m.path.join(',') == '45,67'), isTrue);
      const e = DraughtsRules(8, false);
      final c = List.filled(64, 0);
      c[3 * 8 + 4] = 1; // (3,4)
      c[4 * 8 + 5] = -1; // behind
      expect(e.legal(c, 1).any((m) => m.isCapture), isFalse);
    });
    test('international flying king captures from distance', () {
      const r = DraughtsRules(10, true);
      final b = List.filled(100, 0);
      b[90] = 2; // (9,0)
      b[54] = -1; // (5,4)
      final ms = r.legal(b, 1);
      expect(ms.every((m) => m.caps.length == 1 && m.caps.first == 54), isTrue);
      expect(ms.map((m) => m.to).toSet(), {45, 36, 27, 18, 9});
    });
    test('engine rejects non-max capture path and accepts full path', () {
      final d = Draughts(_setup(2, {'variant': 'intl'}))..start();
      final b = List.filled(100, 0)
        ..[63] = 1
        ..[54] = -1
        ..[36] = -1
        ..[52] = -1
        ..[98] = -1;
      d.setPosition(b, 1);
      final me = d.turn;
      expect(() => d.handle(me, {'type': 'move', 'path': [63, 41]}), throwsA(isA<GameError>()));
      expect(() => d.handle(me, {'type': 'move', 'path': [63, 45]}), throwsA(isA<GameError>()));
      d.handle(me, {'type': 'move', 'path': [63, 45, 27]});
      expect(d.board[54], 0);
      expect(d.board[36], 0);
      expect(d.board[27], 1);
    });
    test('english: kings step one square', () {
      const e = DraughtsRules(8, false);
      final c = List.filled(64, 0);
      c[4 * 8 + 3] = 2;
      expect(e.legal(c, 1).length, 4);
    });
  });
}
