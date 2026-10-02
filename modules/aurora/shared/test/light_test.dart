import 'dart:math';

import 'package:aurora_shared/games/light/coup.dart';
import 'package:aurora_shared/games/light/defs.dart';
import 'package:aurora_shared/games/light/nothanks.dart';
import 'package:aurora_shared/games/light/sixnimmt.dart';
import 'package:aurora_shared/games/light/skull.dart';
import 'package:aurora_shared/games/light/sushigo.dart';
import 'package:aurora_shared/games/light/themind.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, {Map<String, dynamic> opts = const {}, bool bots = false, int seed = 7}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, bots),
      rng: Random(seed),
    );

T _start<T extends GameEngine>(T e) {
  final h = SimHost();
  e.host = h;
  e.start();
  h.runPending();
  return e;
}

void main() {
  group('6 nimmt', () {
    test('bulls', () {
      expect(nimmtBulls(55), 7);
      expect(nimmtBulls(22), 5);
      expect(nimmtBulls(30), 3);
      expect(nimmtBulls(15), 2);
      expect(nimmtBulls(7), 1);
      var total = 0;
      for (var c = 1; c <= 104; c++) {
        total += nimmtBulls(c);
      }
      expect(total, 171);
    });
    test('target row and sixth card', () {
      final g = _start(SixNimmt(_setup(2)));
      g.rows = [
        [10, 11, 12, 13, 14],
        [20],
        [30],
        [40]
      ];
      expect(nimmtTargetRow(g.rows, 15), 0);
      expect(nimmtTargetRow(g.rows, 25), 1);
      expect(nimmtTargetRow(g.rows, 5), -1);
      g.hands[0] = [15, 60];
      g.hands[1] = [3, 70];
      g.handle(0, {'type': 'choose', 'card': 15});
      g.handle(1, {'type': 'choose', 'card': 3});
      // 3 is lowest: P1 must pick a row first
      expect(g.phase, 'pickRow');
      expect(g.waitingFor, [1]);
      expect(() => g.handle(0, {'type': 'row', 'row': 1}), throwsA(isA<GameError>()));
      g.handle(1, {'type': 'row', 'row': 2});
      expect(g.roundPen[1], 3);
      expect(g.rows[2], [3]);
      // then 15 is the 6th card of row 0
      expect(g.rows[0], [15]);
      expect(g.roundPen[0], nimmtRowBulls([10, 11, 12, 13, 14]));
      expect(g.phase, 'choose');
    });
    test('hand hidden from others', () {
      final g = _start(SixNimmt(_setup(3)));
      expect(g.view(1)['hand'], g.hands[1]);
      expect(g.view(-1)['hand'], isEmpty);
      g.handle(0, {'type': 'choose', 'card': g.hands[0].first});
      expect(g.view(1)['myChoice'], -1);
      expect(g.view(1)['chosen'], [true, false, false]);
    });
  });

  group('No Thanks', () {
    test('runs scoring', () {
      expect(noThanksCardPoints([27, 28, 29]), 27);
      expect(noThanksCardPoints([3, 5, 6, 35]), 3 + 5 + 35);
      expect(noThanksRuns([6, 3, 4, 10]), [
        [3, 4],
        [6],
        [10]
      ]);
    });
    test('pass costs a chip, take collects pot', () {
      final g = _start(NoThanks(_setup(3)));
      expect(g.deck.length, 23);
      final t = g.turn;
      final card = g.current;
      g.handle(t, {'type': 'pass'});
      expect(g.chips[t], 10);
      expect(g.pot, 1);
      final t2 = g.turn;
      g.handle(t2, {'type': 'take'});
      expect(g.cards[t2], [card]);
      expect(g.chips[t2], 12);
      expect(g.turn, t2); // taker continues
      g.chips[t2] = 0;
      expect(() => g.handle(t2, {'type': 'pass'}), throwsA(isA<GameError>()));
    });
  });

  group('Sushi Go', () {
    test('tableau scoring', () {
      expect(sushiTableauPoints(['tempura', 'tempura', 'tempura']), 5);
      expect(sushiTableauPoints(['sashimi', 'sashimi', 'sashimi']), 10);
      expect(sushiTableauPoints(['dumpling', 'dumpling', 'dumpling', 'dumpling']), 10);
      expect(sushiTableauPoints(List.filled(7, 'dumpling')), 15);
      expect(sushiTableauPoints(['w_squid', 'egg', 'wasabi']), 10);
      expect(sushiMakiPoints([5, 5, 2]), [3, 3, 0]);
      expect(sushiMakiPoints([6, 3, 3]), [6, 1, 1]);
      expect(sushiMakiPoints([0, 0, 0]), [0, 0, 0]);
      expect(sushiPuddingPoints([3, 1, 1]), [6, -3, -3]);
      expect(sushiPuddingPoints([2, 0]), [6, 0]);
    });
    test('wasabi, chopsticks and passing', () {
      final g = _start(SushiGo(_setup(2)));
      g.hands[0] = ['wasabi', 'squid', 'egg'];
      g.hands[1] = ['tempura', 'tempura', 'chopsticks'];
      g.tableau[1] = ['chopsticks'];
      g.handle(0, {'type': 'pick', 'card': 0});
      g.handle(1, {'type': 'pick', 'card': 0, 'second': 1});
      expect(g.tableau[1], ['tempura', 'tempura']);
      // hands passed: P0 now holds P1's leftover + returned chopsticks
      expect(g.hands[0], ['chopsticks', 'chopsticks']);
      expect(g.hands[1], ['squid', 'egg']);
      expect(() => g.handle(0, {'type': 'pick', 'card': 0, 'second': 1}), throwsA(isA<GameError>()));
      g.handle(1, {'type': 'pick', 'card': 0});
      g.handle(0, {'type': 'pick', 'card': 0});
      expect(g.tableau[1].first, 'tempura');
      expect(g.view(0)['hand'], isNot(g.view(1)['hand']));
    });
  });

  group('Coup', () {
    Coup mk(int n) {
      final g = _start(Coup(_setup(n)));
      g.turn = 0;
      return g;
    }

    test('successful challenge of a bluff', () {
      final g = mk(3);
      g.hands[0] = ['contessa', 'captain'];
      g.handle(0, {'type': 'tax'});
      expect(g.phase, 'respond');
      g.handle(1, {'type': 'challenge'});
      // bluffer loses influence (must choose, has 2)
      expect(g.phase, 'lose');
      expect(g.loser, 0);
      g.handle(0, {'type': 'lose', 'card': 'captain'});
      expect(g.coins[0], 2);
      expect(g.revealed[0], ['captain']);
      expect(g.turn, 1);
    });
    test('failed challenge: truth-teller swaps card, challenger loses', () {
      final g = mk(3);
      g.hands[0] = ['duke', 'captain'];
      g.handle(0, {'type': 'tax'});
      g.hands[1] = ['contessa'];
      g.revealed[1] = ['duke'];
      g.handle(1, {'type': 'challenge'});
      expect(g.alive(1), isFalse);
      expect(g.coins[0], 5);
      expect(g.hands[0].length, 2);
    });
    test('assassination blocked by contessa, coins not refunded', () {
      final g = mk(2);
      g.coins[0] = 3;
      g.hands[0] = ['assassin', 'duke'];
      g.handle(0, {'type': 'assassinate', 'target': 1});
      expect(g.coins[0], 0);
      g.handle(1, {'type': 'pass'});
      expect(g.phase, 'block');
      g.handle(1, {'type': 'block', 'role': 'contessa'});
      expect(g.phase, 'respondBlock');
      expect(g.waitingFor, [0]);
      g.handle(0, {'type': 'pass'});
      expect(g.hands[1].length, 2);
      expect(g.coins[0], 0);
      expect(g.turn, 1);
    });
    test('must coup at 10 coins, views hide hands', () {
      final g = mk(3);
      g.coins[0] = 10;
      expect(() => g.handle(0, {'type': 'income'}), throwsA(isA<GameError>()));
      g.handle(0, {'type': 'coup', 'target': 2});
      expect(g.coins[0], 3);
      expect(g.view(1)['hand'], g.hands[1]);
      expect(g.view(1)['hands'], isNull);
      expect(g.view(-1)['hand'], isEmpty);
    });
    test('exchange keeps hand size', () {
      final g = mk(3);
      g.hands[0] = ['contessa', 'captain'];
      g.handle(0, {'type': 'exchange'});
      g.handle(1, {'type': 'pass'});
      g.handle(2, {'type': 'pass'});
      expect(g.phase, 'exchange');
      final pool = g.exchangeCards;
      expect(pool.length, 4);
      expect(() => g.handle(0, {'type': 'exchange', 'keep': [pool[0]]}), throwsA(isA<GameError>()));
      g.handle(0, {'type': 'exchange', 'keep': [pool[2], pool[3]]});
      expect(g.hands[0], [pool[2], pool[3]]);
      expect(g.deck.length, 15 - 6);
    });
  });

  group('The Mind', () {
    test('mistake costs a life and discards lower cards', () {
      final g = TheMind(_setup(2))..host = NullHost();
      g.start();
      g.hands[0] = [50];
      g.hands[1] = [10];
      g.handle(0, {'type': 'play'});
      expect(g.lives, 1);
      expect(g.hands[1], isEmpty);
      expect(g.phase, 'levelEnd');
    });
    test('shuriken needs everyone', () {
      final g = TheMind(_setup(2))..host = NullHost();
      g.start();
      g.hands[0] = [5, 50];
      g.hands[1] = [10, 60];
      g.handle(0, {'type': 'star'});
      expect(g.stars, 1);
      g.handle(1, {'type': 'star'});
      expect(g.stars, 0);
      expect(g.hands[0], [50]);
      expect(g.hands[1], [60]);
      expect(g.view(1)['hand'], [60]);
    });
    test('all-bot game terminates', () {
      for (var p = 2; p <= 4; p++) {
        final r = simulate(lightGames.firstWhere((d) => d.id == 'themind'), p, seed: 3);
        expect(r.finished, isTrue);
      }
    });
  });

  group('Skull', () {
    test('challenger flips own first; skull costs a disc', () {
      final g = _start(Skull(_setup(3)));
      g.turn = 0;
      g.handle(0, {'type': 'place', 'skull': false});
      g.handle(1, {'type': 'place', 'skull': true});
      g.handle(2, {'type': 'place', 'skull': false});
      expect(g.phase, 'turn');
      expect(g.view(0)['myMat'], [false]);
      expect(g.view(0)['matCounts'], [1, 1, 1]);
      expect(() => g.handle(0, {'type': 'bid', 'n': 4}), throwsA(isA<GameError>()));
      g.handle(0, {'type': 'bid', 'n': 2});
      g.handle(1, {'type': 'fold'});
      g.handle(2, {'type': 'fold'});
      expect(g.phase, 'flip');
      expect(g.flips, 1); // own disc auto-flipped
      g.handle(0, {'type': 'flip', 'target': 1});
      expect(g.discs(0), 3);
      expect(g.phase, 'roundEnd');
    });
    test('two successes win', () {
      final g = _start(Skull(_setup(3)));
      g.turn = 0;
      g.points[0] = 1;
      for (var s = 0; s < 3; s++) {
        g.handle(s, {'type': 'place', 'skull': false});
      }
      g.handle(0, {'type': 'bid', 'n': 3});
      g.handle(0, {'type': 'flip', 'target': 1});
      g.handle(0, {'type': 'flip', 'target': 2});
      expect(g.isOver, isTrue);
      expect(g.placings![0], 1);
    });
    test('own skull: challenger chooses the lost disc', () {
      final g = _start(Skull(_setup(3)));
      g.turn = 0;
      g.handle(0, {'type': 'place', 'skull': true});
      g.handle(1, {'type': 'place', 'skull': false});
      g.handle(2, {'type': 'place', 'skull': false});
      g.handle(0, {'type': 'bid', 'n': 3});
      expect(g.phase, 'discard');
      g.handle(0, {'type': 'discard', 'skull': false});
      expect(g.roses[0], 2);
      expect(g.hasSkull[0], isTrue);
    });
  });

  test('light sims', () {
    expect(runSims(lightGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
