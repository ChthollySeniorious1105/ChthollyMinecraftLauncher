import 'dart:math';

import 'package:aurora_shared/games/party2/bullscows.dart';
import 'package:aurora_shared/games/party2/decrypto.dart';
import 'package:aurora_shared/games/party2/decrypto_words.dart';
import 'package:aurora_shared/games/party2/defs.dart';
import 'package:aurora_shared/games/party2/halligalli.dart';
import 'package:aurora_shared/games/party2/turtlesoup.dart';
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

GameSetup _setup(int n, Map<String, dynamic> opts, {List<bool>? bots, int host = 0, Map<String, Object> res = const {}, AiService? ai}) =>
    GameSetup(
      ai: ai,
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: bots ?? List.filled(n, false),
      hostSeat: host,
      rng: Random(3),
      resources: res,
    );

void main() {
  group('德国心脏病', () {
    test('five detection', () {
      expect(HalliGalli.fruitTotals([[1], [3], [12]]), [4, 2, 0, 0]);
      expect(HalliGalli.fruitTotals([[1, 2], [3], [12, 5]]), [10, 0, 0, 0]);
      expect(HalliGalli.fruitTotals([[2], [3], [32]]).indexOf(5), 0);
      expect(HalliGalli.fullDeck().length, 56);
    });

    test('correct ring collects pile, wrong ring pays each', () {
      final e = HalliGalli(_setup(3, {'maxFlips': 600}))..start();
      e.up = [[2], [3], [14]];
      final before = e.total(1);
      e.handle(1, {'type': 'ring', 'ver': e.ver});
      expect(e.total(1), before + 2); // own face-up card was already counted
      expect(e.up.every((p) => p.isEmpty), isTrue);
      expect(e.turn, 1);

      e.up = [[1], [], []];
      final t0 = e.total(0), t1 = e.total(1), t2 = e.total(2);
      e.handle(0, {'type': 'ring', 'ver': e.ver});
      expect(e.total(0), t0 - 2);
      expect(e.total(1), t1 + 1);
      expect(e.total(2), t2 + 1);
      expect(() => e.handle(2, {'type': 'ring', 'ver': e.ver - 1}), throwsA(isA<GameError>()));
    });
  });

  group('猜数字', () {
    test('feedback', () {
      expect(BullsCows.score('1234', '1234'), (4, 0));
      expect(BullsCows.score('1234', '4321'), (0, 4));
      expect(BullsCows.score('1234', '1356'), (1, 1));
      expect(BullsCows.score('5678', '1234'), (0, 0));
      expect(BullsCows.validate('1123', 4), isNotNull);
      expect(BullsCows.validate('123', 4), isNotNull);
      expect(BullsCows.validate('0123', 4), isNull);
    });

    test('solver cracks within 10 guesses', () {
      final rng = Random(5);
      for (var k = 0; k < 10; k++) {
        final e = BullsCows(_setup(2, {'digits': 4}, bots: [true, true]))..start();
        final all = BullsCows.allCodes(4);
        e.handle(0, {'type': 'secret', 'code': '0123'});
        e.handle(1, {'type': 'secret', 'code': all[rng.nextInt(all.length)]});
        var n = 0;
        while (!e.isOver && n < 40) {
          e.handle(e.turn, e.bot(e.turn)!);
          n++;
        }
        expect(e.isOver, isTrue);
        expect(n, lessThanOrEqualTo(20));
      }
    });

    test('secrets hidden', () {
      final e = BullsCows(_setup(2, {'digits': 3}))..start();
      e.handle(0, {'type': 'secret', 'code': '012'});
      e.handle(1, {'type': 'secret', 'code': '345'});
      expect((e.view(0)['secrets'] as List)[1], isNull);
      expect(e.view(1)['mySecret'], '345');
      expect((e.view(-1)['secrets'] as List).every((x) => x == null), isTrue);
    });
  });

  group('海龟汤', () {
    test('built-in bank size & parsing', () {
      expect(soupStories.length, greaterThanOrEqualTo(60));
      expect(soupStories.map((s) => s.title).toSet().length, soupStories.length);
      final p = parseSoupLines(['# 注释', '标题一|汤面一|汤底一', '坏行|只有两段', '标题二｜汤面二｜汤底|含竖线', '', '标题一|重复|重复']);
      expect(p.length, 2);
      expect(p[1].bottom, '汤底|含竖线');
    });

    test('GM flow and hidden 汤底', () {
      final e = TurtleSoup(_setup(3, {'source': 'custom', 'rounds': 1, 'cap': 30}, host: 1,
          res: {'turtlesoup.stories': ['门|他推开门|其实是风']}))..start();
      expect(e.gm, 1);
      expect(e.phase, 'prepare');
      expect(e.view(0)['story'], isNull);
      expect((e.view(1)['story'] as Map)['bottom'], '其实是风');
      expect(() => e.handle(0, {'type': 'begin'}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'begin'});
      expect((e.view(0)['story'] as Map).containsKey('bottom'), isFalse);
      expect((e.view(-1)['story'] as Map).containsKey('bottom'), isFalse);
      expect((e.view(0)['story'] as Map)['surface'], '他推开门');

      e.handle(0, {'type': 'ask', 'text': '和天气有关吗？'});
      expect(() => e.handle(0, {'type': 'ask', 'text': '再问'}), throwsA(isA<GameError>()));
      expect(e.waitingFor, contains(1));
      final id = (e.view(2)['items'] as List).first['id'];
      expect(() => e.handle(1, {'type': 'answer', 'id': id, 'answer': 'maybe'}), throwsA(isA<GameError>()));
      e.handle(1, {'type': 'answer', 'id': id, 'answer': 'yes'});
      expect((e.view(2)['items'] as List).first['a'], 'yes');

      e.handle(2, {'type': 'guess', 'text': '是风吹开的'});
      final gid = (e.view(0)['items'] as List).last['id'];
      e.handle(1, {'type': 'answer', 'id': gid, 'answer': 'right'});
      expect(e.phase, 'reveal');
      expect((e.view(0)['story'] as Map)['bottom'], '其实是风');
      expect(e.solver, 2);
      e.handle(1, {'type': 'next'});
      expect(e.isOver, isTrue);
    });

    test('GM compose + question cap terminates', () {
      final e = TurtleSoup(_setup(3, {'source': 'gm', 'cap': 30}))..start();
      expect(e.story, isNull);
      e.handle(0, {'type': 'compose', 'title': 'T', 'surface': 'S', 'bottom': 'B'});
      expect(e.phase, 'ask');
      for (var i = 0; i < 30; i++) {
        final s = 1 + i % 2;
        e.handle(s, {'type': 'ask', 'text': 'q$i'});
        e.handle(0, {'type': 'answer', 'id': e.items.last['id'], 'answer': 'no'});
      }
      expect(() => e.handle(1, {'type': 'ask', 'text': 'more'}), throwsA(isA<GameError>()));
      for (var i = 0; i < 6; i++) {
        e.handle(1 + i % 2, {'type': 'guess', 'text': 'g$i'});
        if (e.phase == 'ask') e.handle(0, {'type': 'answer', 'id': e.items.last['id'], 'answer': 'wrong'});
      }
      expect(e.phase, 'reveal');
    });
  });

  group('截码战', () {
    test('word bank and codes', () {
      expect(decryptoWords.length, greaterThanOrEqualTo(400));
      expect(decryptoWords.toSet().length, decryptoWords.length);
      expect(Decrypto.allCodes.length, 24);
      expect(() => Decrypto.parseCode([1, 1, 2]), throwsA(isA<GameError>()));
      expect(() => Decrypto.parseCode([0, 1, 2]), throwsA(isA<GameError>()));
      expect(Decrypto.parseCode([4, 1, 2]), [4, 1, 2]);
      expect(parseDecryptoLines(['# x', '密室', '密室', '  灯 塔 ', '超级长的一个词语啊啊']), ['密室', '灯塔']);
    });

    test('hidden info', () {
      final e = Decrypto(_setup(4, {'words': 'builtin'}))..start();
      final v0 = e.view(0), v1 = e.view(1), vs = e.view(-1);
      expect((v0['keywords'] as List)[0], hasLength(4));
      expect((v0['keywords'] as List)[1], isNull);
      expect((v1['keywords'] as List)[0], isNull);
      expect((vs['keywords'] as List).every((x) => x == null), isTrue);
      final enc0 = e.encryptor(0);
      expect(e.view(enc0)['myCode'], e.code[0]);
      for (var s = 0; s < 4; s++) {
        if (s != enc0) expect(e.view(s)['myCode'], anyOf(isNull, e.code[1]));
      }
      expect(e.view(2 - enc0)['myCode'], isNull); // teammate of team 0's encryptor
      // clue text hidden from the other team until both encryptors are done
      e.handle(enc0, {'type': 'clue', 'clues': ['甲', '乙', '丙']});
      expect((e.view(1)['clues'] as List)[0], isNull);
      expect(() => e.handle(enc0, {'type': 'clue', 'clues': ['a', 'b', 'c']}), throwsA(isA<GameError>()));
      expect(() => e.handle(e.encryptor(1), {'type': 'clue', 'clues': [e.words[1][0], 'b', 'c']}), throwsA(isA<GameError>()));
      e.handle(e.encryptor(1), {'type': 'clue', 'clues': ['丁', '戊', '己']});
      expect(e.phase, 'guess');
      expect((e.view(1)['clues'] as List)[0], ['甲', '乙', '丙']);
      expect(() => e.handle(enc0, {'type': 'guess', 'code': [1, 2, 3]}), throwsA(isA<GameError>()));
      expect(() => e.handle(1 - enc0 % 2 == 0 ? 1 : 3, {'type': 'intercept', 'code': [1, 2, 3]}), throwsA(isA<GameError>()));
    });

    test('miscommunications and interceptions', () {
      final host = SimHost();
      final e = Decrypto(_setup(4, {'words': 'builtin'}))..host = host..start();
      List<int> wrong(List<int> c) => Decrypto.allCodes.firstWhere((x) => x.join() != c.join());
      for (var r = 1; r <= 2; r++) {
        for (var t = 0; t < 2; t++) {
          e.handle(e.encryptor(t), {'type': 'clue', 'clues': ['a$r', 'b$r', 'c$r']});
        }
        e.handle(e.lead(0), {'type': 'guess', 'code': wrong(e.code[0])});
        e.handle(e.lead(1), {'type': 'guess', 'code': e.code[1]});
        if (r >= 2) {
          e.handle(e.lead(0), {'type': 'intercept', 'code': wrong(e.code[1])});
          e.handle(e.lead(1), {'type': 'intercept', 'code': wrong(e.code[0])});
        }
        if (r == 1) {
          expect(e.phase, 'result');
          expect(e.miss, [1, 0]);
          host.runPending();
          expect(e.round, 2);
          expect(e.phase, 'clue');
        }
      }
      expect(e.isOver, isTrue);
      expect(e.winner, 1);
      expect((e.view(0)['keywords'] as List)[1], hasLength(4));
    });
  });

  group('AI', () {
    test('turtlesoup GM answer mapping', () {
      expect(TurtleSoup.mapAiAnswer('是也不是。'), 'both');
      expect(TurtleSoup.mapAiAnswer('是的'), 'yes');
      expect(TurtleSoup.mapAiAnswer('是'), 'yes');
      expect(TurtleSoup.mapAiAnswer('不是'), 'no');
      expect(TurtleSoup.mapAiAnswer('否。'), 'no');
      expect(TurtleSoup.mapAiAnswer('无关'), 'irrelevant');
      expect(TurtleSoup.mapAiAnswer('「很接近」'), 'close');
      expect(TurtleSoup.mapAiAnswer('{"answer":"无关"}'), 'irrelevant');
      expect(TurtleSoup.mapAiAnswer('blah'), isNull);
      expect(TurtleSoup.mapAiAnswer(''), isNull);
      expect(TurtleSoup.mapAiAnswer(null), isNull);
      expect(TurtleSoup.mapAiAnswer('猜对了！', guess: true), 'right');
      expect(TurtleSoup.mapAiAnswer('不对', guess: true), 'wrong');
      expect(TurtleSoup.mapAiAnswer('很接近', guess: true), 'close');
      expect(TurtleSoup.mapAiAnswer('是', guess: true), isNull);
    });

    TurtleSoup soup(String? Function(AiRequest) r) {
      final e = TurtleSoup(_setup(3, {'source': 'builtin', 'rounds': 1, 'cap': 40, 'ai': true}, bots: [true, false, false], ai: _Ai(r)))..start();
      e.handle(0, {'type': 'begin'});
      e.handle(1, {'type': 'ask', 'text': '有人死了吗？'});
      return e;
    }

    test('turtlesoup AI GM answers from the reply and sees the bottom', () {
      AiRequest? seen;
      final e = soup((q) {
        seen = q;
        return '是也不是。';
      });
      final a = e.runBot(0)!;
      expect(a['type'], 'answer');
      expect(a['answer'], 'both');
      expect(seen!.prompt, contains(e.story!.bottom));
      e.handle(0, a);
      expect(e.items.first['a'], 'both');
    });

    test('turtlesoup AI GM junk falls back to heuristic', () {
      final e = soup((_) => 'blah');
      final a = e.runBot(0)!;
      expect(TurtleSoup.answers.containsKey(a['answer']), isTrue);
    });

    test('turtlesoup AI player never sees the bottom', () {
      final ai = _Ai((_) => '{"type":"ask","text":"主角是故意的吗？"}');
      final e = TurtleSoup(_setup(3, {'source': 'builtin', 'rounds': 1, 'cap': 40, 'ai': true}, bots: [false, true, false], ai: ai))..start();
      e.handle(0, {'type': 'begin'});
      final a = e.runBot(1)!;
      expect(a, {'type': 'ask', 'text': '主角是故意的吗？'});
      expect(ai.requests.single.prompt, isNot(contains(e.story!.bottom)));
    });

    test('decrypto AI clues validated', () {
      final e = Decrypto(_setup(4, {'words': 'builtin', 'ai': true}, bots: List.filled(4, true), ai: _Ai((_) => '{"clues":["甲","乙","丙"]}')))..start();
      expect(e.runBot(e.encryptor(0)), {'type': 'clue', 'clues': ['甲', '乙', '丙']});
      final kw = e.words[1][0];
      final e2 = Decrypto(_setup(4, {'words': 'builtin', 'ai': true}, bots: List.filled(4, true), ai: _Ai((_) => '{"clues":["$kw","乙","丙"]}')))..start();
      e2.words[1] = e.words[1];
      final c = e2.runBot(e2.encryptor(1))!['clues'] as List;
      expect(c.contains(kw), isFalse);
    });
  });

  test('placings', () {
    final e = Decrypto(_setup(4, {'words': 'builtin'}))..start();
    expect(e.placings, isNull);
    e.winner = 1;
    e.phase = 'over';
    expect(e.placings, [2, 1, 2, 1]);
  });

  test('bot simulations', () {
    expect(runSims(party2Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
