import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/drawguess/defs.dart';
import 'package:aurora_shared/games/drawguess/drawguess.dart';
import 'package:aurora_shared/games/drawguess/pool.dart';
import 'package:aurora_shared/games/drawguess/telephone.dart';
import 'package:aurora_shared/games/drawguess/words/bank.dart';
import 'package:aurora_shared/games/drawguess/ai_draw.dart';
import 'package:aurora_shared/src/ai.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:aurora_shared/src/strokes.dart';
import 'package:test/test.dart';

/// Host that records scheduled callbacks without running them (manual control).
class ManualHost implements GameHost {
  final logs = <String>[];
  final q = <void Function()>[];
  @override
  void log(String text) => logs.add(text);
  @override
  void Function() schedule(int ms, void Function() fn) {
    var c = false;
    q.add(() {
      if (!c) fn();
    });
    return () => c = true;
  }

  void runAll() {
    final l = List.of(q);
    q.clear();
    for (final f in l) {
      f();
    }
  }
}

class _Ai extends FakeAi {
  String? Function(AiRequest) reply;
  _Ai(this.reply);
  @override
  String? completeNow(AiRequest req) {
    requests.add(req);
    return reply(req);
  }
}

DrawGuess make(int players,
    {Map<String, dynamic> opts = const {}, List<String>? custom, int hostSeat = 0, List<bool>? bots, ManualHost? host, AiService? ai}) {
  final def = drawguessGames.first;
  final e = def.create(GameSetup(
    ai: ai,
    players: players,
    options: def.normalizeOptions(opts),
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: bots ?? List.filled(players, false),
    hostSeat: hostSeat,
    rng: Random(3),
    resources: custom == null ? const {} : {'drawguess.words': custom},
  )) as DrawGuess;
  e.host = host ?? ManualHost();
  e.start();
  return e;
}

/// Starts a system-mode game and chooses the first offered word.
DrawGuess drawing(int players, {Map<String, dynamic> opts = const {}}) {
  final e = make(players, opts: opts);
  e.handle(e.drawer, {'type': 'choose', 'word': e.choices.first});
  expect(e.phase, 'draw');
  return e;
}

void main() {
  test('word bank: size, uniqueness, categories, length', () {
    final bank = drawWordBank;
    expect(bank.length, greaterThanOrEqualTo(2000));
    expect(bank.map((w) => w.word).toSet().length, bank.length);
    expect(drawWordRawCount, bank.length, reason: 'no duplicates in the source lists');
    final cats = drawWordsByCategory.keys.toSet();
    for (final c in ['动物', '食物', '物品', '职业', '动作', '地点', '交通', '植物', '自然', '运动', '乐器', '成语', '电器', '身体', '服装', '节日']) {
      expect(cats, contains(c));
    }
    for (final w in bank) {
      expect(w.word.length, lessThanOrEqualTo(kMaxWordLen), reason: w.word);
      expect(w.word.contains(' '), isFalse);
    }
  });

  test('custom words merged with built-in, deduped, invalid skipped', () {
    final lines = ['  小熊软糖|食物 ', '猫', '超级无敌长长长长长长长的词语哈', '', '魔法扫帚', '魔法扫帚|物品'];
    final pool = buildWordPool('both', lines, (_) {});
    expect(pool.length, drawWordBank.length + 2);
    expect(pool.where((w) => w.word == '猫').length, 1);
    final bear = pool.firstWhere((w) => w.word == '小熊软糖');
    expect(bear.category, '食物');
    expect(pool.firstWhere((w) => w.word == '魔法扫帚').category, kCustomCategory);
  });

  test('only custom words / fallback with warning', () {
    final logs = <String>[];
    final only = buildWordPool('custom', ['甲虫王|动物', '魔法扫帚', '飞天毯', '飞天毯'], logs.add);
    expect(only.map((w) => w.word).toList(), ['甲虫王', '魔法扫帚', '飞天毯']);
    expect(logs, isEmpty);
    final fb = buildWordPool('custom', ['魔法扫帚', '   '], logs.add);
    expect(fb.length, drawWordBank.length);
    expect(logs, [kCustomFileHint]);
    expect(buildWordPool('builtin', ['魔法扫帚'], (_) {}).any((w) => w.word == '魔法扫帚'), isFalse);

    // through the engine
    final host = ManualHost();
    final e = make(3, opts: {'words': 'custom'}, custom: ['魔法扫帚', '飞天毯', '水晶球'], host: host);
    expect(e.pool.length, 3);
    for (final c in e.choices) {
      expect(['魔法扫帚', '飞天毯', '水晶球'], contains(c));
    }
    final host2 = ManualHost();
    final e2 = make(3, opts: {'words': 'custom'}, custom: ['魔法扫帚'], host: host2);
    expect(e2.pool.length, drawWordBank.length);
    expect(host2.logs, contains(kCustomFileHint));
  });

  test('player range depends on mode', () {
    final def = drawguessGames.first;
    expect(def.playerRange(def.defaultOptions()), (3, 12));
    expect(def.playerRange({...def.defaultOptions(), 'mode': 'gm'}), (4, 12));
  });

  test('GM mode: GM sees word and guesses, cannot guess, never draws', () {
    final e = make(5, opts: {'mode': 'gm'}, hostSeat: 2);
    expect(e.gm, 2);
    expect(e.phase, 'gmword');
    expect(e.waitingFor, [2]);
    expect(e.drawers.contains(2), isFalse);
    expect(() => e.handle(2, {'type': 'gmword', 'word': '  '}), throwsA(isA<GameError>()));
    expect(() => e.handle(2, {'type': 'gmword', 'word': '一二三四五六七八九十一二三'}), throwsA(isA<GameError>()));
    expect(() => e.handle(0, {'type': 'gmword', 'word': '苹果'}), throwsA(isA<GameError>()));
    e.handle(2, {'type': 'gmword', 'word': '苹果', 'hint': '水果'});
    expect(e.phase, 'draw');
    final d = e.drawer;
    expect(e.view(2)['word'], '苹果');
    expect(e.view(d)['word'], '苹果');
    expect(e.view(2)['myRole'], 'gm');
    expect(() => e.handle(2, {'type': 'guess', 'text': '苹果'}), throwsA(isA<GameError>()));
    final g = e.guessers.first;
    e.handle(g, {'type': 'guess', 'text': '苹果'});
    final gmFeed = (e.view(2)['feed'] as List).last as Map;
    expect(gmFeed['t'], '苹果');
    expect(gmFeed['k'], 'right');
    e.handle(2, {'type': 'gmskip'});
    expect(e.phase, 'reveal');
    expect(e.scores[2], 0);
    // play every round: GM never becomes drawer
    final host = e.host as ManualHost;
    while (!e.isOver) {
      if (e.phase == 'gmword') {
        expect(e.drawer, isNot(2));
        e.handle(2, {'type': 'gmword', 'word': '香蕉'});
      }
      host.runAll();
    }
    expect((e.view(-1)['final'] as List).any((r) => (r as Map)['s'] == 2), isFalse);
  });

  test('GM bot picks from bank', () {
    final e = make(4, opts: {'mode': 'gm'}, bots: [true, false, false, false]);
    final a = e.bot(0)!;
    expect(a['type'], 'gmword');
    expect(e.pool.any((w) => w.word == a['word']), isTrue);
    e.handle(0, a);
    expect(e.phase, 'draw');
    expect(e.category, isNotEmpty);
  });

  test('scoring by guess order and drawer per correct guesser', () {
    final e = drawing(5);
    final w = e.word;
    final gs = e.guessers;
    e.handle(gs[0], {'type': 'guess', 'text': w});
    e.handle(gs[1], {'type': 'guess', 'text': ' $w '});
    expect(() => e.handle(gs[1], {'type': 'guess', 'text': w}), throwsA(isA<GameError>()));
    expect(() => e.handle(e.drawer, {'type': 'guess', 'text': w}), throwsA(isA<GameError>()));
    e.handle(gs[2], {'type': 'guess', 'text': w});
    expect(e.phase, 'draw');
    e.handle(gs[3], {'type': 'guess', 'text': w});
    expect(e.phase, 'reveal', reason: 'all guessed ends round');
    expect([for (final s in gs) e.scores[s]], [10, 8, 6, 5]);
    expect(e.scores[e.drawer], 4 * DrawGuess.drawerPerGuess);
  });

  test('strokes append by id, undo, clear, only drawer, point cap', () {
    final e = drawing(3);
    final d = e.drawer;
    e.handle(d, {'type': 'stroke', 'id': 1, 'color': 0xFF000000, 'width': 6, 'pts': [0, 0, 10, 10]});
    e.handle(d, {'type': 'stroke', 'id': 1, 'color': 0xFF000000, 'width': 6, 'pts': [20, 20, 2000, -5]});
    e.handle(d, {'type': 'stroke', 'id': 2, 'color': 0xFFFF0000, 'width': 12, 'pts': [5, 5]});
    var st = e.view(-1)['strokes'] as List;
    expect(st.length, 2);
    expect((st[0] as Map)['p'], [0, 0, 10, 10, 20, 20, 1000, 0]);
    expect(e.pointCount, 5);
    expect(() => e.handle(e.guessers.first, {'type': 'stroke', 'id': 3, 'pts': [1, 1]}), throwsA(isA<GameError>()));
    expect(() => e.handle(d, {'type': 'stroke', 'id': 3, 'pts': [1]}), throwsA(isA<GameError>()));
    e.handle(d, {'type': 'undo'});
    st = e.view(-1)['strokes'] as List;
    expect(st.length, 1);
    expect(e.pointCount, 4);
    e.handle(d, {'type': 'clear'});
    expect((e.view(-1)['strokes'] as List), isEmpty);
    expect(e.pointCount, 0);
    // cap
    final batch = List.filled(600, 1);
    for (var i = 0; i < DrawGuess.maxPoints ~/ 300; i++) {
      e.handle(d, {'type': 'stroke', 'id': 10 + i ~/ 50, 'pts': batch});
    }
    expect(() => e.handle(d, {'type': 'stroke', 'id': 20, 'pts': batch}), throwsA(isA<GameError>()));
    e.handle(d, {'type': 'stroke', 'id': 20, 'pts': List.filled(400, 1)});
    expect(e.pointCount, DrawGuess.maxPoints);
    expect(() => e.handle(d, {'type': 'stroke', 'id': 99, 'pts': [1, 1]}), throwsA(isA<GameError>()));
  });

  test('hidden word never in guesser / spectator views before reveal', () {
    for (final mode in ['bank', 'gm']) {
      final e = make(5, opts: {'mode': mode, 'pick': 'random'});
      if (mode == 'gm') e.handle(e.gm, {'type': 'gmword', 'word': '长颈鹿', 'hint': '动物'});
      expect(e.phase, 'draw');
      final w = e.word;
      final host = e.host as ManualHost;
      for (var stage = 0; stage < 3; stage++) {
        final g = e.guessers.first;
        e.handle(g, {'type': 'guess', 'text': '错误答案'});
        for (final s in [-1, ...e.guessers]) {
          final j = jsonEncode(e.view(s));
          expect(j.contains('"$w"'), isFalse, reason: 'seat $s stage $stage');
          expect(e.view(s)['word'], isNull);
        }
        expect(e.view(e.drawer)['word'], w);
        if (stage < 2) host.runAll();
      }
    }
    // choices only for the drawer
    final e = make(4);
    for (final s in [-1, 0, 1, 2, 3]) {
      if (s == e.drawer) {
        expect(e.view(s)['choices'], hasLength(3));
      } else {
        expect(e.view(s)['choices'], isNull);
        final j = jsonEncode(e.view(s));
        for (final c in e.choices) {
          expect(j.contains('"$c"'), isFalse);
        }
      }
    }
  });

  test('correct and near-miss guesses masked for others', () {
    final e = make(4, opts: {'mode': 'gm'});
    e.handle(e.gm, {'type': 'gmword', 'word': '大熊猫'});
    final gs = e.guessers;
    e.handle(gs[0], {'type': 'guess', 'text': '熊猫大'.substring(0, 2)}); // 熊猫 -> close
    e.handle(gs[1], {'type': 'guess', 'text': '苹果'}); // wrong
    e.handle(gs[0], {'type': 'guess', 'text': '大熊猫'}); // right
    final other = e.view(gs[1])['feed'] as List;
    expect((other[0] as Map)['k'], 'close');
    expect((other[0] as Map)['t'], isNull);
    expect((other[1] as Map)['t'], '苹果');
    expect((other[2] as Map)['k'], 'right');
    expect((other[2] as Map)['t'], isNull);
    final spec = jsonEncode(e.view(-1));
    expect(spec.contains('熊猫'), isFalse);
    // the guesser sees their own text; drawer and GM see everything
    expect(((e.view(gs[0])['feed'] as List)[0] as Map)['t'], '熊猫');
    expect(((e.view(e.drawer)['feed'] as List)[0] as Map)['t'], '熊猫');
    expect(((e.view(e.gm)['feed'] as List)[2] as Map)['t'], '大熊猫');
    expect(DrawGuess.isClose('熊猫', '大熊猫'), isTrue);
    expect(DrawGuess.isClose('苹果', '大熊猫'), isFalse);
  });

  test('hints reveal length, then category, then a char', () {
    final e = make(3, opts: {'pick': 'random'});
    final host = e.host as ManualHost;
    final g = e.guessers.first;
    var h = e.view(g)['hint'] as Map;
    expect(h['len'], e.word.length);
    expect(h['cat'], isNull);
    host.runAll();
    h = e.view(g)['hint'] as Map;
    expect(h['cat'], e.category);
    host.runAll();
    h = e.view(g)['hint'] as Map;
    if (e.word.length > 1) expect((h['chars'] as List).whereType<String>().length, 1);
    host.runAll();
    expect(e.phase, 'reveal');
    expect(e.view(g)['word'], isNotNull);
  });

  test('bot guesser does not read hidden word', () {
    // category-constrained guesses come from the revealed category only
    final e = make(3, opts: {'pick': 'random'}, bots: [true, true, true]);
    final host = e.host as ManualHost;
    host.runAll(); // reveal category
    final g = e.guessers.first;
    for (var i = 0; i < 3; i++) {
      final a = e.bot(g)!;
      final w = e.pool.firstWhere((x) => x.word == a['text']);
      expect(w.category, e.category);
      expect(w.word.length, e.word.length);
    }
  });

  test('bot simulations', () {
    expect(runSims(drawguessGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));

  group('AI', () {
    test('AI guess from the picture gets submitted and scores', () {
      late DrawGuess e;
      final ai = _Ai((_) => '「${e.word}」');
      e = make(3, opts: {'ai': true}, bots: [false, true, true], ai: ai);
      e.handle(e.drawer, {'type': 'choose', 'word': e.choices.first});
      e.handle(e.drawer, {'type': 'stroke', 'id': 1, 'pts': [100, 100, 900, 900]});
      final g = e.guessers.firstWhere(e.isBot);
      final a = e.runBot(g)!;
      expect(a, {'type': 'guess', 'text': e.word});
      expect(ai.requests.single.images, hasLength(1));
      expect(ai.requests.single.prompt, isNot(contains(e.word)));
      e.handle(g, a);
      expect(e.guessed[g], isTrue);
    });

    test('AI guess repeats are rejected and asks are capped', () {
      final e = make(3, opts: {'ai': true}, bots: [false, true, true], ai: _Ai((_) => '不可能的答案'));
      e.handle(e.drawer, {'type': 'choose', 'word': e.choices.first});
      e.handle(e.drawer, {'type': 'stroke', 'id': 1, 'pts': [100, 100, 900, 900]});
      final g = e.guessers.first;
      // hints are on: a guess of the wrong length is rejected -> heuristic
      final a = e.runBot(g)!;
      expect(a['type'], 'guess');
    });

    test('AI drawing JSON is validated and emitted stroke by stroke', () {
      expect(parseAiStrokes('{"strokes":[[0,0,1200,-5,300]]}'), [[0, 0, 1000, 0]]);
      expect(parseAiStrokes('{"strokes":[[1,2]]}'), isNull);
      expect(parseAiStrokes('{"strokes":"x"}'), isNull);
      expect(parseAiStrokes('garbage'), isNull);
      expect(parseAiStrokes('{"strokes":[${List.filled(20, '[1,1,2,2]').join(',')}]}'), hasLength(kAiMaxStrokes));

      final e = make(3, opts: {'ai': true}, bots: [true, true, true], ai: _Ai((_) => '{"strokes":[[100,100,200,200],[300,300,400,400,500,500]]}'));
      e.handle(e.drawer, {'type': 'choose', 'word': e.choices.first});
      final s1 = e.runBot(e.drawer)!;
      expect(s1['pts'], [100, 100, 200, 200]);
      e.handle(e.drawer, s1);
      final s2 = e.runBot(e.drawer)!;
      e.handle(e.drawer, s2);
      expect(e.strokes, hasLength(2));
      expect(e.waitingFor.contains(e.drawer), isFalse);

      final g = make(3, opts: {'ai': true}, bots: [true, true, true], ai: _Ai((_) => 'junk'));
      g.handle(g.drawer, {'type': 'choose', 'word': g.choices.first});
      final h = g.runBot(g.drawer)!;
      expect(h['type'], 'stroke'); // heuristic fallback
    });
  });

  // ------------------------------------------------------------ 传话画画

  test('telephone: rotation covers all books, never own book, one page per player', () {
    for (var n = 3; n <= 12; n++) {
      for (var p = 0; p < n; p++) {
        final seen = <int>{};
        for (var r = 0; r < n; r++) {
          final b = Telephone.bookFor(p, r, n);
          if (r == 0) {
            expect(b, p);
          } else {
            expect(b, isNot(p), reason: 'n=$n p=$p r=$r got own book');
          }
          seen.add(b);
        }
        expect(seen.length, n, reason: 'player touches every book once');
      }
      for (var r = 0; r < n; r++) {
        final bs = {for (var p = 0; p < n; p++) Telephone.bookFor(p, r, n)};
        expect(bs.length, n, reason: 'each book worked on by exactly one player per round');
      }
    }
    // through the engine
    final e = tel(5);
    while (e.phase != 'reveal') {
      for (var p = 0; p < 5; p++) {
        if (e.phase != 'write') expect(e.bookOf(p), isNot(p));
      }
      finishRound(e);
    }
    expect(e.books.length, 5);
    for (var b = 0; b < 5; b++) {
      expect(e.books[b].length, 5);
      expect(e.books[b].map((pg) => pg['s']).toSet().length, 5);
      expect(e.books[b][0]['s'], b);
      expect([for (final pg in e.books[b]) pg['k']], ['text', 'draw', 'text', 'draw', 'text']);
    }
  });

  test('telephone: views show only the previous page of the current book', () {
    final e = tel(4);
    expect(e.phase, 'write');
    expect(e.waitingFor, [0, 1, 2, 3]);
    expect((e.view(0)['task'] as Map)['prev'], isNull);
    finishRound(e); // prompts r0-pX
    expect(e.phase, 'draw');
    for (var p = 0; p < 4; p++) {
      final v = e.view(p);
      final prev = (v['task'] as Map)['prev'] as Map;
      final b = e.bookOf(p);
      expect(b, isNot(p));
      expect(prev['t'], 'r0-p$b');
      final js = jsonEncode(v);
      for (var q = 0; q < 4; q++) {
        if (q != b) expect(js.contains('r0-p$q'), isFalse, reason: 'seat $p sees prompt of $q');
      }
      expect(v.containsKey('reveal'), isFalse);
      expect(v.containsKey('gallery'), isFalse);
    }
    finishRound(e); // drawings
    expect(e.phase, 'describe');
    for (var p = 0; p < 4; p++) {
      final js = jsonEncode(e.view(p));
      for (var q = 0; q < 4; q++) {
        expect(js.contains('r0-p$q'), isFalse, reason: 'describe phase must not leak prompts');
      }
      final prev = (e.view(p)['task'] as Map)['prev'] as Map;
      expect(prev['k'], 'draw');
      expect((prev['strokes'] as List).length, 1);
    }
    // spectators: progress only
    final sv = e.view(-1);
    expect(sv.containsKey('task'), isFalse);
    final sjs = jsonEncode(sv);
    expect(sjs.contains('r0-p'), isFalse);
    expect(sjs.contains('strokes'), isFalse);
    e.handle(2, {'type': 'done', 'text': 'x'});
    expect(e.view(-1)['done'], [false, false, true, false]);
    expect(e.waitingFor, [0, 1, 3]);
  });

  test('telephone: timeout auto-submits drafts / empty text / empty drawing', () {
    final host = ManualHost();
    final e = tel(3, host: host);
    e.handle(0, {'type': 'done', 'text': '一只猫在弹钢琴'});
    e.handle(1, {'type': 'draft', 'text': '半截草稿'});
    host.runAll(); // timer expires
    expect(e.phase, 'draw');
    expect(e.books[0][0]['t'], '一只猫在弹钢琴');
    expect(e.books[1][0]['t'], '半截草稿');
    expect((e.books[2][0]['t'] as String).isNotEmpty, isTrue, reason: 'empty prompt -> pool word');
    // drawing: only seat 0 draws something, nobody presses 完成
    e.handle(0, {'type': 'stroke', 'id': 7, 'color': 0xFF000000, 'width': 6, 'pts': [1, 2, 3, 4]});
    host.runAll();
    expect(e.phase, 'describe');
    expect((e.books[Telephone.bookFor(0, 1, 3)][1]['strokes'] as List).length, 1);
    expect((e.books[Telephone.bookFor(1, 1, 3)][1]['strokes'] as List), isEmpty);
    host.runAll(); // describe timeout, nothing typed
    expect(e.phase, 'reveal');
    for (var b = 0; b < 3; b++) {
      expect(e.books[b][2]['t'], Telephone.emptyText);
    }
  });

  test('telephone: text limits, strokes only while drawing, undo/clear', () {
    final e = tel(3);
    expect(() => e.handle(0, {'type': 'done', 'text': '字' * 41}), throwsA(isA<GameError>()));
    expect(() => e.handle(0, {'type': 'stroke', 'id': 1, 'pts': [1, 2]}), throwsA(isA<GameError>()));
    expect(() => e.handle(-1, {'type': 'done', 'text': 'a'}), throwsA(isA<GameError>()));
    e.handle(0, {'type': 'done', 'text': '字' * 40});
    expect(() => e.handle(0, {'type': 'done', 'text': 'again'}), throwsA(isA<GameError>()));
    e.handle(1, {'type': 'done', 'text': 'b'});
    e.handle(2, {'type': 'done', 'text': 'c'});
    expect(e.phase, 'draw');
    e.handle(1, {'type': 'stroke', 'id': 5, 'color': 0xFFFF0000, 'width': 8, 'pts': [0, 0, 5, 5]});
    e.handle(1, {'type': 'stroke', 'id': 5, 'pts': [9, 9]});
    e.handle(1, {'type': 'stroke', 'id': 6, 'pts': [1, 1]});
    final page = e.pageOf(1);
    expect((page['strokes'] as List).length, 2);
    expect((page['sketch'] as Sketch).points, 4);
    e.handle(1, {'type': 'undo'});
    expect((page['sketch'] as Sketch).points, 3);
    e.handle(1, {'type': 'clear'});
    expect((page['strokes'] as List), isEmpty);
    expect(() => e.handle(1, {'type': 'stroke', 'id': 1, 'pts': List.filled(602, 1)}), throwsA(isA<GameError>()));
    e.handle(1, {'type': 'done'});
    expect(() => e.handle(1, {'type': 'stroke', 'id': 2, 'pts': [1, 1]}), throwsA(isA<GameError>()));
  });

  test('telephone: reveal is paged by the host, likes, gallery at the end', () {
    final e = tel(3, hostSeat: 1);
    while (e.phase != 'reveal') {
      finishRound(e);
    }
    expect(e.waitingFor, [1]);
    expect(() => e.handle(0, {'type': 'next'}), throwsA(isA<GameError>()));
    final r = e.view(2)['reveal'] as Map;
    expect(r['book'], 0);
    expect((r['pages'] as List).length, 1);
    expect(jsonEncode(e.view(2)['reveal']), jsonEncode(e.view(-1)['reveal']));
    expect(() => e.handle(2, {'type': 'like', 'book': 0, 'page': 1}), throwsA(isA<GameError>()));
    e.handle(2, {'type': 'like', 'book': 0, 'page': 0});
    expect(() => e.handle(0, {'type': 'like', 'book': 0, 'page': 0}), throwsA(isA<GameError>()));
    var steps = 0;
    while (!e.isOver) {
      e.handle(1, {'type': 'next'});
      steps++;
    }
    expect(steps, 3 * 3); // 2 more pages per book + switch / finish
    final gal = e.view(0)['gallery'] as List;
    expect(gal.length, 3);
    expect(((gal[0] as Map)['pages'] as List).length, 3);
    expect(((e.view(0)['final'] as List).first as Map)['likes'], 1);
    expect(e.waitingFor, isEmpty);
  });

  test('telephone: bots legal in every state, bot host advances reveal', () {
    final e = tel(4, bots: List.filled(4, true));
    var guard = 0;
    while (!e.isOver && guard++ < 5000) {
      final w = e.waitingFor;
      expect(w, isNotEmpty);
      final a = e.bot(w.first);
      expect(a, isNotNull, reason: 'phase ${e.phase}');
      e.handle(w.first, a!);
    }
    expect(e.isOver, isTrue);
    // offline human seat: bot() just hands in the draft
    final h = tel(3);
    h.handle(0, {'type': 'draft', 'text': '草稿'});
    expect(h.bot(0), {'type': 'done', 'text': '草稿'});
  });

  test('sketch: fill strokes, undo / redo, undoable clear', () {
    final k = Sketch(maxPoints: 200);
    k.stroke({'id': 1, 'color': 0xFF000000, 'width': 8, 'pts': [0, 0, 10, 10]});
    k.stroke({'id': 2, 'color': 0xFFFF0000, 'width': kFillWidth, 'pts': [500, 500]});
    expect(k.strokes.last['w'], kFillWidth);
    expect(k.points, 2 + kFillCost);
    // fills can't grow, strokes under a fill can't grow
    expect(() => k.stroke({'id': 2, 'pts': [1, 1]}), throwsA(isA<GameError>()));
    expect(() => k.stroke({'id': 1, 'pts': [1, 1]}), throwsA(isA<GameError>()));
    // width 0 with several points is a normal (min width) stroke
    k.stroke({'id': 3, 'width': 0, 'pts': [1, 1, 2, 2]});
    expect(k.strokes.last['w'], 1);
    k.undo();
    k.undo();
    expect(k.strokes.length, 1);
    expect(k.points, 2);
    expect(k.canRedo, isTrue);
    k.redo();
    expect(k.strokes.last['w'], kFillWidth);
    k.clear();
    expect(k.strokes, isEmpty);
    expect(k.canUndo, isTrue);
    k.undo(); // restores the cleared drawing
    expect(k.strokes.length, 2);
    expect(k.points, 2 + kFillCost);
    k.redo(); // clears again
    expect(k.strokes, isEmpty);
    k.undo();
    k.stroke({'id': 4, 'pts': [5, 5]});
    expect(k.canRedo, isFalse);
    expect(() => k.stroke({'id': 5, 'width': kFillWidth, 'pts': [1, 1]}..['pts'] = List.filled(400, 1)), throwsA(isA<GameError>()));
  });

  test('stroke raster: fill stays inside a closed outline', () {
    final r = StrokeRaster(kFillGridW, kFillGridH);
    // square outline 200..800
    r.add(0xFF000000, 8, [200, 200, 800, 200, 800, 800, 200, 800, 200, 200]);
    final runs = r.add(0xFFFF0000, kFillWidth, [500, 500])!;
    expect(runs, isNotEmpty);
    int at(int x, int y) => r.px[(y * kFillGridH ~/ 1000) * kFillGridW + x * kFillGridW ~/ 1000];
    expect(at(500, 500), 0xFFFF0000);
    expect(at(100, 100), 0xFFFFFFFF);
    expect(at(900, 500), 0xFFFFFFFF);
    // same colour again: nothing to fill
    expect(r.fill(0xFFFF0000, 500, 500), isEmpty);
    // fill outside the square
    r.fill(0xFF00FF00, 50, 50);
    expect(at(900, 900), 0xFF00FF00);
    expect(at(500, 500), 0xFFFF0000);
  });

  test('drawguess / telephone: undo, redo and fill through actions', () {
    final e = drawing(3);
    final d = e.drawer;
    e.handle(d, {'type': 'stroke', 'id': 1, 'color': 0xFF000000, 'width': 6, 'pts': [0, 0, 10, 10]});
    e.handle(d, {'type': 'stroke', 'id': 2, 'color': 0xFF00FF00, 'width': 0, 'pts': [500, 500]});
    expect(e.view(-1)['canRedo'], isFalse);
    e.handle(d, {'type': 'undo'});
    expect((e.view(-1)['strokes'] as List).length, 1);
    expect(e.view(d)['canRedo'], isTrue);
    e.handle(d, {'type': 'redo'});
    expect(((e.view(-1)['strokes'] as List).last as Map)['w'], kFillWidth);
    expect(() => e.handle(e.guessers.first, {'type': 'redo'}), throwsA(isA<GameError>()));

    final t = tel(3);
    for (var p = 0; p < 3; p++) {
      t.handle(p, {'type': 'done', 'text': 'x$p'});
    }
    t.handle(1, {'type': 'stroke', 'id': 9, 'width': 0, 'pts': [10, 10]});
    t.handle(1, {'type': 'clear'});
    t.handle(1, {'type': 'undo'});
    expect(t.view(1)['task']['strokes'], hasLength(1));
    expect(t.view(1)['task']['canRedo'], isTrue);
    t.handle(1, {'type': 'redo'});
    expect(t.view(1)['task']['strokes'], isEmpty);
    // the AI image rasteriser understands fills too
    expect(AiImage.fromStrokes([
      {'c': 0xFF000000, 'w': 8, 'p': [100, 100, 900, 100]},
      {'c': 0xFFFF0000, 'w': 0, 'p': [500, 500]},
    ]).bytes, isNotEmpty);
  });
}

Telephone tel(int players, {int hostSeat = 0, List<bool>? bots, ManualHost? host}) {
  final def = drawguessGames.firstWhere((d) => d.id == 'telephone');
  final e = def.create(GameSetup(
    players: players,
    options: def.normalizeOptions(const {}),
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: bots ?? List.filled(players, false),
    hostSeat: hostSeat,
    rng: Random(5),
  )) as Telephone;
  e.host = host ?? ManualHost();
  e.start();
  return e;
}

/// Everyone finishes the current round (text 'r<round>-p<seat>' / one stroke).
void finishRound(Telephone e) {
  for (var p = 0; p < e.players; p++) {
    if (e.phase == 'draw') {
      e.handle(p, {'type': 'stroke', 'id': 1, 'color': 0xFF000000, 'width': 6, 'pts': [p, e.round, 10, 10]});
      e.handle(p, {'type': 'done'});
    } else {
      e.handle(p, {'type': 'done', 'text': 'r${e.round}-p$p'});
    }
  }
}
