import '../../src/engine.dart';
import 'cards.dart';
import 'sets.dart';
import 'trick.dart';

/// 够级（山东）：6 人 3v3 隔位组队，四副牌（216 张）每人 36 张。
/// 只出同点数的牌（单张、对子、三张…），王可挂作任意点数；跟牌须同张数、点数更大。
/// 够级牌只有对头能管，其他对手要管须“烧牌”（挂王）。见 [goujiRules]。
class Gouji extends C4Trick {
  Gouji(super.setup);

  static const placeNames = ['头科', '二科', '三科', '四科', '二落', '大落'];
  static const placePts = [2, 1, 0, 0, -1, -2];

  late int rounds;
  late bool tributeOn;
  int round = 0;
  List<int> teamScores = [0, 0];
  String phase = 'play'; // tribute | play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  List<int> lastFinish = [];
  late List<bool> opened; // 开点
  late List<bool> dian; // 被点（头科出完时尚未开点）
  List<Map<String, dynamic>> tributes = [];
  int starter = 0;
  final List<String> log = [];

  int opp(int s) => (s + 3) % 6;
  int team(int s) => s % 2;

  void _log(String s) {
    log.add(s);
    if (log.length > 12) log.removeAt(0);
    host.log(s);
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'tribute') {
      return {for (final t in tributes) if (t['back'] == null) t['to'] as int}.toList();
    }
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (teamScores[0] == teamScores[1]) return List.filled(players, 1);
    final w = teamScores[0] > teamScores[1] ? 0 : 1;
    return [for (var s = 0; s < players; s++) team(s) == w ? 1 : 2];
  }

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 4);
    tributeOn = setup.opt<bool>('tribute', true);
    starter = rng.nextInt(players);
    _log('够级开始：3v3 隔位组队，四副牌，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = shuffled([for (var i = 0; i < 4; i++) ...c4Deck()], rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[i % players].add(deck[i]);
    }
    finish = [];
    plays = 0;
    opened = List.filled(players, false);
    resetTrick();
    result = null;
    ready = List.filled(players, false);
    tributes = [];
    if (tributeOn && lastFinish.length == players) {
      final head = lastFinish[0], second = lastFinish[1], last = lastFinish[5], second2 = lastFinish[4];
      void add(int from, int to, int n, String why) {
        if (team(from) == team(to)) return;
        tributes.add({'from': from, 'to': to, 'n': n, 'why': why, 'give': <String>[], 'back': null});
      }

      add(last, head, 2, '落贡');
      add(second2, second, 1, '落贡');
      for (var s = 0; s < players; s++) {
        if (dian[s]) add(s, opp(s), 1, '点贡');
      }
      for (final h in hands) {
        c4Sort(h);
      }
      for (final t in tributes) {
        final h = hands[t['from'] as int];
        final give = h.sublist(h.length - (t['n'] as int));
        t['give'] = give;
        c4Remove(h, give);
      }
      for (final t in tributes) {
        hands[t['to'] as int].addAll(t['give'] as List<String>);
        _log('${name(t['from'] as int)} 向 ${name(t['to'] as int)} ${t['why']} ${(t['give'] as List<String>).map(c4CardName).join(' ')}');
      }
    }
    for (final h in hands) {
      c4Sort(h);
    }
    dian = List.filled(players, false);
    if (lastFinish.length == players) starter = lastFinish.last;
    turn = starter;
    phase = tributes.isEmpty ? 'play' : 'tribute';
    if (phase == 'play') _log('第 $round 局：${name(turn)} 先出');
  }

  // ---------------- rules ----------------

  static bool isGouji(SetCombo c) {
    if (c.jokers > 0) return true;
    return switch (c.rank) {
      10 => c.size >= 5,
      11 => c.size >= 4,
      12 => c.size >= 3,
      13 || 14 => c.size >= 2,
      15 => true,
      _ => false,
    };
  }

  /// Whether [seat] could lead something that isn't a 4 (憋三 counts).
  bool _hasNon4Lead(int seat) {
    final h = hands[seat];
    if (h.every((c) => c4Val(c) == 3)) return true;
    return h.any((c) => c4Val(c) != 3 && c4Val(c) != 4);
  }

  bool fourLocked(int seat) =>
      !opened[seat] && finish.isEmpty && !(leading && seat == turn && !_hasNon4Lead(seat));

  @override
  Map<String, dynamic> checkPlay(int seat, List<String> cards) {
    final c = classifySet(cards);
    if (c == null) throw GameError('够级只能出同点数的牌（王可以挂）');
    final hand = hands[seat];
    final isLast = cards.length == hand.length;
    if (cards.any((x) => c4Val(x) == 3)) {
      if (!isLast || cards.any((x) => c4Val(x) != 3)) throw GameError('憋三：3 只能在最后一手单独出完，且不能挂王');
    }
    if (c.rank == 4 && !c.allJokers && fourLocked(seat)) throw GameError('还没开点，不能出 4');
    final info = c.toJson();
    info['gouji'] = isGouji(c);
    if (leading) return info;
    final t = SetCombo.fromJson(tableInfo)!;
    if (c.size != t.size) throw GameError('张数必须相同（${t.size} 张）');
    if (c.rank <= t.rank) throw GameError('点数要比桌上的大');
    if (tableInfo!['gouji'] == true && seat != opp(tableSeat)) {
      if (!isLast && c.jokers == 0) throw GameError('够级牌只有对头能管；烧牌必须挂王（最后一手除外）');
      info['burn'] = true;
    }
    return info;
  }

  @override
  List<int> responders(int seat) {
    if (tableInfo?['gouji'] == true) {
      return [for (final d in const [3, 1, 5]) if (active((seat + d) % 6)) (seat + d) % 6];
    }
    return super.responders(seat);
  }

  @override
  void onPlay(int seat, List<String> cards, Map<String, dynamic> info) {
    if (info['burn'] == true) _log('${name(seat)} 烧牌！打出${info['label']}');
  }

  @override
  void onPass(int seat) {
    if (tableInfo?['gouji'] == true && seat == opp(tableSeat) && !opened[tableSeat]) {
      opened[tableSeat] = true;
      _log('${name(tableSeat)} 的够级牌对头不管，开点！');
    }
  }

  @override
  void onTrickWon(int seat) {
    if (tableInfo?['gouji'] == true && !opened[seat] && !active(opp(seat))) {
      opened[seat] = true;
      _log('${name(seat)} 开点');
    }
  }

  @override
  void onFinish(int seat) {
    if (finish.length == 1) {
      final d = [for (var s = 0; s < players; s++) if (active(s) && !opened[s]) s];
      for (final s in d) {
        dian[s] = true;
      }
      if (d.isNotEmpty) _log('头科 ${name(seat)} 出完，${d.map(name).join('、')} 未开点被点${tributeOn ? '（下局点贡）' : ''}');
    }
  }

  @override
  int leaderAfter(int winner) {
    if (active(winner)) return winner;
    // 接风：队友优先
    for (var i = 1; i < players; i++) {
      final t = (winner + i) % players;
      if (active(t) && team(t) == team(winner)) return t;
    }
    return nextActive(winner);
  }

  @override
  bool get roundDone {
    if (activeCount <= 1) return true;
    for (final tm in const [0, 1]) {
      if ([for (var s = tm; s < players; s += 2) s].every((s) => !active(s))) return true;
    }
    return false;
  }

  @override
  void endRound() {
    final rest = [for (var s = 0; s < players; s++) if (active(s)) s]
      ..sort((a, b) => hands[a].length != hands[b].length ? hands[a].length - hands[b].length : a - b);
    final order = [...finish, ...rest];
    final top3 = order.sublist(0, 3).map(team).toSet();
    final men = top3.length == 1;
    final mult = men ? 2 : 1;
    final td = [0, 0];
    final delta = List.filled(players, 0);
    for (var i = 0; i < players; i++) {
      delta[order[i]] = placePts[i] * mult;
      td[team(order[i])] += placePts[i] * mult;
    }
    teamScores[0] += td[0];
    teamScores[1] += td[1];
    result = {
      'order': order,
      'delta': delta,
      'teamDelta': td,
      'men': men,
      'hands': [for (final h in hands) List.of(h)],
    };
    _log('第 $round 局结束：头科 ${name(order.first)}，大落 ${name(order.last)}${men ? '（闷！分数翻倍）' : ''}');
    lastFinish = order;
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  // ---------------- actions ----------------

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _deal();
      return;
    }
    if (phase == 'tribute') {
      if (type != 'return') throw GameError('等待还贡');
      final t = tributes.where((t) => t['to'] == seat && t['back'] == null).firstOrNull;
      if (t == null) throw GameError('你不需要还贡');
      final n = t['n'] as int;
      final cards = c4Take(a['cards'], hands[seat], max: n);
      if (cards.length != n) throw GameError('需要还 $n 张牌');
      c4Remove(hands[seat], cards);
      hands[t['from'] as int].addAll(cards);
      c4Sort(hands[t['from'] as int]);
      t['back'] = cards;
      if (tributes.every((t) => t['back'] != null)) {
        phase = 'play';
        _log('还贡完毕。第 $round 局：${name(turn)} 先出');
      }
      return;
    }
    if (phase != 'play') throw GameError('游戏已结束');
    handlePlay(seat, a);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...trickView(seat),
        'phase': phase,
        'turn': phase == 'play' ? turn : -1,
        'round': round,
        'rounds': rounds,
        'teamScores': teamScores,
        'opened': opened,
        'dian': dian,
        'fourLocked': seat >= 0 && seat < players && phase == 'play' ? fourLocked(seat) : false,
        'lastFinish': lastFinish,
        'tributes': [
          for (final t in tributes)
            {
              'from': t['from'],
              'to': t['to'],
              'n': t['n'],
              'why': t['why'],
              'give': t['give'],
              'back': t['back'] == null
                  ? null
                  : (seat == t['from'] || seat == t['to'] ? t['back'] : [for (final _ in t['back'] as List) 'back']),
            }
        ],
        'log': log,
        'result': phase == 'roundEnd' || phase == 'over' ? result : null,
        'ready': phase == 'roundEnd' ? ready : null,
      };

  // ---------------- bot ----------------

  bool _legal(int seat, List<String> cards) {
    try {
      checkPlay(seat, cards);
      return true;
    } on GameError {
      return false;
    }
  }

  /// Legal leads: each natural rank group whole (and split for big groups), jokers, 憋三.
  List<List<String>> leads(int seat) {
    final h = hands[seat];
    final out = <List<String>>[];
    if (h.every((c) => c4Val(c) == 3)) return [List.of(h)];
    final g = c4Groups(h.where((c) => !setWild(c)));
    final keys = g.keys.toList()..sort();
    for (final v in keys) {
      if (v == 3) continue;
      out.add(g[v]!);
    }
    final w = h.where(setWild).toList();
    if (w.isNotEmpty) out.add([w.last]);
    return out.where((c) => _legal(seat, c)).toList();
  }

  List<List<String>> follows(int seat) {
    final t = SetCombo.fromJson(tableInfo);
    if (t == null) return const [];
    return setCandidates(hands[seat], size: t.size, above: t.rank).where((c) => _legal(seat, c)).toList();
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase == 'tribute') {
      final t = tributes.where((t) => t['to'] == seat && t['back'] == null).firstOrNull;
      if (t == null) return null;
      final h = List.of(hands[seat])..sort((a, b) => c4Val(a) - c4Val(b));
      return {'type': 'return', 'cards': h.sublist(0, t['n'] as int)};
    }
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    if (leading) {
      final ls = leads(seat);
      if (botLevel == 0) return {'type': 'play', 'cards': ls[rng.nextInt(ls.length)]};
      final whole = ls.where((c) => c.length == hand.length);
      if (whole.isNotEmpty) return {'type': 'play', 'cards': whole.first};
      // 困难：未开点时主动出够级牌争取开点
      if (botLevel >= 2 && !opened[seat] && hand.any((c) => c4Val(c) == 4)) {
        final gj = ls.where((c) => isGouji(classifySet(c)!) && !c.any(setWild)).toList();
        if (gj.isNotEmpty) return {'type': 'play', 'cards': gj.first};
      }
      final nat = ls.where((c) => !c.any(setWild)).toList();
      return {'type': 'play', 'cards': (nat.isNotEmpty ? nat : ls).first};
    }
    final owner = tableSeat;
    if (team(owner) == team(seat)) return {'type': 'pass'};
    final fs = follows(seat);
    if (fs.isEmpty) return {'type': 'pass'};
    if (botLevel == 0) return rng.nextBool() ? {'type': 'play', 'cards': fs[rng.nextInt(fs.length)]} : {'type': 'pass'};
    final whole = fs.where((c) => c.length == hand.length);
    if (whole.isNotEmpty) return {'type': 'play', 'cards': whole.first};
    final isGj = tableInfo?['gouji'] == true;
    final iAmOpp = seat == opp(owner);
    final wildsLeft = hand.where(setWild).length;
    for (final c in fs) {
      final j = c.where(setWild).length;
      if (j == 0) return {'type': 'play', 'cards': c};
      // spend jokers only to stop a 够级 play as 对头, or when few cards remain
      final worth = (isGj && iAmOpp) || hand.length <= 8 || (botLevel >= 2 && hands[owner].length <= 5);
      if (worth && j <= (botLevel >= 2 ? 2 : 1) && wildsLeft - j >= 0) return {'type': 'play', 'cards': c};
    }
    return {'type': 'pass'};
  }
}

const String goujiRules = '''
# 够级（山东）
六人游戏，隔位组队 3 对 3（座位 1/3/5 一队，2/4/6 一队），正对面的对手称为“对头”。四副牌连王共 216 张，每人 36 张。
# 牌型与大小
- 只能出同点数的牌：单张、对子、三张……任意张数。大小：大王 > 小王 > 2 > A > K > … > 4 > 3。
- 王可以“挂”在任何点数上充当该点数（例：8 8 小王 = 三张 8）；全是王时按最小的王比较。
- 首家任意出；跟牌必须张数相同且点数更大。不出可以“过”。其他人都不要时，最后出牌者收轮并首出；出完后由队友接风。
# 够级牌
- 达到以下门槛的牌是“够级牌”：五张 10、四张 J、三张 Q、两张 K、两张 A、一张 2，以及任何带王的牌；同点数更多张也算。
- 够级牌只有对头能管，队友不能管。对头不管（或已出完）时，另外两个对手可以“烧牌”：烧牌必须挂王（最后一手除外）。
- 开点：你出的够级牌被对头让过（对头选择过），你就“开点”了。
# 4 与 3
- 开点前不能出 4；头科出完后 4 解禁。若首家手中只剩 3 和 4，也可以出 4。
- 憋三：3 只能作为最后一手一次出完，且不能挂王。
# 名次与计分
- 依出完顺序为头科、二科、三科、四科、二落、大落。一方三人全部出完时本局立即结束，剩余者按剩牌数排名。
- 个人得分：头科 +2、二科 +1、三科/四科 0、二落 -1、大落 -2，计入所在队。一队包揽前三名为“闷”，本局分数翻倍。
- 打满设定局数后队伍总分高者胜。
# 进贡（可选）
- 下一局发牌后：大落向头科进贡最大的 2 张、二落向二科进贡 1 张（仅限对手之间）；头科出完时还没开点的玩家“被点”，向对头点贡 1 张。
- 收贡者自选同样张数的牌还给进贡者。上一局大落先出牌。
# 本实现的简化
- 不支持“革命”、宣点、“闷”以外的特殊加倍，2 不能当作挂牌使用。
- 烧牌成功后不强制烧牌者一口气出完；被点者没有其他惩罚。
''';
