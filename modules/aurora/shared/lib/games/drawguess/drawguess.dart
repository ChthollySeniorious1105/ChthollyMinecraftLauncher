import 'dart:math' as m;

import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import '../../src/strokes.dart';
import 'ai_draw.dart';
import 'pool.dart';

/// 你画我猜
///
/// Phases: gmword (GM 出题) | choose (画手选词) → draw → reveal → … → over.
/// Timers are chained via [GameHost.schedule]: the drawing phase is split into
/// 3 stages (hints revealed at 1/3 and 2/3), the last stage ends the round.
class DrawGuess extends GameEngine {
  DrawGuess(super.setup);

  static const chooseMs = 15000;
  static const revealMs = 5000;
  static const maxPoints = 20000;
  static const maxBatch = 600; // ints per stroke batch
  static const maxStrokes = 800;
  static const maxGuessLen = 20;
  static const maxFeed = 200;
  static const guesserPoints = [10, 8, 6, 5, 4, 3];
  static const drawerPerGuess = 2;

  late final List<DrawWord> pool;
  late final bool gmMode;
  late final bool pick3;
  late final bool hints;
  late final int timeSec;
  int gm = -1;

  /// Non-GM seats, in drawing order.
  List<int> drawers = [];
  int totalRounds = 0;
  int roundIdx = 0; // 1-based once started
  int drawer = -1;
  String phase = 'init';

  String word = '';
  String category = '';
  List<String> choices = [];
  final Set<String> _used = {};

  /// Drawing stage 0..2 (hint level); 3 = over.
  int stage = 0;
  int endsAt = 0;
  List<int> revealPos = [];

  late List<int> scores;
  late List<bool> guessed;
  final List<int> correctOrder = [];
  final Map<int, int> gains = {};

  /// Drawing of the current round.
  final sketch = Sketch(maxPoints: maxPoints, maxBatch: maxBatch, maxStrokes: maxStrokes);
  List<Map<String, dynamic>> get strokes => sketch.strokes;
  int get pointCount => sketch.points;

  /// Feed: {'s': seat, 't': text, 'k': 'guess'|'close'|'right'|'sys'}.
  final List<Map<String, dynamic>> feed = [];

  /// Result of the last finished round.
  Map<String, dynamic>? roundResult;
  List<Map<String, dynamic>>? finalRanking;

  // bot bookkeeping (per round)
  final Map<int, int> _botGuesses = {};
  final Map<int, Set<String>> _botTried = {};
  int _botStrokes = 0;
  int _botStrokeId = 1000000;
  final AiSlot _ai = AiSlot();
  // LLM drawing for the current round: null = not asked yet, [] = failed.
  List<List<int>>? _aiDraw;
  int _aiDrawIdx = 0;
  final Set<String> _aiUsed = {};

  int _epoch = 0;
  final List<void Function()> _cancels = [];

  bool get isGm => gmMode;
  List<int> get guessers => [for (final s in drawers) if (s != drawer) s];

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver || finalRanking == null) return null;
    final r = List.filled(players, 1); // 出题人不参与排名
    for (final e in finalRanking!) {
      r[e['s'] as int] = e['rank'] as int;
    }
    return r;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void start() {
    gmMode = setup.opt<String>('mode', 'bank') == 'gm';
    pick3 = setup.opt<String>('pick', 'choose3') == 'choose3';
    hints = setup.opt<bool>('hints', true);
    timeSec = setup.opt<int>('time', 80);
    final perPlayer = setup.opt<int>('rounds', 1);
    pool = buildWordPool(setup.opt<String>('words', 'both'), setup.resourceLines('drawguess.words'), host.log);
    scores = List.filled(players, 0);
    guessed = List.filled(players, false);
    if (gmMode) {
      if (players < 4) throw GameError('GM出题模式至少需要 4 名玩家');
      gm = (setup.hostSeat >= 0 && setup.hostSeat < players) ? setup.hostSeat : 0;
    }
    drawers = [for (var s = 0; s < players; s++) if (s != gm) s];
    totalRounds = drawers.length * perPlayer;
    host.log('你画我猜开始！共 $totalRounds 轮，每轮 $timeSec 秒${gm >= 0 ? '，出题人：${name(gm)}' : ''}');
    _nextRound();
  }

  // ------------------------------------------------------------ flow

  void _cancelTimers() {
    _epoch++;
    for (final c in _cancels) {
      c();
    }
    _cancels.clear();
  }

  void _after(int ms, void Function() fn) {
    final ep = _epoch;
    _cancels.add(host.schedule(ms, () {
      if (ep != _epoch || isOver) return;
      fn();
    }));
  }

  void _nextRound() {
    _cancelTimers();
    if (roundIdx >= totalRounds) {
      _finish();
      return;
    }
    roundIdx++;
    drawer = drawers[(roundIdx - 1) % drawers.length];
    word = '';
    category = '';
    choices = [];
    stage = 0;
    revealPos = [];
    sketch.reset();
    feed.clear();
    correctOrder.clear();
    gains.clear();
    guessed = List.filled(players, false);
    _botGuesses.clear();
    _botTried.clear();
    _botStrokes = 0;
    _aiDraw = null;
    _aiDrawIdx = 0;
    _aiUsed.clear();
    if (gmMode) {
      phase = 'gmword';
      endsAt = 0;
      host.log('第 $roundIdx/$totalRounds 轮：${name(drawer)} 作画，等待出题人出题…');
    } else if (pick3) {
      phase = 'choose';
      choices = _drawWords(3).map((w) => w.word).toList();
      endsAt = _now() + chooseMs;
      host.log('第 $roundIdx/$totalRounds 轮：${name(drawer)} 正在选词…');
      _after(chooseMs, () {
        if (phase == 'choose') _setWord(choices.first);
      });
    } else {
      final w = _drawWords(1).first;
      host.log('第 $roundIdx/$totalRounds 轮：${name(drawer)} 作画');
      _beginDraw(w.word, w.category);
    }
  }

  List<DrawWord> _drawWords(int n) {
    var avail = [for (final w in pool) if (!_used.contains(w.word)) w];
    if (avail.length < n) {
      _used.clear();
      avail = List.of(pool);
    }
    final picked = <DrawWord>[];
    final seen = <String>{};
    while (picked.length < n && seen.length < avail.length) {
      final w = avail[rng.nextInt(avail.length)];
      if (seen.add(w.word)) picked.add(w);
    }
    return picked;
  }

  String _catOf(String w) {
    for (final e in pool) {
      if (e.word == w) return e.category;
    }
    return '';
  }

  void _setWord(String w) => _beginDraw(w, _catOf(w));

  void _beginDraw(String w, String cat) {
    _cancelTimers();
    word = w;
    category = cat;
    _used.add(w);
    choices = [];
    phase = 'draw';
    stage = 0;
    // pick the character revealed at stage 2 (never whitespace)
    final chars = word.split('');
    revealPos = chars.length > 1 ? [rng.nextInt(chars.length)] : [];
    endsAt = _now() + timeSec * 1000;
    final part = timeSec * 1000 ~/ 3;
    void stageUp() {
      if (phase != 'draw') return;
      stage++;
      if (stage >= 3) {
        _endRound('time');
      } else {
        if (hints) host.log(stage == 1 ? '提示：${category.isEmpty ? '（无类别）' : category}' : '提示：揭示一个字');
        _after(part, stageUp);
      }
    }

    _after(part, stageUp);
  }

  void _endRound(String reason) {
    if (phase != 'draw') return;
    _cancelTimers();
    final got = correctOrder.length;
    if (got > 0) {
      final g = got * drawerPerGuess;
      scores[drawer] += g;
      gains[drawer] = (gains[drawer] ?? 0) + g;
    }
    roundResult = {
      'round': roundIdx,
      'word': word,
      'cat': category,
      'drawer': drawer,
      'reason': reason,
      'correct': List<int>.of(correctOrder),
      'gains': [for (final e in gains.entries) [e.key, e.value]],
    };
    final why = switch (reason) {
      'all' => '所有人都猜对了！',
      'gm' => '出题人结束了本轮。',
      _ => '时间到！',
    };
    host.log('$why 答案是「$word」，$got 人猜对');
    phase = 'reveal';
    endsAt = _now() + revealMs;
    _after(revealMs, _nextRound);
  }

  void _finish() {
    _cancelTimers();
    phase = 'over';
    endsAt = 0;
    final order = List.of(drawers)..sort((a, b) => scores[b] != scores[a] ? scores[b] - scores[a] : a - b);
    finalRanking = [];
    var rank = 0;
    for (var i = 0; i < order.length; i++) {
      if (i == 0 || scores[order[i]] != scores[order[i - 1]]) rank = i + 1;
      finalRanking!.add({'s': order[i], 'score': scores[order[i]], 'rank': rank});
    }
    host.log('游戏结束！冠军：${[for (final r in finalRanking!) if (r['rank'] == 1) name(r['s'] as int)].join('、')}');
  }

  // ------------------------------------------------------------ actions

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'gmword':
        return [gm];
      case 'choose':
        return [drawer];
      case 'draw':
        return [
          if (isBot(drawer) &&
              (_aiDraw != null && _aiDraw!.isNotEmpty ? _aiDrawIdx < _aiDraw!.length : _botStrokes < 3 + stage * 2))
            drawer,
          for (final s in guessers)
            if (isBot(s) && !guessed[s] && (_botGuesses[s] ?? 0) < 2 + stage * 2) s,
        ];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final type = asStr(a['type']);
    switch (type) {
      case 'gmword':
        if (seat != gm || gm < 0) throw GameError('只有出题人可以出题');
        if (phase != 'gmword') throw GameError('现在不是出题阶段');
        final w = normWord(sanitizeText(asStr(a['word'])));
        if (w.isEmpty) throw GameError('词语不能为空');
        if (w.length > kMaxWordLen) throw GameError('词语最多 $kMaxWordLen 个字');
        final hint = sanitizeText(asStr(a['hint'])).trim();
        if (hint.length > kMaxCatLen) throw GameError('类别提示最多 $kMaxCatLen 个字');
        host.log('出题人已出题，${name(drawer)} 开始作画！');
        _beginDraw(w, hint);
      case 'choose':
        if (phase != 'choose') throw GameError('现在不是选词阶段');
        if (seat != drawer) throw GameError('只有画手可以选词');
        final w = asStr(a['word']);
        if (!choices.contains(w)) throw GameError('请从给出的词语中选择');
        host.log('${name(drawer)} 选好了词，开始作画！');
        _setWord(w);
      case 'stroke':
        _needDrawer(seat);
        sketch.stroke(a);
      case 'undo':
        _needDrawer(seat);
        sketch.undo();
      case 'redo':
        _needDrawer(seat);
        sketch.redo();
      case 'clear':
        _needDrawer(seat);
        sketch.clear();
      case 'guess':
        _guess(seat, sanitizeText(asStr(a['text'])));
      case 'gmskip':
        if (seat != gm || gm < 0) throw GameError('只有出题人可以结束本轮');
        if (phase != 'draw') throw GameError('现在不能结束本轮');
        _endRound('gm');
      default:
        throw GameError('未知操作');
    }
  }

  void _needDrawer(int seat) {
    if (phase != 'draw') throw GameError('现在不能作画');
    if (seat != drawer) throw GameError('只有画手可以作画');
  }

  static String _norm(String s) => normWord(s).toLowerCase();

  void _guess(int seat, String text) {
    if (phase != 'draw') throw GameError('现在不能猜词');
    if (seat == gm) throw GameError('出题人不能猜词');
    if (seat == drawer) throw GameError('画手不能猜词');
    if (seat < 0 || seat >= players) throw GameError('观众不能猜词');
    if (guessed[seat]) throw GameError('你已经猜对了，等待其他人吧');
    final t = text.trim();
    if (t.isEmpty) throw GameError('请输入你的答案');
    if (t.length > maxGuessLen) throw GameError('答案最多 $maxGuessLen 个字');
    final g = _norm(t);
    final ans = _norm(word);
    if (g == ans) {
      guessed[seat] = true;
      final i = correctOrder.length;
      correctOrder.add(seat);
      final pts = i < guesserPoints.length ? guesserPoints[i] : 2;
      scores[seat] += pts;
      gains[seat] = (gains[seat] ?? 0) + pts;
      _addFeed({'s': seat, 't': t, 'k': 'right', 'pts': pts});
      host.log('${name(seat)} 猜对了！');
      if (guessers.every((s) => guessed[s])) _endRound('all');
      return;
    }
    final close = isClose(g, ans);
    _addFeed({'s': seat, 't': t, 'k': close ? 'close' : 'guess'});
  }

  /// A near miss: shares at least one character with the answer.
  static bool isClose(String guess, String answer) {
    final a = answer.split('').toSet();
    return guess.split('').any(a.contains);
  }

  void _addFeed(Map<String, dynamic> e) {
    feed.add(e);
    if (feed.length > maxFeed) feed.removeAt(0);
  }

  // ------------------------------------------------------------ view

  String roleOf(int seat) {
    if (seat < 0 || seat >= players) return 'spectator';
    if (seat == gm) return 'gm';
    if (seat == drawer && phase != 'over') return 'drawer';
    return 'guesser';
  }

  /// Hint data visible to everyone during drawing.
  Map<String, dynamic>? _hint() {
    if (phase != 'draw') return null;
    if (!hints) return {'on': false};
    final chars = word.split('');
    return {
      'on': true,
      'len': chars.length,
      'cat': stage >= 1 ? category : null,
      'catShown': stage >= 1,
      'chars': [
        for (var i = 0; i < chars.length; i++) stage >= 2 && revealPos.contains(i) ? chars[i] : null,
      ],
    };
  }

  @override
  Map<String, dynamic> view(int seat) {
    final role = roleOf(seat);
    final mine = seat >= 0 && seat < players;
    // Only the drawer and the GM may see the answer before the reveal.
    final full = role == 'gm' || (mine && seat == drawer);
    final knows = full || phase == 'reveal' || phase == 'over';
    return {
      'phase': phase,
      'mode': gmMode ? 'gm' : 'bank',
      'gm': gm,
      'drawer': drawer,
      'drawers': drawers,
      'round': roundIdx,
      'totalRounds': totalRounds,
      'timeSec': timeSec,
      'endsAt': endsAt,
      'now': _now(),
      'scores': scores,
      'guessed': guessed,
      'myRole': role,
      'word': knows && phase != 'gmword' && phase != 'choose' ? word : null,
      'wordCat': knows && phase != 'gmword' && phase != 'choose' ? category : null,
      'choices': seat == drawer && phase == 'choose' ? choices : null,
      'hint': _hint(),
      'strokes': phase == 'draw' || phase == 'reveal' || phase == 'over'
          ? sketch.toJson()
          : const [],
      'points': pointCount,
      'canUndo': sketch.canUndo,
      'canRedo': sketch.canRedo,
      'maxPoints': maxPoints,
      'feed': [
        for (final e in feed)
          {
            's': e['s'],
            'k': e['k'],
            't': (e['k'] == 'guess' || full || e['s'] == seat) ? e['t'] : null,
            if (e['pts'] != null) 'pts': e['pts'],
          }
      ],
      'roundResult': phase == 'reveal' || phase == 'over' ? roundResult : null,
      'final': finalRanking,
    };
  }

  // ------------------------------------------------------------ bots

  @override
  int get botDelayMs => phase == 'draw' ? 2200 : 1200;

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'gmword':
        if (seat != gm) return null;
        final w = _drawWords(1).first;
        return {'type': 'gmword', 'word': w.word, 'hint': w.category};
      case 'choose':
        if (seat != drawer || choices.isEmpty) return null;
        return {'type': 'choose', 'word': choices[rng.nextInt(choices.length)]};
      case 'draw':
        if (seat == drawer) {
          if (aiOn && _aiDraw == null) {
            final r = _ai.poll(setup.ai!, 'draw:$roundIdx', () => aiDrawRequest(word));
            if (r.pending) return null;
            _aiDraw = parseAiStrokes(r.text) ?? const [];
          }
          final d = _aiDraw;
          if (d != null && d.isNotEmpty) {
            if (_aiDrawIdx >= d.length) return null;
            if (pointCount + d[_aiDrawIdx].length ~/ 2 > maxPoints || strokes.length >= maxStrokes) return null;
            _botStrokes++;
            return {'type': 'stroke', 'id': _botStrokeId++, 'color': 0xFF222222, 'width': 8, 'pts': d[_aiDrawIdx++]};
          }
          return _botStroke();
        }
        if (seat == gm || guessed[seat] || !guessers.contains(seat)) return null;
        if (aiOn && setup.ai!.vision && strokes.isNotEmpty) {
          final a = _aiGuess(seat);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        return _botGuess(seat);
      default:
        return null;
    }
  }

  Map<String, dynamic> _botStroke() {
    _botStrokes++;
    final pts = <int>[];
    final kind = rng.nextInt(4);
    final cx = 200 + rng.nextInt(600), cy = 200 + rng.nextInt(600);
    final r = 60 + rng.nextInt(180);
    int c(int v) => v.clamp(0, 1000);
    switch (kind) {
      case 0: // circle
        for (var i = 0; i <= 24; i++) {
          final t = i / 24 * 6.2832;
          pts.addAll([c(cx + (r * _cos(t)).round()), c(cy + (r * _sin(t)).round())]);
        }
      case 1: // rectangle
        final w = r, h = (r * 0.7).round();
        pts.addAll([c(cx - w), c(cy - h), c(cx + w), c(cy - h), c(cx + w), c(cy + h), c(cx - w), c(cy + h), c(cx - w), c(cy - h)]);
      case 2: // zigzag
        for (var i = 0; i < 8; i++) {
          pts.addAll([c(cx - r + i * r ~/ 4), c(cy + (i.isEven ? -r ~/ 3 : r ~/ 3))]);
        }
      default: // line
        pts.addAll([c(cx - r), c(cy - rng.nextInt(r)), c(cx + r), c(cy + rng.nextInt(r))]);
    }
    const colors = [0xFF222222, 0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFB8C00, 0xFF8E24AA];
    return {'type': 'stroke', 'id': _botStrokeId++, 'color': colors[rng.nextInt(colors.length)], 'width': 4 + rng.nextInt(3) * 4, 'pts': pts};
  }

  static const Map<String, dynamic> _wait = {'_pending': true};

  /// LLM guess from the picture + visible hints. At most 3 asks per round per
  /// seat (key = round, seat, progress bucket). `_wait` = pending, null = use
  /// the heuristic.
  Map<String, dynamic>? _aiGuess(int seat) {
    final bucket = m.max(stage, m.min(2, strokes.length ~/ 6));
    final key = 'guess:$roundIdx:$seat:$bucket';
    if (_aiUsed.contains(key)) return null;
    final v = view(seat);
    final h = v['hint'] as Map<String, dynamic>?;
    final len = h?['on'] == true ? h!['len'] as int? : null;
    final mine = <String>{
      for (final e in v['feed'] as List)
        if (e['s'] == seat && e['t'] is String) _norm(e['t'] as String),
      ...?_botTried[seat],
    };
    final others = <String>[
      for (final e in v['feed'] as List)
        if (e['k'] == 'guess' && e['s'] != seat && e['t'] is String) e['t'] as String,
    ];
    final r = _ai.poll(setup.ai!, key, () {
      final p = StringBuffer('这是“你画我猜”游戏中画手正在画的画（可能还没画完）。请猜出画的是什么词语。\n');
      if (len != null) p.writeln('提示：答案是 $len 个字。');
      final cat = h?['catShown'] == true ? h!['cat'] as String? : null;
      if (cat != null && cat.isNotEmpty) p.writeln('提示：类别是「$cat」。');
      final chars = h?['chars'] as List?;
      if (chars != null && chars.any((c) => c is String)) {
        p.writeln('提示：已揭示的字：${[for (final c in chars) c is String ? c : '＿'].join()}');
      }
      if (mine.isNotEmpty) p.writeln('你已经猜错过：${mine.join('、')}（不要重复）');
      if (others.isNotEmpty) p.writeln('别人猜错过：${others.take(15).join('、')}');
      p.write('只输出你猜的一个中文词语，不要任何解释或标点。');
      return AiRequest(
          system: '你是一个擅长看简笔画猜词的玩家。',
          prompt: p.toString(),
          images: [AiImage.fromStrokes([for (final s in strokes) {'c': s['c'], 'w': s['w'], 'p': s['p']}])],
          maxTokens: 30);
    });
    if (r.pending) return _wait;
    _aiUsed.add(key);
    final t = aiLine(r.text, maxGuessLen);
    if (t == null) return null;
    final g = _norm(sanitizeText(t));
    if (g.isEmpty || g.length > maxGuessLen || mine.contains(g)) return null;
    if (len != null && g.length != len) return null;
    _botGuesses[seat] = (_botGuesses[seat] ?? 0) + 1;
    (_botTried[seat] ??= {}).add(g);
    return {'type': 'guess', 'text': g};
  }

  /// Guesses using ONLY what this seat's view shows (hint length/category/char).
  Map<String, dynamic> _botGuess(int seat) {
    _botGuesses[seat] = (_botGuesses[seat] ?? 0) + 1;
    final h = view(seat)['hint'] as Map<String, dynamic>?;
    final len = h?['len'] as int?;
    final cat = h?['catShown'] == true ? h!['cat'] as String? : null;
    final known = <int, String>{};
    final chars = h?['chars'] as List?;
    if (chars != null) {
      for (var i = 0; i < chars.length; i++) {
        if (chars[i] is String) known[i] = chars[i] as String;
      }
    }
    final tried = _botTried[seat] ??= {};
    bool fits(DrawWord w) {
      if (tried.contains(w.word)) return false;
      if (len != null && w.word.length != len) return false;
      if (cat != null && cat.isNotEmpty && w.category != cat) return false;
      for (final e in known.entries) {
        if (e.key >= w.word.length || w.word[e.key] != e.value) return false;
      }
      return true;
    }

    // 简单: often ignores the hints
    var cands = botLevel == 0 && rng.nextInt(2) == 0 ? <DrawWord>[] : [for (final w in pool) if (fits(w)) w];
    if (cands.isEmpty) cands = [for (final w in pool) if (!tried.contains(w.word)) w];
    final pick = cands.isEmpty ? '不知道' : cands[rng.nextInt(cands.length)].word;
    tried.add(pick);
    return {'type': 'guess', 'text': pick};
  }
}

double _sin(double x) => m.sin(x);
double _cos(double x) => m.cos(x);
