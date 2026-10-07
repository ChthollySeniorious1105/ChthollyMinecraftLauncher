/// Small helpers shared by the arcade2 engines (private copy of the arcade
/// package's helpers so the packages stay independent).
library;

/// Sorts seats 0..n-1 with [cmp] (negative = a ranks better) and assigns
/// competition ranks (ties share a rank). [extra] adds per-seat fields.
List<Map<String, dynamic>> a2Ranking(
    int n, int Function(int a, int b) cmp, Map<String, dynamic> Function(int s) extra) {
  final order = [for (var s = 0; s < n; s++) s]..sort((a, b) {
      final c = cmp(a, b);
      return c != 0 ? c : a - b;
    });
  final out = <Map<String, dynamic>>[];
  var rank = 0;
  for (var i = 0; i < order.length; i++) {
    if (i == 0 || cmp(order[i], order[i - 1]) != 0) rank = i + 1;
    out.add({'s': order[i], 'rank': rank, ...extra(order[i])});
  }
  return out;
}

/// Rotates [seats] so that element `k % length` comes first (the simulator
/// only lets the first bot in waitingFor act per step).
List<int> a2Rotated(List<int> seats, int k) {
  if (seats.length < 2) return seats;
  final i = k % seats.length;
  return [...seats.sublist(i), ...seats.sublist(0, i)];
}

/// Winners' names for a log line.
String a2Winners(List<Map<String, dynamic>> ranking, String Function(int) name) =>
    [for (final r in ranking) if (r['rank'] == 1) name(r['s'] as int)].join('、');

/// Per-seat placings from an [a2Ranking] result.
List<int>? a2Placings(List<Map<String, dynamic>>? ranking, int n) {
  if (ranking == null) return null;
  final out = List<int>.filled(n, n);
  for (final r in ranking) {
    out[r['s'] as int] = r['rank'] as int;
  }
  return out;
}

/// Cheap deterministic integer hash (bot timing decisions that must not be
/// stored in game state).
int a2Hash(int a, [int b = 0, int c = 0, int d = 0]) {
  var h = 0x2545F491;
  for (final v in [a, b, c, d]) {
    h ^= v & 0x7fffffff;
    h = (h * 0x9E3779B1) & 0x7fffffff;
    h ^= h >> 15;
  }
  return h & 0x7fffffff;
}
