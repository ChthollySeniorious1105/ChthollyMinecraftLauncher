import '../../src/engine.dart';
import 'a2_util.dart';

/// 炸弹人 (2-4 人). Real-time grid game on a 15×13 arena (13×11 playable),
/// driven by a self-rescheduling tick like 贪吃蛇大作战.
///
/// Players hold a direction (`{'type':'dir','dir':'up'|..|'none'}`) and move
/// one cell every [moveTicksFor] ticks; a short tap still moves one cell.
/// `{'type':'bomb'}` drops a bomb on the next tick. Bombs explode after
/// [fuseTicks] in a + shape, chain other bombs, destroy bricks (which may drop
/// power-ups) and kill players standing in the flames.
class Bomberman extends GameEngine {
  Bomberman(super.setup);

  static const w = 15, h = 13;
  static const tickMs = 60;
  static const countdownTicks = 40; // 2.4 s
  static const fuseTicks = 42; // ≈ 2.5 s
  static const flameTicks = 8; // ≈ 0.5 s
  static const maxBombs = 8, maxRange = 8, maxSpeed = 2;
  static const dirs = {'up': (0, -1), 'down': (0, 1), 'left': (-1, 0), 'right': (1, 0)};
  static const dirNames = ['up', 'right', 'down', 'left'];

  /// Ticks per cell for a speed level (0 = base).
  static int moveTicksFor(int speed) => const [5, 4, 3][speed.clamp(0, 2)];

  /// Spawn corners (x, y), used in this order for 2/3/4 players.
  static const spawns = [(1, 1), (13, 11), (13, 1), (1, 11)];

  late int maxTicks;

  /// Cell contents: '#' pillar/wall, '+' brick, '.' floor.
  late List<String> grid;

  /// Power-ups lying on the floor: 'b' +炸弹, 'r' +火力, 's' +速度.
  final Map<int, String> items = {};
  final Map<int, BombermanBomb> bombs = {};

  /// Burning cells: cell -> (ticks left, bitmask of owner seats).
  final Map<int, (int, int)> flames = {};
  late List<BombermanPlayer> ps;
  int tick = 0;
  int countdown = countdownTicks;
  bool over = false;
  int _deaths = 0;
  int _resigns = 0;
  List<Map<String, dynamic>>? ranking;
  Map<String, dynamic>? last;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? a2Placings(ranking, players) : null;

  @override
  int get botDelayMs => 300;

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (!p.alive) throw GameError('你已出局');
    p
      ..alive = false
      ..deathTick = tick
      ..deathNo = ++_deaths
      ..resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    _checkEnd();
  }

  static int cell(int x, int y) => y * w + x;
  static bool pillar(int x, int y) => x == 0 || y == 0 || x == w - 1 || y == h - 1 || (x.isEven && y.isEven);

  @override
  void start() {
    maxTicks = setup.opt<int>('time', 180) * 1000 ~/ tickMs;
    final density = switch (setup.opt<String>('bricks', 'normal')) { 'few' => 0.45, 'many' => 0.85, _ => 0.68 };
    // spawn corners and their two neighbours stay clear
    final clear = <int>{};
    for (final (x, y) in spawns) {
      final sx = x == 1 ? 1 : -1, sy = y == 1 ? 1 : -1;
      clear.addAll([cell(x, y), cell(x + sx, y), cell(x, y + sy), cell(x + 2 * sx, y), cell(x, y + 2 * sy)]);
    }
    grid = [
      for (var i = 0; i < w * h; i++)
        pillar(i % w, i ~/ w) ? '#' : (!clear.contains(i) && rng.nextDouble() < density ? '+' : '.'),
    ];
    ps = [
      for (var i = 0; i < players; i++) BombermanPlayer(cell(spawns[i].$1, spawns[i].$2))..dir = spawns[i].$2 == 1 ? 'down' : 'up',
    ];
    host.log('炸弹人开始！方向键/WASD 移动，空格放炸弹。炸开砖块拿道具，炸到对手即可淘汰，最后存活者获胜。');
    host.schedule(tickMs, _tick);
  }

  bool _blocked(int c) => grid[c] != '.' || bombs.containsKey(c);

  static int step(int c, String d) {
    final (dx, dy) = dirs[d]!;
    return c + dy * w + dx;
  }

  // ---------------------------------------------------------------- tick

  void _tick() {
    if (over) return;
    tick++;
    if (countdown > 0) {
      countdown--;
      host.schedule(tickMs, _tick);
      return;
    }
    final alive = [for (var s = 0; s < players; s++) if (ps[s].alive) s];
    // computer players think inside the tick (bot() only returns 'idle')
    for (final s in alive) {
      if (isBot(s) || ps[s].auto) _botThink(s, isBot(s) ? botLevel : 1);
    }
    // 1. bombs dropped this tick
    for (final s in alive) {
      final p = ps[s];
      if (!p.wantBomb) continue;
      p.wantBomb = false;
      if (bombs.containsKey(p.cell) || p.placed >= p.bombs) continue;
      bombs[p.cell] = BombermanBomb(s, fuseTicks, p.range);
      p.placed++;
    }
    // 2. movement
    for (final s in alive) {
      final p = ps[s];
      if (p.cool > 0) p.cool--;
      final d = p.pending ?? p.hold;
      if (d == null || p.cool > 0) continue;
      p.pending = null;
      p.dir = d;
      final nc = step(p.cell, d);
      if (_blocked(nc)) continue;
      p.cell = nc;
      p.cool = moveTicksFor(p.speed);
      p.moves++;
      final it = items.remove(nc);
      if (it != null) {
        switch (it) {
          case 'b':
            p.bombs = (p.bombs + 1).clamp(1, maxBombs);
          case 'r':
            p.range = (p.range + 1).clamp(1, maxRange);
          default:
            p.speed = (p.speed + 1).clamp(0, maxSpeed);
        }
      }
    }
    // 3. burning flames die down
    for (final c in flames.keys.toList()) {
      final (t, o) = flames[c]!;
      if (t <= 1) {
        flames.remove(c);
      } else {
        flames[c] = (t - 1, o);
      }
    }
    // 4. fuses + chain reactions
    for (final b in bombs.values) {
      b.fuse--;
    }
    final fresh = <int>{};
    var boom = [for (final e in bombs.entries) if (e.value.fuse <= 0) e.key];
    while (boom.isNotEmpty) {
      final next = <int>[];
      for (final c in boom) {
        final b = bombs.remove(c);
        if (b == null) continue;
        ps[b.owner].placed--;
        for (final f in blast(c, b.range, fresh: fresh)) {
          final old = flames[f];
          flames[f] = (flameTicks, (old == null ? 0 : old.$2) | (1 << b.owner));
          if (bombs.containsKey(f)) next.add(f);
        }
      }
      boom = next;
    }
    // 5. deaths
    final died = <int>[];
    for (final s in alive) {
      final p = ps[s];
      final f = flames[p.cell];
      if (f == null) continue;
      p.alive = false;
      p.deathTick = tick;
      died.add(s);
      // credit someone else's bomb when several flames overlap
      var killer = s;
      for (var o = 0; o < players; o++) {
        if (o != s && f.$2 & (1 << o) != 0) {
          killer = o;
          break;
        }
      }
      if (killer != s) {
        ps[killer].kills++;
        host.log('${name(s)} 被 ${name(killer)} 炸飞了！');
      } else {
        host.log('${name(s)} 被自己的炸弹炸飞了！');
      }
    }
    if (died.isNotEmpty) {
      _deaths++;
      for (final s in died) {
        ps[s].deathNo = _deaths;
      }
      last = {'k': 'die', 'ss': died, 't': tick};
    }
    _checkEnd();
    if (!over && tick >= maxTicks + countdownTicks) _finish('时间到');
    if (!over) host.schedule(tickMs, _tick);
  }

  /// Cells hit by a bomb at [c] with [range]: stops at pillars, destroys the
  /// first brick / power-up in each direction. When [fresh] is given the
  /// destruction is applied (bricks -> floor, maybe dropping a power-up).
  List<int> blast(int c, int range, {Set<int>? fresh}) {
    final out = [c];
    for (final d in dirNames) {
      var x = c;
      for (var i = 0; i < range; i++) {
        x = step(x, d);
        final g = grid[x];
        if (g == '#') break;
        out.add(x);
        if (fresh != null && fresh.contains(x)) break; // brick destroyed by an earlier bomb this tick
        if (g == '+') {
          if (fresh != null) {
            grid[x] = '.';
            fresh.add(x);
            final r = rng.nextInt(100);
            if (r < 32) items[x] = r < 13 ? 'b' : (r < 26 ? 'r' : 's');
          }
          break;
        }
        if (items.containsKey(x)) {
          if (fresh != null) items.remove(x);
          break;
        }
        if (bombs.containsKey(x)) break; // that bomb chains; its own blast continues
      }
    }
    return out;
  }

  void _checkEnd() {
    if (over) return;
    final still = [for (var s = 0; s < players; s++) if (ps[s].alive) s];
    if (still.length <= 1) _finish(still.isEmpty ? '同归于尽' : '${name(still.first)} 存活到最后');
  }

  void _finish(String why) {
    over = true;
    ranking = a2Ranking(players, (a, b) {
      final pa = ps[a], pb = ps[b];
      if (pa.resignNo != pb.resignNo) return pa.resignNo == 0 ? -1 : (pb.resignNo == 0 ? 1 : pb.resignNo - pa.resignNo);
      if (pa.alive != pb.alive) return pa.alive ? -1 : 1;
      if (!pa.alive && pa.deathNo != pb.deathNo) return pb.deathNo - pa.deathNo;
      return pb.kills - pa.kills;
    }, (s) => {'kills': ps[s].kills, 'alive': ps[s].alive});
    host.log('游戏结束（$why）！冠军：${a2Winners(ranking!, name)}');
  }

  @override
  List<int> get waitingFor => over ? const [] : a2Rotated([for (var s = 0; s < players; s++) if (ps[s].alive) s], tick);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    final p = ps[seat];
    if (type == 'auto') {
      p.auto = true;
      return;
    }
    if (!p.alive) throw GameError('你已出局');
    switch (type) {
      case 'dir':
        p.auto = false;
        final d = asStr(a['dir']);
        if (d == 'none') {
          p.hold = null;
          return;
        }
        if (!dirs.containsKey(d)) throw GameError('方向无效');
        p.hold = d;
        p.pending = d;
      case 'bomb':
        p.auto = false;
        if (countdown > 0) return;
        p.wantBomb = true;
      default:
        throw GameError('未知操作');
    }
  }

  // ---------------------------------------------------------------- bot

  /// Ticks from now until each threatened cell burns: cell -> (start, end).
  /// Accounts for chain reactions and flames already burning.
  Map<int, (int, int)> dangerMap({int? extraCell, int extraRange = 0}) {
    final t = <int, int>{for (final e in bombs.entries) e.key: e.value.fuse};
    final range = <int, int>{for (final e in bombs.entries) e.key: e.value.range};
    if (extraCell != null && !t.containsKey(extraCell)) {
      t[extraCell] = fuseTicks;
      range[extraCell] = extraRange;
    }
    // chain: a bomb inside another blast goes off no later than it
    var changed = true;
    final blasts = <int, List<int>>{};
    List<int> bl(int c) => blasts.putIfAbsent(c, () => _blastWith(c, range[c]!, t.keys.toSet()));
    while (changed) {
      changed = false;
      for (final c in t.keys) {
        for (final f in bl(c)) {
          if (f != c && t.containsKey(f) && t[f]! > t[c]!) {
            t[f] = t[c]!;
            changed = true;
          }
        }
      }
    }
    final out = <int, (int, int)>{};
    void add(int c, int s, int e) {
      final o = out[c];
      out[c] = o == null ? (s, e) : (o.$1 < s ? o.$1 : s, o.$2 > e ? o.$2 : e);
    }
    // replay detonations in order: bricks broken / bombs gone earlier no
    // longer stop later blasts (they reach further than a static check says)
    final order = t.keys.toList()..sort((a, b) => t[a]! - t[b]!);
    final broken = <int, int>{}; // brick cell -> tick it breaks
    for (final c in order) {
      final tc = t[c]!;
      final live = {for (final o in order) if (t[o]! >= tc) o};
      for (final f in _blastWith(c, range[c]!, live, broken: broken, at: tc)) {
        add(f, tc, tc + flameTicks);
        if (grid[f] == '+') broken.putIfAbsent(f, () => tc);
      }
    }
    for (final e in flames.entries) {
      add(e.key, 0, e.value.$1);
    }
    return out;
  }

  /// Blast cells without side effects, treating [bombCells] as blast stoppers.
  List<int> _blastWith(int c, int r, Set<int> bombCells, {Map<int, int> broken = const {}, int at = 0}) {
    final out = [c];
    for (final d in dirNames) {
      var x = c;
      for (var i = 0; i < r; i++) {
        x = step(x, d);
        final g = grid[x];
        if (g == '#') break;
        out.add(x);
        // power-ups are ignored: they may be picked up before the bomb goes off
        if (g == '+' && !(broken[x] != null && broken[x]! < at)) break;
        if (x != c && bombCells.contains(x)) break;
      }
    }
    return out;
  }

  /// BFS over walkable cells from the player's cell; returns first step
  /// direction towards the nearest cell satisfying [goal] while never being
  /// inside a burning window. null = no such path ('' = stay, already there).
  String? _path(int seat, Map<int, (int, int)> danger, bool Function(int c, int arrive) goal,
      {int maxDepth = 40, Set<int> extraBlocked = const {}}) {
    final p = ps[seat];
    final mt = moveTicksFor(p.speed);
    final start = p.cell;
    if (goal(start, 0)) return '';
    final first = <int, String>{start: ''};
    final depth = <int, int>{start: 0};
    final q = [start];
    for (var i = 0; i < q.length; i++) {
      final c = q[i];
      final dpt = depth[c]!;
      if (dpt >= maxDepth) continue;
      // when we leave c (and arrive at the next cell)
      final arrive = (dpt == 0 ? (p.cool > 0 ? p.cool : 1) : 1 + p.cool + dpt * mt);
      for (final d in dirNames) {
        final nc = step(c, d);
        if (first.containsKey(nc) || _blocked(nc) || extraBlocked.contains(nc)) continue;
        final win = danger[nc];
        if (win != null && arrive + mt >= win.$1 - 1 && arrive <= win.$2 + 1) continue;
        first[nc] = dpt == 0 ? d : first[c]!;
        depth[nc] = dpt + 1;
        if (goal(nc, arrive)) return first[nc];
        q.add(nc);
      }
    }
    return null;
  }

  bool _safeCell(Map<int, (int, int)> danger, int c, int arrive) {
    final win = danger[c];
    return win == null || win.$2 + 1 < arrive;
  }

  /// Enemies or bricks a bomb at [c] would hit.
  (int, int) _bombValue(int seat, int c) {
    var bricks = 0, enemies = 0;
    final r = ps[seat].range;
    for (final d in dirNames) {
      var x = c;
      for (var i = 0; i < r; i++) {
        x = step(x, d);
        if (grid[x] == '#') break;
        if (grid[x] == '+') {
          bricks++;
          break;
        }
        for (var o = 0; o < players; o++) {
          if (o != seat && ps[o].alive && ps[o].cell == x) enemies++;
        }
      }
    }
    for (var o = 0; o < players; o++) {
      if (o != seat && ps[o].alive && ps[o].cell == c) enemies++;
    }
    return (bricks, enemies);
  }

  int _noise(int m) => setup.botRng.nextInt(m);

  /// Steers [seat] for this tick (sets hold / wantBomb). [level] 0 hesitates
  /// and sometimes bombs without checking the way out; 2 hunts players.
  void _botThink(int seat, int level) {
    final p = ps[seat];
    p.pending = null;
    if (p.cool > 1) return; // mid-step: keep going
    final danger = dangerMap();
    final here = danger[p.cell];
    if (here != null) {
      // flee to the nearest cell outside every blast
      final d = _path(seat, danger, (c, t) => _safeCell(danger, c, t));
      p.hold = (d == null || d.isEmpty) ? null : d;
      if (d == null) {
        // no clean escape: at least step to the cell that burns latest
        var best = '';
        var bestT = here.$1;
        for (final dd in dirNames) {
          final nc = step(p.cell, dd);
          if (_blocked(nc)) continue;
          final w2 = danger[nc];
          final t2 = w2 == null ? 999 : w2.$1;
          if (t2 > bestT) {
            bestT = t2;
            best = dd;
          }
        }
        p.hold = best.isEmpty ? null : best;
      }
      return;
    }
    if (level <= 0 && _noise(3) == 0) {
      p.hold = null; // hesitates
      return;
    }
    // drop a bomb here?
    // easy/normal bots keep at most 1/2 bombs out at once (less self-trapping)
    final cap = level >= 2 ? p.bombs : (level == 1 ? 2 : 1);
    if (p.placed < p.bombs && p.placed < cap && !bombs.containsKey(p.cell)) {
      final (bricks, enemies) = _bombValue(seat, p.cell);
      final want = enemies > 0 || bricks > 0;
      if (want && (level >= 1 || _noise(2) == 0)) {
        final d2 = dangerMap(extraCell: p.cell, extraRange: p.range);
        final reckless = level <= 0 && _noise(5) == 0;
        // the hiding spot must be reached with some margin before the blast
        final margin = level >= 2 ? 6 : 10;
        // and normal/hard bots want more than one hiding spot, so a single
        // enemy bomb can't seal the only way out
        var found = 0;
        final need = level >= 2 ? 3 : (level == 1 ? 2 : 1);
        bool hide(int c, int t) {
          if (_safeCell(d2, c, t) && t + margin < fuseTicks) found++;
          return found >= need;
        }
        if (reckless || _path(seat, d2, hide, maxDepth: 10) != null) {
          p.wantBomb = true;
          p.hold = null;
          return;
        }
      }
    }
    // pick a target: power-ups, a spot next to bricks/enemies
    bool useful(int c) {
      if (items.containsKey(c)) return true;
      final (b, e) = _bombValue(seat, c);
      if (level >= 2) return e > 0 || b > 0;
      return b > 0 || (level >= 1 && e > 0);
    }
    String? d;
    if (level >= 2 && !_anyBricksLeft()) {
      // hunt: walk towards the nearest enemy
      d = _path(seat, danger, (c, t) => _safeCell(danger, c, t) && _bombValue(seat, c).$2 > 0);
    }
    d ??= p.placed >= p.bombs
        ? null
        : _path(seat, danger, (c, t) => _safeCell(danger, c, t) && useful(c));
    if (d == null || d.isEmpty) {
      // nothing to do (or waiting for bombs): wander safely
      final opts = [
        for (final dd in dirNames)
          if (!_blocked(step(p.cell, dd)) && !danger.containsKey(step(p.cell, dd))) dd,
      ];
      d = opts.isEmpty || _noise(3) == 0 ? null : opts[_noise(opts.length)];
      // when an enemy is far away and no bricks remain, approach them
      if (opts.isNotEmpty && !_anyBricksLeft()) {
        final toward = _path(seat, danger, (c, t) => _safeCell(danger, c, t) && _bombValue(seat, c).$2 > 0);
        if (toward != null && toward.isNotEmpty) d = toward;
      }
    }
    p.hold = d;
  }

  bool _anyBricksLeft() => grid.contains('+');

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players) return null;
    final p = ps[seat];
    if (!p.alive || countdown > 0 || isBot(seat) || p.auto) return {'type': 'idle'};
    return {'type': 'auto'};
  }

  // ---------------------------------------------------------------- view

  @override
  Map<String, dynamic> view(int seat) {
    final g = StringBuffer();
    for (var i = 0; i < w * h; i++) {
      g.write(items[i] ?? grid[i]);
    }
    return {
      'phase': over ? 'over' : (countdown > 0 ? 'countdown' : 'play'),
      'tick': tick,
      'tickMs': tickMs,
      'w': w,
      'h': h,
      'cd': countdown,
      'fuse': fuseTicks,
      'flameT': flameTicks,
      'left': over ? 0 : (maxTicks + countdownTicks - tick).clamp(0, maxTicks) * tickMs ~/ 1000,
      'g': g.toString(),
      'bombs': [
        for (final e in bombs.entries) {'c': e.key, 'f': e.value.fuse, 'o': e.value.owner, 'r': e.value.range},
      ],
      'fl': [for (final e in flames.entries) [e.key, e.value.$1]],
      'ps': [
        for (final p in ps)
          {
            'c': p.cell,
            'al': p.alive,
            'd': p.dir,
            'k': p.kills,
            'b': p.bombs,
            'r': p.range,
            'sp': p.speed,
            'mt': moveTicksFor(p.speed),
            'mv': p.moves,
          },
      ],
      'last': last,
      'final': ranking,
    };
  }
}

class BombermanBomb {
  final int owner;
  int fuse;
  final int range;
  BombermanBomb(this.owner, this.fuse, this.range);
}

class BombermanPlayer {
  int cell;
  BombermanPlayer(this.cell);
  String dir = 'down';
  String? hold; // held direction
  String? pending; // tapped direction not yet applied
  bool wantBomb = false;
  int cool = 0;
  int bombs = 1;
  int range = 2;
  int speed = 0;
  int placed = 0;
  int kills = 0;
  int moves = 0;
  bool alive = true;
  bool auto = false;
  int deathTick = 0;
  int deathNo = 0;
  int resignNo = 0;
}
