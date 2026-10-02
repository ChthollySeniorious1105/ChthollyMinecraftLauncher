import '../../src/engine.dart';
import 'arcade_util.dart';

/// 2048对战 (2-4 人). Turn-free: everyone swipes their own 4×4 board.
/// All boards draw new tiles from the same seeded sequence (per-player index),
/// so luck is equal. Merging a tile of 128 or more (option) drops a 2-tile
/// "block" (value 2, shown as a stone that merges normally) onto every
/// opponent's board. The game ends when every board is stuck or at the time
/// cap; highest score wins.
class Battle2048 extends GameEngine {
  Battle2048(super.setup);

  static const n = 4;
  static const dirs = ['up', 'down', 'left', 'right'];

  late bool attack;
  late int maxSec;
  late List<G2048Player> ps;
  final List<int> seq = []; // spawn randoms: cellPick * 10 + (four ? 1 : 0)
  int sec = 0;
  int moves = 0;
  bool over = false;
  List<Map<String, dynamic>>? ranking;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? placingsOf(ranking, players) : null;

  int _resigns = 0;

  @override
  bool get canResign => !over;

  /// 认输 = stuck now (ranked after everyone who didn't resign). The game
  /// ends when at most one non-resigned player remains or nobody can move.
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (p.resigned) throw GameError('你已认输');
    p.resigned = true;
    if (!p.stuck) {
      p.stuck = true;
      p.stuckSec = sec;
    }
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (!ps[s].resigned) s];
    if (left.length <= 1) {
      _finish(left.isEmpty ? '所有人都已认输' : '其他人都已认输');
    } else if (ps.every((q) => q.stuck)) {
      _finish('所有人都无路可走');
    }
  }

  @override
  int get botDelayMs => 450;

  @override
  void start() {
    attack = setup.opt<bool>('attack', true);
    maxSec = setup.opt<int>('time', 180);
    ps = [for (var s = 0; s < players; s++) G2048Player()];
    for (final p in ps) {
      _spawn(p);
      _spawn(p);
    }
    host.log('2048对战开始！所有人方块序列相同。${attack ? '合成 128 及以上会给对手扔 2 个石块。' : ''}${maxSec ~/ 60} 分钟内分数最高者获胜。');
    host.schedule(1000, _clock);
  }

  void _clock() {
    if (over) return;
    sec++;
    if (sec >= maxSec) {
      _finish('时间到');
      return;
    }
    host.schedule(1000, _clock);
  }

  int _rand(int i) {
    while (seq.length <= i) {
      seq.add(rng.nextInt(1 << 20) * 10 + (rng.nextInt(10) == 0 ? 1 : 0));
    }
    return seq[i];
  }

  void _spawn(G2048Player p) {
    final empty = [for (var i = 0; i < n * n; i++) if (p.b[i] == 0) i];
    if (empty.isEmpty) return;
    final r = _rand(p.seqIdx++);
    final c = empty[(r ~/ 10) % empty.length];
    p.b[c] = r % 10 == 1 ? 4 : 2;
    p.lastSpawn = c;
  }

  /// Slides one line toward index 0. Returns (new line, points, merged values).
  /// Negative values are stones (-2): they take up space and merge like a 2
  /// (with a 2 or another stone), producing a normal 4.
  static (List<int>, int, List<int>) slideLine(List<int> line) {
    final vals = [for (final v in line) if (v != 0) v];
    final out = <int>[];
    var pts = 0;
    final merged = <int>[];
    for (var i = 0; i < vals.length; i++) {
      final a = vals[i].abs();
      if (i + 1 < vals.length && vals[i + 1].abs() == a) {
        out.add(a * 2);
        pts += a * 2;
        merged.add(a * 2);
        i++;
      } else {
        out.add(vals[i]);
      }
    }
    while (out.length < line.length) {
      out.add(0);
    }
    return (out, pts, merged);
  }

  static List<int> _lineIdx(String dir, int k) => switch (dir) {
        'left' => [for (var x = 0; x < n; x++) k * n + x],
        'right' => [for (var x = n - 1; x >= 0; x--) k * n + x],
        'up' => [for (var y = 0; y < n; y++) y * n + k],
        _ => [for (var y = n - 1; y >= 0; y--) y * n + k],
      };

  /// Applies a move to board [b]. Returns (new board, points, merged) or null
  /// if nothing moved.
  static (List<int>, int, List<int>)? move(List<int> b, String dir) {
    final nb = List<int>.of(b);
    var pts = 0;
    final merged = <int>[];
    for (var k = 0; k < n; k++) {
      final idx = _lineIdx(dir, k);
      final (line, p, m) = slideLine([for (final i in idx) b[i]]);
      for (var j = 0; j < n; j++) {
        nb[idx[j]] = line[j];
      }
      pts += p;
      merged.addAll(m);
    }
    for (var i = 0; i < n * n; i++) {
      if (nb[i] != b[i]) return (nb, pts, merged);
    }
    return null;
  }

  static bool canMove(List<int> b) => dirs.any((d) => move(b, d) != null);

  @override
  List<int> get waitingFor => over ? const [] : rotated([for (var s = 0; s < players; s++) if (!ps[s].stuck) s], moves);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    if (type != 'move') throw GameError('未知操作');
    final p = ps[seat];
    if (p.stuck) throw GameError('你已无路可走');
    final d = asStr(a['dir']);
    if (!dirs.contains(d)) throw GameError('方向无效');
    final r = move(p.b, d);
    if (r == null) throw GameError('这个方向无法移动');
    final (nb, pts, merged) = r;
    p.b = nb;
    p.score += pts;
    p.moves++;
    moves++;
    p.lastDir = d;
    for (final v in merged) {
      if (v > p.best) p.best = v;
    }
    _spawn(p);
    if (attack) {
      final big = merged.where((v) => v >= 128).length;
      if (big > 0) {
        for (var o = 0; o < players; o++) {
          if (o == seat || ps[o].stuck) continue;
          ps[o].incoming += 2 * big;
        }
        p.sent += 2 * big * (players - 1);
        host.log('${name(seat)} 合成了 ${merged.where((v) => v >= 128).join('、')}，给对手扔出石块！');
      }
    }
    _dropStones(p);
    _updateStuck();
  }

  /// Drops pending stones (value -2) into random empty cells of [p].
  void _dropStones(G2048Player p) {
    while (p.incoming > 0) {
      final empty = [for (var i = 0; i < n * n; i++) if (p.b[i] == 0) i];
      if (empty.isEmpty) break;
      p.b[empty[rng.nextInt(empty.length)]] = -2;
      p.incoming--;
    }
    p.incoming = 0;
  }

  void _updateStuck() {
    for (var s = 0; s < players; s++) {
      final p = ps[s];
      if (!p.stuck && !canMove(p.b)) {
        p.stuck = true;
        p.stuckSec = sec;
        host.log('${name(s)} 无路可走了！最终 ${p.score} 分');
      }
    }
    if (ps.every((p) => p.stuck)) _finish('所有人都无路可走');
  }

  void _finish(String why) {
    if (over) return;
    over = true;
    ranking = buildRanking(players, (a, b) {
      final ra = ps[a].resignNo, rb = ps[b].resignNo;
      if (ra != rb) return ra == 0 ? -1 : (rb == 0 ? 1 : rb - ra);
      return ps[b].score != ps[a].score ? ps[b].score - ps[a].score : ps[b].best - ps[a].best;
    },
        (s) => {'score': ps[s].score, 'best': ps[s].best, 'stuck': ps[s].stuck});
    host.log('游戏结束（$why）！冠军：${winnersText(ranking!, name)}');
  }

  // ---------------------------------------------------------------- bot

  static double heuristic(List<int> b) {
    var empty = 0, mono = 0.0, smooth = 0.0, maxV = 0;
    for (var i = 0; i < n * n; i++) {
      final v = b[i].abs();
      if (v == 0) {
        empty++;
        continue;
      }
      if (v > maxV) maxV = v;
    }
    double lg(int v) => v == 0 ? 0 : (v.abs().bitLength - 1).toDouble();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n - 1; x++) {
        final a = lg(b[y * n + x]), c = lg(b[y * n + x + 1]);
        mono += a >= c ? 0 : c - a;
        if (a > 0 && c > 0) smooth -= (a - c).abs();
        final d = lg(b[x * n + y]), e = lg(b[(x + 1) * n + y]);
        mono += d >= e ? 0 : e - d;
        if (d > 0 && e > 0) smooth -= (d - e).abs();
      }
    }
    final corner = b[0].abs() == maxV ? lg(maxV) * 2 : 0;
    return empty * 2.7 + smooth * 0.1 - mono * 1.0 + corner;
  }

  /// Expectimax: move (max) → random 2/4 spawn (chance) → move (max).
  double _chance(List<int> b, int depth) {
    final empty = [for (var i = 0; i < n * n; i++) if (b[i] == 0) i];
    if (empty.isEmpty) return _max(b, depth);
    final sample = empty.length > 6 ? empty.sublist(0, 6) : empty;
    var sum = 0.0;
    for (final c in sample) {
      for (final (v, pr) in const [(2, 0.9), (4, 0.1)]) {
        final nb = List<int>.of(b)..[c] = v;
        sum += pr * _max(nb, depth);
      }
    }
    return sum / sample.length;
  }

  double _max(List<int> b, int depth) {
    if (depth <= 0) return heuristic(b);
    var best = -1e9;
    for (final d in dirs) {
      final r = move(b, d);
      if (r == null) continue;
      final v = r.$2 * 0.05 + _chance(r.$1, depth - 1);
      if (v > best) best = v;
    }
    return best == -1e9 ? heuristic(b) - 100 : best;
  }

  /// Expectimax move choice; [depth] 1 = normal, 2 = 困难 (one move deeper).
  String? bestDir(List<int> b, {int depth = 1}) {
    String? best;
    var bestV = -1e18;
    for (final d in dirs) {
      final r = move(b, d);
      if (r == null) continue;
      final v = r.$2 * 0.05 + _chance(r.$1, depth);
      if (v > bestV) {
        bestV = v;
        best = d;
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players) return null;
    final p = ps[seat];
    if (p.stuck) return {'type': 'idle'};
    String? d;
    if (botLevel <= 0 && rng.nextInt(3) == 0) {
      // 简单: frequent careless swipes
      final legal = [for (final x in dirs) if (move(p.b, x) != null) x];
      if (legal.isNotEmpty) d = legal[rng.nextInt(legal.length)];
    }
    d ??= bestDir(p.b, depth: botLevel >= 2 ? 2 : 1);
    return d == null ? {'type': 'idle'} : {'type': 'move', 'dir': d};
  }

  // ---------------------------------------------------------------- view

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : 'play',
        'sec': sec,
        'max': maxSec,
        'moves': moves,
        'attack': attack,
        'ps': [
          for (final p in ps)
            {'b': p.b, 'sc': p.score, 'best': p.best, 'stuck': p.stuck, 'sp': p.lastSpawn, 'mv': p.moves, 'd': p.lastDir},
        ],
        'final': ranking,
      };
}

class G2048Player {
  List<int> b = List.filled(16, 0);
  int score = 0, best = 0, moves = 0, sent = 0, incoming = 0, seqIdx = 0;
  int lastSpawn = -1;
  String? lastDir;
  bool stuck = false, resigned = false;
  int resignNo = 0; // order of resigning (later = better placed)
  int stuckSec = 0;
}
