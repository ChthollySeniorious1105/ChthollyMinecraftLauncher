import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'words/bank.dart';

/// 谁是卧底
///
/// Roles: 'civ' 平民, 'spy' 卧底, 'blank' 白板, 'gm' 出题人（不参与）.
/// Phases: gm_setup → (describe → vote)* → [blank_guess] → over.
class Undercover extends GameEngine {
  Undercover(super.setup);

  static const maxRounds = 30;
  static const maxDescLen = 40;

  int gm = -1;
  late List<String> roles;
  late List<bool> alive;
  String civWord = '';
  String spyWord = '';
  String phase = 'gm_setup';
  int round = 0;

  /// Describe order for the current round (or tie-break).
  List<int> order = [];
  int descIdx = 0;

  /// History: {'r': round, 's': seat, 't': text, 'tb': tieBreak}.
  final List<Map<String, dynamic>> descs = [];

  /// Current voting.
  List<int> candidates = [];
  final Map<int, int> votes = {};
  bool tieBreak = false;

  /// Result of the most recent vote.
  Map<String, dynamic>? lastVote;

  /// Elimination order: {'s': seat, 'role': role, 'r': round}.
  final List<Map<String, dynamic>> outs = [];

  /// Vote counts received last round, used by bot heuristic.
  final Map<int, int> _suspicion = {};

  int guesser = -1;
  String? guessText;
  bool? guessOk;

  String winner = ''; // 'civ' | 'spy' | 'blank'
  List<int> winners = [];

  bool get _gmMode => setup.opt<String>('source', 'bank') == 'gm';

  List<int> get playing => [for (var s = 0; s < players; s++) if (s != gm) s];
  List<int> get aliveSeats => [for (var s = 0; s < players; s++) if (s != gm && alive[s]) s];

  static String roleName(String r) => switch (r) {
        'civ' => '平民',
        'spy' => '卧底',
        'blank' => '白板',
        'gm' => '出题人',
        _ => '?',
      };

  String wordOf(int s) => switch (roles[s]) {
        'civ' => civWord,
        'spy' => spyWord,
        _ => '',
      };

  @override
  void start() {
    roles = List.filled(players, 'civ');
    alive = List.filled(players, true);
    if (_gmMode) {
      if (players < 5) throw GameError('指定出题人模式至少需要 5 名玩家');
      gm = (setup.hostSeat >= 0 && setup.hostSeat < players) ? setup.hostSeat : 0;
      roles[gm] = 'gm';
      alive[gm] = false;
    }
    final n = playing.length;
    var blank = setup.opt<bool>('blank', false) ? 1 : 0;
    if (blank == 1 && n < 4) {
      blank = 0;
      host.log('人数不足 4 人，本局不设白板');
    }
    final opt = setup.opt<int>('spies', 0);
    var spies = opt > 0 ? opt : (n <= 6 ? 1 : (n <= 10 ? 2 : 3));
    // Civilians must strictly outnumber undercover + blank at the start.
    final cap = (n - blank - 1) ~/ 2;
    if (spies > cap) {
      spies = cap < 1 ? 1 : cap;
      host.log('人数较少，卧底人数调整为 $spies');
    }
    final seats = shuffled(playing, rng);
    for (var i = 0; i < spies; i++) {
      roles[seats[i]] = 'spy';
    }
    if (blank == 1) roles[seats[spies]] = 'blank';

    host.log('谁是卧底开始！共 $n 名玩家，卧底 $spies 人${blank == 1 ? '，白板 1 人' : ''}');
    if (gm >= 0) {
      host.log('出题人：${name(gm)}');
      if (isBot(gm)) {
        _pickBankWords();
        _beginRound();
      } else {
        phase = 'gm_setup';
        host.log('等待出题人 ${name(gm)} 出题…');
      }
    } else {
      _pickBankWords();
      _beginRound();
    }
  }

  /// Custom pairs from the server's words/undercover.txt ("平民词|卧底词").
  late final List<(String, String)> _custom = [
    for (final l in setup.resourceLines('undercover.pairs'))
      if (l.split('|').length == 2)
        if (l.split('|').map((x) => x.trim()).toList() case [final a, final b]
            when a.isNotEmpty && b.isNotEmpty && a != b && a.length <= 12 && b.length <= 12)
          (a, b)
  ];

  (String, String) _randomPair() {
    final mode = setup.opt<String>('bank', 'mix');
    if (mode != 'builtin' && _custom.isNotEmpty) {
      if (mode == 'custom') return _custom[rng.nextInt(_custom.length)];
      // mix: custom pairs weighted by their share of the combined bank
      final total = _custom.length + undercoverWordBank.length;
      if (rng.nextInt(total) < _custom.length) return _custom[rng.nextInt(_custom.length)];
    } else if (mode == 'custom') {
      host.log('服务器自定义词库为空（words/undercover.txt），已改用内置词库');
    }
    return undercoverPair(rng.nextInt(undercoverWordBank.length));
  }

  void _pickBankWords() {
    final (a, b) = _randomPair();
    if (rng.nextBool()) {
      civWord = a;
      spyWord = b;
    } else {
      civWord = b;
      spyWord = a;
    }
  }

  void _beginRound() {
    round++;
    tieBreak = false;
    final a = aliveSeats;
    // Rotate the starting speaker each round.
    final startAt = (round - 1) % a.length;
    order = [...a.sublist(startAt), ...a.sublist(0, startAt)];
    descIdx = 0;
    phase = 'describe';
    host.log('第 $round 轮：请依次描述你的词语，从 ${name(order.first)} 开始');
  }

  void _beginVote() {
    phase = 'vote';
    votes.clear();
    if (!tieBreak) candidates = aliveSeats;
    host.log(tieBreak ? '平票加赛投票：只能投给 ${candidates.map(name).join('、')}' : '描述结束，开始投票！');
  }

  @override
  bool get isOver => phase == 'over';

  List<int> get _voters => [
        for (final s in aliveSeats)
          if (!votes.containsKey(s)) s
      ];

  @override
  List<int> get waitingFor => switch (phase) {
        'gm_setup' => [gm],
        'describe' => descIdx < order.length ? [order[descIdx]] : const [],
        'vote' => _voters,
        'blank_guess' => [guesser],
        _ => const [],
      };

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final type = asStr(a['type']);
    switch (phase) {
      case 'gm_setup':
        if (seat != gm) throw GameError('等待出题人出题');
        if (type != 'words') throw GameError('请先填写平民词和卧底词');
        final c = sanitizeText(asStr(a['civ'])).trim();
        final s = sanitizeText(asStr(a['spy'])).trim();
        if (c.isEmpty || s.isEmpty) throw GameError('平民词和卧底词都不能为空');
        if (c == s) throw GameError('平民词和卧底词不能相同');
        if (c.length > 12 || s.length > 12) throw GameError('词语最多 12 个字');
        civWord = c;
        spyWord = s;
        host.log('出题人已出题，词语已发放');
        _beginRound();
      case 'describe':
        if (seat != order[descIdx]) throw GameError('还没轮到你描述');
        String text;
        if (type == 'verbal') {
          text = '（已口头描述）';
        } else if (type == 'describe') {
          text = sanitizeText(asStr(a['text'])).trim().replaceAll(RegExp(r'\s+'), ' ');
          if (text.isEmpty) throw GameError('描述不能为空');
          if (text.length > maxDescLen) throw GameError('描述最多 $maxDescLen 个字');
          final w = wordOf(seat);
          if (w.isNotEmpty && text.contains(w)) throw GameError('描述中不能直接说出你的词语');
        } else {
          throw GameError('现在是描述阶段');
        }
        descs.add({'r': round, 's': seat, 't': text, 'tb': tieBreak});
        host.log('${name(seat)}：$text');
        descIdx++;
        if (descIdx >= order.length) _beginVote();
      case 'vote':
        if (type != 'vote') throw GameError('现在是投票阶段');
        if (!aliveSeats.contains(seat)) throw GameError('你已出局，不能投票');
        if (votes.containsKey(seat)) throw GameError('你已经投过票了');
        final t = asInt(a['target']);
        if (t == seat) throw GameError('不能投给自己');
        if (!candidates.contains(t)) throw GameError('只能投给候选玩家');
        votes[seat] = t;
        if (_voters.isEmpty) _resolveVote();
      case 'blank_guess':
        if (seat != guesser) throw GameError('等待白板猜词');
        if (type == 'skip') {
          host.log('${name(seat)} 放弃猜词');
          guessText = null;
          guessOk = false;
          _afterElimination();
        } else if (type == 'guess') {
          final g = sanitizeText(asStr(a['word'])).trim();
          if (g.isEmpty) throw GameError('请输入你猜的平民词');
          if (g.length > 12) throw GameError('词语最多 12 个字');
          guessText = g;
          guessOk = g == civWord;
          host.log('${name(seat)} 猜平民词：$g —— ${guessOk! ? '猜对了！' : '猜错了'}');
          if (guessOk!) {
            _finish('blank');
          } else {
            _afterElimination();
          }
        } else {
          throw GameError('请猜词或放弃');
        }
      default:
        throw GameError('现在不能操作');
    }
  }

  void _resolveVote() {
    final counts = <int, int>{};
    for (final t in votes.values) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final top = counts.values.fold(0, (m, v) => v > m ? v : m);
    final tied = [for (final c in candidates) if ((counts[c] ?? 0) == top) c];
    _suspicion
      ..clear()
      ..addAll(counts);
    final result = <String, dynamic>{
      'r': round,
      'tb': tieBreak,
      'votes': [for (final e in votes.entries) [e.key, e.value]],
      'out': -1,
      'tie': <int>[],
    };
    lastVote = result;
    if (tied.length == 1) {
      final out = tied.first;
      result['out'] = out;
      result['role'] = roles[out];
      alive[out] = false;
      outs.add({'s': out, 'role': roles[out], 'r': round});
      host.log('${name(out)} 以 $top 票出局，身份是【${roleName(roles[out])}】');
      if (roles[out] == 'blank' && civWord.isNotEmpty) {
        guesser = out;
        phase = 'blank_guess';
        host.log('白板 ${name(out)} 可以猜平民词，猜中则白板获胜');
        return;
      }
      _afterElimination();
      return;
    }
    result['tie'] = tied;
    if (!tieBreak) {
      host.log('${tied.map(name).join('、')} 平票（各 $top 票），请平票玩家再描述一次后重新投票');
      tieBreak = true;
      candidates = tied;
      order = List.of(tied);
      descIdx = 0;
      phase = 'describe';
    } else {
      host.log('再次平票，本轮无人出局');
      _nextRoundOrEnd();
    }
  }

  void _afterElimination() {
    if (!_checkWin()) _nextRoundOrEnd();
  }

  void _nextRoundOrEnd() {
    if (round >= maxRounds) {
      host.log('已达到最大轮数，卧底成功潜伏');
      _finish(aliveSeats.any((s) => roles[s] == 'spy') ? 'spy' : 'blank');
      return;
    }
    _beginRound();
  }

  bool _checkWin() {
    final a = aliveSeats;
    final civ = a.where((s) => roles[s] == 'civ').length;
    final spy = a.where((s) => roles[s] == 'spy').length;
    final blank = a.where((s) => roles[s] == 'blank').length;
    if (spy + blank == 0) {
      _finish('civ');
      return true;
    }
    if (spy + blank >= civ || a.length <= 2) {
      _finish(spy > 0 ? 'spy' : 'blank');
      return true;
    }
    return false;
  }

  void _finish(String w) {
    winner = w;
    phase = 'over';
    if (w == 'civ') {
      winners = [for (final s in playing) if (roles[s] == 'civ') s];
    } else if (w == 'spy') {
      // Undercover side: spies, plus a surviving blank.
      winners = [
        for (final s in playing)
          if (roles[s] == 'spy' || (roles[s] == 'blank' && alive[s])) s
      ];
    } else {
      winners = [for (final s in playing) if (roles[s] == 'blank') s];
    }
    final label = switch (w) { 'civ' => '平民获胜！', 'spy' => '卧底获胜！', _ => '白板获胜！' };
    host.log('$label 平民词：$civWord，卧底词：$spyWord');
  }

  // ---------------------------------------------------------------- view

  @override
  Map<String, dynamic> view(int seat) {
    final all = isOver || (seat >= 0 && seat == gm);
    final me = seat >= 0 && seat < players ? seat : -1;
    String? myWord;
    String? myRole;
    if (me >= 0) {
      if (roles[me] == 'gm') {
        myRole = 'gm';
      } else if (roles[me] == 'blank') {
        myRole = 'blank';
      } else if (phase != 'gm_setup') {
        myWord = wordOf(me);
      }
      if (all) myRole = roles[me];
    }
    return {
      'phase': phase,
      'round': round,
      'gm': gm,
      'mode': gm >= 0 ? 'gm' : 'bank',
      'alive': alive,
      'roles': [
        for (var s = 0; s < players; s++)
          if (all || !alive[s] || s == gm || (s == me && roles[s] == 'blank')) roles[s] else null
      ],
      'myWord': myWord,
      'myRole': myRole,
      'civWord': all && phase != 'gm_setup' ? civWord : null,
      'spyWord': all && phase != 'gm_setup' ? spyWord : null,
      'words': all && phase != 'gm_setup' ? [for (var s = 0; s < players; s++) wordOf(s)] : null,
      'order': order,
      'speaker': phase == 'describe' && descIdx < order.length ? order[descIdx] : -1,
      'tieBreak': tieBreak,
      'descs': descs,
      'candidates': phase == 'vote' ? candidates : const <int>[],
      'voted': [for (final s in votes.keys) s],
      'myVote': me >= 0 ? votes[me] : null,
      // GM sees live votes; others only after resolution.
      'liveVotes': seat >= 0 && seat == gm ? [for (final e in votes.entries) [e.key, e.value]] : null,
      'lastVote': lastVote,
      'outs': outs,
      'guesser': phase == 'blank_guess' ? guesser : -1,
      'guess': guessText,
      'guessOk': guessOk,
      'winner': winner,
      'winners': winners,
      'over': isOver,
    };
  }

  // ---------------------------------------------------------------- bots / AI

  static const _generic = [
    '这个东西挺常见的',
    '生活里经常能碰到',
    '大家应该都见过',
    '我身边就有',
    '有好几种不同的样子',
    '小朋友也知道',
    '说多了就暴露了',
    '它有自己的特点',
    '不同地方叫法可能不一样',
    '我还挺喜欢的',
    '和我们的日常生活有关',
    '这个我很熟悉',
    '有时候会让人想起小时候',
    '网上经常能看到',
    '一般人都能说出一二',
  ];

  static const _blankHints = [
    '和上一位说的差不多',
    '我同意前面的描述',
    '嗯……挺常见的',
    '这个有点难描述',
    '我觉得大家说得都对',
    '平时能接触到',
  ];

  static const _hintMap = <String, List<String>>{
    '牛奶': ['白色的', '早餐常喝'],
    '豆浆': ['早餐常喝', '热的比较好'],
    '饺子': ['过年必吃', '有馅儿'],
    '包子': ['早餐常吃', '有馅儿'],
    '眉毛': ['在脸上', '每个人都有'],
    '胡子': ['在脸上', '会越长越长'],
    '猫': ['是宠物', '毛茸茸的'],
    '狗': ['是宠物', '很忠诚'],
    '咖啡': ['提神', '有点苦'],
    '奶茶': ['年轻人爱喝', '甜甜的'],
    '火锅': ['适合一群人吃', '冬天吃很暖和'],
    '手机': ['每天都在用', '离不开它'],
    '医生': ['在医院', '穿白色的衣服'],
    '老师': ['在学校', '很辛苦'],
    '足球': ['一种球类运动', '要跑很多'],
    '篮球': ['一种球类运动', '个子高有优势'],
    '春节': ['很热闹', '家人团聚'],
    '中秋节': ['家人团聚', '要赏月'],
    '钢琴': ['一种乐器', '有黑白色'],
    '西瓜': ['夏天吃', '水分很多'],
    '苹果': ['一种水果', '很常见'],
    '香蕉': ['一种水果', '黄色的'],
  };

  String _botDesc(int seat) {
    final w = wordOf(seat);
    final opts = <String>[];
    if (w.isEmpty) {
      opts.addAll(_blankHints);
    } else {
      opts.addAll(_generic);
      final h = _hintMap[w];
      if (h != null) opts.addAll(h);
      opts.add('是个${w.length}个字的词');
      opts.removeWhere((t) => t.contains(w));
    }
    // Avoid repeating own earlier descriptions when possible.
    final used = {for (final d in descs) if (d['s'] == seat) d['t']};
    final fresh = opts.where((t) => !used.contains(t)).toList();
    final pool = fresh.isEmpty ? opts : fresh;
    return pool[rng.nextInt(pool.length)];
  }


  final AiSlot _ai = AiSlot();
  static const Map<String, dynamic> _wait = {'_pending': true};

  /// True when [text] gives away [word]: contains it, or (for longer words)
  /// any run of 2+ consecutive characters of it; 1-char words: the char.
  static bool leaksWord(String text, String word) {
    if (word.isEmpty) return false;
    if (text.contains(word)) return true;
    if (word.length == 1) return false;
    for (var i = 0; i + 2 <= word.length; i++) {
      if (text.contains(word.substring(i, i + 2))) return true;
    }
    return false;
  }

  String _descHistory() {
    if (descs.isEmpty) return '（还没有人描述）';
    final b = StringBuffer();
    for (final d in descs) {
      b.writeln('第${d['r']}轮${d['tb'] == true ? '（平票加赛）' : ''} ${name(d['s'] as int)}（${d['s']}号）：${d['t']}');
    }
    for (final o in outs) {
      b.writeln('第${o['r']}轮 ${name(o['s'] as int)}（${o['s']}号）被投出，身份是${roleName(o['role'] as String)}');
    }
    return b.toString().trimRight();
  }

  static const _sys = '你在玩派对游戏“谁是卧底”。大多数人（平民）拿到同一个词，少数卧底拿到一个相近但不同的词，'
      '可能还有一个没有词的“白板”。每个人都不知道自己是平民还是卧底，只知道自己的词。'
      '大家轮流用一句话描述自己的词，然后投票淘汰最可疑的人。平民要找出卧底，卧底和白板要隐藏自己。';

  Map<String, dynamic>? _aiDescribe(int seat) {
    final w = wordOf(seat);
    final r = _ai.poll(setup.ai!, 'desc:$round:${tieBreak ? 1 : 0}:$seat', () {
      final p = StringBuffer();
      if (w.isEmpty) {
        p.writeln('你是白板：你没有拿到词。请根据别人的描述猜测大家的词，给出一句模糊但不突兀的描述，混在人群里不被发现。');
      } else {
        p.writeln('你的词是：「$w」（你不知道自己是平民还是卧底）。');
        p.writeln('描述要求：一句话，不超过 20 个字；绝对不能说出这个词或其中任何字；不要太直白，以免卧底猜到平民词，'
            '也不要太偏，以免被当成卧底；参考别人的描述判断自己是否可能是卧底，如果像卧底就说得更含糊、向大家靠拢。');
      }
      p
        ..writeln('目前的描述记录：')
        ..writeln(_descHistory())
        ..writeln('不要重复别人已经说过的话。只输出你的描述这一句话，不要加引号或解释。');
      return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 80);
    });
    if (r.pending) return _wait;
    final t0 = r.text;
    if (t0 == null) return null;
    final t = AiText.firstLine(sanitizeText(t0), maxLen: 200).replaceAll(RegExp(r'\s+'), ' ');
    if (t.length < 2 || t.length > maxDescLen) return null;
    if (leaksWord(t, w)) return null;
    if (t.contains('{') || t.contains('卧底') || t.contains('平民') || t.contains('白板')) return null;
    if (descs.any((d) => d['t'] == t)) return null;
    return {'type': 'describe', 'text': t};
  }

  Map<String, dynamic>? _aiVote(int seat, List<int> c) {
    final w = wordOf(seat);
    final r = _ai.poll(setup.ai!, 'vote:$round:${tieBreak ? 1 : 0}:$seat', () {
      final p = StringBuffer()
        ..writeln(w.isEmpty ? '你是白板（没有词）。' : '你的词是：「$w」（你不知道自己是平民还是卧底）。')
        ..writeln('描述记录：')
        ..writeln(_descHistory())
        ..writeln('可以投票的玩家：${[for (final s in c) '$s号 ${name(s)}'].join('，')}')
        ..writeln('请分析谁的描述和大多数人不一致、最可能是卧底（如果你发现自己的词才是少数派，就投一个平民来保护自己）。')
        ..write('只输出 JSON：{"target": 座位号}');
      return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 150);
    });
    if (r.pending) return _wait;
    final j = r.text == null ? null : AiText.json(r.text!);
    final t = j == null ? -1 : asInt(j['target']);
    return c.contains(t) ? {'type': 'vote', 'target': t} : null;
  }

  Map<String, dynamic>? _aiGuess(int seat) {
    final r = _ai.poll(setup.ai!, 'guess:$seat', () => AiRequest(
        system: _sys,
        prompt: '你是白板，已被投出，现在可以猜平民的词，猜中则白板获胜。\n描述记录：\n${_descHistory()}\n'
            '请根据大多数人的描述猜出平民词（一个词，不超过 12 字）。只输出这个词。',
        maxTokens: 30));
    if (r.pending) return _wait;
    if (r.text == null) return null;
    final g = AiText.firstLine(sanitizeText(r.text!), maxLen: 100).replaceAll(RegExp(r'\s+'), '');
    if (g.isEmpty || g.length > 12 || g.contains('{')) return null;
    return {'type': 'guess', 'word': g};
  }

  // AI-backed bots

  @override
  Map<String, dynamic>? bot(int seat) {
    if (!waitingFor.contains(seat)) return null;
    switch (phase) {
      case 'gm_setup':
        final (a, b) = _randomPair();
        return {'type': 'words', 'civ': a, 'spy': b};
      case 'describe':
        if (aiOn) {
          final a = _aiDescribe(seat);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        return {'type': 'describe', 'text': _botDesc(seat)};
      case 'vote':
        final c = candidates.where((s) => s != seat).toList();
        if (c.isEmpty) return null;
        if (aiOn) {
          final a = _aiVote(seat, c);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        if (botLevel == 0) return {'type': 'vote', 'target': c[rng.nextInt(c.length)]};
        // Weighted random: suspicion from last vote + verbal-only players.
        // 困难: players whose descriptions echo this bot's own word hints look safe.
        final myHints = _hintMap[wordOf(seat)] ?? const <String>[];
        final weights = [
          for (final s in c)
            3 +
                (_suspicion[s] ?? 0) * (botLevel == 2 ? 3 : 2) +
                (descs.any((d) => d['s'] == s && d['r'] == round && (d['t'] as String).startsWith('（')) ? 1 : 0) -
                (botLevel == 2 && descs.any((d) => d['s'] == s && myHints.contains(d['t'])) ? 2 : 0)
        ];
        var r = rng.nextInt(weights.fold(0, (a, b) => a + b));
        for (var i = 0; i < c.length; i++) {
          r -= weights[i];
          if (r < 0) return {'type': 'vote', 'target': c[i]};
        }
        return {'type': 'vote', 'target': c.last};
      case 'blank_guess':
        if (aiOn) {
          final a = _aiGuess(seat);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        return {'type': 'skip'};
    }
    return null;
  }

  @override
  List<int>? get placings => isOver ? rankWinners(players, [...winners, if (gm >= 0) gm]) : null; // 出题人不分胜负

  @override
  int get botDelayMs => phase == 'vote' ? 1200 : 1500;
}
