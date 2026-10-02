import 'dart:math';

import '../../src/engine.dart';
import 'common.dart';

/// 牛头数：55=7，11 的倍数=5，10 的倍数=3，5 的倍数=2，其他=1。
int nimmtBulls(int c) {
  if (c == 55) return 7;
  if (c % 11 == 0) return 5;
  if (c % 10 == 0) return 3;
  if (c % 5 == 0) return 2;
  return 1;
}

int nimmtRowBulls(List<int> row) => row.fold(0, (a, c) => a + nimmtBulls(c));

/// Row a card goes to: the row whose last card is the highest below [card]; -1 = none.
int nimmtTargetRow(List<List<int>> rows, int card) {
  var best = -1;
  for (var i = 0; i < rows.length; i++) {
    final last = rows[i].last;
    if (last < card && (best < 0 || last > rows[best].last)) best = i;
  }
  return best;
}

const sixNimmtRules = '''
# 概述
谁是牛头王（6 nimmt!）共 104 张牌，编号 1~104，每张牌上有 1~7 个牛头。牛头是罚分，整场结束时牛头最少的人获胜。

# 牛头数
- 55：7 个牛头
- 11 的倍数（11、22…99）：5 个
- 10 的倍数：3 个
- 5 的倍数（不含上述）：2 个
- 其余：1 个

# 每局流程
- 每人发 10 张牌，桌面翻开 4 张作为 4 列的开头。
- 每回合所有人同时秘密选一张牌，全部选好后同时亮牌，从小到大依次放置。
- 放置规则：牌放到“末尾牌比它小、且差值最小”的那一列末尾。
- 若该列已经有 5 张牌，你的牌就是第 6 张：你必须收走这 5 张（计入罚分），你的牌成为该列新的开头。
- 若你的牌比 4 列末尾都小，你必须选择任意一列收走，你的牌成为该列新的开头（由出牌者自己选）。
- 10 回合后手牌出完，本局结束，结算每人本局收走的牛头数并累计。

# 结束条件（选项）
- 66 分：有人累计达到 66 个牛头时，在该局结束后整场结束。
- 固定局数：打满 1 / 3 / 5 局后结束。
- 累计牛头最少者获胜，名次按牛头从少到多排列。

# 专业变体（选项）
- 只使用 1 ~ (10×人数+4) 号牌（例如 3 人用 1~34），所有牌都会被发出，整局完全可计算。
- 界面会显示“尚未出现的牌”，方便推算。

# 操作
- 选牌阶段：点一张手牌，再点“出这张”。所有人选好之前可以改选。
- 选列阶段：你的牌最小时，点选要收走的一列。
''';

class SixNimmt extends GameEngine with LightLog {
  SixNimmt(super.setup);

  late final bool pro = setup.opt<bool>('pro', false);
  late final int endMode = setup.opt<int>('end', 66); // 66 = to 66 points; 1/3/5 = rounds
  late List<List<int>> hands = [for (var i = 0; i < players; i++) <int>[]];
  late List<int> chosen = List.filled(players, -1);
  late List<int> score = List.filled(players, 0);
  late List<int> roundPen = List.filled(players, 0);
  late List<List<int>> taken = [for (var i = 0; i < players; i++) <int>[]];
  List<List<int>> rows = [];
  String phase = 'choose'; // choose / pickRow / roundEnd / over
  int round = 0;
  int trick = 0;

  /// Revealed cards of the current turn, ascending, still to be placed ({seat, card}).
  List<Map<String, int>> pending = [];
  int picker = -1;

  /// What happened in the last completed turn (for the UI).
  List<Map<String, dynamic>> lastTurn = [];
  List<Map<String, dynamic>> turnSoFar = [];
  Set<int> seen = {};
  Map<String, dynamic>? roundResult;
  int resigned = -1;

  int get deckMax => pro ? 10 * players + 4 : 104;

  @override
  void start() {
    say('谁是牛头王开始！${endMode == 66 ? '有人达到 66 牛头时结束' : '共 $endMode 局'}${pro ? '（专业变体：1~$deckMax）' : ''}');
    _newRound();
  }

  void _newRound() {
    round++;
    trick = 0;
    final deck = shuffled([for (var c = 1; c <= deckMax; c++) c], rng);
    for (var i = 0; i < players; i++) {
      hands[i] = deck.sublist(i * 10, i * 10 + 10)..sort();
      roundPen[i] = 0;
      taken[i] = [];
      chosen[i] = -1;
    }
    rows = [for (var r = 0; r < 4; r++) [deck[players * 10 + r]]];
    seen = {for (final r in rows) ...r};
    pending = [];
    lastTurn = [];
    turnSoFar = [];
    roundResult = null;
    phase = 'choose';
    say('—— 第 $round 局 ——');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'choose') return [for (var i = 0; i < players; i++) if (chosen[i] < 0) i];
    if (phase == 'pickRow') return [picker];
    return const [];
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return [for (var i = 0; i < players; i++) i == resigned ? 2 : 1];
    return rankByScore(score, lowWins: true);
  }

  @override
  bool get canResign => players == 2 && !isOver;

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    resigned = seat;
    phase = 'over';
    say('${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (phase == 'choose') {
      if (type != 'choose') throw GameError('请选择一张牌');
      if (seat < 0 || seat >= players) throw GameError('无效座位');
      final c = asInt(a['card']);
      if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
      chosen[seat] = c;
      if (chosen.every((x) => x > 0)) _reveal();
      return;
    }
    if (phase == 'pickRow') {
      if (seat != picker) throw GameError('还没轮到你');
      if (type != 'row') throw GameError('请选择要收走的一列');
      final r = asInt(a['row']);
      if (r < 0 || r >= 4) throw GameError('无效的列');
      final p = pending.removeAt(0);
      _takeRow(p['seat']!, p['card']!, r, forced: false);
      _resolve();
      return;
    }
    throw GameError('请稍候');
  }

  void _reveal() {
    trick++;
    pending = [
      for (var i = 0; i < players; i++) {'seat': i, 'card': chosen[i]}
    ]..sort((a, b) => a['card']!.compareTo(b['card']!));
    for (var i = 0; i < players; i++) {
      hands[i].remove(chosen[i]);
      seen.add(chosen[i]);
    }
    say('亮牌：${pending.map((p) => '${name(p['seat']!)} ${p['card']}').join('，')}');
    turnSoFar = [];
    _resolve();
  }

  void _takeRow(int seat, int card, int r, {required bool forced}) {
    final row = rows[r];
    final b = nimmtRowBulls(row);
    taken[seat].addAll(row);
    roundPen[seat] += b;
    turnSoFar.add({'seat': seat, 'card': card, 'row': r, 'took': List.of(row), 'bulls': b, 'sixth': forced});
    rows[r] = [card];
    say(forced
        ? '${name(seat)} 的 $card 是第 6 张，收走第 ${r + 1} 列（$b 牛头）'
        : '${name(seat)} 的 $card 最小，选择收走第 ${r + 1} 列（$b 牛头）');
  }

  void _resolve() {
    while (pending.isNotEmpty) {
      final p = pending.first;
      final seat = p['seat']!, card = p['card']!;
      final r = nimmtTargetRow(rows, card);
      if (r < 0) {
        phase = 'pickRow';
        picker = seat;
        return;
      }
      pending.removeAt(0);
      if (rows[r].length >= 5) {
        _takeRow(seat, card, r, forced: true);
      } else {
        rows[r].add(card);
        turnSoFar.add({'seat': seat, 'card': card, 'row': r, 'took': <int>[], 'bulls': 0, 'sixth': false});
      }
    }
    picker = -1;
    lastTurn = turnSoFar;
    chosen = List.filled(players, -1);
    if (hands.every((h) => h.isEmpty)) {
      _endRound();
    } else {
      phase = 'choose';
    }
  }

  void _endRound() {
    for (var i = 0; i < players; i++) {
      score[i] += roundPen[i];
    }
    say('第 $round 局结束：${[for (var i = 0; i < players; i++) '${name(i)} +${roundPen[i]}'].join('，')}');
    roundResult = {'round': round, 'pen': List.of(roundPen), 'score': List.of(score)};
    final done = endMode == 66 ? score.any((s) => s >= 66) : round >= endMode;
    if (done) {
      phase = 'over';
      final best = score.reduce(min);
      say('游戏结束！${[for (var i = 0; i < players; i++) if (score[i] == best) name(i)].join('、')} 牛头最少（$best），获胜');
      return;
    }
    phase = 'roundEnd';
    host.schedule(5000, () {
      if (phase == 'roundEnd') _newRound();
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'players': players,
      'phase': phase,
      'round': round,
      'trick': trick,
      'endMode': endMode,
      'pro': pro,
      'deckMax': deckMax,
      'rows': rows,
      'hand': me ? hands[seat] : <int>[],
      'handCounts': [for (final h in hands) h.length],
      'chosen': [for (var i = 0; i < players; i++) chosen[i] > 0],
      'myChoice': me ? chosen[seat] : -1,
      'pending': phase == 'pickRow' ? [for (final p in pending) Map<String, dynamic>.from(p)] : <Map<String, dynamic>>[],
      'turnSoFar': phase == 'pickRow' ? turnSoFar : <Map<String, dynamic>>[],
      'picker': picker,
      'lastTurn': lastTurn,
      'score': score,
      'roundPen': roundPen,
      'takenCount': [for (final t in taken) t.length],
      'unseen': pro ? [for (var c = 1; c <= deckMax; c++) if (!seen.contains(c) && !(me && hands[seat].contains(c))) c] : <int>[],
      'roundResult': phase == 'roundEnd' || phase == 'over' ? roundResult : null,
      'resigned': resigned,
      'log': recentLogs(),
    };
  }

  // ---------------------------------------------------------------- bot

  /// Expected penalty of playing [card] now (from [seat]'s point of view).
  double _risk(int seat, int card, List<int> unseen) {
    final r = nimmtTargetRow(rows, card);
    if (r < 0) {
      final cheapest = rows.map(nimmtRowBulls).reduce(min);
      // only bad if someone else goes even lower; we still pick the cheapest row
      return cheapest.toDouble() + 0.3;
    }
    final row = rows[r];
    final bulls = nimmtRowBulls(row);
    if (row.length >= 5) {
      // someone lower than us might take this row first — rarely; treat as certain
      return bulls.toDouble();
    }
    final last = row.last;
    final gap = unseen.where((c) => c > last && c < card).length;
    final others = players - 1;
    final slots = 5 - row.length; // intruders needed to make us 6th
    final pIn = unseen.isEmpty ? 0.0 : gap / unseen.length;
    // Poisson-ish chance that at least [slots] other cards land before ours
    final lambda = others * pIn;
    var pLess = 0.0, term = exp(-lambda);
    for (var k = 0; k < slots; k++) {
      pLess += term;
      term = term * lambda / (k + 1);
    }
    final pSixth = (1 - pLess).clamp(0.0, 1.0);
    // expected bulls: the row plus the intruders (≈1.3 each)
    return pSixth * (bulls + slots * 1.3) + (row.length == 4 ? 0.2 * pIn * others : 0);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'pickRow') {
      var best = 0;
      for (var r = 1; r < 4; r++) {
        final a = nimmtRowBulls(rows[r]), b = nimmtRowBulls(rows[best]);
        if (a < b || (a == b && rows[r].length > rows[best].length)) best = r;
      }
      if (botLevel == 0 && rng.nextDouble() < 0.3) best = rng.nextInt(4);
      return {'type': 'row', 'row': best};
    }
    if (phase != 'choose' || chosen[seat] > 0 || hands[seat].isEmpty) {
      return hands[seat].isEmpty ? null : {'type': 'choose', 'card': chosen[seat] > 0 ? chosen[seat] : hands[seat].first};
    }
    final hand = hands[seat];
    if (botLevel == 0 && rng.nextDouble() < 0.5) return {'type': 'choose', 'card': hand[rng.nextInt(hand.length)]};
    final unseen = [for (var c = 1; c <= deckMax; c++) if (!seen.contains(c) && !hand.contains(c)) c];
    var bestC = hand.first;
    var bestS = double.infinity;
    for (final c in hand) {
      var s = _risk(seat, c, unseen);
      if (botLevel >= 2) {
        // keep flexible middle cards; dump dangerous extremes when safe
        final r = nimmtTargetRow(rows, c);
        if (r >= 0 && rows[r].length <= 2) s -= 0.15;
        if (s < 0.3 && (c < 15 || c > 90)) s -= 0.1;
      } else {
        s += rng.nextDouble() * 0.4;
      }
      if (s < bestS) {
        bestS = s;
        bestC = c;
      }
    }
    return {'type': 'choose', 'card': bestC};
  }
}
