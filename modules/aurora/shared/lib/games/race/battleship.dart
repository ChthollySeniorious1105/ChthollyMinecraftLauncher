import '../../src/engine.dart';

/// 炸飞机 geometry. A plane is (r, c, d): head cell (r, c), pointing
/// direction d (0 up, 1 right, 2 down, 3 left). Shape when pointing up:
///
///   . . H . .      head   (0, 0)
///   W W W W W      wings  (1, -2..2)
///   . . B . .      body   (2, 0)
///   . T T T .      tail   (3, -1..1)
class PlaneGeo {
  static const size = 10;
  static const List<(int, int)> _up = [
    (0, 0),
    (1, -2), (1, -1), (1, 0), (1, 1), (1, 2),
    (2, 0),
    (3, -1), (3, 0), (3, 1),
  ];

  /// Cells of a plane; first element is the head. May be out of bounds.
  static List<(int, int)> cells(int r, int c, int d) => [
        for (final (dr, dc) in _up)
          switch (d % 4) {
            0 => (r + dr, c + dc),
            1 => (r + dc, c - dr),
            2 => (r - dr, c - dc),
            _ => (r - dc, c + dr),
          },
      ];

  static bool inBounds(int r, int c, int d) =>
      cells(r, c, d).every((p) => p.$1 >= 0 && p.$1 < size && p.$2 >= 0 && p.$2 < size);

  /// Returns an error for an invalid layout, else null.
  static String? validate(List<(int, int, int)> planes, int count) {
    if (planes.length != count) return '需要布置 $count 架飞机';
    final used = <int>{};
    for (final (r, c, d) in planes) {
      if (d < 0 || d > 3 || !inBounds(r, c, d)) return '飞机超出边界';
      for (final (pr, pc) in cells(r, c, d)) {
        if (!used.add(pr * size + pc)) return '飞机不能重叠';
      }
    }
    return null;
  }

  /// All in-bounds placements.
  static final List<(int, int, int)> all = [
    for (var d = 0; d < 4; d++)
      for (var r = 0; r < size; r++)
        for (var c = 0; c < size; c++)
          if (inBounds(r, c, d)) (r, c, d),
  ];
}

class Battleship extends GameEngine {
  Battleship(super.setup);

  late final int count = setup.opt<int>('planes', 3);
  final List<List<(int, int, int)>> layout = [[], []];
  final List<bool> ready = [false, false];

  /// shots[s][cell] = result of seat s shooting cell: -1 not shot, 0 空, 1 伤, 2 毁
  final List<List<int>> shots = [List.filled(100, -1), List.filled(100, -1)];
  final List<int> destroyed = [0, 0];
  String phase = 'place';
  int turn = 0;
  int winner = -1;
  List<int>? lastShot; // [seat, cell, result]
  int resignedSeat = -1;

  @override
  List<int>? get placings => isOver ? [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2] : null;

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat > 1) return;
    resignedSeat = seat;
    winner = 1 - seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
  }

  @override
  void start() {
    host.log('请布置你的 $count 架飞机');
  }

  @override
  bool get isOver => winner >= 0;

  @override
  List<int> get waitingFor {
    if (isOver) return const [];
    if (phase == 'place') return [for (var s = 0; s < 2; s++) if (!ready[s]) s];
    return [turn];
  }

  List<(int, int, int)> randomLayout() {
    for (var attempt = 0; attempt < 1000; attempt++) {
      final out = <(int, int, int)>[];
      final used = <int>{};
      var tries = 0;
      while (out.length < count && tries++ < 200) {
        final p = PlaneGeo.all[rng.nextInt(PlaneGeo.all.length)];
        final cs = PlaneGeo.cells(p.$1, p.$2, p.$3);
        if (cs.any((q) => used.contains(q.$1 * 10 + q.$2))) continue;
        for (final q in cs) {
          used.add(q.$1 * 10 + q.$2);
        }
        out.add(p);
      }
      if (out.length == count) return out;
    }
    throw StateError('layout');
  }

  int _resultAt(int target, int cell) {
    final r = cell ~/ 10, c = cell % 10;
    for (final (pr, pc, pd) in layout[target]) {
      final cs = PlaneGeo.cells(pr, pc, pd);
      if (cs.first == (r, c)) return 2;
      if (cs.contains((r, c))) return 1;
    }
    return 0;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('你不是玩家');
    final t = asStr(a['t']);
    if (phase == 'place') {
      if (t != 'place') throw GameError('请先布置飞机');
      if (ready[seat]) throw GameError('已经布置完成');
      final raw = a['planes'];
      if (raw is! List) throw GameError('布局无效');
      final planes = <(int, int, int)>[];
      for (final p in raw) {
        final l = asIntList(p);
        if (l.length != 3) throw GameError('布局无效');
        planes.add((l[0], l[1], l[2]));
      }
      final err = PlaneGeo.validate(planes, count);
      if (err != null) throw GameError(err);
      layout[seat] = planes;
      ready[seat] = true;
      host.log('${name(seat)} 布置完毕');
      if (ready.every((x) => x)) {
        phase = 'play';
        turn = rng.nextInt(2);
        host.log('开战！${name(turn)} 先轰炸');
      }
      return;
    }
    if (t != 'shoot') throw GameError('未知操作');
    if (seat != turn) throw GameError('还没轮到你');
    final cell = asInt(a['cell']);
    if (cell < 0 || cell >= 100) throw GameError('无效位置');
    if (shots[seat][cell] >= 0) throw GameError('这里已经炸过了');
    final res = _resultAt(1 - seat, cell);
    shots[seat][cell] = res;
    lastShot = [seat, cell, res];
    final label = '${String.fromCharCode(65 + cell % 10)}${cell ~/ 10 + 1}';
    host.log('${name(seat)} 轰炸 $label：${const ['空', '伤', '毁'][res]}');
    if (res == 2) {
      destroyed[seat]++;
      if (destroyed[seat] >= count) {
        winner = seat;
        phase = 'over';
        host.log('${name(seat)} 炸毁了对方全部飞机，获胜！');
        return;
      }
    }
    turn = 1 - seat;
  }

  List<List<int>> _planesJson(int s) => [for (final p in layout[s]) [p.$1, p.$2, p.$3]];

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat == 0 || seat == 1;
    return {
      'phase': phase,
      'count': count,
      'ready': ready,
      'turn': turn,
      'winner': winner,
      'shots': shots, // public: every shot result is announced
      'destroyed': destroyed,
      'last': lastShot,
      'resigned': resignedSeat,
      'mine': me ? _planesJson(seat) : null,
      // opponent planes (and spectators' view) only revealed when the game ends
      'planes': isOver ? [_planesJson(0), _planesJson(1)] : null,
    };
  }

  @override
  int get botDelayMs => 700;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'place') {
      if (ready[seat]) return null;
      return {
        't': 'place',
        'planes': [for (final p in randomLayout()) [p.$1, p.$2, p.$3]],
      };
    }
    if (seat != turn) return null;
    final known = shots[seat];
    // 简单: often shoots a random unexplored cell
    if (botLevel <= 0 && rng.nextDouble() < 0.5) {
      final free = [for (var i = 0; i < 100; i++) if (known[i] == -1) i];
      return {'t': 'shoot', 'cell': free[rng.nextInt(free.length)]};
    }
    return {'t': 'shoot', 'cell': bestShot(known, count - destroyed[seat], rng.nextDouble, exact: botLevel >= 2)};
  }

  /// Probability-density targeting. [known] = results per cell (-1 unknown).
  /// [exact] (困难): heads are only aimed at when the head probability is high,
  /// otherwise cells are scored by how many consistent placements cover them.
  static int bestShot(List<int> known, int alive, double Function() rand, {bool exact = false}) {
    final score = List.filled(100, 0.0);
    final heads = <int>{for (var i = 0; i < 100; i++) if (known[i] == 2) i};
    for (final (r, c, d) in PlaneGeo.all) {
      final cs = PlaneGeo.cells(r, c, d);
      final head = cs.first.$1 * 10 + cs.first.$2;
      if (known[head] != -1) continue; // an alive plane's head is still unshot
      var ok = true, hits = 0;
      for (var k = 1; k < cs.length; k++) {
        final i = cs[k].$1 * 10 + cs[k].$2;
        if (known[i] == 0 || heads.contains(i)) {
          ok = false;
          break;
        }
        if (known[i] == 1) hits++;
      }
      if (!ok) continue;
      final w = 1.0 + hits * hits * 12.0;
      score[head] += w;
      final side = exact && hits == 0 ? 0.25 : 0.15;
      for (var k = 1; k < cs.length; k++) {
        final i = cs[k].$1 * 10 + cs[k].$2;
        if (known[i] == -1) score[i] += w * side;
      }
    }
    var best = -1;
    var bs = -1.0;
    for (var i = 0; i < 100; i++) {
      if (known[i] != -1) continue;
      final s = score[i] + rand() * 0.01;
      if (s > bs) {
        bs = s;
        best = i;
      }
    }
    return best;
  }
}
