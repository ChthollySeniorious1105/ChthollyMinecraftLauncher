import '../../src/ai.dart';
import '../../src/engine.dart';
import 'chengyu_data.dart';
import 'p3_turns.dart';
import 'p3_util.dart';

/// One idiom of the built-in list.
class Chengyu {
  final String word;
  final String firstPy; // with tone digit, e.g. wu2
  final String lastPy;
  final bool common;
  const Chengyu(this.word, this.firstPy, this.lastPy, this.common);
  String get first => word.substring(0, 1);
  String get last => word.substring(word.length - 1);
}

/// Plain phrases that slipped into the source list (not 成语).
const Set<String> _notIdioms = {
  '摸金校尉', '万里长城', '心力衰竭', '下回分解', '十字路口', '必经之路', '年事已高', '大政方针', '有生力量',
  '既得利益', '增收节支', '发财致富', '十字街头', '天下第一', '有钱有势', '意料之外', '原来如此', '哭丧着脸',
};

String toneless(String py) => py.replaceAll(RegExp(r'[0-9]'), '');

/// The idiom dictionary with lookup indexes (parsed once, lazily).
class ChengyuDict {
  final List<Chengyu> all;
  final Map<String, int> byWord = {};
  final Map<String, List<int>> byFirst = {};
  final Map<String, List<int>> byFirstPy = {}; // toneless
  final List<int> common = [];
  ChengyuDict._(this.all) {
    for (var i = 0; i < all.length; i++) {
      final c = all[i];
      if (c.common) common.add(i);
      byWord[c.word] = i;
      (byFirst[c.first] ??= []).add(i);
      (byFirstPy[toneless(c.firstPy)] ??= []).add(i);
    }
  }

  static final ChengyuDict instance = () {
    final out = <Chengyu>[];
    var i = 0;
    for (final item in chengyuData.split(RegExp(r'\s+'))) {
      if (item.isEmpty) continue;
      final p = item.split('|');
      final idx = i++;
      if (p.length != 3 || _notIdioms.contains(p[0])) continue;
      out.add(Chengyu(p[0], p[1], p[2], idx < kChengyuCommonCount));
    }
    return ChengyuDict._(out);
  }();

  Chengyu? lookup(String w) {
    final i = byWord[w];
    return i == null ? null : all[i];
  }

  /// Indexes of idioms that may follow [prev].
  List<int> followers(Chengyu prev, bool sound) =>
      sound ? (byFirstPy[toneless(prev.lastPy)] ?? const []) : (byFirst[prev.last] ?? const []);

  static bool follows(Chengyu prev, Chengyu next, bool sound) =>
      sound ? toneless(prev.lastPy) == toneless(next.firstPy) : prev.last == next.first;
}

/// 成语接龙.
class ChengyuGame extends P3LifeGame {
  ChengyuGame(super.setup);

  final ChengyuDict dict = ChengyuDict.instance;
  late bool sound; // 同音 mode
  late Chengyu current;
  int chainLen = 0;
  final Set<String> used = {};
  final AiSlot _ai = AiSlot();
  int _move = 0;

  @override
  int get botDelayMs => 1400;

  @override
  void start() {
    startLives();
    sound = setup.opt<String>('match', 'char') == 'sound';
    _newChain();
    host.log('成语接龙开始！下一个成语的首字要${sound ? '与上一个的尾字同音（不计声调）' : '与上一个成语的尾字相同'}。'
        '每人 $maxLives 条命，放弃或超时失去 1 条命。');
    beginTurn();
  }

  int _unusedFollowers(Chengyu c, {bool commonOnly = false}) =>
      dict.followers(c, sound).where((i) => !used.contains(dict.all[i].word) && (!commonOnly || dict.all[i].common)).length;

  void _newChain() {
    Chengyu c;
    var tries = 0;
    do {
      c = dict.all[dict.common[rng.nextInt(dict.common.length)]];
      tries++;
    } while ((used.contains(c.word) || _unusedFollowers(c, commonOnly: true) < 3) && tries < 500);
    current = c;
    used.add(c.word);
    chainLen = 0;
    history.add({'s': -1, 'k': 'start', 'w': c.word, 'py': c.lastPy});
    host.log('新的接龙：「${c.word}」，请接「${_need(c)}」');
  }

  String _need(Chengyu c) => sound ? '${c.last}（${toneless(c.lastPy)}）' : c.last;

  @override
  void onFail(int seat) {
    if (!isOver) _newChain();
  }

  /// Why [w] can't follow now, or null if it's fine.
  String? answerError(String w) {
    if (w.isEmpty) return '请输入成语';
    if (!isHan(w)) return '成语只能由汉字组成';
    if (w.runes.length != 4) return '请输入四字成语';
    final c = dict.lookup(w);
    if (c == null) return '「$w」不在成语词库里';
    if (used.contains(w)) return '「$w」已经用过了';
    if (!ChengyuDict.follows(current, c, sound)) {
      return sound ? '首字读音要是 ${toneless(current.lastPy)}（接「${current.last}」）' : '首字要是「${current.last}」';
    }
    return null;
  }

  @override
  List<int> get waitingFor => isOver || phase != 'play' ? const [] : [turn];

  @override
  void handle(int seat, Map<String, dynamic> a) {
    guardPlayer(seat);
    if (seat != turn || phase != 'play') throw GameError('还没轮到你');
    switch (asStr(a['type'])) {
      case 'answer':
        final w = p3Norm(asStr(a['text']));
        final err = answerError(w);
        if (err != null) throw GameError(err);
        final c = dict.lookup(w)!;
        used.add(w);
        final prev = current;
        current = c;
        chainLen++;
        _move++;
        final dead = _unusedFollowers(c) == 0;
        host.log('${name(seat)}：「$w」${dead ? '——接死了！无人能接，+1 奖励分' : ''}');
        succeed(seat, {'w': w, 'py': c.lastPy, 'prev': prev.word, 'dead': dead}, points: dead ? 2 : 1);
        if (dead && !isOver) _newChain();
      case 'pass':
        _move++;
        fail(seat, '放弃');
      default:
        throw GameError('未知操作');
    }
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...baseView(),
        'match': sound ? 'sound' : 'char',
        'current': current.word,
        'lastChar': current.last,
        'lastPy': current.lastPy,
        'need': _need(current),
        'chain': chainLen,
        'usedCount': used.length,
        'dictSize': dict.all.length,
      };

  // ------------------------------------------------------------ bots

  static const _system = '你在玩成语接龙。请接一个四字成语：它的第一个字必须和上一个成语的最后一个字相同'
      '（同音模式下读音相同即可，不计声调）。必须是真实存在、常见的成语，不能重复已用过的。只输出这个成语，不要解释。';

  String? _aiAnswer(int seat) {
    final r = _ai.poll(setup.ai!, 'cy:$_move:$seat', () {
      final recent = [for (final h in history.reversed) if (h['w'] != null) h['w'] as String].take(12).toList();
      return AiRequest(
        system: _system,
        prompt: '上一个成语：「${current.word}」，最后一个字「${current.last}」读 ${current.lastPy}。\n'
            '${sound ? '同音模式：首字读 ${toneless(current.lastPy)} 即可。' : '同字模式：首字必须是「${current.last}」。'}\n'
            '最近用过的：${recent.join('、')}\n请接龙。',
        maxTokens: 30,
      );
    });
    if (r.pending) return '';
    final t = r.text;
    if (t == null) return null;
    final line = AiText.firstLine(t, maxLen: 20);
    // accept a bare idiom or one embedded in a short sentence
    for (final m in RegExp(r'[一-鿿]{4}').allMatches(line)) {
      final w = m.group(0)!;
      if (answerError(w) == null) return w;
    }
    return null;
  }

  Map<String, dynamic> _heuristic() {
    final cands = [for (final i in dict.followers(current, sound)) if (!used.contains(dict.all[i].word)) dict.all[i]];
    final common = [for (final c in cands) if (c.common) c];
    switch (botLevel) {
      case 0:
        // 简单: only knows common idioms and blanks out now and then
        if (common.isEmpty || rng.nextInt(100) < 18) return {'type': 'pass'};
        return {'type': 'answer', 'text': common[rng.nextInt(common.length)].word};
      case 2:
        if (cands.isEmpty) return {'type': 'pass'};
        // 困难: 接死 if possible, else leave the next player as few options as possible
        Chengyu? best;
        var bestN = 1 << 30;
        for (final c in cands) {
          final n = _unusedFollowers(c);
          final k = n == 0 ? -1 : n;
          if (k < bestN || (k == bestN && rng.nextBool())) {
            bestN = k;
            best = c;
          }
        }
        return {'type': 'answer', 'text': best!.word};
      default:
        final pool = common.isNotEmpty ? common : cands;
        if (pool.isEmpty || (common.isEmpty && rng.nextInt(100) < 40)) return {'type': 'pass'};
        return {'type': 'answer', 'text': pool[rng.nextInt(pool.length)].word};
    }
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver || phase != 'play' || seat != turn) return null;
    if (aiOn) {
      final w = _aiAnswer(seat);
      if (w == '') return null; // pending
      if (w != null) return {'type': 'answer', 'text': w};
    }
    return _heuristic();
  }
}
