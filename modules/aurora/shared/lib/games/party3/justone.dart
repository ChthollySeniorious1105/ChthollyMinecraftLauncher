import '../../src/ai.dart';
import '../../src/engine.dart';
import 'justone_words.dart';
import 'p3_util.dart';

export 'justone_words.dart' show JustOneWord, justOneBank, parseJustOneLines;

/// Just One 合作猜词 (cooperative).
///
/// Per card: `clue` (writers secretly write clues; 3 players → 2 clues each)
/// → `review` (identical clues auto-cancelled; writers may vote to cancel
/// more, then confirm) → `guess` (guesser sees the surviving clues) →
/// `result` (shown for a few seconds) → next card … → `over`.
class JustOne extends GameEngine {
  JustOne(super.setup);

  static const maxClueLen = 8;
  static const maxGuessLen = 12;
  static const resultMs = 4500;
  static const reviewMs = 45000;
  static const maxSkips = 2;

  late List<JustOneWord> pool;
  late int totalCards;
  late int timeSec;
  late int cluesPer;
  final Set<String> _used = {};

  String phase = 'clue';
  int cardNo = 0; // 1-based index of the current card
  int deck = 0; // cards still in the deck (including the current one)
  int success = 0;
  int guesser = 0;
  JustOneWord? word;
  int skipsUsed = 0;
  int endsAt = 0;

  /// writer seat → submitted clue texts
  final Map<int, List<String>> submitted = {};

  /// Clue list after the clue phase: {'id','s','t','auto':bool,'votes':[seats]}
  final List<Map<String, dynamic>> clues = [];
  final Set<int> confirmed = {};
  Map<String, dynamic>? lastResult;
  final List<Map<String, dynamic>> history = [];
  final P3Timers _timers = P3Timers();
  final AiSlot _ai = AiSlot();

  List<int> get writers => [for (var s = 0; s < players; s++) if (s != guesser) s];

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings => isOver ? List.filled(players, 1) : null;

  @override
  int get botDelayMs => 1200;

  @override
  void start() {
    totalCards = setup.opt<int>('cards', 13);
    timeSec = setup.opt<int>('time', 0);
    cluesPer = players == 3 ? 2 : 1;
    final src = setup.opt<String>('words', 'both');
    final custom = parseJustOneLines(setup.resourceLines('justone.words'));
    if (src == 'custom' && custom.length < totalCards) {
      host.log('服务器自定义词库（words/justone.txt）不足 $totalCards 个词，已改用内置词库');
    }
    if (src == 'builtin' || (src == 'custom' && custom.length < totalCards)) {
      pool = List.of(justOneBank);
    } else if (src == 'custom') {
      pool = custom;
    } else {
      final known = {for (final w in justOneBank) w.word};
      pool = [...justOneBank, for (final w in custom) if (!known.contains(w.word)) w];
    }
    deck = totalCards;
    guesser = rng.nextInt(players);
    host.log('Just One 开始！共 $totalCards 张牌，大家一起努力猜中尽可能多的词。${players == 3 ? '（3 人局：每人写 2 条提示）' : ''}');
    _nextCard(first: true);
  }

  JustOneWord _drawWord() {
    var avail = [for (final w in pool) if (!_used.contains(w.word)) w];
    if (avail.isEmpty) {
      _used.clear();
      avail = List.of(pool);
    }
    final w = avail[rng.nextInt(avail.length)];
    _used.add(w.word);
    return w;
  }

  void _nextCard({bool first = false}) {
    _timers.cancel();
    if (deck <= 0) {
      _finish();
      return;
    }
    cardNo++;
    if (!first) guesser = (guesser + 1) % players;
    word = _drawWord();
    skipsUsed = 0;
    submitted.clear();
    clues.clear();
    confirmed.clear();
    phase = 'clue';
    _ai.clear();
    host.log('第 $cardNo 张牌（剩 $deck 张）：${name(guesser)} 猜词，其他人写提示');
    _arm(timeSec * 1000, _endClues);
  }

  void _arm(int ms, void Function() fn) {
    if (ms <= 0 || timeSec <= 0) {
      endsAt = 0;
      return;
    }
    endsAt = p3Now() + ms;
    _timers.countdown(host, ms, fn);
  }

  void _endClues() {
    if (phase != 'clue') return;
    _timers.cancel();
    var id = 1;
    for (final s in writers) {
      for (final t in submitted[s] ?? const <String>[]) {
        clues.add({'id': id++, 's': s, 't': t, 'auto': false, 'votes': <int>[]});
      }
    }
    // automatic normalisation: identical clues cancel each other
    final counts = <String, int>{};
    for (final c in clues) {
      final k = p3Norm(c['t'] as String);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    var dup = 0;
    for (final c in clues) {
      if ((counts[p3Norm(c['t'] as String)] ?? 0) > 1) {
        c['auto'] = true;
        dup++;
      }
    }
    final missing = writers.where((s) => (submitted[s] ?? const []).isEmpty).length;
    if (missing > 0) host.log('$missing 人没有交提示');
    if (dup > 0) host.log('有 $dup 条提示重复，已自动作废');
    phase = 'review';
    _arm(reviewMs, _endReview);
  }

  bool cancelled(Map<String, dynamic> c) {
    if (c['auto'] == true) return true;
    final v = (c['votes'] as List).length;
    return v > 0 && v * 2 >= writers.length;
  }

  void _endReview() {
    if (phase != 'review') return;
    _timers.cancel();
    phase = 'guess';
    final ok = clues.where((c) => !cancelled(c)).length;
    host.log('提示审核完毕：有效提示 $ok 条，作废 ${clues.length - ok} 条。${name(guesser)} 请猜词');
    _arm(timeSec * 1000, () {
      if (phase == 'guess') _resolve(null);
    });
  }

  void _resolve(String? guess) {
    _timers.cancel();
    final w = word!;
    final right = guess != null && p3Norm(guess) == p3Norm(w.word);
    String outcome;
    var lost = 0;
    if (right) {
      success++;
      outcome = 'right';
      deck--;
    } else if (guess == null) {
      outcome = 'pass';
      deck--;
      lost = 1;
    } else {
      outcome = 'wrong';
      deck--;
      lost = 1;
      if (deck > 0) {
        deck--; // wrong guess: the next card from the deck is also discarded
        lost = 2;
      } else if (success > 0) {
        success--; // last card: lose a scored card instead
        lost = 2;
      }
    }
    lastResult = {
      'card': cardNo,
      'word': w.word,
      'cat': w.category,
      'guesser': guesser,
      'guess': guess,
      'outcome': outcome,
      'lost': lost,
      'clues': [for (final c in clues) _clueOut(c, true)],
    };
    history.add({'card': cardNo, 'word': w.word, 'guesser': guesser, 'guess': guess, 'outcome': outcome});
    host.log(switch (outcome) {
      'right' => '✅ ${name(guesser)} 猜对了「${w.word}」！',
      'pass' => '⏭ ${name(guesser)} 放弃了本题，答案是「${w.word}」',
      _ => '❌ ${name(guesser)} 猜「$guess」错了，答案是「${w.word}」${lost == 2 ? '（额外失去 1 张牌）' : ''}',
    });
    phase = 'result';
    endsAt = p3Now() + resultMs;
    _timers.after(host, resultMs, _nextCard);
  }

  void _finish() {
    _timers.cancel();
    phase = 'over';
    endsAt = 0;
    host.log('游戏结束！共猜中 $success / $totalCards 张 —— ${rating(success, totalCards)}');
  }

  static String rating(int n, int total) {
    final r = n * 13 / (total == 0 ? 13 : total);
    if (r >= 13) return '完美！全部猜中！';
    if (r >= 12) return '惊人！默契满分的团队';
    if (r >= 11) return '了不起！';
    if (r >= 9) return '优秀！';
    if (r >= 7) return '不错，继续加油';
    if (r >= 4) return '还行，多练练默契';
    return '再接再厉！';
  }

  // ------------------------------------------------------------ actions

  /// Returns an error message for [clue] or null if it is acceptable.
  static String? clueError(String clue, String answer) {
    final t = p3Norm(clue);
    if (t.isEmpty) return '提示不能为空';
    if (clue.trim().contains(RegExp(r'\s'))) return '提示只能是一个词（不能有空格）';
    if (t.runes.length > maxClueLen) return '提示最多 $maxClueLen 个字';
    final a = p3Norm(answer);
    if (t == a || t.contains(a)) return '提示不能包含答案';
    if (shareChar(t, a)) return '提示不能包含答案里的字';
    return null;
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'clue':
        return [for (final s in writers) if (!submitted.containsKey(s)) s];
      case 'review':
        return [for (final s in writers) if (!confirmed.contains(s)) s];
      case 'guess':
        return [guesser];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    switch (type) {
      case 'clue':
        if (phase != 'clue') throw GameError('现在不是写提示的时候');
        if (seat == guesser) throw GameError('你是猜词者，不能写提示');
        if (submitted.containsKey(seat)) throw GameError('你已经交过提示了');
        final raw = a['texts'] is List ? [for (final t in a['texts'] as List) asStr(t)] : [asStr(a['text'])];
        final texts = [for (final t in raw) p3Clean(t, 20)];
        if (texts.length != cluesPer) throw GameError(cluesPer == 2 ? '3 人局每人要写 2 条提示' : '请写 1 条提示');
        for (final t in texts) {
          final err = clueError(t, word!.word);
          if (err != null) throw GameError(err);
        }
        if (cluesPer == 2 && p3Norm(texts[0]) == p3Norm(texts[1])) throw GameError('两条提示不能相同');
        submitted[seat] = texts;
        if (writers.every(submitted.containsKey)) _endClues();
      case 'skipWord':
        if (phase != 'clue') throw GameError('现在不能换词');
        if (seat == guesser) throw GameError('猜词者不能换词');
        if (submitted.isNotEmpty) throw GameError('已经有人交了提示，不能换词');
        if (skipsUsed >= maxSkips) throw GameError('本张牌换词次数已用完');
        skipsUsed++;
        word = _drawWord();
        host.log('${name(seat)} 觉得这个词不好提示，换了一个词');
      case 'vote':
        if (phase != 'review') throw GameError('现在不能投票');
        if (seat == guesser) throw GameError('猜词者不能看提示');
        if (confirmed.contains(seat)) throw GameError('你已经确认了');
        final c = clues.firstWhere((c) => c['id'] == asInt(a['id']), orElse: () => throw GameError('没有这条提示'));
        final votes = c['votes'] as List<int>;
        final on = a.containsKey('on') ? asBool(a['on']) : !votes.contains(seat);
        votes.remove(seat);
        if (on) votes.add(seat);
      case 'confirm':
        if (phase != 'review') throw GameError('现在不需要确认');
        if (seat == guesser) throw GameError('猜词者不能看提示');
        if (confirmed.contains(seat)) throw GameError('你已经确认了');
        if (a['cancel'] is List) {
          final ids = asIntList(a['cancel']).toSet();
          for (final c in clues) {
            final v = c['votes'] as List<int>;
            v.remove(seat);
            if (ids.contains(c['id'])) v.add(seat);
          }
        }
        confirmed.add(seat);
        if (writers.every(confirmed.contains)) _endReview();
      case 'guess':
        if (phase != 'guess') throw GameError('现在不能猜');
        if (seat != guesser) throw GameError('只有猜词者可以猜');
        final t = p3Clean(asStr(a['text']), 30);
        if (p3Norm(t).isEmpty) throw GameError('请输入你的答案');
        if (p3Norm(t).runes.length > maxGuessLen) throw GameError('答案最多 $maxGuessLen 个字');
        _resolve(t);
      case 'pass':
        if (phase != 'guess') throw GameError('现在不能跳过');
        if (seat != guesser) throw GameError('只有猜词者可以跳过');
        _resolve(null);
      default:
        throw GameError('未知操作');
    }
  }

  Map<String, dynamic> _clueOut(Map<String, dynamic> c, bool full) => {
        'id': c['id'],
        's': c['s'],
        't': c['t'],
        if (full) 'auto': c['auto'],
        if (full) 'votes': List<int>.of(c['votes'] as List<int>),
        'cancelled': cancelled(c),
      };

  @override
  Map<String, dynamic> view(int seat) {
    final isWriter = seat >= 0 && seat < players && seat != guesser;
    final showWord = isWriter && phase != 'over' && phase != 'result';
    List<Map<String, dynamic>>? clueList;
    if (phase == 'review') {
      clueList = seat == guesser ? null : [for (final c in clues) _clueOut(c, true)];
    } else if (phase == 'guess') {
      clueList = seat == guesser
          ? [for (final c in clues) if (!cancelled(c)) _clueOut(c, false)]
          : [for (final c in clues) _clueOut(c, true)];
    }
    return {
      'phase': phase,
      'card': cardNo,
      'totalCards': totalCards,
      'deck': deck,
      'success': success,
      'guesser': guesser,
      'cluesPer': cluesPer,
      'word': showWord ? word?.word : null,
      'cat': phase == 'over' ? null : word?.category,
      'skipsLeft': maxSkips - skipsUsed,
      'submitted': [for (final s in writers) if (submitted.containsKey(s)) s],
      'myClues': submitted[seat],
      'clues': clueList,
      'cancelledCount': phase == 'guess' ? clues.where(cancelled).length : null,
      'confirmed': confirmed.toList(),
      'result': phase == 'result' || phase == 'over' ? lastResult : null,
      'history': history,
      'rating': phase == 'over' ? rating(success, totalCards) : null,
      'timeSec': timeSec,
      'endsAt': endsAt,
      'now': p3Now(),
    };
  }

  // ------------------------------------------------------------ bots

  static const _genericClues = ['常见', '生活', '东西', '日常', '中国', '大家', '熟悉'];

  int _writerIndex(int seat) => writers.indexOf(seat);

  List<String> _heuristicClues(int seat) {
    final w = word!;
    final opts = [for (final c in w.assoc) if (clueError(c, w.word) == null) c];
    final out = <String>[];
    if (opts.isNotEmpty) {
      // 困难: seat-based convention spreads writers over different
      // associations so fewer clues collide; 简单 often picks the most obvious.
      var i = switch (botLevel) {
        2 => _writerIndex(seat) * cluesPer,
        0 => rng.nextInt(2) == 0 ? 0 : rng.nextInt(opts.length),
        _ => rng.nextInt(opts.length),
      };
      for (var k = 0; k < cluesPer; k++) {
        final c = opts[(i + k) % opts.length];
        if (!out.contains(c)) out.add(c);
      }
    }
    final extra = [
      if (clueError(w.category, w.word) == null) w.category,
      for (final g in _genericClues)
        if (clueError(g, w.word) == null) g,
    ];
    for (final g in extra) {
      if (out.length >= cluesPer) break;
      if (!out.contains(g)) out.add(g);
    }
    // last resort (custom words can share characters with every generic clue)
    for (var n = 0; out.length < cluesPer && n < 200; n++) {
      final c = n < 26 ? '${'物品事情人东西感觉样子地方时候颜色声音味道形状大小用途'[n % 24]}${'类型样态'[n % 4]}' : 'clue$n';
      if (clueError(c, w.word) == null && !out.contains(c)) out.add(c);
    }
    return out;
  }

  static const _writerSystem = '你在玩合作猜词游戏 Just One。你和队友要帮助猜词者猜出神秘词。'
      '每人写提示词，相同的提示会互相抵消，所以尽量写有用但不那么“撞车”的提示。'
      '规则：每条提示只能是一个词（1~6 个汉字），不能包含神秘词里的任何一个字，不能用谐音、拼音或外语翻译作弊。'
      '只输出提示词本身，不要解释。';

  static const _guesserSystem = '你在玩合作猜词游戏 Just One，你是猜词者。队友给了你若干提示词（相同的提示已被作废），'
      '请根据所有提示猜出他们共同指向的一个常见中文词语。只输出你猜的词（1~6 个汉字），完全没头绪时输出“跳过”。';

  Map<String, dynamic>? _aiClue(int seat) {
    final w = word!;
    final r = _ai.poll(setup.ai!, 'clue:$cardNo:$seat', () {
      final p = StringBuffer()
        ..writeln('神秘词：${w.word}（类别：${w.category}）')
        ..writeln('请给出 $cluesPer 个提示词${cluesPer > 1 ? '，用空格分隔' : ''}。')
        ..write('禁止出现这些字：${w.word.split('').join('、')}');
      return AiRequest(system: _writerSystem, prompt: p.toString(), maxTokens: 60);
    });
    if (r.pending) return const {'_pending': true};
    final t = r.text;
    if (t == null) return null;
    final line = AiText.firstLine(t, maxLen: 40);
    final parts = [
      for (final p in line.split(RegExp(r'[\s,，、/；;]+')))
        if (p.trim().isNotEmpty) p.trim()
    ];
    final ok = <String>[];
    for (final p in parts) {
      if (!isHan(p) || p.length > 6 || clueError(p, w.word) != null || ok.contains(p)) continue;
      ok.add(p);
      if (ok.length == cluesPer) break;
    }
    if (ok.isEmpty) return null;
    if (ok.length < cluesPer) {
      for (final h in _heuristicClues(seat)) {
        if (ok.length >= cluesPer) break;
        if (!ok.contains(h)) ok.add(h);
      }
    }
    return {'type': 'clue', 'texts': ok};
  }

  Map<String, dynamic>? _aiGuess(List<String> valid, int cancelledN) {
    final r = _ai.poll(setup.ai!, 'guess:$cardNo', () {
      final p = StringBuffer()
        ..writeln('类别：${word!.category}')
        ..writeln(valid.isEmpty ? '所有提示都被作废了。' : '有效提示：${valid.join('、')}')
        ..writeln(cancelledN > 0 ? '（另有 $cancelledN 条提示因重复或违规被作废）' : '')
        ..write('请猜词。');
      return AiRequest(system: _guesserSystem, prompt: p.toString(), maxTokens: 30);
    });
    if (r.pending) return const {'_pending': true};
    final t = r.text;
    if (t == null) return null;
    final g = AiText.firstLine(t, maxLen: 20);
    if (g == '跳过' || g.toLowerCase() == 'pass') return {'type': 'pass'};
    if (!isHan(g) || g.length > 6) return null;
    if (valid.any((c) => p3Norm(c) == p3Norm(g))) return null; // echoing a clue is never right
    return {'type': 'guess', 'text': g};
  }

  /// Guess from public clues using the (public) word bank's associations.
  Map<String, dynamic> _heuristicGuess(List<String> valid) {
    if (valid.isEmpty) return {'type': 'pass'};
    final cat = word!.category;
    JustOneWord? best;
    var bestScore = 0.0;
    for (final w in pool) {
      if (valid.any((c) => shareChar(c, w.word))) continue; // clues never share chars with the answer
      var sc = 0.0;
      for (final c in valid) {
        final i = w.assoc.indexOf(c);
        if (i >= 0) {
          sc += 3 - i * 0.2;
        } else if (botLevel >= 1 && w.assoc.any((x) => x.length > 1 && (x.contains(c) || c.contains(x)))) {
          sc += 1;
        } else if (botLevel >= 2 && w.assoc.any((x) => shareChar(x, c))) {
          sc += 0.4;
        }
      }
      if (w.category == cat) sc += 0.3;
      sc += rng.nextDouble() * 0.1;
      if (sc > bestScore) {
        bestScore = sc;
        best = w;
      }
    }
    final need = switch (botLevel) { 0 => 0.5, 2 => 1.2, _ => 1.0 };
    if (best == null || bestScore < need) {
      // unsure: 困难 passes (loses 1 card instead of 2); 简单 guesses anyway
      if (botLevel == 0 && best != null) return {'type': 'guess', 'text': best.word};
      return {'type': 'pass'};
    }
    return {'type': 'guess', 'text': best.word};
  }

  List<int> _botCancels() {
    final live = [for (final c in clues) if (c['auto'] != true) c];
    final ids = <int>{};
    for (var i = 0; i < live.length; i++) {
      for (var j = i + 1; j < live.length; j++) {
        final a = p3Norm(live[i]['t'] as String), b = p3Norm(live[j]['t'] as String);
        // same root (猫/小猫, 跑步/跑) counts as identical under the official rules
        if (a.contains(b) || b.contains(a)) {
          ids.add(live[i]['id'] as int);
          ids.add(live[j]['id'] as int);
        }
      }
    }
    return ids.toList();
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'clue':
        if (seat == guesser || submitted.containsKey(seat)) return null;
        if (aiOn) {
          final a = _aiClue(seat);
          if (a != null && a['_pending'] == true) return null;
          if (a != null) return a;
        }
        return {'type': 'clue', 'texts': _heuristicClues(seat)};
      case 'review':
        if (seat == guesser || confirmed.contains(seat)) return null;
        return {'type': 'confirm', 'cancel': botLevel == 0 ? <int>[] : _botCancels()};
      case 'guess':
        if (seat != guesser) return null;
        final valid = [for (final c in clues) if (!cancelled(c)) c['t'] as String];
        if (aiOn) {
          final a = _aiGuess(valid, clues.length - valid.length);
          if (a != null && a['_pending'] == true) return null;
          if (a != null) return a;
        }
        return _heuristicGuess(valid);
      default:
        return null;
    }
  }
}
