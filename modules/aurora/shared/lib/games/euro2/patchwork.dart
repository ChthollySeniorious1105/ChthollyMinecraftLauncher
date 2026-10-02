import 'dart:math';

import '../../src/engine.dart';

/// A patch: cost (buttons), time, button income, shape rows ('X' filled).
class PwPatch {
  final int cost, time, income;
  final List<String> rows;
  const PwPatch(this.cost, this.time, this.income, this.rows);
  List<(int, int)> get cells => [
        for (var y = 0; y < rows.length; y++)
          for (var x = 0; x < rows[y].length; x++)
            if (rows[y][x] == 'X') (x, y),
      ];
}

/// 33 patches (index 0 = the small 1×2 starter patch placed last in the ring).
const List<PwPatch> pwPatches = [
  PwPatch(2, 1, 0, ['XX']),
  PwPatch(2, 2, 0, ['XXX']),
  PwPatch(3, 1, 0, ['XX', 'X.']),
  PwPatch(1, 3, 0, ['XX', '.X']),
  PwPatch(1, 2, 0, ['X.X', 'XXX']),
  PwPatch(3, 3, 1, ['XXXX']),
  PwPatch(6, 5, 2, ['XX', 'XX']),
  PwPatch(3, 2, 1, ['X.', 'XX', '.X']),
  PwPatch(2, 2, 0, ['XXX', '.X.']),
  PwPatch(4, 2, 1, ['XXX', 'X..']),
  PwPatch(3, 3, 1, ['XXXX', 'X...']),
  PwPatch(7, 1, 1, ['XXXXX']),
  PwPatch(5, 4, 2, ['.X.', 'XXX', '.X.']),
  PwPatch(2, 3, 0, ['X.X', 'XXX', 'X.X']),
  PwPatch(8, 6, 3, ['XX.', 'XXX']),
  PwPatch(10, 5, 3, ['XX', 'XX', 'XX']),
  PwPatch(7, 6, 3, ['.XX', 'XX.', 'X..']),
  PwPatch(10, 3, 2, ['XXX.', '..XX']),
  PwPatch(4, 6, 2, ['XX..', '.XXX']),
  PwPatch(1, 5, 1, ['X...', 'XXXX', 'X...']),
  PwPatch(5, 3, 1, ['.X.', 'XXX', 'X.X']),
  PwPatch(0, 3, 1, ['.X..', 'XXXX', '.X..']),
  PwPatch(1, 4, 1, ['XX.', '.XX', '..X']),
  PwPatch(3, 4, 1, ['.X.', '.X.', 'XXX']),
  PwPatch(2, 1, 0, ['X..', 'XXX', '..X']),
  PwPatch(7, 2, 2, ['XXX', '.X.', '.X.']),
  PwPatch(5, 5, 2, ['.X.', 'XXX', '.X.', '.X.']),
  PwPatch(10, 4, 3, ['X..', 'XX.', '.XX']),
  PwPatch(4, 2, 0, ['XXX', 'XX.']),
  PwPatch(1, 2, 0, ['.XX.', 'XXXX']),
  PwPatch(6, 3, 2, ['XXXX', '.XX.']),
  PwPatch(2, 3, 1, ['.X.', 'XXX', '.X.', 'X..']),
  PwPatch(3, 6, 2, ['..X.', 'XXXX', '.X..']),
];

const pwEnd = 53;
const pwIncomeMarks = [5, 11, 17, 23, 29, 35, 41, 47, 53];
const pwLeatherInit = [26, 32, 38, 44, 50];
const pwLeather = 100; // board code for 1×1 leather patches

/// Normalised oriented cells of [patch] for rotation [rot] (0..3) and [flip].
List<(int, int)> pwOrient(int patch, int rot, bool flip) {
  var cs = pwPatches[patch].cells;
  if (flip) cs = [for (final (x, y) in cs) (-x, y)];
  for (var r = 0; r < rot; r++) {
    cs = [for (final (x, y) in cs) (-y, x)];
  }
  final mx = cs.map((c) => c.$1).reduce(min), my = cs.map((c) => c.$2).reduce(min);
  return [for (final (x, y) in cs) (x - mx, y - my)]..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
}

class Patchwork extends GameEngine {
  Patchwork(super.setup);

  List<int> ring = [];
  int np = 0;
  final List<int> pos = [0, 0];
  final List<int> buttons = [5, 5];
  final List<List<int>> board = [List.filled(81, 0), List.filled(81, 0)];
  final List<int> income = [0, 0];
  List<int> leather = List.of(pwLeatherInit);
  int top = 0; // seat whose token is on top (moved there last)
  int bonus7 = -1;
  int pendingLeather = 0;
  int leatherSeat = -1;
  String phase = 'turn'; // turn / leather / over
  int firstFinish = -1;
  int resigned = -1;
  Map<String, dynamic>? last;
  final List<String> recent = [];
  Map<String, dynamic>? result;

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 8) recent.removeAt(0);
  }

  int get turn {
    if (pos[0] < pos[1]) return 0;
    if (pos[1] < pos[0]) return 1;
    return top;
  }

  @override
  void start() {
    ring = [...shuffled(List.generate(32, (i) => i + 1), rng), 0];
    np = 0;
    top = rng.nextInt(2);
    _log('拼布艺术：${name(top)} 先手');
  }

  List<int> get available => ring.isEmpty ? const [] : [for (var k = 0; k < min(3, ring.length); k++) ring[(np + k) % ring.length]];

  bool fits(int seat, List<(int, int)> cells, int x, int y) {
    for (final (dx, dy) in cells) {
      final cx = x + dx, cy = y + dy;
      if (cx < 0 || cy < 0 || cx >= 9 || cy >= 9) return false;
      if (board[seat][cy * 9 + cx] != 0) return false;
    }
    return true;
  }

  List<(int, int, int, bool)> placements(int seat, int patch) {
    final out = <(int, int, int, bool)>[];
    final seen = <String>{};
    for (final flip in const [false, true]) {
      for (var r = 0; r < 4; r++) {
        final cs = pwOrient(patch, r, flip);
        final key = cs.map((c) => '${c.$1},${c.$2}').join(';');
        if (!seen.add(key)) continue;
        for (var y = 0; y < 9; y++) {
          for (var x = 0; x < 9; x++) {
            if (fits(seat, cs, x, y)) out.add((x, y, r, flip));
          }
        }
      }
    }
    return out;
  }

  bool canPlaceAnywhere(int seat, int patch) {
    for (final flip in const [false, true]) {
      for (var r = 0; r < 4; r++) {
        final cs = pwOrient(patch, r, flip);
        for (var y = 0; y < 9; y++) {
          for (var x = 0; x < 9; x++) {
            if (fits(seat, cs, x, y)) return true;
          }
        }
      }
    }
    return false;
  }

  bool _has7(int seat) {
    for (var oy = 0; oy <= 2; oy++) {
      for (var ox = 0; ox <= 2; ox++) {
        var ok = true;
        for (var y = oy; y < oy + 7 && ok; y++) {
          for (var x = ox; x < ox + 7; x++) {
            if (board[seat][y * 9 + x] == 0) {
              ok = false;
              break;
            }
          }
        }
        if (ok) return true;
      }
    }
    return false;
  }

  void _check7(int seat) {
    if (bonus7 == -1 && _has7(seat)) {
      bonus7 = seat;
      _log('${name(seat)} 率先拼满 7×7，获得 +7 奖励板块');
    }
  }

  /// Move [seat]'s time token to [to]; collects income and leather patches.
  void _moveTo(int seat, int to) {
    final from = pos[seat];
    to = min(to, pwEnd);
    pos[seat] = to;
    top = seat;
    for (final m in pwIncomeMarks) {
      if (from < m && m <= to && income[seat] > 0) {
        buttons[seat] += income[seat];
        _log('${name(seat)} 经过收入格，获得 ${income[seat]} 纽扣');
      }
    }
    for (final l in List.of(leather)) {
      if (from < l && l <= to) {
        leather.remove(l);
        pendingLeather++;
      }
    }
    if (to == pwEnd && firstFinish == -1) firstFinish = seat;
  }

  void _afterMove(int seat) {
    if (pendingLeather > 0) {
      // skip if the board has no free cell
      if (!board[seat].contains(0)) {
        _log('${name(seat)} 获得皮革补丁但棋盘已满，只能放弃');
        pendingLeather = 0;
      } else {
        phase = 'leather';
        leatherSeat = seat;
        return;
      }
    }
    phase = 'turn';
    leatherSeat = -1;
    if (pos[0] >= pwEnd && pos[1] >= pwEnd) _end();
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (phase == 'leather') {
      if (seat != leatherSeat) throw GameError('等待对手放置皮革补丁');
      if (type != 'leather') throw GameError('请先放置 1×1 皮革补丁');
      final x = asInt(a['x']), y = asInt(a['y']);
      if (x < 0 || y < 0 || x >= 9 || y >= 9 || board[seat][y * 9 + x] != 0) throw GameError('这里不能放');
      board[seat][y * 9 + x] = pwLeather;
      pendingLeather--;
      last = {'seat': seat, 'type': 'leather', 'x': x, 'y': y};
      _log('${name(seat)} 放置了皮革补丁');
      _check7(seat);
      _afterMove(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'advance') {
      final target = min(pos[1 - seat] + 1, pwEnd);
      final gain = target - pos[seat];
      if (gain <= 0) throw GameError('无法前进');
      buttons[seat] += gain;
      last = {'seat': seat, 'type': 'advance', 'n': gain};
      _log('${name(seat)} 前进 $gain 格，获得 $gain 纽扣');
      _moveTo(seat, target);
      _afterMove(seat);
      return;
    }
    if (type != 'buy') throw GameError('无效操作');
    final k = asInt(a['k']);
    final av = available;
    if (k < 0 || k >= av.length) throw GameError('只能选择中立标记前方的 3 块布片');
    final p = av[k];
    final patch = pwPatches[p];
    if (buttons[seat] < patch.cost) throw GameError('纽扣不足（需要 ${patch.cost}）');
    final rot = asInt(a['rot'], 0), flip = asBool(a['flip']);
    if (rot < 0 || rot > 3) throw GameError('无效旋转');
    final cs = pwOrient(p, rot, flip);
    final x = asInt(a['x']), y = asInt(a['y']);
    if (!fits(seat, cs, x, y)) throw GameError('这里放不下这块布片');
    for (final (dx, dy) in cs) {
      board[seat][(y + dy) * 9 + x + dx] = p + 1;
    }
    buttons[seat] -= patch.cost;
    income[seat] += patch.income;
    final idx = (np + k) % ring.length;
    ring.removeAt(idx);
    np = ring.isEmpty ? 0 : idx % ring.length;
    last = {'seat': seat, 'type': 'buy', 'patch': p, 'x': x, 'y': y, 'rot': rot, 'flip': flip};
    _log('${name(seat)} 花 ${patch.cost} 纽扣买下布片（时间 ${patch.time}${patch.income > 0 ? '，收入 +${patch.income}' : ''}）');
    _check7(seat);
    _moveTo(seat, pos[seat] + patch.time);
    _afterMove(seat);
  }

  int emptyCells(int s) => board[s].where((c) => c == 0).length;
  int scoreOf(int s) => buttons[s] - 2 * emptyCells(s) + (bonus7 == s ? 7 : 0);

  void _end() {
    phase = 'over';
    result = {
      'rows': [
        for (var s = 0; s < 2; s++) {'seat': s, 'buttons': buttons[s], 'empty': emptyCells(s), 'bonus': bonus7 == s ? 7 : 0, 'score': scoreOf(s)}
      ],
    };
    final pl = placings!;
    final w = pl[0] == 1 ? 0 : 1;
    _log('游戏结束！${name(w)} 获胜（${name(0)} ${scoreOf(0)} / ${name(1)} ${scoreOf(1)}）');
  }

  @override
  List<int> get waitingFor {
    if (phase == 'over') return const [];
    if (phase == 'leather') return [leatherSeat];
    return [turn];
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (resigned >= 0) return rankWinners(2, [1 - resigned]);
    final a = scoreOf(0), b = scoreOf(1);
    if (a != b) return a > b ? [1, 2] : [2, 1];
    return firstFinish == 1 ? [2, 1] : [1, 2];
  }

  @override
  bool get canResign => phase != 'over';

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    if (seat < 0 || seat > 1) throw GameError('无效座位');
    resigned = seat;
    phase = 'over';
    _log('${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': phase,
        'turn': phase == 'leather' ? leatherSeat : turn,
        'ring': ring,
        'np': np,
        'available': available,
        'patches': [for (final p in pwPatches) {'cost': p.cost, 'time': p.time, 'income': p.income, 'rows': p.rows}],
        'pos': pos,
        'buttons': buttons,
        'income': income,
        'boards': board,
        'leather': leather,
        'incomeMarks': pwIncomeMarks,
        'end': pwEnd,
        'bonus7': bonus7,
        'pendingLeather': pendingLeather,
        'scores': [scoreOf(0), scoreOf(1)],
        'last': last,
        'recent': recent,
        'result': result,
        'resigned': resigned,
        'placings': placings,
      };

  // ------------------------------------------------------------------ bot
  int _incomeLeft(int s) => pwIncomeMarks.where((m) => m > pos[s]).length;

  /// Placement quality: prefer edges/filled neighbours, avoid isolated holes.
  double _placeScore(int seat, List<(int, int)> cs, int x, int y) {
    final b = board[seat];
    final filled = {for (final (dx, dy) in cs) (y + dy) * 9 + x + dx};
    var contact = 0;
    for (final (dx, dy) in cs) {
      final cx = x + dx, cy = y + dy;
      for (final (ox, oy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = cx + ox, ny = cy + oy;
        if (nx < 0 || ny < 0 || nx >= 9 || ny >= 9) {
          contact++;
        } else if (b[ny * 9 + nx] != 0 && !filled.contains(ny * 9 + nx)) {
          contact++;
        }
      }
    }
    // holes: empty neighbour cells that become fully enclosed
    var holes = 0;
    for (final (dx, dy) in cs) {
      for (final (ox, oy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx + ox, ny = y + dy + oy;
        if (nx < 0 || ny < 0 || nx >= 9 || ny >= 9) continue;
        final i = ny * 9 + nx;
        if (b[i] != 0 || filled.contains(i)) continue;
        var free = 0;
        for (final (px, py) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final qx = nx + px, qy = ny + py;
          if (qx < 0 || qy < 0 || qx >= 9 || qy >= 9) continue;
          final q = qy * 9 + qx;
          if (b[q] == 0 && !filled.contains(q)) free++;
        }
        if (free == 0) holes++;
      }
    }
    // gravitate to a corner block early (helps the 7×7 bonus)
    final cx = x + cs.map((c) => c.$1).reduce(max) / 2, cy = y + cs.map((c) => c.$2).reduce(max) / 2;
    return contact * 1.0 - holes * 3.0 - (cx + cy) * 0.05;
  }

  (int, int, int, bool)? _bestPlacement(int seat, int patch) {
    final ps = placements(seat, patch);
    if (ps.isEmpty) return null;
    if (botLevel == 0) return ps[rng.nextInt(ps.length)];
    (int, int, int, bool)? best;
    var bv = -1e9;
    for (final p in ps) {
      final v = _placeScore(seat, pwOrient(patch, p.$3, p.$4), p.$1, p.$2) + rng.nextDouble() * 0.01;
      if (v > bv) {
        bv = v;
        best = p;
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'over') return null;
    if (phase == 'leather') {
      if (seat != leatherSeat) return null;
      // 1×1: find best single empty cell (prefer enclosed holes)
      var bi = -1;
      var bv = -1e9;
      for (var i = 0; i < 81; i++) {
        if (board[seat][i] != 0) continue;
        final v = botLevel == 0 ? rng.nextDouble() : _placeScore(seat, const [(0, 0)], i % 9, i ~/ 9) + rng.nextDouble() * 0.01;
        if (v > bv) {
          bv = v;
          bi = i;
        }
      }
      if (bi < 0) return null;
      return {'type': 'leather', 'x': bi % 9, 'y': bi ~/ 9};
    }
    if (seat != turn) return null;
    final av = available;
    final inc = _incomeLeft(seat);
    var bestK = -1;
    var bestV = -1e9;
    for (var k = 0; k < av.length; k++) {
      final p = pwPatches[av[k]];
      if (p.cost > buttons[seat]) continue;
      if (!canPlaceAnywhere(seat, av[k])) continue;
      final size = p.cells.length;
      final timeLeft = pwEnd - pos[seat];
      final t = min(p.time, max(1, timeLeft));
      double v;
      if (botLevel == 0) {
        v = rng.nextDouble() * 10 + size;
      } else {
        final incW = botLevel >= 2 ? 1.0 : 0.8;
        v = (size * 2 + p.income * inc * incW - p.cost) / (t + 0.5);
        if (botLevel >= 2) {
          // late game: time is what's left; big patches cover minus-2 squares
          if (timeLeft < 12) v = (size * 2 - p.cost) - t * 0.8;
          // leaving the opponent with an extra turn behind us costs something
          if (pos[seat] + p.time > pos[1 - seat]) v -= 0.1;
        }
        v += rng.nextDouble() * 0.05;
      }
      if (v > bestV) {
        bestV = v;
        bestK = k;
      }
    }
    final advGain = min(pos[1 - seat] + 1, pwEnd) - pos[seat];
    final advV = botLevel == 0 ? 0.8 : (botLevel >= 2 && pwEnd - pos[seat] < 12 ? advGain.toDouble() - advGain * 0.8 : 1.0 / 1.5);
    if (bestK >= 0 && (bestV > advV || botLevel == 0 && rng.nextDouble() < 0.7)) {
      final pl = _bestPlacement(seat, av[bestK])!;
      return {'type': 'buy', 'k': bestK, 'x': pl.$1, 'y': pl.$2, 'rot': pl.$3, 'flip': pl.$4};
    }
    return {'type': 'advance'};
  }
}

const patchworkRules = '''
# 拼布艺术 Patchwork
两名玩家各自用布片拼出一床 9×9 的被子。纽扣是货币也是分数，时间是另一种资源：谁在时间轨上落后，谁就行动。

# 准备
- 每人 5 颗纽扣，时间标记都在时间轨起点（共 53 格）。
- 33 块布片随机围成一圈，中立标记放在最小的 1×2 布片之后。

# 回合
- 时间轨上落后的玩家行动（位置相同时，后到达的——叠在上面的——先行动），因此一个人可能连续行动多次。
- 行动 A「前进拿纽扣」：把时间标记移到对手前方一格，每前进一格获得 1 颗纽扣。
- 行动 B「购买布片」：从中立标记顺时针前方的 3 块布片中选一块，支付纽扣，放到自己的被子上（可以旋转、翻转，不能重叠，不能超出 9×9），
  中立标记移到该布片的位置；然后时间标记前进布片上的时间数。

# 时间轨上的格子
- 收入格（纽扣图标，共 9 个）：经过时获得等于自己被子上所有布片纽扣收入之和的纽扣。
- 皮革补丁（第 26、32、38、44、50 格）：第一个经过的玩家拿走并立刻放到自己被子的任意空格上（1×1）。

# 7×7 奖励
- 第一个在被子上拼满一个完整 7×7 方块的玩家获得 +7 分奖励板块。

# 结束与计分
- 双方都到达终点后游戏结束。时间不能超过终点，前进只计算实际移动的格数。
- 得分 = 纽扣数 − 被子上每个空格 2 分 + 7×7 奖励。
- 分高者胜；平局时先到达终点的玩家获胜。

# 操作
- 选中一块可购买的布片，用“旋转/翻转”调整方向，再点被子上的格子放置（格子为布片左上角）。
- 可以认输。
''';
