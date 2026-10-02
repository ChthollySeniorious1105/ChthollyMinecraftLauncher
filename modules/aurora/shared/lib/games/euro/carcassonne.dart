import 'dart:math';

import '../../src/engine.dart';
import 'carc_tiles.dart';

class _Node {
  final FeatureKind kind;
  final int tile; // placed tile id
  final int feat; // feature index on that tile
  int parent;
  Set<int> tiles;
  int open;
  int shields;
  List<int> meeples = [];
  List<int> cityAdj;
  _Node(this.kind, this.tile, this.feat, this.parent, this.tiles, this.open, this.shields, this.cityAdj);
}

class CarcPlaced {
  final int id, x, y, type, rot, base;
  final List<TileFeature> feats;
  final List<int> sideFeat; // feature index per side for city/road edges, -1 otherwise
  final List<int> halfFeat; // field feature index per half-port, -1 if none
  CarcPlaced(this.id, this.x, this.y, this.type, this.rot, this.base, this.feats, this.sideFeat, this.halfFeat);
}

class CarcMeeple {
  final int seat, node, tile, feat;
  CarcMeeple(this.seat, this.node, this.tile, this.feat);
}

/// Aggregated information about a (possibly hypothetical) connected feature.
class FeatInfo {
  final FeatureKind kind;
  final int tiles, open, shields;
  final List<int> owners; // meeple seats (one entry per meeple)
  final List<int> localFeats; // features of the new tile in this group
  FeatInfo(this.kind, this.tiles, this.open, this.shields, this.owners, this.localFeats);
  bool get complete => open == 0;
}

int _key(int x, int y) => (x + 500) * 2000 + (y + 500);

/// 卡卡颂 base game.
class Carcassonne extends GameEngine {
  Carcassonne(super.setup);

  late final bool farmers = setup.opt<bool>('farmers', true);
  final Map<int, CarcPlaced> board = {};
  final List<CarcPlaced> placed = [];
  final List<_Node> nodes = [];
  final Map<int, CarcMeeple> meeples = {};
  int _meepleSeq = 0;
  List<int> deck = [];
  late List<int> scores;
  late List<int> meeplesLeft;
  int turn = 0;
  int cur = -1; // current tile type
  String phase = 'place'; // place / meeple / over
  int lastTile = -1;
  final List<String> recent = [];
  List<Map<String, dynamic>>? finalScores;
  late List<int> endBonus;

  /// Seat that resigned (2-player only), or -1.
  int resigned = -1;

  @override
  void start() {
    scores = List.filled(players, 0);
    endBonus = List.filled(players, 0);
    meeplesLeft = List.filled(players, 7);
    for (var t = 0; t < carcTiles.length; t++) {
      final n = carcTiles[t].count - (t == carcStartType ? 1 : 0);
      for (var i = 0; i < n; i++) {
        deck.add(t);
      }
    }
    deck.shuffle(rng);
    placeTile(0, 0, carcStartType, 0);
    turn = rng.nextInt(players);
    _draw();
  }

  // ------------------------------------------------------------------ board
  CarcPlaced? at(int x, int y) => board[_key(x, y)];

  int find(int n) {
    while (nodes[n].parent != n) {
      nodes[n].parent = nodes[nodes[n].parent].parent;
      n = nodes[n].parent;
    }
    return n;
  }

  void _union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra == rb) return;
    final A = nodes[ra], B = nodes[rb];
    B.parent = ra;
    A.tiles.addAll(B.tiles);
    A.open += B.open;
    A.shields += B.shields;
    A.meeples.addAll(B.meeples);
    A.cityAdj.addAll(B.cityAdj);
    B.meeples = [];
    B.cityAdj = [];
  }

  /// Whether tile [type] with rotation [rot] fits at (x,y).
  bool fits(int x, int y, int type, int rot) {
    if (at(x, y) != null) return false;
    final t = carcTiles[type];
    var any = false;
    for (var s = 0; s < 4; s++) {
      final (dx, dy) = sideDelta[s];
      final n = at(x + dx, y + dy);
      if (n == null) continue;
      any = true;
      if (carcTiles[n.type].edge((s + 2) % 4, n.rot) != t.edge(s, rot)) return false;
    }
    return any;
  }

  Set<int> frontier() {
    final out = <int>{};
    for (final p in placed) {
      for (final (dx, dy) in sideDelta) {
        if (at(p.x + dx, p.y + dy) == null) out.add(_key(p.x + dx, p.y + dy));
      }
    }
    return out;
  }

  /// All legal placements: list of (x, y, rot).
  List<(int, int, int)> legalPlacements(int type) {
    final out = <(int, int, int)>[];
    final f = frontier().toList()..sort();
    for (final k in f) {
      final x = k ~/ 2000 - 500, y = k % 2000 - 500;
      for (var r = 0; r < 4; r++) {
        if (fits(x, y, type, r)) out.add((x, y, r));
      }
    }
    return out;
  }

  CarcPlaced placeTile(int x, int y, int type, int rot) {
    final t = carcTiles[type];
    final feats = t.featuresAt(rot);
    final id = placed.length, base = nodes.length;
    final sideFeat = List.filled(4, -1), halfFeat = List.filled(8, -1);
    for (var i = 0; i < feats.length; i++) {
      final f = feats[i];
      for (final s in f.sides) {
        sideFeat[s] = i;
      }
      for (final h in f.halves) {
        halfFeat[h] = i;
      }
      final isEdge = f.kind == FeatureKind.city || f.kind == FeatureKind.road;
      nodes.add(_Node(f.kind, id, i, base + i, {id}, isEdge ? f.sides.length : 0, f.shield ? 1 : 0,
          [for (final a in f.adj) base + a]));
    }
    final p = CarcPlaced(id, x, y, type, rot, base, feats, sideFeat, halfFeat);
    placed.add(p);
    board[_key(x, y)] = p;
    for (var s = 0; s < 4; s++) {
      final (dx, dy) = sideDelta[s];
      final n = at(x + dx, y + dy);
      if (n == null) continue;
      final a = sideFeat[s], b = n.sideFeat[(s + 2) % 4];
      if (a >= 0 && b >= 0) {
        _union(base + a, n.base + b);
        nodes[find(base + a)].open -= 2;
      }
      for (final h in [2 * s, 2 * s + 1]) {
        final fa = halfFeat[h], fb = n.halfFeat[oppositeHalf(h)];
        if (fa >= 0 && fb >= 0) _union(base + fa, n.base + fb);
      }
    }
    lastTile = id;
    return p;
  }

  int cloisterCount(int x, int y) {
    var c = 0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (at(x + dx, y + dy) != null) c++;
      }
    }
    return c;
  }

  FeatInfo info(int node) {
    final r = nodes[find(node)];
    final owners = [for (final m in r.meeples) meeples[m]!.seat];
    if (r.kind == FeatureKind.cloister) {
      final p = placed[r.tile];
      final c = cloisterCount(p.x, p.y);
      return FeatInfo(r.kind, c, 9 - c, 0, owners, [r.feat]);
    }
    return FeatInfo(r.kind, r.tiles.length, r.open, r.shields, owners, [r.feat]);
  }

  /// Hypothetical merged features if tile (type,rot) were placed at (x,y).
  /// Field features are omitted.
  List<FeatInfo> preview(int x, int y, int type, int rot) {
    final feats = carcTiles[type].featuresAt(rot);
    final groups = <FeatInfo>[];
    // per local feature: roots it would connect to and connection count
    final roots = <int, Set<int>>{}, conns = <int, int>{};
    for (var i = 0; i < feats.length; i++) {
      final f = feats[i];
      if (f.kind != FeatureKind.city && f.kind != FeatureKind.road) continue;
      roots[i] = {};
      conns[i] = 0;
      for (final s in f.sides) {
        final (dx, dy) = sideDelta[s];
        final n = at(x + dx, y + dy);
        if (n == null) continue;
        final b = n.sideFeat[(s + 2) % 4];
        if (b < 0) continue;
        roots[i]!.add(find(n.base + b));
        conns[i] = conns[i]! + 1;
      }
    }
    // group local features sharing roots
    final done = <int>{};
    for (final i in roots.keys) {
      if (done.contains(i)) continue;
      final group = <int>{i};
      final rs = <int>{...roots[i]!};
      var changed = true;
      while (changed) {
        changed = false;
        for (final j in roots.keys) {
          if (group.contains(j)) continue;
          if (roots[j]!.any(rs.contains)) {
            group.add(j);
            rs.addAll(roots[j]!);
            changed = true;
          }
        }
      }
      done.addAll(group);
      final tiles = <int>{-1};
      var open = 0, shields = 0;
      final owners = <int>[];
      for (final r in rs) {
        final n = nodes[r];
        tiles.addAll(n.tiles);
        open += n.open;
        shields += n.shields;
        for (final m in n.meeples) {
          owners.add(meeples[m]!.seat);
        }
      }
      for (final j in group) {
        open += feats[j].sides.length - 2 * conns[j]!;
        if (feats[j].shield) shields++;
      }
      groups.add(FeatInfo(feats[i].kind, tiles.length, open, shields, owners, group.toList()));
    }
    for (var i = 0; i < feats.length; i++) {
      if (feats[i].kind == FeatureKind.cloister) {
        final c = cloisterCount(x, y) + 1;
        groups.add(FeatInfo(FeatureKind.cloister, c, 9 - c, 0, const [], [i]));
      }
    }
    return groups;
  }

  static int points(FeatInfo f, {bool endGame = false}) {
    switch (f.kind) {
      case FeatureKind.city:
        return endGame && !f.complete ? f.tiles + f.shields : 2 * f.tiles + 2 * f.shields;
      case FeatureKind.road:
        return f.tiles;
      case FeatureKind.cloister:
        return f.tiles;
      case FeatureKind.field:
        return 0;
    }
  }

  /// Seats holding the majority of meeples (ties all win).
  static List<int> majority(List<int> owners) {
    if (owners.isEmpty) return const [];
    final cnt = <int, int>{};
    for (final o in owners) {
      cnt[o] = (cnt[o] ?? 0) + 1;
    }
    final mx = cnt.values.reduce(max);
    return [for (final e in cnt.entries) if (e.value == mx) e.key]..sort();
  }

  /// Field root -> number of distinct completed cities it borders.
  int farmCities(int fieldNode) {
    final r = nodes[find(fieldNode)];
    final cities = <int>{};
    for (final c in r.cityAdj) {
      final cr = find(c);
      if (nodes[cr].open == 0) cities.add(cr);
    }
    return cities.length;
  }

  // ------------------------------------------------------------------ turn flow
  void _log(String s) {
    host.log(s);
    _note(s);
  }

  /// Adds a line to the on-board log only (not the chat).
  void _note(String s) {
    recent.add(s);
    if (recent.length > 6) recent.removeAt(0);
  }

  void _draw() {
    while (deck.isNotEmpty) {
      final t = deck.removeLast();
      if (legalPlacements(t).isNotEmpty) {
        cur = t;
        phase = 'place';
        return;
      }
      _log('板块 ${carcTiles[t].id} 无处可放，已弃置并重抽');
    }
    cur = -1;
    _endGame();
  }

  void _returnMeeples(int root) {
    for (final m in nodes[root].meeples) {
      final mm = meeples.remove(m)!;
      meeplesLeft[mm.seat]++;
    }
    nodes[root].meeples = [];
  }

  void _award(FeatInfo f, int pts, String what) {
    final win = majority(f.owners);
    if (win.isEmpty) return;
    for (final s in win) {
      scores[s] += pts;
    }
    _log('${win.map(name).join('、')} 完成$what，得 $pts 分');
  }

  void _scoreAfterPlacement(CarcPlaced p) {
    // cities & roads of the new tile
    final seen = <int>{};
    for (var i = 0; i < p.feats.length; i++) {
      final k = p.feats[i].kind;
      if (k != FeatureKind.city && k != FeatureKind.road) continue;
      final r = find(p.base + i);
      if (!seen.add(r)) continue;
      if (nodes[r].open != 0) continue;
      final f = info(r);
      _award(f, points(f), '${featureNames[k]}（${f.tiles} 块）');
      _returnMeeples(r);
    }
    // cloisters around (including own)
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final q = at(p.x + dx, p.y + dy);
        if (q == null) continue;
        for (var i = 0; i < q.feats.length; i++) {
          if (q.feats[i].kind != FeatureKind.cloister) continue;
          final n = q.base + i;
          if (nodes[n].meeples.isEmpty || cloisterCount(q.x, q.y) < 9) continue;
          final f = info(n);
          _award(f, 9, '修道院');
          _returnMeeples(n);
        }
      }
    }
  }

  void _endGame() {
    phase = 'over';
    final before = List.of(scores);
    final seen = <int>{};
    for (final m in meeples.values.toList()) {
      final r = find(m.node);
      if (!seen.add(r)) continue;
      final n = nodes[r];
      final f = info(r);
      int pts;
      if (n.kind == FeatureKind.field) {
        pts = 3 * farmCities(r);
      } else {
        pts = points(f, endGame: true);
      }
      final win = majority(f.owners);
      if (pts > 0) {
        for (final s in win) {
          scores[s] += pts;
        }
        _log('终局：${win.map(name).join('、')} 的${featureNames[n.kind]}得 $pts 分');
      }
    }
    for (var s = 0; s < players; s++) {
      endBonus[s] = scores[s] - before[s];
    }
    final best = scores.reduce(max);
    finalScores = [
      for (var s = 0; s < players; s++) {'seat': s, 'score': scores[s], 'end': endBonus[s], 'win': scores[s] == best}
    ];
    _log('游戏结束！${[for (var s = 0; s < players; s++) if (scores[s] == best) name(s)].join('、')} 获胜');
  }

  /// Features of the just-placed tile where [seat] may put a meeple.
  List<int> meepleOptions(int seat) {
    if (phase != 'meeple' || meeplesLeft[seat] <= 0) return const [];
    final p = placed[lastTile];
    return [
      for (var i = 0; i < p.feats.length; i++)
        if ((farmers || p.feats[i].kind != FeatureKind.field) && nodes[find(p.base + i)].meeples.isEmpty) i
    ];
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (phase == 'place') {
      if (type != 'place') throw GameError('请先放置板块');
      final x = asInt(a['x'], 99999), y = asInt(a['y'], 99999), r = asInt(a['rot'], 0) % 4;
      if (!fits(x, y, cur, r)) throw GameError('这里放不下（边必须与相邻板块吻合）');
      placeTile(x, y, cur, r);
      phase = 'meeple';
      return;
    }
    if (phase == 'meeple') {
      if (type != 'meeple') throw GameError('请选择是否放置跟随者');
      final f = asInt(a['f'], -1);
      final p = placed[lastTile];
      if (f >= 0) {
        if (!meepleOptions(seat).contains(f)) throw GameError('这个位置不能放跟随者');
        final id = _meepleSeq++;
        meeples[id] = CarcMeeple(seat, p.base + f, p.id, f);
        nodes[find(p.base + f)].meeples.add(id);
        meeplesLeft[seat]--;
        _note('${name(seat)} 放置板块，并派跟随者占据${featureNames[p.feats[f].kind]}');
      } else {
        _note('${name(seat)} 放置板块');
      }
      _scoreAfterPlacement(p);
      turn = (turn + 1) % players;
      _draw();
      return;
    }
  }

  @override
  List<int> get waitingFor => phase == 'over' ? const [] : [turn];

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(scores);
  }

  @override
  bool get canResign => phase != 'over' && players == 2;

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    resigned = seat;
    phase = 'over';
    cur = -1;
    finalScores = [
      for (var s = 0; s < players; s++) {'seat': s, 'score': scores[s], 'end': 0, 'win': s != seat}
    ];
    _log('${name(seat)} 认输，${name(1 - seat)} 获胜');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  Map<String, dynamic> view(int seat) {
    final legal = <String, List<int>>{};
    if (phase == 'place' && cur >= 0) {
      for (final (x, y, r) in legalPlacements(cur)) {
        (legal['$x,$y'] ??= []).add(r);
      }
    }
    return {
      'phase': phase,
      'turn': turn,
      'cur': cur >= 0 ? carcTiles[cur].id : null,
      'deck': deck.length,
      'farmers': farmers,
      'tiles': [for (final p in placed) {'x': p.x, 'y': p.y, 't': carcTiles[p.type].id, 'r': p.rot}],
      'last': lastTile,
      'meeples': [
        for (final m in meeples.values) {'s': m.seat, 'tile': m.tile, 'f': m.feat, 'k': nodes[m.node].kind.name}
      ],
      'legal': [
        for (final e in legal.entries)
          {'x': int.parse(e.key.split(',')[0]), 'y': int.parse(e.key.split(',')[1]), 'r': e.value}
      ],
      'meepleOpts': phase == 'meeple' ? meepleOptions(turn) : const <int>[],
      'scores': scores,
      'meeplesLeft': meeplesLeft,
      'recent': recent,
      'final': finalScores,
    };
  }

  // ------------------------------------------------------------------ bot
  double _meepleCost(int seat) {
    if (botLevel >= 2) {
      // spare meeples are worthless near the end: cost falls with remaining own turns
      final turnsLeft = deck.length / players;
      if (turnsLeft <= meeplesLeft[seat]) return 0.2;
      final scarcity = (7 - meeplesLeft[seat]) * 0.7;
      return 1.2 + scarcity * min(1.0, turnsLeft / 12);
    }
    return 1.5 + (7 - meeplesLeft[seat]) * 0.6 - (deck.length < 8 ? 1.0 : 0);
  }

  /// Value of the feature change for [seat]; [withMeeple] = seat adds a meeple to it.
  double _featValue(int seat, FeatInfo f, bool withMeeple, {int addedTiles = 1}) {
    final owners = withMeeple ? [...f.owners, seat] : f.owners;
    final win = majority(owners);
    final endSoon = deck.length < 6;
    double v = 0;
    if (f.complete) {
      final pts = f.kind == FeatureKind.cloister ? 9 : points(f);
      if (win.contains(seat)) v += pts;
      for (final o in win) {
        if (o != seat) v -= pts * _rivalWeight;
      }
      // 困难: completing also returns our meeples for reuse
      if (botLevel >= 2 && !withMeeple && deck.length > 2 * players) {
        v += 1.2 * f.owners.where((o) => o == seat).length;
      }
      return v;
    }
    // incomplete: expected fraction of eventual points
    final prob = botLevel >= 2
        ? _completionProb(f)
        : f.kind == FeatureKind.cloister
            ? (endSoon ? 0.0 : 0.6)
            : endSoon
                ? 0.0
                : (f.open <= 2 ? 0.65 : (f.open <= 4 ? 0.4 : 0.25));
    final full = f.kind == FeatureKind.cloister ? 9.0 : points(f).toDouble();
    final partial = points(f, endGame: true).toDouble();
    final expected = prob * full + (1 - prob) * partial;
    if (withMeeple) {
      v += expected - _meepleCost(seat);
    } else {
      // growth of features already owned
      final growth = f.kind == FeatureKind.city ? 1.6 : (f.kind == FeatureKind.cloister ? 1.0 : 0.8);
      if (win.contains(seat)) v += growth * addedTiles;
      for (final o in win) {
        if (o != seat) v -= growth * 0.7 * addedTiles;
      }
    }
    return v;
  }

  /// How much an opponent's gain hurts.
  double get _rivalWeight => botLevel >= 2 && players > 2 ? 0.6 : 0.8;

  /// 困难: completion chance from open edges vs. the tiles each player still gets.
  double _completionProb(FeatInfo f) {
    final myTurns = deck.length / players;
    if (f.kind == FeatureKind.cloister) {
      // missing neighbours get filled by anyone's tiles
      final need = 9 - f.tiles;
      if (need <= 0) return 1;
      return (deck.length / (need * 2.5 + deck.length)).clamp(0.0, 0.9) * (deck.length >= need ? 1 : 0);
    }
    if (f.open <= 0) return 1;
    if (myTurns < 1) return 0;
    final base = f.open <= 1 ? 0.8 : (f.open <= 2 ? 0.62 : (f.open <= 4 ? 0.38 : 0.2));
    // late in the game an open feature needs roughly one own tile per open edge
    final timeFactor = (myTurns / (f.open + 1)).clamp(0.0, 1.0);
    return base * timeFactor;
  }

  double _placementValue(int seat, int x, int y, int rot) {
    var v = 0.0;
    var bestMeeple = 0.0;
    final canMeeple = meeplesLeft[seat] > 0;
    for (final f in preview(x, y, cur, rot)) {
      v += _featValue(seat, f, false);
      if (canMeeple && f.owners.isEmpty) bestMeeple = max(bestMeeple, _featValue(seat, f, true) - _featValue(seat, f, false));
    }
    // neighbouring cloisters
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final q = at(x + dx, y + dy);
        if (q == null) continue;
        for (var i = 0; i < q.feats.length; i++) {
          if (q.feats[i].kind != FeatureKind.cloister) continue;
          final n = nodes[q.base + i];
          if (n.meeples.isEmpty) continue;
          final o = meeples[n.meeples.first]!.seat;
          final done = cloisterCount(q.x, q.y) + 1 == 9;
          final gain = done ? 3.0 : 1.0;
          v += o == seat ? gain : -gain * 0.7;
        }
      }
    }
    return v + bestMeeple;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (seat != turn || phase == 'over') return null;
    // 简单: often just a random legal move
    final sloppy = botLevel <= 0 && rng.nextDouble() < 0.45;
    if (phase == 'place') {
      final opts = legalPlacements(cur);
      if (sloppy) {
        final o = opts[rng.nextInt(opts.length)];
        return {'type': 'place', 'x': o.$1, 'y': o.$2, 'rot': o.$3};
      }
      final noise = botLevel <= 0 ? 3.0 : (botLevel >= 2 ? 0.05 : 0.2);
      var best = opts.first;
      var bv = double.negativeInfinity;
      for (final o in opts) {
        final v = _placementValue(seat, o.$1, o.$2, o.$3) + rng.nextDouble() * noise;
        if (v > bv) {
          bv = v;
          best = o;
        }
      }
      return {'type': 'place', 'x': best.$1, 'y': best.$2, 'rot': best.$3};
    }
    // meeple phase
    final p = placed[lastTile];
    if (sloppy) {
      final o = meepleOptions(seat);
      final pick = rng.nextInt(o.length + 2) - 2; // -2/-1 = no meeple
      return {'type': 'meeple', 'f': pick < 0 ? -1 : o[pick]};
    }
    var bestF = -1;
    var bv = 0.3;
    for (final i in meepleOptions(seat)) {
      final n = p.base + i;
      double v;
      if (p.feats[i].kind == FeatureKind.field) {
        final cities = farmCities(n);
        final pending = nodes[find(n)].cityAdj.map(find).toSet().length - cities;
        v = 3.0 * cities + 1.2 * pending - 4.0 - (botLevel >= 2 ? _meepleCost(seat) : (7 - meeplesLeft[seat]) * 0.8);
        if (deck.length > 40) v -= 2;
        if (botLevel >= 2) {
          // late farmers are cheap: meeples would not return anyway
          if (deck.length < 3 * players) v += 1.5 * cities + 1.0;
        }
      } else {
        final f = info(n);
        v = _featValue(seat, f, true) - _featValue(seat, f, false);
      }
      if (v > bv) {
        bv = v;
        bestF = i;
      }
    }
    return {'type': 'meeple', 'f': bestF};
  }
}
