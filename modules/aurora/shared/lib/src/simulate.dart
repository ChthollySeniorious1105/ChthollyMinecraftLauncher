import 'dart:convert';
import 'dart:math';

import 'ai.dart';
import 'engine.dart';

/// Host used by the simulator: runs scheduled callbacks immediately (in order).
class SimHost implements GameHost {
  final List<String> logs = [];
  final List<void Function()> _queue = [];
  final bool verbose;
  SimHost({this.verbose = false});

  @override
  void log(String text) {
    logs.add(text);
    if (verbose) print('  [log] $text');
  }

  @override
  void Function() schedule(int ms, void Function() fn) {
    var cancelled = false;
    _queue.add(() {
      if (!cancelled) fn();
    });
    return () => cancelled = true;
  }

  bool runPending() {
    if (_queue.isEmpty) return false;
    final q = List.of(_queue);
    _queue.clear();
    for (final f in q) {
      f();
    }
    return true;
  }
}

class SimResult {
  final bool finished;
  final int steps;
  final String? error;
  final List<String> logs;
  SimResult(this.finished, this.steps, this.error, this.logs);
  @override
  String toString() => finished ? 'finished in $steps steps' : 'NOT finished after $steps steps: $error';
}

/// Plays one full game with every seat controlled by [GameEngine.bot].
/// Verifies after every step that every seat's view is JSON-encodable.
SimResult simulate(GameDef def, int players,
    {Map<String, dynamic>? options, int seed = 1, int maxSteps = 20000, bool verbose = false, int botLevel = 1}) {
  final opts = def.normalizeOptions(options);
  final setup = GameSetup(
    players: players,
    options: opts,
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: List.filled(players, true),
    hostSeat: 0,
    rng: Random(seed),
    botLevel: botLevel,
    ai: FakeAi(seed),
    botRng: Random(seed * 7919 + 13),
  );
  final log = <(int, Map<String, dynamic>)>[];
  final e = def.create(setup);
  final host = SimHost(verbose: verbose);
  e.host = host;
  var steps = 0;
  try {
    e.start();
    host.runPending();
    while (!e.isOver && steps < maxSteps) {
      for (var s = -1; s < players; s++) {
        jsonEncode(e.view(s));
      }
      final waiting = e.waitingFor;
      if (waiting.isEmpty) {
        if (!host.runPending()) {
          return SimResult(false, steps, 'deadlock: nobody waiting and no scheduled work', host.logs);
        }
        continue;
      }
      var acted = false;
      for (final s in waiting) {
        final a = e.runBot(s);
        if (a == null) continue;
        if (verbose) print('seat $s -> ${jsonEncode(a)}');
        // actions travel as JSON on the wire: make sure they survive it
        final wire = jsonDecode(jsonEncode(a)) as Map<String, dynamic>;
        e.handle(s, wire);
        log.add((s, wire));
        acted = true;
        steps++;
        break; // re-evaluate waitingFor after every action
      }
      final ran = host.runPending();
      if (!acted && !ran) {
        return SimResult(false, steps, 'stuck: waiting for $waiting but bots return null', host.logs);
      }
    }
    for (var s = -1; s < players; s++) {
      jsonEncode(e.view(s));
    }
    if (e.isOver) {
      final r = e.placings;
      if (r == null || r.length != players || r.any((x) => x < 1 || x > players) || !r.contains(1)) {
        return SimResult(false, steps, 'bad placings $r', host.logs);
      }
      if (def.undo) {
        final err = verifyUndoReplay(def, setup, seed, log, e);
        if (err != null) return SimResult(false, steps, err, host.logs);
      }
    }
  } catch (err, st) {
    return SimResult(false, steps, '$err\n$st', host.logs);
  }
  return SimResult(e.isOver, steps, e.isOver ? null : 'step limit', host.logs);
}

/// Rebuilds a game from its seed + action log and checks it ends in the same
/// state (requirement for [GameDef.undo]).
String? verifyUndoReplay(GameDef def, GameSetup setup, int seed, List<(int, Map<String, dynamic>)> log, GameEngine original) {
  final e2 = rebuildEngine(def, setup.copyWith(rng: Random(seed)), log);
  for (var s = -1; s < setup.players; s++) {
    if (jsonEncode(e2.view(s)) != jsonEncode(original.view(s))) {
      return 'undo replay mismatch for seat $s: rebuilding from the action log gives a different view';
    }
  }
  return null;
}

/// New engine from [setup], started, with [log] re-applied (scheduled callbacks
/// run instantly). Used by the server for 悔棋.
GameEngine rebuildEngine(GameDef def, GameSetup setup, List<(int, Map<String, dynamic>)> log) {
  final e = def.create(setup);
  final host = SimHost();
  e.host = host;
  e.start();
  host.runPending();
  for (final (s, a) in log) {
    e.handle(s, a);
    host.runPending();
  }
  return e;
}

/// Plays [n] bot games for every player count and every single-option variation
/// of each def. Prints a report and returns the number of failures.
int runSims(List<GameDef> defs, {int n = 20, bool verbose = false, int maxSteps = 20000}) {
  var failures = 0;
  for (final def in defs) {
    if (def.rules.trim().length < 150) {
      failures++;
      print('FAIL ${def.id}: GameDef.rules 规则说明缺失或太短（至少 150 字）');
    }
    final combos = <Map<String, dynamic>>[def.defaultOptions()];
    for (final o in def.options) {
      for (final c in o.choices) {
        if (c.value != o.defaultValue) combos.add({...def.defaultOptions(), o.key: c.value});
      }
    }
    for (final opts in combos) {
      final (lo, hi) = def.playerRange(opts);
      for (var p = lo; p <= hi; p++) {
        var done = 0, totalSteps = 0;
        for (var seed = 1; seed <= n; seed++) {
          final r = simulate(def, p, options: opts, seed: seed, verbose: verbose, maxSteps: maxSteps);
          if (r.finished) {
            done++;
            totalSteps += r.steps;
          } else {
            failures++;
            print('FAIL ${def.id} p=$p opts=$opts seed=$seed: ${r.error}');
            final tail = r.logs.length > 8 ? r.logs.sublist(r.logs.length - 8) : r.logs;
            for (final l in tail) {
              print('    log: $l');
            }
            break;
          }
        }
        print('${def.id} p=$p opts=$opts: $done/$n ok, avg steps ${done == 0 ? 0 : totalSteps ~/ done}');
        if (identical(opts, combos.first)) {
          // bot difficulty levels 简单 / 困难 must work too
          for (final lvl in const [0, 2]) {
            for (var seed = 1; seed <= 3; seed++) {
              final r = simulate(def, p, options: opts, seed: seed, maxSteps: maxSteps, botLevel: lvl);
              if (!r.finished) {
                failures++;
                print('FAIL ${def.id} p=$p botLevel=$lvl seed=$seed: ${r.error}');
                break;
              }
            }
          }
        }
      }
    }
  }
  print(failures == 0 ? 'ALL OK' : '$failures FAILURES');
  return failures;
}
