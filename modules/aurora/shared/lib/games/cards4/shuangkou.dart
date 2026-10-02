import '../../src/engine.dart';
import 'cards.dart';
import 'sk_rules.dart';
import 'trick.dart';

/// 双扣：4 人对家 2v2，两副牌 108 张每人 27 张。见 [shuangkouRules]。
class Shuangkou extends C4Trick {
  Shuangkou(super.setup);

  late int target;
  late bool bombBonus;
  int round = 0;
  List<int> teamScores = [0, 0];
  String phase = 'play'; // play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  List<int> lastFinish = [];
  late List<int> bombs; // per team this round (5 张以上炸弹 / 天王炸)
  int starter = 0;
  final List<String> log = [];

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
    target = setup.opt<int>('target', 10);
    bombBonus = setup.opt<bool>('bombBonus', true);
    starter = rng.nextInt(players);
    _log('双扣开始：对家组队，两副牌，先到 $target 分的一方获胜');
    _deal();
  }

  void _deal() {
    round++;
    final deck = shuffled([...c4Deck(), ...c4Deck()], rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[i % players].add(deck[i]);
    }
    for (final h in hands) {
      c4Sort(h);
    }
    finish = [];
    plays = 0;
    bombs = [0, 0];
    resetTrick();
    result = null;
    ready = List.filled(players, false);
    if (lastFinish.length == players) starter = lastFinish.last;
    turn = starter;
    phase = 'play';
    _log('第 $round 局：${name(turn)} 先出');
  }

  @override
  Map<String, dynamic> checkPlay(int seat, List<String> cards) {
    final c = skClassify(cards);
    if (c == null) throw GameError('不是合法牌型');
    if (!leading) {
      final t = SkCombo.fromJson(tableInfo)!;
      if (!c.beats(t)) throw GameError(t.isBomb ? '管不上：需要更大的炸弹' : '管不上：需出同型更大的牌（${t.label}）或炸弹');
    }
    return c.toJson();
  }

  @override
  void onPlay(int seat, List<String> cards, Map<String, dynamic> info) {
    final c = SkCombo.fromJson(info)!;
    if (c.isBomb) {
      _log('${name(seat)} 打出${c.label}！');
      if (c.type == 'kings' || c.len >= 6) bombs[team(seat)]++;
    }
  }

  @override
  int leaderAfter(int winner) {
    if (active(winner)) return winner;
    final p = (winner + 2) % 4;
    return active(p) ? p : nextActive(winner);
  }

  @override
  bool get roundDone => finish.length >= 3 || (finish.length == 2 && team(finish[0]) == team(finish[1]));

  @override
  void endRound() {
    final rest = [for (var s = 0; s < players; s++) if (active(s)) s]
      ..sort((a, b) => hands[a].length != hands[b].length ? hands[a].length - hands[b].length : a - b);
    final order = [...finish, ...rest];
    final win = team(order[0]);
    final partnerPos = order.indexWhere((s) => s != order[0] && team(s) == win);
    final base = switch (partnerPos) { 1 => 3, 2 => 2, _ => 1 };
    final kind = switch (partnerPos) { 1 => '双扣', 2 => '单扣', _ => '平扣' };
    final td = [0, 0];
    td[win] = base;
    if (bombBonus) {
      td[0] += bombs[0];
      td[1] += bombs[1];
    }
    teamScores[0] += td[0];
    teamScores[1] += td[1];
    result = {
      'order': order,
      'kind': kind,
      'teamDelta': td,
      'bombs': List.of(bombs),
      'winTeam': win,
      'hands': [for (final h in hands) List.of(h)],
    };
    _log('第 $round 局结束：${name(order[0])} 上游，$kind +$base');
    lastFinish = order;
    final done = teamScores.any((x) => x >= target) && teamScores[0] != teamScores[1];
    phase = done || round >= 30 ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

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
    if (phase != 'play') throw GameError('游戏已结束');
    handlePlay(seat, a);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        ...trickView(seat),
        'phase': phase,
        'turn': phase == 'play' ? turn : -1,
        'round': round,
        'target': target,
        'teamScores': teamScores,
        'bombs': bombs,
        'lastFinish': lastFinish,
        'log': log,
        'result': phase == 'play' ? null : result,
        'ready': phase == 'roundEnd' ? ready : null,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    final table = SkCombo.fromJson(tableInfo);
    final cands = skCandidates(hand, table);
    if (cands.isEmpty) return leading ? {'type': 'play', 'cards': [hand.first]} : {'type': 'pass'};
    if (botLevel == 0) {
      if (!leading && rng.nextInt(3) == 0) return {'type': 'pass'};
      return {'type': 'play', 'cards': cands[rng.nextInt(cands.length)]};
    }
    final whole = cands.where((c) => c.length == hand.length);
    if (whole.isNotEmpty) return {'type': 'play', 'cards': whole.first};
    final g = c4Groups(hand);
    bool breaks(List<String> c) {
      final x = skClassify(c)!;
      return !x.isBomb && c.any((card) => (g[c4Val(card)]?.length ?? 0) >= 4);
    }

    final plain = cands.where((c) => !skClassify(c)!.isBomb && !breaks(c)).toList();
    if (leading) {
      if (plain.isEmpty) return {'type': 'play', 'cards': cands.first};
      int low(List<String> c) => c.map(c4Val).reduce((a, b) => a < b ? a : b);
      plain.sort((a, b) {
        final d = low(a) - low(b);
        return d != 0 ? d : b.length - a.length;
      });
      return {'type': 'play', 'cards': plain.first};
    }
    final partner = (seat + 2) % 4;
    final enemyDanger = [for (var s = 0; s < 4; s++) if (team(s) != team(seat) && active(s)) hands[s].length].any((n) => n <= (botLevel >= 2 ? 6 : 3));
    if (tableSeat == partner) {
      // 不压队友，除非能直接走完（上面已处理）
      return {'type': 'pass'};
    }
    if (plain.isNotEmpty) {
      final p = plain.first;
      if (p.any((c) => c4Val(c) >= 15) && !enemyDanger && hand.length > 8 && table!.key < 11) return {'type': 'pass'};
      return {'type': 'play', 'cards': p};
    }
    if (enemyDanger || hand.length <= 10) {
      return {'type': 'play', 'cards': cands.firstWhere((c) => skClassify(c)!.isBomb, orElse: () => cands.first)};
    }
    return {'type': 'pass'};
  }
}

const String shuangkouRules = '''
# 双扣
四人游戏，对家组队（座位 1/3 对 2/4）。两副牌共 108 张，每人 27 张，没有百搭。
# 牌型
- 单张、对子、三张（不带牌）。
- 顺子：5 张以上连续单张（3 到 A，2 和王不能进顺子）。
- 连对：3 对以上连续对子；三顺：2 个以上连续三张。
- 炸弹：4~8 张同点数，张数多的大，张数相同比点数。
- 天王炸：四个王，最大。
- 牌点大小：大王 > 小王 > 2 > A > K > … > 3。
# 出牌
- 首家任意出；后面的人须出同型、同张数、更大的牌，或者出炸弹；也可以不要。
- 其他三人都不要时，最后出牌者收轮再出。出完的人由对家接风。
- 第一局随机首出，之后由上一局的下游先出。
# 计分
- 第一个出完为上游，依次二游、三游、下游。
- 双扣：上游和对家包揽前两名，得 3 分（此时本局立即结束）。
- 单扣：上游的对家是第三名，得 2 分；平扣：上游的对家是最后一名，得 1 分。
- 炸弹奖励（可选）：本局打出 6 张以上的炸弹或天王炸，每个给本方 +1 分。
- 先达到目标分且分数领先的一方获胜（最多 30 局）。
''';
