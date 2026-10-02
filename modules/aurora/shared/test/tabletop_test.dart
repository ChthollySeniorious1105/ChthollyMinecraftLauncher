import 'dart:math';

import 'package:aurora_shared/games/tabletop/defs.dart';
import 'package:aurora_shared/games/tabletop/liarsbar.dart';
import 'package:aurora_shared/games/tabletop/loveletter.dart';
import 'package:aurora_shared/games/tabletop/splendor.dart';
import 'package:aurora_shared/games/tabletop/yahtzee.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, [Map<String, dynamic> opts = const {}]) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      rng: Random(7),
    );

LoveLetter _ll(int n) {
  final e = LoveLetter(_setup(n))..host = SimHost();
  e.start();
  return e;
}

void main() {
  group('yahtzee scoring', () {
    test('categories', () {
      expect(yahtzeeScore('threes', [3, 3, 1, 3, 5]), 9);
      expect(yahtzeeScore('threeKind', [3, 3, 1, 3, 5]), 15);
      expect(yahtzeeScore('fourKind', [3, 3, 1, 3, 5]), 0);
      expect(yahtzeeScore('fourKind', [6, 6, 6, 6, 2]), 26);
      expect(yahtzeeScore('fullHouse', [2, 2, 5, 5, 5]), 25);
      expect(yahtzeeScore('fullHouse', [5, 5, 5, 5, 5]), 0);
      expect(yahtzeeScore('smallStraight', [1, 2, 3, 4, 6]), 30);
      expect(yahtzeeScore('smallStraight', [3, 4, 5, 6, 6]), 30);
      expect(yahtzeeScore('smallStraight', [1, 2, 3, 5, 6]), 0);
      expect(yahtzeeScore('largeStraight', [2, 3, 4, 5, 6]), 40);
      expect(yahtzeeScore('largeStraight', [1, 2, 3, 4, 6]), 0);
      expect(yahtzeeScore('yahtzee', [4, 4, 4, 4, 4]), 50);
      expect(yahtzeeScore('chance', [1, 2, 3, 4, 6]), 16);
    });
    test('upper bonus and joker', () {
      final c = YahtzeeCard();
      c.s['ones'] = 3;
      c.s['twos'] = 6;
      c.s['threes'] = 9;
      c.s['fours'] = 12;
      c.s['fives'] = 15;
      c.s['sixes'] = 18;
      expect(c.upper, 63);
      expect(c.upperBonus, 35);
      final j = YahtzeeCard()..s['yahtzee'] = 50;
      // matching upper box open -> forced
      expect(j.options([5, 5, 5, 5, 5]).keys, ['fives']);
      j.s['fives'] = 10;
      final o = j.options([5, 5, 5, 5, 5]);
      expect(o['largeStraight'], 40);
      expect(o['fullHouse'], 25);
      expect(o.containsKey('ones'), isFalse);
    });
    test('yahtzee bonus in game', () {
      final e = Yahtzee(_setup(1))..host = SimHost();
      e.start();
      e.cards[0].s['yahtzee'] = 50;
      e.rollsLeft = 2;
      e.dice = [6, 6, 6, 6, 6];
      e.handle(0, {'type': 'score', 'cat': 'sixes'});
      expect(e.cards[0].bonusYahtzees, 1);
      expect(e.cards[0].total, 50 + 30 + 100);
    });
  });

  group('splendor', () {
    test('card data', () {
      expect(splendorCards.where((c) => c.tier == 0).length, 40);
      expect(splendorCards.where((c) => c.tier == 1).length, 30);
      expect(splendorCards.where((c) => c.tier == 2).length, 20);
      for (var col = 0; col < 5; col++) {
        expect(splendorCards.where((c) => c.color == col).length, 18);
      }
    });
    test('affordability with bonus and gold', () {
      const card = SplendorCard(999, 1, 0, 2, [0, 0, 1, 4, 2]);
      expect(splendorCanAfford(card, [0, 0, 1, 4, 2, 0], [0, 0, 0, 0, 0]), isTrue);
      expect(splendorCanAfford(card, [0, 0, 0, 3, 2, 0], [0, 0, 0, 0, 0]), isFalse);
      expect(splendorCanAfford(card, [0, 0, 0, 3, 2, 2], [0, 0, 0, 0, 0]), isTrue);
      expect(splendorCanAfford(card, [0, 0, 0, 2, 0, 0], [0, 0, 1, 2, 2]), isTrue);
      expect(splendorPayment(card, [0, 0, 0, 3, 2, 2], [0, 0, 0, 0, 0]), [0, 0, 0, 3, 2, 2]);
    });
    test('take rules and token limit', () {
      final e = Splendor(_setup(2))..host = SimHost();
      e.start();
      final s = e.turn;
      expect(e.supply, [4, 4, 4, 4, 4, 5]);
      e.handle(s, {'type': 'take', 'colors': [0, 0]});
      expect(e.ps[s].tokens[0], 2);
      final o = e.turn;
      expect(() => e.handle(o, {'type': 'take', 'colors': [0, 0]}), throwsA(isA<GameError>()));
      expect(() => e.handle(o, {'type': 'take', 'colors': [1, 1, 2]}), throwsA(isA<GameError>()));
      e.handle(o, {'type': 'take', 'colors': [1, 2, 3]});
      e.ps[s].tokens.setAll(0, [2, 3, 3, 0, 0, 0]);
      e.handle(s, {'type': 'take', 'colors': [3, 4, 0]});
      expect(e.phase, 'return');
      e.handle(s, {'type': 'return', 'tokens': [1, 0, 0, 0, 0, 0]});
      expect(e.ps[s].tokenCount, 10);
      expect(e.turn, o);
    });
  });

  group('love letter', () {
    test('deck setup', () {
      final e = _ll(2);
      expect(e.faceUp.length, 3);
      expect(e.deck.length + e.faceUp.length + 1 + 3, 21); // 3 cards in hands (2 + drawn)
    });
    test('guard eliminates on correct guess', () {
      final e = _ll(3);
      final s = e.turn;
      final t = (s + 1) % 3;
      e.hands[s] = [1, 4];
      e.hands[t] = [7];
      expect(() => e.handle(s, {'type': 'play', 'card': 1, 'target': t, 'guess': 1}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'play', 'card': 1, 'target': t, 'guess': 7});
      expect(e.alive[t], isFalse);
    });
    test('baron: lower card out, private info only to participants', () {
      final e = _ll(3);
      final s = e.turn;
      final t = (s + 1) % 3;
      final o = (s + 2) % 3;
      e.hands[s] = [3, 8];
      e.hands[t] = [2];
      e.handle(s, {'type': 'play', 'card': 3, 'target': t});
      expect(e.alive[t], isFalse);
      expect((e.view(s)['priv'] as List).isNotEmpty, isTrue);
      expect((e.view(t)['priv'] as List).isNotEmpty, isTrue);
      expect((e.view(o)['priv'] as List), isEmpty);
      expect((e.view(o)['hand'] as List).length, lessThanOrEqualTo(2));
    });
    test('handmaid protects, prince on princess eliminates', () {
      final e = _ll(3);
      final s = e.turn;
      final t = (s + 1) % 3;
      e.hands[s] = [4, 2];
      e.handle(s, {'type': 'play', 'card': 4});
      expect(e.protectedS[s], isTrue);
      final s2 = e.turn;
      expect(s2, t);
      e.hands[s2] = [5, 1];
      expect(() => e.handle(s2, {'type': 'play', 'card': 5, 'target': s}), throwsA(isA<GameError>()));
      final o = (s + 2) % 3;
      e.hands[o] = [9];
      e.handle(s2, {'type': 'play', 'card': 5, 'target': o});
      expect(e.alive[o], isFalse);
    });
    test('countess forced with king', () {
      final e = _ll(2);
      final s = e.turn;
      e.hands[s] = [7, 8];
      expect(() => e.handle(s, {'type': 'play', 'card': 7, 'target': 1 - s}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'play', 'card': 8});
    });
    test('king swaps, chancellor returns cards to bottom', () {
      final e = _ll(2);
      final s = e.turn;
      e.hands[s] = [7, 2];
      e.hands[1 - s] = [6];
      e.handle(s, {'type': 'play', 'card': 7, 'target': 1 - s});
      expect(e.hands[s], [6]);
      expect(e.hands[1 - s].first, 2);
      final t = e.turn;
      e.hands[t] = [6, 0];
      final before = e.deck.length;
      e.handle(t, {'type': 'play', 'card': 6});
      expect(e.phase, 'chancellor');
      expect(e.hands[t].length, 3);
      final keep = e.hands[t][1];
      final rest = List.of(e.hands[t])..remove(keep);
      e.handle(t, {'type': 'keep', 'card': keep, 'bottom': rest});
      expect(e.deck.length, before - 1); // -2 drawn +2 returned, -1 drawn by next player
      expect(e.hands[t], [keep]);
    });
    test('spy bonus token', () {
      final e = _ll(3);
      final s = e.turn;
      e.deck = []; // deck empties -> round ends after this play
      e.hands[s] = [0, 9];
      e.hands[(s + 1) % 3] = [2];
      e.hands[(s + 2) % 3] = [4];
      e.handle(s, {'type': 'play', 'card': 0});
      expect(e.tokens[s], 2); // round win + spy
      expect(e.roundResult!['spy'], s);
    });
  });

  group('liars bar', () {
    test('views hide hands and dice', () {
      final e = LiarsBar(_setup(3, {'mode': 'deck'}))..host = SimHost();
      e.start();
      expect((e.view(0)['hand'] as List).length, 5);
      expect(e.view(0).toString().contains(e.hands[1].join(', ')), isFalse);
      final d = LiarsBar(_setup(3, {'mode': 'dice', 'wild': true}))..host = SimHost();
      d.start();
      expect((d.view(1)['dice'] as List).length, 5);
      expect(d.view(-1)['dice'], isEmpty);
    });
    test('challenge a liar: liar pulls trigger', () {
      final e = LiarsBar(_setup(2, {'mode': 'deck'}))..host = SimHost();
      e.start();
      final s = e.turn;
      e.hands[s] = [e.tableCard == 'Q' ? 'K' : 'Q', 'J'];
      e.bullet[s] = 5;
      e.handle(s, {'type': 'play', 'cards': [0]});
      e.handle(1 - s, {'type': 'challenge'});
      expect(e.shots[s], 1);
      expect(e.shots[1 - s], 0);
    });
    test('classic dice loses a die', () {
      final e = LiarsBar(_setup(2, {'mode': 'classic', 'wild': false}))..host = SimHost();
      e.start();
      final s = e.turn;
      e.dice[0] = [2, 2, 3, 4, 5];
      e.dice[1] = [6, 6, 6, 6, 6];
      e.handle(s, {'type': 'bid', 'qty': 3, 'face': 2});
      e.handle(1 - s, {'type': 'challenge'});
      expect(e.diceCount[s], 4);
    });
  });

  group('placings & resign', () {
    test('rules present for every def', () {
      for (final d in tabletopGames) {
        expect(d.rules.length, greaterThan(300), reason: d.id);
        expect(d.undo, isFalse);
      }
    });

    test('love letter placings by tokens, winner first', () {
      final e = _ll(3);
      expect(e.placings, isNull);
      final s = e.turn;
      e.tokens[s] = 4;
      e.tokens[(s + 1) % 3] = 2;
      e.deck = [];
      e.hands[s] = [9, 8];
      e.hands[(s + 1) % 3] = [1];
      e.hands[(s + 2) % 3] = [2];
      e.handle(s, {'type': 'play', 'card': 8});
      expect(e.isOver, isTrue);
      final r = e.placings!;
      expect(r[s], 1);
      expect(r[(s + 1) % 3], 2);
      expect(r[(s + 2) % 3], 3);
    });

    test('love letter resign: 3p continues, then last one wins', () {
      final e = _ll(3);
      final s = e.turn;
      e.resign(s);
      expect(e.isOver, isFalse);
      expect(e.alive[s], isFalse);
      expect(e.turn, isNot(s));
      expect(e.waitingFor, [e.turn]);
      final o = e.turn;
      e.resign(o);
      expect(e.isOver, isTrue);
      final w = [0, 1, 2].firstWhere((x) => x != s && x != o);
      final r = e.placings!;
      expect(r[w], 1);
      expect(r[o], 2); // resigned later ranks better
      expect(r[s], 3);
      expect(() => e.resign(w), throwsA(isA<GameError>()));
    });

    test('love letter resigned seat sits out later rounds', () {
      final e = _ll(3);
      final s = (e.turn + 1) % 3;
      e.resign(s);
      final r0 = e.roundNo;
      var guard = 0;
      while (!e.isOver && e.roundNo < r0 + 2 && guard++ < 400) {
        if (e.waitingFor.isEmpty) {
          (e.host as SimHost).runPending();
          continue;
        }
        final t = e.waitingFor.first;
        expect(t, isNot(s));
        e.handle(t, e.runBot(t)!);
      }
      if (!e.isOver) {
        expect(e.roundNo, greaterThan(r0));
        expect(e.alive[s], isFalse);
        expect(e.hands[s], isEmpty);
      }
    });

    test('yahtzee placings and resign', () {
      final e = Yahtzee(_setup(3))..host = SimHost();
      e.start();
      expect(e.placings, isNull);
      e.resign(0);
      expect(e.turn, 1);
      expect(e.isOver, isFalse);
      e.handle(1, {'type': 'roll'});
      e.handle(1, {'type': 'score', 'cat': 'chance'});
      expect(e.turn, 2);
      e.handle(2, {'type': 'roll'});
      e.handle(2, {'type': 'score', 'cat': 'chance'});
      expect(e.turn, 1); // resigned seat 0 skipped
      e.resign(2);
      expect(e.isOver, isTrue);
      expect(e.placings, [3, 1, 2]);
    });

    test('yahtzee full game placings by score', () {
      final e = Yahtzee(_setup(2))..host = SimHost();
      e.start();
      while (!e.isOver) {
        final t = e.turn;
        e.handle(t, e.runBot(t)!);
      }
      final a = e.cards[0].total, b = e.cards[1].total;
      expect(e.placings, a == b ? [1, 1] : (a > b ? [1, 2] : [2, 1]));
    });

    test('yahtzee solo resign ends game', () {
      final e = Yahtzee(_setup(1))..host = SimHost();
      e.start();
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [1]);
    });

    test('splendor placings and resign', () {
      final e = Splendor(_setup(3))..host = SimHost();
      e.start();
      expect(e.placings, isNull);
      final s = e.turn;
      e.handle(s, {'type': 'take', 'colors': [0, 1, 2]});
      e.resign(s);
      expect(e.supply, [5, 5, 5, 5, 5, 5]); // gems returned
      final t = e.turn;
      e.handle(t, {'type': 'take', 'colors': [0, 1, 2]});
      expect(e.turn, isNot(s));
      e.resign(e.turn);
      expect(e.isOver, isTrue);
      final r = e.placings!;
      expect(r[t], 1);
      expect(r[s], 3);
      expect(e.winners, [t]);
    });

    test('splendor 2p resign: opponent wins', () {
      final e = Splendor(_setup(2))..host = SimHost();
      e.start();
      final s = e.turn;
      e.resign(1 - s);
      expect(e.isOver, isTrue);
      expect(e.placings![s], 1);
      expect(e.placings![1 - s], 2);
    });

    test('liars bar placings follow elimination order', () {
      final e = LiarsBar(_setup(3, {'mode': 'classic', 'wild': false}))..host = SimHost();
      e.start();
      expect(e.placings, isNull);
      e.diceCount.setAll(0, [1, 1, 1]);
      e.dice[0] = [3];
      e.dice[1] = [3];
      e.dice[2] = [3];
      final s = e.turn;
      e.handle(s, {'type': 'bid', 'qty': 1, 'face': 3});
      final c = e.turn;
      e.handle(c, {'type': 'challenge'});
      expect(e.alive[c], isFalse);
      e.resign(e.aliveSeats.firstWhere((x) => x != s));
      expect(e.isOver, isTrue);
      final r = e.placings!;
      expect(r[s], 1);
      expect(r[c], 3);
    });

    test('liars bar resign mid-round restarts round', () {
      final e = LiarsBar(_setup(3, {'mode': 'deck'}))..host = SimHost();
      e.start();
      final s = e.turn;
      e.handle(s, {'type': 'play', 'cards': [0]});
      final round = e.roundNo;
      e.resign(e.turn);
      expect(e.isOver, isFalse);
      expect(e.roundNo, round + 1);
      expect(e.waitingFor.length, 1);
      expect(e.alive.where((a) => a).length, 2);
      e.resign(e.turn);
      expect(e.isOver, isTrue);
      expect(e.placings!.where((p) => p == 1).length, 1);
    });
  });

  test('tabletop games: bots finish every variant', () {
    expect(runSims(tabletopGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
