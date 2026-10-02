import 'dart:math';

import 'package:aurora_shared/games/euro2/azul.dart';
import 'package:aurora_shared/games/euro2/defs.dart';
import 'package:aurora_shared/games/euro2/duel.dart';
import 'package:aurora_shared/games/euro2/duel_data.dart';
import 'package:aurora_shared/games/euro2/kingdomino.dart';
import 'package:aurora_shared/games/euro2/patchwork.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, [Map<String, dynamic> opts = const {}, int seed = 3]) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      rng: Random(seed),
    );

T _start<T extends GameEngine>(T e) {
  e.host = SimHost();
  e.start();
  return e;
}

int _card(String name) => duelCards.indexWhere((c) => c.name == name);

void main() {
  group('azul', () {
    test('adjacency scoring', () {
      final w = List.generate(5, (_) => List.filled(5, -1));
      w[0][0] = 0;
      expect(Azul.adjacency(w, 0, 0), 1);
      w[0][1] = 1;
      expect(Azul.adjacency(w, 0, 1), 2);
      w[1][1] = 0;
      expect(Azul.adjacency(w, 1, 1), 2); // vertical pair only
      w[1][0] = 4;
      expect(Azul.adjacency(w, 1, 0), 4); // 2 horizontal + 2 vertical
    });

    test('take, overflow to floor, first-player token', () {
      final e = _start(Azul(_setup(2)));
      final s = e.turn;
      e.factories[0] = [2, 2, 2, 3];
      e.handle(s, {'type': 'take', 'src': 0, 'color': 2, 'line': 1});
      expect(e.lineCount[s][1], 2);
      expect(e.floor[s], [2]); // 3 tiles, line holds 2
      expect(e.center.contains(3), isTrue);
      final o = 1 - s;
      expect(() => e.handle(o, {'type': 'take', 'src': 0, 'color': 2, 'line': 0}), throwsA(isA<GameError>()));
      e.handle(o, {'type': 'take', 'src': -1, 'color': 3, 'line': 0});
      expect(e.floor[o].first, Azul.tokenCode);
      expect(e.firstNext, o);
    });

    test('wall colour already in row blocks the pattern line', () {
      final e = _start(Azul(_setup(2)));
      final s = e.turn;
      e.wall[s][0][2] = 2;
      e.factories[0] = [2, 1, 1, 1];
      expect(() => e.handle(s, {'type': 'take', 'src': 0, 'color': 2, 'line': 0}), throwsA(isA<GameError>()));
    });

    test('round end tiles the wall and scores floor penalties', () {
      final e = _start(Azul(_setup(2)));
      for (var f = 0; f < e.factories.length; f++) {
        e.factories[f] = [];
      }
      e.center = [1, 1, 1];
      e.tokenInCenter = true;
      e.turn = 0;
      e.handle(0, {'type': 'take', 'src': -1, 'color': 1, 'line': 0}); // 1 fits, 2 overflow + token
      expect(e.round, 2);
      expect(e.wall[0][0][1], 1);
      expect(e.score[0], 0); // 1 point - (1+1+2) floored at 0
      expect(e.firstNext, 0);
    });

    test('end bonuses', () {
      final e = _start(Azul(_setup(2)));
      for (var c = 0; c < 5; c++) {
        e.wall[0][0][c] = Azul.wallColor(0, c);
      }
      for (var r = 0; r < 5; r++) {
        e.wall[0][r][0] = Azul.wallColor(r, 0);
      }
      expect(e.completeRows(0), 1);
      expect(e.completeCols(0), 1);
    });

    test('grey wall asks for a column', () {
      final e = _start(Azul(_setup(2, {'wall': 'grey'})));
      e.lineColor[0][0] = 3;
      e.lineCount[0][0] = 1;
      for (var f = 0; f < e.factories.length; f++) {
        e.factories[f] = [];
      }
      e.center = [4];
      e.tokenInCenter = false;
      e.turn = 1;
      e.handle(1, {'type': 'take', 'src': -1, 'color': 4, 'line': -1});
      expect(e.phase, 'tile');
      expect(e.waitingFor, [0]);
      e.handle(0, {'type': 'tile', 'col': 3});
      expect(e.wall[0][0][3], 3);
    });
  });

  group('kingdomino', () {
    test('domino catalogue', () {
      expect(kdDominoes.length, 48);
      expect(kdDominoes.fold(0, (s, d) => s + d.$2 + d.$4), 39);
    });

    test('placement and scoring', () {
      final k = KdKingdom(5);
      // domino 19 (index 18): wheat(1 crown) + forest
      expect(k.canPlace(18, 7, 6, 0), isTrue); // next to castle
      expect(k.canPlace(18, 9, 9, 0), isFalse); // not connected
      k.place(18, 7, 6, 0);
      expect(k.baseScore(), 1);
      k.place(0, 7, 5, 0); // wheat wheat above
      expect(k.baseScore(), 3); // 3 wheat × 1 crown
      k.place(12, 5, 6, 3); // wheat at (5,6), forest at (5,5); span x 5..8
      expect(k.canPlace(2, 9, 6, 1), isTrue); // forest next to forest, x span 5..9 = 5 wide
      expect(k.canPlace(2, 9, 6, 0), isFalse); // x span 5..10 exceeds 5x5
      expect(k.canPlace(2, 4, 7, 1), isFalse); // touches nothing matching
    });

    test('draft order follows domino number', () {
      final e = _start(Kingdomino(_setup(4)));
      for (var i = 0; i < 4; i++) {
        final s = e.actor;
        e.handle(s, {'type': 'pick', 'i': 3 - i});
      }
      expect(e.phase, 'place');
      expect(e.actor, e.curKing[0]);
      expect(e.curDom, [...e.curDom]..sort());
    });

    test('2 players use 24 dominoes, mighty duel 48', () {
      expect(_start(Kingdomino(_setup(2))).deck.length, 24 - 4);
      expect(_start(Kingdomino(_setup(2, {'mighty': true}))).deck.length, 48 - 4);
    });
  });

  group('patchwork', () {
    test('33 patches, turn order by time track', () {
      expect(pwPatches.length, 33);
      final e = _start(Patchwork(_setup(2)));
      final s = e.turn;
      e.handle(s, {'type': 'advance'});
      expect(e.pos[s], 1);
      expect(e.buttons[s], 6);
      expect(e.turn, 1 - s);
    });

    test('buying places the patch and moves the neutral token', () {
      final e = _start(Patchwork(_setup(2)));
      final s = e.turn;
      final p = e.available[0];
      final patch = pwPatches[p];
      e.buttons[s] = 20;
      e.handle(s, {'type': 'buy', 'k': 0, 'x': 0, 'y': 0, 'rot': 0, 'flip': false});
      expect(e.board[s].where((c) => c == p + 1).length, patch.cells.length);
      expect(e.buttons[s], 20 - patch.cost);
      expect(e.pos[s], min(patch.time, pwEnd));
      expect(e.ring.contains(p), isFalse);
      expect(() => e.handle(e.turn, {'type': 'buy', 'k': 5, 'x': 0, 'y': 0}), throwsA(isA<GameError>()));
    });

    test('income and leather patches', () {
      final e = _start(Patchwork(_setup(2)));
      e.top = 0;
      e.pos[1] = 30;
      e.pos[0] = 24;
      e.income[0] = 3;
      e.buttons[0] = 0;
      e.handle(0, {'type': 'advance'}); // to 31: passes 29 (income) and 26 (leather)
      expect(e.buttons[0], 7 + 3);
      expect(e.phase, 'leather');
      expect(e.waitingFor, [0]);
      e.handle(0, {'type': 'leather', 'x': 4, 'y': 4});
      expect(e.board[0][40], pwLeather);
    });

    test('7×7 bonus and scoring', () {
      final e = _start(Patchwork(_setup(2)));
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 7; x++) {
          e.board[0][y * 9 + x] = 1;
        }
      }
      e.board[0][0] = 0;
      e.phase = 'leather';
      e.leatherSeat = 0;
      e.pendingLeather = 1;
      e.handle(0, {'type': 'leather', 'x': 0, 'y': 0});
      expect(e.bonus7, 0);
      expect(e.scoreOf(0), e.buttons[0] - 2 * e.emptyCells(0) + 7);
    });
  });

  group('7 wonders duel', () {
    test('card data', () {
      expect(duelCards.where((c) => c.age == 1 && !c.isGuild).length, 23);
      expect(duelCards.where((c) => c.age == 2).length, 23);
      expect(duelCards.where((c) => c.age == 3 && !c.isGuild).length, 20);
      expect(duelCards.where((c) => c.isGuild).length, 7);
      expect(duelWonders.length, 12);
      expect(duelTokens.length, 10);
      for (var a = 0; a < 3; a++) {
        expect(duelLayouts[a].fold(0, (s, r) => s + r.length), 20);
      }
      // every chain requirement is provided by some card
      final links = {for (final c in duelCards) c.link};
      for (final c in duelCards) {
        if (c.chain.isNotEmpty) expect(links.contains(c.chain), isTrue, reason: c.name);
      }
    });

    Duel duel() {
      final e = _start(Duel(_setup(2)));
      while (e.phase == 'draft') {
        e.handle(e.turn, {'type': 'draft', 'w': 0});
      }
      return e;
    }

    test('wonder draft gives 4 each and deals age I', () {
      final e = duel();
      expect(e.wonders[0].length, 4);
      expect(e.wonders[1].length, 4);
      expect(e.age, 1);
      expect(e.slots.length, 20);
      expect([for (var i = 0; i < 20; i++) e.accessible(i)].where((x) => x).length, 6);
      // face-down rows are hidden in the view
      final v = e.view(0);
      final hidden = (v['slots'] as List).where((s) => s['card'] == null).length;
      expect(hidden, 3 + 5);
    });

    test('trade price = 2 + opponent production, chains are free', () {
      final e = duel();
      e.built[1].addAll([_card('采石场'), _card('石坑')]);
      expect(e.tradePrices(0)[2], 4);
      e.built[0].add(_card('石料储备'));
      expect(e.tradePrices(0)[2], 1);
      final aq = _card('引水渠'); // SSS
      expect(e.cardCost(0, aq).$1, 3);
      e.built[0].add(_card('浴场'));
      expect(e.chainFree(0, aq), isTrue);
      expect(e.cardCost(0, aq).$1, 0);
    });

    test('choice production minimises trading', () {
      final e = duel();
      e.built[0].add(_card('商队旅馆')); // W/C/S
      expect(e.tradeCost(0, e.duelCost('SS'), 0), 2);
      expect(e.tradeCost(0, e.duelCost('SS'), 2), 0);
    });

    test('military loot and supremacy', () {
      final e = duel();
      e.coins[1] = 10;
      e.testShields(0, 3);
      expect(e.coins[1], 8);
      e.testShields(0, 3);
      expect(e.coins[1], 3);
      expect(e.isOver, isFalse);
      e.testShields(0, 3);
      expect(e.isOver, isTrue);
      expect(e.result!['type'], 'military');
      expect(e.placings, [1, 2]);
    });

    test('science pair gives a token, six symbols win', () {
      final e = duel();
      e.built[0].addAll([_card('作坊'), _card('药剂坊'), _card('缮写室'), _card('药房'), _card('大学')]);
      e.testApply(0, _card('学院')); // 6th distinct symbol
      expect(e.isOver, isTrue);
      expect(e.result!['type'], 'science');
    });

    test('discard gives 2 + yellow cards', () {
      final e = duel();
      final s = e.turn;
      final i = [for (var k = 0; k < e.slots.length; k++) if (e.accessible(k)) k].first;
      final c0 = e.coins[s];
      e.built[s].add(_card('酒馆'));
      e.handle(s, {'type': 'discard', 'slot': i});
      expect(e.coins[s], c0 + 3);
      expect(e.discardPile.length, 1);
      expect(e.turn, 1 - s);
      expect(() => e.handle(1 - s, {'type': 'build', 'slot': 0}), throwsA(isA<GameError>())); // covered card
    });
  });

  test('sims', () {
    expect(runSims(euro2Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
