import 'dart:math' as m;

import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import '../../src/strokes.dart';
import 'ai_draw.dart';
import 'pool.dart';

/// 传话画画 (Gartic Phone classic).
///
/// Every player owns one "book". Round 0: everyone writes a prompt into their
/// own book. Then rounds alternate 作画 / 描述; in round r player p works on
/// book (p - r) mod n, so over n rounds every player touches every book exactly
/// once and never gets their own book back. Each player only sees the previous
/// page of the book in hand. After the last round the books are revealed page
/// by page; the host (setup.hostSeat) turns the pages.
///
/// Phases: write | draw | describe | reveal | over.
class Telephone extends GameEngine {
  Telephone(super.setup);

  static const maxText = 40;
  static const maxPoints = 20000;
  static const maxBatch = 600; // ints per stroke batch
  static const maxStrokes = 800;
  static const emptyText = '（没写）';

  late final List<DrawWord> pool;
  late final int drawSec;
  late final int writeSec;

  /// books[b] = pages of the book started by seat b.
  /// Page: {'k': 'text'|'draw', 's': author, 't': text, 'sketch': Sketch,
  /// 'strokes': sketch.strokes, 'likes': Set<int>}
  final List<List<Map<String, dynamic>>> books = [];

  String phase = 'init';
  int round = -1; // 0-based
  int endsAt = 0;
  late List<bool> done;
  late List<String> drafts;

  /// Reveal cursor: book index and number of its pages shown (1..n).
  int revealBook = 0;
  int revealShown = 0;
  int revealer = 0;

  final Map<int, int> _botStrokes = {};
  final AiSlot _ai = AiSlot();
  // LLM drawings per seat for the current round ([] = failed → heuristic).
  final Map<int, List<List<int>>> _aiDraw = {};
  int _botStrokeId = 900000000;
  int _epoch = 0;
  final List<void Function()> _cancels = [];

  int get totalRounds => players;

  @override
  bool get isOver => phase == 'over';

  /// Party game without scoring: everyone shares 1st place.
  @override
  List<int>? get placings => isOver ? List.filled(players, 1) : null;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Book that seat [p] works on in round [r].
  static int bookFor(int p, int r, int n) => ((p - r) % n + n) % n;

  /// Kind of work in round [r]: write (0), then draw / describe alternately.
  static String kindOf(int r) => r == 0 ? 'write' : (r.isOdd ? 'draw' : 'describe');

  int bookOf(int seat) => bookFor(seat, round, players);

  Map<String, dynamic> pageOf(int seat) => books[bookOf(seat)][round];

  @override
  void start() {
    if (players < 3) throw GameError('传话画画至少需要 3 名玩家');
    drawSec = setup.opt<int>('draw', 90);
    writeSec = setup.opt<int>('write', 45);
    pool = drawWordBank;
    revealer = (setup.hostSeat >= 0 && setup.hostSeat < players) ? setup.hostSeat : 0;
    for (var b = 0; b < players; b++) {
      books.add([]);
    }
    host.log('传话画画开始！共 $totalRounds 轮：先写一句话，然后轮流作画和描述');
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
    if (round + 1 >= totalRounds) {
      _beginReveal();
      return;
    }
    round++;
    phase = kindOf(round);
    done = List.filled(players, false);
    drafts = List.filled(players, '');
    _botStrokes.clear();
    _aiDraw.clear();
    for (var p = 0; p < players; p++) {
      final b = bookFor(p, round, players);
      assert(books[b].length == round);
      final sketch = Sketch(maxPoints: maxPoints, maxBatch: maxBatch, maxStrokes: maxStrokes);
      books[b].add({
        'k': phase == 'draw' ? 'draw' : 'text',
        's': p,
        't': '',
        'sketch': sketch,
        'strokes': sketch.strokes,
        'likes': <int>{},
      });
    }
    final sec = phase == 'draw' ? drawSec : writeSec;
    endsAt = _now() + sec * 1000;
    final label = switch (phase) { 'write' => '写题目', 'draw' => '作画', _ => '描述' };
    host.log('第 ${round + 1}/$totalRounds 轮：$label（$sec 秒）');
    _after(sec * 1000, _timeout);
  }

  void _timeout() {
    if (phase != 'write' && phase != 'draw' && phase != 'describe') return;
    var auto = 0;
    for (var p = 0; p < players; p++) {
      if (!done[p]) {
        _submit(p, drafts[p]);
        auto++;
      }
    }
    if (auto > 0) host.log('时间到！$auto 人的作品已自动提交');
    _nextRound();
  }

  String _randomWord() => pool[rng.nextInt(pool.length)].word;

  /// Finalises seat [p]'s page for this round.
  void _submit(int p, String text) {
    final page = pageOf(p);
    if (phase != 'draw') {
      var t = text.trim();
      if (t.isEmpty) t = phase == 'write' ? _randomWord() : emptyText;
      page['t'] = t;
    }
    done[p] = true;
  }

  void _beginReveal() {
    _cancelTimers();
    phase = 'reveal';
    endsAt = 0;
    revealBook = 0;
    revealShown = 1;
    host.log('所有本子都完成了！开始展示，由 ${name(revealer)} 翻页');
  }

  void _finish() {
    _cancelTimers();
    phase = 'over';
    endsAt = 0;
    host.log('展示结束！可以在画廊里回顾所有本子');
  }

  // ------------------------------------------------------------ actions

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'write':
      case 'draw':
      case 'describe':
        return [for (var p = 0; p < players; p++) if (!done[p]) p];
      case 'reveal':
        return [revealer];
      default:
        return const [];
    }
  }

  static String cleanText(String raw) {
    final t = sanitizeText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static int textLen(String s) => s.runes.length;

  static String clip(String s) => textLen(s) <= maxText ? s : String.fromCharCodes(s.runes.take(maxText));

  bool get _working => phase == 'write' || phase == 'draw' || phase == 'describe';

  void _needWorker(int seat) {
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    if (!_working) throw GameError('现在不是作答阶段');
    if (done[seat]) throw GameError('你已经完成了，等待其他人吧');
  }

  void _needDrawer(int seat) {
    _needWorker(seat);
    if (phase != 'draw') throw GameError('现在不是作画阶段');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (isOver && type != 'like') throw GameError('对局已结束');
    switch (type) {
      case 'draft':
        // Silently ignored when not applicable (sent in the background).
        if (seat < 0 || seat >= players || !_working || done[seat] || phase == 'draw') return;
        drafts[seat] = clip(cleanText(asStr(a['text'])));
      case 'done':
        _needWorker(seat);
        if (phase != 'draw') {
          final t = cleanText(asStr(a['text']));
          if (textLen(t) > maxText) throw GameError('最多 $maxText 个字');
          _submit(seat, t);
        } else {
          _submit(seat, '');
        }
        if (done.every((d) => d)) _nextRound();
      case 'stroke':
        _needDrawer(seat);
        _sketchOf(seat).stroke(a);
      case 'undo':
        _needDrawer(seat);
        _sketchOf(seat).undo();
      case 'redo':
        _needDrawer(seat);
        _sketchOf(seat).redo();
      case 'clear':
        _needDrawer(seat);
        _sketchOf(seat).clear();
      case 'next':
        if (phase != 'reveal') throw GameError('现在不是展示阶段');
        if (seat != revealer) throw GameError('只有房主可以翻页');
        if (revealShown < books[revealBook].length) {
          revealShown++;
        } else if (revealBook + 1 < books.length) {
          revealBook++;
          revealShown = 1;
        } else {
          _finish();
        }
      case 'like':
        _like(seat, asInt(a['book']), asInt(a['page']));
      default:
        throw GameError('未知操作');
    }
  }

  bool _revealed(int b, int i) {
    if (phase == 'over') return true;
    if (phase != 'reveal') return false;
    return b < revealBook || (b == revealBook && i < revealShown);
  }

  void _like(int seat, int b, int i) {
    if (seat < 0 || seat >= players) throw GameError('观众不能点赞');
    if (b < 0 || b >= books.length || i < 0 || i >= books[b].length) throw GameError('无效页面');
    if (!_revealed(b, i)) throw GameError('这一页还没有展示');
    final page = books[b][i];
    if (page['s'] == seat) throw GameError('不能给自己点赞');
    final likes = page['likes'] as Set<int>;
    if (!likes.remove(seat)) likes.add(seat);
  }

  // ------------------------------------------------------------ view

  Sketch _sketchOf(int seat) => pageOf(seat)['sketch'] as Sketch;

  static List<Map<String, dynamic>> _strokesJson(Map<String, dynamic> page) => (page['sketch'] as Sketch).toJson();

  Map<String, dynamic> _pageJson(Map<String, dynamic> page) {
    final likes = (page['likes'] as Set<int>).toList()..sort();
    return {
      'k': page['k'],
      's': page['s'],
      if (page['k'] == 'text') 't': page['t'],
      if (page['k'] == 'draw') 'strokes': _strokesJson(page),
      'likes': likes,
    };
  }

  /// The single previous page of the book [seat] works on (content only).
  Map<String, dynamic>? _prevOf(int seat) {
    if (round <= 0) return null;
    final prev = books[bookOf(seat)][round - 1];
    return prev['k'] == 'draw' ? {'k': 'draw', 'strokes': _strokesJson(prev)} : {'k': 'text', 't': prev['t']};
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final v = <String, dynamic>{
      'phase': phase,
      'round': round + 1,
      'totalRounds': totalRounds,
      'drawSec': drawSec,
      'writeSec': writeSec,
      'endsAt': endsAt,
      'now': _now(),
      'done': _working ? List<bool>.of(done) : List<bool>.filled(players, true),
      'revealer': revealer,
      'maxText': maxText,
      'maxPoints': maxPoints,
    };
    if (_working && me) {
      final page = pageOf(seat);
      v['task'] = {
        'kind': phase,
        'done': done[seat],
        'prev': _prevOf(seat),
        if (phase == 'draw') 'strokes': _strokesJson(page),
        if (phase == 'draw') 'points': (page['sketch'] as Sketch).points,
        if (phase == 'draw') 'canUndo': (page['sketch'] as Sketch).canUndo,
        if (phase == 'draw') 'canRedo': (page['sketch'] as Sketch).canRedo,
        if (phase != 'draw') 'text': done[seat] ? page['t'] : drafts[seat],
      };
    }
    if (phase == 'reveal') {
      final pages = books[revealBook];
      v['reveal'] = {
        'book': revealBook,
        'owner': revealBook,
        'bookCount': books.length,
        'shown': revealShown,
        'pageCount': pages.length,
        'pages': [for (var i = 0; i < revealShown; i++) _pageJson(pages[i])],
      };
    }
    if (phase == 'over') {
      v['gallery'] = [
        for (var b = 0; b < books.length; b++) {'owner': b, 'pages': [for (final p in books[b]) _pageJson(p)]}
      ];
      v['final'] = _best();
    }
    return v;
  }

  /// Most liked pages (for the end screen).
  List<Map<String, dynamic>> _best() {
    var top = 0;
    final out = <Map<String, dynamic>>[];
    for (var b = 0; b < books.length; b++) {
      for (var i = 0; i < books[b].length; i++) {
        final n = (books[b][i]['likes'] as Set<int>).length;
        if (n == 0 || n < top) continue;
        if (n > top) {
          top = n;
          out.clear();
        }
        out.add({'book': b, 'page': i, 's': books[b][i]['s'], 'likes': n});
      }
    }
    return out;
  }

  // ------------------------------------------------------------ bots

  @override
  int get botDelayMs => switch (phase) { 'draw' => 1500, 'reveal' => 2500, _ => 2000 };

  static const Map<String, dynamic> _wait = {'_pending': true};

  /// LLM text for write/describe. `_wait` = pending, null = heuristic.
  Map<String, dynamic>? _aiText(int seat) {
    final prev = round > 0 ? books[bookOf(seat)][round - 1] : null;
    if (phase == 'describe') {
      final strokes = prev == null ? const <Map<String, dynamic>>[] : prev['strokes'] as List<Map<String, dynamic>>;
      if (!setup.ai!.vision || strokes.isEmpty) return null;
      final r = _ai.poll(setup.ai!, 'desc:$round:$seat', () => AiRequest(
          system: '你在玩“传话画画”：上一位玩家根据一句话画了这幅简笔画，你要用一句话描述画的内容，传给下一位玩家去画。',
          prompt: '请用一句简短、有画面感的中文描述这幅画画的是什么（不超过 20 个字）。只输出这句话。',
          images: [AiImage.fromStrokes([for (final s in strokes) {'c': s['c'], 'w': s['w'], 'p': s['p']}])],
          maxTokens: 60));
      if (r.pending) return _wait;
      final t = aiLine(r.text, maxText);
      return t == null ? null : {'type': 'done', 'text': cleanText(t)};
    }
    if (phase == 'write') {
      final r = _ai.poll(setup.ai!, 'write:$seat', () => AiRequest(
          system: '你在玩“传话画画”：每人先写一句话，下一位玩家要把它画出来，再下一位根据画描述，看看意思会跑偏多远。',
          prompt: '请写一句有趣、有画面感、适合画出来的中文短句（8~20 个字，例如“一只企鹅在沙漠里卖冰淇淋”）。'
              '灵感词（可用可不用）：${_randomWord()}。只输出这句话。',
          maxTokens: 60));
      if (r.pending) return _wait;
      final t = aiLine(r.text, maxText);
      return t == null ? null : {'type': 'done', 'text': cleanText(t)};
    }
    return null;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (seat < 0 || seat >= players) return null;
    switch (phase) {
      case 'write':
      case 'describe':
        if (done[seat]) return null;
        final draft = drafts[seat];
        // A human seat driven by the server (offline / turn timeout) just
        // hands in what it has typed so far.
        if (!isBot(seat)) return {'type': 'done', 'text': draft};
        if (aiOn && draft.isEmpty) {
          final a = _aiText(seat);
          if (identical(a, _wait)) return null;
          if (a != null && textLen(a['text'] as String) > 0) return a;
        }
        return {'type': 'done', 'text': draft.isNotEmpty ? draft : _randomWord()};
      case 'draw':
        if (done[seat]) return null;
        if (!isBot(seat)) return {'type': 'done'};
        final page = pageOf(seat);
        if (aiOn && !_aiDraw.containsKey(seat)) {
          final prev = books[bookOf(seat)][round - 1];
          final subject = prev['t'] as String;
          final r = _ai.poll(setup.ai!, 'draw:$round:$seat', () => aiDrawRequest(subject));
          if (r.pending) return null;
          _aiDraw[seat] = parseAiStrokes(r.text) ?? const [];
        }
        final n = _botStrokes[seat] ?? 0;
        final ai = _aiDraw[seat];
        final useAi = ai != null && ai.isNotEmpty;
        final target = useAi ? ai.length : 3 + (seat + round) % 3;
        if (n >= target ||
            (page['sketch'] as Sketch).points + (useAi ? ai[n].length ~/ 2 : 30) > maxPoints ||
            (page['strokes'] as List).length >= maxStrokes) {
          return {'type': 'done'};
        }
        _botStrokes[seat] = n + 1;
        if (useAi) return {'type': 'stroke', 'id': _botStrokeId++, 'color': 0xFF222222, 'width': 8, 'pts': ai[n]};
        return _botStroke();
      case 'reveal':
        return seat == revealer ? {'type': 'next'} : null;
      default:
        return null;
    }
  }

  Map<String, dynamic> _botStroke() {
    final pts = <int>[];
    final kind = rng.nextInt(4);
    final cx = 200 + rng.nextInt(600), cy = 200 + rng.nextInt(600);
    final r = 60 + rng.nextInt(180);
    int c(int v) => v.clamp(0, 1000);
    switch (kind) {
      case 0: // circle
        for (var i = 0; i <= 24; i++) {
          final t = i / 24 * 6.2832;
          pts.addAll([c(cx + (r * m.cos(t)).round()), c(cy + (r * m.sin(t)).round())]);
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
}
