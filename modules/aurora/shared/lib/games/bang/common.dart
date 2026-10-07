import '../../src/engine.dart';

/// Chat/log helper shared by the bang package engines.
mixin BangLog on GameEngine {
  final List<String> logs = [];

  void say(String s) {
    logs.add(s);
    if (logs.length > 40) logs.removeAt(0);
    host.log(s);
  }

  List<String> recentLogs([int n = 12]) => logs.length > n ? logs.sublist(logs.length - n) : List.of(logs);
}
