import 'dart:math';

import '../../src/engine.dart';
import 'gomoku_rules.dart';

/// 五子棋：自由 / 标准（恰好五连）/ 连珠禁手（黑棋三三、四四、长连判负）。
class Gomoku extends GameEngine {
  Gomoku(super.setup);

  late final int n = setup.opt<int>('size', 15);
  late final GomokuRule rule = gomokuRuleOf(setup.opt<String>('rule', 'free'));
  late final GomokuBoard b = GomokuBoard(n);

  int blackSeat = 0;
  int turn = 0; // seat to move
  int last = -1;
  int moves = 0;
  int winner = -1; // -1 none, seat, 2 = draw
  List<int> winLine = [];
  String result = '';
  int forbiddenAt = -1; // point where black played a forbidden move
  List<int> _forbidden = const [];
  final List<int> history = [];

  int colorOf(int seat) => seat == blackSeat ? 1 : 2;
  int seatOf(int color) => color == 1 ? blackSeat : 1 - blackSeat;
  bool get over => winner != -1;

  @override
  bool get isOver => over;

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    blackSeat = rng.nextInt(2);
    turn = blackSeat;
    const rn = {GomokuRule.free: '自由规则', GomokuRule.standard: '标准规则', GomokuRule.renju: '连珠禁手'};
    host.log('五子棋 $n 路 · ${rn[rule]}：${name(blackSeat)} 执黑先行');
    _refreshForbidden();
  }

  void _refreshForbidden() {
    if (rule != GomokuRule.renju || over || colorOf(turn) != 1) {
      _forbidden = const [];
      return;
    }
    final out = <int>[];
    for (var p = 0; p < n * n; p++) {
      if (b.cells[p] != 0 || !_nearBlack(p)) continue;
      if (b.isForbidden(p)) out.add(p);
    }
    _forbidden = out;
  }

  bool _nearBlack(int p) {
    final x0 = p % n, y0 = p ~/ n;
    var cnt = 0;
    for (final (dx, dy) in gomokuDirs) {
      for (var s = -4; s <= 4; s++) {
        if (s != 0 && b.at(x0 + dx * s, y0 + dy * s) == 1) cnt++;
      }
    }
    return cnt >= 2;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') {
      if (seat != 0 && seat != 1) throw GameError('你不是棋手');
      resign(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    final p = asInt(a['point']);
    if (p < 0 || p >= n * n || b.cells[p] != 0) throw GameError('这里不能落子');
    final c = colorOf(seat);
    final out = b.outcome(p, c, rule);
    b.cells[p] = c;
    last = p;
    moves++;
    history.add(p);
    if (out == 'forbidden') {
      final t = _typeAt(p);
      forbiddenAt = p;
      winner = 1 - seat;
      result = '黑棋${t.isEmpty ? '' : t}禁手，${name(winner)}（白）获胜';
      host.log(result);
      return;
    }
    if (out == 'win') {
      winner = seat;
      winLine = b.fiveLine(p, c, exact: false) ?? [p];
      result = '${name(seat)}（${c == 1 ? '黑' : '白'}）五连获胜';
      host.log(result);
      return;
    }
    if (moves >= n * n) {
      winner = 2;
      result = '棋盘已满，和棋';
      host.log(result);
      return;
    }
    turn = 1 - turn;
    _refreshForbidden();
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    winner = 1 - seat;
    result = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;

  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    winner = 2;
    result = '双方同意和棋';
    host.log(result);
  }

  String _typeAt(int p) {
    b.cells[p] = 0;
    final t = b.forbiddenType(p) ?? '';
    b.cells[p] = 1;
    return t;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'size': n,
        'rule': rule.name,
        'board': b.cells,
        'blackSeat': blackSeat,
        'turn': turn,
        'last': last,
        'moves': moves,
        'winner': winner,
        'winLine': winLine,
        'forbidden': _forbidden,
        'forbiddenAt': forbiddenAt,
        'result': result,
        'over': over,
      };

  // ---------------------------------------------------------------- bot

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final ai = GomokuAI(b, rule, rng, botLevel);
    final color = colorOf(seat);
    if (botLevel <= 0 && rng.nextDouble() < 0.5) {
      // 简单：随手一步（仍避开明显的禁手点）
      final c = [
        for (final p in ai.candidates())
          if (!(rule == GomokuRule.renju && color == 1 && (_forbidden.contains(p) || b.isForbidden(p)))) p
      ];
      if (c.isNotEmpty) return {'type': 'play', 'point': c[rng.nextInt(c.length)]};
    }
    return {'type': 'play', 'point': ai.best(color, forbidden: _forbidden.toSet())};
  }
}

/// Threat-based heuristic + 2-ply lookahead.
class GomokuAI {
  final GomokuBoard b;
  final GomokuRule rule;
  final Random? rng;

  /// 0 简单（不算 VCF）/ 1 普通 / 2 困难（防对手 VCF、看更多候选点）。
  final int level;
  GomokuAI(this.b, this.rule, [this.rng, this.level = 1]);

  int get n => b.n;

  List<int> candidates() {
    final out = <int>[];
    final cells = b.cells;
    var any = false;
    for (var p = 0; p < n * n; p++) {
      if (cells[p] != 0) {
        any = true;
        continue;
      }
      final x0 = p % n, y0 = p ~/ n;
      var near = false;
      for (var dy = -2; dy <= 2 && !near; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final v = b.at(x0 + dx, y0 + dy);
          if (v > 0) {
            near = true;
            break;
          }
        }
      }
      if (near) out.add(p);
    }
    if (!any) {
      final m = n ~/ 2, j = rng == null ? 0 : rng!.nextInt(3) - 1, k = rng == null ? 0 : rng!.nextInt(3) - 1;
      return [(m + j) * n + m + k];
    }
    if (out.isEmpty) {
      for (var p = 0; p < n * n; p++) {
        if (cells[p] == 0) out.add(p);
      }
    }
    return out;
  }

  /// Shape score of [color] placing a stone at empty p.
  int shape(int p, int color) {
    final x0 = p % n, y0 = p ~/ n;
    var total = 0, strong = 0, fours = 0;
    for (final (dx, dy) in gomokuDirs) {
      // 9-cell line centered on p
      final line = List<int>.filled(9, -1);
      for (var s = -4; s <= 4; s++) {
        final v = b.at(x0 + dx * s, y0 + dy * s);
        line[s + 4] = s == 0 ? color : (v == -1 ? -1 : v);
      }
      var best = 0, cnt4 = 0, cnt3 = 0, cnt2 = 0;
      for (var st = 0; st <= 4; st++) {
        var k = 0, bad = false;
        for (var i = st; i < st + 5; i++) {
          final v = line[i];
          if (v == color) {
            k++;
          } else if (v != 0) {
            bad = true;
            break;
          }
        }
        if (bad) continue;
        if (k > best) best = k;
        if (k == 4) cnt4++;
        if (k == 3) cnt3++;
        if (k == 2) cnt2++;
      }
      var run = 1;
      for (var s = 1; s <= 4 && line[4 + s] == color; s++) {
        run++;
      }
      for (var s = 1; s <= 4 && line[4 - s] == color; s++) {
        run++;
      }
      int sc;
      if (run >= 5) {
        sc = (run == 5 || rule == GomokuRule.free || (rule == GomokuRule.renju && color == 2)) ? 1000000 : 0;
      } else if (best == 4) {
        sc = cnt4 >= 2 ? 50000 : 6000;
        fours++;
        if (cnt4 >= 2) strong++;
      } else if (best == 3) {
        sc = cnt3 >= 2 ? 5000 : 400;
        if (cnt3 >= 2) strong++;
      } else if (best == 2) {
        sc = cnt2 >= 2 ? 300 : 40;
      } else {
        sc = best == 1 ? 4 : 0;
      }
      total += sc;
    }
    if (fours >= 2 || (fours >= 1 && strong >= 1) || strong >= 2) total += 40000;
    return total;
  }

  int best(int color, {Set<int> forbidden = const {}}) {
    final opp = 3 - color;
    var cands = candidates();
    if (rule == GomokuRule.renju && color == 1) {
      final ok = [for (final p in cands) if (!forbidden.contains(p) && !b.isForbidden(p)) p];
      if (ok.isNotEmpty) {
        cands = ok;
      } else {
        final all = [for (var p = 0; p < n * n; p++) if (b.cells[p] == 0 && !b.isForbidden(p)) p];
        if (all.isNotEmpty) cands = all;
      }
    }
    // immediate win / forced block
    for (final p in cands) {
      if (b.outcome(p, color, rule) == 'win') return p;
    }
    for (final p in cands) {
      if (b.outcome(p, opp, rule) == 'win') return p;
    }
    // continuous-four win (VCF)
    _nodes = 0;
    _nodeLimit = level >= 2 ? 8000 : 4000;
    final sw = Stopwatch()..start();
    if (level >= 1) {
      final vcf = _vcf(color, 0, cands);
      if (vcf >= 0) return vcf;
    }
    final scored = <(int, int)>[];
    final c = (n - 1) / 2;
    for (final p in cands) {
      final dx = p % n - c, dy = p ~/ n - c;
      final center = (20 - (dx * dx + dy * dy)).clamp(0, 20).toInt();
      scored.add((p, shape(p, color) * 11 ~/ 10 + shape(p, opp) + center + (rng?.nextInt(12) ?? 0)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // my open four / double threat beats defending
    for (final (p, _) in scored.take(12)) {
      if (shape(p, color) >= 40000) return p;
    }
    // 2-ply: my move, then opponent's best reply
    final top = scored.take(level >= 2 ? 14 : 10).toList();
    var bestP = top.first.$1;
    var bestV = -0x10000000000; // not `-1 << 40`: shifts are 32-bit on the web
    for (final (p, s) in top) {
      b.cells[p] = color;
      // opponent's strongest attacking reply; my follow-up potential
      var reply = 0, follow = 0;
      final wins = _winPts(p, color).length;
      for (final q in candidates()) {
        final r = shape(q, opp);
        if (r > reply) reply = r;
        final f = shape(q, color);
        if (f > follow) follow = f;
      }
      // a simple four forces a reply; judge the position after the block
      if (wins == 1) reply = reply ~/ 2;
      if (wins >= 2) follow = 1 << 20;
      // 困难：对手在这步之后若有连续冲四杀，这步基本等于送死
      var oppVcf = false;
      if (level >= 2 && wins == 0 && sw.elapsedMilliseconds < 900) {
        _nodes = 0;
        _nodeLimit = 1500;
        oppVcf = _vcf(opp, 0) >= 0;
      }
      b.cells[p] = 0;
      final v = s + follow ~/ 3 - reply * 2 ~/ 3 - (oppVcf ? 1 << 22 : 0);
      if (v > bestV) {
        bestV = v;
        bestP = p;
      }
    }
    return bestP;
  }

  int _nodes = 0;
  int _nodeLimit = 4000;

  /// Points on the four lines through p (within 4) where [color] wins at once.
  List<int> _winPts(int p, int color) {
    final out = <int>[];
    final x0 = p % n, y0 = p ~/ n;
    for (final (dx, dy) in gomokuDirs) {
      for (var s = -4; s <= 4; s++) {
        if (s == 0) continue;
        final x = x0 + dx * s, y = y0 + dy * s;
        if (!b.inside(x, y)) continue;
        final q = y * n + x;
        if (b.cells[q] != 0 || out.contains(q)) continue;
        if (b.outcome(q, color, rule) == 'win') out.add(q);
      }
    }
    return out;
  }

  /// Returns the first move of a victory-by-continuous-fours, or -1.
  int _vcf(int color, int depth, [List<int>? pool]) {
    if (depth > 12 || _nodes > _nodeLimit) return -1;
    final opp = 3 - color;
    for (final q in pool ?? candidates()) {
      if (b.cells[q] != 0) continue;
      if (shape(q, color) < 6000) continue; // must make a four
      if (rule == GomokuRule.renju && color == 1 && b.isForbidden(q)) continue;
      _nodes++;
      b.cells[q] = color;
      final w = _winPts(q, color);
      var ok = false;
      if (w.length >= 2) {
        ok = true;
      } else if (w.length == 1) {
        final block = w.first;
        // opponent could win instead of blocking?
        var oppWins = false;
        for (final r in candidates()) {
          if (b.outcome(r, opp, rule) == 'win') {
            oppWins = true;
            break;
          }
        }
        final blockForbidden = rule == GomokuRule.renju && opp == 1 && b.isForbidden(block);
        if (!oppWins) {
          if (blockForbidden) {
            ok = true;
          } else {
            b.cells[block] = opp;
            ok = _vcf(color, depth + 1) >= 0;
            b.cells[block] = 0;
          }
        }
      }
      b.cells[q] = 0;
      if (ok) return q;
    }
    return -1;
  }
}
