import '../../src/ai.dart';
import '../../src/engine.dart';
import 'p3_util.dart';
import 'wavelength_pairs.dart';

/// Built-in spectrum pairs (≥ 300).
final List<(String, String)> wavelengthBank = parseWavelengthLines(wavelengthPairsData.split('\n'));

/// Server lines `左|右` (words/wavelength.txt).
List<(String, String)> parseWavelengthLines(List<String> lines) {
  final out = <(String, String)>[];
  final seen = <String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final p = line.split(RegExp(r'[|｜]'));
    if (p.length < 2) continue;
    final l = p3Clean(p[0], 12), r = p3Clean(p[1], 12);
    if (l.isEmpty || r.isEmpty || l == r || !seen.add('$l|$r')) continue;
    out.add((l, r));
  }
  return out;
}

/// Wavelength 频率猜心.
///
/// `clue` (psychic sees the hidden target 0..100 on the spectrum and gives a
/// clue) → `guess` (the guessing team each set a marker and lock it; the dial
/// is the average of the locked markers) → `counter` (team mode: the other
/// team votes 左/右 of the dial) → `result` → … → `over`.
class Wavelength extends GameEngine {
  Wavelength(super.setup);

  static const resultMs = 5000;
  static const maxClueLen = 20;
  static const maxSkips = 2;

  late bool team;
  late int goal; // team mode: points to win
  late int totalCards; // co-op mode: number of rounds
  late int timeSec;
  late List<(String, String)> pool;
  final Set<int> _usedPairs = {};

  String phase = 'clue';
  int round = 0;
  int psychic = 0;
  int activeTeam = 0; // team mode: team whose turn it is
  (String, String) pair = ('', '');
  int _pairIdx = 0;
  int target = 50;
  String clue = '';
  int skipsUsed = 0;
  int endsAt = 0;
  final Map<int, int> markers = {}; // guesser → marker position
  final Set<int> locked = {};
  final Map<int, String> counterVotes = {}; // opponent seat → 'left' / 'right'
  final List<int> teamScore = [0, 0];
  int coopScore = 0;
  final List<int> psychicTurns = [0, 0]; // team mode: psychic rotation index per team
  Map<String, dynamic>? lastResult;
  final List<Map<String, dynamic>> history = [];
  int? winnerTeam; // null + over = draw / co-op
  bool _over = false;
  final P3Timers _timers = P3Timers();
  final AiSlot _ai = AiSlot();

  int teamOf(int s) => team ? s % 2 : 0;
  List<int> members(int t) => [for (var s = 0; s < players; s++) if (teamOf(s) == t) s];
  List<int> get guessers => [for (final s in members(team ? activeTeam : 0)) if (s != psychic) s];
  List<int> get opponents => team ? members(1 - activeTeam) : const [];

  @override
  bool get isOver => _over;

  @override
  List<int>? get placings {
    if (!_over) return null;
    if (!team || winnerTeam == null) return List.filled(players, 1);
    return [for (var s = 0; s < players; s++) teamOf(s) == winnerTeam ? 1 : 2];
  }

  @override
  int get botDelayMs => 1200;

  @override
  void start() {
    team = setup.opt<String>('mode', 'coop') == 'team' && players >= 4;
    goal = setup.opt<int>('goal', 10);
    totalCards = setup.opt<int>('cards', 7);
    timeSec = setup.opt<int>('time', 0);
    final src = setup.opt<String>('words', 'both');
    final custom = parseWavelengthLines(setup.resourceLines('wavelength.pairs'));
    if (src == 'custom' && custom.length < 10) host.log('服务器自定义光谱（words/wavelength.txt）不足 10 条，已改用内置光谱');
    if (src == 'builtin' || (src == 'custom' && custom.length < 10)) {
      pool = List.of(wavelengthBank);
    } else if (src == 'custom') {
      pool = custom;
    } else {
      final known = {for (final p in wavelengthBank) '${p.$1}|${p.$2}'};
      pool = [...wavelengthBank, for (final p in custom) if (!known.contains('${p.$1}|${p.$2}')) p];
    }
    activeTeam = rng.nextInt(2);
    host.log(team
        ? '频率猜心（团队对抗）开始！先得 $goal 分的队伍获胜。${_teamName(0)}：${members(0).map(name).join('、')}；${_teamName(1)}：${members(1).map(name).join('、')}'
        : '频率猜心（合作）开始！共 $totalCards 轮，大家一起拿尽可能高的分数。');
    psychic = team ? members(activeTeam)[0] : rng.nextInt(players);
    _nextRound(first: true);
  }

  static String _teamName(int t) => t == 0 ? '红队' : '蓝队';

  void _drawPair() {
    if (_usedPairs.length >= pool.length) _usedPairs.clear();
    int i;
    do {
      i = rng.nextInt(pool.length);
    } while (_usedPairs.contains(i));
    _usedPairs.add(i);
    _pairIdx = i;
    pair = pool[i];
    target = rng.nextInt(101);
  }

  void _nextRound({bool first = false}) {
    _timers.cancel();
    if (!first) {
      if (team) {
        activeTeam = 1 - activeTeam;
        final m = members(activeTeam);
        psychicTurns[activeTeam]++;
        psychic = m[psychicTurns[activeTeam] % m.length];
      } else {
        psychic = (psychic + 1) % players;
      }
    }
    round++;
    _drawPair();
    clue = '';
    skipsUsed = 0;
    markers.clear();
    locked.clear();
    counterVotes.clear();
    phase = 'clue';
    _ai.clear();
    host.log('第 $round 轮：${name(psychic)} 是通灵者${team ? '（${_teamName(activeTeam)}）' : ''}，光谱「${pair.$1} ←→ ${pair.$2}」');
    _arm(() {
      if (phase == 'clue') {
        host.log('${name(psychic)} 超时未给线索，本轮作废');
        _score(timeout: true);
      }
    });
  }

  void _arm(void Function() fn) {
    if (timeSec <= 0) {
      endsAt = 0;
      return;
    }
    endsAt = p3Now() + timeSec * 1000;
    _timers.countdown(host, timeSec * 1000, fn);
  }

  int get dial {
    final vs = [for (final s in guessers) if (locked.contains(s)) markers[s] ?? 50];
    if (vs.isEmpty) return 50;
    return (vs.reduce((a, b) => a + b) / vs.length).round();
  }

  static int points(int dial, int target) {
    final d = (dial - target).abs();
    if (d <= 4) return 4;
    if (d <= 11) return 3;
    if (d <= 18) return 2;
    return 0;
  }

  void _toGuess() {
    phase = 'guess';
    host.log('${name(psychic)} 的线索：「$clue」');
    _arm(() {
      if (phase != 'guess') return;
      for (final s in guessers) {
        locked.add(s);
        markers.putIfAbsent(s, () => 50);
      }
      _afterGuess();
    });
  }

  void _afterGuess() {
    _timers.cancel();
    if (team) {
      phase = 'counter';
      host.log('${_teamName(activeTeam)} 把指针定在 $dial。${_teamName(1 - activeTeam)} 猜目标在左还是右');
      _arm(() {
        if (phase == 'counter') _score();
      });
    } else {
      _score();
    }
  }

  void _score({bool timeout = false}) {
    _timers.cancel();
    final d = dial;
    final pts = timeout ? 0 : points(d, target);
    String? side;
    var counterPt = 0;
    if (team && !timeout) {
      final l = counterVotes.values.where((v) => v == 'left').length;
      final r = counterVotes.values.where((v) => v == 'right').length;
      side = l > r ? 'left' : (r > l ? 'right' : null);
      final truth = target < d ? 'left' : (target > d ? 'right' : null);
      if (side != null && pts < 4 && side == truth) counterPt = 1;
    }
    if (team) {
      teamScore[activeTeam] += pts;
      teamScore[1 - activeTeam] += counterPt;
    } else {
      coopScore += pts;
    }
    lastResult = {
      'round': round,
      'left': pair.$1,
      'right': pair.$2,
      'clue': clue,
      'psychic': psychic,
      'target': target,
      'dial': timeout ? null : d,
      'points': pts,
      'team': team ? activeTeam : null,
      'side': side,
      'counterPt': counterPt,
      'timeout': timeout,
      'markers': {for (final e in markers.entries) '${e.key}': e.value},
    };
    history.add({'round': round, 'left': pair.$1, 'right': pair.$2, 'clue': clue, 'target': target, 'dial': timeout ? null : d, 'points': pts, 'team': team ? activeTeam : null, 'counterPt': counterPt});
    if (!timeout) {
      host.log('目标在 $target，指针 $d —— 得 $pts 分${counterPt > 0 ? '；${_teamName(1 - activeTeam)} 猜对方向 +1' : ''}');
    }
    phase = 'result';
    endsAt = p3Now() + resultMs;
    _timers.after(host, resultMs, _afterResult);
  }

  void _afterResult() {
    if (team) {
      final a = teamScore[0], b = teamScore[1];
      // finish only after both teams had the same number of turns
      final even = round % 2 == 0;
      if ((a >= goal || b >= goal) && (even || round >= 40)) {
        if (a != b) {
          _finish(a > b ? 0 : 1);
          return;
        }
      }
      if (round >= 40) {
        _finish(a == b ? null : (a > b ? 0 : 1));
        return;
      }
    } else if (round >= totalCards) {
      _finish(null);
      return;
    }
    _nextRound();
  }

  void _finish(int? w) {
    _timers.cancel();
    winnerTeam = w;
    _over = true;
    phase = 'over';
    endsAt = 0;
    host.log(team
        ? (w == null ? '游戏结束：平局 ${teamScore[0]} : ${teamScore[1]}' : '游戏结束：${_teamName(w)} 获胜！${teamScore[0]} : ${teamScore[1]}')
        : '游戏结束！合作得分 $coopScore / ${totalCards * 4} —— ${rating(coopScore, totalCards)}');
  }

  static String rating(int score, int cards) {
    final r = score / (cards * 4);
    if (r >= 0.85) return '心有灵犀！';
    if (r >= 0.65) return '默契十足';
    if (r >= 0.45) return '还不错';
    if (r >= 0.25) return '频率有点偏';
    return '完全不在一个频道…';
  }

  /// Error message for a psychic clue, or null.
  static String? clueError(String t) {
    final c = p3Norm(t);
    if (c.isEmpty) return '线索不能为空';
    if (c.runes.length > maxClueLen) return '线索最多 $maxClueLen 个字';
    if (RegExp(r'[0-9０-９%]').hasMatch(t) || t.contains('百分')) return '线索不能包含数字或百分比';
    return null;
  }

  // ------------------------------------------------------------ actions

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'clue':
        return [psychic];
      case 'guess':
        return [for (final s in guessers) if (!locked.contains(s)) s];
      case 'counter':
        return [for (final s in opponents) if (!counterVotes.containsKey(s)) s];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (_over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    switch (asStr(a['type'])) {
      case 'clue':
        if (phase != 'clue') throw GameError('现在不是给线索的时候');
        if (seat != psychic) throw GameError('只有通灵者可以给线索');
        final t = p3Clean(asStr(a['text']), 40);
        final err = clueError(t);
        if (err != null) throw GameError(err);
        clue = t;
        _toGuess();
      case 'skip':
        if (phase != 'clue') throw GameError('现在不能换题');
        if (seat != psychic) throw GameError('只有通灵者可以换题');
        if (skipsUsed >= maxSkips) throw GameError('本轮换题次数已用完');
        skipsUsed++;
        _drawPair();
        host.log('${name(seat)} 换了一条光谱：「${pair.$1} ←→ ${pair.$2}」');
      case 'dial':
      case 'lock':
        if (phase != 'guess') throw GameError('现在不能转动指针');
        if (!guessers.contains(seat)) throw GameError(seat == psychic ? '通灵者不能转动指针' : '现在不是你们队猜');
        if (locked.contains(seat)) throw GameError('你已经锁定了');
        final pos = asInt(a['pos'], -999);
        if (pos < 0 || pos > 100) throw GameError('位置必须在 0~100 之间');
        markers[seat] = pos;
        if (a['type'] == 'lock') {
          locked.add(seat);
          if (guessers.every(locked.contains)) _afterGuess();
        }
      case 'side':
        if (phase != 'counter') throw GameError('现在不能猜方向');
        if (!opponents.contains(seat)) throw GameError('只有对方队伍可以猜方向');
        if (counterVotes.containsKey(seat)) throw GameError('你已经投过了');
        final side = asStr(a['side']);
        if (side != 'left' && side != 'right') throw GameError('请选择左或右');
        counterVotes[seat] = side;
        if (opponents.every(counterVotes.containsKey)) _score();
      default:
        throw GameError('未知操作');
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final showTarget = phase == 'result' || phase == 'over' || (seat == psychic && phase != 'over');
    final showMarkers = phase != 'clue';
    return {
      'phase': phase,
      'mode': team ? 'team' : 'coop',
      'round': round,
      'totalCards': totalCards,
      'goal': goal,
      'psychic': psychic,
      'activeTeam': activeTeam,
      'teams': [for (var s = 0; s < players; s++) teamOf(s)],
      'guessers': guessers,
      'opponents': opponents,
      'left': pair.$1,
      'right': pair.$2,
      'target': showTarget ? target : null,
      'clue': clue.isEmpty ? null : clue,
      'skipsLeft': maxSkips - skipsUsed,
      'markers': showMarkers ? {for (final e in markers.entries) '${e.key}': e.value} : const <String, dynamic>{},
      'locked': locked.toList(),
      'dial': phase == 'guess' && locked.isEmpty ? null : dial,
      'votes': phase == 'counter' ? counterVotes.keys.toList() : [for (final e in counterVotes.entries) {'s': e.key, 'v': e.value}],
      'teamScore': teamScore,
      'coopScore': coopScore,
      'result': phase == 'result' || phase == 'over' ? lastResult : null,
      'history': history,
      'winnerTeam': winnerTeam,
      'rating': _over && !team ? rating(coopScore, totalCards) : null,
      'timeSec': timeSec,
      'endsAt': endsAt,
      'now': p3Now(),
    };
  }

  // ------------------------------------------------------------ bots

  static const _ladder = [
    (4, '极其'),
    (14, '非常'),
    (27, '比较'),
    (40, '稍微'),
  ];

  /// Rule-based clue for bots: a degree word + the nearer end.
  static String ladderClue(String left, String right, int t) {
    if (t >= 45 && t <= 55) return '不偏不倚的中间';
    final nearLeft = t < 50;
    final d = nearLeft ? t : 100 - t;
    final word = nearLeft ? left : right;
    for (final (lim, adv) in _ladder) {
      if (d <= lim) return '$adv$word';
    }
    return '稍微$word';
  }

  /// Inverse of [ladderClue]; null when the clue isn't in that form.
  static int? readLadder(String left, String right, String clue) {
    if (clue == '不偏不倚的中间') return 50;
    const centers = {'极其': 2, '非常': 9, '比较': 20, '稍微': 36};
    for (final e in centers.entries) {
      if (clue == '${e.key}$left') return e.value;
      if (clue == '${e.key}$right') return 100 - e.value;
    }
    return null;
  }

  /// Rough estimate from any clue: degree words + which end word it mentions.
  static int estimate(String left, String right, String clue) {
    final exact = readLadder(left, right, clue);
    if (exact != null) return exact;
    var side = 0; // -1 left, +1 right
    if (clue.contains(left) && !clue.contains(right)) side = -1;
    if (clue.contains(right) && !clue.contains(left)) side = 1;
    if (side == 0) return 50;
    var d = 30;
    if (RegExp('极|超|最|特别|无比|爆').hasMatch(clue)) d = 6;
    if (RegExp('很|非常|相当').hasMatch(clue)) d = 14;
    if (RegExp('有点|稍|略|偏').hasMatch(clue)) d = 36;
    return side < 0 ? d : 100 - d;
  }

  int _noisy(int v, int spread) => (v + (spread == 0 ? 0 : rng.nextInt(spread * 2 + 1) - spread)).clamp(0, 100);

  static const _psySystem = '你在玩桌游《频率猜心 Wavelength》，你是通灵者。一条光谱两端是两个相反的概念，'
      '0 表示完全是左端，100 表示完全是右端。你看到了秘密目标位置，要给出一个线索（一个事物、人物、词语或短语），'
      '让队友凭直觉把它放到光谱上接近目标的位置。线索不能包含数字或百分比。只输出线索本身（2~12 个字），不要解释。';

  static const _guessSystem = '你在玩桌游《频率猜心 Wavelength》。一条光谱两端是两个相反的概念（0=左端，100=右端），'
      '通灵者给了一个线索，请判断线索在光谱上的位置。只输出 JSON：{"pos": 0到100的整数}。';

  Map<String, dynamic>? _aiClue() {
    final r = _ai.poll(setup.ai!, 'clue:$round:$_pairIdx', () => AiRequest(
          system: _psySystem,
          prompt: '光谱：左端「${pair.$1}」←→ 右端「${pair.$2}」\n秘密目标位置：$target（0~100）\n请给出线索。',
          maxTokens: 60,
        ));
    if (r.pending) return const {'_pending': true};
    final t = r.text;
    if (t == null) return null;
    final c = AiText.firstLine(t, maxLen: 30);
    if (c.isEmpty || c.runes.length > 12 || c.startsWith('{') || clueError(c) != null) return null;
    if (RegExp(r'[a-zA-Z]{4,}').hasMatch(c)) return null;
    return {'type': 'clue', 'text': c};
  }

  int? _aiPos(int seat) {
    final r = _ai.poll(setup.ai!, 'pos:$round:$seat', () => AiRequest(
          system: _guessSystem,
          prompt: '光谱：左端「${pair.$1}」←→ 右端「${pair.$2}」\n线索：「$clue」\n它在哪个位置？',
          maxTokens: 40,
        ));
    if (r.pending) return -1;
    final t = r.text;
    if (t == null) return null;
    final j = AiText.json(t);
    final p = j?['pos'];
    if (p is! num || !p.isFinite) return null;
    final v = p.round();
    return v < 0 || v > 100 ? null : v;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'clue':
        if (seat != psychic) return null;
        if (aiOn) {
          final a = _aiClue();
          if (a != null && a['_pending'] == true) return null;
          if (a != null) return a;
        }
        // 简单 misreads the dial a little
        final t = botLevel == 0 ? _noisy(target, 8) : target;
        return {'type': 'clue', 'text': ladderClue(pair.$1, pair.$2, t)};
      case 'guess':
        if (!guessers.contains(seat) || locked.contains(seat)) return null;
        int? pos;
        if (aiOn) {
          final p = _aiPos(seat);
          if (p == -1) return null;
          pos = p;
        }
        pos ??= _noisy(estimate(pair.$1, pair.$2, clue), switch (botLevel) { 0 => 12, 2 => 2, _ => 6 });
        return {'type': 'lock', 'pos': pos};
      case 'counter':
        if (!opponents.contains(seat) || counterVotes.containsKey(seat)) return null;
        final est = estimate(pair.$1, pair.$2, clue);
        final d = dial;
        final side = botLevel == 0 || est == d ? (rng.nextBool() ? 'left' : 'right') : (est < d ? 'left' : 'right');
        return {'type': 'side', 'side': side};
      default:
        return null;
    }
  }
}
