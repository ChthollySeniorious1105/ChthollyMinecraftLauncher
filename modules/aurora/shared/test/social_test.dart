import 'dart:math';

import 'package:aurora_shared/games/social/avalon.dart';
import 'package:aurora_shared/games/social/catan.dart';
import 'package:aurora_shared/games/social/catan_geo.dart';
import 'package:aurora_shared/games/social/codenames.dart';
import 'package:aurora_shared/games/social/codenames_duet.dart';
import 'package:aurora_shared/games/social/defs.dart';
import 'package:aurora_shared/games/social/words.dart';
import 'package:aurora_shared/src/ai.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, [Map<String, dynamic> opts = const {}, int seed = 1]) => GameSetup(
    players: n,
    options: opts,
    names: [for (var i = 0; i < n; i++) 'P$i'],
    bots: List.filled(n, false),
    rng: Random(seed));

class _Ai extends FakeAi {
  String? Function(AiRequest) reply;
  _Ai(this.reply);
  @override
  String? completeNow(AiRequest req) {
    requests.add(req);
    return reply(req);
  }
}

Codenames _cn(String? Function(AiRequest) r) => Codenames(GameSetup(
    players: 4,
    options: const {'assign': 'alternate', 'ai': true},
    names: const ['P0', 'P1', 'P2', 'P3'],
    bots: List.filled(4, true),
    rng: Random(5),
    ai: _Ai(r)))
  ..start();

Catan _catan() => Catan(_setup(3))..start();

void main() {
  group('catan', () {
    test('geometry', () {
      final g = CatanGeo.instance;
      expect(g.nHex, 19);
      expect(g.nVert, 54);
      expect(g.nEdge, 72);
      expect(g.harborEdges.toSet().length, 9);
    });

    test('tile distribution and no adjacent 6/8 on random map', () {
      for (var seed = 1; seed < 20; seed++) {
        final c = Catan(_setup(4, {'map': 'random', 'vp': 10}, seed))..start();
        final counts = List.filled(5, 0);
        for (final r in c.tileRes) {
          if (r >= 0) counts[r]++;
        }
        expect(counts, [4, 3, 4, 4, 3]);
        expect(c.tileRes.where((r) => r < 0).length, 1);
        for (var h = 0; h < 19; h++) {
          if (c.tileNum[h] == 6 || c.tileNum[h] == 8) {
            for (final n in c.geo.hexNeighbors[h]) {
              expect(c.tileNum[n] == 6 || c.tileNum[n] == 8, false);
            }
          }
        }
        expect(c.harborType.where((t) => t == -1).length, 4);
      }
    });

    test('distance rule', () {
      final c = _catan();
      const v = 20;
      final s = c.turn;
      c.handle(s, {'type': 'settle', 'v': v});
      expect(c.distanceOk(v), false);
      for (final n in c.geo.vertNeighbors[v]) {
        expect(c.distanceOk(n), false);
      }
      c.handle(s, {'type': 'road', 'e': c.setupRoadSpots().first});
      final next = c.turn;
      expect(() => c.handle(next, {'type': 'settle', 'v': c.geo.vertNeighbors[v].first}), throwsA(isA<GameError>()));
      // two steps away is fine
      final far = c.geo.vertNeighbors[c.geo.vertNeighbors[v].first].firstWhere((x) => x != v);
      expect(c.distanceOk(far), true);
    });

    test('longest road broken by opponent settlement', () {
      final c = _catan();
      final g = c.geo;
      // 5 edges around the centre hex + one spur outward = simple path of 6
      final hv = g.hexVerts[9];
      int edge(int a, int b) => g.vertEdges[a].firstWhere((e) => g.edgeVerts[e].contains(b));
      final path = [for (var i = 0; i < 5; i++) edge(hv[i], hv[i + 1])];
      path.add(g.vertEdges[hv[5]].firstWhere((e) => !g.edgeVerts[e].contains(hv[0]) && !g.edgeVerts[e].contains(hv[4])));
      for (final e in path) {
        c.edgeOwner[e] = 0;
      }
      expect(c.longestRoadOf(0), 6);
      final v = hv[3];
      c.vertOwner[v] = 1;
      c.vertLevel[v] = 1;
      expect(c.longestRoadOf(0), 3);
      c.vertOwner[v] = 0; // own settlement doesn't break the road
      expect(c.longestRoadOf(0), 6);
      c.vertOwner[v] = -1;
      c.vertLevel[v] = 0;
      c.updateLongest();
      expect(c.longestRoad, 0);
      expect(c.roadLen[0], 6);
    });

    test('longest road with loop and spur', () {
      final c = _catan();
      final g = c.geo;
      for (var i = 0; i < 6; i++) {
        final a = g.hexVerts[9][i], b = g.hexVerts[9][(i + 1) % 6];
        c.edgeOwner[g.vertEdges[a].firstWhere((e) => g.edgeVerts[e].contains(b))] = 2;
      }
      expect(c.longestRoadOf(2), 6);
      final v = g.hexVerts[9][0];
      c.edgeOwner[g.vertEdges[v].firstWhere((e) => c.edgeOwner[e] < 0)] = 2;
      expect(c.longestRoadOf(2), 7);
    });

    test('dev card bought this turn is not playable; views hide hands', () {
      final c = _catan();
      while (c.phase == 'setup') {
        c.handle(c.turn, c.bot(c.turn)!);
      }
      final s = c.turn;
      c.handle(s, {'type': 'roll'});
      while (c.phase != 'main') {
        final w = c.waitingFor.first;
        c.handle(w, c.bot(w)!);
      }
      c.hands[s] = [0, 0, 1, 1, 1];
      c.devDeck.add('knight');
      c.handle(s, {'type': 'buyDev'});
      expect(() => c.handle(s, {'type': 'playDev', 'card': 'knight'}), throwsA(isA<GameError>()));
      final other = (s + 1) % 3;
      final v = c.view(other);
      expect((v['players'] as List)[s]['hand'], isNull);
      expect((v['players'] as List)[s]['devCount'], 1);
      expect(v['devNew'], isEmpty);
      expect(c.view(-1)['hand'], isNull);
    });
  });

  group('avalon', () {
    test('role distribution', () {
      const expected = {5: (3, 2), 6: (4, 2), 7: (4, 3), 8: (5, 3), 9: (6, 3), 10: (6, 4)};
      expected.forEach((n, gv) {
        for (final o in [(true, false, false), (true, true, true), (false, true, true), (false, false, false)]) {
          final r = avalonRoles(n, percival: o.$1, mordred: o.$2, oberon: o.$3);
          expect(r.length, n);
          expect(r.where(avalonIsEvil).length, gv.$2);
          expect(r.where((x) => !avalonIsEvil(x)).length, gv.$1);
          expect(r.contains('merlin'), true);
          expect(r.contains('assassin'), true);
          expect(r.contains('percival'), o.$1);
          expect(r.contains('morgana'), o.$1);
        }
      });
    });

    test('night knowledge is private and correct', () {
      final a = Avalon(_setup(7, {'percival': true, 'mordred': true, 'oberon': false}))..start();
      final merlin = a.roles.indexOf('merlin');
      final mordred = a.roles.indexOf('mordred');
      final k = a.knowledge(merlin);
      expect(k.containsKey('$mordred'), false);
      expect(k.length, 2);
      final perc = a.roles.indexOf('percival');
      expect(a.knowledge(perc).keys.toSet(), {'$merlin', '${a.roles.indexOf('morgana')}'});
      final servant = a.roles.indexOf('servant');
      expect(a.knowledge(servant), isEmpty);
      expect(a.view(servant)['roles'], isNull);
      expect(a.view(servant)['myRole'], 'servant');
      expect(a.knowledge(a.roles.indexOf('assassin')).length, 2);
    });

    test('good cannot fail; five rejections -> evil wins', () {
      final a = Avalon(_setup(5))..start();
      for (var i = 0; i < 5; i++) {
        a.handle(a.leader, {'type': 'propose', 'team': [0, 1]});
        for (var s = 0; s < 5; s++) {
          a.handle(s, {'type': 'vote', 'approve': false});
        }
      }
      expect(a.isOver, true);
      expect(a.winner, 'evil');
      final b = Avalon(_setup(5))..start();
      b.handle(b.leader, {'type': 'propose', 'team': [0, 1]});
      for (var s = 0; s < 5; s++) {
        b.handle(s, {'type': 'vote', 'approve': true});
      }
      expect(b.phase, 'quest');
      final good = [0, 1].where((s) => !avalonIsEvil(b.roles[s]));
      for (final s in good) {
        expect(() => b.handle(s, {'type': 'quest', 'success': false}), throwsA(isA<GameError>()));
      }
    });

    test('4th quest needs two fails with 7+ players', () {
      final a = Avalon(_setup(7))..start();
      expect(a.failsNeeded(3), 2);
      expect(a.failsNeeded(2), 1);
      final b = Avalon(_setup(6))..start();
      expect(b.failsNeeded(3), 1);
    });
  });

  group('codenames', () {
    test('word list and key card', () {
      expect(codenameWords.length, greaterThanOrEqualTo(400));
      final c = Codenames(_setup(6))..start();
      expect(c.key.where((k) => k == c.startTeam).length, 9);
      expect(c.key.where((k) => k == 1 - c.startTeam).length, 8);
      expect(c.key.where((k) => k == 2).length, 7);
      expect(c.key.where((k) => k == 3).length, 1);
      final op = c.operatives(0).first;
      expect((c.view(op)['key'] as List).every((k) => k == -1), true);
      expect((c.view(c.spymaster[0])['key'] as List).contains(-1), false);
      expect(() => c.handle(c.spymaster[c.team], {'type': 'clue', 'word': c.words[0], 'num': 1}),
          throwsA(isA<GameError>()));
    });
  });

  group('codenames_duet', () {
    test('key structure', () {
      for (var seed = 1; seed <= 50; seed++) {
        final g = CodenamesDuet(_setup(2, const {}, seed))..start();
        final a = g.keys[0], b = g.keys[1];
        int cnt(bool Function(int, int) f) => [for (var i = 0; i < 25; i++) if (f(a[i], b[i])) i].length;
        for (final k in [a, b]) {
          expect(k.where((x) => x == duetAgent).length, 9);
          expect(k.where((x) => x == duetAssassin).length, 3);
          expect(k.where((x) => x == duetBystander).length, 13);
        }
        expect(cnt((x, y) => x == duetAgent && y == duetAgent), 3);
        expect(cnt((x, y) => x == duetAssassin && y == duetAssassin), 1);
        expect(cnt((x, y) => x == duetAssassin && y == duetAgent), 1);
        expect(cnt((x, y) => x == duetAssassin && y == duetBystander), 1);
        expect(cnt((x, y) => y == duetAssassin && x == duetAgent), 1);
        expect(cnt((x, y) => y == duetAssassin && x == duetBystander), 1);
        expect(g.totalAgents, 15);
        expect(g.words.toSet().length, 25);
      }
    });

    test('views hide the other key', () {
      final g = CodenamesDuet(_setup(4))..start();
      expect(g.view(0)['myKey'], g.keys[0]);
      expect(g.view(2)['myKey'], g.keys[0]);
      expect(g.view(1)['myKey'], g.keys[1]);
      expect(g.view(0)['keys'], isNull);
      expect(g.view(-1)['myKey'], isNull);
      expect(g.view(-1)['keys'], isNull);
    });

    test('clue validation and guessing flow', () {
      final g = CodenamesDuet(_setup(2, {'tokens': 9}))..start();
      final giver = g.giver, guesser = 1 - giver;
      expect(g.waitingFor, [giver]);
      expect(() => g.handle(guesser, {'type': 'clue', 'word': '天空', 'num': 1}), throwsA(isA<GameError>()));
      expect(() => g.handle(giver, {'type': 'clue', 'word': '', 'num': 1}), throwsA(isA<GameError>()));
      expect(() => g.handle(giver, {'type': 'clue', 'word': g.words[3], 'num': 1}), throwsA(isA<GameError>()));
      expect(() => g.handle(giver, {'type': 'clue', 'word': '一二三四五六七八九十十一十二', 'num': 1}), throwsA(isA<GameError>()));
      g.handle(giver, {'type': 'clue', 'word': 'ZZZ', 'num': duetInfinite});
      expect(g.waitingFor, [guesser]);
      expect(() => g.handle(guesser, {'type': 'pass'}), throwsA(isA<GameError>()));
      final key = g.keys[giver];
      final agent = key.indexOf(duetAgent);
      g.handle(guesser, {'type': 'guess', 'card': agent});
      expect(g.found[agent], true);
      expect(g.phase, 'guess');
      final by = key.indexOf(duetBystander);
      g.handle(guesser, {'type': 'guess', 'card': by});
      expect(g.byMark[guesser][by], true);
      expect(g.tokens, 8);
      expect(g.phase, 'clue');
      expect(g.giver, guesser);
    });

    test('assassin loses', () {
      final g = CodenamesDuet(_setup(2))..start();
      final giver = g.giver;
      g.handle(giver, {'type': 'clue', 'word': 'ZZZ', 'num': 1});
      g.handle(1 - giver, {'type': 'guess', 'card': g.keys[giver].indexOf(duetAssassin)});
      expect(g.isOver, true);
      expect(g.won, false);
    });

    test('sudden death after tokens run out', () {
      final g = CodenamesDuet(_setup(2, {'tokens': 7}))..start();
      while (g.phase != 'sudden') {
        final giver = g.giver;
        g.handle(giver, {'type': 'clue', 'word': 'ZZZ', 'num': 1});
        final i = [for (var i = 0; i < 25; i++) if (g.keys[giver][i] == duetAgent && !g.found[i]) i].first;
        g.handle(1 - giver, {'type': 'guess', 'card': i});
        g.handle(1 - giver, {'type': 'pass'});
      }
      expect(g.tokens, 0);
      expect(g.waitingFor, [0, 1]);
      expect(() => g.handle(0, {'type': 'clue', 'word': 'ZZZ', 'num': 1}), throwsA(isA<GameError>()));
      final i = [for (var i = 0; i < 25; i++) if (g.keys[1][i] == duetAgent && !g.found[i]) i].first;
      g.handle(0, {'type': 'guess', 'card': i});
      expect(g.found[i], true);
      final bad = [for (var i = 0; i < 25; i++) if (g.keys[0][i] != duetAgent && !g.found[i]) i].first;
      g.handle(1, {'type': 'guess', 'card': bad});
      expect(g.isOver, true);
      expect(g.won, false);
    });

    test('win when all 15 agents found', () {
      final g = CodenamesDuet(_setup(2, {'tokens': 11}))..start();
      while (!g.isOver) {
        final giver = g.giver;
        g.handle(giver, {'type': 'clue', 'word': 'ZZZ', 'num': 9});
        for (var i = 0; i < 25 && !g.isOver && g.phase == 'guess'; i++) {
          if (g.keys[giver][i] == duetAgent && !g.found[i]) g.handle(1 - giver, {'type': 'guess', 'card': i});
        }
      }
      expect(g.won, true);
      expect(g.foundCount, 15);
    });
  });

  group('AI', () {
    test('clue validation', () {
      const board = ['苹果', '大象', '火车'];
      expect(Codenames.validAiClue('水果', board), isTrue);
      expect(Codenames.validAiClue('苹果', board), isFalse);
      expect(Codenames.validAiClue('果', board), isFalse); // substring of 苹果
      expect(Codenames.validAiClue('火车站', board), isFalse); // contains 火车
      expect(Codenames.validAiClue('水 果', board), isFalse);
      expect(Codenames.validAiClue('水果2', board), isFalse);
      expect(Codenames.validAiClue('', board), isFalse);
    });

    test('AI spymaster: board word rejected, valid clue used', () {
      late Codenames e;
      e = _cn((_) => '{"clue":"${e.words[0]}","number":2}');
      final sm = e.spymaster[e.team];
      final a = e.runBot(sm)!;
      expect(a['type'], 'clue');
      expect(a['word'], isNot(e.words[0]));
      expect(e.clueProblem(a['word'] as String), isNull);

      late Codenames e2;
      e2 = _cn((_) => '{"clue":"宇宙飞行","number":2,"targets":[]}');
      final a2 = e2.runBot(e2.spymaster[e2.team])!;
      expect(a2['word'], '宇宙飞行');
      expect(a2['num'], 2);
      e2.handle(e2.spymaster[e2.team], a2);
      expect(e2.phase, 'guess');
    });

    test('AI guesser pick submitted', () {
      late Codenames e;
      var reply = '{"clue":"宇宙飞行","number":1}';
      e = _cn((_) => reply);
      e.handle(e.spymaster[e.team], e.runBot(e.spymaster[e.team])!);
      final w = e.words[7];
      reply = '{"words":["$w"]}';
      final op = e.operatives(e.team).first;
      expect(e.runBot(op), {'type': 'guess', 'card': 7});
    });
  });

  test('placings', () {
    final c = Codenames(_setup(4))..start();
    expect(c.placings, isNull);
    c.winner = 1;
    c.phase = 'over';
    expect(c.placings, [for (var s = 0; s < 4; s++) c.teamOf[s] == 1 ? 1 : 2]);
    final d = CodenamesDuet(_setup(2))..start();
    d.phase = 'over';
    expect(d.placings, [1, 1]);
  });

  test('social games: bots finish every variant', () {
    expect(runSims(socialGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
