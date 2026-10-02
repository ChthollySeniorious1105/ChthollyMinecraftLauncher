import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/shogi/defs.dart';
import 'package:aurora_shared/games/shogi/jieqi_game.dart';
import 'package:aurora_shared/games/shogi/jieqi_rules.dart';
import 'package:aurora_shared/games/shogi/shogi_game.dart';
import 'package:aurora_shared/games/shogi/shogi_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

/// Shogi square from file (1..9) and rank (1..9), e.g. s(7, 6) = ７六.
int s(int file, int rank) => (rank - 1) * 9 + (9 - file);

GameSetup _setup(Map<String, dynamic> opts, [int seed = 1]) =>
    GameSetup(players: 2, options: opts, names: ['A', 'B'], bots: [false, false], rng: Random(seed));

List<int> hand({int p = 0, int l = 0, int n = 0, int sv = 0, int g = 0, int b = 0, int r = 0}) => [0, p, l, n, sv, g, b, r];

void main() {
  group('shogi rules', () {
    test('perft from start', () {
      final p = ShogiPos.initial();
      expect(p.perft(1), 30);
      expect(p.perft(2), 900);
      expect(p.perft(3), 25470);
    });

    test('handicap starts: 上手 moves first, pieces removed', () {
      final p = ShogiPos.initial(4);
      expect(p.side, -1);
      expect(p.b.where((v) => v == -sgR || v == -sgB), isEmpty);
      final l = ShogiPos.initial(1);
      expect(l.b[s(1, 1)], 0);
      expect(l.b[s(9, 1)], -sgL);
    });

    test('二步 is forbidden', () {
      final p = ShogiPos.empty()
        ..setup({s(5, 9): sgK, s(5, 1): -sgK, s(5, 7): sgP}, senteHand: hand(p: 1));
      final ms = p.legal();
      final drops = ms.where((m) => sgIsDrop(m)).map(sgTo).toSet();
      for (var r = 1; r <= 9; r++) {
        expect(drops.contains(s(5, r)), isFalse);
      }
      expect(drops.contains(s(4, 5)), isTrue);
      // no pawn drop on the last rank
      expect(drops.contains(s(4, 1)), isFalse);
    });

    test('打步诘 is forbidden but pawn-drop check is allowed', () {
      // Gote K 1一, own lance blocks 2一; sente gold 2三 guards 1二 and 2二 -> pawn drop 1二 mates.
      final p = ShogiPos.empty()
        ..setup({
          s(1, 1): -sgK,
          s(2, 1): -sgL,
          s(2, 3): sgG,
          s(5, 9): sgK,
        }, senteHand: hand(p: 1));
      final drop = sgMove(81 + sgP, s(1, 2));
      final ps = <int>[];
      p.gen(ps);
      expect(ps.contains(drop), isTrue); // pseudo-legal
      expect(p.isLegal(drop), isFalse); // but mate by pawn drop
      // same with a gold in hand: drop mate is fine
      final q = ShogiPos.empty()
        ..setup({s(1, 1): -sgK, s(2, 1): -sgL, s(2, 3): sgG, s(5, 9): sgK}, senteHand: hand(g: 1));
      expect(q.isLegal(sgMove(81 + sgG, s(1, 2))), isTrue);
      // pawn drop check that is not mate is allowed (king can capture: remove the gold)
      final r = ShogiPos.empty()
        ..setup({s(1, 1): -sgK, s(2, 1): -sgL, s(5, 9): sgK}, senteHand: hand(p: 1));
      expect(r.isLegal(sgMove(81 + sgP, s(1, 2))), isTrue);
    });

    test('promotion rules: optional, forced, none outside zone', () {
      final p = ShogiPos.empty()
        ..setup({
          s(5, 9): sgK,
          s(5, 1): -sgK,
          s(9, 2): sgP, // pawn to 9一 must promote
          s(8, 4): sgS, // silver to 8三 may promote
          s(1, 3): sgN, // knight 1三 -> 2一 must promote
          s(3, 7): sgP, // pawn 3七 -> 3六 cannot promote
        });
      final ms = p.legal();
      bool has(int f, int t, bool pr) => ms.contains(sgMove(f, t, pr));
      expect(has(s(9, 2), s(9, 1), true), isTrue);
      expect(has(s(9, 2), s(9, 1), false), isFalse);
      expect(has(s(8, 4), s(8, 3), true), isTrue);
      expect(has(s(8, 4), s(8, 3), false), isTrue);
      expect(has(s(1, 3), s(2, 1), true), isTrue);
      expect(has(s(1, 3), s(2, 1), false), isFalse);
      expect(has(s(3, 7), s(3, 6), false), isTrue);
      expect(has(s(3, 7), s(3, 6), true), isFalse);
      // promoted pieces move like gold; capture returns base piece to hand
      p.make(sgMove(s(8, 4), s(8, 3), true));
      expect(p.b[s(8, 3)], sgS + sgPromo);
      p.unmake();
      expect(p.b[s(8, 4)], sgS);
    });

    test('captured promoted piece goes to hand unpromoted', () {
      final p = ShogiPos.empty()
        ..setup({s(5, 9): sgK, s(5, 1): -sgK, s(5, 5): sgR, s(5, 3): -(sgB + sgPromo)});
      p.make(sgMove(s(5, 5), s(5, 3), true));
      expect(p.hands[0][sgB], 1);
      expect(p.b[s(5, 3)], sgR + sgPromo);
      p.unmake();
      expect(p.hands[0][sgB], 0);
      expect(p.b[s(5, 3)], -(sgB + sgPromo));
    });

    test('pieces cannot be dropped where they could never move', () {
      final p = ShogiPos.empty()..setup({s(5, 9): sgK, s(5, 5): -sgK}, senteHand: hand(n: 1, l: 1));
      final drops = p.legal().where(sgIsDrop).toList();
      for (final m in drops) {
        final r = sgTo(m) ~/ 9;
        if (sgDropType(m) == sgN) expect(r >= 2, isTrue);
        if (sgDropType(m) == sgL) expect(r >= 1, isTrue);
      }
    });
  });

  group('shogi game', () {
    test('千日手 fourfold repetition is a draw', () {
      final g = ShogiGame(_setup({'handicap': 0}))..start();
      final sente = g.senteSeat, gote = 1 - sente;
      void mv(int seat, int f, int t) => g.handle(seat, {'type': 'move', 'from': f, 'to': t});
      for (var i = 0; i < 4 && !g.isOver; i++) {
        mv(sente, s(2, 8), s(3, 8));
        mv(gote, s(8, 2), s(7, 2));
        mv(sente, s(3, 8), s(2, 8));
        if (g.isOver) break;
        mv(gote, s(7, 2), s(8, 2));
      }
      expect(g.isOver, isTrue);
      expect(g.winner, -1);
      expect(g.reason, contains('千日手'));
    });

    test('perpetual check loses', () {
      final g = ShogiGame(_setup({'handicap': 0}))..start();
      final sente = g.senteSeat, gote = 1 - sente;
      g.pos.setup({s(5, 1): -sgK, s(5, 9): sgK, s(4, 5): sgR}, toMove: 1);
      g.legalMoves = g.pos.legal();
      g.occurrences
        ..clear()
        ..[g.pos.key()] = [0];
      g.checkHist
        ..clear()
        ..add(false);
      g.sideHist
        ..clear()
        ..add(1);
      void mv(int seat, int f, int t) => g.handle(seat, {'type': 'move', 'from': f, 'to': t});
      for (var i = 0; i < 5 && !g.isOver; i++) {
        mv(sente, s(4, 5), s(5, 5)); // 王手 on the 5 file
        mv(gote, s(5, 1), s(4, 1));
        mv(sente, s(5, 5), s(4, 5)); // 王手 on the 4 file
        mv(gote, s(4, 1), s(5, 1));
      }
      expect(g.isOver, isTrue);
      expect(g.winner, gote);
      expect(g.reason, contains('连续将军'));
    });

    test('bot plays legal moves and views are JSON', () {
      final g = ShogiGame(_setup({'handicap': 2}, 3))..start();
      for (var i = 0; i < 20 && !g.isOver; i++) {
        final seat = g.waitingFor.first;
        g.handle(seat, g.bot(seat)!);
        jsonEncode(g.view(seat));
      }
    });

    test('runSims shogi & jieqi', () {
      expect(runSims(shogiGames, n: 5), 0);
    }, timeout: const Timeout(Duration(minutes: 30)));
  });

  group('jieqi', () {
    test('start: all non-king pieces hidden, shuffled per side', () {
      final g = JieqiGame(_setup({}))..start();
      final v = g.view(0);
      final board = (v['board'] as List).cast<int>();
      expect(board.where((x) => x == jHidden).length, 15);
      expect(board.where((x) => x == -jHidden).length, 15);
      expect(board[4], jK);
      expect(board[85], -jK);
      // true identities are a permutation of the piece set
      final red = [for (final sq in jStartSquares(1)) g.pos.b[sq]]..sort();
      expect(red, List.of(jPieceSet)..sort());
      // views never contain real identities of hidden pieces
      final js = jsonEncode(g.view(0)) + jsonEncode(g.view(1)) + jsonEncode(g.view(-1));
      expect(js.contains('"board":[${g.pos.b.join(',')}'), isFalse);
    });

    test('hidden piece moves by square type and is revealed', () {
      final g = JieqiGame(_setup({}, 5))..start();
      final redSeat = g.redSeat;
      // red piece on cannon square (row 2, col 1) moves like a cannon: 炮二平五 -> (2,4)
      final f = 2 * 9 + 1, t = 2 * 9 + 4;
      expect(g.legalMoves.contains(jMove(f, t)), isTrue);
      // a hidden piece on a 马 square cannot move like a cannon
      expect(g.legalMoves.contains(jMove(1, 1 + 9 * 3)), isFalse);
      final real = g.pos.b[f];
      g.handle(redSeat, {'from': f, 'to': t});
      final board = (g.view(1 - redSeat)['board'] as List).cast<int>();
      expect(board[t], real);
      expect(g.pos.hidden[t], isFalse);
    });

    test('revealed advisor / elephant can leave palace and cross river', () {
      final p = JqPos();
      p.b[4] = jK;
      p.b[86] = -jK; // off the king's file (no flying general)
      p.findKings();
      p.b[3 + 4 * 9] = jA; // revealed advisor at row 4 col 3
      p.b[2 + 4 * 9] = jB; // revealed elephant at row 4 col 2
      p.side = 1;
      final ms = p.legal();
      expect(ms.contains(jMove(3 + 4 * 9, 4 + 5 * 9)), isTrue);
      expect(ms.contains(jMove(2 + 4 * 9, 0 + 6 * 9)), isTrue);
      // hidden piece on the advisor square stays in the palace
      final q = JqPos.shuffledStart(Random(1));
      final adv = q.legal().where((m) => jFrom(m) == 3).map(jTo).toList();
      expect(adv, [13]);
    });

    test('captured hidden pieces are revealed only to the capturer', () {
      for (final pub in [false, true]) {
        final g = JieqiGame(_setup({'publicCaptures': pub}, 2))..start();
        // find a capture of a hidden piece by playing bot moves
        var found = false;
        for (var i = 0; i < 200 && !g.isOver; i++) {
          final before = [g.captured[0].length, g.captured[1].length];
          final seat = g.waitingFor.first;
          g.handle(seat, g.bot(seat)!);
          final grew = g.captured[0].length > before[0] ? 0 : (g.captured[1].length > before[1] ? 1 : -1);
          if (grew >= 0) {
            final c = g.captured[grew].last.$2 ? grew : -1;
            if (c < 0) continue;
            final capturer = c == 0 ? g.redSeat : 1 - g.redSeat;
            final mine = (g.view(capturer)['captured'] as List)[c] as List;
            final theirs = (g.view(1 - capturer)['captured'] as List)[c] as List;
            final spec = (g.view(-1)['captured'] as List)[c] as List;
            expect(mine.last, isNot(jHidden));
            if (pub) {
              expect(theirs.last, mine.last);
            } else {
              expect(theirs.last, jHidden);
              expect(spec.last, jHidden);
            }
            found = true;
            break;
          }
        }
        expect(found, isTrue);
      }
    });

    test('bot fairness: swapping hidden identities gives the same action', () {
      for (var seed = 1; seed <= 6; seed++) {
        final a = JieqiGame(_setup({}, seed))..start();
        // play a few moves so that some pieces are revealed
        for (var i = 0; i < 6 && !a.isOver; i++) {
          final seat = a.waitingFor.first;
          a.handle(seat, a.bot(seat)!);
        }
        if (a.isOver) continue;
        final seat = a.waitingFor.first;
        // Swap the identities of two hidden pieces of each color (engine-side only).
        final b = JieqiGame(_setup({}, seed))..start();
        for (var i = 0; i < 6; i++) {
          final st = b.waitingFor.first;
          b.handle(st, b.bot(st)!);
        }
        for (final side in const [1, -1]) {
          final hid = [for (var sq = 0; sq < 90; sq++) if (b.pos.hidden[sq] && (b.pos.b[sq] > 0) == (side > 0)) sq];
          for (var i = 0; i + 1 < hid.length; i += 2) {
            final t = b.pos.b[hid[i]];
            b.pos.b[hid[i]] = b.pos.b[hid[i + 1]];
            b.pos.b[hid[i + 1]] = t;
          }
        }
        a.botNodes = b.botNodes = 4000;
        a.botTimeMs = b.botTimeMs = 100000;
        expect(jsonEncode(a.view(seat)), jsonEncode(b.view(seat)));
        expect(a.bot(seat), b.bot(seat));
      }
    });
  });
  group('v3 platform', () {
    for (final mk in <GameEngine Function(GameSetup)>[ShogiGame.new, JieqiGame.new]) {
      test('resign / agreeDraw / placings (${mk(_setup({})).runtimeType})', () {
        final g = mk(_setup({}))..host = SimHost()..start();
        expect(g.placings, isNull);
        expect(g.canResign, isTrue);
        expect(g.canDraw, isTrue);
        g.resign(0);
        expect(g.isOver, isTrue);
        expect(g.placings, [2, 1]);
        expect(g.canResign, isFalse);
        expect(g.canDraw, isFalse);
        expect((g.host as SimHost).logs.any((l) => l.contains('A 认输')), isTrue);

        final h = mk(_setup({}))..host = SimHost()..start();
        h.resign(1);
        expect(h.placings, [1, 2]);

        final d = mk(_setup({}))..host = SimHost()..start();
        d.agreeDraw();
        expect(d.isOver, isTrue);
        expect(d.placings, [1, 1]);
        expect(d.waitingFor, isEmpty);

        // in-game resign action uses the same path
        final r = mk(_setup({}))..host = SimHost()..start();
        r.handle(1, {'type': 'resign'});
        expect(r.placings, [1, 2]);
      });
    }

    test('bot levels 0 and 2 play legal moves quickly', () {
      for (final lvl in const [0, 2]) {
        for (final mk in <GameEngine Function(GameSetup)>[ShogiGame.new, JieqiGame.new]) {
          final g = mk(GameSetup(players: 2, options: {}, names: ['A', 'B'], bots: [true, true], rng: Random(5), botLevel: lvl))
            ..host = SimHost()
            ..start();
          for (var i = 0; i < 12 && !g.isOver; i++) {
            final seat = g.waitingFor.first;
            final sw = Stopwatch()..start();
            final a = g.runBot(seat)!;
            expect(sw.elapsedMilliseconds, lessThan(1500));
            g.handle(seat, a);
          }
        }
      }
    });
  });
}
