// Robustness / security fuzzing for every game engine.
//
// A malicious client can send any JSON object as an action. For every game in
// [gameRegistry] this plays bot games and, at many points, injects malformed
// actions from random seats. It asserts that:
//  * handle() either succeeds or throws GameError (nothing else),
//  * a rejected action leaves the state untouched (views unchanged),
//  * no single action takes excessively long (DoS),
//  * views stay JSON-encodable and the bots can still finish the game.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

/// Packages being edited concurrently by others; not fuzzed here.
const skipIds = {'bigtwo', 'zhajinhua', 'douniu', 'shisanshui', 'carcassonne', 'hanabi'};

class Fuzzer {
  final Random r;
  final Set<String> vocab = {'type', 'a', 'kind', 'action', 'op', 'move', 'card', 'cards', 'tile',
    'index', 'i', 'x', 'y', 'from', 'to', 'target', 'seat', 'text', 'word', 'n', 'value', 'id',
    'amount', 'bid', 'choice', 'pos', 'color', 'suit', 'rank', 'play', 'pass', 'ready', 'next'};
  final Set<String> keys = {'type', 'a', 'kind', 'action', 'op'};
  Fuzzer(this.r);

  void learn(Object? v, {int depth = 0}) {
    if (depth > 6 || vocab.length > 600) return;
    if (v is String) {
      if (v.length <= 24) vocab.add(v);
    } else if (v is Map) {
      v.forEach((k, x) {
        if (k is String && k.length <= 24) vocab.add(k);
        learn(x, depth: depth + 1);
      });
    } else if (v is List) {
      for (final x in v.take(20)) {
        learn(x, depth: depth + 1);
      }
    }
  }

  void learnAction(Map<String, dynamic> a) {
    keys.addAll(a.keys);
    learn(a);
  }

  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
  String word() => pick(vocab.toList());

  Object? scalar() {
    switch (r.nextInt(14)) {
      case 0:
        return pick<int>([-1, 0, 1, 2, 3, 1 << 31, -(1 << 31), 1000000000, 1 << 53, 0x7fffffffffffffff, -0x7fffffffffffffff]);
      case 1:
      case 2:
        return r.nextInt(60) - 5;
      case 3:
        return pick<double>([0.5, -0.0, 1.5, 3.0, 1e308, -1e308, double.infinity, double.negativeInfinity, 2.0]);
      case 4:
      case 5:
        return word();
      case 6:
        return pick<String>(['', 'x' * 10000, '\u202e evil \u2066\u200b', 'a\u0000b\n\r\t', '3', '-1', '1e9',
          '你好' * 300, '😀', '99999999999999999999', ' ', 'null']);
      case 7:
        return null;
      case 8:
        return r.nextBool();
      case 9:
        return <dynamic>[];
      case 10:
        return <dynamic>[for (var i = 0; i < r.nextInt(6); i++) r.nextInt(80) - 3];
      case 11:
        return pick([
          <dynamic>[for (var i = 0; i < 20000; i++) i % 50],
          <dynamic>[for (var i = 0; i < 20000; i++) 'x'],
          <dynamic>[for (var i = 0; i < 3000; i++) <dynamic>[i, i]],
        ]);
      case 12:
        return <dynamic>[for (var i = 0; i < r.nextInt(5); i++) scalar()];
      default:
        return <String, dynamic>{for (var i = 0; i < r.nextInt(4); i++) word(): scalar()};
    }
  }

  Object? tweak(Object? v) {
    if (v is int && r.nextBool()) {
      return pick<Object>([v + 1, v - 1, -v - 1, v + 1000, v * 1000, v.toDouble(), '$v', 1 << 40]);
    }
    if (v is List && v.isNotEmpty && r.nextBool()) {
      final l = <dynamic>[...v];
      switch (r.nextInt(5)) {
        case 0:
          l.add(l.first);
        case 1:
          l.removeLast();
        case 2:
          l[r.nextInt(l.length)] = scalar();
        case 3:
          l.addAll([for (var i = 0; i < 50; i++) l.first]);
        default:
          l[r.nextInt(l.length)] = tweak(l[r.nextInt(l.length)]);
      }
      return l;
    }
    if (v is Map<String, dynamic> && v.isNotEmpty && r.nextBool()) {
      return mutate(v);
    }
    return scalar();
  }

  Map<String, dynamic> mutate(Map<String, dynamic> a) {
    final m = <String, dynamic>{...a};
    final n = 1 + r.nextInt(2);
    for (var i = 0; i < n; i++) {
      switch (r.nextInt(5)) {
        case 0:
          if (m.isNotEmpty) m.remove(pick(m.keys.toList()));
        case 1:
          m[word()] = scalar();
        default:
          if (m.isNotEmpty) {
            final k = pick(m.keys.toList());
            m[k] = tweak(m[k]);
          } else {
            m[pick(keys.toList())] = scalar();
          }
      }
    }
    return m;
  }

  Map<String, dynamic> random() {
    final m = <String, dynamic>{};
    if (r.nextInt(5) != 0) m[pick(keys.toList())] = word();
    for (var i = 0; i < r.nextInt(4); i++) {
      m[r.nextBool() ? pick(keys.toList()) : word()] = scalar();
    }
    return m;
  }
}

/// Wall-clock fields that legitimately change between two identical views.
const volatileKeys = {'now'};

String snap(GameEngine e, Iterable<int> seats) => jsonEncode([
      for (final s in seats) {for (final en in e.view(s).entries) if (!volatileKeys.contains(en.key)) en.key: en.value}
    ]);

/// Action vocabulary harvested from the engine package source of [id]:
/// `case '...'`, `== '...'` literals and `a['key']` style keys.
final _srcVocab = <String, (Set<String>, Set<String>)>{};
(Set<String>, Set<String>) sourceVocab(String id) => _srcVocab.putIfAbsent(id, () {
      final words = <String>{}, keys = <String>{};
      final root = Directory('lib/games');
      if (!root.existsSync()) return (words, keys);
      for (final dir in root.listSync().whereType<Directory>()) {
        final defs = File('${dir.path}/defs.dart');
        if (!defs.existsSync() || !defs.readAsStringSync().contains("id: '$id'")) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
          final src = f.readAsStringSync();
          for (final m in RegExp(r"(?:case|==|!=|contains\()\s*'([A-Za-z0-9_]{1,20})'").allMatches(src)) {
            words.add(m.group(1)!);
          }
          for (final m in RegExp(r"(?:^|[^A-Za-z0-9_])(?:a|action|c|p)\['([A-Za-z0-9_]{1,20})'\]").allMatches(src)) {
            keys.add(m.group(1)!);
          }
        }
      }
      return (words, keys);
    });

/// Result problems for one game run.
List<String> fuzzGame(GameDef def, int players, Map<String, dynamic> opts, int seed,
    {int bursts = 12, int perBurst = 60, int maxSteps = 20000}) {
  final problems = <String>[];
  final rng = Random(seed * 7919 + players);
  final f = Fuzzer(rng);
  final (sw0, sk0) = sourceVocab(def.id);
  f.vocab.addAll(sw0);
  f.vocab.addAll(sk0);
  f.keys.addAll(sk0);
  final setup = GameSetup(
    players: players,
    options: def.normalizeOptions(opts),
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: List.filled(players, true),
    hostSeat: 0,
    rng: Random(seed),
  );
  final e = def.create(setup);
  final host = SimHost();
  e.host = host;
  final tag = '${def.id} p=$players opts=$opts seed=$seed';
  final allSeats = [for (var s = -1; s < players; s++) s];
  e.start();
  host.runPending();

  // Estimate game length first with a twin game so bursts are spread out.
  final est = simulate(def, players, options: opts, seed: seed, maxSteps: maxSteps);
  final total = max(1, est.steps);
  final burstAt = <int>{for (var i = 0; i < bursts; i++) (total * i) ~/ bursts};
  burstAt.add(0);

  var steps = 0;
  final sw = Stopwatch();
  void burst() {
    for (var s = -1; s < players; s++) {
      f.learn(e.view(s));
    }
    final waiting = e.waitingFor;
    final botActs = <int, Map<String, dynamic>>{};
    for (final s in waiting) {
      final a = e.bot(s);
      if (a != null) {
        botActs[s] = a;
        f.learnAction(a);
      }
    }
    var before = snap(e, allSeats);
    for (var i = 0; i < perBurst && !e.isOver; i++) {
      final waitingNow = e.waitingFor.toList();
      final seat = waitingNow.isNotEmpty && rng.nextBool()
          ? waitingNow[rng.nextInt(waitingNow.length)]
          : rng.nextInt(players);
      Map<String, dynamic> a;
      final roll = rng.nextInt(10);
      if (botActs.isNotEmpty && roll < 6) {
        final base = botActs.values.elementAt(rng.nextInt(botActs.length));
        a = roll == 0 ? {...base} : f.mutate(base);
      } else {
        a = f.random();
      }
      sw
        ..reset()
        ..start();
      var ok = false;
      try {
        e.handle(seat, a);
        ok = true;
      } on GameError {
        // expected
      } catch (err, st) {
        final s = st.toString().split('\n').take(4).join(' | ');
        problems.add('$tag: seat $seat action ${_short(a)} threw ${err.runtimeType}: $err @ $s');
        return;
      }
      sw.stop();
      if (sw.elapsedMilliseconds > 300) {
        problems.add('$tag: seat $seat action ${_short(a)} took ${sw.elapsedMilliseconds}ms');
      }
      if (ok) host.runPending();
      String after;
      try {
        after = snap(e, allSeats);
      } catch (err) {
        problems.add('$tag: view not encodable after ${_short(a)}: $err');
        return;
      }
      if (ok) {
        if (!waitingNow.contains(seat)) {
          // Accepted from a seat that was not being waited on: note for review.
          outOfTurn.add('${def.id}: seat $seat not in $waitingNow accepted ${_short(a)}');
        }
        before = after;
        // State changed: refresh bot actions.
        botActs.clear();
        for (final s in e.waitingFor) {
          final b = e.bot(s);
          if (b != null) botActs[s] = b;
        }
      } else if (after != before) {
        problems.add('$tag: rejected action ${_short(a)} from seat $seat mutated state');
        return;
      }
    }
  }

  try {
    while (!e.isOver && steps < maxSteps) {
      if (burstAt.remove(steps)) {
        burst();
        if (problems.isNotEmpty) return problems;
        continue;
      }
      final waiting = e.waitingFor;
      if (waiting.isEmpty) {
        if (!host.runPending()) {
          problems.add('$tag: deadlock after fuzzing at step $steps');
          return problems;
        }
        continue;
      }
      var acted = false;
      for (final s in waiting) {
        final a = e.bot(s);
        if (a == null) continue;
        e.handle(s, a);
        acted = true;
        steps++;
        break;
      }
      final ran = host.runPending();
      if (!acted && !ran) {
        problems.add('$tag: stuck after fuzzing, waiting for $waiting');
        return problems;
      }
    }
    for (final s in allSeats) {
      jsonEncode(e.view(s));
    }
  } catch (err, st) {
    problems.add('$tag: bot game broke after fuzzing at step $steps: $err\n$st');
    return problems;
  }
  if (!e.isOver) problems.add('$tag: did not finish after fuzzing ($steps steps)');
  return problems;
}

final outOfTurn = <String>{};

String _short(Object? a) {
  String s;
  try {
    s = jsonEncode(a);
  } catch (_) {
    s = a.toString();
  }
  return s.length > 160 ? '${s.substring(0, 160)}…(${s.length})' : s;
}

List<Map<String, dynamic>> optionCombos(GameDef def) {
  final combos = <Map<String, dynamic>>[def.defaultOptions()];
  for (final o in def.options) {
    for (final c in o.choices) {
      if (c.value != o.defaultValue) combos.add({...def.defaultOptions(), o.key: c.value});
    }
  }
  return combos;
}

// ---------------------------------------------------------------------------
// Hidden-information checks. For each game a checker compares engine secrets
// (read through public engine fields) with view(seat) for every seat
// including the spectator (-1), at every step of a bot game.

typedef LeakCheck = void Function(dynamic e, int seat, Map<String, dynamic> v, void Function(bool ok, String what) expectOk);

List<String> leakRun(String id, int players, LeakCheck check, {Map<String, dynamic>? options, int seed = 1, int maxSteps = 4000}) {
  final def = findGame(id)!;
  final e = def.create(GameSetup(
    players: players,
    options: def.normalizeOptions(options),
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: List.filled(players, true),
    hostSeat: 0,
    rng: Random(seed),
  ));
  final host = SimHost();
  e.host = host;
  e.start();
  host.runPending();
  final problems = <String>[];
  var steps = 0;
  void checkAll() {
    for (var s = -1; s < players; s++) {
      // round-trip through JSON: that is exactly what the client receives
      final v = jsonDecode(jsonEncode(e.view(s))) as Map<String, dynamic>;
      check(e, s, v, (ok, what) {
        if (!ok && problems.length < 5) problems.add('$id p=$players seed=$seed step $steps seat $s: $what');
      });
    }
  }

  checkAll();
  while (!e.isOver && steps < maxSteps && problems.isEmpty) {
    final w = e.waitingFor;
    Map<String, dynamic>? a;
    int? who;
    for (final s in w) {
      a = e.bot(s);
      if (a != null) {
        who = s;
        break;
      }
    }
    if (a != null) {
      e.handle(who!, a);
      steps++;
      // check before timers fire too (e.g. reaction windows the simulator
      // would otherwise close instantly)
      checkAll();
    }
    final ran = host.runPending();
    if (a == null && !ran) break;
    checkAll();
  }
  return problems;
}

bool _isBackOrNull(Object? x) => x == null || x == 'back';
bool _noOthers(Object? list, int seat) => list is List && list.every((x) => x == seat);
String _j(Object? o) => jsonEncode(o);

final Map<String, (int, LeakCheck)> leakChecks = {
  'doudizhu': (3, (e, s, v, ok) {
    ok(_j(v['hand']) == _j(s >= 0 ? e.hands[s] : []), 'own hand only');
    if (e.phase == 'bid' || e.phase == 'play') ok(v['hands'] == null, 'all hands shown mid-round');
    if (e.landlord < 0) ok(v['bottom'] == null, 'bottom shown before landlord');
  }),
  'paodekuai': (3, (e, s, v, ok) {
    if (e.phase == 'play') ok(v['hands'] == null, 'all hands shown mid-round');
    if (s < 0) ok((v['hand'] as List).isEmpty, 'spectator sees a hand');
  }),
  'guandan': (4, (e, s, v, ok) {
    if (e.phase != 'dealEnd' && e.phase != 'over') ok(v['hands'] == null, 'all hands shown mid-deal');
    if (s < 0) ok((v['hand'] as List).isEmpty, 'spectator sees a hand');
  }),
  'shengji': (4, (e, s, v, ok) {
    final allowed = (s >= 0 && s == e.banker && e.phase == 'bury') || e.phase == 'dealEnd' || e.phase == 'over';
    if (!allowed) ok(v['bottom'] == null, 'kitty visible');
    if (s < 0) ok((v['hand'] as List).isEmpty, 'spectator sees a hand');
  }),
  'texasholdem': (5, (e, s, v, ok) {
    final holes = v['holes'] as List;
    for (var o = 0; o < e.players; o++) {
      if (o == s || e.shown[o] == true) continue;
      ok((holes[o] as List).every(_isBackOrNull), 'hole cards of seat $o visible');
    }
  }),
  'blackjack': (3, (e, s, v, ok) {
    if (e.dealerHidden == true && (e.dealer as List).length >= 2) ok((v['dealer'] as List)[1] == 'back', 'dealer hole card');
  }),
  'uno': (4, (e, s, v, ok) {
    final mine = s >= 0 ? (e.hands[s] as List).toSet() : <Object?>{};
    ok((v['hand'] as List).every((c) => mine.contains((c as Map)['id'])), 'hand contains foreign cards');
  }),
  'rummikub': (3, (e, s, v, ok) {
    ok(_j(v['rack']) == _j(s >= 0 ? e.racks[s] : []), 'rack is not own rack');
    if (e.over != true) ok(v['racks'] == null, 'racks visible');
  }),
  'cabo': (3, (e, s, v, ok) {
    if (e.phase == 'roundEnd' || e.phase == 'over') return;
    final grid = v['grid'] as List;
    for (var o = 0; o < e.players; o++) {
      final row = grid[o] as List;
      for (var i = 0; i < row.length; i++) {
        if (row[i] != -1) ok(s >= 0 && (e.known[s][o] as Set).contains(i), 'cabo card $o/$i visible');
      }
    }
    if (s < 0) ok(v['drawn'] == null && v['reveal'] == null, 'spectator sees drawn/reveal');
  }),
  'explodingkittens': (4, (e, s, v, ok) {
    ok(_noOthers(v['nopers'], s), 'nopers exposes who holds Nope');
    if (s < 0) ok(v['future'] == null && (v['hand'] as List).isEmpty, 'spectator private info');
    if (e.phase != 'over') ok(v['hands'] == null, 'hands visible');
  }),
  'loveletter': (4, (e, s, v, ok) {
    ok(_j(v['hand']) == _j(s >= 0 ? e.hands[s] : []), 'hand is not own hand');
    if (s < 0) ok((v['priv'] as List? ?? const []).isEmpty, 'spectator private log');
  }),
  'liarsbar': (4, (e, s, v, ok) {
    ok(_j(v['hand']) == _j(s >= 0 ? e.hands[s] : []), 'hand is not own hand');
    if (e.phase == 'play') ok(v['allDice'] == null, 'all dice visible');
    ok(!_j(v).contains('"bullet"'), 'revolver chamber exposed');
  }),
  'splendor': (3, (e, s, v, ok) {
    if (e.phase == 'over') return;
    final ps = v['ps'] as List;
    for (var o = 0; o < e.players; o++) {
      if (o == s) continue;
      final res = (ps[o] as Map)['reserved'] as List;
      final real = e.ps[o].reserved as List;
      for (var i = 0; i < res.length; i++) {
        if (!(e.ps[o].reservedPublic as Set).contains(real[i])) ok((res[i] as Map)['id'] == -1, 'blind reserve of $o visible');
      }
    }
  }),
  'davinci': (3, (e, s, v, ok) {
    if (e.isOver) return;
    final hs = v['hands'] as List;
    for (var o = 0; o < e.players; o++) {
      if (o == s) continue;
      final h = e.hand[o] as List;
      for (var i = 0; i < h.length; i++) {
        if (!(e.revealed as Set).contains(h[i])) ok(((hs[o] as List)[i] as Map)['v'] == null, 'tile $o/$i value visible');
      }
    }
  }),
  'battleship': (2, (e, s, v, ok) {
    if (!e.isOver) ok(v['planes'] == null, 'all planes visible');
    if (s < 0) ok(v['mine'] == null, 'spectator sees a layout');
  }),
  'junqi': (2, (e, s, v, ok) {
    if (e.phase != 1) return;
    final cells = v['board'] as List;
    for (var i = 0; i < cells.length; i++) {
      final p = e.b[i];
      if (p == null || p.up == true) continue;
      if (s >= 0 && e.team(p.owner) == e.team(s)) continue;
      ok((cells[i] as Map)['k'] == -1, 'hidden piece rank at $i visible');
    }
  }),
  'jieqi': (2, (e, s, v, ok) {
    final b = v['board'] as List;
    for (var i = 0; i < 90; i++) {
      if (e.pos.hidden[i] == true) ok((b[i] as int).abs() == 8, 'face-down piece identity at $i');
    }
  }),
  'werewolf': (9, (e, s, v, ok) {
    if (e.isOver) return;
    final roles = v['roles'] as List;
    final iWolf = s >= 0 && e.isWolfSeat(s) == true;
    for (var o = 0; o < e.players; o++) {
      if (o == s || (e.revealed as Map).containsKey(o) || (iWolf && e.isWolfSeat(o) == true)) continue;
      ok(roles[o] == null, 'role of seat $o visible');
    }
    if (s < 0 || e.roles[s] != 'seer') ok((v['checks'] as List).isEmpty, 'seer checks visible');
    if (s < 0) ok((v['private'] as List).isEmpty && v['myRole'] == null && v['night'] == null, 'spectator private info');
    // the night waiting list must not single out the witch (server publishes per-seat clocks)
    if (e.phase == 'night' && e.wolfKill == -2) {
      for (var o = 0; o < e.players; o++) {
        if (e.roles[o] == 'witch' && e.alive[o] == true && e.nightDone(o) != true) {
          ok((e.waitingFor as List).contains(o), 'witch hidden from waitingFor at night');
        }
      }
    }
  }),
  'avalon': (7, (e, s, v, ok) {
    if (e.isOver) return;
    ok(v['roles'] == null, 'roles visible');
    ok(v['myRole'] == (s >= 0 ? e.roles[s] : null), 'myRole wrong');
    if (s < 0) ok((v['known'] as Map).isEmpty && v['myCard'] == null && v['myVote'] == null, 'spectator private info');
  }),
  'codenames': (6, (e, s, v, ok) {
    if (e.phase == 'over' || (s >= 0 && (e.spymaster as List).contains(s))) return;
    final key = v['key'] as List;
    for (var i = 0; i < 25; i++) {
      if (e.revealed[i] != true) ok(key[i] == -1, 'key card $i visible to operative/spectator');
    }
    ok(!v.containsKey('intended') && !v.containsKey('_targets'), 'bot targets exposed');
  }),
  'undercover': (6, (e, s, v, ok) {
    if (e.isOver || (s >= 0 && s == e.gm)) return;
    ok(v['civWord'] == null && v['spyWord'] == null && v['words'] == null, 'words visible');
    if (s < 0) ok(v['myWord'] == null && v['myRole'] == null, 'spectator sees a word');
  }),
  'decrypto': (6, (e, s, v, ok) {
    if (e.isOver) return;
    final t = e.teamOf(s) as int;
    final kw = v['keywords'] as List;
    for (var i = 0; i < 2; i++) {
      if (i != t) ok(kw[i] == null, 'team $i keywords visible');
    }
    if (t < 0 || s != e.encryptor(t)) ok(v['myCode'] == null, 'code visible to non-encryptor');
  }),
  'bullscows': (3, (e, s, v, ok) {
    if (e.isOver) return;
    final sec = v['secrets'] as List;
    for (var o = 0; o < e.players; o++) {
      if (o != s && e.alive[o] == true) ok(sec[o] == null, 'secret of $o visible');
    }
  }),
  'drawguess': (4, (e, s, v, ok) {
    final full = s >= 0 && (s == e.drawer || s == e.gm);
    if (!full && e.phase != 'reveal' && e.phase != 'over') ok(v['word'] == null && v['wordCat'] == null, 'answer visible');
    if (!(s >= 0 && s == e.drawer)) ok(v['choices'] == null, 'word choices visible');
    if (!full && e.phase == 'draw') {
      for (final f in v['feed'] as List) {
        final m = f as Map;
        if (m['k'] != 'guess' && m['s'] != s) ok(m['t'] == null, 'correct/close guess text visible');
      }
    }
  }),
  'turtlesoup': (4, (e, s, v, ok) {
    final story = v['story'] as Map?;
    if (s != e.gm && e.phase != 'reveal' && e.phase != 'over') ok(story == null || !story.containsKey('bottom'), 'soup bottom visible');
  }),
  'catan': (4, (e, s, v, ok) {
    if (e.phase == 'over') return;
    if (s < 0) ok((v['dev'] as List).isEmpty && (v['devNew'] as List).isEmpty, 'spectator sees dev cards');
    for (final p in v['players'] as List) {
      ok(!(p as Map).containsKey('dev'), 'dev cards of others visible');
    }
  }),
  'bridge': (4, (e, s, v, ok) {
    ok(_j(v['hand']) == _j(s >= 0 ? e.hands[s] : []), 'hand is not own hand');
    if (e.dummyShown != true) ok(v['dummyHand'] == null, 'dummy shown before opening lead');
    if (e.phase != 'dealEnd' && e.phase != 'over') ok(v['allHands'] == null, 'all hands visible');
  }),
  'hearts': (4, (e, s, v, ok) {
    ok(_j(v['hand']) == _j(s >= 0 ? e.hands[s] : []), 'hand is not own hand');
    if (s < 0) ok(v['myPass'] == null && (v['received'] as List).isEmpty, 'spectator sees passes');
    if (e.phase == 'pass') ok((v['received'] as List).isEmpty, 'received cards before pass completes');
  }),
  'spades': (4, (e, s, v, ok) {
    ok((v['hand'] as List).isEmpty || (s >= 0 && _j(v['hand']) == _j(e.hands[s])), 'hand is not own hand');
  }),
};

/// Mahjong family: other seats' concealed hands, concealed kongs, claim windows.
LeakCheck mahjongCheck({required bool riichi, bool sichuan = false}) => (e, s, v, ok) {
      final seats = v['seats'] as List;
      if (riichi) {
        if (e.phase == 'result' || e.isOver) return;
        for (var o = 0; o < e.players; o++) {
          if (o == s) continue;
          final p = e.ps[o];
          if (p.won == true && e.rules.bloodbath == true) continue;
          final hand = ((seats[o] as Map)['hand'] as List).cast<String>();
          final glass = [for (final id in p.hand as List<int>) if (e.isGlass(id) == true) id].length;
          final shown = hand.where((c) => c != 'back').length;
          ok(hand.every((c) => c == 'back' || c.startsWith('G')) && shown <= glass, 'riichi hand of $o visible');
          final d = (seats[o] as Map)['drawn'];
          ok(d == null || d == 'back' || (d as String).startsWith('G'), 'drawn tile of $o visible');
        }
        if (const {'call', 'chankan', 'anyeOpen'}.contains(e.phase)) ok(_noOthers(v['waiting'], s), 'claim window reveals callers');
        return;
      }
      if (e.phase == 'settle' || e.phase == 'over') return;
      for (var o = 0; o < e.players; o++) {
        if (o == s) continue;
        final sv = seats[o] as Map;
        final wonOpen = sichuan && (e.wonOrder[o] as int) > 0;
        if (wonOpen) continue;
        ok(sv['hand'] == null, 'hand of $o visible');
        for (final m in sv['melds'] as List) {
          final mm = m as Map;
          if (mm['kind'] != 'agang') continue;
          ok(mm.containsKey('tiles') ? (mm['tiles'] as List).every(_isBackOrNull) : mm['tile'] == 'back',
              'concealed kong of $o visible');
        }
      }
      if (e.phase == 'claim') ok(_noOthers(v['waiting'], s), 'claim window reveals callers');
    };

void _leakTests() {
  group('hidden info', () {
    final all = <String, (int, LeakCheck)>{
      ...leakChecks,
      for (final id in ['riichi4', 'majsoul_mingjing', 'majsoul_anye', 'majsoul_wanxiang', 'majsoul_shura'])
        id: (4, mahjongCheck(riichi: true)),
      'riichi3': (3, mahjongCheck(riichi: true)),
      'sichuan': (4, mahjongCheck(riichi: false, sichuan: true)),
      for (final id in ['mcr', 'guangdong', 'taiwan16']) id: (4, mahjongCheck(riichi: false)),
    };
    for (final en in all.entries) {
      test('no leaks: ${en.key}', () {
        final def = findGame(en.key);
        expect(def, isNotNull, reason: 'unknown game ${en.key}');
        final (lo, hi) = def!.defaultOptionsRange();
        final p = en.value.$1.clamp(lo, hi);
        final problems = <String>[];
        for (var seed = 1; seed <= 2 && problems.isEmpty; seed++) {
          problems.addAll(leakRun(en.key, p, en.value.$2, seed: seed));
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}

void main() {
  _leakTests();
  _regressionTests();
  final defs = [for (final d in gameRegistry) if (!skipIds.contains(d.id)) d];
  final fuzzSeeds = int.tryParse(Platform.environment['FUZZ_SEEDS'] ?? '') ?? 1;

  group('fuzz', () {
    for (final def in defs) {
      test('fuzz ${def.id}', () {
        final problems = <String>[];
        final sw = Stopwatch()..start();
        final combos = optionCombos(def);
        var i = 0;
        for (final opts in combos) {
          final (lo, hi) = def.playerRange(opts);
          final counts = i == 0 ? {lo, hi, (lo + hi) ~/ 2} : {i.isEven ? lo : hi};
          for (final p in counts) {
            for (var seed = 1; seed <= fuzzSeeds; seed++) {
              problems.addAll(fuzzGame(def, p, opts, seed + i * 31,
                  bursts: i == 0 ? 12 : 5, perBurst: i == 0 ? 60 : 30));
            }
          }
          i++;
          // Keep the whole suite within a few minutes.
          if (sw.elapsedMilliseconds > 2500) break;
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
    tearDownAll(() {
      if (outOfTurn.isNotEmpty && Platform.environment['FUZZ_VERBOSE'] == '1') {
        print('Accepted out-of-turn actions (review):');
        for (final l in outOfTurn.take(300)) {
          print('  $l');
        }
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Regression tests for specific input-validation fixes.

GameEngine _mk(String id, int players, {Map<String, dynamic>? opts, int seed = 1, List<bool>? bots}) {
  final def = findGame(id)!;
  final e = def.create(GameSetup(
    players: players,
    options: def.normalizeOptions(opts),
    names: [for (var i = 0; i < players; i++) 'P$i'],
    bots: bots ?? List.filled(players, false),
    hostSeat: 0,
    rng: Random(seed),
  ));
  e.host = SimHost();
  e.start();
  (e.host as SimHost).runPending();
  return e;
}

/// Advance with bots until [until] holds.
void _advance(GameEngine e, bool Function() until, {int max = 3000}) {
  final host = e.host as SimHost;
  for (var i = 0; i < max && !until() && !e.isOver; i++) {
    final w = e.waitingFor;
    Map<String, dynamic>? a;
    for (final s in w) {
      a = e.bot(s);
      if (a != null) {
        e.handle(s, a);
        break;
      }
    }
    if (!host.runPending() && a == null) break;
  }
}

const _bidi = '\u202e\u2066abc\u0007';

void _regressionTests() {
  group('validation regressions', () {
    test('asInt never throws on non-finite numbers', () {
      expect(asInt(double.infinity), -1);
      expect(asInt(double.negativeInfinity, 7), 7);
      expect(asInt(double.nan), -1);
      expect(asInt(1e300), isA<int>());
      expect(asIntList([double.infinity, 2]), [-1, 2]);
    });

    test('non-list "cards" is a GameError, not a TypeError', () {
      for (final id in ['doudizhu', 'paodekuai', 'guandan', 'shengji', 'hearts']) {
        final e = _mk(id, findGame(id)!.defaultOptionsRange().$1);
        for (final bad in [5, 'AS', {'x': 1}, double.infinity, true]) {
          for (final s in e.waitingFor) {
            for (final t in ['play', 'pass', 'bury']) {
              try {
                e.handle(s, {'type': t, 'cards': bad});
              } on GameError {
                // fine
              }
            }
          }
        }
      }
    });

    test('werewolf speech is sanitized and capped', () {
      final e = _mk('werewolf', 6, opts: {'sheriff': false}, bots: List.filled(6, true));
      _advance(e, () => (e as dynamic).phase == 'speech');
      final d = e as dynamic;
      expect(d.phase, 'speech');
      e.handle(d.speaker as int, {'type': 'end', 'text': '$_bidi${'长' * 500}'});
      final t = (d.speeches as List).last['t'] as String;
      expect(hasIllegalChars(t.replaceAll('\n', ' ')), isFalse);
      expect(t.length, lessThanOrEqualTo(60));
    });

    test('undercover description and blank guess are sanitized / capped', () {
      final e = _mk('undercover', 4, bots: List.filled(4, true));
      _advance(e, () => (e as dynamic).phase == 'describe');
      final d = e as dynamic;
      final s = (d.order as List)[d.descIdx as int] as int;
      expect(() => e.handle(s, {'type': 'describe', 'text': 'x' * 41}), throwsA(isA<GameError>()));
      e.handle(s, {'type': 'describe', 'text': '${_bidi}hello'});
      expect(hasIllegalChars((d.descs as List).last['t'] as String), isFalse);
    });

    test('turtlesoup questions are sanitized', () {
      final e = _mk('turtlesoup', 4, bots: List.filled(4, true));
      _advance(e, () => (e as dynamic).phase == 'ask');
      final d = e as dynamic;
      final s = [for (var i = 0; i < 4; i++) if (i != d.gm) i].first;
      e.handle(s, {'type': 'ask', 'text': '$_bidi是人吗'});
      expect(hasIllegalChars((d.items as List).last['t'] as String), isFalse);
    });

    test('decrypto tiebreak words are capped', () {
      final g = _mk('decrypto', 4);
      final dynamic d = g;
      d.phase = 'tiebreak';
      expect(() => g.handle(1, {'type': 'tiebreak', 'words': ['x' * 5000, 'a', 'b', 'c']}),
          throwsA(isA<GameError>()));
    });

    test('codenames ignores _targets from human spymasters', () {
      final g = _mk('codenames', 4);
      final dynamic d = g;
      final sm = (d.spymaster as List)[d.team as int] as int;
      g.handle(sm, {'type': 'clue', 'word': '测试提示', 'num': 2, '_targets': [for (var i = 0; i < 25; i++) i]});
      expect(d.intended, isEmpty);
    });

    test('catan offer spam is capped per turn', () {
      final g = _mk('catan', 3, bots: List.filled(3, true));
      final dynamic d = g;
      _advance(g, () => d.phase == 'main' && (d.hands[d.turn] as List<int>).any((x) => x > 0));
      if (d.phase != 'main') return;
      final t = d.turn as int;
      final h = d.hands[t] as List<int>;
      final r = h.indexWhere((x) => x > 0);
      final give = List.filled(5, 0)..[r] = 1;
      final get = List.filled(5, 0)..[(r + 1) % 5] = 1;
      var accepted = 0;
      for (var i = 0; i < 100; i++) {
        try {
          g.handle(t, {'type': 'offer', 'give': give, 'get': get, 'to': -1});
          accepted++;
          g.handle(t, {'type': 'cancelOffer'});
        } on GameError {
          break;
        }
      }
      expect(accepted, inInclusiveRange(1, 20));
    });

    test('exploding kittens: "pass" from a seat without Nope is rejected', () {
      final g = _mk('explodingkittens', 3);
      final dynamic d = g;
      d.phase = 'nope';
      for (var s = 0; s < 3; s++) {
        (d.hands[s] as List).remove('nope');
      }
      expect(() => g.handle(0, {'type': 'pass'}), throwsA(isA<GameError>()));
    });
  });
}
