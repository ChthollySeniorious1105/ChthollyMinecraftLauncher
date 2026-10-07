import 'dart:math';

import 'package:aurora_shared/games/words/defs.dart';
import 'package:aurora_shared/games/words/handle.dart';
import 'package:aurora_shared/games/words/handle_data.dart';
import 'package:aurora_shared/games/words/race.dart';
import 'package:aurora_shared/games/words/wordle.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(int n, {int rounds = 1, int level = 1, int seed = 3}) => GameSetup(
      players: n,
      options: {'rounds': rounds},
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, false),
      hostSeat: 0,
      rng: Random(seed),
      botLevel: level,
    );

T _start<T extends WordRace>(String id, int n, {int rounds = 1, int level = 1, int seed = 3}) {
  final d = wordsGames.firstWhere((d) => d.id == id);
  final e = d.create(_setup(n, rounds: rounds, level: level, seed: seed));
  e.start();
  return e as T;
}

void main() {
  test('runSims words', () {
    expect(runSims(wordsGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('data', () {
    test('sizes', () {
      expect(WordleDict.answers.length, greaterThan(1500));
      expect(WordleDict.guesses.length, greaterThan(8000));
      expect(WordleDict.answers.every(WordleDict.guesses.contains), isTrue);
      expect(HandleDict.all.length, 17914);
      expect(HandleDict.common.length, kHandleCommonCount);
      final yi = HandleDict.byWord['一心一意']!;
      expect(yi.fin, ['i', 'in', 'i', 'i']);
    });
  });

  group('wordle marking', () {
    test('basic', () {
      expect(wordleMark('crane', 'crane'), 'ggggg');
      expect(wordleMark('about', 'crane'), 'yxxxx');
      expect(wordleMark('nacre', 'crane'), 'yyyyg');
    });
    test('duplicates', () {
      // answer APPLE, guess PAPAL: P y, A y, P g, A x, L y
      expect(wordleMark('papal', 'apple'), 'yygxy');
      // only one E in answer: green takes it, other E grey
      expect(wordleMark('geese', 'those'), 'xxxgg');
      expect(wordleMark('eerie', 'those'), 'xxxxg');
      // two Ls in answer, three in guess
      expect(wordleMark('lolly', 'hello'), 'xyggx');
      expect(wordleMark('allee', 'eagle'), 'yyxyg');
    });
  });

  group('handle marking', () {
    test('layers', () {
      final m = handleMark('三心二意', '一心一意');
      expect(m.length, 16);
      // cells: [char, initial, final, tone]
      expect(m.substring(4, 8), 'gggg'); // 心
      expect(m.substring(12, 16), 'gggg'); // 意
      expect(m[0], 'x'); // 三 not in answer
      // data uses sandhi: 一心一意 = yì xīn yí yì, 三心二意 = sān xīn èr yì
      expect(m.substring(0, 4), 'xxxx'); // 三 s an 1
      expect(m[8], 'x'); // 二 not in answer
      expect(m[9], '-'); // zero initial
      expect(m[10], 'x'); // er
      expect(m[11], 'y'); // tone 4 present at answer pos 1
      expect(handleMark('一心一意', '一心一意'), 'g' * 16);
    });
  });

  group('wordle game', () {
    test('invalid guesses do not consume tries', () {
      final e = _start<WordleGame>('wordle', 2);
      expect(() => e.handle(0, {'type': 'guess', 'word': 'abc'}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'guess', 'word': 'zzzzz'}), throwsA(isA<GameError>()));
      expect(e.guesses[0], isEmpty);
      e.handle(0, {'type': 'guess', 'word': 'CRANE'});
      expect(e.guesses[0], ['crane']);
    });

    test('views hide words of others, scoring and placings', () {
      final e = _start<WordleGame>('wordle', 3);
      final ans = e.answer;
      final wrong = WordleDict.answers.firstWhere((w) => w != ans);
      e.handle(1, {'type': 'guess', 'word': wrong});
      final v0 = e.view(0);
      expect(v0['words'], isNull);
      expect(v0['answer'], isNull);
      expect((v0['marks'] as List)[1], hasLength(1));
      expect(v0['mine'], isEmpty);
      expect((e.view(1)['mine'] as List).first['w'], wrong);
      expect(e.view(-1).toString().contains(ans), isFalse);
      e.handle(1, {'type': 'guess', 'word': ans}); // 2 guesses, first solver
      expect(e.score[1], 5 + 1);
      e.handle(0, {'type': 'guess', 'word': ans}); // 1 guess
      expect(e.score[0], 6);
      expect(() => e.handle(0, {'type': 'guess', 'word': ans}), throwsA(isA<GameError>()));
      expect(e.waitingFor, [2]);
      e.handle(2, {'type': 'giveup'});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1, 3]);
      expect(e.view(2)['answer'], isNotNull);
    });

    test('six misses end the round', () {
      final e = _start<WordleGame>('wordle', 1, rounds: 3);
      final wrong = WordleDict.answers.where((w) => w != e.answer).take(6).toList();
      for (final w in wrong) {
        e.handle(0, {'type': 'guess', 'word': w});
      }
      expect(e.phase, 'reveal');
      expect(e.waitingFor, isEmpty);
      expect(e.score[0], 0);
    });

    test('bots solve using only own feedback', () {
      for (final lvl in [0, 1, 2]) {
        var solved = 0;
        for (var seed = 1; seed <= 10; seed++) {
          final e = _start<WordleGame>('wordle', 1, level: lvl, seed: seed);
          while (!e.isOver) {
            e.handle(0, e.runBot(0)!);
          }
          if (e.solvedIn[0] > 0) solved++;
        }
        if (lvl > 0) expect(solved, greaterThanOrEqualTo(8), reason: 'level $lvl');
      }
    });
  });

  group('handle game', () {
    test('validation', () {
      final e = _start<HandleGame>('handle', 2);
      expect(() => e.handle(0, {'type': 'guess', 'word': '一心'}), throwsA(isA<GameError>()));
      expect(() => e.handle(0, {'type': 'guess', 'word': '你好世界'}), throwsA(isA<GameError>()));
      e.handle(0, {'type': 'guess', 'word': ' 一心一意 '});
      expect(e.guesses[0], ['一心一意']);
      expect((e.view(0)['mine'] as List).first['py'], hasLength(4));
      expect(e.view(1)['mine'], isEmpty);
    });

    test('bots finish', () {
      for (final lvl in [1, 2]) {
        var solved = 0;
        for (var seed = 1; seed <= 6; seed++) {
          final e = _start<HandleGame>('handle', 1, level: lvl, seed: seed);
          while (!e.isOver) {
            e.handle(0, e.runBot(0)!);
          }
          if (e.solvedIn[0] > 0) solved++;
        }
        expect(solved, greaterThanOrEqualTo(5), reason: 'level $lvl');
      }
    });
  });
}
