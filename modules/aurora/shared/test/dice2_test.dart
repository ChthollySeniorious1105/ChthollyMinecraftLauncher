import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/dice2/chuiniu.dart';
import 'package:aurora_shared/games/dice2/defs.dart';
import 'package:aurora_shared/games/dice2/dicepoker.dart';
import 'package:aurora_shared/games/dice2/farkle.dart';
import 'package:aurora_shared/games/dice2/pig.dart';
import 'package:aurora_shared/games/dice2/shidianban.dart';
import 'package:aurora_shared/games/dice2/util.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, [Map<String, dynamic> opts = const {}]) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      rng: Random(3),
    );

void main() {
  group('十点半', () {
    test('card values', () {
      expect(sdbHalfValue('AS'), 2);
      expect(sdbHalfValue('7H'), 14);
      expect(sdbHalfValue('TD'), 20);
      expect(sdbHalfValue('KC'), 1);
      expect(sdbPointsText(sdbTotalHalf(['KC', 'TD'])), '10.5');
    });
    test('hand kinds', () {
      final table = <List<String>, SdbKind>{
        ['TS', 'JH']: SdbKind.tenHalf,
        ['5S', '5H', 'QD']: SdbKind.tenHalf,
        ['9S', '2H']: SdbKind.bust,
        ['9S', 'AH']: SdbKind.normal,
        ['AS', 'AH', '2D', '3C', 'KS']: SdbKind.fiveSmall, // 7.5
        ['AS', '2H', '3D', '4C', 'KS']: SdbKind.tianWang, // 10.5 with 5 cards
        ['JS', 'QH', 'KD', 'JC', 'QS']: SdbKind.renWuXiao,
        ['5S', '2H', '2D', '2C', 'KS']: SdbKind.bust, // 11.5
      };
      table.forEach((h, k) => expect(sdbKind(h), k, reason: '$h'));
    });
    test('payouts standard', () {
      // player 十点半 beats banker normal: ×2
      expect(sdbSettle(['TS', 'JH'], ['9S', 'AH'], 10, 'standard'), 20);
      // equal normal points: banker wins
      expect(sdbSettle(['9S', 'AH'], ['8S', '2H'], 10, 'standard'), -10);
      // player higher points
      expect(sdbSettle(['9S', 'AH'], ['8S', 'AH'], 10, 'standard'), 10);
      // player bust loses even if banker busts
      expect(sdbSettle(['9S', '3H'], ['9D', '4H'], 10, 'standard'), -10);
      // banker bust pays by player kind
      expect(sdbSettle(['AS', 'AH', '2D', '3C', 'KS'], ['9D', '4H'], 10, 'standard'), 30);
      // banker 人五小 beats player 天王, player pays ×5
      expect(sdbSettle(['AS', '2H', '3D', '4C', 'KS'], ['JS', 'QH', 'KD', 'JC', 'QS'], 10, 'standard'), -50);
      // tie of 十点半 -> banker, ×2
      expect(sdbSettle(['TS', 'JH'], ['TD', 'QH'], 10, 'standard'), -20);
      expect(sdbSettle(['JS', 'QH', 'KD', 'JC', 'QS'], ['9S', 'AH'], 10, 'high'), 80);
      expect(sdbSettle(['JS', 'QH', 'KD', 'JC', 'QS'], ['9S', 'AH'], 10, 'flat'), 10);
    });
    test('engine rejects junk', () {
      final e = ShiDianBan(_setup(3))..host = SimHost();
      e.start();
      final p = e.waitingFor.first;
      expect(() => e.handle(p, {'type': 'bet', 'amount': 7}), throwsA(isA<GameError>()));
      expect(() => e.handle(e.banker, {'type': 'bet', 'amount': 10}), throwsA(isA<GameError>()));
      expect(() => e.handle(9, {'type': 'bet', 'amount': 10}), throwsA(isA<GameError>()));
      // hidden card
      final other = (p + 1) % 3;
      expect((e.view(p)['hands'] as List)[other], ['']);
      expect(((e.view(p)['hands'] as List)[p] as List).first, isNot(''));
    });
  });

  group('骰子扑克', () {
    test('ranking', () {
      final ranks = <List<int>, int>{
        [4, 4, 4, 4, 4]: 8,
        [4, 4, 4, 4, 2]: 7,
        [3, 3, 3, 6, 6]: 6,
        [2, 3, 4, 5, 6]: 5,
        [1, 2, 3, 4, 5]: 4,
        [5, 5, 5, 1, 2]: 3,
        [5, 5, 2, 2, 1]: 2,
        [6, 6, 1, 2, 3]: 1,
        [1, 2, 3, 4, 6]: 0,
      };
      ranks.forEach((d, r) => expect(dpRank(d), r, reason: '$d'));
      final ordered = ranks.keys.toList();
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(dpScore(ordered[i]) > dpScore(ordered[i + 1]), isTrue);
      }
      // tiebreaks
      expect(dpScore([6, 6, 6, 6, 6]) > dpScore([5, 5, 5, 5, 5]), isTrue);
      expect(dpScore([3, 3, 3, 3, 6]) > dpScore([3, 3, 3, 3, 5]), isTrue);
      expect(dpScore([6, 6, 1, 1, 2]) > dpScore([5, 5, 4, 4, 6]), isTrue);
      expect(dpScore([2, 2, 5, 4, 3]), dpScore([3, 4, 2, 5, 2]));
    });
    test('roll limits', () {
      final e = DicePoker(_setup(2))..host = SimHost();
      e.start();
      final t = e.turn;
      expect(() => e.handle(t, {'type': 'stand'}), throwsA(isA<GameError>()));
      e.handle(t, {'type': 'roll'});
      expect(() => e.handle(t, {'type': 'roll', 'hold': [true, true]}), throwsA(isA<GameError>()));
      expect(() => e.handle(t, {'type': 'roll', 'hold': List.filled(5, true)}), throwsA(isA<GameError>()));
      e.handle(t, {'type': 'roll', 'hold': List.filled(5, false)});
      e.handle(t, {'type': 'roll'});
      expect(e.turn, isNot(t)); // third roll ends turn
    });
  });

  group('猪骰', () {
    test('outcomes', () {
      expect(pigOutcome([1]), PigOutcome.loseTurn);
      expect(pigOutcome([4]), PigOutcome.add);
      expect(pigOutcome([1, 5]), PigOutcome.loseTurn);
      expect(pigOutcome([1, 1]), PigOutcome.loseAll);
      expect(pigOutcome([6, 6]), PigOutcome.add);
    });
    test('hold banks, 1 loses turn points', () {
      final e = PigDice(_setup(2))..host = SimHost();
      e.start();
      final t = e.turn;
      expect(() => e.handle(t, {'type': 'hold'}), throwsA(isA<GameError>()));
      expect(() => e.handle(1 - t, {'type': 'roll'}), throwsA(isA<GameError>()));
      var guard = 0;
      while (e.turn == t && guard++ < 100) {
        e.handle(t, {'type': 'roll'});
        if (e.turn == t && e.turnPoints >= 10) {
          final tp = e.turnPoints;
          e.handle(t, {'type': 'hold'});
          expect(e.scores[t], tp);
        }
      }
      expect(e.turn, 1 - t);
    });
  });

  group('快乐骰 Farkle', () {
    test('scoring table', () {
      final table = <List<int>, int>{
        [1]: 100,
        [5]: 50,
        [1, 5]: 150,
        [1, 1]: 200,
        [2]: 0,
        [1, 2]: 0,
        [2, 2, 2]: 200,
        [3, 3, 3]: 300,
        [6, 6, 6]: 600,
        [1, 1, 1]: 1000,
        [4, 4, 4, 4]: 800,
        [4, 4, 4, 4, 4]: 1600,
        [4, 4, 4, 4, 4, 4]: 3200,
        [1, 1, 1, 1]: 2000,
        [1, 1, 1, 1, 1, 1]: 8000,
        [5, 5, 5, 5]: 1000,
        [2, 2, 2, 1]: 300,
        [2, 2, 2, 5, 5]: 300,
        [1, 2, 3, 4, 5, 6]: 1500,
        [2, 2, 3, 3, 4, 4]: 750,
        [1, 1, 5, 5, 6, 6]: 750,
        [2, 2, 2, 2, 3, 3]: 750, // four of a kind + pair counts as three pairs
        [1, 1, 1, 1, 5, 5]: 2100, // 2000 + 100 > 750
        [3, 3, 3, 4, 4, 4]: 700,
        [2, 3, 4, 5, 6]: 0, // partial straight: 6 is not scoring alone
        [1, 1, 1, 5]: 1050,
      };
      table.forEach((d, s) => expect(farkleScore(d), s, reason: '$d'));
    });
    test('best & bust', () {
      expect(farkleIsBust([2, 3, 4, 6, 6, 2]), isTrue);
      expect(farkleIsBust([2, 3]), isTrue);
      expect(farkleIsBust([2, 5]), isFalse);
      expect(farkleBest([2, 2, 2, 1, 3, 4]).$1, 300);
      expect(farkleBest([1, 2, 3, 4, 5, 6]).$1, 1500);
    });
    test('engine validates keep', () {
      final e = Farkle(_setup(2))..host = SimHost();
      e.start();
      final t = e.turn;
      expect(() => e.handle(t, {'type': 'keep', 'dice': [0]}), throwsA(isA<GameError>()));
      e.roll = [2, 3, 4, 6, 6, 5];
      expect(() => e.handle(t, {'type': 'keep', 'dice': [0, 5]}), throwsA(isA<GameError>()));
      expect(() => e.handle(t, {'type': 'keep', 'dice': [5, 5]}), throwsA(isA<GameError>()));
      expect(() => e.handle(t, {'type': 'keep', 'dice': [9]}), throwsA(isA<GameError>()));
      e.handle(t, {'type': 'keep', 'dice': [5], 'then': 'bank'});
      expect(e.scores[t], 50);
      expect(e.turn, 1 - t);
    });
    test('final round after reaching target', () {
      final e = Farkle(_setup(3, {'target': 5000}))..host = SimHost();
      e.start();
      final t = e.turn;
      e.scores[t] = 4900;
      e.roll = [1, 1, 1, 2, 3, 4];
      e.handle(t, {'type': 'keep', 'dice': [0, 1, 2], 'then': 'bank'});
      expect(e.finalTrigger, t);
      expect(e.isOver, isFalse);
      for (var i = 0; i < 2; i++) {
        final s = e.turn;
        e.roll = [5, 2, 3, 4, 6, 6];
        e.handle(s, {'type': 'keep', 'dice': [0], 'then': 'bank'});
      }
      expect(e.isOver, isTrue);
      expect(e.winners, [t]);
    });
  });

  group('吹牛骰', () {
    test('counting with wild 1s and 斋', () {
      final dice = [
        [1, 2, 3, 3, 6],
        [1, 1, 3, 5, 5],
      ];
      expect(cnCount(dice, 3, false), 6);
      expect(cnCount(dice, 3, true), 3);
      expect(cnCount(dice, 1, false), 3);
      expect(cnCount(dice, 5, false), 5);
    });
    test('bid validity', () {
      String? v(int q, int f, bool z, int pq, int pf, bool pz) =>
          cnBidError(q, f, z, pq, pf, pz, minFly: 3, minZhai: 2, total: 10);
      expect(v(2, 3, false, 0, 0, false), isNotNull); // opening fly min = players+1
      expect(v(3, 3, false, 0, 0, false), isNull);
      expect(v(2, 3, true, 0, 0, false), isNull); // 斋 min = players
      expect(v(2, 1, false, 0, 0, false), isNull); // 1s are always 斋
      expect(v(4, 3, false, 3, 5, false), isNull);
      expect(v(3, 6, false, 3, 5, false), isNull);
      expect(v(3, 4, false, 3, 5, false), isNotNull);
      expect(v(3, 1, false, 3, 6, false), isNull); // 1 ranks above 6
      expect(v(3, 4, true, 3, 5, false), isNull); // 飞→斋 same qty ok
      expect(v(2, 4, true, 3, 5, false), isNotNull);
      expect(v(5, 4, false, 3, 5, true), isNotNull); // 斋→飞 needs double
      expect(v(6, 4, false, 3, 5, true), isNull);
      expect(v(4, 2, true, 3, 5, true), isNull);
      expect(v(11, 2, false, 3, 5, false), isNotNull);
      expect(v(4, 7, false, 3, 5, false), isNotNull);
    });
    test('challenge resolution incl. 斋 and 劈', () {
      final e = ChuiNiu(_setup(2))..host = SimHost();
      e.start();
      e.dice = [
        [1, 2, 3, 3, 6],
        [1, 1, 3, 5, 5],
      ];
      e.turn = 0;
      e.handle(0, {'type': 'bid', 'qty': 4, 'face': 3, 'zhai': true}); // only 3 threes
      expect(() => e.handle(0, {'type': 'open'}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'open'});
      expect(e.lives, [2, 3]);
      expect(e.view(0)['reveal']['count'], 3);
      // hidden dice
      expect(e.view(1)['dice'], [1, 1, 3, 5, 5]);
      expect(e.view(-1)['dice'], isEmpty);

      final f = ChuiNiu(_setup(2))..host = SimHost();
      f.start();
      f.dice = [
        [1, 2, 3, 3, 6],
        [1, 1, 3, 5, 5],
      ];
      f.turn = 0;
      f.handle(0, {'type': 'bid', 'qty': 6, 'face': 3}); // 6 with wilds: true
      f.handle(1, {'type': 'pi'});
      expect(f.waitingFor, [0]);
      f.handle(0, {'type': 'repi'});
      expect(f.lives, [3, 0]);
      expect(f.stake, 4);
    });
    test('bot does not see others (spectator dice empty)', () {
      final e = ChuiNiu(_setup(3))..host = SimHost();
      e.start();
      final a = e.bot(e.turn)!;
      expect(a['type'], 'bid');
    });
  });

  group('v3: placings / resign', () {
    test('d2Placings: scores, exits ranked last (later exit better), forced winner', () {
      expect(d2Placings([10, 30, 30], []), [3, 1, 1]);
      expect(d2Placings([10, 30, 50, 5], [2, 0]), [3, 1, 4, 2]);
      expect(d2Placings([10, 30, 50], [], winner: 0), [1, 3, 2]);
    });
    test('null until over', () {
      for (final def in dice2Games) {
        final e = def.create(_setup(3, def.defaultOptions()))..host = SimHost();
        e.start();
        expect(e.placings, isNull, reason: def.id);
      }
    });
    test('pig: 2-player resign -> opponent wins', () {
      final e = PigDice(_setup(2))..host = SimHost();
      e.start();
      expect(e.canResign, isTrue);
      e.scores = [40, 10];
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.winner, 1);
      expect(e.placings, [2, 1]);
      expect(e.canResign, isFalse);
    });
    test('pig: 3-player resign drops seat, game continues', () {
      final host = SimHost();
      final e = PigDice(_setup(3))..host = host;
      e.start();
      final t = e.turn;
      e.resign(t);
      expect(host.logs.last, contains('认输'));
      expect(e.isOver, isFalse);
      expect(e.turn, isNot(t));
      e.scores[(t + 1) % 3] = 99;
      final w = (t + 1) % 3;
      while (e.turn != w) {
        e.handle(e.turn, {'type': 'roll'});
        if (!e.isOver && e.turnRolls > 0 && e.turn != w) e.handle(e.turn, {'type': 'hold'});
      }
      var guard = 0;
      while (!e.isOver && guard++ < 200) {
        if (e.turn == w) {
          e.handle(w, {'type': 'roll'});
        } else {
          e.handle(e.turn, {'type': 'roll'});
          if (!e.isOver && e.turnRolls > 0 && e.turn != w) e.handle(e.turn, {'type': 'hold'});
        }
      }
      expect(e.isOver, isTrue);
      expect(e.placings![t], 3);
      expect(e.placings!.contains(1), isTrue);
    });
    test('farkle placings by score, resign last', () {
      final e = Farkle(_setup(3, {'target': 5000}))..host = SimHost();
      e.start();
      final t = e.turn;
      final r = (t + 2) % 3;
      e.resign(r);
      e.scores[t] = 4900;
      e.roll = [1, 1, 1, 2, 3, 4];
      e.handle(t, {'type': 'keep', 'dice': [0, 1, 2], 'then': 'bank'});
      final s = e.turn;
      expect(s, (t + 1) % 3);
      e.roll = [5, 2, 3, 4, 6, 6];
      e.handle(s, {'type': 'keep', 'dice': [0], 'then': 'bank'});
      expect(e.isOver, isTrue);
      expect(e.placings, [for (var i = 0; i < 3; i++) i == t ? 1 : (i == r ? 3 : 2)]);
      final f = Farkle(_setup(2))..host = SimHost();
      f.start();
      f.resign(f.turn);
      expect(f.isOver, isTrue);
      expect(f.placings![f.turn], 2);
    });
    test('dicepoker placings by points; resign', () {
      final e = DicePoker(_setup(3))..host = SimHost();
      e.start();
      e.points = [2, 5, 2];
      e.phase = 'over';
      expect(e.placings, [2, 1, 2]);
      final f = DicePoker(_setup(2))..host = SimHost();
      f.start();
      f.points = [3, 0];
      f.resign(0);
      expect(f.isOver, isTrue);
      expect(f.placings, [2, 1]);
      expect(f.winners, [1]);
    });
    test('chuiniu: resign mid-bid, knocked-out order', () {
      final host = SimHost();
      final e = ChuiNiu(_setup(3))..host = host;
      e.start();
      e.lives = [3, 3, 3];
      e.resign(1);
      expect(e.isOver, isFalse);
      expect(e.phase, 'bid');
      expect(e.lives[1], 0);
      expect(e.waitingFor.single, isNot(1));
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.winner, 2);
      expect(e.placings, [2, 3, 1]);
    });
    test('shidianban placings by chips', () {
      final e = ShiDianBan(_setup(3))..host = SimHost();
      e.start();
      e.chips = [900, 1200, 900];
      e.phase = 'over';
      expect(e.placings, [2, 1, 2]);
      expect(e.canResign, isFalse);
    });
    test('bot() does not change game state or rng', () {
      for (final def in dice2Games) {
        for (final lvl in [0, 1, 2]) {
          final setup = GameSetup(
            players: 3,
            options: def.defaultOptions(),
            names: ['a', 'b', 'c'],
            bots: [true, true, true],
            rng: Random(5),
            botLevel: lvl,
          );
          final e = def.create(setup)..host = SimHost();
          e.start();
          for (var k = 0; k < 20 && !e.isOver; k++) {
            final w = e.waitingFor;
            if (w.isEmpty) break;
            final before = jsonEncode(e.view(-1));
            final a = e.runBot(w.first);
            expect(jsonEncode(e.view(-1)), before, reason: def.id);
            if (a == null) break;
            e.handle(w.first, a);
          }
        }
      }
    });
  });

  test('simulate all', () {
    expect(runSims(dice2Games, n: 30), 0);
  });
}
