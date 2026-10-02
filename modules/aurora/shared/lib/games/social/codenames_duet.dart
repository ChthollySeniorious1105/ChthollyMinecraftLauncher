import '../../src/ai.dart';
import '../../src/engine.dart';
import 'codenames.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'words.dart';

/// Key codes on each side's key card.
const int duetAgent = 0;
const int duetBystander = 1;
const int duetAssassin = 2;

/// Clue number meaning "∞".
const int duetInfinite = -1;

/// Builds a random two-sided Codenames Duet key with the official overlap.
/// Returns [keyA, keyB] (25 entries each, codes [duetAgent]/[duetBystander]/[duetAssassin]).
List<List<int>> buildDuetKeys(Iterable<int> Function(List<int>) shuffle) {
  const g = duetAgent, b = duetBystander, x = duetAssassin;
  // (side A, side B) pairs
  final pairs = <List<int>>[
    for (var i = 0; i < 3; i++) [g, g], // green on both
    [g, x], // A agent, B assassin
    for (var i = 0; i < 5; i++) [g, b],
    [x, g], // A assassin, B agent
    for (var i = 0; i < 5; i++) [b, g],
    [x, x], // assassin on both
    [x, b],
    [b, x],
    for (var i = 0; i < 7; i++) [b, b],
  ];
  final order = shuffle([for (var i = 0; i < 25; i++) i]).toList();
  return [
    [for (final i in order) pairs[i][0]],
    [for (final i in order) pairs[i][1]],
  ];
}

/// 代号：合作版 (Codenames Duet). Two sides (A = even seats, B = odd seats)
/// cooperate to find all 15 agents before the timer tokens run out.
class CodenamesDuet extends GameEngine {
  CodenamesDuet(super.setup);

  static const sideNames = ['A 方', 'B 方'];

  late List<String> words;
  late List<List<int>> keys; // keys[side][card]
  final List<bool> found = List.filled(25, false);
  // byMark[side][card]: `side` guessed this card and it was a bystander on the
  // other side's key (so it is not an agent for clues from the other side).
  final List<List<bool>> byMark = [List.filled(25, false), List.filled(25, false)];
  int maxTokens = 9;
  int tokens = 9;
  int giver = 0; // side giving the clue
  String phase = 'clue'; // clue guess sudden over
  String clue = '';
  int clueNum = 0;
  int guesses = 0;
  int lastCard = -1;
  String lastResult = ''; // agent bystander assassin
  int lastSide = -1;
  bool won = false;
  String reason = '';
  int lossCard = -1;
  final List<Map<String, dynamic>> clues = [];

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 1100;

  int sideOf(int seat) => seat % 2;
  List<int> seatsOf(int side) => [for (var s = 0; s < players; s++) if (sideOf(s) == side) s];

  /// Agents still hidden on [side]'s key.
  int remainingOn(int side) => [for (var i = 0; i < 25; i++) if (!found[i] && keys[side][i] == duetAgent) i].length;

  int get totalAgents => [for (var i = 0; i < 25; i++) if (keys[0][i] == duetAgent || keys[1][i] == duetAgent) i].length;
  int get foundCount => found.where((f) => f).length;

  @override
  void start() {
    maxTokens = setup.opt<int>('tokens', 9);
    tokens = maxTokens;
    words = shuffled(codenameWords, rng).take(25).toList();
    keys = buildDuetKeys((l) => shuffled(l, rng));
    giver = rng.nextInt(2);
    final a = seatsOf(0).map(name).join('、'), b = seatsOf(1).map(name).join('、');
    host.log('代号：合作版开始！A 方：$a；B 方：$b。共 $maxTokens 个计时回合，'
        '${sideNames[giver]}先给提示');
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'clue':
        return seatsOf(giver);
      case 'guess':
        return seatsOf(1 - giver);
      case 'sudden':
        return [for (var s = 0; s < players; s++) if (remainingOn(1 - sideOf(s)) > 0) s];
    }
    return const [];
  }

  void _finish(bool win, String why) {
    won = win;
    reason = why;
    phase = 'over';
    host.log(win ? '任务成功！$why' : '任务失败：$why');
  }

  bool _checkWin() {
    if (foundCount >= totalAgents) {
      _finish(true, '找出了全部 $totalAgents 名特工');
      return true;
    }
    return false;
  }

  void _endTurn() {
    tokens--;
    clue = '';
    clueNum = 0;
    guesses = 0;
    if (tokens <= 0) {
      tokens = 0;
      phase = 'sudden';
      host.log('计时用尽，进入突然死亡：不能再给提示，双方可直接猜对方钥匙卡上的特工，猜错即失败');
      return;
    }
    var next = 1 - giver;
    if (remainingOn(next) == 0) next = giver; // that side's key is done
    giver = next;
    phase = 'clue';
  }

  String? clueProblem(String c) {
    if (c.isEmpty) return '提示词不能为空';
    if (c.length > 12) return '提示词最多 12 个字';
    if (c.contains(RegExp(r'\s'))) return '提示词只能是一个词';
    for (var i = 0; i < 25; i++) {
      if (!found[i] && words[i] == c) return '提示词不能是场上的词：${words[i]}';
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    final type = asStr(a['type']);
    final side = sideOf(seat);
    if (phase == 'clue') {
      if (side != giver) throw GameError('等待${sideNames[giver]}给出提示');
      if (type != 'clue') throw GameError('请给出提示');
      final c = sanitizeText(asStr(a['word'])).trim();
      final n = asInt(a['num'], -99);
      final p = clueProblem(c);
      if (p != null) throw GameError(p);
      if (n != duetInfinite && (n < 0 || n > 9)) throw GameError('数字需为 0~9 或 ∞');
      clue = c;
      clueNum = n;
      guesses = 0;
      lastCard = -1;
      lastResult = '';
      clues.add({'side': giver, 'word': c, 'num': n, 'by': seat, 'hits': 0});
      phase = 'guess';
      host.log('${sideNames[giver]} ${name(seat)} 提示：$c ${n == duetInfinite ? '∞' : n}');
      return;
    }
    if (phase == 'guess') {
      if (side == giver) throw GameError('等待${sideNames[1 - giver]}猜词');
      if (type == 'pass') {
        if (guesses == 0) throw GameError('至少要猜一个词');
        host.log('${name(seat)} 停止猜测');
        _endTurn();
        return;
      }
      if (type != 'guess') throw GameError('请选择一张卡');
      final i = _card(a, side);
      guesses++;
      lastCard = i;
      lastSide = side;
      final k = keys[giver][i];
      if (k == duetAgent) {
        found[i] = true;
        lastResult = 'agent';
        if (clues.isNotEmpty) clues.last['hits'] = (clues.last['hits'] as int) + 1;
        host.log('${name(seat)} 猜「${words[i]}」——特工！');
        if (_checkWin()) return;
        if (remainingOn(giver) == 0) {
          host.log('${sideNames[giver]}钥匙卡上的特工已全部找到');
          _endTurn();
        }
        return;
      }
      if (k == duetAssassin) {
        lastResult = 'assassin';
        lossCard = i;
        _finish(false, '${name(seat)} 猜中了刺客「${words[i]}」');
        return;
      }
      byMark[side][i] = true;
      lastResult = 'bystander';
      host.log('${name(seat)} 猜「${words[i]}」——路人，回合结束');
      _endTurn();
      return;
    }
    if (phase == 'sudden') {
      if (!waitingFor.contains(seat)) throw GameError('对方钥匙卡上的特工已全部找到');
      if (type != 'guess') throw GameError('突然死亡：请直接选择一张卡');
      final i = _card(a, side);
      lastCard = i;
      lastSide = side;
      final k = keys[1 - side][i];
      if (k == duetAgent) {
        found[i] = true;
        lastResult = 'agent';
        host.log('${name(seat)} 猜「${words[i]}」——特工！');
        _checkWin();
        return;
      }
      lastResult = k == duetAssassin ? 'assassin' : 'bystander';
      lossCard = i;
      if (k == duetBystander) byMark[side][i] = true;
      _finish(false, '突然死亡中 ${name(seat)} 猜错了「${words[i]}」（${k == duetAssassin ? '刺客' : '路人'}）');
      return;
    }
    throw GameError('现在不能操作');
  }

  int _card(Map<String, dynamic> a, int side) {
    final i = asInt(a['card']);
    if (i < 0 || i >= 25 || found[i]) throw GameError('无效的卡片');
    if (byMark[side][i]) throw GameError('这张卡已确认是路人');
    return i;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final mySide = me ? sideOf(seat) : -1;
    return {
      'phase': phase,
      'words': words,
      'found': found,
      'byA': byMark[0],
      'byB': byMark[1],
      'sides': [for (var s = 0; s < players; s++) sideOf(s)],
      'mySide': mySide,
      'myKey': me ? keys[mySide] : null,
      'keys': isOver ? keys : null,
      'giver': giver,
      'tokens': tokens,
      'maxTokens': maxTokens,
      'foundCount': foundCount,
      'totalAgents': totalAgents,
      'remaining': [remainingOn(0), remainingOn(1)],
      'clue': clue,
      'clueNum': clueNum,
      'guesses': guesses,
      'lastCard': lastCard,
      'lastResult': lastResult,
      'lastSide': lastSide,
      'lossCard': lossCard,
      'won': won,
      'reason': reason,
      'clues': clues,
      'waiting': waitingFor,
    };
  }

  // ---------------------------------------------------------------- bot
  /// Only one bot per side acts (the first bot seat of that side).
  bool _designated(int seat) {
    final mine = seatsOf(sideOf(seat)).where(isBot).toList();
    return mine.isEmpty || mine.first == seat;
  }

  Map<String, dynamic> _botClue(int side) {
    // Uses only the bot's own key (legitimately known to the clue-giver).
    final own = keys[side];
    String? best;
    var bestSc = 0.0;
    var bestN = 1;
    codenameCategories.forEach((cat, list) {
      if (clueProblem(cat) != null) return;
      final set = list.toSet();
      final hits = [for (var i = 0; i < 25; i++) if (!found[i] && set.contains(words[i])) i];
      if (hits.any((i) => own[i] == duetAssassin)) return;
      final good = hits.where((i) => own[i] == duetAgent).length;
      if (good == 0) return;
      final sc = good - (hits.length - good) * 1.2 + rng.nextDouble() * 0.3;
      if (sc > bestSc) {
        bestSc = sc;
        best = cat;
        bestN = good;
      }
    });
    if (best != null) return {'type': 'clue', 'word': best, 'num': bestN.clamp(1, 2)};
    final pool = codenameWords.where((w) => !words.contains(w) && clueProblem(w) == null).toList();
    final w = pool.isEmpty ? '线索' : pool[rng.nextInt(pool.length)];
    return {'type': 'clue', 'word': w, 'num': 1 + rng.nextInt(2)};
  }

  Map<String, dynamic> _botGuess(int side, {bool useClue = true}) {
    final open = [for (var i = 0; i < 25; i++) if (!found[i] && !byMark[side][i]) i];
    if (useClue) {
      final cat = codenameCategories[clue];
      if (cat != null) {
        final t = open.where((i) => cat.contains(words[i])).toList();
        final acc = switch (botLevel) { 0 => 0.6, 2 => 0.95, _ => 0.85 };
        if (t.isNotEmpty && rng.nextDouble() < acc) return {'type': 'guess', 'card': t[rng.nextInt(t.length)]};
      }
    }
    return {'type': 'guess', 'card': open[rng.nextInt(open.length)]};
  }

  // ---------------------------------------------------------------- AI

  final AiSlot _ai = AiSlot();

  static const _sys = '你在玩合作桌游“代号：合作版”（Codenames Duet）。桌上有 25 个词，两方各看一面钥匙卡：'
      '上面标出哪些词是特工、路人、刺客。给提示的一方只能说一个提示词加一个数字，另一方根据提示在给提示方的钥匙卡上找特工；'
      '翻到路人结束回合，翻到刺客直接失败。双方合作在计时用完前找出全部特工。只输出要求的 JSON。';

  String _openWords(int side) => [for (var i = 0; i < 25; i++) if (!found[i] && !byMark[side][i]) words[i]].join('、');

  Map<String, dynamic>? _aiClue(int side) {
    final r = _ai.poll(setup.ai!, 'clue:${clues.length}', () {
      final own = keys[side];
      String cat(int k) => [for (var i = 0; i < 25; i++) if (!found[i] && own[i] == k) words[i]].join('、');
      final p = StringBuffer()
        ..writeln('你负责给提示。你的钥匙卡上还没找到的词：')
        ..writeln('- 特工（要让队友翻）：${cat(duetAgent)}')
        ..writeln('- 路人（避免）：${cat(duetBystander)}')
        ..writeln('- 刺客（绝对避免）：${cat(duetAssassin)}')
        ..writeln('已经给过的提示：${clues.isEmpty ? '无' : [for (final c in clues) '「${c['word']}」${c['num'] == duetInfinite ? '∞' : c['num']}'].join('，')}')
        ..writeln('剩余计时回合：$tokens。请想一个中文提示词，关联 1~3 个特工词，不能让队友联想到刺客。'
            '提示词必须是一个词，不能是场上的词，也不能包含场上的词或被场上的词包含。')
        ..write('只输出 JSON：{"clue":"提示词","number":关联数量}');
      return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 120);
    });
    if (r.pending) return const {};
    final j = r.text == null ? null : AiText.json(r.text!);
    if (j == null) return null;
    final c = j['clue'], n = asInt(j['number'] ?? j['num']);
    if (c is! String) return null;
    final w = c.trim();
    if (!Codenames.validAiClue(w, words) || clueProblem(w) != null) return null;
    if (n < 1 || n > remainingOn(side) || n > 9) return null;
    return {'type': 'clue', 'word': w, 'num': n};
  }

  Map<String, dynamic>? _aiGuess(int side) {
    final r = _ai.poll(setup.ai!, 'guess:${clues.length}', () {
      final p = StringBuffer()
        ..writeln('你负责猜词。可以选择的词：${_openWords(side)}')
        ..writeln('已找到的特工：${[for (var i = 0; i < 25; i++) if (found[i]) words[i]].join('、')}')
        ..writeln('历史提示：${[for (final c in clues) '「${c['word']}」${c['num'] == duetInfinite ? '∞' : c['num']}'].join('，')}')
        ..writeln('本轮提示：「$clue」${clueNum == duetInfinite ? '∞' : clueNum}')
        ..writeln('请按把握从大到小列出你要翻的词（只写有把握的），只能从可以选择的词中选。')
        ..write('只输出 JSON：{"words":["词1","词2"]}');
      return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 120);
    });
    if (r.pending) return const {};
    final j = r.text == null ? null : AiText.json(r.text!);
    final ws = j?['words'];
    if (ws is! List) return null;
    final picks = <int>[];
    for (final w in ws) {
      final i = w is String ? words.indexOf(w.trim()) : -1;
      if (i >= 0 && !picks.contains(i)) picks.add(i);
    }
    if (picks.isEmpty) return null;
    final limit = clueNum > 0 ? clueNum : 1;
    final next = picks.where((i) => !found[i] && !byMark[side][i]).toList();
    if (next.isEmpty || guesses >= limit) return guesses > 0 ? {'type': 'pass'} : null;
    return {'type': 'guess', 'card': next.first};
  }

  /// Cooperative: everyone shares the result (placings must contain a 1).
  @override
  List<int>? get placings => isOver ? List.filled(players, 1) : null;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver || !waitingFor.contains(seat) || !_designated(seat)) return null;
    final side = sideOf(seat);
    switch (phase) {
      case 'clue':
        if (aiOn) {
          final a = _aiClue(side);
          if (a != null) return a.isEmpty ? null : a;
        }
        return _botClue(side);
      case 'guess':
        final limit = clueNum > 0 ? clueNum : 1;
        if (guesses >= limit) return {'type': 'pass'};
        if (aiOn) {
          final a = _aiGuess(side);
          if (a != null) return a.isEmpty ? null : a;
        }
        return _botGuess(side);
      case 'sudden':
        return _botGuess(side, useClue: false);
    }
    return null;
  }
}
