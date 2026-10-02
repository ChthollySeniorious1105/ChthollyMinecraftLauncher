import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'soup_a.dart';
import 'soup_b.dart';

export 'soup_a.dart' show SoupStory;

/// All built-in (original) puzzles.
final List<SoupStory> soupStories = [...soupStoriesA, ...soupStoriesB];

const int kSoupTitleMax = 20;
const int kSoupSurfaceMax = 300;
const int kSoupBottomMax = 800;
const int kSoupQuestionMax = 60;
const int kSoupGuessMax = 150;

/// Parses admin lines `标题|汤面|汤底` (half/full-width bar). Invalid lines skipped.
List<SoupStory> parseSoupLines(List<String> lines) {
  final out = <SoupStory>[];
  final seen = <String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final parts = line.split(RegExp(r'[|｜]'));
    if (parts.length < 3) continue;
    final title = parts[0].trim();
    final surface = parts[1].trim();
    final bottom = parts.sublist(2).join('|').trim();
    if (title.isEmpty || surface.isEmpty || bottom.isEmpty) continue;
    if (title.length > kSoupTitleMax || surface.length > kSoupSurfaceMax || bottom.length > kSoupBottomMax) continue;
    if (!seen.add(title)) continue;
    out.add(SoupStory(title, surface, bottom));
  }
  return out;
}

/// 海龟汤 (lateral thinking puzzles).
///
/// A GM (host seat, or 0) holds the 汤底. Phases per puzzle:
/// prepare (GM swaps / starts, or composes own puzzle) → ask → reveal; then
/// the next puzzle or over. During `ask` every player may queue one item at
/// a time: a yes/no question or a final guess. The GM answers questions with
/// 是/否/无关/是也不是/很接近 and judges guesses (对/很接近/不对).
class TurtleSoup extends GameEngine {
  TurtleSoup(super.setup);

  static const answers = {'yes': '是', 'no': '否', 'irrelevant': '无关', 'both': '是也不是', 'close': '很接近'};
  static const verdicts = {'right': '猜对了', 'close': '很接近', 'wrong': '不对'};
  static const guessesPerPuzzle = 3;
  static const maxSwaps = 10;

  late String source;
  late int totalRounds;
  late int cap;
  int gm = 0;
  List<SoupStory> pool = [];
  final Set<int> _used = {};
  int round = 0;
  String phase = 'prepare';
  SoupStory? story;
  int swaps = 0;

  /// {'id','s','k':'q'|'g','t','a'? (answer key), 'r': round}
  final List<Map<String, dynamic>> items = [];
  int _nextId = 1;
  int asked = 0;
  late List<int> guessesLeft;
  late List<int> scores;
  int solver = -1;
  Map<String, dynamic>? roundResult;
  List<Map<String, dynamic>>? finalRanking;

  // bot bookkeeping (LLM replies only; never part of the view)
  final AiSlot _ai = AiSlot();

  @override
  List<int>? get placings {
    if (!isOver || finalRanking == null) return null;
    // The GM hosts the story (cooperative role): shares 1st place.
    final r = List.filled(players, 1);
    for (final e in finalRanking!) {
      r[e['s'] as int] = e['rank'] as int;
    }
    return r;
  }

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 1500;

  List<int> get askers => [for (var s = 0; s < players; s++) if (s != gm) s];

  @override
  void start() {
    source = setup.opt<String>('source', 'builtin');
    totalRounds = setup.opt<int>('rounds', 1);
    cap = setup.opt<int>('cap', 40);
    gm = (setup.hostSeat >= 0 && setup.hostSeat < players) ? setup.hostSeat : 0;
    scores = List.filled(players, 0);
    if (source == 'custom') {
      pool = parseSoupLines(setup.resourceLines('turtlesoup.stories'));
      if (pool.isEmpty) {
        host.log('服务器没有可用的自定义汤（words/turtlesoup.txt，格式：标题|汤面|汤底），已改用内置题库');
        pool = List.of(soupStories);
      }
    } else {
      pool = List.of(soupStories);
    }
    host.log('海龟汤开始！主持人（GM）：${name(gm)}。提问只能用“是/否”回答的问题，猜出汤底即可获胜。');
    _nextPuzzle();
  }

  SoupStory _draw() {
    if (_used.length >= pool.length) _used.clear();
    int i;
    do {
      i = rng.nextInt(pool.length);
    } while (_used.contains(i));
    _used.add(i);
    return pool[i];
  }

  void _nextPuzzle() {
    if (round >= totalRounds) {
      _finish();
      return;
    }
    round++;
    items.clear();
    asked = 0;
    swaps = 0;
    solver = -1;
    roundResult = null;
    guessesLeft = List.filled(players, guessesPerPuzzle);
    guessesLeft[gm] = 0;
    phase = 'prepare';
    story = source == 'gm' ? null : _draw();
    host.log(source == 'gm' ? '第 $round/$totalRounds 题：等待 ${name(gm)} 自拟题目…' : '第 $round/$totalRounds 题：等待 ${name(gm)} 确认题目…');
  }

  void _reveal(String why) {
    phase = 'reveal';
    roundResult = {'round': round, 'why': why, 'solver': solver, 'title': story!.title, 'bottom': story!.bottom};
    host.log('$why 汤底：${story!.bottom}');
  }

  void _finish() {
    phase = 'over';
    final order = List.of(askers)..sort((a, b) => scores[b] != scores[a] ? scores[b] - scores[a] : a - b);
    finalRanking = [];
    var rank = 0;
    for (var i = 0; i < order.length; i++) {
      if (i == 0 || scores[order[i]] != scores[order[i - 1]]) rank = i + 1;
      finalRanking!.add({'s': order[i], 'score': scores[order[i]], 'rank': rank});
    }
    host.log('游戏结束！${[for (final r in finalRanking!) if (r['rank'] == 1) name(r['s'] as int)].join('、')} 得分最高');
  }

  bool _hasPending(int s) => items.any((e) => e['s'] == s && e['a'] == null);
  List<Map<String, dynamic>> get pending => [for (final e in items) if (e['a'] == null) e];

  bool canAsk(int s) => asked < cap && !_hasPending(s);
  bool canGuess(int s) => guessesLeft[s] > 0 && !_hasPending(s);

  void _checkExhausted() {
    if (phase != 'ask' || pending.isNotEmpty) return;
    if (askers.every((s) => !canAsk(s) && !canGuess(s))) {
      _reveal('提问次数与猜测次数都已用完，无人猜中。');
    }
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'prepare':
      case 'reveal':
        return [gm];
      case 'ask':
        return [
          if (pending.isNotEmpty) gm,
          for (final s in askers)
            if (canAsk(s) || canGuess(s)) s,
        ];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    final isGm = seat == gm;
    switch (type) {
      case 'swap':
        if (!isGm) throw GameError('只有主持人可以换题');
        if (phase != 'prepare' || source == 'gm') throw GameError('现在不能换题');
        if (swaps >= maxSwaps) throw GameError('换题次数已用完');
        if (pool.length < 2) throw GameError('题库里没有别的题了');
        swaps++;
        final old = story;
        do {
          story = _draw();
        } while (identical(story, old));
      case 'compose':
        if (!isGm) throw GameError('只有主持人可以出题');
        if (phase != 'prepare' || source != 'gm') throw GameError('现在不能自拟题目');
        final t = sanitizeText(asStr(a['title'])).trim(),
            sf = sanitizeText(asStr(a['surface'])).trim(),
            b = sanitizeText(asStr(a['bottom'])).trim();
        if (t.isEmpty || sf.isEmpty || b.isEmpty) throw GameError('标题、汤面、汤底都不能为空');
        if (t.length > kSoupTitleMax) throw GameError('标题最多 $kSoupTitleMax 个字');
        if (sf.length > kSoupSurfaceMax) throw GameError('汤面最多 $kSoupSurfaceMax 个字');
        if (b.length > kSoupBottomMax) throw GameError('汤底最多 $kSoupBottomMax 个字');
        story = SoupStory(t, sf, b);
        _begin();
      case 'begin':
        if (!isGm) throw GameError('只有主持人可以开始');
        if (phase != 'prepare' || story == null) throw GameError('现在不能开始');
        _begin();
      case 'ask':
      case 'guess':
        if (phase != 'ask') throw GameError('现在不能提问');
        if (isGm) throw GameError('主持人不能提问');
        final t = sanitizeText(asStr(a['text'])).trim();
        if (t.isEmpty) throw GameError('内容不能为空');
        if (_hasPending(seat)) throw GameError('请等待主持人回答你上一个问题');
        if (type == 'ask') {
          if (t.length > kSoupQuestionMax) throw GameError('问题最多 $kSoupQuestionMax 个字');
          if (asked >= cap) throw GameError('本题提问次数已达上限（$cap），只能猜汤底了');
          asked++;
        } else {
          if (t.length > kSoupGuessMax) throw GameError('猜测最多 $kSoupGuessMax 个字');
          if (guessesLeft[seat] <= 0) throw GameError('你的猜测次数已用完');
          guessesLeft[seat]--;
        }
        items.add({'id': _nextId++, 's': seat, 'k': type == 'ask' ? 'q' : 'g', 't': t, 'a': null, 'r': round});
      case 'answer':
        if (!isGm) throw GameError('只有主持人可以回答');
        if (phase != 'ask') throw GameError('现在不能回答');
        final id = asInt(a['id']);
        final it = items.firstWhere((e) => e['id'] == id && e['a'] == null, orElse: () => throw GameError('该问题已回答或不存在'));
        final ans = asStr(a['answer']);
        if (it['k'] == 'q') {
          if (!answers.containsKey(ans)) throw GameError('请选择 是/否/无关/是也不是/很接近');
          it['a'] = ans;
          final s = it['s'] as int;
          if (ans == 'yes' || ans == 'close') scores[s] += 1;
        } else {
          if (!verdicts.containsKey(ans)) throw GameError('请判定：猜对了/很接近/不对');
          it['a'] = ans;
          final s = it['s'] as int;
          host.log('主持人判定 ${name(s)} 的猜测：${verdicts[ans]}');
          if (ans == 'right') {
            solver = s;
            scores[s] += 5;
            _reveal('${name(s)} 猜中了汤底！');
            return;
          }
        }
        _checkExhausted();
      case 'reveal':
        if (!isGm) throw GameError('只有主持人可以公布汤底');
        if (phase != 'ask') throw GameError('现在不能公布汤底');
        _reveal('主持人公布了汤底。');
      case 'next':
        if (!isGm) throw GameError('只有主持人可以继续');
        if (phase != 'reveal') throw GameError('现在不能继续');
        _nextPuzzle();
      default:
        throw GameError('未知操作');
    }
  }

  void _begin() {
    phase = 'ask';
    host.log('汤面《${story!.title}》：${story!.surface}');
  }

  // ------------------------------------------------------------ view

  @override
  Map<String, dynamic> view(int seat) {
    final isGm = seat == gm;
    final showBottom = isGm || phase == 'reveal' || phase == 'over';
    final showStory = story != null && (isGm || phase != 'prepare');
    return {
      'phase': phase,
      'gm': gm,
      'source': source,
      'round': round,
      'totalRounds': totalRounds,
      'isGm': isGm,
      'story': showStory
          ? {'title': story!.title, 'surface': story!.surface, if (showBottom) 'bottom': story!.bottom}
          : null,
      'swapsLeft': maxSwaps - swaps,
      'items': [for (final e in items) Map<String, dynamic>.of(e)],
      'asked': asked,
      'cap': cap,
      'guessesLeft': guessesLeft,
      'scores': scores,
      'solver': solver,
      'roundResult': roundResult,
      'final': finalRanking,
    };
  }

  // ------------------------------------------------------------ bots

  static const _botQuestions = [
    '这件事和钱有关吗？', '有人死了吗？', '主角是故意这么做的吗？', '这件事发生在晚上吗？', '和主角的家人有关吗？',
    '有第三个人参与吗？', '主角的工作和这件事有关吗？', '这件事是一场误会吗？', '有动物参与吗？', '和天气有关吗？',
    '主角事先就知道结果吗？', '和食物有关吗？', '主角后来后悔了吗？', '有人在说谎吗？', '这件事发生在家里吗？',
    '和时间有关吗？', '主角身体有什么特殊情况吗？', '和交通工具有关吗？', '这是个温馨的故事吗？', '和手机或电话有关吗？',
    '主角是在帮助别人吗？', '和过去发生的事有关吗？', '有东西被弄丢了吗？', '主角的情绪变化是关键吗？', '和声音有关吗？',
  ];

  static Set<String> _bigrams(String s) {
    final t = s.replaceAll(RegExp(r'[\s，。？！、,.?!：:“”"（）()吗呢的了是有和]'), '');
    return {for (var i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)};
  }

  /// Share of the guess's bigrams that appear in the bottom.
  static double overlap(String guess, String bottom) {
    final g = _bigrams(guess);
    if (g.isEmpty) return 0;
    final b = _bigrams(bottom);
    return g.where(b.contains).length / g.length;
  }


  // ------------------------------------------------------------ AI helpers

  /// Maps a model reply to an answer key of [answers] (question) or
  /// [verdicts] (guess). null = unrecognised → use the heuristic.
  static String? mapAiAnswer(String? reply, {bool guess = false}) {
    if (reply == null) return null;
    var t = reply.trim();
    final j = AiText.json(t);
    if (j != null) {
      final v = j['answer'] ?? j['verdict'];
      if (v is! String) return null;
      t = v;
    }
    t = AiText.firstLine(t, maxLen: 30).replaceAll(RegExp(r'[\s，。,.!！？?：:“”"「」*`]'), '').toLowerCase();
    if (t.isEmpty) return null;
    if (guess) {
      if (t.startsWith('猜对') || t.startsWith('正确') || t == '对' || t.startsWith('对的') || t == 'right') return 'right';
      if (t.startsWith('很接近') || t.startsWith('接近') || t == 'close') return 'close';
      if (t.startsWith('不对') || t.startsWith('错') || t.startsWith('不正确') || t == '否' || t == 'wrong') return 'wrong';
      return null;
    }
    if (t.startsWith('是也不是') || t.startsWith('也是也不是') || t.startsWith('部分是') || t == 'both') return 'both';
    if (t.startsWith('很接近') || t.startsWith('接近') || t == 'close') return 'close';
    if (t.startsWith('无关') || t.startsWith('不相关') || t.startsWith('不重要') || t == 'irrelevant') return 'irrelevant';
    if (t.startsWith('否') || t.startsWith('不是') || t.startsWith('不对') || t.startsWith('没有') || t == 'no') return 'no';
    if (t.startsWith('是') || t == '对' || t.startsWith('对的') || t == 'yes') return 'yes';
    return null;
  }

  String _qaHistory() {
    final b = StringBuffer();
    var n = 0;
    for (final e in items) {
      if (e['a'] == null) continue;
      n++;
      if (e['k'] == 'q') {
        b.writeln('$n. 问：${e['t']} —— 答：${answers[e['a']]}');
      } else {
        b.writeln('$n. [猜汤底] ${e['t']} —— 判定：${verdicts[e['a']]}');
      }
    }
    return n == 0 ? '（还没有人提问）' : b.toString().trimRight();
  }

  static const _gmSystem = '你是“海龟汤”（情境推理游戏）的主持人。你知道完整的汤底（真相），玩家只知道汤面。'
      '玩家会问只能用“是/否”回答的问题，你必须严格依据汤底判断，保持和之前的回答前后一致，绝不透露汤底中玩家没问到的细节。\n'
      '回答规则（只能从下面五个里选一个）：\n'
      '- 是：问题描述的情况在汤底中成立。\n'
      '- 否：问题描述的情况在汤底中不成立。\n'
      '- 无关：问题与还原真相无关，或汤底中没有涉及、答是答否都不影响推理。\n'
      '- 是也不是：问题部分正确、部分错误，或需要分情况才成立。\n'
      '- 很接近：问题触及了汤底的关键点（核心真相/关键动机/关键道具），而且基本成立。\n'
      '汤底没写明的次要细节，按故事最合理的情况回答；拿不准时回答“无关”。只输出这一个词，不要解释，不要标点。';

  static const _judgeSystem = '你是“海龟汤”（情境推理游戏）的主持人，负责判定玩家对汤底的最终猜测。'
      '把玩家的猜测和汤底对比：\n'
      '- 猜对了：玩家说中了汤底的核心真相（关键原因/关键身份/关键事件），细节不必完全一致，意思对即可。\n'
      '- 很接近：抓住了部分关键点，但核心真相还缺一块或有明显偏差。\n'
      '- 不对：没有说中核心真相。\n'
      '要求严格：只是复述汤面、泛泛而谈（例如“是一场误会”）或把多种可能罗列在一起的，都判“不对”。'
      '只输出“猜对了”“很接近”“不对”三者之一，不要解释。';

  static const _playerSystem = '你在玩“海龟汤”（情境推理游戏），你是提问的玩家。主持人知道真相（汤底），你只知道汤面。'
      '你可以问只能用“是/否”回答的问题，主持人会回答：是 / 否 / 无关 / 是也不是 / 很接近。'
      '你的目标是尽快还原真相。好的提问策略：\n'
      '- 先确认大方向（有没有人死亡或受伤、是否故意、是否有别人参与、是否和职业/身体状况/时间地点有关），再逐步缩小范围。\n'
      '- 紧紧抓住回答为“是”和“很接近”的线索深挖；回答“否”和“无关”的方向不要再问。\n'
      '- 汤面里不合常理的地方往往是突破口。问题要具体、可判定，一次只问一件事，不要重复已经问过的问题。\n'
      '- 当你已经能解释汤面里所有奇怪之处时，就提交猜测：用一两句话完整说出你认为的真相（谁、为什么、发生了什么）。\n'
      '只输出一个 JSON：{"type":"ask","text":"你的问题"} 或 {"type":"guess","text":"你对汤底的完整猜测"}。'
      '问题不超过 $kSoupQuestionMax 字，猜测不超过 $kSoupGuessMax 字，用自然的中文。';

  /// Result wrapper: `pending` → return null from bot(); `action` null → heuristic.
  static const Map<String, dynamic> _wait = {'_pending': true};

  Map<String, dynamic>? _aiGm(Map<String, dynamic> it) {
    final isGuess = it['k'] == 'g';
    final st = story!;
    final r = _ai.poll(setup.ai!, 'gm:$round:${it['id']}', () {
      final p = StringBuffer()
        ..writeln('汤名：《${st.title}》')
        ..writeln('汤面：${st.surface}')
        ..writeln('汤底（只有你知道）：${st.bottom}')
        ..writeln()
        ..writeln('之前的问答（请保持一致）：')
        ..writeln(_qaHistory())
        ..writeln();
      if (isGuess) {
        p.writeln('玩家 ${name(it['s'] as int)} 提交的汤底猜测：${it['t']}');
        p.write('请判定：猜对了 / 很接近 / 不对');
      } else {
        p.writeln('玩家 ${name(it['s'] as int)} 的问题：${it['t']}');
        p.write('请回答：是 / 否 / 无关 / 是也不是 / 很接近');
      }
      return AiRequest(system: isGuess ? _judgeSystem : _gmSystem, prompt: p.toString(), maxTokens: 50);
    });
    if (r.pending) return _wait;
    final a = mapAiAnswer(r.text, guess: isGuess);
    return a == null ? null : {'type': 'answer', 'id': it['id'], 'answer': a};
  }

  Map<String, dynamic>? _aiPlayer(int seat) {
    final answered = items.where((e) => e['a'] != null).length;
    final st = story!;
    final r = _ai.poll(setup.ai!, 'play:$round:$seat:$answered', () {
      final mine = [
        for (final e in items)
          if (e['s'] == seat && e['k'] == 'g') '${e['t']}（${verdicts[e['a']] ?? '待判定'}）',
      ];
      final p = StringBuffer()
        ..writeln('汤名：《${st.title}》')
        ..writeln('汤面：${st.surface}')
        ..writeln()
        ..writeln('目前所有玩家的问答记录：')
        ..writeln(_qaHistory())
        ..writeln()
        ..writeln('本题已用提问 $asked/$cap 次；你还剩 ${guessesLeft[seat]} 次猜汤底机会。')
        ..writeln(mine.isEmpty ? '你还没有猜过汤底。' : '你之前的猜测：${mine.join('；')}');
      if (!canAsk(seat)) p.writeln('提问次数已用完，你只能提交猜测。');
      if (!canGuess(seat)) p.writeln('你的猜测次数已用完，只能提问。');
      if (answered < 6 && canAsk(seat)) p.writeln('线索还很少，请先提问。');
      p.write('请给出你的下一步（只输出 JSON）。');
      return AiRequest(system: _playerSystem, prompt: p.toString(), maxTokens: 200);
    });
    if (r.pending) return _wait;
    final j = r.text == null ? null : AiText.json(r.text!);
    if (j == null) return null;
    final type = j['type'];
    final raw = j['text'];
    if (raw is! String) return null;
    final text = sanitizeText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length < 2) return null;
    if (type == 'ask') {
      if (!canAsk(seat) || text.length > kSoupQuestionMax) return null;
      if (items.any((e) => e['t'] == text)) return null;
      return {'type': 'ask', 'text': text};
    }
    if (type == 'guess') {
      if (!canGuess(seat) || text.length > kSoupGuessMax || text.length < 6) return null;
      if (answered < 3 && canAsk(seat)) return null;
      return {'type': 'guess', 'text': text};
    }
    return null;
  }

  // ------------------------------------------------------------ bots

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'prepare':
        if (seat != gm) return null;
        if (source == 'gm') {
          final s = soupStories[rng.nextInt(soupStories.length)];
          return {'type': 'compose', 'title': s.title, 'surface': s.surface, 'bottom': s.bottom};
        }
        return {'type': 'begin'};
      case 'reveal':
        return seat == gm ? {'type': 'next'} : null;
      case 'ask':
        if (seat == gm) {
          final p = pending;
          if (p.isEmpty) return null;
          final it = p.first;
          if (aiOn) {
            final a = _aiGm(it);
            if (identical(a, _wait)) return null;
            if (a != null) return a;
          }
          final text = it['t'] as String;
          final ov = overlap(text, story!.bottom);
          if (it['k'] == 'g') {
            return {'type': 'answer', 'id': it['id'], 'answer': ov >= 0.6 ? 'right' : (ov >= 0.35 ? 'close' : 'wrong')};
          }
          final ans = ov >= 0.5 ? 'yes' : (ov > 0 ? 'close' : (rng.nextInt(3) == 0 ? 'no' : 'irrelevant'));
          return {'type': 'answer', 'id': it['id'], 'answer': ans};
        }
        if (_hasPending(seat) || (!canAsk(seat) && !canGuess(seat))) return null;
        if (aiOn) {
          final a = _aiPlayer(seat);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        return _botPlayer(seat);
      default:
        return null;
    }
  }

  Map<String, dynamic>? _botPlayer(int seat) {
    final n = items.where((e) => e['s'] == seat && e['k'] == 'q').length;
    // 简单: guesses early; 困难: waits for more 是/很接近 clues
    final minAsk = switch (botLevel) { 0 => 2, 2 => 9, _ => 6 };
    final wantGuess = canGuess(seat) && (!canAsk(seat) || (n >= minAsk && rng.nextInt(4) == 0));
    if (wantGuess) {
      // build a guess from the questions the GM answered with 是/很接近 (public info)
      final hits = [
        for (final e in items)
          if (e['k'] == 'q' && (e['a'] == 'yes' || e['a'] == 'close'))
            (e['t'] as String).replaceAll(RegExp(r'[吗？?]'), ''),
      ];
      final text = hits.isEmpty ? '我觉得这是一场误会' : '我猜：${hits.take(botLevel == 2 ? 5 : 3).join('，')}';
      return {'type': 'guess', 'text': text.length > kSoupGuessMax ? text.substring(0, kSoupGuessMax) : text};
    }
    if (canAsk(seat)) {
      final used = {for (final e in items) e['t']};
      final fresh = [for (final q in _botQuestions) if (!used.contains(q)) q];
      final q = fresh.isEmpty ? _botQuestions[rng.nextInt(_botQuestions.length)] : fresh[rng.nextInt(fresh.length)];
      return {'type': 'ask', 'text': q};
    }
    return null;
  }
}
