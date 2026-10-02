import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'decrypto_words.dart';

/// Word/category lookup for bots: built-in words carry the index of their
/// themed line in the bank as a category.
final Map<String, int> _catOf = () {
  final m = <String, int>{};
  for (var i = 0; i < decryptoWordLines.length; i++) {
    for (final w in decryptoWordLines[i]) {
      m.putIfAbsent(w, () => i);
    }
  }
  return m;
}();

const int kDecClueMax = 12;

/// Parses admin lines (one word per line; `词|…` extra fields ignored).
List<String> parseDecryptoLines(List<String> lines) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final w = line.split(RegExp(r'[|｜]')).first.replaceAll(RegExp(r'\s+'), '');
    if (w.isEmpty || w.length > 8) continue;
    if (seen.add(w)) out.add(w);
  }
  return out;
}

/// 截码战 (Decrypto). Team 0 = even seats, team 1 = odd seats.
///
/// Each round: both encryptors see a secret 3-digit code (digits 1..4, distinct)
/// and give 3 clues (phase `clue`); then each team guesses its own code and,
/// from round 2, tries to intercept the other team's (phase `guess`); results
/// shown (phase `result`, timed). 2 interceptions win, 2 miscommunications
/// lose. After 8 rounds / simultaneous outcomes: score = 拦截 − 失误, then a
/// tiebreak where each team guesses the other's 4 keywords.
class Decrypto extends GameEngine {
  Decrypto(super.setup);

  static const maxRounds = 8;
  static const resultMs = 6000;

  late List<List<String>> words; // [team][0..3]
  late List<List<int>> members;
  String phase = 'clue';
  int round = 1;
  List<List<int>> code = [[], []];
  List<List<String>?> clues = [null, null];
  List<List<int>?> own = [null, null];
  List<List<int>?> icpt = [null, null]; // icpt[t] = team t's guess of the OTHER team's code
  List<int> ints = [0, 0], miss = [0, 0];
  List<List<String>?> tbGuess = [null, null];
  List<int> tbScore = [0, 0];

  /// {'r','t','clues','code','guess','icpt'(opponent's guess or null)}
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? lastResult;
  int winner = -2; // -2 ongoing, -1 draw, 0/1 team
  String reason = '';

  @override
  bool get isOver => phase == 'over';

  final AiSlot _ai = AiSlot();

  @override
  List<int>? get placings => !isOver ? null : (winner < 0 ? List.filled(players, 1) : [for (var s = 0; s < players; s++) teamOf(s) == winner ? 1 : 2]);

  @override
  int get botDelayMs => 1400;

  int teamOf(int s) => s >= 0 && s < players ? s % 2 : -1;
  int encryptor(int t) => members[t][(round - 1) % members[t].length];

  /// Seat that the game waits on for team decisions (a human if any, so bots
  /// don't pre-empt their human teammates). Any non-encryptor member may act.
  int lead(int t) {
    final c = [for (final s in members[t]) if (s != encryptor(t)) s];
    return c.firstWhere((s) => !isBot(s), orElse: () => c.first);
  }

  @override
  void start() {
    members = [
      [for (var s = 0; s < players; s += 2) s],
      [for (var s = 1; s < players; s += 2) s],
    ];
    final src = setup.opt<String>('words', 'both');
    final custom = parseDecryptoLines(setup.resourceLines('decrypto.words'));
    var pool = <String>[];
    if (src != 'custom') pool.addAll(decryptoWords);
    if (src != 'builtin') {
      for (final w in custom) {
        if (!pool.contains(w)) pool.add(w);
      }
    }
    if (pool.length < 8) {
      host.log('服务器自定义词库不足（words/decrypto.txt，每行一个词），已改用内置词库');
      pool = List.of(decryptoWords);
    }
    final pick = shuffled(pool, rng);
    words = [pick.sublist(0, 4), pick.sublist(4, 8)];
    host.log('截码战开始！红队：${members[0].map(name).join('、')}；蓝队：${members[1].map(name).join('、')}。');
    _beginRound();
  }

  static final List<List<int>> allCodes = [
    for (var a = 1; a <= 4; a++)
      for (var b = 1; b <= 4; b++)
        for (var c = 1; c <= 4; c++)
          if (a != b && b != c && a != c) [a, b, c],
  ];

  void _beginRound() {
    phase = 'clue';
    code = [for (var t = 0; t < 2; t++) List.of(allCodes[rng.nextInt(allCodes.length)])];
    clues = [null, null];
    own = [null, null];
    icpt = [null, null];
    host.log('第 $round 轮：红队 ${name(encryptor(0))}、蓝队 ${name(encryptor(1))} 担任加密者');
  }

  static const teamNames = ['红队', '蓝队'];

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'clue':
        return [for (var t = 0; t < 2; t++) if (clues[t] == null) encryptor(t)];
      case 'guess':
        return [
          for (var t = 0; t < 2; t++)
            if (own[t] == null || (round >= 2 && icpt[t] == null)) lead(t),
        ];
      case 'tiebreak':
        return [for (var t = 0; t < 2; t++) if (tbGuess[t] == null) lead(t)];
      default:
        return const [];
    }
  }

  static List<int> parseCode(Object? raw) {
    final c = asIntList(raw);
    if (c.length != 3 || c.any((d) => d < 1 || d > 4) || c.toSet().length != 3) {
      throw GameError('密码必须是 3 个互不相同的 1~4 数字');
    }
    return c;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final t = teamOf(seat);
    if (t < 0) throw GameError('观众不能操作');
    switch (asStr(a['type'])) {
      case 'clue':
        if (phase != 'clue') throw GameError('现在不是给线索的阶段');
        if (seat != encryptor(t)) throw GameError('只有本轮加密者可以给线索');
        if (clues[t] != null) throw GameError('你已经给过线索了');
        final raw = a['clues'];
        if (raw is! List || raw.length != 3) throw GameError('请给出 3 条线索');
        final cs = [for (final c in raw) sanitizeText(asStr(c)).trim()];
        for (var i = 0; i < 3; i++) {
          if (cs[i].isEmpty) throw GameError('线索不能为空');
          if (cs[i].length > kDecClueMax) throw GameError('每条线索最多 $kDecClueMax 个字');
          if (words[t].contains(cs[i])) throw GameError('线索不能直接说出关键词');
        }
        clues[t] = cs;
        host.log('${teamNames[t]}加密者 ${name(seat)} 已给出线索');
        if (clues.every((c) => c != null)) {
          phase = 'guess';
          host.log('红队线索：${clues[0]!.join(' / ')}；蓝队线索：${clues[1]!.join(' / ')}');
        }
      case 'guess':
        if (phase != 'guess') throw GameError('现在不能猜密码');
        if (seat == encryptor(t)) throw GameError('加密者不能参与本队猜码');
        if (own[t] != null) throw GameError('本队已提交猜测');
        own[t] = parseCode(a['code']);
        host.log('${teamNames[t]} 提交了本队密码猜测');
        _maybeResolve();
      case 'intercept':
        if (phase != 'guess') throw GameError('现在不能拦截');
        if (round < 2) throw GameError('第 2 轮起才能拦截');
        if (seat == encryptor(t)) throw GameError('加密者请等待队友决定');
        if (icpt[t] != null) throw GameError('本队已提交拦截');
        icpt[t] = parseCode(a['code']);
        host.log('${teamNames[t]} 提交了拦截猜测');
        _maybeResolve();
      case 'tiebreak':
        if (phase != 'tiebreak') throw GameError('现在不是决胜阶段');
        if (tbGuess[t] != null) throw GameError('本队已提交');
        final raw = a['words'];
        if (raw is! List || raw.length != 4) throw GameError('请猜出对方的 4 个关键词');
        final ws = [for (final w in raw) sanitizeText(asStr(w)).replaceAll(RegExp(r'\s+'), '')];
        if (ws.any((w) => w.length > kDecClueMax)) throw GameError('每个词最多 $kDecClueMax 个字');
        tbGuess[t] = ws;
        host.log('${teamNames[t]} 提交了关键词猜测');
        if (tbGuess.every((g) => g != null)) _resolveTiebreak();
      default:
        throw GameError('未知操作');
    }
  }

  void _maybeResolve() {
    if (own.any((g) => g == null)) return;
    if (round >= 2 && icpt.any((g) => g == null)) return;
    final res = <Map<String, dynamic>>[];
    for (var t = 0; t < 2; t++) {
      final ok = _eq(own[t]!, code[t]);
      final opp = icpt[1 - t];
      final caught = opp != null && _eq(opp, code[t]);
      if (!ok) miss[t]++;
      if (caught) ints[1 - t]++;
      final h = {'r': round, 't': t, 'clues': clues[t], 'code': code[t], 'guess': own[t], 'icpt': opp, 'ok': ok, 'caught': caught};
      history.add(h);
      res.add(h);
      host.log('${teamNames[t]}密码 ${code[t].join()}：${ok ? '队友猜对' : '队友猜错（失误+1）'}'
          '${opp == null ? '' : caught ? '，被${teamNames[1 - t]}拦截！' : '，拦截失败'}');
    }
    lastResult = {'round': round, 'teams': res};
    final st = [for (var t = 0; t < 2; t++) (ints[t] >= 2 ? 1 : 0) - (miss[t] >= 2 ? 1 : 0)];
    if (st[0] != st[1]) {
      final w = st[0] > st[1] ? 0 : 1;
      _end(w, ints[w] >= 2 ? '${teamNames[w]}成功拦截 2 次' : '${teamNames[1 - w]}失误 2 次');
      return;
    }
    if (st[0] != 0 || round >= maxRounds) {
      final sc = [for (var t = 0; t < 2; t++) ints[t] - miss[t]];
      if (sc[0] != sc[1]) {
        final w = sc[0] > sc[1] ? 0 : 1;
        _end(w, '按分数（拦截−失误）${sc[0]} : ${sc[1]} 判定');
        return;
      }
      phase = 'tiebreak';
      tbGuess = [null, null];
      host.log('比分相同，进入决胜：各队猜出对方的 4 个关键词！');
      return;
    }
    phase = 'result';
    final r = round;
    host.schedule(resultMs, () {
      if (phase == 'result' && round == r) {
        round++;
        _beginRound();
      }
    });
  }

  void _resolveTiebreak() {
    for (var t = 0; t < 2; t++) {
      var n = 0;
      for (var i = 0; i < 4; i++) {
        if (tbGuess[t]![i] == words[1 - t][i]) n++;
      }
      tbScore[t] = n;
    }
    if (tbScore[0] == tbScore[1]) {
      _end(-1, '决胜猜词 ${tbScore[0]} : ${tbScore[1]}，平局');
    } else {
      final w = tbScore[0] > tbScore[1] ? 0 : 1;
      _end(w, '决胜猜词 ${tbScore[0]} : ${tbScore[1]}');
    }
  }

  void _end(int w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    host.log(w < 0 ? '游戏结束：$why' : '${teamNames[w]}获胜！（$why）');
    host.log('红队关键词：${words[0].join('、')}；蓝队关键词：${words[1].join('、')}');
  }

  static bool _eq(List<int> a, List<int> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  // ------------------------------------------------------------ view

  @override
  Map<String, dynamic> view(int seat) {
    final t = teamOf(seat);
    final over = isOver;
    final isEnc = t >= 0 && seat == encryptor(t) && (phase == 'clue' || phase == 'guess');
    return {
      'phase': phase,
      'round': round,
      'maxRounds': maxRounds,
      'team': t,
      'teams': members,
      'encryptor': [encryptor(0), encryptor(1)],
      'lead': [lead(0), lead(1)],
      'keywords': over ? words : [for (var i = 0; i < 2; i++) i == t ? words[i] : null],
      'myCode': isEnc ? code[t] : null,
      'clues': [
        for (var i = 0; i < 2; i++)
          (phase != 'clue' || (isEnc && i == t)) ? clues[i] : null,
      ],
      'clueDone': [for (final c in clues) c != null],
      'own': [for (var i = 0; i < 2; i++) i == t ? own[i] : null],
      'icpt': [for (var i = 0; i < 2; i++) i == t ? icpt[i] : null],
      'ownDone': [for (final g in own) g != null],
      'icptDone': [for (final g in icpt) g != null],
      'ints': ints,
      'miss': miss,
      'history': history,
      'lastResult': phase == 'result' ? lastResult : null,
      'tbGuess': [for (var i = 0; i < 2; i++) (over || i == t) ? tbGuess[i] : null],
      'tbDone': [for (final g in tbGuess) g != null],
      'tbScore': over ? tbScore : null,
      'winner': winner,
      'reason': reason,
      'final': over ? {'winner': winner, 'reason': reason} : null,
    };
  }

  // ------------------------------------------------------------ bots
  // Bots only use: their own team's keywords, the current code if they are
  // the encryptor, and the public clue history.

  static bool related(String a, String b) {
    if (a == b) return true;
    final ca = _catOf[a], cb = _catOf[b];
    if (ca != null && ca == cb) return true;
    String? fc(String x) => x.startsWith('首字：') && x.length > 3 ? x.substring(3, 4) : null;
    final fa = fc(a), fb = fc(b);
    if (fa != null && (fa == fb || b.startsWith(fa))) return true;
    if (fb != null && a.startsWith(fb)) return true;
    return false;
  }

  /// Public clues team [t] gave for keyword position p (1..4).
  List<List<String>> pastClues(int t) {
    final out = [<String>[], <String>[], <String>[], <String>[]];
    for (final h in history) {
      if (h['t'] != t) continue;
      final cs = h['clues'] as List<String>, cd = h['code'] as List<int>;
      for (var i = 0; i < 3; i++) {
        out[cd[i] - 1].add(cs[i]);
      }
    }
    return out;
  }

  List<int> _bestCode(List<String> cs, List<String>? keys, List<List<String>> past) {
    var best = <List<int>>[];
    var bestSc = -1;
    for (final c in allCodes) {
      var sc = 0;
      for (var i = 0; i < 3; i++) {
        final p = c[i] - 1;
        if (keys != null && related(cs[i], keys[p])) sc += 3;
        sc += past[p].where((x) => related(cs[i], x)).length;
      }
      if (sc > bestSc) {
        bestSc = sc;
        best = [c];
      } else if (sc == bestSc) {
        best.add(c);
      }
    }
    return List.of(best[rng.nextInt(best.length)]);
  }

  String _clueFor(int t, String kw) {
    final c = _catOf[kw];
    if (c == null) return '首字：${kw.substring(0, 1)}';
    final opts = [for (final w in decryptoWordLines[c]) if (!words[t].contains(w) && w != kw) w];
    return opts.isEmpty ? '首字：${kw.substring(0, 1)}' : opts[rng.nextInt(opts.length)];
  }

  // ------------------------------------------------------------ AI

  static const _sys = '你在玩桌游“截码战”（Decrypto）。每队有 4 个编号 1~4 的秘密关键词。'
      '每轮加密者拿到一个 3 位密码（1~4 中 3 个不同数字），按顺序为每个数字对应的关键词各给一条线索，'
      '让队友猜出密码，同时不能让对手（看不到关键词、只能看历史线索）轻易拦截。回答只输出要求的 JSON。';

  String _histText(int t, {required bool showWords}) {
    final past = pastClues(t);
    final b = StringBuffer();
    for (var p = 0; p < 4; p++) {
      final label = showWords ? '${p + 1} 号词「${words[t][p]}」' : '${p + 1} 号词';
      b.writeln('$label：历史线索 ${past[p].isEmpty ? '（无）' : past[p].join('、')}');
    }
    return b.toString().trimRight();
  }

  static List<int>? _aiCode(String? reply) {
    if (reply == null) return null;
    final j = AiText.json(reply);
    final raw = j?['code'];
    List<int>? c;
    if (raw is List) {
      c = [for (final x in raw) asInt(x)];
    } else if (raw is String || raw is int) {
      c = [for (final ch in '$raw'.replaceAll(RegExp(r'[^0-9]'), '').split('')) int.parse(ch)];
    }
    if (c == null || c.length != 3 || c.any((d) => d < 1 || d > 4) || c.toSet().length != 3) return null;
    return c;
  }

  /// Validates model clues for team [t] (3 short, distinct, never a keyword
  /// or containing one).
  List<String>? _aiClues(String? reply, int t) {
    if (reply == null) return null;
    final raw = AiText.json(reply)?['clues'];
    if (raw is! List || raw.length != 3) return null;
    final cs = <String>[];
    for (final c in raw) {
      if (c is! String) return null;
      final x = sanitizeText(c).replaceAll(RegExp(r'\s+'), '').trim();
      if (x.isEmpty || x.length > kDecClueMax) return null;
      if (words[t].any((w) => x.contains(w) || w.contains(x))) return null;
      if (cs.contains(x)) return null;
      cs.add(x);
    }
    return cs;
  }

  /// null = no AI answer (use heuristic); `[]` = still waiting.
  Map<String, dynamic>? _aiBot(int seat, int t) {
    final ai = setup.ai!;
    switch (phase) {
      case 'clue':
        final r = _ai.poll(ai, 'clue:$round:$t', () {
          final p = StringBuffer()
            ..writeln('你是加密者。你们队的关键词：${[for (var i = 0; i < 4; i++) '${i + 1}.${words[t][i]}'].join('  ')}')
            ..writeln('本轮密码：${code[t].join('-')}')
            ..writeln('你们队以往的线索（对手也都看得到）：')
            ..writeln(_histText(t, showWords: true))
            ..writeln('请按密码顺序给出 3 条线索，每条是一个词或短语（不超过 $kDecClueMax 字），不能包含关键词本身，'
                '要让队友联想到对应关键词，但尽量别和历史线索太相似以免被对手拦截。')
            ..write('只输出 JSON：{"clues":["线索1","线索2","线索3"]}');
          return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 120);
        });
        if (r.pending) return const {};
        final cs = _aiClues(r.text, t);
        return cs == null ? null : {'type': 'clue', 'clues': cs};
      case 'guess':
        final mineTurn = own[t] == null;
        final target = mineTurn ? t : 1 - t;
        final r = _ai.poll(ai, '${mineTurn ? 'own' : 'icpt'}:$round:$t', () {
          final p = StringBuffer();
          if (mineTurn) {
            p
              ..writeln('你在猜本队的密码。本队关键词：${[for (var i = 0; i < 4; i++) '${i + 1}.${words[t][i]}'].join('  ')}')
              ..writeln('本队以往线索：')
              ..writeln(_histText(t, showWords: false));
          } else {
            p
              ..writeln('你在拦截对手的密码。你看不到对手的关键词，只能根据对手以往每个编号的线索推断。')
              ..writeln('对手以往线索：')
              ..writeln(_histText(1 - t, showWords: false));
          }
          p
            ..writeln('本轮${mineTurn ? '本队' : '对手'}加密者给出的线索（按密码顺序）：${clues[target]!.join(' / ')}')
            ..write('请推断密码（3 个 1~4 不同数字）。只输出 JSON：{"code":[a,b,c]}');
          return AiRequest(system: _sys, prompt: p.toString(), maxTokens: 60);
        });
        if (r.pending) return const {};
        final c = _aiCode(r.text);
        return c == null ? null : {'type': mineTurn ? 'guess' : 'intercept', 'code': c};
      default:
        return null;
    }
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final t = teamOf(seat);
    if (t < 0 || !waitingFor.contains(seat)) return null;
    if (aiOn) {
      final a = _aiBot(seat, t);
      if (a != null) return a.isEmpty ? null : a;
    }
    switch (phase) {
      case 'clue':
        return {'type': 'clue', 'clues': [for (final d in code[t]) _clueFor(t, words[t][d - 1])]};
      case 'guess':
        if (own[t] == null) {
          // 简单: sometimes ignores the history and guesses from the keywords only
          if (botLevel == 0 && rng.nextInt(4) == 0) {
            return {'type': 'guess', 'code': List.of(allCodes[rng.nextInt(allCodes.length)])};
          }
          return {'type': 'guess', 'code': _bestCode(clues[t]!, words[t], pastClues(t))};
        }
        final randomPct = switch (botLevel) { 0 => 7, 2 => 0, _ => 3 };
        final guess = rng.nextInt(10) < randomPct
            ? List.of(allCodes[rng.nextInt(allCodes.length)])
            : _bestCode(clues[1 - t]!, null, pastClues(1 - t));
        return {'type': 'intercept', 'code': guess};
      case 'tiebreak':
        final past = pastClues(1 - t);
        return {
          'type': 'tiebreak',
          'words': [
            for (var p = 0; p < 4; p++) _tbGuess(past[p]),
          ],
        };
      default:
        return null;
    }
  }

  String _tbGuess(List<String> past) {
    for (final c in past) {
      final cat = _catOf[c];
      if (cat != null) {
        final opts = [for (final w in decryptoWordLines[cat]) if (!past.contains(w)) w];
        if (opts.isNotEmpty) return opts[rng.nextInt(opts.length)];
      }
    }
    return past.isEmpty ? '不知道' : past.first;
  }
}
