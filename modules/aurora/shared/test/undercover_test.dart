import 'dart:math';

import 'package:aurora_shared/games/undercover/defs.dart';
import 'package:aurora_shared/games/undercover/undercover.dart';
import 'package:aurora_shared/games/undercover/words/bank.dart';
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

Undercover make(int n, Map<String, dynamic> opts, {int seed = 3, int host = 0, AiService? ai}) {
  final e = undercoverGames.first.create(GameSetup(
    ai: ai,
    players: n,
    options: undercoverGames.first.normalizeOptions(opts),
    names: [for (var i = 0; i < n; i++) 'P$i'],
    bots: List.filled(n, false),
    hostSeat: host,
    rng: Random(seed),
  )) as Undercover;
  e.start();
  return e;
}

void main() {
  test('word bank: >= 10000 unique valid pairs', () {
    final bank = undercoverWordBank;
    expect(bank.length, greaterThanOrEqualTo(10000));
    final seen = <String>{};
    for (var i = 0; i < bank.length; i++) {
      final parts = bank[i].split('|');
      expect(parts.length, 2, reason: bank[i]);
      final (a, b) = undercoverPair(i);
      expect(a.trim(), isNotEmpty, reason: bank[i]);
      expect(b.trim(), isNotEmpty, reason: bank[i]);
      expect(a, isNot(b), reason: bank[i]);
      final key = (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';
      expect(seen.add(key), isTrue, reason: 'duplicate ${bank[i]}');
    }
  });

  test('auto undercover count', () {
    int spies(Undercover e) => e.roles.where((r) => r == 'spy').length;
    expect(spies(make(6, {})), 1);
    expect(spies(make(7, {})), 2);
    expect(spies(make(10, {})), 2);
    expect(spies(make(11, {})), 3);
    expect(spies(make(12, {'blank': true})), 3);
    expect(make(8, {'blank': true}).roles.where((r) => r == 'blank').length, 1);
  });

  test('view hides other words and roles', () {
    final e = make(6, {});
    final spy = e.roles.indexOf('spy');
    final civ = e.roles.indexOf('civ');
    final vs = e.view(spy);
    expect(vs['myWord'], e.spyWord);
    expect(vs['myRole'], isNull);
    expect(vs['civWord'], isNull);
    expect((vs['roles'] as List).every((r) => r == null), isTrue);
    expect(e.view(civ)['myWord'], e.civWord);
    expect(e.view(-1)['myWord'], isNull);
  });

  test('describe order, word leak rejected, vote & elimination', () {
    final e = make(5, {});
    expect(e.phase, 'describe');
    final first = e.waitingFor.single;
    expect(() => e.handle(first, {'type': 'describe', 'text': '就是${e.wordOf(first)}'}), throwsA(isA<GameError>()));
    for (var i = 0; i < 5; i++) {
      e.handle(e.waitingFor.single, {'type': 'verbal'});
    }
    expect(e.phase, 'vote');
    expect(e.waitingFor.length, 5);
    final spy = e.roles.indexOf('spy');
    for (var s = 0; s < 5; s++) {
      e.handle(s, {'type': 'vote', 'target': s == spy ? (spy + 1) % 5 : spy});
    }
    expect(e.alive[spy], isFalse);
    expect(e.isOver, isTrue);
    expect(e.winner, 'civ');
    expect(e.view(1)['civWord'], e.civWord);
  });

  test('tie → re-describe among tied → second tie nobody out', () {
    final e = make(4, {});
    for (var i = 0; i < 4; i++) {
      e.handle(e.waitingFor.single, {'type': 'verbal'});
    }
    // 0↔1, 2→0, 3→1 : 0 and 1 tie with 2 votes.
    e.handle(0, {'type': 'vote', 'target': 1});
    e.handle(1, {'type': 'vote', 'target': 0});
    e.handle(2, {'type': 'vote', 'target': 0});
    e.handle(3, {'type': 'vote', 'target': 1});
    expect(e.phase, 'describe');
    expect(e.tieBreak, isTrue);
    expect(e.order, [0, 1]);
    e.handle(0, {'type': 'verbal'});
    e.handle(1, {'type': 'verbal'});
    expect(e.phase, 'vote');
    expect(() => e.handle(2, {'type': 'vote', 'target': 3}), throwsA(isA<GameError>()));
    e.handle(0, {'type': 'vote', 'target': 1});
    e.handle(1, {'type': 'vote', 'target': 0});
    e.handle(2, {'type': 'vote', 'target': 0});
    e.handle(3, {'type': 'vote', 'target': 1});
    expect(e.alive.every((a) => a), isTrue);
    expect(e.round, 2);
    expect(e.phase, 'describe');
  });

  test('GM mode: GM enters words and sees everything', () {
    final e = make(6, {'source': 'gm'}, host: 2);
    expect(e.gm, 2);
    expect(e.phase, 'gm_setup');
    expect(e.waitingFor, [2]);
    expect(() => e.handle(2, {'type': 'words', 'civ': '猫', 'spy': '猫'}), throwsA(isA<GameError>()));
    e.handle(2, {'type': 'words', 'civ': '猫', 'spy': '狗'});
    expect(e.phase, 'describe');
    expect(e.waitingFor.contains(2), isFalse);
    final v = e.view(2);
    expect(v['civWord'], '猫');
    expect((v['roles'] as List).every((r) => r != null), isTrue);
    expect(undercoverGames.first.playerRange({'source': 'gm'}), (5, 12));
    expect(() => make(4, {'source': 'gm'}), throwsA(isA<GameError>()));
  });

  test('bots finish every variant', () {
    expect(runSims(undercoverGames, n: 30), 0);
  });

  test('server custom pairs are used (only-custom mode) and fall back when empty', () {
    for (final (lines, expectCustom) in [(['奶茶|咖啡'], true), (<String>[], false)]) {
      final setup = GameSetup(
        players: 4,
        options: {...undercoverGames.first.defaultOptions(), 'bank': 'custom'},
        names: ['a', 'b', 'c', 'd'],
        bots: List.filled(4, true),
        rng: Random(3),
        resources: {'undercover.pairs': lines},
      );
      final e = undercoverGames.first.create(setup);
      e.start();
      final words = {for (var s = 0; s < 4; s++) '${e.view(s)['word'] ?? ''}'};
      if (expectCustom) {
        expect(words.difference({'奶茶', '咖啡', ''}), isEmpty, reason: '$words');
      } else {
        expect(words.intersection({'奶茶', '咖啡'}), isEmpty);
      }
    }
  });

  group('AI', () {
    test('leaksWord', () {
      expect(Undercover.leaksWord('早上喝的牛奶', '牛奶'), isTrue);
      expect(Undercover.leaksWord('中秋赏月', '中秋节'), isTrue);
      expect(Undercover.leaksWord('很甜的饮品', '奶茶'), isFalse);
      expect(Undercover.leaksWord('随便', ''), isFalse);
    });

    test('rejects an AI description containing the word, uses a valid one', () {
      var reply = '';
      final e = make(5, {'ai': true}, ai: _Ai((_) => reply));
      final s = e.order[e.descIdx];
      final w = e.wordOf(s);
      reply = '我的词是$w，很常见';
      final a = e.runBot(s)!;
      expect(a['type'], 'describe');
      expect((a['text'] as String).contains(w), isFalse);
      expect(a['text'], isNot(reply));

      final e2 = make(5, {'ai': true}, ai: _Ai((_) => '「一种很常见的东西」'));
      final s2 = e2.order[e2.descIdx];
      final a2 = e2.runBot(s2)!;
      expect(a2, {'type': 'describe', 'text': '一种很常见的东西'});
      e2.handle(s2, a2);
      expect(e2.descs.last['t'], '一种很常见的东西');
    });

    test('AI vote validated', () {
      var reply = '';
      final e = make(4, {'ai': true}, ai: _Ai((_) => reply));
      while (e.phase == 'describe') {
        e.handle(e.order[e.descIdx], {'type': 'describe', 'text': '嗯${e.descIdx}'});
      }
      final v = e.aliveSeats.first;
      final t = e.aliveSeats.last;
      reply = '我投 {"target": $t}';
      expect(e.runBot(v), {'type': 'vote', 'target': t});
      final e2 = make(4, {'ai': true}, ai: _Ai((_) => '{"target": 0}'));
      while (e2.phase == 'describe') {
        e2.handle(e2.order[e2.descIdx], {'type': 'describe', 'text': '嗯${e2.descIdx}'});
      }
      final a = e2.runBot(0)!; // self-vote rejected -> heuristic
      expect(a['target'], isNot(0));
    });
  });

  test('placings', () {
    final e = make(4, {});
    expect(e.placings, isNull);
    e.phase = 'over';
    e.winners = [0, 2];
    expect(e.placings, [1, 2, 1, 2]);
  });
}
