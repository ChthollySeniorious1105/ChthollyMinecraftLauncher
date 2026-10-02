import 'dart:math';

import '../../src/engine.dart';

/// Small helpers shared by the dice2 engines.

/// Face counts, index 0 unused (1..6).
List<int> d2Counts(Iterable<int> dice) {
  final c = List.filled(7, 0);
  for (final d in dice) {
    if (d >= 1 && d <= 6) c[d]++;
  }
  return c;
}

int d2Roll(Random rng) => rng.nextInt(6) + 1;

/// Parse a list of distinct in-range indices; throws GameError on junk.
List<int> d2Indices(Object? raw, int length, {String what = '骰子'}) {
  if (raw is! List) throw GameError('请选择$what');
  final out = <int>[];
  for (final e in raw) {
    final i = asInt(e);
    if (i < 0 || i >= length) throw GameError('无效的$what');
    if (out.contains(i)) throw GameError('重复选择了$what');
    out.add(i);
  }
  return out;
}

/// Parse a hold mask of exactly [length] bools (junk -> false).
List<bool> d2Mask(Object? raw, int length) {
  if (raw is! List || raw.length != length) {
    if (raw == null) return List.filled(length, false);
    throw GameError('保留骰子参数无效');
  }
  return [for (final e in raw) e == true];
}

/// Binomial tail P(X >= k), X ~ Bin(n, p).
double d2BinomAtLeast(int n, double p, int k) {
  if (k <= 0) return 1;
  if (k > n) return 0;
  var total = 0.0;
  for (var i = k; i <= n; i++) {
    total += _choose(n, i) * pow(p, i) * pow(1 - p, n - i);
  }
  return total.clamp(0.0, 1.0);
}

double _choose(int n, int k) {
  var r = 1.0;
  for (var i = 1; i <= k; i++) {
    r = r * (n - k + i) / i;
  }
  return r;
}

/// Placings for games where some seats may have left (认输/出局).
/// Seats still in play rank by [scores] (higher better, ties share); seats in
/// [outOrder] (earliest first) rank below them, later exits ranking better.
/// [winner] >= 0 forces that seat to be 1st (e.g. last player standing).
List<int> d2Placings(List<num> scores, List<int> outOrder, {int winner = -1}) {
  final n = scores.length;
  final alive = [for (var s = 0; s < n; s++) if (!outOrder.contains(s)) s];
  final r = List.filled(n, n);
  for (final s in alive) {
    if (s == winner) {
      r[s] = 1;
      continue;
    }
    var better = 0;
    for (final o in alive) {
      if (o == s) continue;
      if (o == winner || (o != winner && scores[o] > scores[s])) better++;
    }
    r[s] = 1 + better;
  }
  for (var i = 0; i < outOrder.length; i++) {
    r[outOrder[i]] = alive.length + (outOrder.length - i);
  }
  return r;
}

/// Bounded log kept in views.
class D2Log {
  final List<String> lines = [];
  final GameHost Function() host;
  D2Log(this.host);
  void add(String s, {bool chat = true}) {
    lines.add(s);
    if (lines.length > 40) lines.removeAt(0);
    if (chat) host().log(s);
  }

  List<String> tail([int n = 12]) => lines.length > n ? lines.sublist(lines.length - n) : List.of(lines);
}
