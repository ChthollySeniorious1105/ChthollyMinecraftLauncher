import 'dart:math';

import 'package:aurora_shared/games/abstract2/blokus.dart';
import 'package:aurora_shared/games/abstract2/defs.dart';
import 'package:aurora_shared/games/abstract2/hive.dart';
import 'package:aurora_shared/games/abstract2/onitama.dart';
import 'package:aurora_shared/games/abstract2/quarto.dart';
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

/// Build a hive position: list of (q, r, color, type) bottom-to-top.
HiveState _hive(List<(int, int, int, int)> ps, {bool exp = false, int toMove = 0}) {
  final s = HiveState(exp);
  for (final (q, r, c, t) in ps) {
    (s.st[hk(q, r)] ??= []).add(c * 8 + t);
    s.hand[c][t]--;
    s.placed[c]++;
  }
  s.toMove = toMove;
  return s;
}

Set<(int, int)> _dests(HiveState s, int q, int r) => {for (final k in s.destinations(hk(q, r))) (hq(k), hr(k))};

void main() {
  test('abstract2: bots finish every variant', () {
    expect(runSims(abstract2Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));

  group('hive', () {
    test('queen must be placed by the 4th turn', () {
      final e = Hive(_setup(2))..start();
      final w = e.whiteSeat;
      void place(int seat, String p, int q, int r) => e.handle(seat, {'type': 'place', 'piece': p, 'q': q, 'r': r});
      place(w, 'G', 0, 0);
      place(1 - w, 'G', 1, 0);
      place(w, 'A', -1, 0);
      place(1 - w, 'A', 2, 0);
      place(w, 'S', -2, 0);
      place(1 - w, 'S', 3, 0);
      expect(() => place(w, 'B', -3, 0), throwsA(isA<GameError>()));
      expect(e.view(w)['placeTypes'], ['Q']);
      place(w, 'Q', -3, 0);
    });

    test('first move cannot be the queen; placement must not touch enemy', () {
      final e = Hive(_setup(2))..start();
      final w = e.whiteSeat;
      expect(() => e.handle(w, {'type': 'place', 'piece': 'Q', 'q': 0, 'r': 0}), throwsA(isA<GameError>()));
      e.handle(w, {'type': 'place', 'piece': 'A', 'q': 0, 'r': 0});
      e.handle(1 - w, {'type': 'place', 'piece': 'A', 'q': 1, 'r': 0});
      // (2,0) touches only black -> illegal for white
      expect(() => e.handle(w, {'type': 'place', 'piece': 'G', 'q': 2, 'r': 0}), throwsA(isA<GameError>()));
      e.handle(w, {'type': 'place', 'piece': 'G', 'q': -1, 'r': 0});
    });

    test('one hive rule pins the connecting piece', () {
      // line: A(-1,0) Q(0,0) G(1,0): the middle queen can't move
      final s = _hive([(-1, 0, 0, tA), (0, 0, 0, tQ), (1, 0, 1, tG), (2, 0, 1, tQ)]);
      final ms = s.legalMoves().where((m) => m.kind == 1 && m.from == hk(0, 0));
      expect(ms, isEmpty);
    });

    test('grasshopper jumps over a line', () {
      final s = _hive([(0, 0, 0, tG), (1, 0, 0, tQ), (2, 0, 1, tQ), (3, 0, 1, tA)]);
      expect(_dests(s, 0, 0), contains((4, 0)));
      expect(_dests(s, 0, 0).length, 1);
    });

    test('freedom to move: queen cannot enter a gated gap', () {
      // ring around (0,0) except one neighbour; queen outside can't slide in
      final ring = [for (final d in hDirs.sublist(0, 5)) (hq(hk(0, 0) + d), hr(hk(0, 0) + d))];
      final ps = <(int, int, int, int)>[for (final (q, r) in ring) (q, r, 1, tA)];
      // white queen at the open side's outer spot, next to the hole's entrance
      final open = hk(0, 0) + hDirs[5]; // (0,1)
      ps.add((hq(open), hr(open), 0, tQ));
      final s = _hive(ps.map((p) => p).toList());
      // (0,0) is surrounded on 5 sides + queen => queen at (0,1) can't move into (0,0)? it's adjacent
      // entering from (0,1) to (0,0): the two common neighbours are (-1,1) and (1,0).
      final d = _dests(s, 0, 1);
      expect(d.contains((0, 0)), isFalse);
    });

    test('spider moves exactly 3', () {
      final s = _hive([(0, 0, 0, tS), (1, 0, 0, tQ), (2, 0, 1, tQ)]);
      final d = _dests(s, 0, 0);
      expect(d.every((c) => c != (0, 0)), isTrue);
      // spider around a 2-piece line ends at (2,-1)? positions at distance 3 along the edge
      expect(d.contains((3, -1)) || d.contains((2, 1)) || d.contains((1, 1)) || d.contains((2, -1)), isTrue);
      expect(d.contains((1, -1)), isFalse); // 1 step away
    });

    test('beetle climbs', () {
      final s = _hive([(0, 0, 0, tB), (1, 0, 0, tQ), (2, 0, 1, tQ)]);
      expect(_dests(s, 0, 0), contains((1, 0)));
    });

    test('surrounding the queen wins; both = draw', () {
      final e = Hive(_setup(2))..start();
      final bq = hk(0, 0);
      final ps = <(int, int, int, int)>[(0, 0, 1, tQ)];
      final ts = [tA, tA, tA, tG, tG];
      for (var i = 0; i < 5; i++) {
        final k = bq + hDirs[i];
        ps.add((hq(k), hr(k), 0, ts[i]));
      }
      // white queen next to the gap, far enough to move in
      final gap = bq + hDirs[5];
      final wq = hk(1, 1); // touches (1,0), slides into the gap (0,1)
      ps.add((hq(wq), hr(wq), 0, tQ));
      e.s = _hive(ps);
      e.s.toMove = 0;
      e.handle(e.whiteSeat, {
        'type': 'move',
        'from': [hq(wq), hr(wq)],
        'to': [hq(gap), hr(gap)],
      });
      expect(e.isOver, isTrue);
      expect(e.winner, e.whiteSeat);
      expect(e.placings![e.whiteSeat], 1);
    });

    test('pillbug throws an adjacent piece', () {
      final s = _hive([(0, 0, 0, tP), (1, 0, 0, tQ), (-1, 0, 1, tQ), (-2, 0, 1, tA)], exp: true);
      final th = s.legalMoves().where((m) => m.kind == 2).toList();
      // it may throw its own queen (1,0) around to other empty neighbours; enemy queen is pinned (articulation)
      expect(th.any((m) => m.from == hk(1, 0)), isTrue);
      expect(th.any((m) => m.from == hk(-1, 0)), isFalse);
    });

    test('resign and draw', () {
      final e = Hive(_setup(2))..start();
      e.resign(0);
      expect(e.placings, [2, 1]);
      final d = Hive(_setup(2))..start();
      d.agreeDraw();
      expect(d.placings, [1, 1]);
    });
  });

  group('blokus', () {
    test('21 pieces, 89 squares, orientation counts', () {
      expect(blokusPieces.length, 21);
      expect(blokusPieces.fold(0, (a, p) => a + p.size), 89);
      expect(blokusPieces.firstWhere((p) => p.id == 'X5').orients.length, 1);
      expect(blokusPieces.firstWhere((p) => p.id == 'F5').orients.length, 8);
      expect(blokusPieces.firstWhere((p) => p.id == 'I5').orients.length, 2);
    });

    test('corner rules', () {
      final b = BlokusBoard(20, 4);
      expect(b.check(0, [(1, 1)]), isNotNull); // must cover own corner
      expect(b.check(0, [(0, 0)]), isNull);
      b.place(0, const BlokusMove(0, 0, 0, 0));
      expect(b.check(0, [(1, 0)]), isNotNull); // edge-adjacent
      expect(b.check(0, [(1, 1)]), isNull); // corner
      expect(b.check(0, [(2, 2)]), isNotNull); // not touching
      expect(b.check(1, [(19, 0)]), isNull);
    });

    test('duo start points and scoring bonus', () {
      final e = Blokus(_setup(2))..start();
      expect(e.n, 14);
      expect(() => e.handle(0, {'type': 'place', 'piece': 0, 'orient': 0, 'x': 0, 'y': 0}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'place', 'piece': 0, 'orient': 0, 'x': 4, 'y': 4});
      expect(e.turn, 1);
      expect(e.remaining(0), 88);
      expect(e.score(0), -88);
      for (var p = 0; p < 21; p++) {
        e.b.used[0][p] = true;
      }
      e.lastPiece[0] = 0;
      expect(e.score(0), 20);
      e.lastPiece[0] = 5;
      expect(e.score(0), 15);
    });

    test('4p resign keeps game going', () {
      final e = Blokus(_setup(4))..start();
      e.resign(2);
      expect(e.isOver, isFalse);
      e.resign(0);
      e.resign(1);
      expect(e.isOver, isTrue);
      expect(e.placings![3], 1);
    });
  });

  group('onitama', () {
    test('cards rotate through the side slot', () {
      final e = Onitama(_setup(2))..start();
      final side = e.s.side;
      final seat = e.turnSeat;
      final ms = e.s.moves();
      final (ci, f, t) = ms.first;
      e.handle(seat, {'type': 'move', 'card': oniCards[ci].id, 'from': f, 'to': t});
      expect(e.s.side, ci);
      expect(e.s.hands[1 - e.s.toMove].contains(side), isTrue);
      expect(e.turnSeat, 1 - seat);
    });

    test('16 cards, first player from stamp', () {
      expect(oniCards.length, 16);
      final e = Onitama(_setup(2, const {}, 5))..start();
      expect(e.s.toMove, oniCards[e.s.side].stamp);
    });

    test('temple arch wins', () {
      final e = Onitama(_setup(2))..start();
      final b = List.filled(25, 0);
      b[17] = 2; // red master one step below blue temple (22)
      b[0] = 4; // blue master far away
      e.s = OniState(b, [
        [oniCardIndex('tiger'), oniCardIndex('ox')],
        [oniCardIndex('crab'), oniCardIndex('eel')]
      ], oniCardIndex('boar'), 0);
      e.handle(e.seatOf(0), {'type': 'move', 'card': 'ox', 'from': 17, 'to': 22});
      expect(e.isOver, isTrue);
      expect(e.winner, e.seatOf(0));
    });

    test('blue moves are mirrored', () {
      final b = List.filled(25, 0);
      b[22] = 4;
      b[2] = 2;
      final s = OniState(b, [
        [0, 1],
        [oniCardIndex('tiger'), oniCardIndex('crab')]
      ], 2, 1);
      final ts = s.moves().where((m) => m.$1 == oniCardIndex('tiger')).map((m) => m.$3).toSet();
      expect(ts, {12}); // forward 2 for blue = down 2 rows (22 -> 12); back 1 is off-board
    });
  });

  group('quarto', () {
    test('shared attribute line wins', () {
      final e = Quarto(_setup(2))..start();
      var seat = e.turn;
      // pieces 1,3,5,7 all share bit0 (tall)
      final pcs = [1, 3, 5, 7];
      for (var i = 0; i < 4; i++) {
        e.handle(seat, {'type': 'give', 'piece': pcs[i]});
        seat = 1 - seat;
        e.handle(seat, {'type': 'place', 'cell': i});
        if (i < 3) expect(e.isOver, isFalse);
      }
      expect(e.isOver, isTrue);
      expect(e.winner, seat);
    });

    test('no shared attribute -> no win', () {
      // 0 (0000), 15 (1111), 6 (0110), 9 (1001): each bit mixed
      final b = List.filled(16, -1);
      b[0] = 0;
      b[1] = 15;
      b[2] = 6;
      b[3] = 9;
      expect(QuartoRules.winThrough(b, 3, false), isNull);
    });

    test('square variant', () {
      final b = List.filled(16, -1);
      b[0] = 1;
      b[1] = 3;
      b[4] = 5;
      b[5] = 7;
      expect(QuartoRules.winThrough(b, 5, false), isNull);
      expect(QuartoRules.winThrough(b, 5, true), isNotNull);
    });

    test('bot takes an immediate win and avoids giving one', () {
      final b = List.filled(16, -1);
      b[0] = 1;
      b[1] = 3;
      b[2] = 5;
      final ai = QuartoAI(false);
      final (c, _) = ai.bestPlace(b, 7, 0xFFFF & ~((1 << 1) | (1 << 3) | (1 << 5) | (1 << 7)));
      expect(c, 3);
      final safe = ai.safeGives(b, 0xFFFF & ~((1 << 1) | (1 << 3) | (1 << 5)));
      expect(safe.every((g) => g & 1 == 0), isTrue);
    });
  });
}
