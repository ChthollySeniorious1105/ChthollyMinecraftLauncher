import '../../src/engine.dart';

/// Small helpers shared by the light party-card engines.
mixin LightLog on GameEngine {
  final List<String> logs = [];

  void say(String s) {
    logs.add(s);
    if (logs.length > 40) logs.removeAt(0);
    host.log(s);
  }

  List<String> recentLogs([int n = 12]) => logs.length > n ? logs.sublist(logs.length - n) : List.of(logs);
}

/// Placings from a "survival" order: [outOrder][s] = 0 while still in, else the
/// k-th player knocked out (1 = first out). Survivors share 1st; the last
/// knocked out is next, etc.
List<int> placingsFromElimination(List<int> outOrder) {
  final n = outOrder.length;
  return [
    for (var i = 0; i < n; i++)
      outOrder[i] == 0 ? 1 : 1 + [for (var j = 0; j < n; j++) j].where((j) => outOrder[j] == 0 || outOrder[j] > outOrder[i]).length,
  ];
}
