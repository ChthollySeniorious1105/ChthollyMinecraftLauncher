import 'dart:math';

import 'package:aurora_shared/games/bang/bang.dart';
import 'package:aurora_shared/games/bang/bang_cards.dart';
import 'package:aurora_shared/games/bang/cockroach.dart';
import 'package:aurora_shared/games/bang/defs.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

int _find(String kind, [List<int> avoid = const []]) {
  for (var i = 0; i < bangDeck.length; i++) {
    if (bangDeck[i].kind == kind && !avoid.contains(i)) return i;
  }
  throw StateError(kind);
}

/// A Bang game with no characters, all hands/equipment emptied, seat 0 to play.
Bang _bang(int n) {
  final e = Bang(_setup(n, {'chars': false}))..start();
  for (var i = 0; i < n; i++) {
    e.discard.addAll(e.hands[i]);
    e.hands[i].clear();
    e.equip[i].clear();
  }
  e.turn = 0;
  e.phase = 'play';
  e.bangs = 0;
  return e;
}

void _take(Bang e, int seat, int card) {
  e.deck.remove(card);
  e.discard.remove(card);
  e.hands[seat].add(card);
}

void main() {
  group('蟑螂扑克', () {
    test('deal all 64 cards', () {
      final e = Cockroach(_setup(5, {}))..start();
      expect(e.hands.fold<int>(0, (a, h) => a + h.length), 64);
    });
    test('call right: passer takes; call wrong: receiver takes', () {
      final e = Cockroach(_setup(3, {}))..start();
      e.turn = 0;
      e.hands[0] = [2, 3];
      e.handle(0, {'type': 'pass', 'card': 2, 'to': 1, 'claim': 2});
      expect(e.view(1)['card'], -1);
      expect(e.view(0)['card'], 2);
      e.handle(1, {'type': 'call', 'truth': false});
      expect(e.faceUp[1][2], 1);
      expect(e.turn, 1);
      e.hands[1] = [5];
      e.handle(1, {'type': 'pass', 'card': 5, 'to': 2, 'claim': 0});
      e.handle(2, {'type': 'call', 'truth': false});
      expect(e.faceUp[1][5], 1);
    });
    test('peek & pass; last player must call', () {
      final e = Cockroach(_setup(3, {}))..start();
      e.turn = 0;
      e.hands[0] = [4];
      e.handle(0, {'type': 'pass', 'card': 4, 'to': 1, 'claim': 4});
      e.handle(1, {'type': 'peek'});
      expect(e.view(1)['card'], 4);
      expect(() => e.handle(1, {'type': 'pass', 'to': 0, 'claim': 1}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'pass', 'to': 2, 'claim': 1});
      expect(() => e.handle(2, {'type': 'peek'}), throwsA(isA<GameError>()));
      e.handle(2, {'type': 'call', 'truth': true});
      expect(e.faceUp[2][4], 1);
    });
    test('4 of a kind loses', () {
      final e = Cockroach(_setup(3, {}))..start();
      e.turn = 0;
      e.hands[0] = [6, 6];
      e.faceUp[1][6] = 3;
      e.handle(0, {'type': 'pass', 'card': 6, 'to': 1, 'claim': 6});
      e.handle(1, {'type': 'call', 'truth': false});
      expect(e.isOver, isTrue);
      expect(e.placings![1], 3);
    });
  });

  group('西部无间道', () {
    test('deck: 80 cards with correct counts', () {
      expect(bangDeck.length, 80);
      int n(String k) => bangDeck.where((c) => c.kind == k).length;
      expect(n('bang'), 25);
      expect(n('missed'), 12);
      expect(n('beer'), 6);
      expect(n('panic'), 4);
      expect(n('catbalou'), 4);
      expect(n('duel'), 3);
      expect(bangDeck.where((c) => bangBlueKinds.contains(c.kind)).length, 17);
    });
    test('roles by player count', () {
      expect(bangRolesFor(4)..sort(), ['outlaw', 'outlaw', 'renegade', 'sheriff']);
      expect(bangRolesFor(7).where((r) => r == 'outlaw').length, 3);
      expect(bangRolesFor(7).where((r) => r == 'deputy').length, 2);
      final e = Bang(_setup(5, {}))..start();
      expect(e.turn, e.sheriff);
      expect(e.maxHp[e.sheriff], (e.chars[e.sheriff] >= 0 ? bangChars[e.chars[e.sheriff]].hp : 4) + 1);
      // role hidden from others, sheriff public
      final other = (e.sheriff + 1) % 5;
      final v = e.view((other + 1) % 5);
      expect((v['players'] as List)[other]['role'], isNull);
      expect((v['players'] as List)[e.sheriff]['role'], 'sheriff');
    });
    test('distance, range, mustang, one BANG per turn', () {
      final e = _bang(5);
      expect(e.dist(0, 1), 1);
      expect(e.dist(0, 2), 2);
      expect(e.dist(0, 3), 2);
      e.equip[1].add(_find('mustang'));
      expect(e.dist(0, 1), 2);
      final b1 = _find('bang');
      final b2 = _find('bang', [b1]);
      _take(e, 0, b1);
      _take(e, 0, b2);
      expect(e.targetsFor(0, b1), [4]);
      e.handle(0, {'type': 'play', 'card': b1, 'target': 4});
      // seat 4 has no missed -> damage resolved
      expect(e.hp[4], e.maxHp[4] - 1);
      expect(e.phase, 'play');
      expect(e.targetsFor(0, b2), isNull);
      expect(() => e.handle(0, {'type': 'play', 'card': b2, 'target': 4}), throwsA(isA<GameError>()));
    });
    test('missed response window', () {
      final e = _bang(4);
      final b = _find('bang');
      final m = _find('missed');
      _take(e, 0, b);
      _take(e, 1, m);
      e.handle(0, {'type': 'play', 'card': b, 'target': 1});
      expect(e.phase, 'respond');
      expect(e.waitingFor, [1]);
      e.handle(1, {'type': 'respond', 'card': m});
      expect(e.hp[1], e.maxHp[1]);
      expect(e.phase, 'play');
    });
    test('beer saves at 0 hp; useless with 2 players', () {
      final e = _bang(4);
      final b = _find('bang');
      final beer = _find('beer');
      _take(e, 0, b);
      _take(e, 1, beer);
      e.hp[1] = 1;
      e.handle(0, {'type': 'play', 'card': b, 'target': 1});
      expect(e.alive[1], isTrue);
      expect(e.hp[1], 1);
    });
    test('killing an outlaw draws 3; sheriff wins when bad guys dead', () {
      final e = _bang(4);
      // make seat 0 sheriff and seat 1 an outlaw
      e.roles = ['sheriff', 'outlaw', 'outlaw', 'renegade'];
      e.sheriff = 0;
      final b = _find('bang');
      _take(e, 0, b);
      e.hp[1] = 1;
      e.handle(0, {'type': 'play', 'card': b, 'target': 1});
      expect(e.alive[1], isFalse);
      expect(e.hands[0].length, 3);
      expect((e.view(2)['players'] as List)[1]['role'], 'outlaw');
      e.alive[2] = false;
      e.hp[3] = 1;
      final g = _find('gatling');
      _take(e, 0, g);
      e.handle(0, {'type': 'play', 'card': g});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 2, 2]);
    });
    test('sheriff killing deputy discards everything', () {
      final e = _bang(5);
      e.roles = ['sheriff', 'deputy', 'outlaw', 'outlaw', 'renegade'];
      e.sheriff = 0;
      final d = _find('duel');
      _take(e, 0, d);
      _take(e, 0, _find('beer'));
      e.hp[1] = 1;
      e.handle(0, {'type': 'play', 'card': d, 'target': 1});
      expect(e.alive[1], isFalse);
      expect(e.hands[0], isEmpty);
    });
    test('jail cannot target sheriff; jail skips turn on non-heart', () {
      final e = _bang(4);
      e.roles = ['outlaw', 'sheriff', 'outlaw', 'renegade'];
      e.sheriff = 1;
      final j = _find('jail');
      _take(e, 0, j);
      expect(e.targetsFor(0, j), isNot(contains(1)));
      e.handle(0, {'type': 'play', 'card': j, 'target': 2});
      expect(e.hasEquip(2, 'jail'), isTrue);
    });
    test('discard down to hp at end of turn', () {
      final e = _bang(4);
      e.hp[0] = 2;
      for (final k in ['missed', 'beer', 'saloon']) {
        _take(e, 0, _find(k));
      }
      e.handle(0, {'type': 'end'});
      expect(e.phase, 'discard');
      expect(() => e.handle(0, {'type': 'discard', 'cards': <int>[]}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'discard', 'cards': [e.hands[0].first]});
      expect(e.turn, isNot(0));
    });
    test('general store: everyone picks in order', () {
      final e = _bang(4);
      final s = _find('store');
      _take(e, 0, s);
      e.handle(0, {'type': 'play', 'card': s});
      expect(e.phase, 'store');
      expect(e.waitingFor, [0]);
      e.handle(0, {'type': 'pick', 'card': e.storeCards.first});
      expect(e.waitingFor, [1]);
      e.handle(1, {'type': 'pick', 'card': e.storeCards.first});
      e.handle(2, {'type': 'pick', 'card': e.storeCards.first});
      expect(e.phase, 'play');
      expect(e.hands[3].length, 1);
    });
    test('views hide hands', () {
      final e = Bang(_setup(6, {}))..start();
      final v = e.view(2);
      expect(v['hand'], e.hands[2]);
      expect(e.view(-1)['hand'], isEmpty);
    });
  });

  test('simulations', () {
    expect(runSims(bangGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
