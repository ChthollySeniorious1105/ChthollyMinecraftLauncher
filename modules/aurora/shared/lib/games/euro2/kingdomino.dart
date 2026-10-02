import 'dart:math';

import '../../src/engine.dart';

/// 王国骨牌 Kingdomino.
///
/// Terrains: 0 麦田 1 森林 2 湖泊 3 草地 4 沼泽 5 矿山; 6 = 城堡.
/// Each domino: (terrainA, crownsA, terrainB, crownsB), number = index+1.
const List<(int, int, int, int)> kdDominoes = [
  (0, 0, 0, 0), (0, 0, 0, 0), (1, 0, 1, 0), (1, 0, 1, 0), (1, 0, 1, 0), (1, 0, 1, 0), // 1-6
  (2, 0, 2, 0), (2, 0, 2, 0), (2, 0, 2, 0), (3, 0, 3, 0), (3, 0, 3, 0), (4, 0, 4, 0), // 7-12
  (0, 0, 1, 0), (0, 0, 2, 0), (0, 0, 3, 0), (0, 0, 4, 0), (1, 0, 2, 0), (1, 0, 3, 0), // 13-18
  (0, 1, 1, 0), (0, 1, 2, 0), (0, 1, 3, 0), (0, 1, 4, 0), (0, 1, 5, 0), (1, 1, 0, 0), // 19-24
  (1, 1, 0, 0), (1, 1, 0, 0), (1, 1, 0, 0), (1, 1, 2, 0), (1, 1, 3, 0), (2, 1, 0, 0), // 25-30
  (2, 1, 0, 0), (2, 1, 1, 0), (2, 1, 1, 0), (2, 1, 1, 0), (2, 1, 1, 0), (0, 0, 3, 1), // 31-36
  (2, 0, 3, 1), (0, 0, 4, 1), (3, 0, 4, 1), (5, 1, 0, 0), (0, 0, 3, 2), (2, 0, 3, 2), // 37-42
  (0, 0, 4, 2), (3, 0, 4, 2), (5, 2, 0, 0), (4, 0, 5, 2), (4, 0, 5, 2), (0, 0, 5, 3), // 43-48
];

const kdTerrainNames = ['麦田', '森林', '湖泊', '草地', '沼泽', '矿山', '城堡'];
const _dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];

class KdKingdom {
  static const g = 13; // grid side, castle at (6,6)
  static const c0 = 6;
  final int size; // 5 or 7
  final List<int> t = List.filled(g * g, -1);
  final List<int> cr = List.filled(g * g, 0);
  int minX = c0, maxX = c0, minY = c0, maxY = c0;
  int discarded = 0;

  KdKingdom(this.size) {
    t[c0 * g + c0] = 6;
  }

  KdKingdom clone() {
    final k = KdKingdom(size);
    k.t.setAll(0, t);
    k.cr.setAll(0, cr);
    k.minX = minX;
    k.maxX = maxX;
    k.minY = minY;
    k.maxY = maxY;
    k.discarded = discarded;
    return k;
  }

  int at(int x, int y) => x < 0 || y < 0 || x >= g || y >= g ? -2 : t[y * g + x];

  bool _fitsBox(int x, int y) =>
      max(maxX, x) - min(minX, x) < size && max(maxY, y) - min(minY, y) < size && x >= 0 && y >= 0 && x < g && y < g;

  bool _matches(int x, int y, int terrain) {
    for (final (dx, dy) in _dirs) {
      final v = at(x + dx, y + dy);
      if (v == 6 || v == terrain) return true;
    }
    return false;
  }

  /// First half at (x,y), second half at (x,y)+dir.
  bool canPlace(int dom, int x, int y, int dir) {
    if (dir < 0 || dir > 3) return false;
    final (ta, _, tb, _) = kdDominoes[dom];
    final x2 = x + _dirs[dir].$1, y2 = y + _dirs[dir].$2;
    if (at(x, y) != -1 || at(x2, y2) != -1) return false;
    // bounding box with both halves
    final nx0 = min(min(minX, x), x2), nx1 = max(max(maxX, x), x2);
    final ny0 = min(min(minY, y), y2), ny1 = max(max(maxY, y), y2);
    if (nx1 - nx0 >= size || ny1 - ny0 >= size) return false;
    if (!_fitsBox(x, y) || !_fitsBox(x2, y2)) return false;
    return _matches(x, y, ta) || _matches(x2, y2, tb);
  }

  void place(int dom, int x, int y, int dir) {
    final (ta, ca, tb, cb) = kdDominoes[dom];
    final x2 = x + _dirs[dir].$1, y2 = y + _dirs[dir].$2;
    t[y * g + x] = ta;
    cr[y * g + x] = ca;
    t[y2 * g + x2] = tb;
    cr[y2 * g + x2] = cb;
    minX = min(minX, min(x, x2));
    maxX = max(maxX, max(x, x2));
    minY = min(minY, min(y, y2));
    maxY = max(maxY, max(y, y2));
  }

  List<(int, int, int)> placements(int dom) {
    final out = <(int, int, int)>[];
    for (var y = maxY - size; y <= minY + size; y++) {
      for (var x = maxX - size; x <= minX + size; x++) {
        if (at(x, y) != -1) continue;
        for (var d = 0; d < 4; d++) {
          if (canPlace(dom, x, y, d)) out.add((x, y, d));
        }
      }
    }
    return out;
  }

  /// Properties: list of (terrain, squares, crowns).
  List<(int, int, int)> properties() {
    final seen = List.filled(g * g, false);
    final out = <(int, int, int)>[];
    for (var i = 0; i < g * g; i++) {
      if (seen[i] || t[i] < 0 || t[i] == 6) continue;
      final ter = t[i];
      var n = 0, c = 0;
      final st = [i];
      seen[i] = true;
      while (st.isNotEmpty) {
        final p = st.removeLast();
        n++;
        c += cr[p];
        final px = p % g, py = p ~/ g;
        for (final (dx, dy) in _dirs) {
          final nx = px + dx, ny = py + dy;
          if (nx < 0 || ny < 0 || nx >= g || ny >= g) continue;
          final q = ny * g + nx;
          if (!seen[q] && t[q] == ter) {
            seen[q] = true;
            st.add(q);
          }
        }
      }
      out.add((ter, n, c));
    }
    return out;
  }

  int baseScore() => properties().fold(0, (s, p) => s + p.$2 * p.$3);

  bool get centered =>
      maxX - minX == size - 1 && maxY - minY == size - 1 && c0 - minX == size ~/ 2 && c0 - minY == size ~/ 2;

  bool get complete {
    if (discarded > 0) return false;
    if (maxX - minX != size - 1 || maxY - minY != size - 1) return false;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (t[y * g + x] == -1) return false;
      }
    }
    return true;
  }

  int largest() => properties().fold(0, (m, p) => max(m, p.$2));
  int crowns() => cr.fold(0, (a, b) => a + b);
}

class Kingdomino extends GameEngine {
  Kingdomino(super.setup);

  bool mighty = false, middleBonus = false, harmonyBonus = false;
  late List<KdKingdom> kingdoms;
  List<int> deck = [];
  // current row: dominoes being placed; next row: being claimed
  List<int> curDom = [], curKing = [];
  List<int> nextDom = [], nextKing = [];
  int ci = 0; // index into current row
  String phase = 'pick'; // pick / place / over
  int actor = 0;
  int kingsEach = 1;
  List<int> initOrder = []; // first round claim order (seats)
  int initIdx = 0;
  int round = 0;
  Map<String, dynamic>? last;
  final List<String> recent = [];
  List<Map<String, dynamic>>? result;
  int resigned = -1;

  int get rowSize => players == 3 ? 3 : 4;

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 8) recent.removeAt(0);
  }

  @override
  void start() {
    mighty = players == 2 && setup.opt('mighty', false) == true;
    middleBonus = setup.opt('middle', false) == true;
    harmonyBonus = setup.opt('harmony', false) == true;
    final size = mighty ? 7 : 5;
    kingdoms = [for (var p = 0; p < players; p++) KdKingdom(size)];
    kingsEach = players == 2 ? 2 : 1;
    final all = shuffled(List.generate(48, (i) => i), rng);
    final useN = players == 2 && !mighty ? 24 : (players == 3 ? 36 : 48);
    deck = all.sublist(0, useN);
    final kings = [for (var p = 0; p < players; p++) for (var k = 0; k < kingsEach; k++) p];
    initOrder = shuffled(kings, rng);
    initIdx = 0;
    _reveal();
    phase = 'pick';
    actor = initOrder[0];
    _log('王国骨牌${mighty ? '（巨人对决 7×7）' : ''}：认领顺序 ${initOrder.map(name).join(' → ')}');
  }

  void _reveal() {
    nextDom = deck.length >= rowSize ? (deck.sublist(0, rowSize)..sort()) : <int>[];
    if (nextDom.isNotEmpty) deck.removeRange(0, rowSize);
    nextKing = List.filled(nextDom.length, -1);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != actor) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (phase == 'pick') {
      if (type != 'pick') throw GameError('请选择下一块骨牌');
      final i = asInt(a['i']);
      if (i < 0 || i >= nextDom.length) throw GameError('无效的骨牌');
      if (nextKing[i] != -1) throw GameError('这块骨牌已经被选了');
      nextKing[i] = seat;
      last = {'seat': seat, 'type': 'pick', 'dom': nextDom[i]};
      _log('${name(seat)} 选择了 ${nextDom[i] + 1} 号骨牌');
      _afterPick();
      return;
    }
    // place phase
    final dom = curDom[ci];
    final k = kingdoms[seat];
    if (type == 'discard') {
      if (k.placements(dom).isNotEmpty) throw GameError('还有合法位置，不能弃掉');
      k.discarded++;
      last = {'seat': seat, 'type': 'discard', 'dom': dom};
      _log('${name(seat)} 无处放置 ${dom + 1} 号骨牌，只能弃掉');
    } else if (type == 'place') {
      final x = asInt(a['x']), y = asInt(a['y']), d = asInt(a['dir']);
      if (!k.canPlace(dom, x, y, d)) throw GameError('这里不能放：需与城堡或相同地形相邻，且王国不超过 ${k.size}×${k.size}');
      k.place(dom, x, y, d);
      last = {'seat': seat, 'type': 'place', 'dom': dom, 'x': x, 'y': y, 'dir': d};
      _log('${name(seat)} 放置 ${dom + 1} 号骨牌');
    } else {
      throw GameError('请先放置你的骨牌');
    }
    if (nextDom.isNotEmpty) {
      phase = 'pick';
    } else {
      _nextInRow();
    }
  }

  void _afterPick() {
    if (round == 0) {
      initIdx++;
      if (initIdx < initOrder.length) {
        actor = initOrder[initIdx];
        return;
      }
      _beginRow();
      return;
    }
    _nextInRow();
  }

  void _beginRow() {
    round++;
    curDom = nextDom;
    curKing = nextKing;
    _reveal();
    ci = 0;
    phase = 'place';
    actor = curKing[0];
  }

  void _nextInRow() {
    ci++;
    if (ci < curDom.length) {
      phase = 'place';
      actor = curKing[ci];
      return;
    }
    if (nextDom.isEmpty) {
      _end();
      return;
    }
    _beginRow();
  }

  int scoreOf(int p) {
    final k = kingdoms[p];
    var s = k.baseScore();
    if (middleBonus && k.centered) s += 10;
    if (harmonyBonus && k.complete) s += 5;
    return s;
  }

  void _end() {
    phase = 'over';
    result = [
      for (var p = 0; p < players; p++)
        {
          'seat': p,
          'base': kingdoms[p].baseScore(),
          'middle': middleBonus && kingdoms[p].centered ? 10 : 0,
          'harmony': harmonyBonus && kingdoms[p].complete ? 5 : 0,
          'score': scoreOf(p),
          'largest': kingdoms[p].largest(),
          'crowns': kingdoms[p].crowns(),
        }
    ];
    final pl = placings!;
    _log('游戏结束！${[for (var p = 0; p < players; p++) if (pl[p] == 1) name(p)].join('、')} 获胜（${[for (var p = 0; p < players; p++) '${name(p)} ${scoreOf(p)}'].join(' / ')}）');
  }

  @override
  List<int> get waitingFor => phase == 'over' ? const [] : [actor];

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore([for (var p = 0; p < players; p++) scoreOf(p) * 10000 + kingdoms[p].largest() * 100 + kingdoms[p].crowns()]);
  }

  @override
  bool get canResign => phase != 'over' && players == 2;

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    resigned = seat;
    phase = 'over';
    _log('${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  List<List<int>> _gridOf(KdKingdom k, bool crowns) => [
        for (var y = 0; y < KdKingdom.g; y++) [for (var x = 0; x < KdKingdom.g; x++) crowns ? k.cr[y * KdKingdom.g + x] : k.t[y * KdKingdom.g + x]]
      ];

  @override
  Map<String, dynamic> view(int seat) {
    final placeList = phase == 'place' && seat == actor
        ? [for (final (x, y, d) in kingdoms[actor].placements(curDom[ci])) [x, y, d]]
        : const <List<int>>[];
    return {
      'phase': phase,
      'actor': actor,
      'round': round,
      'size': mighty ? 7 : 5,
      'grid': KdKingdom.g,
      'middle': middleBonus,
      'harmony': harmonyBonus,
      'deck': deck.length,
      'cur': [for (var i = 0; i < curDom.length; i++) {'dom': curDom[i], 'king': curKing[i], 'done': round > 0 && i < ci || (i == ci && phase == 'pick' && round > 0)}],
      'ci': round == 0 ? -1 : ci,
      'next': [for (var i = 0; i < nextDom.length; i++) {'dom': nextDom[i], 'king': nextKing[i]}],
      'dominoes': [for (final d in kdDominoes) [d.$1, d.$2, d.$3, d.$4]],
      'players': [
        for (var p = 0; p < players; p++)
          {
            't': _gridOf(kingdoms[p], false),
            'c': _gridOf(kingdoms[p], true),
            'box': [kingdoms[p].minX, kingdoms[p].minY, kingdoms[p].maxX, kingdoms[p].maxY],
            'score': scoreOf(p),
            'discarded': kingdoms[p].discarded,
          }
      ],
      'legal': placeList,
      'last': last,
      'recent': recent,
      'result': result,
      'resigned': resigned,
      'placings': placings,
    };
  }

  // ------------------------------------------------------------------ bot
  double _placeValue(KdKingdom k, int dom, (int, int, int) m) {
    final c = k.clone();
    final before = c.baseScore();
    c.place(dom, m.$1, m.$2, m.$3);
    var v = (c.baseScore() - before).toDouble();
    // adjacency bonus: same-terrain neighbours (future crowns multiply)
    final (ta, _, tb, _) = kdDominoes[dom];
    final x2 = m.$1 + _dirs[m.$3].$1, y2 = m.$2 + _dirs[m.$3].$2;
    var adj = 0;
    for (final (x, y, t) in [(m.$1, m.$2, ta), (x2, y2, tb)]) {
      for (final (dx, dy) in _dirs) {
        if (c.at(x + dx, y + dy) == t) adj++;
      }
    }
    v += adj * 0.3;
    if (botLevel >= 2) {
      // keep the castle centred / avoid dead holes
      if (middleBonus) {
        final cx = (c.minX + c.maxX) / 2 - KdKingdom.c0, cy = (c.minY + c.maxY) / 2 - KdKingdom.c0;
        v -= (cx.abs() + cy.abs()) * 0.6;
      }
      var holes = 0;
      for (var y = c.maxY - c.size + 1; y <= c.minY + c.size - 1; y++) {
        for (var x = c.maxX - c.size + 1; x <= c.minX + c.size - 1; x++) {
          if (c.at(x, y) != -1) continue;
          var n = 0;
          for (final (dx, dy) in _dirs) {
            final w = c.at(x + dx, y + dy);
            if (w >= 0) n++;
          }
          if (n >= 4) holes++;
        }
      }
      v -= holes * (harmonyBonus ? 2.0 : 0.8);
    }
    return v;
  }

  (int, int, int)? _bestPlacement(int seat, int dom) {
    final k = kingdoms[seat];
    final ms = k.placements(dom);
    if (ms.isEmpty) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.5) return ms[rng.nextInt(ms.length)];
    (int, int, int)? best;
    var bv = -1e9;
    for (final m in ms) {
      final v = _placeValue(k, dom, m) + rng.nextDouble() * 0.05;
      if (v > bv) {
        bv = v;
        best = m;
      }
    }
    return best;
  }

  double _domValue(int seat, int dom) {
    final k = kingdoms[seat];
    final ms = k.placements(dom);
    if (ms.isEmpty) return -3;
    var bv = -1e9;
    for (final m in ms) {
      bv = max(bv, _placeValue(k, dom, m));
    }
    final (_, ca, _, cb) = kdDominoes[dom];
    return bv + (ca + cb) * 0.8;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'over' || seat != actor) return null;
    if (phase == 'place') {
      final m = _bestPlacement(seat, curDom[ci]);
      if (m == null) return {'type': 'discard'};
      return {'type': 'place', 'x': m.$1, 'y': m.$2, 'dir': m.$3};
    }
    final free = [for (var i = 0; i < nextDom.length; i++) if (nextKing[i] == -1) i];
    if (free.isEmpty) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.5) return {'type': 'pick', 'i': free[rng.nextInt(free.length)]};
    var best = free.first;
    var bv = -1e9;
    for (final i in free) {
      var v = _domValue(seat, nextDom[i]);
      // earlier pick next round is worth a little
      if (botLevel >= 1) v -= i * 0.25;
      v += rng.nextDouble() * 0.1;
      if (v > bv) {
        bv = v;
        best = i;
      }
    }
    return {'type': 'pick', 'i': best};
  }
}

const kingdominoRules = '''
# 王国骨牌 Kingdomino
2~4 名领主扩建自己的王国：每块骨牌由两格地形组成（麦田、森林、湖泊、草地、沼泽、矿山），部分格子上有皇冠。

# 骨牌与准备
- 共 48 块骨牌，编号 1~48，编号越大越珍贵（皇冠越多）。
- 4 人使用全部 48 块，3 人随机使用 36 块，2 人随机使用 24 块且每人有 2 个国王；3、4 人每人 1 个国王。
- 每一排翻开 4 块（3 人为 3 块），按编号从小到大排列。
- 开局随机决定认领顺序，各国王依次在第一排选一块骨牌。

# 回合流程
- 每一轮先翻开新的一排。按当前排从上到下（编号小的先）的顺序，国王所在骨牌的主人：
- 1）把这块骨牌放进自己的王国；2）把国王移到新一排中还没人选的一块骨牌上。
- 选编号小（较差）的骨牌，下一轮能更早行动；选编号大的骨牌则行动靠后。
- 最后一排没有新骨牌，只放置不再选择。

# 放置规则
- 骨牌至少一格必须与城堡相邻（城堡视为任意地形），或与同种地形的格子相邻（上下左右）。
- 整个王国（含城堡）必须位于 5×5 的范围之内。
- 如果无处可放，这块骨牌只能被弃掉，不得分。

# 计分
- 每片相连的同种地形称为一块领地：得分 = 格子数 × 该领地的皇冠总数；没有皇冠的领地不得分。
- 平局时比最大领地的格数，再比皇冠总数，仍相同则共享胜利。

# 选项
- 巨人对决（仅 2 人）：使用全部 48 块骨牌，每人 2 个国王，王国扩大为 7×7。
- 中央王国：城堡位于王国正中央 +10 分。
- 和谐：王国完整拼满（没有空格、没有弃牌）+5 分。
- 两人对局可以认输。
''';
