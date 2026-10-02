import 'dart:math';

import 'package:aurora_shared/games/chess/chess_game.dart';
import 'package:aurora_shared/games/chess/chess_rules.dart';
import 'package:aurora_shared/games/chess/defs.dart';
import 'package:aurora_shared/games/chess/go_board.dart';
import 'package:aurora_shared/games/chess/go_game.dart';
import 'package:aurora_shared/games/chess/xiangqi_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int sq(String s) => (int.parse(s[1]) - 1) * 8 + 'abcdefgh'.indexOf(s[0]);
int xs(int row, int col) => row * 9 + col;

GameSetup _setup(Map<String, dynamic> opts, [int seed = 1]) =>
    GameSetup(players: 2, options: opts, names: ['A', 'B'], bots: [false, false], rng: Random(seed));

void main() {
  group('chess', () {
    test('perft start position', () {
      final p = ChessPos.initial();
      expect(p.perft(1), 20);
      expect(p.perft(2), 400);
      expect(p.perft(3), 8902);
    });

    test('perft kiwipete & tricky positions', () {
      expect(ChessPos.fen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1').perft(3), 97862);
      expect(ChessPos.fen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1').perft(4), 43238);
      expect(ChessPos.fen('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1').perft(3), 9467);
    });

    test('en passant', () {
      final p = ChessPos.fen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      final ep = p.legal().where((m) => mFlag(m) & fEp != 0).toList();
      expect(ep.length, 1);
      expect(mTo(ep.first), sq('d6'));
      p.make(ep.first);
      expect(p.b[sq('d5')], 0);
      expect(p.b[sq('d6')], cP);
      p.unmake();
      expect(p.b[sq('d5')], -cP);
      // no ep square -> no ep
      expect(ChessPos.fen('4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1').legal().any((m) => mFlag(m) & fEp != 0), isFalse);
    });

    test('castling rules', () {
      final p = ChessPos.fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final castles = p.legal().where((m) => mFlag(m) & fCastle != 0).map(mTo).toSet();
      expect(castles, {sq('g1'), sq('c1')});
      // cannot castle through attacked square f1
      final q = ChessPos.fen('r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1');
      expect(q.legal().where((m) => mFlag(m) & fCastle != 0).map(mTo).toSet(), {sq('c1')});
      // cannot castle out of check
      final c = ChessPos.fen('r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1');
      expect(c.legal().any((m) => mFlag(m) & fCastle != 0), isFalse);
      // castling moves the rook
      final m = p.legal().firstWhere((m) => mFlag(m) & fCastle != 0 && mTo(m) == sq('g1'));
      p.make(m);
      expect(p.b[sq('f1')], cR);
      expect(p.b[sq('h1')], 0);
      expect(p.castle & 3, 0);
    });

    test('game: fool\'s mate, promotion and SAN', () {
      final g = ChessGame(_setup({}))..start();
      final w = g.whiteSeat, b = 1 - w;
      void mv(int s, String f, String t) => g.handle(s, {'from': sq(f), 'to': sq(t)});
      mv(w, 'f2', 'f3');
      mv(b, 'e7', 'e5');
      mv(w, 'g2', 'g4');
      expect(() => mv(w, 'e2', 'e4'), throwsA(isA<GameError>()));
      mv(b, 'd8', 'h4');
      expect(g.isOver, isTrue);
      expect(g.winner, b);
      expect(g.sanList.last, 'Qh4#');
    });

    test('stalemate and insufficient material', () {
      final p = ChessPos.fen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(p.legal(), isEmpty);
      expect(p.inCheck(), isFalse);
      expect(ChessPos.fen('8/8/4k3/8/8/2B5/4K3/8 w - - 0 1').insufficientMaterial(), isTrue);
      expect(ChessPos.fen('8/8/4k3/8/8/2R5/4K3/8 w - - 0 1').insufficientMaterial(), isFalse);
    });

    test('bot finds mate in one quickly', () {
      final p = ChessPos.fen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
      final sw = Stopwatch()..start();
      final m = ChessSearch(p, limitMs: 400, maxDepth: 3, rng: Random(1)).bestMove();
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(mTo(m), sq('a8'));
    });
  });

  group('xiangqi', () {
    test('perft start position', () {
      final p = XqPos.initial();
      expect(p.perft(1), 44);
      expect(p.perft(2), 1920);
      expect(p.perft(3), 79666);
    });

    List<int> targets(XqPos p, int from) => [for (final m in p.legal()) if (xFrom(m) == from) xTo(m)];

    test('horse leg blocked (蹩马腿)', () {
      // red horse at (0,1) with a piece on (1,1) blocks the forward jumps
      final p = XqPos.fen('3k5/9/9/9/9/9/9/9/1P7/1N2K4 w');
      final t = targets(p, xs(0, 1));
      expect(t.contains(xs(2, 0)), isFalse);
      expect(t.contains(xs(2, 2)), isFalse);
      expect(t.contains(xs(1, 3)), isTrue);
    });

    test('elephant eye blocked and cannot cross river', () {
      final p = XqPos.fen('3k5/9/9/9/9/9/9/9/3P5/2B1K4 w');
      final t = targets(p, xs(0, 2));
      expect(t.contains(xs(2, 4)), isFalse); // eye (1,3) blocked
      expect(t.contains(xs(2, 0)), isTrue);
      final q = XqPos.fen('3k5/9/9/9/9/2B6/9/9/9/4K4 w');
      expect(targets(q, xs(4, 2)).every((to) => to ~/ 9 <= 4), isTrue);
    });

    test('cannon captures by jumping exactly one screen', () {
      final p = XqPos.fen('3k5/9/9/9/9/r8/9/p8/9/C3K4 w');
      final t = targets(p, xs(0, 0));
      expect(t.contains(xs(1, 0)), isTrue);
      expect(t.contains(xs(2, 0)), isFalse); // cannot capture the adjacent-less screen
      expect(t.contains(xs(4, 0)), isTrue); // jump over pawn at (2,0) to rook at (4,0)
      expect(t.contains(xs(3, 0)), isFalse);
    });

    test('flying general is illegal', () {
      // kings on the same file with one blocker: the blocker is pinned
      final p = XqPos.fen('4k4/9/9/9/9/9/9/9/4R4/4K4 w');
      expect(targets(p, xs(1, 4)).every((to) => to % 9 == 4), isTrue);
      final q = XqPos.fen('3k5/9/9/9/9/9/9/9/9/4K4 w');
      expect(targets(q, xs(0, 4)).contains(xs(0, 3)), isFalse); // would face the general
    });

    test('pawn moves sideways only after crossing river', () {
      final p = XqPos.fen('3k5/9/9/9/9/9/4P4/9/9/4K4 w');
      expect(targets(p, xs(3, 4)), [xs(4, 4)]);
      final q = XqPos.fen('3k5/9/9/9/4P4/9/9/9/9/4K4 w');
      expect(targets(q, xs(5, 4)).toSet(), {xs(6, 4), xs(5, 3), xs(5, 5)});
    });

    test('advisor stays on palace diagonals', () {
      final p = XqPos.fen('3k5/9/9/9/9/9/9/9/9/3AK4 w');
      expect(targets(p, xs(0, 3)), [xs(1, 4)]);
    });
  });

  group('go', () {
    test('capture and suicide', () {
      final b = GoBoard(9);
      // white stone at (1,1) surrounded by black
      b.play(10, 2);
      b.play(1, 1);
      b.play(9, 1);
      b.play(11, 1);
      expect(b.play(19, 1), 1);
      expect(b.col[10], 0);
      // corner suicide: white at 0 with black at 1 and 9
      expect(b.isLegal(0, 2), isFalse);
      expect(b.isLegal(10, 2), isFalse);
      expect(b.isLegal(10, 1), isTrue);
    });

    test('ko: immediate recapture forbidden', () {
      final g = GoGame(_setup({'size': 9, 'komi': '7.5', 'handicap': 0}))..start();
      final bs = g.blackSeat, ws = 1 - bs;
      int p(int x, int y) => y * 9 + x;
      void play(int s, int pt) => g.handle(s, {'type': 'play', 'point': pt});
      // build a ko around (1,1)/(2,1)
      play(bs, p(1, 0));
      play(ws, p(2, 0));
      play(bs, p(0, 1));
      play(ws, p(3, 1));
      play(bs, p(1, 2));
      play(ws, p(2, 2));
      play(bs, p(2, 1)); // black stone in white's mouth
      play(ws, p(1, 1)); // white captures -> ko
      expect(g.board.col[p(2, 1)], 0);
      expect(g.caps[2], 1);
      expect(() => play(bs, p(2, 1)), throwsA(isA<GameError>()));
      play(bs, p(8, 8)); // ko threat
      play(ws, p(8, 7));
      play(bs, p(2, 1)); // now allowed
      expect(g.board.col[p(1, 1)], 0);
    });

    test('two passes lead to scoring; area score with komi', () {
      final g = GoGame(_setup({'size': 9, 'komi': '7.5', 'handicap': 0}))..start();
      final bs = g.blackSeat, ws = 1 - bs;
      g.handle(bs, {'type': 'play', 'point': 40});
      g.handle(ws, {'type': 'pass'});
      g.handle(bs, {'type': 'pass'});
      expect(g.phase, 'scoring');
      g.handle(bs, {'type': 'confirm'});
      g.handle(ws, {'type': 'confirm'});
      expect(g.isOver, isTrue);
      expect(g.blackScore, 81);
      expect(g.winner, bs);
    });

    test('handicap stones placed and white moves first', () {
      final g = GoGame(_setup({'size': 19, 'komi': '0.5', 'handicap': 4}))..start();
      expect(g.board.col.where((c) => c == 1).length, 4);
      expect(g.toMove, 2);
    });

    test('bot move is fast on 19x19', () {
      final g = GoGame(_setup({'size': 19, 'komi': '7.5', 'handicap': 0}))..start();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 40; i++) {
        final s = g.waitingFor.first;
        g.handle(s, g.bot(s)!);
      }
      expect(sw.elapsedMilliseconds, lessThan(40 * 300));
    });
  });

  group('v3: resign / draw / placings', () {
    for (final def in chessGames) {
      test('${def.id} resign', () {
        final g = def.create(_setup(def.defaultOptions()))..start();
        expect(g.placings, isNull);
        expect(g.canResign, isTrue);
        g.resign(0);
        expect(g.isOver, isTrue);
        expect(g.placings, [2, 1]);
        expect(g.canResign, isFalse);
      });
      test('${def.id} agreeDraw', () {
        final g = def.create(_setup(def.defaultOptions()))..start();
        expect(g.canDraw, isTrue);
        g.agreeDraw();
        expect(g.isOver, isTrue);
        expect(g.placings, [1, 1]);
      });
      test('${def.id} bot levels respect time budget', () {
        for (final lvl in [0, 2]) {
          final g = def.create(GameSetup(
              players: 2, options: def.defaultOptions(), names: ['A', 'B'], bots: [true, true], rng: Random(3), botLevel: lvl))
            ..start();
          for (var i = 0; i < 12 && !g.isOver; i++) {
            final s = g.waitingFor.first;
            final sw = Stopwatch()..start();
            final a = g.runBot(s)!;
            expect(sw.elapsedMilliseconds, lessThan(1500));
            g.handle(s, a);
          }
        }
      });
    }
  });

  test('chess games: bots finish every variant', () {
    expect(runSims(chessGames, n: 3), 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
