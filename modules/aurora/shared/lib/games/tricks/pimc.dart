import 'dart:math';

import '../../src/engine.dart';
import 'cards.dart';

/// Host for throw-away rollout clones: logs are dropped and scheduled work
/// (trick collection) runs immediately.
class TrInstantHost implements GameHost {
  @override
  void log(String text) {}
  @override
  void Function() schedule(int ms, void Function() fn) {
    fn();
    return () {};
  }
}

/// Suits each seat has publicly shown out of (failed to follow), from the
/// play sequence [seq] (seat, card) in play order, 4 cards per trick.
List<Set<String>> trVoids(List<(int, String)> seq, [int seats = 4]) {
  final v = List.generate(seats, (_) => <String>{});
  for (var i = 0; i < seq.length; i++) {
    final lead = seq[i - i % 4].$2;
    if (i % 4 != 0 && trSuit(seq[i].$2) != trSuit(lead)) v[seq[i].$1].add(trSuit(lead));
  }
  return v;
}

/// Randomly deals [unknown] cards to the seats with need[s] > 0 cards,
/// respecting [voids] (and [fixed] cards known to be in a seat). Returns null
/// when no consistent deal was found; callers then ignore the void info.
List<List<String>>? trSampleDeal(Random rng, List<String> unknown, List<int> need, List<Set<String>> voids,
    {Map<int, List<String>> fixed = const {}}) {
  final n = need.length;
  for (var attempt = 0; attempt < 40; attempt++) {
    final out = List.generate(n, (s) => List.of(fixed[s] ?? const <String>[]));
    final left = [for (var s = 0; s < n; s++) need[s] - out[s].length];
    if (left.any((x) => x < 0)) return null;
    final fixedSet = {for (final l in fixed.values) ...l};
    final cards = [for (final c in unknown) if (!fixedSet.contains(c)) c]..shuffle(rng);
    // most constrained cards first
    int options(String c) => [for (var s = 0; s < n; s++) if (left[s] > 0 && !voids[s].contains(trSuit(c))) s].length;
    cards.sort((a, b) => options(a).compareTo(options(b)));
    var ok = true;
    for (final c in cards) {
      final cand = [for (var s = 0; s < n; s++) if (left[s] > 0 && !voids[s].contains(trSuit(c))) s];
      if (cand.isEmpty) {
        ok = false;
        break;
      }
      // weight by remaining room so the deal stays roughly uniform
      final tot = cand.fold<int>(0, (a, s) => a + left[s]);
      var r = rng.nextInt(tot);
      var pick = cand.first;
      for (final s in cand) {
        r -= left[s];
        if (r < 0) {
          pick = s;
          break;
        }
      }
      out[pick].add(c);
      left[pick]--;
    }
    if (ok) return out;
  }
  return null;
}

/// Perfect-information Monte Carlo over [legal]: for each sampled deal run
/// [rollout] (which returns a score for the candidate card, higher = better)
/// and pick the best average. Bounded by [samples] and [maxMs].
String trPimc(Random rng, List<String> legal, List<List<String>>? Function() sample,
    double Function(List<List<String>> deal, String card) rollout,
    {int samples = 12, int maxMs = 900}) {
  final sw = Stopwatch()..start();
  final total = {for (final c in legal) c: 0.0};
  var done = 0;
  for (var i = 0; i < samples; i++) {
    final deal = sample();
    if (deal == null) continue;
    for (final c in legal) {
      total[c] = total[c]! + rollout(deal, c);
    }
    done++;
    if (sw.elapsedMilliseconds > maxMs) break;
  }
  if (done == 0) return legal[rng.nextInt(legal.length)];
  var best = legal.first;
  for (final c in legal) {
    if (total[c]! > total[best]! + 1e-9) best = c;
  }
  return best;
}
