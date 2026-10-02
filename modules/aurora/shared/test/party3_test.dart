import 'dart:math';

import 'package:aurora_shared/games/party3/chengyu.dart';
import 'package:aurora_shared/games/party3/defs.dart';
import 'package:aurora_shared/games/party3/feihualing.dart';
import 'package:aurora_shared/games/party3/justone.dart';
import 'package:aurora_shared/games/party3/wavelength.dart';
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

GameSetup _setup(int n, Map<String, dynamic> opts, {List<bool>? bots, Map<String, Object> res = const {}, AiService? ai, int level = 1, int seed = 3}) =>
    GameSetup(
      ai: ai,
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: bots ?? List.filled(n, false),
      hostSeat: 0,
      rng: Random(seed),
      resources: res,
      botLevel: level,
    );

GameDef _def(String id) => party3Games.firstWhere((d) => d.id == id);

T _start<T extends GameEngine>(String id, int n, Map<String, dynamic> opts, {AiService? ai, Map<String, Object> res = const {}, int level = 1, int seed = 3}) {
  final d = _def(id);
  final e = d.create(_setup(n, d.normalizeOptions(opts), ai: ai, res: res, level: level, seed: seed, bots: List.filled(n, true)));
  e.start();
  return e as T;
}

void main() {
  test('runSims party3', () {
    expect(runSims(party3Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('data', () {
    test('sizes', () {
      expect(justOneBank.length, greaterThanOrEqualTo(800));
      expect(wavelengthBank.length, greaterThanOrEqualTo(300));
      expect(ChengyuDict.instance.all.length, greaterThan(15000));
      expect(FeihuaDict.instance.all.length, greaterThan(10000));
      for (final w in justOneBank) {
        expect(w.word.isNotEmpty && w.category.isNotEmpty, isTrue);
      }
      for (final k in kFeihuaOptionKeys) {
        expect(FeihuaDict.instance.withKey(k).length, greaterThan(150), reason: k);
      }
      expect(ChengyuDict.instance.lookup('摸金校尉'), isNull); // non-idioms filtered
      expect(ChengyuDict.instance.lookup('一心一意'), isNotNull);
      expect(FeihuaDict.instance.lookup('床前明月光'), isNotNull);
    });

    test('custom resources', () {
      final jo = parseJustOneLines(['# c', '宇宙|自定义|星星,黑洞', '宇宙', '  ', '超长的词语超长的词语超长']);
      expect(jo.map((w) => w.word), ['宇宙']);
      expect(jo.first.assoc, ['星星', '黑洞']);
      final wl = parseWavelengthLines(['冷|热', '冷|热', '坏', '甲｜乙']);
      expect(wl, [('冷', '热'), ('甲', '乙')]);
      final words = [for (var i = 0; i < 20; i++) '自定词$i'];
      final e = _start<JustOne>('justone', 4, {'words': 'custom'}, res: {'justone.words': words});
      expect(e.word!.word.startsWith('自定词'), isTrue);
    });
  });

  group('Just One', () {
    test('clue validation', () {
      expect(JustOne.clueError('猫咪', '猫'), isNotNull);
      expect(JustOne.clueError('老鼠', '猫'), isNull);
      expect(JustOne.clueError('two words', '猫'), isNotNull);
      expect(JustOne.clueError('', '猫'), isNotNull);
      expect(JustOne.clueError('一二三四五六七八九', '猫'), isNotNull);
    });

    test('duplicates cancel, votes cancel, scoring', () {
      final e = _start<JustOne>('justone', 5, {'time': 0});
      final g = e.guesser;
      final ws = e.writers;
      final w = e.word!.word;
      expect(e.view(g)['word'], isNull);
      expect(e.view(ws[0])['word'], w);
      expect(() => e.handle(g, {'type': 'clue', 'text': '甲'}), throwsA(isA<GameError>()));
      expect(() => e.handle(ws[0], {'type': 'clue', 'text': w}), throwsA(isA<GameError>()));
      e.handle(ws[0], {'type': 'clue', 'text': 'ＡＢ'});
      e.handle(ws[1], {'type': 'clue', 'text': 'ab'});
      e.handle(ws[2], {'type': 'clue', 'text': '提示甲'});
      // clues are secret from the guesser and from other writers during `clue`
      expect(e.view(ws[3])['clues'], isNull);
      e.handle(ws[3], {'type': 'clue', 'text': '提示乙'});
      expect(e.phase, 'review');
      expect(e.view(g)['clues'], isNull);
      final cl = e.clues;
      expect(cl.where((c) => c['auto'] == true).length, 2);
      final idB = cl.firstWhere((c) => c['t'] == '提示乙')['id'];
      e.handle(ws[0], {'type': 'confirm', 'cancel': [idB]});
      e.handle(ws[1], {'type': 'confirm', 'cancel': [idB]});
      e.handle(ws[2], {'type': 'confirm'});
      e.handle(ws[3], {'type': 'confirm'});
      expect(e.phase, 'guess');
      final seen = (e.view(g)['clues'] as List).map((c) => (c as Map)['t']).toList();
      expect(seen, ['提示甲']);
      final deck = e.deck;
      e.handle(g, {'type': 'guess', 'text': '绝对不是这个词'});
      expect(e.deck, deck - 2); // wrong guess also discards the next card
      expect(e.success, 0);
    });

    test('3 players write two clues each; correct guess scores', () {
      final e = _start<JustOne>('justone', 3, {'time': 0, 'cards': 7});
      expect(e.cluesPer, 2);
      for (final s in e.writers) {
        expect(() => e.handle(s, {'type': 'clue', 'text': '一个'}), throwsA(isA<GameError>()));
        e.handle(s, {'type': 'clue', 'texts': ['线索$s甲', '线索$s乙']});
      }
      for (final s in e.writers) {
        e.handle(s, {'type': 'confirm'});
      }
      e.handle(e.guesser, {'type': 'guess', 'text': e.word!.word});
      expect(e.success, 1);
      expect(e.deck, 6);
    });

    test('AI clues/guesses are validated with fallback', () {
      late JustOne e;
      final ai = _Ai((r) {
        if (r.system.contains('你是猜词者')) return e.word!.word; // AI guesser is right
        return '${e.word!.word}的 好提示 好提示'; // first part contains answer, rest dup
      });
      final d = _def('justone');
      e = d.create(_setup(4, d.normalizeOptions({'ai': true, 'time': 0}), ai: ai, bots: List.filled(4, true))) as JustOne;
      e.start();
      final w0 = e.writers.first;
      final a = e.runBot(w0)!;
      expect(a['texts'], ['好提示']);
      // the prompt only contains the writer's own knowledge
      expect(ai.requests.last.prompt.contains(e.word!.word), isTrue);
      for (final s in e.writers) {
        e.handle(s, e.runBot(s)!);
      }
      for (final s in e.writers) {
        e.handle(s, e.runBot(s)!);
      }
      expect(e.phase, 'guess');
      // guesser prompt must not leak the word
      final g = e.runBot(e.guesser)!;
      expect(ai.requests.last.prompt.contains(e.word!.word), isFalse);
      expect(g, {'type': 'guess', 'text': e.word!.word});
      ai.reply = (r) => 'I think it is a very long english answer';
      expect(e.runBot(e.guesser)!['type'], anyOf('guess', 'pass'));
    });
  });

  group('频率猜心', () {
    test('scoring bands', () {
      expect(Wavelength.points(50, 50), 4);
      expect(Wavelength.points(54, 50), 4);
      expect(Wavelength.points(61, 50), 3);
      expect(Wavelength.points(32, 50), 2);
      expect(Wavelength.points(31, 50), 0);
      expect(Wavelength.clueError('百分之八十'), isNotNull);
      expect(Wavelength.clueError('80度'), isNotNull);
      expect(Wavelength.clueError('火锅'), isNull);
    });

    test('ladder clue round-trips', () {
      for (var t = 0; t <= 100; t++) {
        final c = Wavelength.ladderClue('冷', '热', t);
        final p = Wavelength.readLadder('冷', '热', c)!;
        expect(Wavelength.points(p, t), greaterThanOrEqualTo(2), reason: '$t $c $p');
      }
    });

    test('target hidden from guessers; team mode counter guess', () {
      final e = _start<Wavelength>('wavelength', 4, {'mode': 'team', 'time': 0});
      final psy = e.psychic;
      final mate = e.guessers.single;
      expect(e.view(psy)['target'], e.target);
      expect(e.view(mate)['target'], isNull);
      expect(e.view(-1)['target'], isNull);
      expect(() => e.handle(mate, {'type': 'clue', 'text': 'x'}), throwsA(isA<GameError>()));
      expect(() => e.handle(psy, {'type': 'clue', 'text': '三成'}), returnsNormally);
      expect(e.phase, 'guess');
      final pos = e.target < 50 ? e.target + 8 : e.target - 8; // 3 points
      e.handle(mate, {'type': 'lock', 'pos': pos});
      expect(e.phase, 'counter');
      final t = e.activeTeam;
      final truth = e.target < pos ? 'left' : 'right';
      for (final s in e.opponents) {
        e.handle(s, {'type': 'side', 'side': truth});
      }
      expect(e.teamScore[t], 3);
      expect(e.teamScore[1 - t], 1);
    });

    test('coop mode averages locked markers', () {
      final e = _start<Wavelength>('wavelength', 3, {'time': 0});
      e.handle(e.psychic, {'type': 'clue', 'text': '温水'});
      final gs = e.guessers;
      e.handle(gs[0], {'type': 'dial', 'pos': 90});
      e.handle(gs[0], {'type': 'lock', 'pos': 20});
      e.handle(gs[1], {'type': 'lock', 'pos': 40});
      expect(e.lastResult!['dial'], 30);
      expect(() => e.handle(gs[0], {'type': 'lock', 'pos': 101}), throwsA(isA<GameError>()));
    });

    test('AI psychic / guesser validated', () {
      var clue = '{"pos": 30}';
      final ai = _Ai((r) => r.system.contains('通灵者。') ? clue : '好的 {"pos": 77}');
      final d = _def('wavelength');
      final e = d.create(_setup(3, d.normalizeOptions({'ai': true, 'time': 0}), ai: ai, bots: List.filled(3, true))) as Wavelength;
      e.start();
      // JSON-looking clue rejected -> ladder fallback
      final a = e.runBot(e.psychic)!;
      expect(Wavelength.readLadder(e.pair.$1, e.pair.$2, a['text'] as String), isNotNull);
      expect(ai.requests.last.prompt.contains('${e.target}'), isTrue);
      clue = '北极的冬天';
      final e2 = d.create(_setup(3, d.normalizeOptions({'ai': true, 'time': 0}), ai: ai, bots: List.filled(3, true), seed: 9)) as Wavelength;
      e2.start();
      final c2 = e2.runBot(e2.psychic)!;
      expect(c2['text'], '北极的冬天');
      e2.handle(e2.psychic, c2);
      final g = e2.runBot(e2.guessers.first)!;
      expect(g['pos'], 77);
      expect(ai.requests.last.prompt.contains('${e2.target}'), isFalse);
      ai.reply = (_) => '{"pos": 500}';
      final g2 = e2.runBot(e2.guessers.last)!;
      expect((g2['pos'] as int) >= 0 && (g2['pos'] as int) <= 100, isTrue);
    });
  });

  group('成语接龙', () {
    ChengyuGame cy({String match = 'char', int lives = 3}) => _start<ChengyuGame>('chengyu', 3, {'match': match, 'lives': lives, 'time': 0});

    void setCurrent(ChengyuGame e, String w) => e.current = e.dict.lookup(w)!;

    test('char match validation, repeats, pass loses life', () {
      final e = cy();
      setCurrent(e, '一心一意');
      final s = e.turn;
      expect(() => e.handle(s, {'type': 'answer', 'text': '发扬光大'}), throwsA(isA<GameError>()));
      expect(() => e.handle(s, {'type': 'answer', 'text': '意气用事啊'}), throwsA(isA<GameError>()));
      expect(() => e.handle(s, {'type': 'answer', 'text': '意意意意'}), throwsA(isA<GameError>()));
      expect(() => e.handle((s + 1) % 3, {'type': 'answer', 'text': '意气风发'}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'answer', 'text': ' 意气风发 '});
      expect(e.score[s], 1);
      expect(e.current.word, '意气风发');
      final n = e.turn;
      expect(n, isNot(s));
      e.handle(n, {'type': 'answer', 'text': '发扬光大'});
      setCurrent(e, '一心一意');
      expect(() => e.handle(e.turn, {'type': 'answer', 'text': '意气风发'}), throwsA(isA<GameError>())); // used
      final t = e.turn;
      e.handle(t, {'type': 'pass'});
      expect(e.lives[t], 2);
      expect(e.current.word, isNot('一心一意')); // chain restarted
    });

    test('sound match accepts homophones', () {
      final e = cy(match: 'sound');
      setCurrent(e, '一心一意');
      final follow = e.dict.all.firstWhere((c) => toneless(c.firstPy) == 'yi' && c.first != '意' && !e.used.contains(c.word));
      e.handle(e.turn, {'type': 'answer', 'text': follow.word});
      expect(e.answers, 1);
    });

    test('elimination and placings', () {
      final e = cy(lives: 1);
      final first = e.turn;
      e.handle(first, {'type': 'pass'});
      expect(e.alive(first), isFalse);
      final second = e.turn;
      e.handle(second, {'type': 'pass'});
      expect(e.isOver, isTrue);
      final p = e.placings!;
      final winner = [0, 1, 2].firstWhere((s) => s != first && s != second);
      expect(p[winner], 1);
      expect(p[second], 2);
      expect(p[first], 3);
    });

    test('AI answer validated against the list', () {
      final ai = _Ai((_) => '当然是：意马心猿');
      final d = _def('chengyu');
      final e = d.create(_setup(2, d.normalizeOptions({'ai': true, 'time': 0}), ai: ai, bots: [true, true])) as ChengyuGame;
      e.start();
      e.current = e.dict.lookup('一心一意')!;
      expect(e.runBot(e.turn), {'type': 'answer', 'text': '意马心猿'});
      ai.reply = (_) => '意意不舍'; // invented → fallback search
      final a = e.runBot(e.turn)!;
      if (a['type'] == 'answer') expect(e.answerError(a['text'] as String), isNull);
      ai.reply = (_) => null;
      expect(e.runBot(e.turn), isNotNull);
    });

    test('easy bots sometimes fail', () {
      var passes = 0;
      for (var seed = 1; seed <= 10; seed++) {
        final e = _start<ChengyuGame>('chengyu', 2, {'time': 0}, level: 0, seed: seed);
        for (var i = 0; i < 20 && !e.isOver; i++) {
          final a = e.runBot(e.turn)!;
          if (a['type'] == 'pass') passes++;
          e.handle(e.turn, a);
        }
      }
      expect(passes, greaterThan(0));
    });
  });

  group('飞花令', () {
    Feihualing fh({String check = 'strict', String key = '月'}) =>
        _start<Feihualing>('feihualing', 3, {'check': check, 'key': key, 'time': 0});

    test('strict validation', () {
      final e = fh();
      expect(e.key, '月');
      final s = e.turn;
      expect(() => e.handle(s, {'type': 'answer', 'text': '白日依山尽'}), throwsA(isA<GameError>())); // no key
      expect(() => e.handle(s, {'type': 'answer', 'text': '月亮圆圆挂天上'}), throwsA(isA<GameError>())); // not listed
      e.handle(s, {'type': 'answer', 'text': '床前明月光，疑是地上霜。'});
      expect(e.score[s], 1);
      expect(e.used.contains('床前明月光'), isTrue);
      expect(() => e.handle(e.turn, {'type': 'answer', 'text': '床前明月光'}), throwsA(isA<GameError>()));
      e.handle(e.turn, {'type': 'answer', 'text': '举头望明月'});
      expect(e.answers, 2);
    });

    test('loose mode vote', () {
      final e = fh(check: 'loose');
      final s = e.turn;
      e.handle(s, {'type': 'answer', 'text': '月亮圆圆挂天上'});
      expect(e.phase, 'vote');
      expect(e.waitingFor.contains(s), isFalse);
      expect(() => e.handle(s, {'type': 'vote', 'ok': true}), throwsA(isA<GameError>()));
      final vs = e.voters;
      e.handle(vs[0], {'type': 'vote', 'ok': false});
      e.handle(vs[1], {'type': 'vote', 'ok': false});
      expect(e.phase, 'play');
      expect(e.lives[s], 2);
      final s2 = e.turn;
      e.handle(s2, {'type': 'answer', 'text': '月落乌啼何处寻'});
      for (final v in e.voters) {
        e.handle(v, {'type': 'vote', 'ok': true});
      }
      expect(e.score[s2], 1);
    });

    test('AI line validated', () {
      final ai = _Ai((_) => '好的：“海上生明月，天涯共此时。”');
      final d = _def('feihualing');
      final e = d.create(_setup(2, d.normalizeOptions({'ai': true, 'key': '月', 'time': 0}), ai: ai, bots: [true, true])) as Feihualing;
      e.start();
      expect(e.runBot(e.turn), {'type': 'answer', 'text': '海上生明月'});
      ai.reply = (_) => '明月几时有啊啊啊啊我编的';
      final a = e.runBot(e.turn)!;
      if (a['type'] == 'answer') expect(e.dict.lookup(a['text'] as String), isNotNull);
    });
  });
}
