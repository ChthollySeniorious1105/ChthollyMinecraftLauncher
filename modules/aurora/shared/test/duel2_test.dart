import 'dart:math';

import 'package:aurora_shared/games/duel2/banqi.dart';
import 'package:aurora_shared/games/duel2/defs.dart';
import 'package:aurora_shared/games/duel2/jaipur.dart';
import 'package:aurora_shared/games/duel2/lostcities.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup([Map<String, dynamic> opts = const {}, int seed = 3]) => GameSetup(
      players: 2,
      options: opts,
      names: const ['P0', 'P1'],
      bots: const [false, false],
      rng: Random(seed),
    );

T _start<T extends GameEngine>(T e) {
  e.host = SimHost();
  e.start();
  return e;
}

void main() {
  group('jaipur', () {
    test('setup', () {
      final e = _start(Jaipur(_setup()));
      expect(e.market.length, 5);
      expect(e.market.where((c) => c == jpCamel).length, greaterThanOrEqualTo(3));
      for (var s = 0; s < 2; s++) {
        expect(e.hand[s].length + e.herd[s], 5);
      }
      final total = e.deck.length + 5 + 10;
      expect(total, 44 + 11); // 44 goods + 11 camels = 55 cards
    });

    test('sell takes tokens in order and bonus for 3', () {
      final e = _start(Jaipur(_setup()));
      final s = e.turn;
      e.hand[s]
        ..clear()
        ..addAll([3, 3, 3]);
      e.handle(s, {'type': 'sell', 'good': 3, 'count': 3});
      expect(e.goodsTaken[s], [5, 3, 3]);
      expect(e.bonusTaken[s].length, 1);
      expect(e.tokens[3], [2, 2, 1, 1]);
      expect(e.turn, 1 - s);
    });

    test('precious goods need at least 2', () {
      final e = _start(Jaipur(_setup()));
      final s = e.turn;
      e.hand[s]
        ..clear()
        ..addAll([0, 4]);
      expect(() => e.handle(s, {'type': 'sell', 'good': 0, 'count': 1}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'sell', 'good': 4, 'count': 1});
    });

    test('exchange rules', () {
      final e = _start(Jaipur(_setup()));
      final s = e.turn;
      e.market = [0, 1, 2, jpCamel, jpCamel];
      e.hand[s]
        ..clear()
        ..addAll([0, 5]);
      e.herd[s] = 2;
      // cannot take camels
      expect(() => e.handle(s, {'type': 'exchange', 'market': [3, 4], 'hand': [1], 'camels': 1}), throwsA(isA<GameError>()));
      // cannot swap same type
      expect(() => e.handle(s, {'type': 'exchange', 'market': [0, 1], 'hand': [0, 1], 'camels': 0}), throwsA(isA<GameError>()));
      // single card exchange illegal
      expect(() => e.handle(s, {'type': 'exchange', 'market': [1], 'hand': [1], 'camels': 0}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'exchange', 'market': [1, 2], 'hand': [1], 'camels': 1});
      expect(e.hand[s], [0, 1, 2]);
      expect(e.herd[s], 1);
      expect(e.market.where((c) => c == jpCamel).length, 3);
    });

    test('hand limit and camels', () {
      final e = _start(Jaipur(_setup()));
      final s = e.turn;
      e.market = [0, 1, jpCamel, jpCamel, jpCamel];
      e.hand[s]
        ..clear()
        ..addAll([5, 5, 5, 5, 5, 5, 5]);
      expect(() => e.handle(s, {'type': 'take', 'idx': 0}), throwsA(isA<GameError>()));
      final h0 = e.herd[s];
      e.handle(s, {'type': 'camels'});
      expect(e.herd[s], h0 + 3);
      expect(e.market.length, 5);
    });

    test('round ends when three piles empty, camel bonus, best of 3', () {
      final e = _start(Jaipur(_setup()));
      final s = e.turn;
      e.tokens[0].clear();
      e.tokens[1].clear();
      e.tokens[2] = [5];
      e.hand[s]
        ..clear()
        ..addAll([2, 2]);
      e.herd[s] = 3;
      e.herd[1 - s] = 1;
      e.handle(s, {'type': 'sell', 'good': 2, 'count': 2});
      expect(e.phase, 'roundEnd');
      final rows = e.roundResult!['rows'] as List;
      expect((rows[s] as Map)['camel'], 5);
      expect(e.seals[s], 1);
      // opponent bonus hidden during play only
      e.handle(0, {'type': 'continue'});
      e.handle(1, {'type': 'continue'});
      expect(e.phase, 'play');
      expect(e.round, 2);
      expect(e.view(s)['bonusValues'], isA<List>());
    });

    test('hidden info in view', () {
      final e = _start(Jaipur(_setup()));
      expect(e.view(0)['hand'], isNotNull);
      expect(e.view(-1)['hand'], isNull);
      e.bonusTaken[1].add(9);
      expect((e.view(0)['bonusValues'] as List)[1], isNull);
      expect((e.view(1)['bonusValues'] as List)[1], [9]);
    });

    test('resign', () {
      final e = _start(Jaipur(_setup()));
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
    });
  });

  group('lostcities', () {
    test('scoring', () {
      expect(lcScore([]), 0);
      expect(lcScore([0, 3, 4]), (2 + 3 - 20) * 2); // invest + 2 + 3
      expect(lcScore([3, 4, 5, 6, 7, 8, 9, 10]), (2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 - 20) + 20);
      expect(lcScore([0, 1, 11]), (10 - 20) * 3);
    });

    test('ascending order and investments first', () {
      final e = _start(LostCities(_setup()));
      final s = e.turn;
      e.hand[s]
        ..clear()
        ..addAll([0, 1, 5, 4, 12, 13, 14, 15]);
      e.handle(s, {'type': 'play', 'card': 5}); // yellow 4
      e.handle(s, {'type': 'draw', 'from': -1});
      final o = 1 - s;
      e.handle(o, {'type': 'discard', 'card': e.hand[o].first});
      e.handle(o, {'type': 'draw', 'from': -1});
      expect(e.canPlay(s, 4), isFalse); // yellow 3 < 4
      expect(e.canPlay(s, 0), isFalse); // investment after number
      expect(() => e.handle(s, {'type': 'play', 'card': 0}), throwsA(isA<GameError>()));
    });

    test('cannot draw back the card just discarded', () {
      final e = _start(LostCities(_setup()));
      final s = e.turn;
      final c = e.hand[s].first;
      e.handle(s, {'type': 'discard', 'card': c});
      expect(() => e.handle(s, {'type': 'draw', 'from': lcColor(c)}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'draw', 'from': -1});
      expect(e.hand[s].length, 8);
    });

    test('round ends when deck runs out', () {
      final e = _start(LostCities(_setup()));
      e.deck = [e.deck.first];
      final s = e.turn;
      e.handle(s, {'type': 'discard', 'card': e.hand[s].first});
      e.handle(s, {'type': 'draw', 'from': -1});
      expect(e.isOver, isTrue);
      expect(e.placings, isNotNull);
    });

    test('opponent hand hidden', () {
      final e = _start(LostCities(_setup()));
      expect(e.view(-1)['hand'], isNull);
      expect(e.view(0)['hand'], e.hand[0]);
    });
  });

  group('banqi', () {
    Banqi fresh() {
      final e = _start(Banqi(_setup()));
      e.pos.board.fillRange(0, 32, 0);
      e.pos.hidden.fillRange(0, 32, false);
      e.color0 = 1; // seat0 red
      e.turn = 0;
      return e;
    }

    test('rank captures and pawn/general exception', () {
      expect(bqCanTake(1, -2), isTrue);
      expect(bqCanTake(1, -7), isFalse);
      expect(bqCanTake(7, -1), isTrue);
      expect(bqCanTake(7, -2), isFalse);
      expect(bqCanTake(5, -4), isTrue); // 车 > 马
      expect(bqCanTake(4, -5), isFalse);
      expect(bqCanTake(2, -2), isTrue);
    });

    test('cannon jumps exactly one screen, any distance', () {
      final e = fresh();
      e.pos.board[0] = 6; // red cannon a1
      e.pos.board[2] = 99; // hidden screen
      e.pos.hidden[2] = true;
      e.pos.board[6] = -1; // black general far right
      e.pos.board[1 + 8] = -7; // adjacent below? (b2) not adjacent to a1
      e.pos.board[8] = -7; // a2 adjacent: cannon can't capture adjacent
      final ms = e.pos.moves(1);
      expect(ms.contains(0 * 32 + 6), isTrue);
      expect(ms.contains(0 * 32 + 8), isFalse);
      e.handle(0, {'type': 'move', 'from': 0, 'to': 6});
      expect(e.pos.board[6], 6);
    });

    test('first flip decides colour; game ends when pieces gone', () {
      final e = _start(Banqi(_setup()));
      final s = e.turn;
      final sq = 5;
      final p = e.pos.board[sq];
      e.handle(s, {'type': 'flip', 'sq': sq});
      expect(e.colorOf(s), p > 0 ? 1 : -1);
      // hidden pieces are masked in the view
      expect((e.view(1 - s)['board'] as List).where((x) => x == 99).length, 31);
    });

    test('win by capturing last piece', () {
      final e = fresh();
      e.pos.board[0] = 5; // red chariot
      e.pos.board[1] = -4; // black horse
      e.handle(0, {'type': 'move', 'from': 0, 'to': 1});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2]);
    });

    test('no legal move loses', () {
      final e = fresh();
      e.pos.board[0] = -7; // black pawn cornered
      e.pos.board[1] = 2;
      e.pos.board[8] = 2;
      e.pos.board[31] = 5;
      e.turn = 0;
      e.handle(0, {'type': 'move', 'from': 31, 'to': 30});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2]);
    });

    test('draw after quiet moves', () {
      final e = _start(Banqi(_setup({'drawRule': 30})));
      e.pos.board.fillRange(0, 32, 0);
      e.pos.hidden.fillRange(0, 32, false);
      e.color0 = 1;
      e.turn = 0;
      e.pos.board[0] = 5;
      e.pos.board[31] = -5;
      for (var i = 0; i < 30; i++) {
        final s = e.turn;
        if (s == 0) {
          e.handle(0, {'type': 'move', 'from': e.pos.board[0] != 0 ? 0 : 1, 'to': e.pos.board[0] != 0 ? 1 : 0});
        } else {
          e.handle(1, {'type': 'move', 'from': e.pos.board[31] != 0 ? 31 : 30, 'to': e.pos.board[31] != 0 ? 30 : 31});
        }
      }
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1]);
    });
  });

  test('bot simulations', () {
    expect(runSims(duel2Games, n: 30), 0);
  });
}
