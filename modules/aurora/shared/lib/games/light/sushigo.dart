import 'dart:math';

import '../../src/engine.dart';
import 'common.dart';

/// Card ids. Nigiri placed on a wasabi become `w_<nigiri>`.
const sushiCards = ['tempura', 'sashimi', 'dumpling', 'maki1', 'maki2', 'maki3', 'salmon', 'squid', 'egg', 'pudding', 'wasabi', 'chopsticks'];
const sushiCounts = [14, 14, 14, 6, 12, 8, 10, 5, 5, 10, 6, 4];
const sushiNames = {
  'tempura': '天妇罗',
  'sashimi': '刺身',
  'dumpling': '饺子',
  'maki1': '卷寿司×1',
  'maki2': '卷寿司×2',
  'maki3': '卷寿司×3',
  'salmon': '三文鱼握寿司',
  'squid': '鱿鱼握寿司',
  'egg': '玉子握寿司',
  'pudding': '布丁',
  'wasabi': '芥末',
  'chopsticks': '筷子',
  'w_salmon': '芥末三文鱼',
  'w_squid': '芥末鱿鱼',
  'w_egg': '芥末玉子',
};

int sushiHandSize(int players) => switch (players) { 2 => 10, 3 => 9, 4 => 8, _ => 7 };

int _nigiri(String c) => switch (c) { 'salmon' => 2, 'squid' => 3, 'egg' => 1, _ => 0 };
int sushiMaki(String c) => switch (c) { 'maki1' => 1, 'maki2' => 2, 'maki3' => 3, _ => 0 };
const _dumplingPts = [0, 1, 3, 6, 10, 15];

/// Points of one tableau, excluding maki and pudding.
int sushiTableauPoints(List<String> t) {
  var p = 0;
  final tem = t.where((c) => c == 'tempura').length;
  final sas = t.where((c) => c == 'sashimi').length;
  final dum = t.where((c) => c == 'dumpling').length;
  p += tem ~/ 2 * 5;
  p += sas ~/ 3 * 10;
  p += _dumplingPts[min(dum, 5)];
  for (final c in t) {
    p += _nigiri(c);
    if (c.startsWith('w_')) p += _nigiri(c.substring(2)) * 3;
  }
  return p;
}

/// Maki points for every seat: most +6 (split), second +3 (split; none if tie for first).
List<int> sushiMakiPoints(List<int> maki) {
  final n = maki.length;
  final out = List.filled(n, 0);
  final top = maki.reduce(max);
  if (top <= 0) return out;
  final firsts = [for (var i = 0; i < n; i++) if (maki[i] == top) i];
  for (final i in firsts) {
    out[i] += 6 ~/ firsts.length;
  }
  if (firsts.length > 1) return out;
  final rest = [for (var i = 0; i < n; i++) if (maki[i] < top && maki[i] > 0) maki[i]];
  if (rest.isEmpty) return out;
  final second = rest.reduce(max);
  final seconds = [for (var i = 0; i < n; i++) if (maki[i] == second) i];
  for (final i in seconds) {
    out[i] += 3 ~/ seconds.length;
  }
  return out;
}

/// Pudding at game end: most +6 split, fewest -6 split (not in 2-player games).
List<int> sushiPuddingPoints(List<int> pud) {
  final n = pud.length;
  final out = List.filled(n, 0);
  final hi = pud.reduce(max), lo = pud.reduce(min);
  if (hi == lo) return out;
  final most = [for (var i = 0; i < n; i++) if (pud[i] == hi) i];
  for (final i in most) {
    out[i] += 6 ~/ most.length;
  }
  if (n > 2) {
    final least = [for (var i = 0; i < n; i++) if (pud[i] == lo) i];
    for (final i in least) {
      out[i] -= 6 ~/ least.length;
    }
  }
  return out;
}

const sushiGoRules = '''
# 概述
寿司狗（Sushi Go!）是 2~5 人的轮抽（drafting）游戏，共 3 轮。每轮每人发一手牌（2 人 10 张、3 人 9 张、4 人 8 张、5 人 7 张）。

# 每一回合
- 所有人同时从手牌中选 1 张面朝下放好，全部选好后同时翻开放到自己面前。
- 然后把剩下的手牌传给左手边（下一座位）的玩家，继续选牌，直到手牌全部选完，本轮结束计分。
- 除布丁外，本轮打出的牌在计分后弃掉；布丁保留到游戏结束。

# 牌与计分
- 天妇罗（14 张）：每 2 张 = 5 分，单张不得分。
- 刺身（14 张）：每 3 张 = 10 分。
- 饺子（14 张）：1/2/3/4/5 张及以上 = 1/3/6/10/15 分。
- 卷寿司（1/2/3 个卷，各 6/12/8 张）：每轮结束时卷数最多者 6 分、第二多者 3 分；并列时平分（向下取整），第一名并列则没有第二名。
- 握寿司：玉子 1 分、三文鱼 2 分、鱿鱼 3 分。
- 芥末（6 张）：之后你打出的第一张握寿司放在它上面，分数 ×3。没有握寿司的芥末 0 分。
- 筷子（4 张）：之后某一回合，你可以一次选 2 张牌，然后把筷子放回手牌传出去。
- 布丁（10 张）：游戏结束时布丁最多者 +6 分，最少者 −6 分（并列平分；2 人游戏不扣分）。

# 结束
- 3 轮后总分最高者获胜；同分时布丁多者名次靠前。

# 操作
- 点一张牌再点“选这张”。面前有筷子时，可以打开“用筷子”再额外选第二张。
- 所有人选好前可以改选。
''';

class SushiGo extends GameEngine with LightLog {
  SushiGo(super.setup);

  List<String> deck = [];
  late List<List<String>> hands = [for (var i = 0; i < players; i++) <String>[]];
  late List<List<String>> tableau = [for (var i = 0; i < players; i++) <String>[]];
  late List<int> pudding = List.filled(players, 0);
  late List<int> score = List.filled(players, 0);

  /// Pending pick per seat: indices into the hand (1 or 2), or null.
  late List<List<int>?> picks = List.filled(players, null);
  int round = 0;
  int turn = 0;
  String phase = 'pick'; // pick / roundEnd / over
  List<Map<String, dynamic>> lastReveal = [];
  Map<String, dynamic>? roundResult;
  List<Map<String, dynamic>> history = [];

  @override
  void start() {
    for (var i = 0; i < sushiCards.length; i++) {
      for (var k = 0; k < sushiCounts[i]; k++) {
        deck.add(sushiCards[i]);
      }
    }
    deck.shuffle(rng);
    say('寿司狗开始！共 3 轮，每轮每人 ${sushiHandSize(players)} 张');
    _newRound();
  }

  void _newRound() {
    round++;
    turn = 0;
    final n = sushiHandSize(players);
    for (var i = 0; i < players; i++) {
      hands[i] = [for (var k = 0; k < n; k++) deck.removeLast()];
      tableau[i] = [];
      picks[i] = null;
    }
    lastReveal = [];
    roundResult = null;
    phase = 'pick';
    say('—— 第 $round 轮 ——');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => phase == 'pick' ? [for (var i = 0; i < players; i++) if (picks[i] == null) i] : const [];

  List<num> get _finalKey => [for (var i = 0; i < players; i++) score[i] * 100 + pudding[i]];

  @override
  List<int>? get placings => isOver ? rankByScore(_finalKey) : null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase != 'pick') throw GameError(isOver ? '对局已结束' : '请稍候');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    if (asStr(a['type']) != 'pick') throw GameError('请选择一张牌');
    final hand = hands[seat];
    final i1 = asInt(a['card']);
    final i2 = asInt(a['second']);
    if (i1 < 0 || i1 >= hand.length) throw GameError('请选择一张手牌');
    if (i2 >= 0) {
      if (!tableau[seat].contains('chopsticks')) throw GameError('你面前没有筷子');
      if (i2 == i1 || i2 >= hand.length) throw GameError('请选择另一张手牌');
      picks[seat] = [i1, i2];
    } else {
      picks[seat] = [i1];
    }
    if (picks.every((p) => p != null)) _reveal();
  }

  void _place(int s, String c) {
    final t = tableau[s];
    if (_nigiri(c) > 0) {
      final w = t.indexOf('wasabi');
      if (w >= 0) {
        t[w] = 'w_$c';
        return;
      }
    }
    if (c == 'pudding') pudding[s]++;
    t.add(c);
  }

  void _reveal() {
    turn++;
    lastReveal = [];
    for (var s = 0; s < players; s++) {
      final p = picks[s]!;
      final cards = [for (final i in p) hands[s][i]];
      final sorted = List.of(p)..sort();
      for (final i in sorted.reversed) {
        hands[s].removeAt(i);
      }
      for (final c in cards) {
        _place(s, c);
      }
      if (cards.length == 2) {
        tableau[s].remove('chopsticks');
        hands[s].add('chopsticks');
      }
      lastReveal.add({'seat': s, 'cards': cards});
    }
    say('第 $turn 手：${[for (final r in lastReveal) '${name(r['seat'] as int)} ${(r['cards'] as List).map((c) => sushiNames[c]).join('+')}'].join('，')}');
    picks = List.filled(players, null);
    if (hands.every((h) => h.isEmpty)) {
      _endRound();
      return;
    }
    // pass hands to the left (next seat)
    final old = hands;
    hands = [for (var s = 0; s < players; s++) old[(s - 1 + players) % players]];
  }

  void _endRound() {
    final maki = [for (final t in tableau) t.fold(0, (a, c) => a + sushiMaki(c))];
    final mp = sushiMakiPoints(maki);
    final gained = [for (var s = 0; s < players; s++) sushiTableauPoints(tableau[s]) + mp[s]];
    List<int>? pp;
    for (var s = 0; s < players; s++) {
      score[s] += gained[s];
    }
    if (round >= 3) {
      pp = sushiPuddingPoints(pudding);
      for (var s = 0; s < players; s++) {
        score[s] += pp[s];
      }
    }
    roundResult = {
      'round': round,
      'gained': gained,
      'maki': maki,
      'makiPts': mp,
      'puddingPts': pp,
      'score': List.of(score),
      'tableau': [for (final t in tableau) List.of(t)],
    };
    history.add({'round': round, 'gained': gained});
    say('第 $round 轮计分：${[for (var s = 0; s < players; s++) '${name(s)} +${gained[s]}'].join('，')}');
    if (pp != null) {
      say('布丁结算：${[for (var s = 0; s < players; s++) if (pp[s] != 0) '${name(s)} ${pp[s] > 0 ? '+' : ''}${pp[s]}'].join('，')}');
      phase = 'over';
      final best = score.reduce(max);
      say('游戏结束！${[for (var s = 0; s < players; s++) if (score[s] == best) name(s)].join('、')} 以 $best 分获胜');
      return;
    }
    phase = 'roundEnd';
    host.schedule(6000, () {
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
      'turn': turn,
      'hand': me ? hands[seat] : <String>[],
      'handCounts': [for (final h in hands) h.length],
      'myPick': me ? picks[seat] : null,
      'picked': [for (final p in picks) p != null],
      'tableau': tableau,
      'pudding': pudding,
      'score': score,
      'maki': [for (final t in tableau) t.fold(0, (a, c) => a + sushiMaki(c))],
      'live': [for (final t in tableau) sushiTableauPoints(t)],
      'lastReveal': lastReveal,
      'roundResult': phase == 'roundEnd' || phase == 'over' ? roundResult : null,
      'history': history,
      'log': recentLogs(),
    };
  }

  // ---------------------------------------------------------------- bot

  /// Heuristic value of adding [c] to tableau [t] with [left] picks remaining after this one.
  double _value(int seat, List<String> t, String c, int left) {
    final others = [for (var o = 0; o < players; o++) if (o != seat) tableau[o]];
    switch (c) {
      case 'tempura':
        final n = t.where((x) => x == 'tempura').length;
        return n.isOdd ? 5 : (left >= 2 ? 2.4 : 0.2);
      case 'sashimi':
        final n = t.where((x) => x == 'sashimi').length % 3;
        if (n == 2) return 10;
        if (n == 1) return left >= 2 ? 3.8 : 0.1;
        return left >= 4 ? 2.6 : 0.1;
      case 'dumpling':
        final n = min(t.where((x) => x == 'dumpling').length, 5);
        return n >= 5 ? 0 : (_dumplingPts[n + 1] - _dumplingPts[n]).toDouble() + (left >= 2 && n < 3 ? 0.7 : 0);
      case 'maki1':
      case 'maki2':
      case 'maki3':
        final mine = t.fold(0, (a, x) => a + sushiMaki(x));
        final best = others.isEmpty ? 0 : others.map((o) => o.fold(0, (a, x) => a + sushiMaki(x))).reduce(max);
        final add = sushiMaki(c);
        var v = add * 1.1;
        if (mine <= best && mine + add > best) v += 2.0;
        if (mine > best + 4) v *= 0.4;
        return v;
      case 'salmon':
      case 'squid':
      case 'egg':
        return _nigiri(c) * (t.contains('wasabi') ? 3.0 : 1.0);
      case 'wasabi':
        return t.contains('wasabi') ? (left >= 3 ? 1.5 : 0.1) : (left >= 2 ? 3.5 : 0.1);
      case 'chopsticks':
        return t.contains('chopsticks') ? 0.2 : (left >= 3 ? 2.2 : 0.1);
      case 'pudding':
        final mine = pudding[seat];
        final hi = pudding.reduce(max), lo = pudding.reduce(min);
        var v = 1.5 + round * 0.5;
        if (mine == lo && players > 2) v += 1.0;
        if (mine == hi && hi - pudding.where((p) => p != hi).fold(0, max) > 2) v -= 1.0;
        return v;
    }
    return 0;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'pick' || picks[seat] != null) return null;
    final hand = hands[seat];
    if (hand.isEmpty) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.5) return {'type': 'pick', 'card': rng.nextInt(hand.length)};
    final left = hand.length - 1;
    final t = tableau[seat];
    var best = 0;
    var bestV = -1e9;
    final vals = <double>[];
    for (var i = 0; i < hand.length; i++) {
      var v = _value(seat, t, hand[i], left);
      if (botLevel == 1) v += rng.nextDouble() * 0.8;
      if (botLevel >= 2) {
        // hate-draft: deny what the next player badly needs
        final nxt = tableau[(seat + 1) % players];
        final deny = _value((seat + 1) % players, nxt, hand[i], left);
        v += deny * 0.15;
      }
      vals.add(v);
      if (v > bestV) {
        bestV = v;
        best = i;
      }
    }
    if (t.contains('chopsticks') && hand.length >= 2) {
      final t2 = [...t, hand[best]];
      var second = -1;
      var sv = -1e9;
      for (var i = 0; i < hand.length; i++) {
        if (i == best) continue;
        final v = _value(seat, t2, hand[i], left - 1);
        if (v > sv) {
          sv = v;
          second = i;
        }
      }
      if (second >= 0 && sv >= (botLevel >= 2 ? 3.0 : 3.5)) return {'type': 'pick', 'card': best, 'second': second};
    }
    return {'type': 'pick', 'card': best};
  }
}
