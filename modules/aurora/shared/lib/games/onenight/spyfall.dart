import '../../src/ai.dart';
import '../../src/engine.dart';
import 'spyfall_data.dart';
import 'util.dart';

const _botQuestions = [
  '你平时多久来这里一次？',
  '你觉得这里最吵的时候是什么时候？',
  '来这里需要穿什么衣服？',
  '你在这里最常闻到什么味道？',
  '这里的人一般待多久？',
  '你会带小孩来这里吗？',
  '这里晚上开门吗？',
  '你在这里花钱多吗？',
  '说一件你在这里会用到的东西。',
  '你觉得这里安全吗？',
];

const _botAnswers = [
  '看情况吧，说不准。',
  '挺常见的，大家都懂。',
  '这个嘛……我不太好说。',
  '和平时差不多，没什么特别的。',
  '人多的时候会比较热闹。',
  '我觉得还行，挺习惯的。',
  '一般不会太久。',
  '这得看你是来干什么的。',
  '反正我挺喜欢这里的。',
  '有时候会有点紧张。',
];

/// 谁是间谍 (Spyfall). Phases: play (Q&A) · accuse (unanimous vote) · final
/// (time-out vote) · roundEnd · over.
class Spyfall extends GameEngine {
  Spyfall(super.setup);

  int get totalRounds => setup.opt<int>('rounds', 3);
  int get roundMs => setup.opt<int>('minutes', 8) * 60000;

  int round = 0;
  String phase = 'play';
  int spy = -1;
  String location = '';
  List<String> roles = [];
  late List<int> scores;
  final clock = OnClock();
  int pausedMs = 0;

  // Q&A
  int asker = 0;
  int answerer = -1; // -1: asker must ask
  int lastAsker = -1;
  String pendingQ = '';
  List<Map<String, dynamic>> feed = [];
  // accusation
  final Set<int> accusedBy = {}; // who used their accusation this round
  int accuser = -1;
  int accused = -1;
  Map<int, bool> accVotes = {};
  List<Map<String, dynamic>> accLog = [];
  // final vote
  Map<int, int> finalVotes = {};
  // round end
  Map<String, dynamic>? result;
  final Set<int> cont = {};
  final List<Map<String, dynamic>> history = [];

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 1500;

  @override
  void start() {
    scores = List.filled(players, 0);
    host.log('谁是间谍开始！共 $totalRounds 轮，每轮 ${roundMs ~/ 60000} 分钟');
    _newRound();
  }

  void _newRound() {
    round++;
    spy = rng.nextInt(players);
    location = spyfallLocationNames[rng.nextInt(spyfallLocationNames.length)];
    final pool = shuffled(spyfallLocations[location]!, rng);
    roles = [for (var s = 0; s < players; s++) s == spy ? '间谍' : pool[s % pool.length]];
    asker = rng.nextInt(players);
    answerer = -1;
    lastAsker = -1;
    pendingQ = '';
    feed = [];
    accusedBy.clear();
    accuser = -1;
    accused = -1;
    accVotes = {};
    accLog = [];
    finalVotes = {};
    result = null;
    cont.clear();
    phase = 'play';
    host.log('第 $round 轮开始，由 ${name(asker)} 先提问');
    _startClock(roundMs);
  }

  void _startClock(int ms) {
    clock.start(host, ms, () {
      if (phase != 'play') return;
      host.log('时间到！所有人投票指认间谍');
      finalVotes = {};
      phase = 'final';
    });
  }

  @override
  List<int> get waitingFor => switch (phase) {
        'play' => [answerer >= 0 ? answerer : asker],
        'accuse' => [for (var s = 0; s < players; s++) if (s != accused && !accVotes.containsKey(s)) s],
        'final' => [for (var s = 0; s < players; s++) if (!finalVotes.containsKey(s)) s],
        'roundEnd' => [for (var s = 0; s < players; s++) if (!cont.contains(s)) s],
        _ => const [],
      };

  int _seat(Object? v, int self) {
    final t = asInt(v);
    if (t < 0 || t >= players || t == self) throw GameError('请选择另一名玩家');
    return t;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    switch (phase) {
      case 'play':
        switch (type) {
          case 'ask':
            if (seat != asker || answerer >= 0) throw GameError('现在不是你提问');
            final t = _seat(a['target'], seat);
            if (t == lastAsker && players > 2) throw GameError('不能反问刚刚问你的人');
            final q = onCleanText(a['text'], 80);
            if (q.isEmpty) throw GameError('请输入问题');
            pendingQ = q;
            answerer = t;
            feed.add({'from': seat, 'to': t, 'q': q, 'a': ''});
            if (feed.length > 60) feed.removeAt(0);
            return;
          case 'answer':
            if (seat != answerer) throw GameError('现在不是你回答');
            final ans = onCleanText(a['text'], 80);
            if (ans.isEmpty) throw GameError('请输入回答');
            feed.last['a'] = ans;
            lastAsker = asker;
            asker = seat;
            answerer = -1;
            pendingQ = '';
            return;
          case 'accuse':
            if (accusedBy.contains(seat)) throw GameError('本轮你已经发起过指认');
            final t = _seat(a['target'], seat);
            accusedBy.add(seat);
            accuser = seat;
            accused = t;
            accVotes = {seat: true};
            pausedMs = clock.stop();
            phase = 'accuse';
            host.log('${name(seat)} 指认 ${name(t)} 是间谍！其他人请表决（需全票通过）');
            if (players == 2) _resolveAccuse();
            return;
          case 'guess':
            if (seat != spy) throw GameError('只有间谍可以猜地点');
            final loc = asStr(a['location']);
            if (!spyfallLocations.containsKey(loc)) throw GameError('未知的地点');
            clock.stop();
            final ok = loc == location;
            host.log('${name(seat)} 亮明间谍身份，猜测地点是「$loc」——${ok ? '猜对了！' : '猜错了！'}');
            _endRound(ok ? 'spyGuess' : 'spyWrong', guess: loc);
            return;
          default:
            throw GameError('未知操作');
        }
      case 'accuse':
        if (type != 'accuseVote') throw GameError('请对指认表决');
        if (seat == accused) throw GameError('被指认者不能表决');
        if (accVotes.containsKey(seat)) throw GameError('你已经表决过');
        accVotes[seat] = asBool(a['agree']);
        if (accVotes.length == players - 1) _resolveAccuse();
        return;
      case 'final':
        if (type != 'finalVote') throw GameError('请投票指认间谍');
        if (finalVotes.containsKey(seat)) throw GameError('你已经投过票');
        finalVotes[seat] = _seat(a['target'], seat);
        if (finalVotes.length == players) _resolveFinal();
        return;
      case 'roundEnd':
        if (type != 'continue') throw GameError('请点击继续');
        cont.add(seat);
        if (cont.length == players) {
          if (round >= totalRounds) {
            phase = 'over';
            final best = scores.reduce((a, b) => a > b ? a : b);
            host.log('游戏结束！最高分：${[for (var s = 0; s < players; s++) if (scores[s] == best) name(s)].join('、')}（$best 分）');
          } else {
            _newRound();
          }
        }
        return;
      default:
        throw GameError('请稍候');
    }
  }

  void _resolveAccuse() {
    final yes = accVotes.values.where((v) => v).length;
    final pass = yes == players - 1;
    accLog.add({'by': accuser, 'target': accused, 'yes': yes, 'pass': pass});
    if (pass) {
      final wasSpy = accused == spy;
      host.log('全票通过！${name(accused)} 翻开身份：${wasSpy ? '正是间谍！' : '不是间谍……'}');
      _endRound(wasSpy ? 'caught' : 'wrongAccuse', accuser: accuser);
      return;
    }
    host.log('指认未获全票通过（$yes/${players - 1}），游戏继续');
    accuser = -1;
    accused = -1;
    accVotes = {};
    phase = 'play';
    _startClock(pausedMs < 1000 ? 1000 : pausedMs);
  }

  void _resolveFinal() {
    final counts = List.filled(players, 0);
    for (final t in finalVotes.values) {
      counts[t]++;
    }
    final mx = counts.reduce((a, b) => a > b ? a : b);
    final tops = [for (var s = 0; s < players; s++) if (counts[s] == mx) s];
    if (tops.length != 1 || mx * 2 <= players - 1) {
      host.log('投票没有形成多数，间谍成功潜伏');
      _endRound('hidden');
      return;
    }
    final t = tops.first;
    accused = t;
    host.log('${name(t)} 被票出：${t == spy ? '正是间谍！' : '不是间谍……'}');
    _endRound(t == spy ? 'caughtFinal' : 'wrongAccuse');
  }

  void _endRound(String how, {int accuser = -1, String guess = ''}) {
    clock.stop();
    final gain = List.filled(players, 0);
    final spyWins = switch (how) { 'spyGuess' || 'wrongAccuse' || 'hidden' => true, _ => false };
    if (spyWins) {
      gain[spy] = how == 'hidden' ? 2 : 4;
    } else {
      for (var s = 0; s < players; s++) {
        if (s != spy) gain[s] = 1;
      }
      if (how == 'caught' && accuser >= 0) gain[accuser] = 2;
    }
    for (var s = 0; s < players; s++) {
      scores[s] += gain[s];
    }
    result = {
      'how': how,
      'spyWins': spyWins,
      'spy': spy,
      'location': location,
      'roles': roles,
      'guess': guess,
      'accused': accused,
      'gain': gain,
      'text': switch (how) {
        'spyGuess' => '间谍猜中地点「$location」，间谍获胜',
        'spyWrong' => '间谍猜错了（猜「$guess」，实际是「$location」），平民获胜',
        'caught' => '间谍被全票指认，平民获胜',
        'caughtFinal' => '时间到，间谍被票出，平民获胜',
        'wrongAccuse' => '冤枉了好人！间谍获胜',
        _ => '时间到，间谍成功潜伏',
      },
    };
    history.add({'round': round, 'spy': spy, 'location': location, 'spyWins': spyWins});
    cont.clear();
    phase = 'roundEnd';
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final reveal = phase == 'roundEnd' || phase == 'over';
    final isSpy = me && seat == spy;
    return {
      'phase': phase,
      'round': round,
      'totalRounds': totalRounds,
      'locations': spyfallLocationNames,
      'myRole': me ? roles[seat] : null,
      'amSpy': me ? isSpy : null,
      'location': (me && !isSpy) || reveal ? location : null,
      'scores': scores,
      'asker': asker,
      'answerer': answerer,
      'lastAsker': lastAsker,
      'pendingQ': pendingQ,
      'feed': feed,
      'endsAt': phase == 'play' ? clock.endsAt : 0,
      'pausedMs': phase == 'accuse' ? pausedMs : 0,
      'now': onNow(),
      'minutes': roundMs ~/ 60000,
      'accusedBy': [for (var s = 0; s < players; s++) accusedBy.contains(s)],
      'accuser': accuser,
      'accused': accused,
      'accVoted': [for (var s = 0; s < players; s++) accVotes.containsKey(s)],
      'myAccVote': me ? accVotes[seat] : null,
      'accLog': accLog,
      'finalVoted': [for (var s = 0; s < players; s++) finalVotes.containsKey(s)],
      'myFinalVote': me ? finalVotes[seat] : null,
      'finalVotes': reveal && finalVotes.isNotEmpty ? [for (var s = 0; s < players; s++) finalVotes[s] ?? -1] : null,
      'result': result,
      'cont': [for (var s = 0; s < players; s++) cont.contains(s)],
      'history': history,
    };
  }

  // ------------------------------------------------------------ bot

  /// Public text hints: count how often each location's name / roles appear
  /// in the Q&A feed (from all players). Used by the spy bot.
  String _spyGuess() {
    final text = feed.map((e) => '${e['q']} ${e['a']}').join(' ');
    var best = <String>[];
    var bestScore = 0;
    for (final e in spyfallLocations.entries) {
      var sc = text.contains(e.key) ? 3 : 0;
      for (final r in e.value) {
        if (text.contains(r)) sc++;
      }
      if (sc > bestScore) {
        bestScore = sc;
        best = [e.key];
      } else if (sc == bestScore) {
        best.add(e.key);
      }
    }
    return best[rng.nextInt(best.length)];
  }

  // ------------------------------------------------------------ AI

  final AiSlot _ai = AiSlot();
  static const Map<String, dynamic> _wait = {'_pending': true};

  static const _sys = '你在玩“谁是间谍”（Spyfall）。除了间谍，所有人都知道大家所在的地点，并各有一个身份。'
      '大家轮流互相提问、回答。平民要通过问答找出间谍，但问题和回答不能太直白，否则间谍会猜出地点；'
      '间谍不知道地点，要装作知道、含糊地回答，并从别人的问答中推断地点。玩家用名字称呼。回答要简短自然。';

  String _aiContext(int seat) {
    final b = StringBuffer();
    if (seat == spy) {
      b.writeln('你是间谍，你不知道地点。可能的地点：${spyfallLocationNames.join('、')}。');
    } else {
      b.writeln('地点是「$location」，你的身份是「${roles[seat]}」。');
    }
    b.writeln('玩家：${[for (var s = 0; s < players; s++) '${name(s)}${s == seat ? '（你）' : ''}'].join('、')}');
    b.writeln('目前的问答：');
    if (feed.isEmpty) b.writeln('（还没有）');
    for (final e in feed) {
      b.writeln('${name(e['from'] as int)} 问 ${name(e['to'] as int)}：${e['q']}${(e['a'] as String).isEmpty ? '' : ' —— 答：${e['a']}'}');
    }
    return b.toString();
  }

  /// Rejects a text that names the location outright (non-spy) or is junk.
  String? _aiLine(String? reply, {bool forbidLocation = true}) {
    if (reply == null) return null;
    final t = onCleanText(AiText.firstLine(reply, maxLen: 400), 400);
    if (t.length < 2 || t.runes.length > 60 || t.contains('{') || t.contains('}')) return null;
    if (forbidLocation && t.contains(location)) return null;
    return t;
  }

  Map<String, dynamic>? _aiAnswer(int seat) {
    final r = _ai.poll(setup.ai!, 'ans:$round:${feed.length}', () => AiRequest(
        system: _sys,
        prompt: '${_aiContext(seat)}\n${name(asker)} 问你：$pendingQ\n'
            '${seat == spy ? '你是间谍，请给一个模糊但听起来合理的回答，别暴露自己不知道地点。' : '请结合地点和身份回答，但不要说出地点名称，也别太直白。'}'
            '只输出你的回答（一句话，不超过 30 字）。',
        maxTokens: 80));
    if (r.pending) return _wait;
    final t = _aiLine(r.text, forbidLocation: seat != spy);
    return t == null ? null : {'type': 'answer', 'text': t};
  }

  Map<String, dynamic>? _aiAsk(int seat, List<int> targets) {
    final r = _ai.poll(setup.ai!, 'ask:$round:${feed.length}', () => AiRequest(
        system: _sys,
        prompt: '${_aiContext(seat)}\n轮到你提问。可以问的人：${[for (final t in targets) '$t=${name(t)}'].join('，')}。'
            '${seat == spy ? '你是间谍，问一个通用、不暴露自己的问题，最好能从回答中套出地点线索。' : '问一个能试探对方是否知道地点的问题，但不要泄露地点。'}'
            '只输出 JSON：{"target": 编号, "text": "你的问题（不超过 30 字）"}',
        maxTokens: 120));
    if (r.pending) return _wait;
    final j = r.text == null ? null : AiText.json(r.text!);
    if (j == null) return null;
    final t = asInt(j['target']);
    final q = j['text'] is String ? _aiLine(j['text'] as String, forbidLocation: seat != spy) : null;
    if (!targets.contains(t) || q == null) return null;
    return {'type': 'ask', 'target': t, 'text': q};
  }

  /// Spy's location guess from the Q&A (validated against the location list).
  String? aiSpyGuess() {
    final r = _ai.poll(setup.ai!, 'guess:$round:${feed.length}', () => AiRequest(
        system: _sys,
        prompt: '${_aiContext(spy)}\n根据以上问答推断最可能的地点。只输出 JSON：{"location": "地点名"}，地点必须来自可能的地点列表。',
        maxTokens: 60));
    if (r.pending) return '';
    return parseSpyLocation(r.text);
  }

  static String? parseSpyLocation(String? reply) {
    if (reply == null) return null;
    final j = AiText.json(reply);
    final v = j == null ? AiText.firstLine(reply) : j['location'];
    if (v is! String) return null;
    final t = v.trim();
    return spyfallLocations.containsKey(t) ? t : null;
  }

  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'play':
        if (answerer >= 0) {
          if (seat != answerer) return null;
          if (aiOn) {
            final a = _aiAnswer(seat);
            if (identical(a, _wait)) return null;
            if (a != null) return a;
          }
          return {'type': 'answer', 'text': _botAnswers[rng.nextInt(_botAnswers.length)]};
        }
        if (seat != asker) return null;
        final qn = feed.length;
        if (seat == spy && (qn >= 3 * players || (qn >= players && rng.nextDouble() < 0.12))) {
          if (aiOn) {
            final g = aiSpyGuess();
            if (g == '') return null;
            if (g != null) return {'type': 'guess', 'location': g};
          }
          return {'type': 'guess', 'location': _spyGuess()};
        }
        final accuseP = switch (botLevel) { 0 => 0.3, 2 => 0.1, _ => 0.2 };
        if (seat != spy && !accusedBy.contains(seat) && qn >= players && rng.nextDouble() < accuseP) {
          final others = [for (var s = 0; s < players; s++) if (s != seat) s];
          // 困难: accuse whoever answered with the most generic lines
          var target = others[rng.nextInt(others.length)];
          if (botLevel == 2) {
            final vague = {for (final s in others) s: feed.where((e) => e['to'] == s && _botAnswers.contains(e['a'])).length};
            others.sort((a, b) => vague[b]!.compareTo(vague[a]!));
            if (vague[others.first]! > 0) target = others.first;
          }
          return {'type': 'accuse', 'target': target};
        }
        final targets = [for (var s = 0; s < players; s++) if (s != seat && (s != lastAsker || players <= 2)) s];
        if (aiOn) {
          final a = _aiAsk(seat, targets);
          if (identical(a, _wait)) return null;
          if (a != null) return a;
        }
        return {
          'type': 'ask',
          'target': targets[rng.nextInt(targets.length)],
          'text': _botQuestions[rng.nextInt(_botQuestions.length)],
        };
      case 'accuse':
        if (seat == accused || accVotes.containsKey(seat)) return null;
        // The spy happily agrees to convict someone else; others are unsure.
        return {'type': 'accuseVote', 'agree': seat == spy || rng.nextDouble() < 0.55};
      case 'final':
        if (finalVotes.containsKey(seat)) return null;
        final others = [for (var s = 0; s < players; s++) if (s != seat) s];
        return {'type': 'finalVote', 'target': others[rng.nextInt(others.length)]};
      case 'roundEnd':
        return cont.contains(seat) ? null : {'type': 'continue'};
    }
    return null;
  }
}
