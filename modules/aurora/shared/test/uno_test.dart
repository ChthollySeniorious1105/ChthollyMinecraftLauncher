import 'dart:math';

import 'package:aurora_shared/games/uno/defs.dart';
import 'package:aurora_shared/games/uno/rummikub.dart';
import 'package:aurora_shared/games/uno/uno.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

int t(int color, int n) => color * 13 + n - 1;
const j1 = 104, j2 = 105;

UnoGame unoGame(int players, Map<String, dynamic> opts, {int seed = 1}) {
  final g = UnoGame(GameSetup(
      players: players,
      options: opts,
      names: [for (var i = 0; i < players; i++) 'P$i'],
      bots: List.filled(players, false),
      rng: Random(seed)));
  g.start();
  return g;
}

/// Find a card id whose face is [f] (anywhere) and put it in seat's hand.
int give(UnoGame g, int seat, String f) {
  for (var id = 0; id < g.deck.length; id++) {
    if (g.face(id) != f) continue;
    if (g.discard.contains(id)) continue;
    for (final h in g.hands) {
      h.remove(id);
    }
    g.drawPile.remove(id);
    g.hands[seat].add(id);
    return id;
  }
  throw StateError('no $f');
}

void main() {
  group('rummikub sets', () {
    test('runs', () {
      expect(rkValid([t(0, 3), t(0, 4), t(0, 5)]), isTrue);
      expect(rkValid([t(0, 3), t(1, 4), t(0, 5)]), isFalse);
      expect(rkValid([t(0, 3), t(0, 4)]), isFalse);
      expect(rkValid([t(0, 11), t(0, 12), t(0, 13), j1]), isFalse); // no wrap
      expect(rkSetValue([t(0, 3), t(0, 4), t(0, 5)]), 12);
    });
    test('groups', () {
      expect(rkValid([t(0, 7), t(1, 7), t(2, 7)]), isTrue);
      expect(rkValid([t(0, 7), t(1, 7), t(2, 7), t(3, 7)]), isTrue);
      expect(rkValid([t(0, 7), t(0, 7) + 52, t(2, 7)]), isFalse); // duplicate colour
      expect(rkSetValue([t(0, 10), t(1, 10), t(2, 10)]), 30);
    });
    test('jokers', () {
      expect(rkSetValue([t(0, 3), j1, t(0, 5)]), 12);
      expect(rkSetValue([t(0, 9), t(1, 9), j1]), 27);
      expect(rkValid([j1, j2, t(0, 5)]), isTrue);
      expect(rkNormalize([t(0, 5), t(0, 3), j1]), [t(0, 3), j1, t(0, 5)]);
      expect(rkNormalize([t(0, 12), t(0, 13), j1]), isNotNull);
      expect(rkNormalize([t(0, 3), t(1, 5), j1]), isNull);
    });
    test('initial meld needs 30', () {
      final g = RummikubGame(GameSetup(players: 2, options: {}, names: ['a', 'b'], bots: [false, false], rng: Random(1)));
      g.start();
      final s = g.turn;
      g.racks[s] = [t(0, 1), t(0, 2), t(0, 3), t(1, 10), t(2, 10), t(3, 10), t(1, 13)];
      expect(() => g.submit(s, [[t(0, 1), t(0, 2), t(0, 3)]]), throwsA(isA<GameError>()));
      g.submit(s, [[t(1, 10), t(2, 10), t(3, 10)]]);
      expect(g.melded[s], isTrue);
      expect(g.table.length, 1);
      // other player cannot take table tiles back
      final o = g.turn;
      g.racks[o] = [t(0, 10), t(0, 5)];
      g.melded[o] = true;
      expect(() => g.submit(o, [[t(1, 10), t(2, 10)]]), throwsA(isA<GameError>()));
      g.submit(o, [[t(1, 10), t(2, 10), t(3, 10), t(0, 10)]]);
      expect(g.racks[o], [t(0, 5)]);
    });
  });

  group('uno', () {
    test('deck sizes', () {
      expect(buildUnoDeck('classic').length, 108);
      expect(buildUnoDeck('flip').length, 112);
      expect(buildUnoDeck('nomercy').length, 168);
    });
    test('stacking +2 on +2 then draw total', () {
      final g = unoGame(3, {'mode': 'classic', 'stack': true});
      g.turn = 0;
      final a = give(g, 0, 'r+2');
      give(g, 0, 'y5');
      g.curColor = 'r';
      final b = give(g, 1, 'b+2');
      give(g, 1, 'b7');
      g.handle(0, {'type': 'play', 'card': a});
      expect(g.pending, 2);
      expect(g.turn, 1);
      g.handle(1, {'type': 'play', 'card': b});
      expect(g.pending, 4);
      final before = g.hands[2].length;
      expect(() => g.handle(2, {'type': 'play', 'card': g.hands[2].first}), throwsA(isA<GameError>()));
      g.handle(2, {'type': 'draw'});
      expect(g.hands[2].length, before + 4);
      expect(g.turn, 0);
    });
    test('no stacking: +2 draws immediately and skips', () {
      final g = unoGame(3, {'mode': 'classic', 'stack': false});
      g.turn = 0;
      final a = give(g, 0, 'r+2');
      give(g, 0, 'y5');
      g.curColor = 'r';
      final before = g.hands[1].length;
      g.handle(0, {'type': 'play', 'card': a});
      expect(g.hands[1].length, before + 2);
      expect(g.turn, 2);
    });
    test('no mercy: cannot stack lower', () {
      final g = unoGame(3, {'mode': 'nomercy'});
      g.turn = 0;
      final a = give(g, 0, 'w+6');
      give(g, 0, 'y5');
      final low = give(g, 1, 'r+4');
      final high = give(g, 1, 'w+10');
      give(g, 1, 'y1');
      g.handle(0, {'type': 'play', 'card': a, 'color': 'r'});
      expect(() => g.handle(1, {'type': 'play', 'card': low}), throwsA(isA<GameError>()));
      g.handle(1, {'type': 'play', 'card': high, 'color': 'b'});
      expect(g.pending, 16);
    });
    test('wild +4 challenge', () {
      final g = unoGame(3, {'mode': 'classic'});
      g.turn = 0;
      g.hands[0].clear();
      final w = give(g, 0, 'w+4');
      give(g, 0, 'r3');
      give(g, 0, 'y3');
      g.curColor = 'r';
      g.handle(0, {'type': 'play', 'card': w, 'color': 'b'});
      final b0 = g.hands[0].length;
      g.handle(1, {'type': 'challenge'});
      expect(g.hands[0].length, b0 + 4); // guilty
      expect(g.turn, 1);
    });
    test('uno catch', () {
      final g = unoGame(3, {'mode': 'classic'});
      g.turn = 0;
      g.hands[0].clear();
      final a = give(g, 0, 'r3');
      give(g, 0, 'r4');
      g.curColor = 'r';
      g.handle(0, {'type': 'play', 'card': a});
      expect(g.vulnerable, 0);
      g.handle(2, {'type': 'catch'});
      expect(g.hands[0].length, 3);
    });
  });

  group('v3', () {
    test('uno resign + placings', () {
      final g = unoGame(2, {'mode': 'classic'});
      expect(g.placings, isNull);
      expect(g.canResign, isTrue);
      g.resign(0);
      expect(g.isOver, isTrue);
      expect(g.placings, [2, 1]);
      expect(g.canResign, isFalse);
      expect(unoGame(3, {'mode': 'classic'}).canResign, isFalse);
    });

    test('uno single-game placings by remaining points', () {
      final g = unoGame(3, {'mode': 'classic'});
      g.hands[0] = [give(g, 0, 'r5')];
      g.hands[1] = [give(g, 1, 'wW')];
      g.hands[2] = [give(g, 2, 'g1')];
      g.curColor = 'r';
      g.turn = 0;
      g.handle(0, {'type': 'play', 'card': g.hands[0].first});
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 3, 2]);
    });

    test('rummikub resign + placings', () {
      final g = RummikubGame(GameSetup(players: 2, options: {}, names: ['a', 'b'], bots: [false, false], rng: Random(2)))..start();
      expect(g.placings, isNull);
      g.resign(1);
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 2]);
    });
  });

  test('simulations', () {
    expect(runSims(unoGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
