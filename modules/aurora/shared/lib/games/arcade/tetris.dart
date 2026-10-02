import 'dart:math';

import '../../src/engine.dart';
import 'arcade_util.dart';

/// 俄罗斯方块对战 (2-4 人), TETR.IO multiplayer rules.
///
/// * Guideline field: 10 wide, 20 visible rows plus a 20-row buffer above.
///   Spawn in the top visible rows; block out (spawn overlap), lock out
///   (piece locks entirely above the visible field) or garbage pushed past
///   the buffer top eliminates.
/// * SRS rotation with the guideline kick tables, plus TETR.IO SRS+ 180°
///   rotation kicks. 7-bag, 5 previews, hold (once per piece).
/// * Lock delay 0.5 s with up to 15 move/rotate resets per piece (reset when
///   the piece reaches a new lowest row).
/// * T-Spin detection: last successful action was a rotation and ≥3 of the
///   4 corners around the T's centre are filled. Full when both "front"
///   corners are filled or the final (TST/fin) kick was used, else Mini.
/// * Attack: single 0 / double 1 / triple 2 / quad 4; T-Spin single 2 /
///   double 4 / triple 6; Mini single 0 / double 1. Back-to-back chains
///   (quads and spin clears) add +1…+ by chain level; combo multiplies by
///   (1 + 0.25·combo) (or log1p(1.25·combo) when base is 0); Perfect Clear
///   +10. After [marginSec] the garbage multiplier grows 0.008/s.
/// * Garbage: incoming attacks queue and become ready after ~0.33 s. Lines
///   you send cancel your queued garbage first. When you place a piece
///   without clearing, up to 8 ready lines rise. Each attack's lines share
///   one hole column; consecutive attacks use different columns.
/// * Targeting: random opponent, or 反击 (whoever attacked you last).
/// * Last player standing wins; a safety time cap ranks survivors by score.
///
/// Real-time: a self-rescheduling tick every [tickMs] ms drives gravity,
/// lock delay and garbage timers; inputs are applied the moment they arrive.
class TetrisBattle extends GameEngine {
  TetrisBattle(super.setup);

  static const w = 10, h = 20; // visible field
  static const buffer = 20; // hidden rows above the visible field
  static const rows = h + buffer; // internal board height
  static const tickMs = 50;
  static const tps = 1000 ~/ tickMs; // ticks per second (20)
  static const maxTicks = 600 * tps; // 10 分钟安全上限
  static const marginSec = 180; // 之后垃圾倍率每秒 +0.008
  static const botPace = tps ~/ 2; // 电脑每块至少间隔 0.5 秒
  static const countdownTicks = 3 * tps;
  static const lockTicks = tps ~/ 2; // 0.5 s
  static const maxResets = 15;
  static const garbageDelay = 7; // ~0.33 s (20 frames)
  static const garbageCap = 8;
  static const maxQueue = 12;
  static const types = 'IJLOSTZ';
  static const keys = {'left', 'right', 'dasl', 'dasr', 'rotate', 'cw', 'ccw', 'r180', 'soft', 'sonic', 'hard', 'hold'};

  /// Rotation-0 cells (x, y) within an n×n box (y grows downwards).
  static const shapes = <String, List<List<int>>>{
    'I': [[0, 1], [1, 1], [2, 1], [3, 1]],
    'J': [[0, 0], [0, 1], [1, 1], [2, 1]],
    'L': [[2, 0], [0, 1], [1, 1], [2, 1]],
    'O': [[0, 0], [1, 0], [0, 1], [1, 1]],
    'S': [[1, 0], [2, 0], [0, 1], [1, 1]],
    'T': [[1, 0], [0, 1], [1, 1], [2, 1]],
    'Z': [[0, 0], [1, 0], [1, 1], [2, 1]],
  };

  // SRS kick tables (x right, y UP as in the guideline; negated when applied).
  static const _kJlstz = <String, List<List<int>>>{
    '01': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '10': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '12': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '21': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '23': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    '32': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '30': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '03': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
  };
  static const _kI = <String, List<List<int>>>{
    '01': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '10': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '12': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
    '21': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '23': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '32': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '30': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '03': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
  };
  // TETR.IO SRS+ 180° kicks.
  static const _k180 = <String, List<List<int>>>{
    '02': [[0, 0], [0, 1], [1, 1], [-1, 1], [1, 0], [-1, 0]],
    '13': [[0, 0], [1, 0], [1, 2], [1, 1], [0, 2], [0, 1]],
    '20': [[0, 0], [0, -1], [-1, -1], [1, -1], [-1, 0], [1, 0]],
    '31': [[0, 0], [-1, 0], [-1, 2], [-1, 1], [0, 2], [0, 1]],
  };

  static const scoreTable = [0, 100, 300, 500, 800];
  static const spinScore = [400, 800, 1200, 1600];
  static const miniScore = [100, 200, 400, 400];

  static int boxOf(String t) => t == 'I' ? 4 : (t == 'O' ? 2 : 3);

  /// Cells (x, y) of piece [t] with rotation [r] at box origin (x, y).
  static List<List<int>> cellsOf(String t, int r, int x, int y) {
    final n = boxOf(t);
    return [
      for (final c in shapes[t]!)
        () {
          var cx = c[0], cy = c[1];
          for (var i = 0; i < (r & 3); i++) {
            final nx = n - 1 - cy;
            cy = cx;
            cx = nx;
          }
          return [x + cx, y + cy];
        }(),
    ];
  }

  /// B2B bonus for a back-to-back chain of [b2b] (TETR.IO levels).
  static int b2bBonus(int b2b) {
    if (b2b <= 0) return 0;
    if (b2b <= 2) return 1;
    if (b2b <= 7) return 2;
    if (b2b <= 23) return 3;
    if (b2b <= 66) return 4;
    if (b2b <= 184) return 5;
    if (b2b <= 503) return 6;
    return 7;
  }

  /// Raw attack (before the garbage multiplier) for a clear of [lines]
  /// with [spin] (0 none, 1 mini, 2 T-Spin), chain [b2b] (≥1 = back-to-back),
  /// [combo] (0 = first clear in a row) and perfect clear [pc].
  static double rawAttack(int lines, {int spin = 0, int b2b = 0, int combo = 0, bool pc = false}) {
    if (lines <= 0) return 0;
    double a;
    if (spin == 2) {
      a = [0, 2, 4, 6, 6][lines.clamp(0, 4)].toDouble();
    } else if (spin == 1) {
      a = [0, 0, 1, 2, 2][lines.clamp(0, 4)].toDouble();
    } else {
      a = [0, 0, 1, 2, 4][lines.clamp(0, 4)].toDouble();
    }
    a += b2bBonus(b2b);
    if (combo > 0) {
      a = a > 0 ? a * (1 + 0.25 * combo) : log(1 + combo * 1.25);
    }
    if (pc) a += 10;
    return a;
  }

  /// Garbage lines sent (floored) — convenience for tests / UI.
  static int attackFor(int lines, int combo, {int spin = 0, int b2b = 0, bool pc = false, double mult = 1}) =>
      (rawAttack(lines, spin: spin, b2b: b2b, combo: combo, pc: pc) * mult + 1e-9).floor();

  late int startLevel;
  late String targeting; // random | payback
  final List<String> seq = [];
  late List<TetrisPlayer> ps;
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

  /// 认输 = topped out right now (ranked after everyone who didn't resign).
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (!p.alive) throw GameError('你已出局');
    p.resigned = true;
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    _eliminate(p);
    _checkEnd();
  }

  @override
  int get botDelayMs => 400;

  @override
  void start() {
    startLevel = setup.opt<int>('level', 1).clamp(1, 15);
    targeting = setup.opt<String>('target', 'random');
    ps = [for (var i = 0; i < players; i++) TetrisPlayer()];
    for (final p in ps) {
      _spawn(p);
    }
    host.log('俄罗斯方块对战（TETR.IO 规则）开始！T-Spin / B2B / 连击 / 全消都会送出更多垃圾行，'
        '${marginSec ~/ 60} 分钟后垃圾倍率逐渐提升，坚持到最后获胜！');
    host.schedule(tickMs, _tick);
  }

  String pieceAt(int i) {
    while (seq.length <= i) {
      seq.addAll(shuffled(types.split(''), rng));
    }
    return seq[i];
  }

  int get elapsedSec => max(0, tick - countdownTicks) ~/ tps;

  /// Speed level: start level, +1 per 10 lines, +1 per minute.
  int level(TetrisPlayer p) => startLevel + p.lines ~/ 10 + elapsedSec ~/ 60;

  /// Gravity in rows per second (guideline curve, capped at 20G-ish).
  static double gravityOf(int level) {
    final l = level.clamp(1, 20);
    final secPerRow = pow(0.8 - (l - 1) * 0.007, l - 1).toDouble();
    return min(60.0, 1 / secPerRow);
  }

  double get garbageMultiplier => 1 + max(0, elapsedSec - marginSec) * 0.008;

  bool fits(List<int> board, List<List<int>> cells) {
    for (final c in cells) {
      if (c[0] < 0 || c[0] >= w || c[1] >= rows || c[1] < 0) return false;
      if (board[c[1] * w + c[0]] != 0) return false;
    }
    return true;
  }

  bool _fitsP(TetrisPlayer p, int r, int x, int y) => fits(p.board, cellsOf(p.cur, r, x, y));

  void _spawn(TetrisPlayer p, [String? forced]) {
    final t = forced ?? pieceAt(p.seqIdx++);
    pieceAt(p.seqIdx + 6); // keep previews generated so bot() never extends seq
    p.cur = t;
    p.r = 0;
    p.x = t == 'O' ? 4 : 3;
    p.y = t == 'I' ? buffer - 1 : buffer; // top two visible rows
    p.lockT = 0;
    p.resets = 0;
    p.acc = 0;
    p.lastRot = false;
    p.lastKick = 0;
    p.lowest = p.y;
    for (var up = 0; up <= 2; up++) {
      if (_fitsP(p, p.r, p.x, p.y - up)) {
        p.y -= up;
        return;
      }
    }
    _eliminate(p); // block out
  }

  void _eliminate(TetrisPlayer p) {
    if (!p.alive) return;
    p.alive = false;
    p.deathTick = tick;
    p.queue.clear();
    final k = p.lastAttacker;
    if (k >= 0 && k < players && ps[k].alive) ps[k].kos++;
    if (p.resigned) return;
    host.log('${name(ps.indexOf(p))} 顶到天花板，出局！${k >= 0 && k < players ? '（${name(k)} KO）' : ''}');
  }

  bool _grounded(TetrisPlayer p) => !_fitsP(p, p.r, p.x, p.y + 1);

  /// Successful move/rotate while grounded resets the lock timer (limited).
  void _touch(TetrisPlayer p) {
    if (_grounded(p) && p.resets < maxResets) {
      p.lockT = 0;
      p.resets++;
    }
  }

  void _fell(TetrisPlayer p) {
    p.lastRot = false;
    if (p.y > p.lowest) {
      p.lowest = p.y;
      p.resets = 0;
      p.lockT = 0;
    }
  }

  bool _move(TetrisPlayer p, int dx) {
    if (!_fitsP(p, p.r, p.x + dx, p.y)) return false;
    p.x += dx;
    p.lastRot = false;
    _touch(p);
    return true;
  }

  static List<List<int>> kicksFor(String t, int from, int to) {
    if (((to - from) & 3) == 2) return _k180['$from$to']!;
    return (t == 'I' ? _kI : _kJlstz)['$from$to']!;
  }

  bool _rotate(TetrisPlayer p, int dir) {
    if (p.cur == 'O') return false;
    final from = p.r & 3, nr = (p.r + dir) & 3;
    final ks = kicksFor(p.cur, from, nr);
    for (var i = 0; i < ks.length; i++) {
      final dx = ks[i][0], dy = -ks[i][1];
      if (_fitsP(p, nr, p.x + dx, p.y + dy)) {
        p.r = nr;
        p.x += dx;
        p.y += dy;
        p.lastRot = true;
        p.lastKick = i;
        p.lastRot180 = (dir & 3) == 2;
        _touch(p);
        if (p.y > p.lowest) {
          p.lowest = p.y;
          p.resets = 0;
        }
        return true;
      }
    }
    return false;
  }

  int _dropDistance(TetrisPlayer p) {
    var d = 0;
    while (_fitsP(p, p.r, p.x, p.y + d + 1)) {
      d++;
    }
    return d;
  }

  void _applyKey(int seat, TetrisPlayer p, String k) {
    switch (k) {
      case 'left':
        _move(p, -1);
      case 'right':
        _move(p, 1);
      case 'dasl':
        while (_move(p, -1)) {}
      case 'dasr':
        while (_move(p, 1)) {}
      case 'rotate':
      case 'cw':
        _rotate(p, 1);
      case 'ccw':
        _rotate(p, 3);
      case 'r180':
        _rotate(p, 2);
      case 'soft':
        if (_fitsP(p, p.r, p.x, p.y + 1)) {
          p.y++;
          p.score += 1;
          p.acc = 0;
          _fell(p);
        }
      case 'sonic':
        final d = _dropDistance(p);
        if (d > 0) {
          p.y += d;
          p.score += d;
          p.acc = 0;
          _fell(p);
        }
      case 'hard':
        final d = _dropDistance(p);
        if (d > 0) {
          p.y += d;
          p.score += 2 * d;
          p.lastRot = false;
        }
        _lock(seat, p);
      case 'hold':
        if (p.holdUsed) return;
        final old = p.hold;
        p.hold = p.cur;
        p.holdUsed = true;
        _spawn(p, old);
    }
  }

  /// Clears full rows of [board] in place; returns the number cleared.
  static int clearLines(List<int> board) {
    final hh = board.length ~/ w;
    var n = 0;
    for (var y = hh - 1; y >= 0;) {
      var full = true;
      for (var x = 0; x < w; x++) {
        if (board[y * w + x] == 0) {
          full = false;
          break;
        }
      }
      if (!full) {
        y--;
        continue;
      }
      n++;
      for (var yy = y; yy > 0; yy--) {
        for (var x = 0; x < w; x++) {
          board[yy * w + x] = board[(yy - 1) * w + x];
        }
      }
      for (var x = 0; x < w; x++) {
        board[x] = 0;
      }
    }
    return n;
  }

  /// Pushes [n] garbage rows (hole at [hole]) up from the bottom.
  /// Returns false if blocks were pushed off the top.
  static bool addGarbage(List<int> board, int n, int hole) {
    final hh = board.length ~/ w;
    n = min(n, hh);
    var ok = true;
    for (var i = 0; i < n * w; i++) {
      if (board[i] != 0) ok = false;
    }
    for (var y = 0; y < hh - n; y++) {
      for (var x = 0; x < w; x++) {
        board[y * w + x] = board[(y + n) * w + x];
      }
    }
    for (var y = hh - n; y < hh; y++) {
      for (var x = 0; x < w; x++) {
        board[y * w + x] = x == hole ? 0 : 8;
      }
    }
    return ok;
  }

  /// 0 none, 1 mini, 2 full T-Spin — call before the piece is written.
  int spinOf(TetrisPlayer p) {
    if (p.cur != 'T' || !p.lastRot) return 0;
    bool filled(int cx, int cy) {
      final x = p.x + cx, y = p.y + cy;
      if (x < 0 || x >= w || y >= rows || y < 0) return true;
      return p.board[y * w + x] != 0;
    }

    final corners = [filled(0, 0), filled(2, 0), filled(2, 2), filled(0, 2)]; // TL TR BR BL
    final count = corners.where((c) => c).length;
    if (count < 3) return 0;
    // front corners for each rotation (pointing up / right / down / left)
    final front = const [[0, 1], [1, 2], [2, 3], [3, 0]][p.r & 3];
    if (corners[front[0]] && corners[front[1]]) return 2;
    // TST / fin kick upgrades a mini to a full spin
    if (!p.lastRot180 && p.lastKick == 4) return 2;
    return 1;
  }

  void _lock(int seat, TetrisPlayer p) {
    final spin = spinOf(p);
    final cells = cellsOf(p.cur, p.r, p.x, p.y);
    var allAbove = true;
    final code = types.indexOf(p.cur) + 1;
    for (final c in cells) {
      if (c[1] >= buffer) allAbove = false;
      p.board[c[1] * w + c[0]] = code;
    }
    p.pieceNo++;
    p.holdUsed = false;
    p.queue.clear();
    final n = clearLines(p.board);
    final pc = n > 0 && p.board.every((v) => v == 0);
    final lv = level(p);
    if (n > 0) {
      final difficult = n == 4 || spin > 0;
      if (difficult) {
        p.b2b++;
      } else {
        p.b2b = -1;
      }
      p.combo++;
      final chain = difficult ? max(0, p.b2b) : 0;
      var atk = (rawAttack(n, spin: spin, b2b: chain, combo: p.combo - 1, pc: pc) * garbageMultiplier + 1e-9).floor();
      p.lines += n;
      var sc = spin == 2 ? spinScore[n.clamp(0, 3)] : (spin == 1 ? miniScore[n.clamp(0, 3)] : scoreTable[n.clamp(0, 4)]);
      if (chain > 0) sc = sc * 3 ~/ 2;
      p.score += sc * lv + 50 * (p.combo - 1) * lv + (pc ? 3500 * lv : 0);
      final sentRaw = atk;
      // cancel own incoming garbage first (oldest first)
      while (atk > 0 && p.incoming.isNotEmpty) {
        final g = p.incoming.first;
        final c = min(atk, g.lines);
        g.lines -= c;
        atk -= c;
        if (g.lines == 0) p.incoming.removeAt(0);
      }
      var target = -1;
      if (atk > 0) {
        target = _pickTarget(seat);
        if (target >= 0) _send(seat, target, atk);
      }
      p.ev = {
        'k': tick,
        'n': n,
        'sp': spin,
        'b2b': chain,
        'cb': p.combo - 1,
        'pc': pc,
        'a': sentRaw,
        't': target,
      };
    } else {
      p.combo = 0;
      if (spin > 0) {
        p.score += (spin == 2 ? spinScore[0] : miniScore[0]) * lv;
        p.ev = {'k': tick, 'n': 0, 'sp': spin, 'b2b': 0, 'cb': 0, 'pc': false, 'a': 0, 't': -1};
      }
      if (allAbove) {
        _eliminate(p); // lock out
        return;
      }
      // receive ready garbage (≤ cap lines per placement)
      var take = garbageCap;
      while (take > 0 && p.incoming.isNotEmpty && p.incoming.first.ready <= tick) {
        final g = p.incoming.first;
        final c = min(take, g.lines);
        if (!addGarbage(p.board, c, g.hole)) {
          _eliminate(p);
          return;
        }
        g.lines -= c;
        take -= c;
        if (g.lines == 0) p.incoming.removeAt(0);
      }
    }
    if (n > 0 && allAbove && !cells.any((c) => c[1] >= buffer)) {
      // cleared lines pulled everything down: fine, not a lock out
    }
    _spawn(p);
  }

  int _pickTarget(int seat) {
    final opp = [for (var s = 0; s < players; s++) if (s != seat && ps[s].alive) s];
    if (opp.isEmpty) return -1;
    if (targeting == 'payback') {
      final a = ps[seat].lastAttacker;
      if (opp.contains(a)) return a;
    }
    return opp[rng.nextInt(opp.length)];
  }

  void _send(int from, int to, int lines) {
    final t = ps[to];
    var hole = rng.nextInt(w);
    if (hole == t.lastHole) hole = (hole + 1 + rng.nextInt(w - 1)) % w;
    t.lastHole = hole;
    t.incoming.add(Garbage(lines, hole, tick + garbageDelay, from));
    t.lastAttacker = from;
    ps[from].sent += lines;
  }

  void _drain(int s, TetrisPlayer p) {
    while (p.queue.isNotEmpty && p.alive) {
      final (k, pid) = p.queue.removeAt(0);
      if (pid >= 0 && pid != p.pieceNo) continue;
      _applyKey(s, p, k);
    }
  }

  void _tick() {
    if (over) return;
    tick++;
    if (countdown > 0) {
      countdown--;
    } else {
      for (var s = 0; s < players; s++) {
        final p = ps[s];
        if (!p.alive) continue;
        _drain(s, p);
        if (!p.alive) continue;
        // gravity in 1/1000 rows
        p.acc += (gravityOf(level(p)) * 1000 / tps).round();
        var falls = p.acc ~/ 1000;
        p.acc %= 1000;
        while (falls-- > 0 && _fitsP(p, p.r, p.x, p.y + 1)) {
          p.y++;
          _fell(p);
        }
        if (_grounded(p)) {
          p.lockT++;
          if (p.lockT >= lockTicks) _lock(s, p);
        } else {
          p.lockT = 0;
        }
      }
    }
    _checkEnd();
    if (!over) host.schedule(tickMs, _tick);
  }

  void _checkEnd() {
    if (over) return;
    final alive = [for (final p in ps) if (p.alive) p];
    if (alive.length <= 1) {
      _finish(alive.isEmpty ? '全部出局' : '${name(ps.indexOf(alive.first))} 坚持到了最后');
    } else if (tick >= maxTicks) {
      _finish('时间到');
    }
  }

  void _finish(String why) {
    over = true;
    ranking = buildRanking(players, (a, b) {
      final ra = ps[a].resignNo, rb = ps[b].resignNo;
      if (ra != rb) return ra == 0 ? -1 : (rb == 0 ? 1 : rb - ra);
      final da = ps[a].alive ? 1 << 30 : ps[a].deathTick, db = ps[b].alive ? 1 << 30 : ps[b].deathTick;
      if (da != db) return db - da;
      return ps[b].score - ps[a].score;
    }, (s) => {'score': ps[s].score, 'lines': ps[s].lines, 'sent': ps[s].sent, 'kos': ps[s].kos, 'alive': ps[s].alive, 'resigned': ps[s].resigned});
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
    if (type != 'input') throw GameError('未知操作');
    final p = ps[seat];
    if (!p.alive) throw GameError('你已出局');
    final raw = a['keys'] ?? (a['key'] != null ? [a['key']] : null);
    if (raw is! List || raw.isEmpty || raw.length > maxQueue) throw GameError('操作无效');
    final ks = <String>[];
    for (final k in raw) {
      if (k is! String || !keys.contains(k)) throw GameError('未知按键');
      ks.add(k);
    }
    final pid = a.containsKey('pid') ? asInt(a['pid'], -2) : -1;
    if (pid < -1) throw GameError('操作无效');
    for (final k in ks) {
      if (p.queue.length >= maxQueue) break;
      p.queue.add((k, pid));
    }
    p.lastInput = tick;
    // Apply right away (the host pushes the new view after handle): moves
    // feel instant instead of waiting for the next tick.
    if (countdown == 0) {
      _drain(seat, p);
      _checkEnd();
    }
  }

  // ---------------------------------------------------------------- bot

  /// Board evaluation (Dellacherie-style weights) over the whole board.
  static double evaluate(List<int> board, int lines) {
    final hh = board.length ~/ w;
    var agg = 0, holes = 0, bump = 0, prev = -1, maxH = 0;
    for (var x = 0; x < w; x++) {
      var colH = 0;
      var seen = false;
      for (var y = 0; y < hh; y++) {
        if (board[y * w + x] != 0) {
          if (!seen) {
            seen = true;
            colH = hh - y;
          }
        } else if (seen) {
          holes++;
        }
      }
      agg += colH;
      if (colH > maxH) maxH = colH;
      if (prev >= 0) bump += (colH - prev).abs();
      prev = colH;
    }
    return -0.51 * agg + 0.76 * lines - 0.36 * holes * 2 - 0.18 * bump - (maxH > 14 ? (maxH - 14) * 2.0 : 0);
  }

  /// Piece [i] of the shared sequence if already generated (bot() must not
  /// extend [seq]: that would consume game randomness).
  String? _peek(int i) => i < seq.length ? seq[i] : null;

  /// Every reachable placement of [start]'s piece on [board] (rotations ×
  /// columns, simulated with the real SRS movement code), skipping lock outs.
  List<_Placement> _placements(TetrisPlayer start, List<int> board, List<String> prefix) {
    final out = <_Placement>[];
    final t = start.cur;
    for (final rot in t == 'O' ? const [<String>[]] : const [<String>[], ['cw'], ['r180'], ['ccw']]) {
      for (var dx = -5; dx <= 5; dx++) {
        final sim = start.clone()..board = board;
        var ok = true;
        for (final k in rot) {
          if (!_rotate(sim, k == 'cw' ? 1 : (k == 'ccw' ? 3 : 2))) ok = false;
        }
        if (!ok) continue;
        final moves = <String>[];
        for (var i = 0; i < dx.abs(); i++) {
          if (!_move(sim, dx < 0 ? -1 : 1)) {
            ok = false;
            break;
          }
          moves.add(dx < 0 ? 'left' : 'right');
        }
        if (!ok) continue;
        sim.y += _dropDistance(sim);
        final cells = cellsOf(t, sim.r, sim.x, sim.y);
        final b = List<int>.of(board);
        var above = true;
        for (final c in cells) {
          if (c[1] >= buffer) above = false;
          b[c[1] * w + c[0]] = 1;
        }
        final n = clearLines(b);
        if (above && n == 0) continue;
        final sc = evaluate(b, n) + (n >= 2 ? n * 0.5 : 0) + (n == 4 ? 3 : 0);
        out.add(_Placement([...prefix, ...rot, ...moves, 'hard'], b, sc));
      }
    }
    return out;
  }

  TetrisPlayer _spawned(TetrisPlayer p, String t) {
    final h = p.clone()
      ..cur = t
      ..r = 0;
    return h
      ..x = t == 'O' ? 4 : 3
      ..y = t == 'I' ? buffer - 1 : buffer;
  }

  /// Best key sequence for [p] (optionally via hold). [level] 0 plays
  /// sloppily (no hold, frequent random placements), 2 looks one piece ahead.
  /// Read-only: never changes game state.
  List<String> bestKeys(TetrisPlayer p, {int level = 1}) {
    final cands = _placements(p, p.board, const []);
    final nextAfter = _peek(p.seqIdx); // piece that follows the current one
    if (level >= 1 && !p.holdUsed) {
      final ht = p.hold ?? _peek(p.seqIdx);
      if (ht != null) {
        final h = _spawned(p, ht);
        if (fits(p.board, cellsOf(h.cur, 0, h.x, h.y))) {
          cands.addAll(_placements(h, p.board, const ['hold']));
        }
      }
    }
    if (cands.isEmpty) return const ['hard'];
    if (level <= 0 && rng.nextInt(10) < 3) return cands[rng.nextInt(cands.length)].keys;
    cands.sort((a, b) => b.score.compareTo(a.score));
    if (level >= 2) {
      // one-piece lookahead on the most promising placements
      _Placement? best;
      var bestV = double.negativeInfinity;
      for (final c in cands.take(8)) {
        final usedHold = c.keys.isNotEmpty && c.keys.first == 'hold';
        // hold with an empty slot consumes the next piece, so the follower is one further
        final nt = usedHold && p.hold == null ? _peek(p.seqIdx + 1) : nextAfter;
        var v = c.score;
        if (nt != null) {
          final follow = _placements(_spawned(p, nt), c.board, const []);
          v = follow.isEmpty ? -1e6 : c.score * 0.3 + follow.map((f) => f.score).reduce(max);
        }
        if (v > bestV) {
          bestV = v;
          best = c;
        }
      }
      return best!.keys;
    }
    return cands.first.keys;
  }

  int get _botPace => switch (botLevel) { 0 => tps, 2 => tps ~/ 3, _ => botPace };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players) return null;
    final p = ps[seat];
    if (!p.alive || countdown > 0 || p.queue.isNotEmpty || tick - p.lastInput < _botPace) return {'type': 'idle'};
    return {'type': 'input', 'keys': bestKeys(p, level: botLevel), 'pid': p.pieceNo};
  }

  // ---------------------------------------------------------------- view

  List<int> _visible(List<List<int>> cells) => [
        for (final c in cells)
          if (c[1] >= buffer) (c[1] - buffer) * w + c[0]
      ];

  Map<String, dynamic> _pview(TetrisPlayer p) {
    final b = StringBuffer();
    for (var i = buffer * w; i < p.board.length; i++) {
      final v = p.board[i];
      b.write(v == 0 ? '.' : (v == 8 ? 'G' : types[v - 1]));
    }
    return {
      'b': b.toString(),
      't': p.alive ? p.cur : null,
      'a': p.alive ? _visible(cellsOf(p.cur, p.r, p.x, p.y)) : const <int>[],
      'gh': p.alive ? _visible(cellsOf(p.cur, p.r, p.x, p.y + _dropDistance(p))) : const <int>[],
      'h': p.hold,
      'nx': [for (var i = 0; i < 5; i++) pieceAt(p.seqIdx + i)].join(),
      'pid': p.pieceNo,
      'sc': p.score,
      'ln': p.lines,
      'lv': level(p),
      'pd': p.incoming.fold<int>(0, (a, g) => a + g.lines),
      'pr': p.incoming.where((g) => g.ready <= tick).fold<int>(0, (a, g) => a + g.lines),
      'cb': max(0, p.combo - 1),
      'b2b': max(0, p.b2b),
      'ko': p.kos,
      'st': p.sent,
      'al': p.alive,
      'ev': p.ev,
    };
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : (countdown > 0 ? 'countdown' : 'play'),
        'tick': tick,
        'tps': tps,
        'cd': countdown,
        'el': elapsedSec,
        'mult': (garbageMultiplier * 1000).round() / 1000,
        'margin': marginSec,
        'p': [for (final p in ps) _pview(p)],
        'final': ranking,
      };
}

class _Placement {
  final List<String> keys;
  final List<int> board; // board after locking (and clearing)
  final double score;
  _Placement(this.keys, this.board, this.score);
}

class Garbage {
  int lines;
  final int hole;
  final int ready; // tick at which it may rise
  final int from;
  Garbage(this.lines, this.hole, this.ready, this.from);
}

class TetrisPlayer {
  List<int> board = List.filled(TetrisBattle.w * TetrisBattle.rows, 0);
  String cur = 'T';
  int r = 0, x = 3, y = 0;
  String? hold;
  bool holdUsed = false;
  int seqIdx = 0;
  int pieceNo = 0;
  int lockT = 0, resets = 0, acc = 0, lowest = 0;
  bool lastRot = false, lastRot180 = false;
  int lastKick = 0;
  int score = 0, lines = 0, combo = 0, sent = 0, kos = 0;
  int b2b = -1; // -1 = no chain yet; 0 = one difficult clear; ≥1 = back-to-back
  final List<Garbage> incoming = [];
  int lastHole = -1, lastAttacker = -1;
  bool alive = true;
  int deathTick = 0;
  int lastInput = -100;
  bool resigned = false;
  int resignNo = 0; // order of resigning (later = better placed)
  Map<String, dynamic>? ev;
  final List<(String, int)> queue = [];

  /// Movement-only copy for bot search (shares the board list read-only).
  TetrisPlayer clone() => TetrisPlayer()
    ..board = board
    ..cur = cur
    ..r = r
    ..x = x
    ..y = y
    ..lowest = lowest;
}
