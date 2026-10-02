import '../../src/ai.dart';
import '../../src/engine.dart';
import 'util.dart';

const onRoleNames = {
  'werewolf': '狼人',
  'minion': '爪牙',
  'seer': '预言家',
  'robber': '强盗',
  'troublemaker': '捣蛋鬼',
  'drunk': '酒鬼',
  'insomniac': '失眠者',
  'hunter': '猎人',
  'tanner': '皮匠',
  'villager': '村民',
};

/// Night wake-up order (roles not listed have no night action).
const onNightOrder = ['werewolf', 'minion', 'seer', 'robber', 'troublemaker', 'drunk', 'insomniac'];

/// Card priority lists per preset; a game with N players uses the first N+3.
const onPresets = {
  'standard': [
    'werewolf', 'werewolf', 'seer', 'robber', 'troublemaker', 'villager', 'drunk', //
    'insomniac', 'minion', 'hunter', 'tanner', 'villager', 'villager',
  ],
  'beginner': [
    'werewolf', 'werewolf', 'seer', 'robber', 'troublemaker', 'villager', 'villager', //
    'insomniac', 'hunter', 'villager', 'villager', 'minion', 'villager',
  ],
  'chaos': [
    'werewolf', 'werewolf', 'seer', 'robber', 'troublemaker', 'drunk', 'tanner', //
    'minion', 'insomniac', 'hunter', 'villager', 'villager', 'villager',
  ],
};

const onPresetNames = {'standard': '标准', 'beginner': '新手', 'chaos': '混乱'};

List<String> onenightDeck(String preset, int players) =>
    (onPresets[preset] ?? onPresets['standard']!).take(players + 3).toList();

bool onWolfTeam(String r) => r == 'werewolf' || r == 'minion';

String onSeat(int s) => '${s + 1}号';
String onCenter(int i) => '中间第${i + 1}张';

class OneNight extends GameEngine {
  OneNight(super.setup);

  /// Cards as dealt: indexes 0..players-1 are players, players..players+2 the center.
  late List<String> dealt;

  /// Current cards (after night swaps once resolved).
  late List<String> cards;
  String phase = 'night'; // night day vote over
  final Map<int, Map<String, dynamic>> nightAct = {};
  final Map<int, List<Map<String, dynamic>>> seen = {};
  final Map<int, List<String>> info = {};
  final Set<int> ready = {};
  final Map<int, int> votes = {};
  final clock = OnClock();
  final List<String> nightLog = [];
  List<int> deaths = [];
  List<int> hunterShots = [];
  List<bool> winners = [];
  List<String> winTeams = [];
  String reason = '';

  /// Day statements made through the engine (bots with AI; humans use chat/voice).
  final List<Map<String, dynamic>> talk = [];
  static const maxSay = 60;
  static const maxSaysPerSeat = 2;
  final AiSlot _ai = AiSlot();

  int get dayMs => setup.opt<int>('day', 5) * 60000;
  String get preset => setup.opt<String>('preset', 'standard');
  int get center0 => players;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings => isOver ? rankWinners(players, [for (var s = 0; s < players; s++) if (winners[s]) s]) : null;

  /// Night: nobody may talk. Day / vote: everyone hears everyone.
  @override
  Set<int>? voiceListeners(int seat) => phase == 'night' ? <int>{} : null;

  @override
  int get botDelayMs => 1200;

  List<int> get wolfSeats => [for (var s = 0; s < players; s++) if (dealt[s] == 'werewolf') s];
  bool get loneWolf => wolfSeats.length == 1;

  @override
  void start() {
    dealt = shuffled(onenightDeck(preset, players), rng);
    cards = List.of(dealt);
    for (var s = 0; s < players; s++) {
      seen[s] = [];
      info[s] = [];
    }
    host.log('一夜终极狼人开始！共 ${players + 3} 张身份牌（中间 3 张）。天黑请闭眼，请查看身份并完成夜间行动');
  }

  @override
  List<int> get waitingFor => switch (phase) {
        'night' => [for (var s = 0; s < players; s++) if (!nightAct.containsKey(s)) s],
        'day' => [for (var s = 0; s < players; s++) if (!ready.contains(s)) s],
        'vote' => [for (var s = 0; s < players; s++) if (!votes.containsKey(s)) s],
        _ => const [],
      };

  // ------------------------------------------------------------ actions

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    switch (phase) {
      case 'night':
        if (type != 'night') throw GameError('请完成夜间行动');
        if (nightAct.containsKey(seat)) throw GameError('你已经完成夜间行动');
        _night(seat, a);
        if (nightAct.length == players) _resolveNight();
        break;
      case 'day':
        if (type == 'say') {
          final t = onCleanText(a['text'], maxSay);
          if (t.isEmpty) throw GameError('发言不能为空');
          if (talk.where((e) => e['s'] == seat).length >= maxSaysPerSeat) throw GameError('发言次数已用完，请在聊天中继续讨论');
          talk.add({'s': seat, 't': t});
          host.log('${onSeat(seat)} ${name(seat)}：$t');
          break;
        }
        if (type != 'ready') throw GameError('讨论阶段只能选择“提前投票”');
        if (a['ready'] == false) {
          ready.remove(seat);
        } else {
          ready.add(seat);
        }
        if (ready.length == players) {
          host.log('全员同意提前投票');
          _startVote();
        }
        break;
      case 'vote':
        if (type != 'vote') throw GameError('请投票');
        if (votes.containsKey(seat)) throw GameError('你已经投过票');
        final t = asInt(a['target']);
        if (t < 0 || t >= players || t == seat) throw GameError('请选择另一名玩家');
        votes[seat] = t;
        if (votes.length == players) _resolveVote();
        break;
      default:
        throw GameError('请稍候');
    }
  }

  int _centerIdx(Object? v) {
    final i = asInt(v);
    if (i < 0 || i > 2) throw GameError('请选择中间的一张牌');
    return i;
  }

  int _other(int seat, Object? v) {
    final t = asInt(v);
    if (t < 0 || t >= players || t == seat) throw GameError('请选择另一名玩家');
    return t;
  }

  void _see(int seat, String kind, int idx, String role) =>
      seen[seat]!.add({'k': kind, 'i': idx, 'role': role});

  void _night(int seat, Map<String, dynamic> a) {
    final role = dealt[seat];
    final skip = a['skip'] == true;
    final rec = <String, dynamic>{'role': role};
    final my = info[seat]!;
    switch (role) {
      case 'werewolf':
        final mates = wolfSeats.where((s) => s != seat).toList();
        if (mates.isNotEmpty) {
          my.add('你的狼人同伴：${mates.map(onSeat).join('、')}');
          break;
        }
        my.add('你是唯一的狼人');
        if (skip || a['center'] == null) break;
        final c = _centerIdx(a['center']);
        rec['center'] = c;
        _see(seat, 'c', c, dealt[center0 + c]);
        my.add('你查看了${onCenter(c)}：${onRoleNames[dealt[center0 + c]]}');
        nightLog.add('独狼 ${onSeat(seat)} 查看了${onCenter(c)}（${onRoleNames[dealt[center0 + c]]}）');
        break;
      case 'minion':
        final w = wolfSeats;
        my.add(w.isEmpty ? '场上没有狼人（都在中间）' : '狼人是：${w.map(onSeat).join('、')}');
        break;
      case 'seer':
        if (skip) {
          my.add('你没有查验');
          break;
        }
        if (a['target'] != null) {
          final t = _other(seat, a['target']);
          rec['target'] = t;
          _see(seat, 'p', t, dealt[t]);
          my.add('你查验了 ${onSeat(t)}：${onRoleNames[dealt[t]]}');
          nightLog.add('预言家 ${onSeat(seat)} 查验了 ${onSeat(t)}（${onRoleNames[dealt[t]]}）');
        } else {
          final cs = asIntList(a['center']);
          if (cs.length != 2 || cs[0] == cs[1]) throw GameError('请选择一名玩家，或中间的两张牌');
          final c1 = _centerIdx(cs[0]), c2 = _centerIdx(cs[1]);
          rec['center'] = [c1, c2];
          for (final c in [c1, c2]) {
            _see(seat, 'c', c, dealt[center0 + c]);
          }
          my.add('你查看了${onCenter(c1)}：${onRoleNames[dealt[center0 + c1]]}，'
              '${onCenter(c2)}：${onRoleNames[dealt[center0 + c2]]}');
          nightLog.add('预言家 ${onSeat(seat)} 查看了${onCenter(c1)}和${onCenter(c2)}');
        }
        break;
      case 'robber':
        if (skip) {
          my.add('你没有抢夺');
          break;
        }
        final t = _other(seat, a['target']);
        rec['target'] = t;
        // Robber wakes before any swap, so the target still holds the dealt card.
        _see(seat, 'p', seat, dealt[t]);
        my.add('你与 ${onSeat(t)} 交换了身份，你现在是：${onRoleNames[dealt[t]]}');
        break;
      case 'troublemaker':
        if (skip) {
          my.add('你没有捣乱');
          break;
        }
        final ts = asIntList(a['targets']);
        if (ts.length != 2 || ts[0] == ts[1]) throw GameError('请选择另外两名玩家');
        final x = _other(seat, ts[0]), y = _other(seat, ts[1]);
        rec['targets'] = [x, y];
        my.add('你交换了 ${onSeat(x)} 与 ${onSeat(y)} 的身份');
        break;
      case 'drunk':
        final c = _centerIdx(a['center']);
        rec['center'] = c;
        my.add('你把自己的牌与${onCenter(c)}交换了（你不知道新身份）');
        break;
      default:
        break;
    }
    nightAct[seat] = rec;
  }

  void _resolveNight() {
    // Resolve in wake order. Werewolves / minion / seer only look.
    for (var s = 0; s < players; s++) {
      if (dealt[s] == 'minion') nightLog.add('爪牙 ${onSeat(s)} 看到了狼人');
    }
    if (wolfSeats.length > 1) nightLog.add('狼人 ${wolfSeats.map(onSeat).join('、')} 互相确认');
    for (final role in ['robber', 'troublemaker', 'drunk']) {
      for (var s = 0; s < players; s++) {
        if (dealt[s] != role) continue;
        final r = nightAct[s]!;
        switch (role) {
          case 'robber':
            if (r['target'] is! int) break;
            final t = r['target'] as int;
            final got = cards[t];
            cards[t] = cards[s];
            cards[s] = got;
            nightLog.add('强盗 ${onSeat(s)} 抢了 ${onSeat(t)}，变成${onRoleNames[got]}');
            break;
          case 'troublemaker':
            if (r['targets'] is! List) break;
            final x = (r['targets'] as List)[0] as int, y = (r['targets'] as List)[1] as int;
            final tmp = cards[x];
            cards[x] = cards[y];
            cards[y] = tmp;
            nightLog.add('捣蛋鬼 ${onSeat(s)} 交换了 ${onSeat(x)} 与 ${onSeat(y)}');
            break;
          case 'drunk':
            final c = r['center'] as int;
            final tmp = cards[s];
            cards[s] = cards[center0 + c];
            cards[center0 + c] = tmp;
            nightLog.add('酒鬼 ${onSeat(s)} 与${onCenter(c)}交换，变成${onRoleNames[cards[s]]}');
            break;
        }
      }
    }
    for (var s = 0; s < players; s++) {
      if (dealt[s] != 'insomniac') continue;
      _see(s, 'p', s, cards[s]);
      info[s]!.add('天亮前你睁眼查看：你现在是${onRoleNames[cards[s]]}');
      nightLog.add('失眠者 ${onSeat(s)} 醒来，自己现在是${onRoleNames[cards[s]]}');
    }
    phase = 'day';
    ready.clear();
    host.log('天亮了！讨论 ${dayMs ~/ 60000} 分钟后投票，全员点“提前投票”可立即开始');
    clock.start(host, dayMs, () {
      if (phase != 'day') return;
      host.log('讨论时间到，开始投票');
      _startVote();
    });
  }

  void _startVote() {
    clock.stop();
    phase = 'vote';
    votes.clear();
  }

  void _resolveVote() {
    final counts = List.filled(players, 0);
    for (final t in votes.values) {
      counts[t]++;
    }
    final mx = counts.reduce((a, b) => a > b ? a : b);
    final dead = <int>{};
    if (mx > 1) {
      for (var s = 0; s < players; s++) {
        if (counts[s] == mx) dead.add(s);
      }
    }
    // Hunter: whoever the dying hunter voted for dies too (chains).
    final queue = dead.toList();
    while (queue.isNotEmpty) {
      final d = queue.removeAt(0);
      if (cards[d] == 'hunter') {
        final t = votes[d]!;
        hunterShots.add(d);
        if (dead.add(t)) queue.add(t);
      }
    }
    deaths = dead.toList()..sort();
    final r = onenightOutcome(cards.sublist(0, players), deaths);
    winners = r.$1;
    winTeams = r.$2;
    reason = r.$3;
    phase = 'over';
    host.log('投票结果：${deaths.isEmpty ? '无人出局' : '${deaths.map(onSeat).join('、')} 出局'}。$reason');
  }

  // ------------------------------------------------------------ view

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final over = isOver;
    final myRole = me ? dealt[seat] : null;
    final knowsWolves = myRole == 'werewolf' || myRole == 'minion';
    return {
      'phase': phase,
      'preset': preset,
      'deck': [for (final r in onNightOrder.followedBy(['hunter', 'tanner', 'villager'])) ...dealt.where((d) => d == r)],
      'myCard': myRole,
      'wolves': knowsWolves || over ? wolfSeats : null,
      'lone': myRole == 'werewolf' ? loneWolf : false,
      // Only a count: per-seat completion timing could hint at roles.
      'nightCount': nightAct.length,
      'myActed': me && nightAct.containsKey(seat),
      'seen': me ? seen[seat] : const [],
      'info': me ? info[seat] : const [],
      'endsAt': phase == 'day' ? clock.endsAt : 0,
      'now': onNow(),
      'dayMin': dayMs ~/ 60000,
      'ready': [for (var s = 0; s < players; s++) ready.contains(s)],
      'voted': [for (var s = 0; s < players; s++) votes.containsKey(s)],
      'myVote': me ? votes[seat] : null,
      'votes': over ? [for (var s = 0; s < players; s++) votes[s] ?? -1] : null,
      'dealt': over ? dealt : null,
      'final': over ? cards : null,
      'deaths': over ? deaths : null,
      'hunterShots': over ? hunterShots : null,
      'winners': over ? winners : null,
      'winTeams': over ? winTeams : null,
      'reason': reason,
      'nightLog': over ? nightLog : null,
      'talk': talk,
    };
  }

  // ------------------------------------------------------------ bot

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'night':
        if (nightAct.containsKey(seat)) return null;
        final others = [for (var s = 0; s < players; s++) if (s != seat) s]..shuffle(rng);
        switch (dealt[seat]) {
          case 'werewolf':
            return loneWolf ? {'type': 'night', 'center': rng.nextInt(3)} : {'type': 'night'};
          case 'seer':
            if (rng.nextDouble() < 0.6) return {'type': 'night', 'target': others.first};
            final c = shuffled([0, 1, 2], rng);
            return {'type': 'night', 'center': [c[0], c[1]]};
          case 'robber':
            return {'type': 'night', 'target': others.first};
          case 'troublemaker':
            if (others.length < 2) return {'type': 'night', 'skip': true};
            return {'type': 'night', 'targets': [others[0], others[1]]};
          case 'drunk':
            return {'type': 'night', 'center': rng.nextInt(3)};
          default:
            return {'type': 'night'};
        }
      case 'day':
        if (ready.contains(seat)) return null;
        if (aiOn && !talk.any((e) => e['s'] == seat)) {
          final r = _ai.poll(setup.ai!, 'say:$seat', () => _speechRequest(seat));
          if (r.pending) return null;
          final t = r.text == null ? '' : onCleanText(AiText.firstLine(r.text!, maxLen: 400), 400);
          if (t.length >= 2 && t.runes.length <= maxSay && !t.contains('{')) return {'type': 'say', 'text': t};
        }
        return {'type': 'ready'};
      case 'vote':
        if (votes.containsKey(seat)) return null;
        if (aiOn) {
          final r = _ai.poll(setup.ai!, 'vote:$seat', () => AiRequest(
              system: _aiSystem,
              prompt: '${_aiContext(seat)}\n现在投票：选出你要投出的一名玩家（不能投自己）。只输出 JSON：{"target": 座位号(1~$players)}',
              maxTokens: 80));
          if (r.pending) return null;
          final j = r.text == null ? null : AiText.json(r.text!);
          final t = j == null ? -1 : asInt(j['target']) - 1;
          if (t >= 0 && t < players && t != seat) return {'type': 'vote', 'target': t};
        }
        // 简单: often votes at random
        if (botLevel == 0 && rng.nextBool()) {
          final o = [for (var s = 0; s < players; s++) if (s != seat) s];
          return {'type': 'vote', 'target': o[rng.nextInt(o.length)]};
        }
        return {'type': 'vote', 'target': _botVote(seat)};
    }
    return null;
  }

  static const _aiSystem = '你在玩“一夜终极狼人”。只有一个夜晚，身份牌可能在夜里被强盗、捣蛋鬼、酒鬼交换，'
      '所以每个人现在的身份不一定是开局看到的。白天讨论后同时投票：投出一名狼人则好人胜；没有狼人出局则狼人胜；'
      '皮匠被投出则皮匠胜。玩家用“N号”称呼。';

  /// Only [seat]'s own knowledge: its starting card, its night info and the
  /// public statements.
  String _aiContext(int seat) {
    final b = StringBuffer()
      ..writeln('你是 ${onSeat(seat)}，开局身份牌：${onRoleNames[dealt[seat]]}。共 $players 名玩家，'
          '本局的牌：${onenightDeck(preset, players).map((r) => onRoleNames[r]).join('、')}（其中 3 张在中间）。')
      ..writeln('你夜里得知的信息：${info[seat]!.isEmpty ? '无' : info[seat]!.join('；')}')
      ..writeln('白天大家的发言：');
    if (talk.isEmpty) b.writeln('（还没有人发言）');
    for (final e in talk) {
      b.writeln('${onSeat(e['s'] as int)}：${e['t']}');
    }
    return b.toString();
  }

  AiRequest _speechRequest(int seat) {
    final r = dealt[seat];
    final hint = switch (r) {
      'werewolf' || 'minion' => '你站在狼人阵营，要隐藏身份：可以谎称自己是村民或别的角色，但要合理，别和别人的说法明显冲突。',
      'tanner' => '你是皮匠，希望自己被投出去，可以故意表现得有点可疑，但别太明显。',
      _ => '你站在好人阵营（除非夜里身份被换了），请分享对找狼有用的信息，推理谁可能是狼人。',
    };
    return AiRequest(
        system: _aiSystem,
        prompt: '${_aiContext(seat)}\n$hint\n现在轮到你发言：用口语化的中文说 1~2 句话，不超过 $maxSay 个字。只输出发言内容。',
        maxTokens: 150);
  }

  /// Chooses a vote using only what [seat] legitimately knows.
  int _botVote(int seat) {
    final orig = dealt[seat];
    // Believed current card.
    var mine = orig;
    final friends = <int>{}; // seats believed to be on my side (not to be voted)
    final wolvesSeen = <int>{};
    for (final x in seen[seat]!) {
      if (x['k'] == 'p' && x['i'] == seat) mine = x['role'] as String; // robber/insomniac
      if (x['k'] == 'p' && x['i'] != seat && x['role'] == 'werewolf') wolvesSeen.add(x['i'] as int);
      if (x['k'] == 'p' && x['i'] != seat && x['role'] != 'werewolf') friends.add(x['i'] as int);
    }
    if (orig == 'robber') {
      final t = nightAct[seat]?['target'];
      if (t is int) {
        // The robbed player now holds the robber card.
        wolvesSeen.remove(t);
        if (mine != 'werewolf') friends.add(t);
      }
    }
    if (orig == 'drunk') mine = 'unknown';
    final others = [for (var s = 0; s < players; s++) if (s != seat) s]..shuffle(rng);
    if (mine == 'werewolf' || mine == 'minion') {
      final mates = orig == 'werewolf' || orig == 'minion' ? wolfSeats.toSet() : <int>{};
      final c = others.where((s) => !mates.contains(s) && !wolvesSeen.contains(s)).toList();
      return c.isNotEmpty ? c.first : others.first;
    }
    if (mine == 'tanner') return others.first;
    if (wolvesSeen.isNotEmpty) return wolvesSeen.first;
    final c = others.where((s) => !friends.contains(s)).toList();
    return c.isNotEmpty ? c.first : others.first;
  }
}

/// Pure win-condition resolution. [finalCards] are the players' final cards,
/// [deaths] the eliminated seats. Returns (winner flag per seat, winning team
/// keys among village/wolf/tanner, explanation).
(List<bool>, List<String>, String) onenightOutcome(List<String> finalCards, List<int> deaths) {
  final n = finalCards.length;
  final wolvesInPlay = finalCards.contains('werewolf');
  final minionInPlay = finalCards.contains('minion');
  final deadWolf = deaths.any((d) => finalCards[d] == 'werewolf');
  final tannerDead = deaths.any((d) => finalCards[d] == 'tanner');
  bool village, wolf;
  if (wolvesInPlay) {
    village = deadWolf;
    wolf = !deadWolf && !tannerDead;
  } else {
    // No wolves: village wins if nobody (or only the minion) dies.
    village = deaths.every((d) => finalCards[d] == 'minion');
    wolf = minionInPlay && !tannerDead && deaths.any((d) => finalCards[d] != 'minion');
  }
  final winners = [
    for (var s = 0; s < n; s++)
      switch (finalCards[s]) {
        'werewolf' || 'minion' => wolf,
        'tanner' => deaths.contains(s),
        _ => village,
      }
  ];
  final teams = [if (village) 'village', if (wolf) 'wolf', if (tannerDead) 'tanner'];
  final parts = <String>[];
  if (tannerDead) parts.add('皮匠被投出，皮匠获胜');
  if (wolvesInPlay) {
    parts.add(deadWolf ? '狼人被投出，好人阵营获胜' : (tannerDead ? '狼人阵营也无法获胜' : '没有狼人出局，狼人阵营获胜'));
  } else {
    if (village) {
      parts.add(deaths.isEmpty ? '场上没有狼人且无人出局，好人阵营获胜' : '场上没有狼人，只投出了爪牙，好人阵营获胜');
    } else {
      parts.add('场上没有狼人却有人出局，好人阵营失败');
      if (wolf) parts.add('爪牙获胜');
    }
  }
  return (winners, teams, parts.join('；'));
}
