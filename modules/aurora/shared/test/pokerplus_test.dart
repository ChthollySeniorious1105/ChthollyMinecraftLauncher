import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/pokerplus/blackjack.dart';
import 'package:aurora_shared/games/pokerplus/cards.dart';
import 'package:aurora_shared/games/pokerplus/defs.dart';
import 'package:aurora_shared/games/pokerplus/holdem.dart';
import 'package:aurora_shared/games/pokerplus/paodekuai.dart';
import 'package:aurora_shared/games/pokerplus/pdk_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int ev(String s) => evalCodes(s.split(' '));
List<int> rk(String s) => [for (final c in s.split(' ')) pdkRank('${c}S')];

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

void main() {
  group('hold\'em evaluator', () {
    test('categories', () {
      expect(handName(ev('AS KS QS JS TS 2D 3C')), '皇家同花顺');
      expect(handName(ev('9S 8S 7S 6S 5S AD AC')), '同花顺');
      expect(handName(ev('9S 9H 9D 9C 5S AD AC')), '四条');
      expect(handName(ev('9S 9H 9D 5C 5S AD 2C')), '葫芦');
      expect(handName(ev('2S 7S 9S JS KS AD AC')), '同花');
      expect(handName(ev('5S 6H 7D 8C 9S AD AC')), '顺子');
      expect(handName(ev('9S 9H 9D 2C 5S AD KC')), '三条');
      expect(handName(ev('9S 9H 5D 5C 2S AD KC')), '两对');
      expect(handName(ev('9S 9H 5D 4C 2S AD KC')), '一对');
      expect(handName(ev('9S 7H 5D 4C 2S AD KC')), '高牌');
    });
    test('wheel is the lowest straight', () {
      final wheel = ev('AS 2H 3D 4C 5S KD KC');
      expect(handName(wheel), '顺子');
      expect(wheel < ev('2S 3H 4D 5C 6S KD QC'), isTrue);
      expect(handName(ev('AS 2S 3S 4S 5S KD KC')), '同花顺');
      expect(ev('AS 2S 3S 4S 5S') < ev('2S 3S 4S 5S 6S'), isTrue);
    });
    test('kickers and ties', () {
      // pair of aces, K kicker beats Q kicker
      expect(ev('AS AH KD 7C 4S 3D 2C') > ev('AD AC QD 7H 4S 3D 2C'), isTrue);
      // board plays: tie
      expect(ev('2S 3H AS KS QS JS TS'), ev('4D 5C AS KS QS JS TS'));
      // two pair: third kicker decides
      expect(ev('KS KH 8D 8C AS 3D 2C') > ev('KD KC 8S 8H QS 3D 2C'), isTrue);
      // full house: trips first
      expect(ev('9S 9H 9D 2C 2S') > ev('8S 8H 8D AC AS'), isTrue);
      // two trips makes a full house with the higher trips
      expect(ev('9S 9H 9D 8C 8S 8D 2C'), ev('9S 9H 9D 8C 8S 3D 2C'));
      // sixth card irrelevant
      expect(ev('AS AH KD QC JS 3D 2C'), ev('AD AC KS QD JH 4D 3C'));
    });
    test('bestFive', () {
      final b = bestFive('AS KS QS JS TS 2D 3C'.split(' '));
      expect(b.toSet(), {'AS', 'KS', 'QS', 'JS', 'TS'});
    });
  });

  group('hold\'em pots', () {
    test('side pots', () {
      // A all-in 100, B all-in 300, C and D 500
      final pots = buildPots([100, 300, 500, 500], [false, false, false, false]);
      expect(pots.length, 3);
      expect(pots[0].amount, 400);
      expect(pots[0].eligible, [0, 1, 2, 3]);
      expect(pots[1].amount, 600);
      expect(pots[1].eligible, [1, 2, 3]);
      expect(pots[2].amount, 400);
      expect(pots[2].eligible, [2, 3]);
    });
    test('folded chips stay in pot', () {
      final pots = buildPots([50, 200, 200], [true, false, false]);
      expect(pots.length, 1);
      expect(pots[0].amount, 450);
      expect(pots[0].eligible, [1, 2]);
    });
    test('odd chip goes left of button', () {
      final s = splitPot(101, [0, 2], 1, 4);
      expect(s[2], 51);
      expect(s[0], 50);
    });
    test('heads-up: dealer posts small blind and acts first preflop', () {
      final g = TexasHoldem(_setup(2, pokerplusGames[0].defaultOptions()))..start();
      expect(g.sbSeat, g.dealer);
      expect(g.turn, g.dealer);
      final v = g.view(g.turn)['me'] as Map;
      expect(v['toCall'], 10);
      expect(v['minTo'], 40);
    });
    test('raise rules and uncalled bet returned', () {
      final g = TexasHoldem(_setup(3, pokerplusGames[0].defaultOptions()))..start();
      final utg = g.turn;
      expect(() => g.handle(utg, {'type': 'raise', 'to': 30}), throwsA(isA<GameError>()));
      g.handle(utg, {'type': 'raise', 'to': 60});
      final n1 = g.turn;
      g.handle(n1, {'type': 'fold'});
      final n2 = g.turn;
      g.handle(n2, {'type': 'fold'});
      expect(g.phase, 'handEnd');
      expect(g.stacks[utg], 1000 + 10 + 20);
      expect(g.stacks.reduce((a, b) => a + b), 3000);
    });
  });

  group('blackjack', () {
    test('soft totals', () {
      expect(bjTotal(['AS', '6H']), (17, true));
      expect(bjTotal(['AS', '6H', 'TD']), (17, false));
      expect(bjTotal(['AS', 'AH']), (12, true));
      expect(bjTotal(['AS', 'AH', '9D']), (21, true));
      expect(bjTotal(['KS', 'QH', '5D']), (25, false));
      expect(isBlackjack(['AS', 'KH']), isTrue);
      expect(isBlackjack(['AS', '5H', '5D']), isFalse);
    });
    test('payouts', () {
      expect(settleHand(BjHand(['AS', 'KH'], 100), ['9S', '8H']), ('bj', 250));
      expect(settleHand(BjHand(['AS', 'KH'], 100), ['AD', 'QH']), ('push', 100));
      expect(settleHand(BjHand(['TS', 'KH'], 100), ['AD', 'QH']), ('lose', 0));
      expect(settleHand(BjHand(['TS', 'KH'], 100), ['9D', '5H', 'QC']), ('win', 200));
      expect(settleHand(BjHand(['TS', '7H'], 100), ['9D', '8H']), ('push', 100));
      expect(settleHand(BjHand(['TS', '6H', '8C'], 100), ['9D', '5H', 'QC']), ('bust', 0));
      // split 21 is not a blackjack
      expect(settleHand(BjHand(['AS', 'KH'], 100, fromSplit: true), ['9S', '8H']), ('win', 200));
    });
    test('basic strategy', () {
      expect(basicStrategy(['8S', '8H'], 'TD', ['hit', 'stand', 'double', 'split']), 'split');
      expect(basicStrategy(['6S', '5H'], '6D', ['hit', 'stand', 'double']), 'double');
      expect(basicStrategy(['TS', '6H'], '7D', ['hit', 'stand']), 'hit');
      expect(basicStrategy(['TS', '3H'], '4D', ['hit', 'stand']), 'stand');
      expect(basicStrategy(['AS', '7H'], '9D', ['hit', 'stand']), 'hit');
    });
  });

  group('paodekuai', () {
    test('combos', () {
      expect(pdkParse(rk('3'))!.type, 'single');
      expect(pdkParse(rk('5 5'))!.type, 'pair');
      expect(pdkParse(rk('5 5 6 6'))!.type, 'pairs');
      expect(pdkParse(rk('5 6 7 8 9'))!.type, 'straight');
      expect(pdkParse(rk('T J Q K A'))!.type, 'straight');
      expect(pdkParse(rk('J Q K A 2')), isNull); // 2 can't be in a straight
      expect(pdkParse(rk('5 6 7 8')), isNull);
      expect(pdkParse(rk('9 9 9 3 4'))!.label, '三带二');
      expect(pdkParse(rk('9 9 9 3')), isNull);
      expect(pdkParse(rk('9 9 9 3'), isAll: true)!.label, '三带一');
      expect(pdkParse(rk('9 9 9 T T T 3 4 5 6'))!.type, 'plane');
      expect(pdkParse(rk('7 7 7 7'))!.type, 'bomb');
      final bomb = pdkParse(rk('3 3 3 3'))!;
      expect(bomb.beats(pdkParse(rk('T J Q K A'))!), isTrue);
      expect(pdkParse(rk('6 7 8 9 T'))!.beats(pdkParse(rk('5 6 7 8 9'))!), isTrue);
      expect(pdkParse(rk('6 7 8 9 T J'))!.beats(pdkParse(rk('5 6 7 8 9'))!), isFalse);
    });
    test('deck', () {
      expect(pdkDeck(16).length, 48);
      expect(pdkDeck(15).length, 45);
      expect(pdkDeck(16).contains('3S'), isTrue);
    });
    Paodekuai game(bool must) {
      final g = Paodekuai(_setup(3, {'cards': 16, 'must': must, 'rounds': 5}))..start();
      g.hands = [
        ['3S', '4H', '9D', 'KD'],
        ['5H', '6D', 'QC', 'KC'],
        ['7H', '8C', '8D', 'JS'],
      ];
      g.turn = 0;
      g.firstPlay = true;
      return g;
    }

    test('♠3 leads first', () {
      final g = game(true);
      expect(() => g.handle(0, {'type': 'play', 'cards': ['4H']}), throwsA(isA<GameError>()));
      g.handle(0, {'type': 'play', 'cards': ['3S']});
      expect(g.turn, 1);
    });
    test('必须管', () {
      final g = game(true);
      g.handle(0, {'type': 'play', 'cards': ['3S']});
      expect(() => g.handle(1, {'type': 'pass'}), throwsA(isA<GameError>()));
      final g2 = game(false);
      g2.handle(0, {'type': 'play', 'cards': ['3S']});
      g2.handle(1, {'type': 'pass'});
      expect(g2.turn, 2);
    });
    test('报单 forces max single', () {
      final g = game(false);
      g.hands[1] = ['5H'];
      g.firstPlay = false;
      g.turn = 0;
      expect(() => g.handle(0, {'type': 'play', 'cards': ['4H']}), throwsA(isA<GameError>()));
      g.handle(0, {'type': 'play', 'cards': ['KD']});
    });
    test('scoring with 关门', () {
      final g = game(true);
      g.hands = [
        ['3S'],
        ['5H', '6D', 'QC', 'KC'],
        List.generate(16, (i) => 'x'),
      ];
      g.hands[2] = ['4C', '5C', '6C', '7C', '8C', '9C', 'TC', 'JC', 'QD', 'KH', '4D', '5D', '6H', '7H', '8H', '9H'];
      g.playedCount = [15, 12, 0];
      g.handle(0, {'type': 'play', 'cards': ['3S']});
      final d = (g.result!['delta'] as List).cast<int>();
      expect(d[1], -4);
      expect(d[2], -32);
      expect(d[0], 36);
    });
  });

  group('v3', () {
    test('holdem placings: survivors by chips, busted by elimination order', () {
      final g = TexasHoldem(_setup(4, pokerplusGames[0].defaultOptions()))..start();
      expect(g.placings, isNull);
      g.out = [false, true, false, true];
      g.bustHand = [0, 3, 0, 7];
      g.stacks = [1500, 0, 2500, 0];
      g.phase = 'over';
      expect(g.placings, [2, 4, 1, 3]);
      g.stacks = [2000, 0, 2000, 0];
      g.bustHand = [0, 5, 0, 5];
      expect(g.placings, [1, 3, 1, 3]);
    });
    test('holdem resign heads-up', () {
      final g = TexasHoldem(_setup(2, pokerplusGames[0].defaultOptions()))..start();
      expect(g.canResign, isTrue);
      g.resign(1);
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 2]);
      expect(g.waitingFor, isEmpty);
      expect(g.canResign, isFalse);
      final g3 = TexasHoldem(_setup(3, pokerplusGames[0].defaultOptions()))..start();
      expect(g3.canResign, isFalse);
      expect(() => g3.resign(0), throwsA(isA<GameError>()));
    });
    test('blackjack placings by chips', () {
      final g = Blackjack(_setup(3, pokerplusGames[1].defaultOptions()))..start();
      expect(g.placings, isNull);
      expect(g.canResign, isFalse);
      g.chips = [800, 1200, 800];
      g.phase = 'over';
      expect(g.placings, [2, 1, 2]);
    });
    test('paodekuai placings by score', () {
      final g = Paodekuai(_setup(3, pokerplusGames[2].defaultOptions()))..start();
      expect(g.placings, isNull);
      g.scores = [-10, 30, -20];
      g.phase = 'over';
      expect(g.placings, [2, 1, 3]);
    });
    test('pdkTurns', () {
      expect(pdkTurns(rk('3 4 5 6 7')), 1);
      expect(pdkTurns(rk('3 3 4 4')), 1);
      expect(pdkTurns(rk('9 9 9 3 4')), 1);
      expect(pdkTurns(rk('3 5 7')), 3);
    });
    test('bots do not mutate state at every level', () {
      for (final def in pokerplusGames) {
        for (final lvl in [0, 1, 2]) {
          final n = def.id == 'paodekuai' ? 3 : 2;
          final setup = GameSetup(
            players: n,
            options: def.defaultOptions(),
            names: [for (var i = 0; i < n; i++) 'P$i'],
            bots: List.filled(n, true),
            rng: Random(3),
            botLevel: lvl,
          );
          final g = def.create(setup)..start();
          for (var step = 0; step < 40 && !g.isOver; step++) {
            final w = g.waitingFor;
            if (w.isEmpty) break;
            final before = [for (var s = -1; s < n; s++) jsonEncode(g.view(s))];
            final a = g.runBot(w.first);
            expect([for (var s = -1; s < n; s++) jsonEncode(g.view(s))], before);
            if (a == null) break;
            g.handle(w.first, a);
          }
        }
      }
    });
  });

  test('simulations', () {
    expect(runSims(pokerplusGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
