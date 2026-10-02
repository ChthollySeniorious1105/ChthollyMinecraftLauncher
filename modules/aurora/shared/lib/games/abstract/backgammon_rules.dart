/// 西洋双陆规则核心。
///
/// 位置表示：c[s][r] 为玩家 s 在其“相对点位” r 上的棋子数：
///   r = 0 已移出(off)，r = 1..24 为距离移出的点数，r = 25 为中柱(bar)。
/// 玩家 s 的相对点 r 对应对手的相对点 25 - r。
/// 绝对点位（给客户端）：0..23，玩家0 的相对点 r = idx+1；玩家1 的相对点 r = 24-idx。
/// 客户端动作中 from = 24 表示中柱，to = 25 表示移出。
class BgMove {
  final int from; // 相对点 1..25
  final int to; // 相对点 0..24（0 = 移出）
  final int die;
  final bool hit;
  const BgMove(this.from, this.to, this.die, this.hit);
  @override
  String toString() => '$from/$to${hit ? '*' : ''}';
}

class BgPos {
  final List<List<int>> c;
  BgPos(this.c);

  factory BgPos.initial() {
    List<int> side() {
      final l = List.filled(26, 0);
      l[24] = 2;
      l[13] = 5;
      l[8] = 3;
      l[6] = 5;
      return l;
    }

    return BgPos([side(), side()]);
  }

  BgPos clone() => BgPos([List.of(c[0]), List.of(c[1])]);

  int off(int s) => c[s][0];
  int bar(int s) => c[s][25];

  int pip(int s) {
    var p = 0;
    for (var r = 1; r <= 25; r++) {
      p += r * c[s][r];
    }
    return p;
  }

  bool allHome(int s) {
    for (var r = 7; r <= 25; r++) {
      if (c[s][r] > 0) return false;
    }
    return true;
  }

  /// 相对点 r (1..24) 对玩家 s 是否被对手封住（≥2 子）。
  bool blocked(int s, int r) => c[1 - s][25 - r] >= 2;

  /// 用骰子 d 的所有合法单步。
  List<BgMove> singleMoves(int s, int d) {
    final out = <BgMove>[];
    final me = c[s], opp = c[1 - s];
    if (me[25] > 0) {
      final t = 25 - d;
      if (opp[25 - t] < 2) out.add(BgMove(25, t, d, opp[25 - t] == 1));
      return out;
    }
    final home = allHome(s);
    for (var r = 24; r >= 1; r--) {
      if (me[r] == 0) continue;
      final t = r - d;
      if (t >= 1) {
        if (opp[25 - t] < 2) out.add(BgMove(r, t, d, opp[25 - t] == 1));
      } else if (home) {
        if (t == 0) {
          out.add(BgMove(r, 0, d, false));
        } else {
          var higher = false;
          for (var q = r + 1; q <= 6; q++) {
            if (me[q] > 0) {
              higher = true;
              break;
            }
          }
          if (!higher) out.add(BgMove(r, 0, d, false));
        }
      }
    }
    return out;
  }

  void apply(int s, BgMove m) {
    final me = c[s], opp = c[1 - s];
    me[m.from]--;
    me[m.to]++;
    if (m.to >= 1 && opp[25 - m.to] == 1) {
      opp[25 - m.to] = 0;
      opp[25]++;
    }
  }

  static List<int> _without(List<int> rem, int d) {
    final r = List.of(rem);
    r.remove(d);
    return r;
  }

  /// 剩余骰子 rem 最多能用掉几个。
  int maxUsable(int s, List<int> rem, [Map<String, int>? memo]) {
    if (rem.isEmpty) return 0;
    memo ??= {};
    final k = '${key()}#${(List.of(rem)..sort()).join()}';
    final m0 = memo[k];
    if (m0 != null) return m0;
    var best = 0;
    for (final d in rem.toSet()) {
      for (final m in singleMoves(s, d)) {
        final q = clone()..apply(s, m);
        final v = 1 + q.maxUsable(s, _without(rem, d), memo);
        if (v > best) best = v;
        if (best == rem.length) break;
      }
      if (best == rem.length) break;
    }
    memo[k] = best;
    return best;
  }

  /// 当前可以走的单步（已保证“尽量多用骰子；只能用一个时必须用大的”）。
  List<BgMove> legalNow(int s, List<int> rem) {
    if (rem.isEmpty) return const [];
    final memo = <String, int>{};
    final need = maxUsable(s, rem, memo);
    if (need == 0) return const [];
    final out = <BgMove>[];
    for (final d in rem.toSet()) {
      for (final m in singleMoves(s, d)) {
        final q = clone()..apply(s, m);
        if (1 + q.maxUsable(s, _without(rem, d), memo) == need) out.add(m);
      }
    }
    if (need == 1 && rem.length == 2 && rem[0] != rem[1]) {
      final big = rem[0] > rem[1] ? rem[0] : rem[1];
      final withBig = [for (final m in out) if (m.die == big) m];
      if (withBig.isNotEmpty) return withBig;
    }
    return out;
  }

  /// 所有合法完整走法（按最终局面去重）。无子可走时返回 [[]]。
  List<List<BgMove>> legalSequences(int s, List<int> dice) {
    final res = <List<BgMove>>[];
    final seen = <String>{};
    void dfs(BgPos p, List<int> rem, List<BgMove> seq) {
      final ms = p.legalNow(s, rem);
      if (ms.isEmpty) {
        if (seen.add(p.key())) res.add(seq);
        return;
      }
      for (final m in ms) {
        final q = p.clone()..apply(s, m);
        final rest = _without(rem, m.die);
        if (!seen.add('${q.key()}#${rest.length}')) continue;
        dfs(q, rest, [...seq, m]);
      }
    }

    dfs(this, dice, const []);
    return res.isEmpty ? [const []] : res;
  }

  String key() => '${c[0].join(',')}|${c[1].join(',')}';

  /// 绝对棋盘：正数为玩家0的棋子数，负数为玩家1。
  List<int> absBoard() => [for (var i = 0; i < 24; i++) c[0][i + 1] - c[1][24 - i]];

  /// 胜负结束时的倍数：1 单胜，2 全胜(gammon)，3 大全胜(backgammon)。
  int winKind(int winner) {
    final l = 1 - winner;
    if (c[l][0] > 0) return 1;
    if (c[l][25] > 0) return 3;
    // 输家在赢家内盘（赢家相对 1..6 = 输家相对 19..24）
    for (var r = 19; r <= 24; r++) {
      if (c[l][r] > 0) return 3;
    }
    return 2;
  }

  bool contact() {
    // 玩家0 最远的子（相对最大）与玩家1 最远的子是否还有交错
    var max0 = 0, max1 = 0;
    for (var r = 25; r >= 1; r--) {
      if (c[0][r] > 0) {
        max0 = r;
        break;
      }
    }
    for (var r = 25; r >= 1; r--) {
      if (c[1][r] > 0) {
        max1 = r;
        break;
      }
    }
    // 玩家1 相对 max1 → 玩家0 相对 25-max1
    return max0 + max1 > 25;
  }
}

int bgAbs(int s, int r) {
  if (r == 25) return 24;
  if (r == 0) return 25;
  return s == 0 ? r - 1 : 24 - r;
}

int bgRel(int s, int a) {
  if (a == 24) return 25;
  if (a == 25) return 0;
  return s == 0 ? a + 1 : 24 - a;
}

const _shotOdds = <int, int>{
  1: 11, 2: 12, 3: 14, 4: 15, 5: 15, 6: 17, 7: 6, 8: 6, 9: 5, 10: 3, 11: 2, 12: 3, 15: 1, 16: 1, 18: 1, 20: 1, 24: 1,
};

/// 启发式评估（玩家 s 视角，越大越好）。
double bgEvaluate(BgPos p, int s) {
  final o = 1 - s;
  final me = p.c[s], opp = p.c[o];
  if (me[0] == 15) return 10000;
  final pipMe = p.pip(s), pipOpp = p.pip(o);
  if (!p.contact()) {
    // 纯赛跑
    var wasted = 0;
    for (var r = 1; r <= 6; r++) {
      if (me[r] > 3) wasted += me[r] - 3;
    }
    return (pipOpp - pipMe) * 1.0 + me[0] * 1.5 - wasted * 0.5;
  }
  var score = (pipOpp - pipMe) * 1.0;
  // 对手棋子在我方相对点 q（q=0 表示对手在中柱）
  final oppAt = <int>[];
  if (opp[25] > 0) oppAt.add(0);
  for (var q = 1; q <= 24; q++) {
    if (opp[25 - q] > 0) oppAt.add(q);
  }
  // 暴露的散子
  for (var r = 1; r <= 24; r++) {
    if (me[r] != 1) continue;
    var odds = 0;
    for (final q in oppAt) {
      if (q < r) odds += _shotOdds[r - q] ?? 0;
    }
    if (odds == 0) continue;
    final prob = (odds > 36 ? 36 : odds) / 36.0;
    score -= prob * (25 - r + 6) * 0.9;
  }
  // 做点
  var run = 0, best = 0;
  var homePts = 0;
  for (var r = 1; r <= 24; r++) {
    if (me[r] >= 2) {
      if (r <= 6) {
        score += r >= 4 ? 5 : 3.5;
        homePts++;
      } else if (r == 7) {
        score += 4.5;
      } else if (r <= 11) {
        score += 2;
      } else if (r >= 19) {
        score += 2.5; // 锚点
      } else {
        score += 1;
      }
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
    if (me[r] > 4) score -= (me[r] - 4) * 1.2;
  }
  score += best * best * 1.2;
  // 对手在中柱
  score += opp[25] * (4 + homePts * 1.5);
  // 我方在中柱
  var oppHome = 0;
  for (var r = 1; r <= 6; r++) {
    if (opp[r] >= 2) oppHome++;
  }
  score -= me[25] * (3 + oppHome * 1.5);
  score += me[0] * 0.8;
  return score;
}

/// 在所有合法走法中选择评估最好的。
List<BgMove> bgBestSequence(BgPos p, int s, List<List<BgMove>> seqs) {
  if (seqs.length == 1) return seqs.first;
  final seen = <String>{};
  List<BgMove>? best;
  var bestV = double.negativeInfinity;
  for (final q in seqs) {
    final r = p.clone();
    for (final m in q) {
      r.apply(s, m);
    }
    if (!seen.add(r.key())) continue;
    final v = bgEvaluate(r, s);
    if (v > bestV) {
      bestV = v;
      best = q;
    }
  }
  return best ?? seqs.first;
}

/// 简单胜率估计（0..1，玩家 s 视角），用于加倍决策。
double bgWinEstimate(BgPos p, int s) {
  final o = 1 - s;
  final pm = p.pip(s) + p.bar(s) * 4, po = p.pip(o) + p.bar(o) * 4;
  final lead = (po - pm) / (pm < 20 ? 20 : pm);
  var v = 0.5 + lead * 1.6 + (bgEvaluate(p, s) - bgEvaluate(p, o)) * 0.004;
  if (v < 0) v = 0;
  if (v > 1) v = 1;
  return v;
}

/// 困难：对评估最好的若干走法做 1 层期望前瞻——枚举对手 21 种掷骰，
/// 假设对手按启发式选最佳回应，取己方评估的加权平均。限时约 1 秒。
List<BgMove> bgLookaheadSequence(BgPos p, int s, List<List<BgMove>> seqs, {int timeMs = 1000, int top = 6}) {
  if (seqs.length == 1) return seqs.first;
  final sw = Stopwatch()..start();
  final o = 1 - s;
  final seen = <String>{};
  final scored = <(List<BgMove>, BgPos, double)>[];
  for (final q in seqs) {
    final r = p.clone();
    for (final m in q) {
      r.apply(s, m);
    }
    if (!seen.add(r.key())) continue;
    scored.add((q, r, bgEvaluate(r, s)));
  }
  scored.sort((a, b) => b.$3.compareTo(a.$3));
  if (scored.isEmpty) return seqs.first;
  var best = scored.first.$1;
  var bestV = double.negativeInfinity;
  for (final (q, r, _) in scored.take(top)) {
    if (r.off(s) == 15) return q;
    var total = 0.0, weight = 0;
    for (var a = 1; a <= 6; a++) {
      for (var b = a; b <= 6; b++) {
        final w = a == b ? 1 : 2;
        final dice = a == b ? [a, a, a, a] : [a, b];
        final reply = bgBestSequence(r, o, r.legalSequences(o, dice));
        final t = r.clone();
        for (final m in reply) {
          t.apply(o, m);
        }
        total += (t.off(o) == 15 ? -10000 : bgEvaluate(t, s)) * w;
        weight += w;
      }
      if (sw.elapsedMilliseconds > timeMs) break;
    }
    if (sw.elapsedMilliseconds > timeMs && weight < 36) break;
    final v = total / weight;
    if (v > bestV) {
      bestV = v;
      best = q;
    }
  }
  return best;
}
