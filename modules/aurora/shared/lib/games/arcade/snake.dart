import '../../src/engine.dart';
import 'arcade_util.dart';

/// 贪吃蛇大作战 (2-6 人). Shared 30×30 grid, ~6 ticks/s.
///
/// Players queue a direction with handle(); it applies on the next tick
/// (reversing into yourself is ignored). Hitting a wall, any body or your own
/// body eliminates; two heads moving into the same cell (or swapping) both die.
/// Last snake alive wins; at the time cap the longest snake wins.
class SnakeBattle extends GameEngine {
  SnakeBattle(super.setup);

  static const n = 30;
  static const tickMs = 160;
  static const countdownTicks = 12;
  static const dirs = {'up': (0, -1), 'down': (0, 1), 'left': (-1, 0), 'right': (1, 0)};
  static const dirNames = ['up', 'right', 'down', 'left'];

  late int maxTicks;
  late int foodCount;
  late List<SnakePlayer> ps;
  final List<int> food = [];
  int tick = 0;
  int countdown = countdownTicks;
  bool over = false;
  List<Map<String, dynamic>>? ranking;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? placingsOf(ranking, players) : null;

  int _resigns = 0;

  @override
  bool get canResign => !over;

  /// 认输 = crash right now (ranked after everyone who didn't resign).
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (!p.alive) throw GameError('你已出局');
    p
      ..alive = false
      ..resigned = true
      ..deathTick = tick;
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    final still = [for (var s = 0; s < players; s++) if (ps[s].alive) s];
    if (still.length <= 1) _finish(still.isEmpty ? '全部出局' : '${name(still.first)} 存活到最后');
  }

  @override
  int get botDelayMs => 300;

  @override
  void start() {
    maxTicks = setup.opt<int>('time', 180) * 1000 ~/ tickMs;
    foodCount = players + 3;
    ps = [];
    // start positions spread around the board, heading inward
    final spots = <(int, int, String)>[
      (4, 5, 'right'), (25, 24, 'left'), (24, 4, 'down'), (5, 25, 'up'), (4, 15, 'right'), (25, 15, 'left'),
    ];
    for (var i = 0; i < players; i++) {
      final (x, y, d) = spots[i];
      final (dx, dy) = dirs[d]!;
      final p = SnakePlayer()..dir = d;
      for (var k = 0; k < 3; k++) {
        p.body.add((y - dy * k) * n + (x - dx * k));
      }
      ps.add(p);
    }
    for (var i = 0; i < foodCount; i++) {
      _spawnFood();
    }
    host.log('贪吃蛇大作战开始！吃食物变长，撞墙/撞蛇出局，最后存活或最长者获胜。');
    host.schedule(tickMs, _tick);
  }

  bool _occupied(int c) => food.contains(c) || ps.any((p) => p.alive && p.body.contains(c));

  void _spawnFood() {
    for (var tries = 0; tries < 200; tries++) {
      final c = rng.nextInt(n * n);
      if (!_occupied(c)) {
        food.add(c);
        return;
      }
    }
  }

  static bool opposite(String a, String b) {
    final (ax, ay) = dirs[a]!;
    final (bx, by) = dirs[b]!;
    return ax == -bx && ay == -by;
  }

  /// Next head cell for moving from [head] in [d], or -1 when off the board.
  static int step(int head, String d) {
    final (dx, dy) = dirs[d]!;
    final x = head % n + dx, y = head ~/ n + dy;
    if (x < 0 || y < 0 || x >= n || y >= n) return -1;
    return y * n + x;
  }

  void _tick() {
    if (over) return;
    tick++;
    if (countdown > 0) {
      countdown--;
      host.schedule(tickMs, _tick);
      return;
    }
    final alive = [for (var s = 0; s < players; s++) if (ps[s].alive) s];
    // computer players steer every tick (bot() only returns 'idle' for them)
    for (final s in alive) {
      if (isBot(s) || ps[s].auto) ps[s].next = botDir(s, level: isBot(s) ? botLevel : 1) ?? ps[s].next;
    }
    final heads = <int, int>{};
    final grows = <int, bool>{};
    for (final s in alive) {
      final p = ps[s];
      if (p.next != null && !opposite(p.next!, p.dir)) p.dir = p.next!;
      p.next = null;
      heads[s] = step(p.body.first, p.dir);
      grows[s] = food.contains(heads[s]);
    }
    final dead = <int>{};
    for (final s in alive) {
      final h = heads[s]!;
      if (h < 0) {
        dead.add(s);
        continue;
      }
      for (final o in alive) {
        final b = ps[o].body;
        // tail cell moves away this tick unless that snake grows
        final len = grows[o]! ? b.length : b.length - 1;
        for (var i = 0; i < len; i++) {
          if (b[i] == h) {
            dead.add(s);
            break;
          }
        }
        if (o != s && heads[o] == h) dead.add(s); // head-on
        if (o != s && heads[o] == ps[s].body.first && h == b.first) dead.add(s); // swap
      }
    }
    for (final s in alive) {
      final p = ps[s];
      if (dead.contains(s)) {
        p.alive = false;
        p.deathTick = tick;
        host.log('${name(s)} 撞上了，出局！（长度 ${p.body.length}）');
        continue;
      }
      p.body.insert(0, heads[s]!);
      if (grows[s]!) {
        food.remove(heads[s]);
        p.eaten++;
      } else {
        p.body.removeLast();
      }
    }
    // dead snakes become food (every other cell)
    for (final s in dead) {
      final b = ps[s].body;
      for (var i = 0; i < b.length; i += 2) {
        if (!food.contains(b[i]) && food.length < 60) food.add(b[i]);
      }
    }
    while (food.length < foodCount) {
      final before = food.length;
      _spawnFood();
      if (food.length == before) break;
    }
    final still = [for (var s = 0; s < players; s++) if (ps[s].alive) s];
    if (still.length <= 1) {
      _finish(still.isEmpty ? '同归于尽' : '${name(still.first)} 存活到最后');
    } else if (tick >= maxTicks + countdownTicks) {
      _finish('时间到');
    }
    if (!over) host.schedule(tickMs, _tick);
  }

  void _finish(String why) {
    over = true;
    ranking = buildRanking(players, (a, b) {
      final pa = ps[a], pb = ps[b];
      if (pa.resignNo != pb.resignNo) return pa.resignNo == 0 ? -1 : (pb.resignNo == 0 ? 1 : pb.resignNo - pa.resignNo);
      if (pa.alive != pb.alive) return pa.alive ? -1 : 1;
      if (!pa.alive && pa.deathTick != pb.deathTick) return pb.deathTick - pa.deathTick;
      return pb.body.length - pa.body.length;
    }, (s) => {'len': ps[s].body.length, 'alive': ps[s].alive});
    host.log('游戏结束（$why）！冠军：${winnersText(ranking!, name)}');
  }

  @override
  List<int> get waitingFor => over ? const [] : rotated([for (var s = 0; s < players; s++) if (ps[s].alive) s], tick);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    final p = ps[seat];
    if (type == 'auto') {
      // sent by the server's stand-in for a disconnected player
      p.auto = true;
      return;
    }
    if (type != 'turn') throw GameError('未知操作');
    if (!p.alive) throw GameError('你已出局');
    p.auto = false;
    final d = asStr(a['dir']);
    if (!dirs.containsKey(d)) throw GameError('方向无效');
    if (opposite(d, p.dir)) return; // silently ignore reversing
    p.next = d;
  }

  // ---------------------------------------------------------------- bot

  /// Cells blocked next tick (all bodies minus tails that will move, plus
  /// cells other heads could enter).
  Set<int> _blocked(int seat, {bool cautious = true}) {
    final b = <int>{};
    for (var s = 0; s < players; s++) {
      final p = ps[s];
      if (!p.alive) continue;
      b.addAll(p.body.take(p.body.length - 1));
      if (s != seat && cautious) {
        for (final d in dirNames) {
          final c = step(p.body.first, d);
          if (c >= 0) b.add(c);
        }
      }
    }
    return b;
  }

  int _reach(int from, Set<int> blocked, int cap) {
    final seen = {from};
    final q = [from];
    for (var i = 0; i < q.length && seen.length < cap; i++) {
      for (final d in dirNames) {
        final c = step(q[i], d);
        if (c >= 0 && !blocked.contains(c) && seen.add(c)) q.add(c);
      }
    }
    return seen.length;
  }

  /// BFS toward the nearest food; falls back to the move with most space.
  /// [level] 0 ignores enemy heads, has a short space check and wanders
  /// randomly (bot randomness only, never the game rng); 2 demands more free
  /// space and skips food another head reaches first.
  String? botDir(int seat, {int level = 1}) => _botDir(seat, level > 0, level) ?? _botDir(seat, false, level);

  /// Bot-only randomness: steering runs inside the tick (not bot()), so use
  /// the separate bot generator directly to keep the game sequence intact.
  int _noise(int m) => setup.botRng.nextInt(m);

  String? _botDir(int seat, bool cautious, [int level = 1]) {
    final p = ps[seat];
    final blocked = _blocked(seat, cautious: cautious);
    final head = p.body.first;
    final options = <String, int>{};
    for (final d in dirNames) {
      if (opposite(d, p.dir)) continue;
      final c = step(head, d);
      if (c < 0 || blocked.contains(c)) continue;
      options[d] = _reach(c, blocked, level >= 2 ? p.body.length * 4 + 20 : p.body.length * 2 + 10);
    }
    if (options.isEmpty) return null;
    final need = level <= 0 ? 3 : (level >= 2 ? p.body.length * 2 + 4 : p.body.length + 2);
    final safe = {for (final e in options.entries) if (e.value >= need) e.key: e.value};
    final pool = safe.isNotEmpty ? safe : options;
    if (level <= 0 && _noise(6) == 0) {
      // wander: keep going or turn at random
      final ks = pool.keys.toList();
      return ks[_noise(ks.length)];
    }
    // food another head is strictly closer to is not worth chasing (困难)
    int dist(int a, int b) => (a % n - b % n).abs() + (a ~/ n - b ~/ n).abs();
    bool contested(int f) {
      if (level < 2) return false;
      final mine = dist(head, f);
      for (var o = 0; o < players; o++) {
        if (o != seat && ps[o].alive && dist(ps[o].body.first, f) < mine) return true;
      }
      return false;
    }
    // BFS from head to nearest food, remembering the first move
    final first = <int, String>{};
    final q = <int>[];
    for (final d in pool.keys) {
      final c = step(head, d);
      first[c] = d;
      q.add(c);
    }
    for (var i = 0; i < q.length; i++) {
      final c = q[i];
      if (food.contains(c) && !contested(c)) return first[c];
      for (final d in dirNames) {
        final nc = step(c, d);
        if (nc >= 0 && !blocked.contains(nc) && !first.containsKey(nc) && nc != head) {
          first[nc] = first[c]!;
          q.add(nc);
        }
      }
    }
    var best = pool.keys.first;
    for (final e in pool.entries) {
      if (e.value > pool[best]!) best = e.key;
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players) return null;
    final p = ps[seat];
    // computer seats are steered inside the tick; a disconnected human gets
    // switched to autopilot (cleared again by their next real input)
    if (!p.alive || countdown > 0 || isBot(seat) || p.auto) return {'type': 'idle'};
    return {'type': 'auto'};
  }

  // ---------------------------------------------------------------- view

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : (countdown > 0 ? 'countdown' : 'play'),
        'tick': tick,
        'tickMs': tickMs,
        'n': n,
        'cd': countdown,
        'left': over ? 0 : (maxTicks + countdownTicks - tick) * tickMs ~/ 1000,
        'food': food,
        'sn': [
          for (final p in ps) {'b': p.alive ? p.body : const <int>[], 'd': p.dir, 'al': p.alive, 'len': p.body.length},
        ],
        'final': ranking,
      };
}

class SnakePlayer {
  final List<int> body = []; // head first
  String dir = 'right';
  String? next;
  bool alive = true;
  bool auto = false;
  int deathTick = 0;
  int eaten = 0;
  bool resigned = false;
  int resignNo = 0; // order of resigning (later = better placed)
}
