import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/military/animalchess.dart';
import 'package:aurora_shared/games/military/defs.dart';
import 'package:aurora_shared/games/military/junqi.dart';
import 'package:aurora_shared/games/military/junqi_ai.dart';
import 'package:aurora_shared/games/military/junqi_geo.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

Junqi makeJunqi(String mode, {int players = 2, int seed = 1}) {
  final g = Junqi(GameSetup(
    players: players,
    options: {'mode': mode},
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: List.filled(players, false),
    rng: Random(seed),
  ));
  g.host = SimHost();
  g.start();
  return g;
}

/// A uniformly random legal action for [seat], chosen from its view only.
Map<String, dynamic> randomAction(Junqi g, int seat, Random r) {
  if (g.phase == 0) return {'type': 'ready'};
  final v = g.view(seat);
  final board = v['board'] as List;
  final moves = (v['moves'] as Map).entries.toList();
  final downs = [
    for (var i = 0; i < board.length; i++)
      if (g.flip && board[i] != null && (board[i] as Map)['u'] == false) i
  ];
  if (downs.isNotEmpty && (moves.isEmpty || r.nextInt(3) == 0)) {
    return {'type': 'flip', 'node': downs[r.nextInt(downs.length)]};
  }
  if (moves.isEmpty) return {'type': 'resign'};
  final e = moves[r.nextInt(moves.length)];
  final tos = e.value as List;
  return {'type': 'move', 'from': int.parse(e.key as String), 'to': tos[r.nextInt(tos.length)]};
}

/// Plays until [plies] non-setup actions happened and it is [observer]'s turn.
/// Returns the action list so the game can be replayed.
List<(int, Map<String, dynamic>)> playUntil(Junqi g, int plies, int observer, int seed) {
  final r = Random(seed);
  final out = <(int, Map<String, dynamic>)>[];
  var n = 0;
  while (!g.isOver && (n < plies || g.phase == 0 || g.waitingFor.first != observer)) {
    final s = g.waitingFor.first;
    final a = g.botWith(s, r)!;
    g.handle(s, a);
    out.add((s, a));
    if (a['type'] != 'ready') n++;
  }
  return out;
}

/// Permutes the hidden pieces selected by [target]. With [whole] the entire
/// piece (owner too) moves, otherwise only ranks are permuted.
void scrambleHidden(Junqi g, bool Function(JP) target, Random r, {bool whole = false}) {
  final idx = [for (var i = 0; i < g.b.length; i++) if (g.b[i] != null && !g.b[i]!.up && target(g.b[i]!)) i];
  final pieces = [for (final i in idx) g.b[i]!];
  var perm = shuffled(pieces, r);
  if (pieces.length > 1 && [for (var k = 0; k < idx.length; k++) perm[k].rank == pieces[k].rank].every((x) => x)) {
    perm = [...perm.skip(1), perm.first];
  }
  for (var k = 0; k < idx.length; k++) {
    final old = pieces[k];
    g.b[idx[k]] = whole
        ? perm[k]
        : (JP(old.owner, perm[k].rank, up: old.up)
          ..moved = old.moved
          ..kills = old.kills);
  }
}

Map<String, dynamic> cell(int o, int k) => {'o': o, 'k': k, 'u': false};

void main() {
  group('junqi geometry', () {
    test('two-player board', () {
      final g = JunqiGeo.two;
      expect(g.nodes.length, 60);
      expect(g.nodes.where((n) => n.kind == JKind.camp).length, 10);
      expect(g.nodes.where((n) => n.kind == JKind.hq).length, 4);
      // front line only connects on columns 0, 2, 4
      for (var c = 0; c < 5; c++) {
        final linked = g.adj[g.at(5, c)!].contains(g.at(6, c));
        expect(linked, c.isEven, reason: 'col $c');
      }
      // camps have diagonal links
      expect(g.adj[g.at(8, 2)!], containsAll([g.at(7, 1), g.at(7, 3), g.at(9, 1), g.at(9, 3)]));
    });
    test('four-player board', () {
      final g = JunqiGeo.cross;
      expect(g.nodes.length, 129);
      expect(g.arcs.length, 4);
    });
  });

  group('junqi combat', () {
    test('ranks', () {
      expect(junqiBattle(kCmd, 8), 1);
      expect(junqiBattle(5, 6), -1);
      expect(junqiBattle(4, 4), 0);
      expect(junqiBattle(kBomb, kCmd), 0);
      expect(junqiBattle(kCmd, kBomb), 0);
      expect(junqiBattle(kEng, kMine), 1);
      expect(junqiBattle(kCmd, kMine), -1);
      expect(junqiBattle(kBomb, kMine), 0);
      expect(junqiBattle(kEng, kFlag), 1);
    });
  });

  group('junqi movement', () {
    List<JP?> empty(JunqiGeo g) => List<JP?>.filled(g.nodes.length, null);
    mine(JP p) => p.owner == 0;
    friend(JP p) => p.owner == 0;

    test('railway straight, engineer turns corners', () {
      final g = JunqiGeo.two;
      final b = empty(g);
      final from = g.at(10, 0)!;
      b[from] = JP(0, 5);
      final t = junqiTargets(g, b, from, friend);
      expect(t, contains(g.at(1, 0))); // straight down the rail
      expect(t, contains(g.at(10, 4))); // straight along the row
      expect(t, isNot(contains(g.at(1, 4)))); // needs a turn
      b[from] = JP(0, kEng);
      final te = junqiTargets(g, b, from, friend);
      expect(te, contains(g.at(1, 4)));
      expect(te, contains(g.at(5, 2)));
    });

    test('rail blocked by pieces; camp protects', () {
      final g = JunqiGeo.two;
      final b = empty(g);
      final from = g.at(10, 0)!;
      b[from] = JP(0, 5);
      b[g.at(7, 0)!] = JP(0, 3);
      final t = junqiTargets(g, b, from, friend);
      expect(t, contains(g.at(8, 0)));
      expect(t, isNot(contains(g.at(6, 0))));
      // enemy in camp cannot be attacked
      final a = g.at(4, 0)!;
      b[a] = JP(0, 9);
      b[g.at(3, 1)!] = JP(1, 2);
      expect(junqiTargets(g, b, a, friend), isNot(contains(g.at(3, 1))));
    });

    test('immobile pieces and hq lock', () {
      final g = JunqiGeo.two;
      final b = empty(g);
      b[g.at(11, 1)!] = JP(0, 9); // in hq
      b[g.at(9, 0)!] = JP(0, kMine);
      b[g.at(8, 0)!] = JP(0, kFlag);
      expect(junqiMoves(g, b, mine, friend), isEmpty);
    });
  });

  group('junqi game', () {
    test('default layouts are valid and hidden', () {
      final g = makeJunqi('two');
      expect(g.layoutError(0), isNull);
      expect(g.layoutError(1), isNull);
      final v = g.view(0);
      final board = v['board'] as List;
      final geo = JunqiGeo.two;
      for (final id in geo.armNodes[1]) {
        if (board[id] != null) expect((board[id] as Map)['k'], -1);
      }
      for (final id in geo.armNodes[0]) {
        if (board[id] != null) expect((board[id] as Map)['k'], isNot(-1));
      }
    });
    test('four-player teammates see each other', () {
      final g = makeJunqi('four', players: 4);
      for (var s = 0; s < 4; s++) {
        expect(g.layoutError(s), isNull);
      }
      final board = g.view(0)['board'] as List;
      final geo = JunqiGeo.cross;
      expect((board[geo.armNodes[2][0]] as Map)['k'], isNot(-1));
      expect((board[geo.armNodes[1][0]] as Map)['k'], -1);
    });
    test('invalid swap is rejected', () {
      final g = makeJunqi('two');
      final geo = JunqiGeo.two;
      final flag = geo.armNodes[0].firstWhere((id) => g.b[id]?.rank == kFlag);
      final front = geo.armNodes[0].firstWhere((id) => geo.nodes[id].lr == 0);
      expect(() => g.handle(0, {'type': 'swap', 'a': flag, 'b': front}), throwsA(isA<GameError>()));
    });
    test('flip mode: 50 face-down pieces', () {
      final g = makeJunqi('flip');
      expect(g.b.where((p) => p != null).length, 50);
      expect((g.view(0)['board'] as List).every((c) => c == null || (c as Map)['k'] == -1), isTrue);
    });
  });

  group('junqi fair bots', () {
    void fairness(String mode, int players, int observer, bool Function(JP) hidden, {bool whole = false}) {
      var checked = 0;
      for (var seed = 1; seed <= 10; seed++) {
        for (final plies in [0, 7, 30, 80]) {
          final a = makeJunqi(mode, players: players, seed: seed);
          final acts = playUntil(a, plies, observer, seed * 31);
          if (a.isOver) continue;
          final b = makeJunqi(mode, players: players, seed: seed);
          for (final (s, x) in acts) {
            b.handle(s, x);
          }
          scrambleHidden(b, hidden, Random(seed + 99), whole: whole);
          expect(jsonEncode(b.view(observer)), jsonEncode(a.view(observer)), reason: 'views must match');
          final differs = [for (var i = 0; i < a.b.length; i++) if (a.b[i]?.rank != b.b[i]?.rank) i];
          if (differs.isEmpty) continue; // nothing hidden left for this selection
          for (var k = 0; k < 3; k++) {
            expect(b.botWith(observer, Random(k)), a.botWith(observer, Random(k)),
                reason: 'mode=$mode seed=$seed plies=$plies');
          }
          checked++;
        }
      }
      expect(checked, greaterThan(10));
    }

    test('两国: bot(1) ignores hidden identities of seat 0', () {
      fairness('two', 2, 1, (p) => p.owner == 0);
    });
    test('两国: bot(0) ignores hidden identities of seat 1', () {
      fairness('two', 2, 0, (p) => p.owner == 1);
    });
    test('四国: bot(1) ignores hidden identities of seats 0 and 2', () {
      fairness('four', 4, 1, (p) => p.owner == 0);
      fairness('four', 4, 1, (p) => p.owner == 2);
    });
    test('翻翻棋: bot ignores face-down identities', () {
      fairness('flip', 2, 0, (p) => true, whole: true);
      fairness('flip', 2, 1, (p) => true, whole: true);
    });

    final geo = JunqiGeo.two;
    List<Map<String, dynamic>?> emptyBoard() => List<Map<String, dynamic>?>.filled(geo.nodes.length, null);

    test('belief: initial layout constraints', () {
      final g = makeJunqi('two');
      g.handle(0, {'type': 'ready'});
      g.handle(1, {'type': 'ready'});
      final m = JunqiMind(geo, false, 0, g.startViews[0]!);
      for (final id in geo.armNodes[1]) {
        final mask = m.maskAt(id);
        if (mask == null) continue;
        final n = geo.nodes[id];
        expect(mask & (1 << kFlag) != 0, n.kind == JKind.hq);
        expect(mask & (1 << kMine) != 0, n.lr >= 4);
        expect(mask & (1 << kBomb) != 0, n.lr >= 1);
      }
      for (final id in geo.armNodes[0]) {
        if (g.b[id] != null) expect(m.maskAt(id), 1 << g.b[id]!.rank);
      }
    });

    test('belief: battle results bound the rank', () {
      final bd = emptyBoard();
      final e1 = geo.at(4, 0)!, e2 = geo.at(1, 2)!, e3 = geo.at(4, 4)!;
      final my7 = geo.at(5, 0)!, my8 = geo.at(2, 2)!, my3 = geo.at(5, 4)!;
      for (final e in [e1, e2, e3]) {
        bd[e] = cell(1, -1);
      }
      bd[my7] = cell(0, 7);
      bd[my8] = cell(0, 8);
      bd[my3] = cell(0, 3);
      final m = JunqiMind(geo, false, 0, bd);
      m.update([
        {'t': 'mv', 's': 1, 'f': e1, 'to': my7, 'r': 'win'}, // beat 师长 -> 军长/司令
        {'t': 'mv', 's': 0, 'f': my8, 'to': e2, 'r': 'lose'}, // stationary kills 军长 -> 司令 or 地雷
        {'t': 'mv', 's': 1, 'f': e3, 'to': my3, 'r': 'tie'}, // tie with 连长 -> 连长 or 炸弹
      ]);
      expect(m.maskAt(my7), (1 << 8) | (1 << 9));
      expect(m.maskAt(e2), (1 << 9) | (1 << kMine));
      expect(m.maskAt(e3), isNull);
    });

    test('belief: moved pieces are not mines/flag; corner turn on rail -> 工兵', () {
      final bd = emptyBoard();
      final a = geo.at(1, 0)!, c = geo.at(0, 1)!;
      bd[a] = cell(1, -1);
      bd[c] = cell(1, -1);
      final m = JunqiMind(geo, false, 0, bd);
      m.update([
        {'t': 'mv', 's': 1, 'f': a, 'to': geo.at(5, 4), 'r': 'move'}, // down col 0 then along row 5
        {'t': 'mv', 's': 1, 'f': c, 'to': geo.at(0, 2), 'r': 'move'},
      ]);
      expect(m.maskAt(geo.at(5, 4)!), 1 << kEng);
      final cm = m.maskAt(geo.at(0, 2)!)!;
      expect(cm & ((1 << kMine) | (1 << kFlag)), 0);
      expect(cm & (1 << kCmd), isNot(0));
    });

    test('belief: 司令 death reveals flag and identifies the dead piece', () {
      final bd = emptyBoard();
      final e = geo.at(4, 2)!, hq = geo.at(0, 1)!, my = geo.at(5, 2)!;
      bd[e] = cell(1, -1);
      bd[hq] = cell(1, -1);
      bd[my] = cell(0, kBomb);
      final m = JunqiMind(geo, false, 0, bd);
      m.update([
        {'t': 'mv', 's': 1, 'f': e, 'to': my, 'r': 'tie'},
        {'t': 'flagshown', 'o': 1, 'n': hq},
      ]);
      expect(m.maskAt(hq), 1 << kFlag);
    });

    test('decide: expected value prefers good attacks', () {
      // my 司令 next to an unknown front-row piece (no bombs/mines there): attacking is +EV
      final bd = emptyBoard();
      final my = geo.at(6, 2)!, weak = geo.at(5, 2)!;
      bd[my] = cell(0, 9);
      bd[weak] = cell(1, -1);
      bd[geo.at(11, 1)!] = cell(0, kFlag);
      final m = JunqiMind(geo, false, 0, bd);
      final view = {
        'board': bd,
        'alive': [true, true],
        'moves': {
          '$my': [weak, geo.at(7, 2)]
        },
      };
      final a = m.decide(view, Random(1));
      expect(a['to'], weak);
    });

    Map<String, int> duel(String mode, int players, int n) {
      final stats = {'bot': 0, 'random': 0, 'draw': 0};
      for (var seed = 1; seed <= n; seed++) {
        final g = makeJunqi(mode, players: players, seed: seed);
        final r = Random(seed * 7);
        var guard = 0;
        while (!g.isOver && guard++ < 5000) {
          final s = g.waitingFor.first;
          g.handle(s, s % 2 == 0 ? g.botWith(s, r)! : randomAction(g, s, r));
        }
        final k = g.winners.isEmpty ? 'draw' : (g.winners.first % 2 == 0 ? 'bot' : 'random');
        stats[k] = stats[k]! + 1;
      }
      return stats;
    }

    test('self-play terminates (stats)', () {
      for (final (mode, players) in [('two', 2), ('four', 4), ('flip', 2)]) {
        final st = <String, int>{};
        var plies = 0;
        for (var seed = 1; seed <= 30; seed++) {
          final g = makeJunqi(mode, players: players, seed: seed);
          final r = Random(seed);
          while (!g.isOver) {
            final s = g.waitingFor.first;
            g.handle(s, g.botWith(s, r)!);
          }
          plies += g.plies;
          final k = g.winners.isEmpty ? 'draw' : 'team${g.winners.first % 2}';
          st[k] = (st[k] ?? 0) + 1;
        }
        print('$mode self-play x30: $st, avg plies ${plies ~/ 30}');
      }
    });

    for (final (mode, players) in [('two', 2), ('four', 4), ('flip', 2)]) {
      test('$mode: fair bot beats random play', () {
        final st = duel(mode, players, 20);
        print('$mode fair bot vs random: $st');
        expect(st['bot']!, greaterThanOrEqualTo(14));
      });
    }
  });

  group('animal chess', () {
    AnimalChess make() {
      final g = AnimalChess(GameSetup(players: 2, options: {}, names: ['A', 'B'], bots: [false, false]));
      g.start();
      return g;
    }

    int at(int r, int c) => AnimalChess.idx(r, c);

    test('lion jumps river, blocked by rat', () {
      final b = List.filled(63, -1);
      b[at(6, 1)] = 7;
      expect(AnimalChess.targets(b, at(6, 1)), contains(at(2, 1)));
      b[at(4, 1)] = 11;
      expect(AnimalChess.targets(b, at(6, 1)), isNot(contains(at(2, 1))));
      b[at(4, 1)] = -1;
      b[at(3, 0)] = 6;
      expect(AnimalChess.targets(b, at(3, 0)), contains(at(3, 3)));
    });
    test('rat vs elephant', () {
      final b = List.filled(63, -1);
      b[at(6, 0)] = 1;
      b[at(5, 0)] = 18;
      expect(AnimalChess.targets(b, at(6, 0)), contains(at(5, 0)));
      b[at(6, 0)] = 8;
      b[at(5, 0)] = 11;
      expect(AnimalChess.targets(b, at(6, 0)), isNot(contains(at(5, 0))));
      // rat in water cannot capture elephant on land
      final c = List.filled(63, -1);
      c[at(3, 1)] = 1;
      c[at(2, 1)] = 18;
      expect(AnimalChess.targets(c, at(3, 1)), isNot(contains(at(2, 1))));
    });
    test('traps and dens', () {
      final b = List.filled(63, -1);
      b[at(7, 2)] = 2; // cat
      b[at(7, 3)] = 18; // enemy elephant in our trap
      expect(AnimalChess.targets(b, at(7, 2)), contains(at(7, 3)));
      b[at(8, 2)] = 3;
      expect(AnimalChess.targets(b, at(8, 2)), isNot(contains(at(8, 3)))); // own den
      final g = make();
      g.cells.fillRange(0, 63, -1);
      g.cells[at(1, 3)] = 3;
      g.cells[at(8, 0)] = 11;
      g.handle(0, {'from': at(1, 3), 'to': at(0, 3)});
      expect(g.winner, 0);
    });
  });

  group('platform v3', () {
    AnimalChess makeAc() {
      final g = AnimalChess(GameSetup(players: 2, options: {}, names: ['A', 'B'], bots: [false, false]));
      g.host = SimHost();
      g.start();
      return g;
    }

    test('animalchess resign / draw / placings', () {
      var g = makeAc();
      expect(g.placings, isNull);
      expect(g.canResign, isTrue);
      expect(g.canDraw, isTrue);
      g.resign(0);
      expect(g.isOver, isTrue);
      expect(g.placings, [2, 1]);
      expect((g.host as SimHost).logs, contains('A 认输'));
      expect(g.canResign, isFalse);
      expect(g.canDraw, isFalse);

      g = makeAc();
      g.handle(0, {'from': AnimalChess.idx(6, 0), 'to': AnimalChess.idx(5, 0)});
      g.resign(0); // resign out of turn is allowed
      expect(g.placings, [2, 1]);

      g = makeAc();
      g.agreeDraw();
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 1]);

      g = makeAc();
      g.cells.fillRange(0, 63, -1);
      g.cells[AnimalChess.idx(7, 3)] = 3;
      g.cells[AnimalChess.idx(1, 0)] = 11;
      g.handle(0, {'from': AnimalChess.idx(7, 3), 'to': AnimalChess.idx(6, 3)});
      g.handle(1, {'from': AnimalChess.idx(1, 0), 'to': AnimalChess.idx(0, 0)});
      expect(g.placings, isNull);
      g.cells[AnimalChess.idx(1, 3)] = 3;
      g.handle(0, {'from': AnimalChess.idx(1, 3), 'to': AnimalChess.idx(0, 3)});
      expect(g.placings, [1, 2]);
    });

    test('animalchess bot levels return legal moves', () {
      for (final lvl in [0, 1, 2]) {
        final g = AnimalChess(GameSetup(players: 2, options: {}, names: ['A', 'B'], bots: [true, true], botLevel: lvl, rng: Random(3)));
        g.host = SimHost();
        g.start();
        for (var i = 0; i < 6 && !g.isOver; i++) {
          final sw = Stopwatch()..start();
          final a = g.runBot(g.turn)!;
          expect(sw.elapsedMilliseconds, lessThan(1500));
          g.handle(g.turn, a);
        }
      }
    });

    test('junqi two-player resign / draw / placings', () {
      var g = makeJunqi('two');
      expect(g.placings, isNull);
      expect(g.canResign, isTrue);
      g.resign(1); // during 布阵
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 2]);
      expect((g.host as SimHost).logs, contains('P1 认输'));

      g = makeJunqi('flip');
      g.resign(g.turn);
      expect(g.placings!.toSet(), {1, 2});

      g = makeJunqi('two');
      g.handle(0, {'type': 'ready'});
      g.handle(1, {'type': 'ready'});
      expect(g.canDraw, isTrue);
      g.agreeDraw();
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 1]);
      expect(g.canDraw, isFalse);
    });

    test('junqi four-player resign eliminates, team placings', () {
      final g = makeJunqi('four', players: 4);
      g.resign(1); // during 布阵
      expect(g.isOver, isFalse);
      expect(g.alive, [true, false, true, true]);
      expect(() => g.resign(1), throwsA(isA<GameError>()));
      for (final s in [0, 2, 3]) {
        g.handle(s, {'type': 'ready'});
      }
      expect(g.phase, 1);
      expect(g.turn, isNot(1));
      expect(g.b.any((p) => p != null && p.owner == 1), isFalse);
      g.resign(3);
      expect(g.isOver, isTrue);
      expect(g.placings, [1, 2, 1, 2]);
    });

    test('junqi bot levels', () {
      for (final mode in ['two', 'flip']) {
        for (final lvl in [0, 2]) {
          final g = Junqi(GameSetup(players: 2, options: {'mode': mode}, names: ['A', 'B'], bots: [true, true], botLevel: lvl, rng: Random(5)));
          g.host = SimHost();
          g.start();
          var guard = 0;
          while (!g.isOver && guard++ < 3000) {
            final s = g.waitingFor.first;
            g.handle(s, g.runBot(s)!);
          }
          expect(g.isOver, isTrue);
          expect(g.placings, isNotNull);
        }
      }
    });
  });

  test('military games: bots finish every variant', () {
    expect(runSims(militaryGames, n: 10), 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
