import '../../src/ai.dart';
import '../../src/engine.dart';
import 'feihua_data.dart';
import 'p3_turns.dart';
import 'p3_util.dart';

export 'feihua_data.dart' show kFeihuaKeys;

/// One poem line of the built-in list.
class PoemLine {
  final String text;
  final String author;
  final String title;
  final bool classic; // from 唐诗三百首 / 千家诗 / 宋词三百首 / 诗经 …
  const PoemLine(this.text, this.author, this.title, this.classic);
}

/// Poem line list with a keyword index (parsed once, lazily).
class FeihuaDict {
  final List<PoemLine> all;
  final Map<String, int> byText = {};
  final Map<String, List<int>> _byKey = {};
  FeihuaDict._(this.all) {
    for (var i = 0; i < all.length; i++) {
      byText.putIfAbsent(all[i].text, () => i);
    }
  }

  static final FeihuaDict instance = () {
    final out = <PoemLine>[];
    var i = 0;
    for (final raw in feihuaData.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final p = line.split('|');
      final idx = i++;
      if (p.length < 3 || p[0].isEmpty) continue;
      out.add(PoemLine(p[0], p[1], p[2], idx < kFeihuaClassicCount));
    }
    return FeihuaDict._(out);
  }();

  PoemLine? lookup(String t) {
    final i = byText[t];
    return i == null ? null : all[i];
  }

  List<int> withKey(String k) => _byKey[k] ??= [for (var i = 0; i < all.length; i++) if (all[i].text.contains(k)) i];
}

/// Keyword choices offered in the room options (all well covered by the list).
const List<String> kFeihuaOptionKeys = ['花', '月', '春', '风', '雪', '山', '水', '云', '雨', '酒', '夜', '秋', '江', '人'];

/// 飞花令.
class Feihualing extends P3LifeGame {
  Feihualing(super.setup);

  static const voteMs = 30000;

  final FeihuaDict dict = FeihuaDict.instance;
  late String key;
  late bool strict;
  final Set<String> used = {};
  final AiSlot _ai = AiSlot();
  int _move = 0;

  /// Loose mode: an unlisted line awaiting votes.
  Map<String, dynamic>? pending; // {'s','t'}
  final Map<int, bool> votes = {};

  @override
  int get botDelayMs => 1400;

  @override
  void start() {
    startLives();
    strict = setup.opt<String>('check', 'strict') == 'strict';
    final k = setup.opt<String>('key', 'random');
    key = kFeihuaKeys.contains(k) ? k : kFeihuaOptionKeys[rng.nextInt(kFeihuaOptionKeys.length)];
    host.log('飞花令开始！令字「$key」：轮流说出含「$key」字的古诗词句，不能重复。'
        '${strict ? '（严格模式：须在诗词库中）' : '（宽松模式：库中没有的句子由其他人投票认可）'}');
    beginTurn();
  }

  List<int> get voters => pending == null ? const [] : [for (final s in aliveSeats) if (s != pending!['s']) s];

  /// Parse an answer: returns (line to record, listed poem or null) or throws.
  (String, PoemLine?) parseAnswer(String raw) {
    final segs = [for (final s in p3Segments(raw)) p3Norm(s)]..removeWhere((s) => s.isEmpty);
    if (segs.isEmpty) throw GameError('请输入诗句');
    for (final s in segs) {
      if (!isHan(s)) throw GameError('诗句只能由汉字组成');
    }
    final withKey = [for (final s in segs) if (s.contains(key)) s];
    if (withKey.isEmpty) throw GameError('句子里没有令字「$key」');
    for (final s in withKey) {
      final p = dict.lookup(s);
      if (p != null && !used.contains(s)) return (s, p);
    }
    final s = withKey.first;
    if (used.contains(s)) throw GameError('「$s」已经有人说过了');
    if (s.runes.length < 4 || s.runes.length > 12) throw GameError('一句诗应为 4~12 个字');
    if (strict) throw GameError('「$s」不在诗词库里（严格模式）');
    return (s, null);
  }

  @override
  List<int> get waitingFor {
    if (isOver) return const [];
    if (phase == 'play') return [turn];
    if (phase == 'vote') return [for (final s in voters) if (!votes.containsKey(s)) s];
    return const [];
  }

  void _accept(int seat, String line, PoemLine? p, {bool voted = false}) {
    used.add(line);
    _move++;
    host.log('${name(seat)}：「$line」${p != null ? '——${p.author}《${p.title}》' : (voted ? '（投票通过）' : '')}');
    succeed(seat, {'t': line, if (p != null) 'a': p.author, if (p != null) 'ti': p.title, 'voted': voted});
  }

  void _closeVote() {
    final p = pending;
    if (p == null) return;
    timers.cancel();
    final vs = voters;
    final yes = vs.where((s) => votes[s] ?? true).length; // silent = accept
    final ok = yes * 2 >= vs.length;
    pending = null;
    votes.clear();
    final s = p['s'] as int;
    final t = p['t'] as String;
    phase = 'play';
    if (ok) {
      _accept(s, t, null, voted: true);
    } else {
      used.add(t); // a rejected line can't be tried again
      _move++;
      fail(s, '的「$t」未获认可');
    }
  }

  @override
  void onResign(int seat) {
    if (phase != 'vote') return;
    if (pending?['s'] == seat) {
      pending = null;
      votes.clear();
      phase = 'play';
    } else {
      votes.remove(seat);
      if (voters.every(votes.containsKey)) {
        // resolved on the next tick of the loop below
        host.schedule(0, _closeVote);
      }
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    guardPlayer(seat);
    switch (asStr(a['type'])) {
      case 'answer':
        if (phase != 'play' || seat != turn) throw GameError('还没轮到你');
        final (line, p) = parseAnswer(asStr(a['text']));
        if (p != null) {
          _accept(seat, line, p);
        } else {
          timers.cancel();
          pending = {'s': seat, 't': line};
          votes.clear();
          phase = 'vote';
          host.log('${name(seat)}：「$line」不在诗词库中，请其他玩家投票是否认可');
          armTimer(_closeVote);
        }
      case 'pass':
        if (phase != 'play' || seat != turn) throw GameError('还没轮到你');
        _move++;
        fail(seat, '放弃');
      case 'vote':
        if (phase != 'vote') throw GameError('现在没有需要投票的句子');
        if (!voters.contains(seat)) throw GameError('你不能给自己投票');
        if (votes.containsKey(seat)) throw GameError('你已经投过了');
        votes[seat] = asBool(a['ok']);
        if (voters.every(votes.containsKey)) _closeVote();
      default:
        throw GameError('未知操作');
    }
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...baseView(),
        'key': key,
        'check': strict ? 'strict' : 'loose',
        'pending': pending,
        'voters': voters,
        'voted': votes.keys.toList(),
        'usedCount': used.length,
        'available': dict.withKey(key).length,
      };

  // ------------------------------------------------------------ bots

  static const _system = '你在玩飞花令：轮流说出一句含有指定“令字”的中国古典诗词原句（一句，不是整首）。'
      '必须是真实存在的古诗词原文，不能自己编，不能重复已说过的句子。只输出这一句诗，不要标点、作者或解释。';

  String? _aiLine(int seat) {
    final r = _ai.poll(setup.ai!, 'fh:$_move:$seat', () {
      final recent = [for (final h in history.reversed) if (h['t'] != null) h['t'] as String].take(15).toList();
      return AiRequest(
        system: _system,
        prompt: '令字：「$key」\n已经说过：${recent.isEmpty ? '（无）' : recent.join('、')}\n请说一句含「$key」的诗句。',
        maxTokens: 40,
      );
    });
    if (r.pending) return '';
    final t = r.text;
    if (t == null) return null;
    final line = AiText.firstLine(t, maxLen: 40);
    for (final s in p3Segments(line)) {
      final n = p3Norm(s);
      if (!isHan(n) || !n.contains(key) || used.contains(n)) continue;
      if (dict.lookup(n) != null) return n;
      // loose mode may put an unlisted (plausible) line to the vote
      if (!strict && (n.length == 5 || n.length == 7)) return n;
    }
    return null;
  }

  Map<String, dynamic> _heuristicLine() {
    final idx = dict.withKey(key);
    final avail = [for (final i in idx) if (!used.contains(dict.all[i].text)) dict.all[i]];
    final classic = [for (final p in avail) if (p.classic) p];
    // how much of the anthology this bot "knows"
    final (pool, miss) = switch (botLevel) {
      0 => (classic.take(60).toList(), 22),
      2 => (classic.isNotEmpty ? classic : avail, 0),
      _ => (classic.take(160).toList(), 6),
    };
    if (pool.isEmpty || rng.nextInt(100) < miss) return {'type': 'pass'};
    return {'type': 'answer', 'text': pool[rng.nextInt(pool.length)].text};
  }

  bool? _aiVote(int seat, String t) {
    final r = _ai.poll(setup.ai!, 'fv:$_move:$seat', () => AiRequest(
          system: '你是飞花令的裁判。判断给出的句子是否是真实存在的中国古典诗词原句。只回答“是”或“否”。',
          prompt: '令字「$key」，句子：「$t」',
          maxTokens: 10,
        ));
    if (r.pending) return null;
    final a = r.text == null ? '' : AiText.firstLine(r.text!, maxLen: 4);
    if (a == '是') return true;
    if (a == '否') return false;
    return null;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver) return null;
    if (phase == 'play') {
      if (seat != turn) return null;
      if (aiOn) {
        final l = _aiLine(seat);
        if (l == '') return null;
        if (l != null) return {'type': 'answer', 'text': l};
      }
      return _heuristicLine();
    }
    if (phase == 'vote') {
      if (!voters.contains(seat) || votes.containsKey(seat)) return null;
      final t = pending!['t'] as String;
      if (aiOn) {
        final v = _aiVote(seat, t);
        if (v != null) return {'type': 'vote', 'ok': v};
      }
      // plausible shape: 5 or 7 characters (or 4 like 诗经)
      final ok = botLevel == 0 ? rng.nextBool() : const [4, 5, 7].contains(t.length);
      return {'type': 'vote', 'ok': ok};
    }
    return null;
  }
}
