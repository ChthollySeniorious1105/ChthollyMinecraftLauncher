import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/monopoly/board_data.dart';
import 'package:aurora_shared/games/monopoly/defs.dart';
import 'package:aurora_shared/games/monopoly/monopoly.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

MonopolyGame _game(int players, {Map<String, dynamic> opts = const {}, int seed = 1}) {
  final g = MonopolyGame(GameSetup(
    players: players,
    options: {...monopolyGames.first.defaultOptions(), ...opts},
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: List.filled(players, false),
    rng: Random(seed),
  ));
  g.start();
  return g;
}

/// Finds a seed whose first roll(s) satisfy [pred].
MonopolyGame _seeded(int players, bool Function(Random r) pred, {Map<String, dynamic> opts = const {}}) {
  for (var s = 1; s < 5000; s++) {
    final probe = Random(s);
    // start() shuffles two decks first
    shuffled(List.generate(16, (i) => i), probe);
    shuffled(List.generate(16, (i) => i), probe);
    if (pred(probe)) return _game(players, opts: opts, seed: s);
  }
  throw StateError('no seed');
}

void main() {
  test('monopoly: bots finish every variant', () {
    expect(runSims(monopolyGames, n: 30), 0);
  });

  test('board has 22 streets in 8 groups, 4 stations, 2 utilities', () {
    expect(mBoard.length, 40);
    expect(mBoard.where((s) => s.type == SqType.street).length, 22);
    expect(mGroups.map((g) => g.length).toList(), [2, 3, 3, 3, 3, 3, 3, 2]);
    expect(mStations.every((i) => mBoard[i].type == SqType.station), isTrue);
    expect(mUtilities.every((i) => mBoard[i].type == SqType.utility), isTrue);
  });

  group('rent', () {
    test('streets: base, monopoly doubles, houses, hotel, mortgage', () {
      final g = _game(2);
      g.owner[1] = 0;
      expect(g.rentFor(1), 2);
      g.owner[3] = 0;
      expect(g.rentFor(1), 4);
      expect(g.rentFor(3), 8);
      g.houses[1] = 1;
      expect(g.rentFor(1), 10);
      g.houses[1] = 5;
      expect(g.rentFor(1), 250);
      g.houses[1] = 0;
      g.mortgaged[1] = true;
      expect(g.rentFor(1), 0);
    });

    test('stations 25/50/100/200', () {
      final g = _game(2);
      final r = <int>[];
      for (final s in mStations) {
        g.owner[s] = 1;
        r.add(g.rentFor(5));
      }
      expect(r, [25, 50, 100, 200]);
      expect(g.rentFor(5, stationMult: 2), 400);
    });

    test('utilities 4x / 10x dice', () {
      final g = _game(2);
      g.owner[12] = 0;
      expect(g.rentFor(12, diceSum: 7), 28);
      g.owner[28] = 0;
      expect(g.rentFor(12, diceSum: 7), 70);
    });
  });

  test('even-build rule and hotel supply', () {
    final g = _game(2, opts: {'cash': 2000});
    for (final i in mGroups[1]) {
      g.owner[i] = 0;
    }
    g.owner[6] = 1;
    expect(g.manageError(0, 'build', 8), isNotNull); // no monopoly
    g.owner[6] = 0;
    g.handle(0, {'t': 'build', 'sq': 6});
    expect(() => g.handle(0, {'t': 'build', 'sq': 6}), throwsA(isA<GameError>()));
    g.handle(0, {'t': 'build', 'sq': 8});
    g.handle(0, {'t': 'build', 'sq': 9});
    g.handle(0, {'t': 'build', 'sq': 6});
    expect(g.houses.sublist(6, 10), [2, 0, 1, 1]);
    expect(g.housesLeft, 28);
    // selling must be even too
    expect(g.manageError(0, 'sell', 8), isNotNull);
    g.handle(0, {'t': 'sell', 'sq': 6});
    expect(g.houses[6], 1);
    // mortgage blocked while group has houses
    expect(g.manageError(0, 'mortgage', 6), isNotNull);
    // hotel
    for (final i in mGroups[1]) {
      g.houses[i] = 4;
    }
    g.handle(0, {'t': 'build', 'sq': 6});
    expect(g.houses[6], 5);
    expect(g.hotelsLeft, 11);
  });

  test('mortgage pays half, unmortgage costs +10%', () {
    final g = _game(2);
    g.owner[39] = 0;
    final c = g.cash[0];
    g.handle(0, {'t': 'mortgage', 'sq': 39});
    expect(g.cash[0], c + 200);
    expect(g.rentFor(39), 0);
    g.handle(0, {'t': 'unmortgage', 'sq': 39});
    expect(g.cash[0], c - 20);
    expect(g.mortgaged[39], isFalse);
  });

  test('jail: pay 50, use card, three failed tries', () {
    final g = _game(2);
    g.inJail[0] = true;
    g.pos[0] = mJailSq;
    g.handle(0, {'t': 'payJail'});
    expect(g.inJail[0], isFalse);
    expect(g.cash[0], 1450);

    g.inJail[0] = true;
    g.jailCards[0].add('chance');
    g.handle(0, {'t': 'useCard'});
    expect(g.inJail[0], isFalse);
    expect(g.jailCards[0], isEmpty);

    // non-double seed: roll 3 times in jail
    final h = _seeded(2, (r) {
      final a = [for (var i = 0; i < 6; i++) r.nextInt(6)];
      return a[0] != a[1] && a[2] != a[3] && a[4] != a[5];
    });
    for (var k = 0; k < 3; k++) {
      h.turn = 0;
      h.phase = 'roll';
      h.inJail[0] = true;
      h.pos[0] = mJailSq;
      h.handle(0, {'t': 'roll'});
      if (k < 2) {
        expect(h.inJail[0], isTrue);
        expect(h.pos[0], mJailSq);
      }
    }
    expect(h.inJail[0], isFalse);
    expect(h.pos[0], isNot(mJailSq));
  });

  test('doubles roll again; third double sends you to jail', () {
    final g = _seeded(2, (r) => r.nextInt(6) == r.nextInt(6));
    g.handle(0, {'t': 'roll'});
    expect(g.again, isTrue);
    final h = _seeded(2, (r) => r.nextInt(6) == r.nextInt(6));
    h.doubles = 2;
    h.handle(0, {'t': 'roll'});
    expect(h.inJail[0], isTrue);
    expect(h.pos[0], mJailSq);
    expect(h.phase, 'end');
    expect(h.again, isFalse);
  });

  test('bankruptcy to creditor transfers properties and cash', () {
    final g = _game(3);
    g.owner[39] = 1;
    g.houses[39] = 0;
    g.owner[1] = 0;
    g.owner[3] = 0;
    g.houses[1] = 1;
    g.houses[3] = 1;
    g.housesLeft = 30;
    g.cash[0] = 10;
    g.jailCards[0].add('chest');
    g.debts.add(MDebt(0, 1, 5000, 'test'));
    g.phase = 'debt';
    final before = g.cash[1];
    g.handle(0, {'t': 'bankrupt'});
    expect(g.bankrupt[0], isTrue);
    expect(g.owner[1], 1);
    expect(g.owner[3], 1);
    expect(g.houses[1], 0);
    expect(g.housesLeft, 32);
    expect(g.cash[1], before + 10 + 50); // cash + half of 2 houses
    expect(g.jailCards[1], ['chest']);
    expect(g.isOver, isFalse);
    expect(g.turn, 1); // bankrupt turn player's turn passes on
  });

  test('bankruptcy to bank returns properties; last player wins', () {
    final g = _game(2, opts: {'end': 0});
    g.owner[5] = 0;
    g.mortgaged[5] = true;
    g.cash[0] = 0;
    g.debts.add(MDebt(0, -1, 200, 'tax'));
    g.phase = 'debt';
    g.handle(0, {'t': 'bankrupt'});
    expect(g.owner[5], -1);
    expect(g.mortgaged[5], isFalse);
    expect(g.isOver, isTrue);
    expect(g.winner, 1);
  });

  test('trade swaps property and cash', () {
    final g = _game(2);
    g.phase = 'end';
    g.owner[1] = 0;
    g.owner[3] = 1;
    g.handle(0, {'t': 'trade', 'to': 1, 'give': [1], 'get': [3], 'giveCash': 100, 'getCash': 0});
    expect(g.waitingFor, [1]);
    g.handle(1, {'t': 'accept'});
    expect(g.owner[1], 1);
    expect(g.owner[3], 0);
    expect(g.cash, [1400, 1600]);
    expect(g.phase, 'end');
  });

  test('auction: highest bidder wins', () {
    final g = _game(3);
    g.buySq = 39;
    g.phase = 'buy';
    g.handle(0, {'t': 'decline'});
    expect(g.phase, 'auction');
    expect(g.waitingFor.toSet(), {0, 1, 2});
    g.handle(0, {'t': 'bid', 'amount': 100});
    g.handle(1, {'t': 'bid', 'amount': 150});
    g.handle(2, {'t': 'pass'});
    expect(g.aucLeader, 1);
    expect(g.waitingFor, [0]);
    g.handle(0, {'t': 'pass'});
    expect(g.owner[39], 1);
    expect(g.cash[1], 1350);
  });

  group('v3: placings / resign', () {
    test('null until over; bankrupt order ranks (last bankrupt better), survivors by worth', () {
      final g = _game(4);
      expect(g.placings, isNull);
      g.cash[2] = 0;
      g.debts.add(MDebt(2, -1, 500, 'tax'));
      g.phase = 'debt';
      g.handle(2, {'t': 'bankrupt'});
      g.cash[0] = 0;
      g.debts.add(MDebt(0, -1, 500, 'tax'));
      g.phase = 'debt';
      g.handle(0, {'t': 'bankrupt'});
      expect(g.isOver, isFalse);
      g.cash[1] = 3000;
      g.cash[3] = 100;
      g.debts.add(MDebt(3, 1, 5000, 'rent'));
      g.phase = 'debt';
      g.handle(3, {'t': 'bankrupt'});
      expect(g.isOver, isTrue);
      expect(g.placings, [3, 1, 4, 2]);
      expect(g.winner, 1);
    });

    test('timed game: survivors ranked by net worth, ties share', () {
      final g = _game(3, opts: {'end': 30});
      g.cash = [500, 900, 500];
      g.round = 30;
      g.turn = 2;
      g.phase = 'end';
      g.handle(2, {'t': 'end'});
      expect(g.isOver, isTrue);
      expect(g.placings, [2, 1, 2]);
    });

    test('resign in 2-player game ends it, opponent wins', () {
      final host = SimHost();
      final g = _game(2)..host = host;
      g.owner[39] = 0;
      expect(g.canResign, isTrue);
      g.resign(0);
      expect(host.logs, contains('P0 认输'));
      expect(g.isOver, isTrue);
      expect(g.winner, 1);
      expect(g.placings, [2, 1]);
      expect(g.owner[39], -1);
      expect(g.canResign, isFalse);
    });

    test('resign in 3-player game: seat out, ranked last, turn passes', () {
      final g = _game(3);
      g.owner[1] = 0;
      g.resign(0);
      expect(g.isOver, isFalse);
      expect(g.bankrupt[0], isTrue);
      expect(g.owner[1], -1);
      expect(g.turn, 1);
      expect(g.phase, 'roll');
      // later a real bankruptcy still ranks above the resigned seat
      g.cash[2] = 0;
      g.debts.add(MDebt(2, 1, 100, 'rent'));
      g.phase = 'debt';
      g.handle(2, {'t': 'bankrupt'});
      expect(g.isOver, isTrue);
      expect(g.placings, [3, 1, 2]);
    });

    test('resign during auction / debt / trade keeps the game going', () {
      final g = _game(3);
      g.buySq = 39;
      g.phase = 'buy';
      g.handle(0, {'t': 'decline'});
      g.handle(0, {'t': 'bid', 'amount': 100});
      g.handle(1, {'t': 'bid', 'amount': 150});
      g.handle(2, {'t': 'pass'});
      expect(g.aucLeader, 1);
      expect(g.waitingFor, [0]);
      g.resign(1); // leader leaves: auction restarts for the others
      expect(g.phase, 'auction');
      expect(g.waitingFor.toSet(), {0, 2});
      g.handle(0, {'t': 'pass'});
      g.handle(2, {'t': 'pass'});
      expect(g.phase, isNot('auction'));
      expect(g.owner[39], -1);

      final h = _game(3);
      h.cash[1] = 0;
      h.debts.add(MDebt(1, -1, 100, 'tax'));
      h.phase = 'debt';
      h.resign(1);
      expect(h.phase, isNot('debt'));
      expect(h.waitingFor, [0]);

      final t = _game(3);
      t.phase = 'end';
      t.owner[1] = 0;
      t.owner[3] = 1;
      t.handle(0, {'t': 'trade', 'to': 1, 'give': [1], 'get': [3], 'giveCash': 0, 'getCash': 0});
      t.resign(1);
      expect(t.phase, 'end');
      expect(t.trade, isNull);
      expect(t.waitingFor, [0]);
    });

    test('bot() does not change state at any level', () {
      for (final lvl in [0, 1, 2]) {
        final g = MonopolyGame(GameSetup(
          players: 3,
          options: monopolyGames.first.defaultOptions(),
          names: ['a', 'b', 'c'],
          bots: [true, true, true],
          rng: Random(9),
          botLevel: lvl,
        ))
          ..host = SimHost();
        g.start();
        for (var k = 0; k < 300 && !g.isOver; k++) {
          final w = g.waitingFor.first;
          final before = jsonEncode(g.view(-1));
          final a = g.runBot(w)!;
          expect(jsonEncode(g.view(-1)), before);
          g.handle(w, a);
        }
      }
    });
  });
}
