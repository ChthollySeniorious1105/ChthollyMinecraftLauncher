import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'words.dart';

/// 行动代号. Cards: key[i] = 0 red, 1 blue, 2 bystander, 3 assassin.
class Codenames extends GameEngine {
  Codenames(super.setup);

  static const teamNames = ['红队', '蓝队'];

  late List<int> teamOf; // seat -> 0/1
  final List<int> spymaster = [-1, -1];
  late List<String> words;
  late List<int> key;
  late List<bool> revealed;
  List<int> revealedBy = List.filled(25, -1);
  int startTeam = 0;
  int team = 0;
  String phase = 'clue'; // clue guess over
  String clue = '';
  int clueNum = 0;
  int guessesLeft = 0;
  int guessesMade = 0;
  List<int> intended = [];
  int winner = -1;
  String reason = '';
  int lastCard = -1;
  final List<Map<String, dynamic>> clues = [];

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 1200;

  @override
  void start() {
    teamOf = List.filled(players, 0);
    final random = setup.opt<String>('assign', 'alternate') == 'random';
    final order = random ? shuffled([for (var i = 0; i < players; i++) i], rng) : [for (var i = 0; i < players; i++) i];
    for (var i = 0; i < players; i++) {
      final s = order[i];
      teamOf[s] = i % 2;
      if (spymaster[i % 2] < 0) spymaster[i % 2] = s;
    }
    words = shuffled(codenameWords, rng).take(25).toList();
    startTeam = rng.nextInt(2);
    key = shuffled([
      ...List.filled(9, startTeam),
      ...List.filled(8, 1 - startTeam),
      ...List.filled(7, 2),
      3,
    ], rng);
    revealed = List.filled(25, false);
    team = startTeam;
    host.log('行动代号开始！${teamNames[startTeam]}先手（9 张），'
        '红队队长 ${name(spymaster[0])}，蓝队队长 ${name(spymaster[1])}');
  }

  List<int> operatives(int t) => [for (var s = 0; s < players; s++) if (teamOf[s] == t && spymaster[t] != s) s];

  int remaining(int t) => [for (var i = 0; i < 25; i++) if (!revealed[i] && key[i] == t) i].length;

  @override
  List<int> get waitingFor {
    if (phase == 'clue') return [spymaster[team]];
    if (phase == 'guess') return operatives(team);
    return const [];
  }

  void _finish(int w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    host.log('${teamNames[w]}获胜！$why');
  }

  void _endTurn() {
    team = 1 - team;
    phase = 'clue';
    clue = '';
    clueNum = 0;
    intended = [];
    guessesLeft = 0;
    guessesMade = 0;
  }

  String? clueProblem(String c) {
    if (c.isEmpty) return '提示词不能为空';
    if (c.length > 12) return '提示词太长';
    if (c.contains(' ')) return '提示词只能是一个词';
    for (var i = 0; i < 25; i++) {
      if (revealed[i]) continue;
      final w = words[i];
      if (w == c || w.contains(c) || c.contains(w)) return '提示词不能是（或包含）场上的词：$w';
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (phase == 'clue') {
      if (seat != spymaster[team]) throw GameError('等待${teamNames[team]}队长给出提示');
      if (type != 'clue') throw GameError('请给出提示');
      final c = sanitizeText(asStr(a['word'])).trim();
      final n = asInt(a['num']);
      final p = clueProblem(c);
      if (p != null) throw GameError(p);
      if (n < 1 || n > 9) throw GameError('数字需在 1~9 之间');
      clue = c;
      clueNum = n;
      guessesLeft = n + 1;
      guessesMade = 0;
      // `_targets` is bot bookkeeping (which words a bot spymaster meant). Never
      // accept it from a human client: bot teammates would follow it, leaking the key.
      intended = isBot(seat)
          ? asIntList(a['_targets']).where((i) => i >= 0 && i < 25 && key[i] == team).take(25).toList()
          : <int>[];
      clues.add({'team': team, 'word': c, 'num': n, 'by': seat});
      phase = 'guess';
      lastCard = -1;
      host.log('${teamNames[team]}队长：$c $n');
      return;
    }
    if (!operatives(team).contains(seat)) throw GameError('等待${teamNames[team]}队员猜词');
    if (type == 'pass') {
      if (guessesMade == 0) throw GameError('至少要猜一个词');
      host.log('${name(seat)} 结束了猜词');
      _endTurn();
      return;
    }
    if (type != 'guess') throw GameError('请选择一张卡');
    final i = asInt(a['card']);
    if (i < 0 || i >= 25 || revealed[i]) throw GameError('无效的卡片');
    revealed[i] = true;
    revealedBy[i] = seat;
    lastCard = i;
    guessesMade++;
    guessesLeft--;
    final k = key[i];
    const kn = ['红队', '蓝队', '路人', '刺客'];
    host.log('${name(seat)} 翻开「${words[i]}」——${kn[k]}');
    if (k == 3) {
      _finish(1 - team, '${teamNames[team]}翻到了刺客');
      return;
    }
    if (remaining(0) == 0) {
      _finish(0, '红队找出了全部特工');
      return;
    }
    if (remaining(1) == 0) {
      _finish(1, '蓝队找出了全部特工');
      return;
    }
    if (k != team || guessesLeft <= 0) _endTurn();
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final isSpy = me && spymaster.contains(seat);
    final showKey = isSpy || isOver;
    return {
      'phase': phase,
      'words': words,
      'revealed': revealed,
      'revealedBy': revealedBy,
      'key': [for (var i = 0; i < 25; i++) (showKey || revealed[i]) ? key[i] : -1],
      'teams': teamOf,
      'spymasters': spymaster,
      'team': team,
      'startTeam': startTeam,
      'clue': clue,
      'clueNum': clueNum,
      'guessesLeft': guessesLeft,
      'guessesMade': guessesMade,
      'remaining': [remaining(0), remaining(1)],
      'winner': winner,
      'reason': reason,
      'lastCard': lastCard,
      'clues': clues,
      'mySpy': isSpy,
    };
  }

  // ---------------------------------------------------------------- bot
  Map<String, dynamic> _botClue() {
    final own = [for (var i = 0; i < 25; i++) if (!revealed[i] && key[i] == team) i];
    String? bestCat;
    var bestSc = 0.0;
    List<int> bestT = [];
    codenameCategories.forEach((cat, list) {
      if (clueProblem(cat) != null) return;
      final set = list.toSet();
      final hits = [for (var i = 0; i < 25; i++) if (!revealed[i] && set.contains(words[i])) i];
      if (hits.any((i) => key[i] == 3)) return;
      final mine = hits.where((i) => key[i] == team).toList();
      if (mine.isEmpty) return;
      final bad = hits.length - mine.length;
      final sc = mine.length - bad * 1.2 + rng.nextDouble() * 0.3;
      if (sc > bestSc) {
        bestSc = sc;
        bestCat = cat;
        bestT = mine;
      }
    });
    if (bestCat != null) {
      return {'type': 'clue', 'word': bestCat, 'num': bestT.length.clamp(1, 4), '_targets': bestT};
    }
    final t = own[rng.nextInt(own.length)];
    var word = '提示';
    if (clueProblem(word) != null) word = '线索';
    if (clueProblem(word) != null) word = '猜猜';
    return {'type': 'clue', 'word': word, 'num': 1, '_targets': [t]};
  }

  /// Seat allowed to guess as a bot: the first bot operative if the team has
  /// one (so bots don't steamroll humans), otherwise any operative (offline).
  bool _mayBotGuess(int seat) {
    final ops = operatives(team);
    if (!ops.contains(seat)) return false;
    final bots = ops.where(isBot).toList();
    return bots.isEmpty || bots.first == seat;
  }

  // ---------------------------------------------------------------- AI

  final AiSlot _ai = AiSlot();

  /// Strict check for a model-proposed clue: one word (letters/CJK only), not
  /// any board word, no substring relation with any board word.
  static bool validAiClue(String c, List<String> board) {
    if (c.isEmpty || c.length > 8) return false;
    if (!RegExp(r'^[一-鿿A-Za-z]+$').hasMatch(c)) return false;
    for (final w in board) {
      if (w == c || w.contains(c) || c.contains(w)) return false;
    }
    return true;
  }

  static const _sys = '你在玩桌游“行动代号”（Codenames）。桌上有 25 个词，红蓝两队各有若干己方特工词，另有路人词和 1 个刺客词。'
      '队长只能说一个提示词加一个数字，队员根据提示翻词；翻到对方特工或路人会结束回合，翻到刺客直接输。只输出要求的 JSON。';

  Map<String, dynamic>? _aiClue() {
    final t = team;
    final r = _ai.poll(setup.ai!, 'clue:${clues.length}', () {
      String cat(int k) => [for (var i = 0; i < 25; i++) if (!revealed[i] && key[i] == k) words[i]].join('、');
      final p = StringBuffer()
        ..writeln('你是${teamNames[t]}队长。场上还没翻开的词：')
        ..writeln('- 我方特工（要让队友翻）：${cat(t)}')
        ..writeln('- 对方特工（避免）：${cat(1 - t)}')
        ..writeln('- 路人（避免）：${cat(2)}')
        ..writeln('- 刺客（绝对避免）：${cat(3)}')
        ..writeln('已经给过的提示：${clues.isEmpty ? '无' : [for (final c in clues) '${teamNames[c['team'] as int]}「${c['word']}」${c['num']}'].join('，')}')
        ..writeln('请想一个中文提示词，同时关联 2~3 个我方特工词（有把握也可以 1 个或 4 个），但不能让队友联想到刺客或对方的词。'
            '提示词必须是一个词，不能是场上任何词，也不能包含场上的词或被场上的词包含，不能用数字或拼音。')
        ..write('只输出 JSON：{"clue":"提示词","number":关联数量,"targets":["你想让队友翻的词"]}');
      return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 150);
    });
    if (r.pending) return const {};
    final j = r.text == null ? null : AiText.json(r.text!);
    if (j == null) return null;
    final c = j['clue'], n = asInt(j['number'] ?? j['num']);
    if (c is! String) return null;
    final w = c.trim();
    if (!validAiClue(w, words) || clueProblem(w) != null) return null;
    if (n < 1 || n > remaining(t) || n > 9) return null;
    final tg = j['targets'];
    final targets = tg is List ? [for (final x in tg) if (x is String) words.indexOf(x)].where((i) => i >= 0 && !revealed[i] && key[i] == t).toList() : <int>[];
    return {'type': 'clue', 'word': w, 'num': n, '_targets': targets};
  }

  /// AI guesser's ordered picks for the current clue (public info only).
  AiPoll _aiPicks() => _ai.poll(setup.ai!, 'guess:${clues.length}', () {
        final open = [for (var i = 0; i < 25; i++) if (!revealed[i]) words[i]];
        const kn = ['红队', '蓝队', '路人', '刺客'];
        final p = StringBuffer()
          ..writeln('你是${teamNames[team]}队员。还没翻开的词：${open.join('、')}')
          ..writeln('已翻开：${[for (var i = 0; i < 25; i++) if (revealed[i]) '${words[i]}(${kn[key[i]]})'].join('、')}')
          ..writeln('历史提示：${[for (final c in clues) '${teamNames[c['team'] as int]}「${c['word']}」${c['num']}'].join('，')}')
          ..writeln('本轮队长提示：「$clue」$clueNum')
          ..writeln('请按把握从大到小列出你要翻的词（最多 $clueNum 个，只写有把握的，可以少于这个数），只能从还没翻开的词中选。')
          ..write('只输出 JSON：{"words":["词1","词2"]}');
        return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 120);
      });

  /// Next AI guess: action, `{}` when waiting, null for heuristic fallback.
  Map<String, dynamic>? _aiGuess() {
    final r = _aiPicks();
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
    final next = picks.take(clueNum + 1).where((i) => !revealed[i]).toList();
    if (next.isEmpty || guessesMade >= clueNum) {
      return guessesMade > 0 ? {'type': 'pass'} : null;
    }
    return {'type': 'guess', 'card': next.first};
  }

  @override
  List<int>? get placings => isOver ? [for (var s = 0; s < players; s++) teamOf[s] == winner ? 1 : 2] : null;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'clue') {
      if (seat != spymaster[team]) return null;
      if (aiOn) {
        final a = _aiClue();
        if (a != null) return a.isEmpty ? null : a;
      }
      final c = _botClue();
      if (botLevel == 0 && (c['num'] as int) > 1) c['num'] = 1 + rng.nextInt(c['num'] as int);
      return c;
    }
    if (phase != 'guess' || !_mayBotGuess(seat)) return null;
    if (aiOn) {
      final a = _aiGuess();
      if (a != null) return a.isEmpty ? null : a;
    }
    final open = [for (var i = 0; i < 25; i++) if (!revealed[i]) i];
    if (guessesMade >= clueNum && guessesMade > 0) return {'type': 'pass'};
    var targets = intended.where((i) => !revealed[i]).toList();
    if (targets.isEmpty) {
      // try category meaning of a human clue
      final cat = codenameCategories[clue];
      if (cat != null) {
        targets = open.where((i) => cat.contains(words[i])).toList();
      }
    }
    if (targets.isEmpty) {
      if (guessesMade > 0) return {'type': 'pass'};
      return {'type': 'guess', 'card': open[rng.nextInt(open.length)]};
    }
    final miss = switch (botLevel) { 0 => 0.4, 2 => 0.05, _ => 0.15 };
    if (rng.nextDouble() < miss) return {'type': 'guess', 'card': open[rng.nextInt(open.length)]};
    return {'type': 'guess', 'card': targets[rng.nextInt(targets.length)]};
  }
}
