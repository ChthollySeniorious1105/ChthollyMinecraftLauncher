import 'dart:math';

import 'package:aurora_shared/games/onenight/defs.dart';
import 'package:aurora_shared/games/onenight/onenight.dart';
import 'package:aurora_shared/games/onenight/resistance.dart';
import 'package:aurora_shared/games/onenight/spyfall.dart';
import 'package:aurora_shared/games/onenight/spyfall_data.dart';
import 'package:aurora_shared/games/onenight/util.dart';
import 'package:aurora_shared/src/ai.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

class _Ai extends FakeAi {
  String? Function(AiRequest) reply;
  _Ai(this.reply);
  @override
  String? completeNow(AiRequest req) {
    requests.add(req);
    return reply(req);
  }
}

GameSetup _setup(int n, [Map<String, dynamic> opts = const {}, int seed = 1, AiService? ai]) => GameSetup(
      ai: ai,
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      rng: Random(seed),
    );

void main() {
  group('onenight', () {
    OneNight game(List<String> deck) {
      final e = OneNight(_setup(deck.length - 3))..host = SimHost();
      e.start();
      e.dealt = List.of(deck);
      e.cards = List.of(deck);
      return e;
    }

    test('swap resolution follows wake order (robber, troublemaker, drunk)', () {
      // seats: 0 robber, 1 troublemaker, 2 drunk, 3 werewolf, 4 insomniac ; center: seer villager tanner
      final e = game(['robber', 'troublemaker', 'drunk', 'werewolf', 'insomniac', 'seer', 'villager', 'tanner']);
      // Submit in reverse order to prove submission order doesn't matter.
      e.handle(4, {'type': 'night'});
      e.handle(2, {'type': 'night', 'center': 2});
      e.handle(1, {'type': 'night', 'targets': [0, 4]});
      e.handle(3, {'type': 'night', 'center': 0});
      expect(e.phase, 'night');
      e.handle(0, {'type': 'night', 'target': 3});
      expect(e.phase, 'day');
      // robber<->3: 0=werewolf 3=robber ; troublemaker 0<->4: 0=insomniac 4=werewolf ; drunk<->c2: 2=tanner
      expect(e.cards.sublist(0, 5), ['insomniac', 'troublemaker', 'tanner', 'robber', 'werewolf']);
      expect(e.cards.sublist(5), ['seer', 'villager', 'drunk']);
      // robber saw werewolf (the card at robbing time), insomniac sees final card
      expect(e.seen[0]!.single['role'], 'werewolf');
      expect(e.seen[4]!.single['role'], 'werewolf');
      // lone wolf peek
      expect(e.seen[3]!.single['role'], 'seer');
      // hidden info: seat 1 must not see others' cards
      final v1 = e.view(1);
      expect(v1['final'], isNull);
      expect(v1['wolves'], isNull);
      expect(e.view(-1)['myCard'], isNull);
    });

    test('invalid night input rejected', () {
      final e = game(['seer', 'troublemaker', 'villager', 'werewolf', 'drunk', 'robber']);
      expect(() => e.handle(0, {'type': 'night', 'target': 0}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'night', 'center': [1, 1]}), throwsA(isA<GameError>()));
      expect(() => e.handle(1, {'type': 'night', 'targets': [1, 2]}), throwsA(isA<GameError>()));
      expect(() => e.handle(1, {'type': 'night', 'targets': [2, 99]}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'night', 'center': [0, 2]});
      expect(e.seen[0]!.map((x) => x['role']), ['werewolf', 'robber']);
    });

    test('win conditions', () {
      // wolf killed -> village
      var r = onenightOutcome(['werewolf', 'villager', 'seer'], [0]);
      expect(r.$2, ['village']);
      expect(r.$1, [false, true, true]);
      // no wolf dies -> wolf team
      r = onenightOutcome(['werewolf', 'minion', 'seer'], [2]);
      expect(r.$2, ['wolf']);
      expect(r.$1, [true, true, false]);
      // tanner dies, no wolf dies -> only tanner
      r = onenightOutcome(['werewolf', 'tanner', 'seer'], [1]);
      expect(r.$2, ['tanner']);
      expect(r.$1, [false, true, false]);
      // tanner + wolf die -> village and tanner
      r = onenightOutcome(['werewolf', 'tanner', 'seer'], [0, 1]);
      expect(r.$2, ['village', 'tanner']);
      // no wolves in play, nobody dies -> village
      r = onenightOutcome(['villager', 'seer', 'robber'], []);
      expect(r.$2, ['village']);
      // no wolves, someone dies -> everyone loses
      r = onenightOutcome(['villager', 'seer', 'robber'], [1]);
      expect(r.$2, isEmpty);
      // no wolves, minion alive, other dies -> minion wins
      r = onenightOutcome(['minion', 'seer', 'robber'], [1]);
      expect(r.$2, ['wolf']);
      expect(r.$1, [true, false, false]);
    });

    test('hunter takes his vote target down', () {
      final e = game(['hunter', 'werewolf', 'villager', 'villager', 'seer', 'robber', 'drunk']);
      for (var s = 0; s < 4; s++) {
        e.handle(s, {'type': 'night'});
      }
      for (var s = 0; s < 4; s++) {
        e.handle(s, {'type': 'ready'});
      }
      expect(e.phase, 'vote');
      e.handle(0, {'type': 'vote', 'target': 1}); // hunter votes wolf
      e.handle(1, {'type': 'vote', 'target': 0});
      e.handle(2, {'type': 'vote', 'target': 0});
      e.handle(3, {'type': 'vote', 'target': 2});
      expect(e.deaths, [0, 1]);
      expect(e.winTeams, ['village']);
      expect(e.view(2)['final'], isNotNull);
    });

    test('tie with one vote each kills nobody', () {
      final e = game(['werewolf', 'villager', 'seer', 'robber', 'drunk', 'villager']);
      for (var s = 0; s < 3; s++) {
        e.handle(s, {'type': 'night', if (s == 0) 'center': 1, if (s == 2) 'target': 1});
      }
      for (var s = 0; s < 3; s++) {
        e.handle(s, {'type': 'ready'});
      }
      e.handle(0, {'type': 'vote', 'target': 1});
      e.handle(1, {'type': 'vote', 'target': 2});
      e.handle(2, {'type': 'vote', 'target': 0});
      expect(e.deaths, isEmpty);
      expect(e.winTeams, ['wolf']);
    });

    test('decks', () {
      for (final p in onPresets.keys) {
        for (var n = 3; n <= 10; n++) {
          final d = onenightDeck(p, n);
          expect(d.length, n + 3);
          expect(d.where((r) => r == 'werewolf').length, 2);
        }
      }
    });
  });

  group('resistance', () {
    test('tables', () {
      expect(resistanceSpyCount, {5: 2, 6: 2, 7: 3, 8: 3, 9: 3, 10: 4});
      expect(resistanceMissionSizes[5], [2, 3, 2, 3, 3]);
      expect(resistanceMissionSizes[7], [2, 3, 3, 4, 4]);
      expect(resistanceMissionSizes[10], [3, 4, 4, 5, 5]);
      for (var n = 5; n <= 10; n++) {
        final e = Resistance(_setup(n))..host = SimHost();
        e.start();
        expect(e.spy.where((x) => x).length, resistanceSpyCount[n]);
        expect(e.failsNeeded(3), n >= 7 ? 2 : 1);
        expect(e.failsNeeded(2), 1);
      }
    });

    test('mission flow, spy info hidden, 4th mission needs 2 fails at 7p', () {
      final e = Resistance(_setup(7))..host = SimHost();
      e.start();
      final spies = [for (var s = 0; s < 7; s++) if (e.spy[s]) s];
      final res = [for (var s = 0; s < 7; s++) if (!e.spy[s]) s];
      expect(e.view(res.first)['spies'], isNull);
      expect(e.view(spies.first)['spies'], spies);
      expect(e.view(-1)['spies'], isNull);
      e.mission = 3;
      final team = [spies[0], res[0], res[1], res[2]]..sort();
      e.handle(e.leader, {'type': 'propose', 'team': team});
      for (var s = 0; s < 7; s++) {
        e.handle(s, {'type': 'vote', 'approve': true});
      }
      expect(e.phase, 'mission');
      expect(() => e.handle(res[0], {'type': 'mission', 'success': false}), throwsA(isA<GameError>()));
      for (final s in team) {
        e.handle(s, {'type': 'mission', 'success': !e.spy[s] || false});
      }
      expect(e.results[3], 1); // one fail isn't enough
    });

    test('five rejections -> spies win', () {
      final e = Resistance(_setup(5))..host = SimHost();
      e.start();
      for (var i = 0; i < 5; i++) {
        e.handle(e.leader, {'type': 'propose', 'team': [0, 1]});
        for (var s = 0; s < 5; s++) {
          e.handle(s, {'type': 'vote', 'approve': false});
        }
      }
      expect(e.winner, 'spy');
      expect(e.isOver, true);
    });
  });

  group('spyfall', () {
    test('locations data', () {
      expect(spyfallLocations.length, greaterThanOrEqualTo(40));
      for (final r in spyfallLocations.values) {
        expect(r.length, greaterThanOrEqualTo(6));
      }
    });

    test('location hidden from spy and spectators; spy guess wins', () {
      final e = Spyfall(_setup(5, {'rounds': 1}))..host = SimHost();
      e.start();
      final spy = e.spy;
      expect(e.view(spy)['location'], isNull);
      expect(e.view(spy)['amSpy'], true);
      expect(e.view(-1)['location'], isNull);
      expect(e.view(-1)['myRole'], isNull);
      final other = (spy + 1) % 5;
      expect(e.view(other)['location'], e.location);
      expect(e.view(other)['myRole'], isNot('间谍'));
      expect(() => e.handle(other, {'type': 'guess', 'location': e.location}), throwsA(isA<GameError>()));
      expect(() => e.handle(spy, {'type': 'guess', 'location': '不存在'}), throwsA(isA<GameError>()));
      e.handle(spy, {'type': 'guess', 'location': e.location});
      expect(e.phase, 'roundEnd');
      expect(e.scores[spy], 4);
      expect(e.view(other)['result']['spyWins'], true);
    });

    test('wrong guess and unanimous accusation', () {
      final e = Spyfall(_setup(4, {'rounds': 3}))..host = SimHost();
      e.start();
      final wrong = spyfallLocationNames.firstWhere((l) => l != e.location);
      e.handle(e.spy, {'type': 'guess', 'location': wrong});
      expect(e.result!['spyWins'], false);
      for (var s = 0; s < 4; s++) {
        e.handle(s, {'type': 'continue'});
      }
      expect(e.round, 2);
      final spy = e.spy;
      final acc = (spy + 1) % 4;
      final before = e.scores[acc];
      e.handle(acc, {'type': 'accuse', 'target': spy});
      expect(e.phase, 'accuse');
      expect(() => e.handle(spy, {'type': 'accuseVote', 'agree': true}), throwsA(isA<GameError>()));
      for (var s = 0; s < 4; s++) {
        if (s != spy && s != acc) e.handle(s, {'type': 'accuseVote', 'agree': true});
      }
      expect(e.result!['how'], 'caught');
      expect(e.scores[acc], before + 2);
    });

    test('q&a text sanitized and capped', () {
      final e = Spyfall(_setup(3))..host = SimHost();
      e.start();
      final t = (e.asker + 1) % 3;
      e.handle(e.asker, {'type': 'ask', 'target': t, 'text': '${String.fromCharCode(0x202E)}你好\u0000${'啊' * 200}'});
      final q = e.feed.last['q'] as String;
      expect(q.runes.length, 80);
      expect(q.startsWith('你好'), true);
      expect(() => e.handle(t, {'type': 'answer', 'text': '   '}), throwsA(isA<GameError>()));
    });
  });

  group('v3', () {
    test('onenight voice: nobody at night, everyone by day', () {
      final e = OneNight(_setup(5))..host = SimHost();
      e.start();
      expect(e.voiceListeners(0), isEmpty);
      expect(e.voiceListeners(3), isEmpty);
      for (var s = 0; s < 5; s++) {
        e.handle(s, e.runBot(s)!);
      }
      expect(e.phase, 'day');
      expect(e.voiceListeners(0), isNull);
    });

    test('onenight AI day speech is used, only own info in the prompt', () {
      final ai = _Ai((_) => '我是村民，昨晚什么都没看到。');
      final e = OneNight(_setup(5, {'ai': true}, 1, ai))..host = SimHost();
      e.start();
      for (var s = 0; s < 5; s++) {
        e.handle(s, e.runBot(s)!);
      }
      final a = e.runBot(2)!;
      expect(a, {'type': 'say', 'text': '我是村民，昨晚什么都没看到'});
      e.handle(2, a);
      expect(e.talk.single['t'], '我是村民，昨晚什么都没看到');
      expect(ai.requests.last.prompt, isNot(contains('nightLog')));
      for (final i in e.info[0]!) {
        expect(ai.requests.last.prompt.contains(i), e.info[2]!.contains(i));
      }
      // junk falls back to "ready"
      final e2 = OneNight(_setup(5, {'ai': true}, 1, _Ai((_) => '{"x":1}')))..host = SimHost();
      e2.start();
      for (var s = 0; s < 5; s++) {
        e2.handle(s, e2.runBot(s)!);
      }
      expect(e2.runBot(1), {'type': 'ready'});
    });

    test('spyfall spy location guess validated', () {
      expect(Spyfall.parseSpyLocation('{"location":"医院"}'), '医院');
      expect(Spyfall.parseSpyLocation('医院'), '医院');
      expect(Spyfall.parseSpyLocation('{"location":"月球"}'), isNull);
      expect(Spyfall.parseSpyLocation('我猜是学校吧'), isNull);
      expect(Spyfall.parseSpyLocation(null), isNull);
    });

    test('spyfall AI answer never names the location (non-spy)', () {
      late Spyfall e;
      e = Spyfall(_setup(4, {'ai': true}, 3, _Ai((_) => '我们在${e.location}呀')))..host = SimHost();
      e.start();
      final asker = e.asker;
      final target = (asker + 1) % 4;
      e.handle(asker, {'type': 'ask', 'target': target, 'text': '你来这里干嘛？'});
      final a = e.runBot(target)!;
      expect(a['type'], 'answer');
      if (target != e.spy) expect((a['text'] as String).contains(e.location), isFalse);
    });

    test('placings', () {
      final r = Resistance(_setup(5))..host = SimHost();
      r.start();
      r.winner = 'spy';
      r.phase = 'over';
      expect(r.placings, [for (var s = 0; s < 5; s++) r.spy[s] ? 1 : 2]);
    });
  });

  test('simulations', () {
    claimCoverEnabled = false;
    expect(runSims(onenightGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
