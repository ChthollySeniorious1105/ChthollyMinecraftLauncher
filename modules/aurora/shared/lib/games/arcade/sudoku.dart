import 'dart:math';

import '../../src/engine.dart';
import 'arcade_util.dart';

/// Sudoku helpers: bitmask backtracking solver + unique-solution generator.
class Sudoku {
  static List<int> _peersOf(int i) {
    final r = i ~/ 9, c = i % 9, br = r ~/ 3 * 3, bc = c ~/ 3 * 3;
    final s = <int>{};
    for (var k = 0; k < 9; k++) {
      s.add(r * 9 + k);
      s.add(k * 9 + c);
      s.add((br + k ~/ 3) * 9 + bc + k % 3);
    }
    s.remove(i);
    return s.toList();
  }

  static final List<List<int>> peers = [for (var i = 0; i < 81; i++) _peersOf(i)];

  /// Bitmask (bits 1..9) of digits allowed at [i].
  static int candidates(List<int> g, int i) {
    var used = 0;
    for (final p in peers[i]) {
      used |= 1 << g[p];
    }
    return ~used & 0x3FE;
  }

  static int _bits(int m) {
    var c = 0;
    while (m != 0) {
      m &= m - 1;
      c++;
    }
    return c;
  }

  /// Counts solutions of [g] (0 = empty) up to [limit]. When [out] is given
  /// the first solution found is written into it. [order] randomizes digits.
  static int solve(List<int> g, {int limit = 2, List<int>? out, Random? order}) {
    final grid = List<int>.of(g);
    var count = 0;
    void rec() {
      if (count >= limit) return;
      var best = -1, bestMask = 0, bestN = 10;
      for (var i = 0; i < 81; i++) {
        if (grid[i] != 0) continue;
        final m = candidates(grid, i);
        final n = _bits(m);
        if (n < bestN) {
          best = i;
          bestMask = m;
          bestN = n;
          if (n <= 1) break;
        }
      }
      if (best < 0) {
        if (count == 0 && out != null) out.setAll(0, grid);
        count++;
        return;
      }
      if (bestN == 0) return;
      final ds = [for (var d = 1; d <= 9; d++) if (bestMask & (1 << d) != 0) d];
      if (order != null) ds.shuffle(order);
      for (final d in ds) {
        grid[best] = d;
        rec();
        if (count >= limit) break;
      }
      grid[best] = 0;
    }

    // reject grids that already contain a conflict
    for (var i = 0; i < 81; i++) {
      final v = g[i];
      if (v == 0) continue;
      for (final p in peers[i]) {
        if (g[p] == v) return 0;
      }
    }
    rec();
    return count;
  }

  /// Generates (puzzle, solution) with a unique solution and roughly
  /// [clues] givens (never fewer than uniqueness allows).
  static (List<int>, List<int>) generate(Random rng, int clues) {
    final sol = List<int>.filled(81, 0);
    solve(List<int>.filled(81, 0), limit: 1, out: sol, order: rng);
    final puzzle = List<int>.of(sol);
    var filled = 81;
    for (final i in shuffled(List.generate(81, (i) => i), rng)) {
      if (filled <= clues) break;
      final keep = puzzle[i];
      puzzle[i] = 0;
      if (solve(puzzle, limit: 2) != 1) {
        puzzle[i] = keep;
      } else {
        filled--;
      }
    }
    return (puzzle, sol);
  }

  /// A cell that logic (naked or hidden single) fills directly: (index, digit).
  static (int, int)? logicalStep(List<int> g) {
    for (var i = 0; i < 81; i++) {
      if (g[i] != 0) continue;
      final m = candidates(g, i);
      if (_bits(m) == 1) return (i, m.bitLength - 1);
    }
    // hidden singles per unit
    for (var u = 0; u < 27; u++) {
      final cells = u < 9
          ? [for (var k = 0; k < 9; k++) u * 9 + k]
          : u < 18
              ? [for (var k = 0; k < 9; k++) k * 9 + (u - 9)]
              : [for (var k = 0; k < 9; k++) ((u - 18) ~/ 3 * 3 + k ~/ 3) * 9 + (u - 18) % 3 * 3 + k % 3];
      for (var d = 1; d <= 9; d++) {
        int? only;
        var n = 0;
        for (final c in cells) {
          if (g[c] == d) {
            n = 99;
            break;
          }
          if (g[c] == 0 && candidates(g, c) & (1 << d) != 0) {
            n++;
            only = c;
          }
        }
        if (n == 1) return (only!, d);
      }
    }
    return null;
  }
}

/// 数独竞速 (1-6 人). Everyone gets the same unique-solution puzzle and fills
/// their own copy. A wrong digit is rejected and counts as a mistake (limit by
/// option). First to solve wins; at the time cap, rank by cells filled.
class SudokuRace extends GameEngine {
  SudokuRace(super.setup);

  static const diffs = {'easy': 40, 'medium': 32, 'hard': 25};
  static const diffNames = {'easy': '简单', 'medium': '中等', 'hard': '困难'};

  late String diff;
  late int maxMistakes; // 0 = unlimited
  late List<int> puzzle, solution;
  late List<SudokuPlayer> ps;
  late int maxSec;
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

  /// 认输 = eliminated now (ranked after everyone who didn't resign). The game
  /// ends when at most one non-resigned player remains (solo: right away).
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (p.resigned) throw GameError('你已认输');
    p
      ..resigned = true
      ..out = true;
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (!ps[s].resigned) s];
    if (left.length <= 1) {
      _finish(left.isEmpty ? '所有人都已认输' : '其他人都已认输');
    } else if (!ps.any((q) => !q.out && !q.done)) {
      _finish('所有人都已出局');
    }
  }

  @override
  int get botDelayMs {
    final base = switch (diff) { 'easy' => 3000, 'medium' => 4500, _ => 6000 };
    return switch (botLevel) { 0 => base * 3 ~/ 2, 2 => base * 3 ~/ 5, _ => base };
  }

  @override
  void start() {
    diff = setup.opt<String>('diff', 'medium');
    if (!diffs.containsKey(diff)) diff = 'medium';
    maxMistakes = setup.opt<int>('mistakes', 3);
    maxSec = 1800;
    final (pz, so) = Sudoku.generate(rng, diffs[diff]!);
    puzzle = pz;
    solution = so;
    ps = [for (var s = 0; s < players; s++) SudokuPlayer(List.of(puzzle))];
    host.log('数独竞速开始（${diffNames[diff]}，${puzzle.where((v) => v != 0).length} 个提示数）！'
        '${maxMistakes > 0 ? '填错 $maxMistakes 次出局。' : ''}最先完成者获胜。');
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

  int get emptyCount => puzzle.where((v) => v == 0).length;
  int filled(int s) => ps[s].g.where((v) => v != 0).length - (81 - emptyCount);
  bool active(int s) => !ps[s].out && !ps[s].done;

  @override
  List<int> get waitingFor => over ? const [] : rotated([for (var s = 0; s < players; s++) if (active(s)) s], moves);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    if (type != 'fill') throw GameError('未知操作');
    final p = ps[seat];
    if (p.out) throw GameError('你已出局');
    if (p.done) throw GameError('你已完成');
    final i = asInt(a['i']), d = asInt(a['d']);
    if (i < 0 || i >= 81) throw GameError('格子无效');
    if (d < 1 || d > 9) throw GameError('只能填 1-9');
    if (puzzle[i] != 0) throw GameError('这是题目给出的数字');
    if (p.g[i] != 0) throw GameError('该格已填好');
    moves++;
    if (solution[i] != d) {
      p.mistakes++;
      p.lastWrong = [moves, i, d];
      if (maxMistakes > 0 && p.mistakes >= maxMistakes) {
        p.out = true;
        host.log('${name(seat)} 填错 ${p.mistakes} 次，出局！');
        if (!ps.any((q) => !q.out && !q.done)) _finish('所有人都已出局');
      }
      return;
    }
    p.g[i] = d;
    p.lastOk = i;
    if (!p.g.contains(0)) {
      p.done = true;
      p.doneSec = sec;
      host.log('${name(seat)} 完成了数独！用时 ${_fmt(sec)}');
      _finish('${name(seat)} 率先完成');
    }
  }

  static String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  void _finish(String why) {
    if (over) return;
    over = true;
    ranking = buildRanking(players, (a, b) {
      final pa = ps[a], pb = ps[b];
      if (pa.resignNo != pb.resignNo) return pa.resignNo == 0 ? -1 : (pb.resignNo == 0 ? 1 : pb.resignNo - pa.resignNo);
      if (pa.done != pb.done) return pa.done ? -1 : 1;
      if (pa.done) return pa.doneSec - pb.doneSec;
      if (pa.out != pb.out) return pa.out ? 1 : -1;
      final fa = filled(a), fb = filled(b);
      if (fa != fb) return fb - fa;
      return pa.mistakes - pb.mistakes;
    }, (s) => {'filled': filled(s), 'done': ps[s].done, 'out': ps[s].out, 'mistakes': ps[s].mistakes, 'time': ps[s].done ? ps[s].doneSec : null});
    host.log('游戏结束（$why）！冠军：${winnersText(ranking!, name)}');
  }

  // ---------------------------------------------------------------- bot

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players || !active(seat)) return null;
    final p = ps[seat];
    // the bot works only from its own grid (puzzle + its correct entries)
    var step = Sudoku.logicalStep(p.g);
    if (step == null) {
      final sol = List<int>.filled(81, 0);
      Sudoku.solve(p.g, limit: 1, out: sol);
      final empty = [for (var i = 0; i < 81; i++) if (p.g[i] == 0) i];
      if (empty.isEmpty) return {'type': 'idle'};
      final i = empty[rng.nextInt(empty.length)];
      step = (i, sol[i] == 0 ? 1 : sol[i]);
    }
    var (i, d) = step;
    // occasional human-like slip (never the final fatal one); 简单 slips more,
    // 困难 never
    final slip = switch (botLevel) { 0 => 12, 2 => 0, _ => 40 };
    if (slip > 0 && rng.nextInt(slip) == 0 && (maxMistakes == 0 || p.mistakes < maxMistakes - 1)) {
      final m = Sudoku.candidates(p.g, i) & ~(1 << d);
      final alts = [for (var k = 1; k <= 9; k++) if (m & (1 << k) != 0) k];
      if (alts.isNotEmpty) d = alts[rng.nextInt(alts.length)];
    }
    return {'type': 'fill', 'i': i, 'd': d};
  }

  // ---------------------------------------------------------------- view

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players ? ps[seat] : null;
    return {
      'phase': over ? 'over' : 'play',
      'sec': sec,
      'max': maxSec,
      'diff': diff,
      'maxMis': maxMistakes,
      'puzzle': puzzle.join(),
      'g': me?.g.join(),
      'wrong': me?.lastWrong,
      'ok': me?.lastOk,
      'sol': over ? solution.join() : null,
      'empty': emptyCount,
      'ps': [
        for (var s = 0; s < players; s++)
          {'f': filled(s), 'mis': ps[s].mistakes, 'out': ps[s].out, 'done': ps[s].done, 'time': ps[s].done ? ps[s].doneSec : null},
      ],
      'final': ranking,
    };
  }
}

class SudokuPlayer {
  final List<int> g;
  int mistakes = 0;
  bool out = false, done = false, resigned = false;
  int resignNo = 0; // order of resigning (later = better placed)
  int doneSec = 0;
  int? lastOk;
  List<int>? lastWrong;
  SudokuPlayer(this.g);
}
