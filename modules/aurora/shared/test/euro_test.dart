import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/euro/carc_tiles.dart';
import 'package:aurora_shared/games/euro/carcassonne.dart';
import 'package:aurora_shared/games/euro/defs.dart';
import 'package:aurora_shared/games/euro/hanabi.dart';
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

int _t(String id) => carcTypeIndex(id);

Carcassonne _carc(int n) {
  final e = Carcassonne(_setup(n))..host = SimHost();
  e.start();
  e.deck = List.filled(20, _t('B'), growable: true);
  return e;
}

/// Places tile [id] for [seat] and optionally a meeple on local feature [f].
void _put(Carcassonne e, int seat, String id, int x, int y, int rot, {int f = -1, bool last = false}) {
  e.turn = seat;
  e.cur = _t(id);
  e.phase = 'place';
  e.handle(seat, {'type': 'place', 'x': x, 'y': y, 'rot': rot});
  if (last) e.deck.clear();
  e.handle(seat, {'type': 'meeple', 'f': f});
}

Hanabi _hanabi(int n, [Map<String, dynamic> opts = const {}]) {
  final e = Hanabi(_setup(n, opts))..host = SimHost();
  e.start();
  e.turn = 0;
  return e;
}

void main() {
  group('carcassonne', () {
    test('tile catalogue', () {
      expect(carcTiles.length, 24);
      expect(carcTiles.fold(0, (a, t) => a + t.count), 72);
    });

    test('edge matching', () {
      final e = _carc(2);
      // start tile D: N=city, E=road, S=field, W=road
      expect(e.fits(0, -1, _t('E'), 2), isTrue); // city faces south onto the city
      expect(e.fits(0, -1, _t('E'), 0), isFalse); // field against city
      expect(e.fits(1, 0, _t('U'), 1), isTrue); // road continues east
      expect(e.fits(1, 0, _t('U'), 0), isFalse);
      expect(e.fits(0, 1, _t('B'), 0), isTrue);
      expect(e.fits(0, 0, _t('B'), 0), isFalse); // occupied
      expect(e.fits(5, 5, _t('B'), 0), isFalse); // not adjacent
      expect(() => e.handle(e.turn, {'type': 'place', 'x': 9, 'y': 9, 'rot': 0}), throwsA(isA<GameError>()));
    });

    test('city completion scores 2 per tile and returns meeple', () {
      final e = _carc(2);
      _put(e, 0, 'E', 0, -1, 2, f: 0);
      expect(e.scores, [4, 0]);
      expect(e.meeplesLeft[0], 7);
      expect(e.meeples, isEmpty);
    });

    test('shield city scoring', () {
      final e = _carc(2);
      // M (city N+W with shield) rotated so the city faces S and W... use rot 1: sides N->E, W->N
      // Instead: cap D's city with Q? simpler: place M rot 3 => sides (0,3)->(3,2): city W+S.
      expect(e.fits(0, -1, _t('M'), 3), isTrue);
      _put(e, 1, 'M', 0, -1, 3, f: 0);
      expect(e.scores[1], 0); // still open to the west
      // close west side of M at (-1,-1) with E rot 1 (city on east)
      _put(e, 0, 'E', -1, -1, 1);
      // 3 tiles + 1 shield = 8
      expect(e.scores, [0, 8]);
    });

    test('road completion and meeple placement rules', () {
      final e = _carc(2);
      _put(e, 0, 'A', 1, 0, 1, f: 1); // road ends at cloister
      expect(e.scores, [0, 0]);
      // the road on the next tile is already occupied -> can't place there
      e.turn = 1;
      e.cur = _t('A');
      e.phase = 'place';
      e.handle(1, {'type': 'place', 'x': -1, 'y': 0, 'rot': 3});
      expect(e.meepleOptions(1).contains(1), isFalse);
      expect(() => e.handle(1, {'type': 'meeple', 'f': 1}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'meeple', 'f': -1});
      expect(e.scores, [3, 0]);
      expect(e.meeplesLeft[0], 7);
    });

    test('monastery scores 9 when surrounded', () {
      final e = _carc(2);
      _put(e, 0, 'B', 0, 1, 0, f: 0);
      _put(e, 1, 'A', 1, 0, 1);
      _put(e, 1, 'A', -1, 0, 3);
      for (final (x, y) in [(1, 1), (-1, 1), (-1, 2), (0, 2)]) {
        _put(e, 1, 'B', x, y, 0);
        expect(e.scores[0], 0);
      }
      _put(e, 1, 'B', 1, 2, 0);
      expect(e.scores[0], 9);
      expect(e.meeplesLeft[0], 7);
    });

    test('end scoring: incomplete features', () {
      final e = _carc(2);
      _put(e, 0, 'B', 0, 1, 0, f: 0); // cloister: 2 tiles
      _put(e, 1, 'U', 1, 0, 1, f: 0); // road D-U: 2 tiles
      _put(e, 0, 'N', 0, -1, 2, f: 0, last: true); // city S+E, still open
      expect(e.isOver, isTrue);
      // cloister (0,1) has (0,0),(1,0) + itself = 3; open city 2 tiles = 2
      expect(e.scores, [5, 2]);
    });

    test('farmers with shared majority both score', () {
      final e = _carc(2);
      _put(e, 0, 'E', 0, -1, 2, f: 1); // closes the city, farmer on field above it
      expect(e.scores, [0, 0]); // nobody on the city
      _put(e, 1, 'A', 1, 0, 1, f: 2); // farmer on the field below the city (via D)
      _put(e, 0, 'B', 1, -1, 0, last: true); // joins both fields
      expect(e.isOver, isTrue);
      expect(e.scores, [3, 3]);
      final fin = e.view(0)['final'] as List;
      expect(fin.every((m) => (m as Map)['win'] == true), isTrue);
    });

    test('farmers option off forbids field meeples', () {
      final e = Carcassonne(_setup(2, {'farmers': false}))..host = SimHost();
      e.start();
      e.turn = 0;
      e.cur = _t('E');
      e.phase = 'place';
      e.handle(0, {'type': 'place', 'x': 0, 'y': -1, 'rot': 2});
      expect(e.meepleOptions(0), [0]);
    });

    test('placings: null while running, rankByScore at the end', () {
      final e = _carc(3);
      expect(e.placings, isNull);
      expect(e.canResign, isFalse); // 3 players: no resign
      _put(e, 0, 'E', 0, -1, 2, f: 0, last: true); // P0 closes a city: 4 points
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 2, 2]);
    });

    test('2p resign: opponent wins', () {
      final e = _carc(2);
      expect(e.canResign, isTrue);
      e.scores = [10, 0];
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
      expect(e.canResign, isFalse);
      expect(e.waitingFor, isEmpty);
      expect(() => e.handle(1, {'type': 'place', 'x': 0, 'y': 1, 'rot': 0}), throwsA(isA<GameError>()));
      final fin = e.view(1)['final'] as List;
      expect((fin[1] as Map)['win'], isTrue);
      expect((fin[0] as Map)['win'], isFalse);
      expect((e.host as SimHost).logs.last, contains('认输'));
    });

    test('bot levels return legal moves without changing state', () {
      for (final lvl in [0, 1, 2]) {
        final e = Carcassonne(GameSetup(
            players: 2, options: const {}, names: const ['a', 'b'], bots: const [true, true], rng: Random(3), botLevel: lvl))
          ..host = SimHost();
        e.start();
        var steps = 0;
        while (!e.isOver && steps++ < 400) {
          final s = e.waitingFor.first;
          final before = jsonEncode(e.view(s));
          final a = e.runBot(s)!;
          expect(jsonEncode(e.view(s)), before);
          e.handle(s, a);
        }
        expect(e.isOver, isTrue);
        expect(e.placings, isNotNull);
      }
    });

    test('majority', () {
      expect(Carcassonne.majority([0, 0, 1]), [0]);
      expect(Carcassonne.majority([1, 0]), [0, 1]);
      expect(Carcassonne.majority([]), isEmpty);
    });
  });

  group('hanabi', () {
    test('setup', () {
      expect(_hanabi(3).hands.every((h) => h.length == 5), isTrue);
      expect(_hanabi(4).hands.every((h) => h.length == 4), isTrue);
      final r = _hanabi(2, {'rainbow': true});
      expect(r.deck.length + 10, 60);
      expect(r.maxScore, 30);
    });

    test('clue legality', () {
      final e = _hanabi(2);
      e.hands[1] = [HCard(900, 0, 1, 5), HCard(901, 1, 1, 5), HCard(902, 0, 3, 5), HCard(903, 2, 4, 5), HCard(904, 3, 5, 5)];
      expect(() => e.handle(0, {'type': 'clue', 'to': 0, 'color': 0}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'clue', 'to': 1, 'color': 4}), throwsA(isA<GameError>())); // no white card
      expect(() => e.handle(0, {'type': 'clue', 'to': 1}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'clue', 'to': 1, 'color': 0, 'number': 1}), throwsA(isA<GameError>()));
      expect(() => e.handle(1, {'type': 'clue', 'to': 0, 'number': 1}), throwsA(isA<GameError>())); // not your turn
      expect(() => e.handle(0, {'type': 'discard', 'i': 0}), throwsA(isA<GameError>())); // 8 clues
      e.handle(0, {'type': 'clue', 'to': 1, 'color': 0});
      expect(e.clues, 7);
      expect(e.turn, 1);
      e.clues = 0;
      expect(() => e.handle(1, {'type': 'clue', 'to': 0, 'number': e.hands[0][0].number}), throwsA(isA<GameError>()));
    });

    test('knowledge and hidden view', () {
      final e = _hanabi(2);
      e.hands[1] = [HCard(900, 0, 1, 5), HCard(901, 1, 1, 5), HCard(902, 0, 3, 5), HCard(903, 2, 4, 5)];
      e.handle(0, {'type': 'clue', 'to': 1, 'number': 1});
      final h = e.hands[1];
      expect(h[0].numbers, {1});
      expect(h[1].numbers, {1});
      expect(h[2].numbers, {2, 3, 4, 5});
      expect(h[0].clued && h[1].clued && !h[2].clued, isTrue);
      final own = (e.view(1)['hands'] as List)[1] as List;
      final c0 = own[0] as Map;
      expect(c0['c'], isNull);
      expect(c0['n'], isNull);
      expect(c0['nn'], [1]);
      final other = (e.view(0)['hands'] as List)[1] as List;
      expect((other[0] as Map)['c'], 0);
      expect(((e.view(-1)['hands'] as List)[0] as List).first['n'], isNotNull);
      // own card knowledge excludes what the player can see elsewhere
      final poss = e.ownPoss(1, h[2]);
      expect(poss.keys.every((id) => id % 10 != 1), isTrue);
    });

    test('play, misplay, fuses and scoring', () {
      final e = _hanabi(2);
      e.hands[0] = [HCard(900, 0, 1, 5), HCard(901, 0, 3, 5), HCard(902, 1, 1, 5), HCard(903, 1, 3, 5), HCard(904, 2, 2, 5)];
      e.handle(0, {'type': 'play', 'i': 0});
      expect(e.stacks[0], 1);
      expect(e.score, 1);
      e.turn = 0;
      e.hands[0][0] = HCard(905, 3, 4, 5);
      e.handle(0, {'type': 'play', 'i': 0});
      expect(e.fuses, 1);
      expect(e.discards.last.id, 905);
      e.fuses = 2;
      e.turn = 0;
      e.hands[0][0] = HCard(906, 4, 5, 5);
      e.handle(0, {'type': 'play', 'i': 0});
      expect(e.isOver, isTrue);
      expect(e.score, 0);
    });

    test('five returns a clue token; perfect game ends', () {
      final e = _hanabi(2);
      e.stacks = [5, 5, 5, 5, 4];
      e.clues = 3;
      e.hands[0][0] = HCard(907, 4, 5, 5);
      e.handle(0, {'type': 'play', 'i': 0});
      expect(e.clues, 4);
      expect(e.isOver, isTrue);
      expect(e.score, 25);
    });

    test('deck exhaustion gives everyone one last turn', () {
      final e = _hanabi(3);
      e.deck = [e.deck.first];
      e.clues = 3;
      e.handle(0, {'type': 'discard', 'i': 0}); // draws the last card
      expect(e.deck, isEmpty);
      expect(e.isOver, isFalse);
      e.handle(1, {'type': 'discard', 'i': 0});
      e.handle(2, {'type': 'discard', 'i': 0});
      expect(e.isOver, isFalse);
      e.handle(0, {'type': 'discard', 'i': 0});
      expect(e.isOver, isTrue);
    });

    test('placings: cooperative, everyone first', () {
      final e = _hanabi(3);
      expect(e.placings, isNull);
      expect(e.canResign, isFalse);
      e.fuses = 2;
      e.hands[0][0] = HCard(906, 4, 5, 5);
      e.handle(0, {'type': 'play', 'i': 0});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1, 1]);
    });

    test('bot levels finish games and never mutate state', () {
      for (final lvl in [0, 1, 2]) {
        final e = Hanabi(GameSetup(
            players: 3, options: const {}, names: const ['a', 'b', 'c'], bots: const [true, true, true], rng: Random(11), botLevel: lvl))
          ..host = SimHost();
        e.start();
        var steps = 0;
        while (!e.isOver && steps++ < 500) {
          final s = e.waitingFor.first;
          final before = jsonEncode(e.view(-1));
          final a = e.runBot(s)!;
          expect(jsonEncode(e.view(-1)), before);
          e.handle(s, a);
        }
        expect(e.isOver, isTrue);
      }
    });

    test('bot ignores the identity of its own cards', () {
      // same public info + same other hands, different own cards -> same decision
      for (var seed = 1; seed <= 20; seed++) {
        final a = Hanabi(GameSetup(players: 3, options: const {}, names: const ['a', 'b', 'c'], bots: const [true, true, true], rng: Random(seed), botRng: Random(1)))
          ..host = SimHost();
        a.start();
        final s = a.turn;
        final r1 = a.runBot(s);
        // swap own hand identities with fresh cards carrying the same clue knowledge
        final h = a.hands[s];
        for (var i = 0; i < h.length; i++) {
          final c = h[i];
          final n = HCard(c.id, (c.color + 1) % 5, c.number == 5 ? 1 : c.number + 1, 5)
            ..clued = c.clued
            ..saved = c.saved
            ..sig = c.sig;
          n.colors..clear()..addAll(c.colors);
          n.numbers..clear()..addAll(c.numbers);
          h[i] = n;
        }
        final b = Hanabi(GameSetup(players: 3, options: const {}, names: const ['a', 'b', 'c'], bots: const [true, true, true], rng: Random(seed), botRng: Random(1)))
          ..host = SimHost();
        b.start();
        b.hands[s] = h;
        expect(jsonEncode(b.runBot(s)), jsonEncode(r1));
      }
    });

    test('bot only returns legal actions', () {
      for (var seed = 1; seed <= 5; seed++) {
        final e = Hanabi(GameSetup(players: 3, options: const {}, names: const ['a', 'b', 'c'], bots: const [true, true, true], rng: Random(seed)))
          ..host = SimHost();
        e.start();
        var steps = 0;
        while (!e.isOver && steps++ < 500) {
          final s = e.waitingFor.first;
          e.handle(s, e.bot(s)!);
        }
        expect(e.isOver, isTrue);
      }
    });
  });

  test('bot simulations', timeout: const Timeout(Duration(minutes: 10)), () {
    expect(runSims(euroGames, n: 30), 0);
  });
}
