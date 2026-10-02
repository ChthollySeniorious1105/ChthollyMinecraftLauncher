import 'dart:math';

import '../../src/engine.dart';

/// 花砖物语 Azul.
///
/// Colours 0..4 = 蓝 黄 红 黑 白; 5 = 先手标记 (only on the floor line).
/// Standard wall: colour at (r, c) = (c - r) mod 5. Grey wall (灰墙) variant:
/// the player chooses the column when tiling, every row and column may hold
/// each colour at most once.
class Azul extends GameEngine {
  Azul(super.setup);

  static const colorNames = ['蓝', '黄', '红', '黑', '白'];
  static const floorPen = [-1, -1, -2, -2, -2, -3, -3];
  static const tokenCode = 5;
  static int wallColor(int r, int c) => (c - r + 5) % 5;

  bool grey = false;
  List<int> bag = [];
  List<int> lid = [];
  List<List<int>> factories = [];
  List<int> center = [];
  bool tokenInCenter = true;
  int firstNext = 0;
  int turn = 0;
  int round = 0;
  String phase = 'draft'; // draft / tile / over
  late List<List<List<int>>> wall; // [p][r][c]: -1 empty, else colour
  late List<List<int>> lineColor; // [p][r]: -1 empty
  late List<List<int>> lineCount;
  late List<List<int>> floor; // [p]: colours, 5 = token
  late List<int> score;
  Map<String, dynamic>? last;
  final List<String> recent = [];
  List<Map<String, dynamic>>? finalRows;
  int resigned = -1;

  /// Per-round tiling summary for the board: [p] -> list of {r,c,pts}.
  List<List<Map<String, dynamic>>> tiled = [];
  List<int> floorLoss = [];

  int get factoryCount => 2 * players + 1;

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 8) recent.removeAt(0);
  }

  @override
  void start() {
    grey = setup.opt('wall', 'color') == 'grey';
    bag = [for (var c = 0; c < 5; c++) ...List.filled(20, c)]..shuffle(rng);
    wall = [for (var p = 0; p < players; p++) List.generate(5, (_) => List.filled(5, -1))];
    lineColor = [for (var p = 0; p < players; p++) List.filled(5, -1)];
    lineCount = [for (var p = 0; p < players; p++) List.filled(5, 0)];
    floor = [for (var p = 0; p < players; p++) <int>[]];
    score = List.filled(players, 0);
    tiled = [for (var p = 0; p < players; p++) <Map<String, dynamic>>[]];
    floorLoss = List.filled(players, 0);
    firstNext = rng.nextInt(players);
    _log('花砖物语${grey ? '（灰墙自由摆放）' : ''}：${name(firstNext)} 持先手标记');
    _newRound();
  }

  void _newRound() {
    round++;
    factories = [];
    for (var f = 0; f < factoryCount; f++) {
      final t = <int>[];
      for (var k = 0; k < 4; k++) {
        if (bag.isEmpty) {
          if (lid.isEmpty) break;
          bag = shuffled(lid, rng);
          lid = [];
        }
        t.add(bag.removeLast());
      }
      t.sort();
      factories.add(t);
    }
    center = [];
    tokenInCenter = true;
    turn = firstNext;
    phase = 'draft';
  }

  /// Can seat [p] put colour [c] on pattern line [r]?
  bool canLine(int p, int r, int c) {
    if (lineCount[p][r] >= r + 1) return false;
    if (lineColor[p][r] != -1 && lineColor[p][r] != c) return false;
    if (wall[p][r].contains(c)) return false;
    return true;
  }

  /// Legal wall columns for row [r] colour [c] (grey wall).
  List<int> greyCols(int p, int r, int c) => [
        for (var col = 0; col < 5; col++)
          if (wall[p][r][col] == -1 && !wall[p][r].contains(c) && ![for (var x = 0; x < 5; x++) wall[p][x][col]].contains(c)) col,
      ];

  void _toFloor(int p, int c, int n) {
    for (var i = 0; i < n; i++) {
      if (floor[p].length < 7) {
        floor[p].add(c);
      } else {
        lid.add(c);
      }
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (phase == 'tile') {
      if (type != 'tile') throw GameError('请先把完成的图案行铺到墙上');
      final r = pendingRow(seat);
      if (r < 0) throw GameError('你没有需要铺砖的行');
      final col = asInt(a['col']);
      final ok = greyCols(seat, r, lineColor[seat][r]);
      if (!ok.contains(col)) throw GameError('这一列不能放这种颜色');
      _placeWall(seat, r, col);
      _advanceTiling();
      return;
    }
    if (type != 'take') throw GameError('无效操作');
    if (seat != turn) throw GameError('还没轮到你');
    final src = asInt(a['src'], -99);
    final c = asInt(a['color']);
    final line = asInt(a['line'], -99);
    if (c < 0 || c > 4) throw GameError('无效颜色');
    List<int> from;
    if (src == -1) {
      from = center;
    } else if (src >= 0 && src < factories.length) {
      from = factories[src];
    } else {
      throw GameError('无效的工厂');
    }
    final n = from.where((x) => x == c).length;
    if (n == 0) throw GameError('那里没有这种颜色的瓷砖');
    if (line != -1 && (line < 0 || line > 4)) throw GameError('无效的图案行');
    if (line >= 0 && !canLine(seat, line, c)) {
      throw GameError(wall[seat][line].contains(c) ? '墙上这一行已经有${colorNames[c]}色' : '这一行放不下这种颜色');
    }
    var gotToken = false;
    if (src == -1) {
      center.removeWhere((x) => x == c);
      if (tokenInCenter) {
        tokenInCenter = false;
        gotToken = true;
        firstNext = seat;
        if (floor[seat].length < 7) floor[seat].add(tokenCode);
      }
    } else {
      final rest = from.where((x) => x != c).toList();
      factories[src] = [];
      center.addAll(rest);
      center.sort();
    }
    var over = n;
    if (line >= 0) {
      final space = line + 1 - lineCount[seat][line];
      final put = min(space, n);
      lineCount[seat][line] += put;
      lineColor[seat][line] = c;
      over = n - put;
    }
    _toFloor(seat, c, over);
    last = {'seat': seat, 'src': src, 'color': c, 'n': n, 'line': line, 'token': gotToken};
    final where = src == -1 ? '中央' : '工厂${src + 1}';
    final to = line >= 0 ? '第${line + 1}行' : '地板';
    _log('${name(seat)} 从$where拿 $n 块${colorNames[c]}砖 → $to${over > 0 && line >= 0 ? '（$over 块溢出）' : ''}${gotToken ? '，拿到先手标记' : ''}');
    if (factories.every((f) => f.isEmpty) && center.isEmpty) {
      _startTiling();
    } else {
      turn = (turn + 1) % players;
    }
  }

  // ------------------------------------------------------------------ tiling
  int pendingRow(int p) {
    for (var r = 0; r < 5; r++) {
      if (lineCount[p][r] == r + 1) return r;
    }
    return -1;
  }

  void _startTiling() {
    tiled = [for (var p = 0; p < players; p++) <Map<String, dynamic>>[]];
    floorLoss = List.filled(players, 0);
    if (!grey) {
      for (var p = 0; p < players; p++) {
        for (var r = 0; r < 5; r++) {
          if (lineCount[p][r] == r + 1) {
            final c = lineColor[p][r];
            _placeWall(p, r, (r + c) % 5);
          }
        }
      }
      _finishRound();
      return;
    }
    phase = 'tile';
    _advanceTiling();
  }

  /// Grey wall: auto-resolve rows that can't be placed; finish when nobody has work.
  void _advanceTiling() {
    for (var p = 0; p < players; p++) {
      while (true) {
        final r = pendingRow(p);
        if (r < 0) break;
        final c = lineColor[p][r];
        final cols = greyCols(p, r, c);
        if (cols.isNotEmpty) break;
        _toFloor(p, c, r + 1);
        lineCount[p][r] = 0;
        lineColor[p][r] = -1;
        _log('${name(p)} 第${r + 1}行的${colorNames[c]}砖无处可放，全部落到地板');
      }
    }
    if ([for (var p = 0; p < players; p++) pendingRow(p)].every((r) => r < 0)) _finishRound();
  }

  static int adjacency(List<List<int>> w, int r, int c) {
    var h = 1, v = 1;
    for (var x = c - 1; x >= 0 && w[r][x] != -1; x--) {
      h++;
    }
    for (var x = c + 1; x < 5 && w[r][x] != -1; x++) {
      h++;
    }
    for (var y = r - 1; y >= 0 && w[y][c] != -1; y--) {
      v++;
    }
    for (var y = r + 1; y < 5 && w[y][c] != -1; y++) {
      v++;
    }
    if (h > 1 && v > 1) return h + v;
    return max(h, v);
  }

  void _placeWall(int p, int r, int col) {
    final c = lineColor[p][r];
    wall[p][r][col] = c;
    final pts = adjacency(wall[p], r, col);
    score[p] += pts;
    lid.addAll(List.filled(r, c));
    lineCount[p][r] = 0;
    lineColor[p][r] = -1;
    tiled[p].add({'r': r, 'c': col, 'pts': pts});
  }

  void _finishRound() {
    for (var p = 0; p < players; p++) {
      var pen = 0;
      for (var i = 0; i < floor[p].length && i < 7; i++) {
        pen += floorPen[i];
      }
      final before = score[p];
      score[p] = max(0, score[p] + pen);
      floorLoss[p] = score[p] - before;
      for (final t in floor[p]) {
        if (t != tokenCode) lid.add(t);
      }
      floor[p] = [];
      final gained = tiled[p].fold<int>(0, (s, t) => s + (t['pts'] as int));
      _log('${name(p)} 本轮铺砖 +$gained${pen != 0 ? '，地板 ${floorLoss[p]}' : ''}，共 ${score[p]} 分');
    }
    final ended = [for (var p = 0; p < players; p++) completeRows(p) > 0].any((x) => x);
    if (ended) {
      _endGame();
    } else {
      _newRound();
    }
  }

  int completeRows(int p) => [for (var r = 0; r < 5; r++) wall[p][r].every((x) => x != -1)].where((x) => x).length;
  int completeCols(int p) => [for (var c = 0; c < 5; c++) [for (var r = 0; r < 5; r++) wall[p][r][c]].every((x) => x != -1)].where((x) => x).length;
  int completeColors(int p) => [for (var k = 0; k < 5; k++) wall[p].expand((row) => row).where((x) => x == k).length == 5].where((x) => x).length;

  void _endGame() {
    finalRows = [];
    for (var p = 0; p < players; p++) {
      final rows = completeRows(p), cols = completeCols(p), colors = completeColors(p);
      final bonus = rows * 2 + cols * 7 + colors * 10;
      score[p] += bonus;
      finalRows!.add({'seat': p, 'rows': rows, 'cols': cols, 'colors': colors, 'bonus': bonus, 'score': score[p]});
    }
    phase = 'over';
    final pl = placings!;
    final winners = [for (var p = 0; p < players; p++) if (pl[p] == 1) name(p)];
    _log('游戏结束！${winners.join('、')} 获胜（${[for (var p = 0; p < players; p++) '${name(p)} ${score[p]}'].join(' / ')}）');
  }

  // ------------------------------------------------------------------ engine api
  @override
  List<int> get waitingFor {
    if (phase == 'draft') return [turn];
    if (phase == 'tile') return [for (var p = 0; p < players; p++) if (pendingRow(p) >= 0) p];
    return const [];
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore([for (var p = 0; p < players; p++) score[p] * 10 + completeRows(p)]);
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

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': phase,
        'grey': grey,
        'round': round,
        'turn': turn,
        'factories': factories,
        'center': center,
        'token': tokenInCenter,
        'firstNext': firstNext,
        'bag': bag.length,
        'lid': lid.length,
        'players': [
          for (var p = 0; p < players; p++)
            {
              'score': score[p],
              'wall': wall[p],
              'lineColor': lineColor[p],
              'lineCount': lineCount[p],
              'floor': floor[p],
              'tiled': tiled[p],
              'floorLoss': floorLoss[p],
              'pending': phase == 'tile' ? pendingRow(p) : -1,
              'greyCols': phase == 'tile' && pendingRow(p) >= 0 ? greyCols(p, pendingRow(p), lineColor[p][pendingRow(p)]) : const <int>[],
            }
        ],
        'last': last,
        'recent': recent,
        'result': finalRows,
        'resigned': resigned,
        'placings': placings,
      };

  // ------------------------------------------------------------------ bot
  List<(int, int, int)> legalMoves(int p) {
    final out = <(int, int, int)>[];
    final sources = <int, List<int>>{-1: center, for (var f = 0; f < factories.length; f++) f: factories[f]};
    for (final e in sources.entries) {
      for (final c in e.value.toSet()) {
        for (var l = -1; l < 5; l++) {
          if (l == -1 || canLine(p, l, c)) out.add((e.key, c, l));
        }
      }
    }
    return out;
  }

  double _evalMove(int p, int src, int c, int line) {
    final from = src == -1 ? center : factories[src];
    final n = from.where((x) => x == c).length;
    final lvl = botLevel;
    final flen = floor[p].length;
    var over = n;
    var v = 0.0;
    final roundsLeftGuess = max(1, 6 - round);
    if (line >= 0) {
      final space = line + 1 - lineCount[p][line];
      final put = min(space, n);
      over = n - put;
      if (put == space) {
        // completes the line: value of the wall tile
        final col = grey ? _bestGreyCol(p, line, c) : (line + c) % 5;
        if (col >= 0) {
          final w = [for (final r in wall[p]) List.of(r)];
          w[line][col] = c;
          v += adjacency(w, line, col) + 0.5;
          if (lvl >= 2) {
            if (w[line].every((x) => x != -1)) v += 2;
            if ([for (var r = 0; r < 5; r++) w[r][col]].every((x) => x != -1)) v += 5;
            if (w.expand((r) => r).where((x) => x == c).length == 5) v += 6;
          }
        }
      } else {
        // progress on a line that stays open this round
        final remaining = space - put;
        v += put * 0.9 - remaining * (lvl >= 2 ? 0.45 : 0.25);
        if (lineCount[p][line] == 0) v -= 0.3 * line;
      }
      // prefer filling top rows early
      v += (4 - line) * 0.05;
    }
    final tokenCost = src == -1 && tokenInCenter ? 1 : 0;
    var pen = 0;
    for (var i = 0; i < over + tokenCost; i++) {
      final idx = flen + i;
      if (idx < 7) pen += floorPen[idx];
    }
    v += pen * (lvl >= 1 ? 1.0 : 0.6);
    if (tokenCost > 0 && lvl >= 1) v += 0.8; // first player next round is worth a bit
    if (lvl >= 2) {
      // don't dump many tiles into the centre for the opponent's benefit late in round
      if (src >= 0) v -= 0.08 * (from.length - n);
      v += 0.05 * roundsLeftGuess;
    }
    return v;
  }

  int _bestGreyCol(int p, int r, int c) {
    final cols = greyCols(p, r, c);
    if (cols.isEmpty) return -1;
    var best = cols.first;
    var bv = -1e9;
    for (final col in cols) {
      final w = [for (final row in wall[p]) List.of(row)];
      w[r][col] = c;
      // adjacency now + how many colours still fit in that column afterwards
      var val = adjacency(w, r, col).toDouble();
      val += 0.1 * (5 - col).abs();
      final colFill = [for (var y = 0; y < 5; y++) w[y][col]].where((x) => x != -1).length;
      val += colFill * 0.3;
      if (val > bv) {
        bv = val;
        best = col;
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'tile') {
      final r = pendingRow(seat);
      if (r < 0) return null;
      final c = lineColor[seat][r];
      final cols = greyCols(seat, r, c);
      if (cols.isEmpty) return null;
      final col = botLevel == 0 ? cols[rng.nextInt(cols.length)] : _bestGreyCol(seat, r, c);
      return {'type': 'tile', 'col': col};
    }
    if (phase != 'draft' || seat != turn) return null;
    final moves = legalMoves(seat);
    if (moves.isEmpty) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.4) {
      final lined = moves.where((m) => m.$3 >= 0).toList();
      final pick = (lined.isNotEmpty ? lined : moves)[rng.nextInt(lined.isNotEmpty ? lined.length : moves.length)];
      return {'type': 'take', 'src': pick.$1, 'color': pick.$2, 'line': pick.$3};
    }
    (int, int, int)? best;
    var bv = -1e9;
    for (final m in moves) {
      var v = _evalMove(seat, m.$1, m.$2, m.$3);
      v += rng.nextDouble() * (botLevel == 0 ? 2.0 : (botLevel == 1 ? 0.4 : 0.05));
      if (v > bv) {
        bv = v;
        best = m;
      }
    }
    return {'type': 'take', 'src': best!.$1, 'color': best.$2, 'line': best.$3};
  }
}

const azulRules = '''
# 花砖物语 Azul
2~4 名玩家为葡萄牙国王的宫殿铺设花砖。共 100 块瓷砖，5 种颜色（蓝、黄、红、黑、白）各 20 块，放在布袋中。

# 准备
- 工厂数量：2 人 5 个，3 人 7 个，4 人 9 个；每轮开始从袋中随机抽 4 块放到每个工厂上。袋子空了就把弃砖盒中的砖倒回袋中重新洗匀。
- 中央区域开局放着“先手标记”。

# 选砖阶段
- 轮到你时，选择一个工厂或中央区域中的一种颜色，拿走那里这种颜色的全部瓷砖。
- 从工厂拿砖时，该工厂剩下的砖移到中央；第一个从中央拿砖的玩家同时拿走先手标记（放在自己地板线上，会扣分，下一轮由他先手）。
- 把拿到的砖放到自己 5 行图案行中的一行（第 1 行放 1 块…第 5 行放 5 块）：一行只能放同一种颜色；墙上这一行已经有该颜色时不能再放。
- 放不下的砖落到地板线；也可以直接全部放到地板线。地板线 7 格依次扣 1、1、2、2、2、3、3 分，超出的砖直接进弃砖盒。
- 所有工厂与中央都被拿空后，进入铺砖阶段。

# 铺砖阶段
- 每一个放满的图案行，把最右 1 块移到墙上同一行的对应位置，其余进弃砖盒；没放满的行保留到下一轮。
- 计分：新砖单独一块得 1 分；与横向相连的砖形成一串，得该串长度；纵向同理；横纵都相连则两者相加。
- 然后结算地板线扣分（分数不会低于 0），地板上的砖清空，持先手标记者下一轮先手。

# 结束与奖励
- 当有玩家在铺砖后墙上完成一整行（横向 5 块），本轮结束后游戏结束。
- 终局奖励：每完成一横行 +2 分，每完成一竖列 +7 分，每种颜色 5 块全部铺上墙 +10 分。
- 分数最高者获胜；平局时完成横行多者获胜，再平则共享胜利。

# 选项
- 标准彩色墙：每行每列颜色位置固定（对角错开）。
- 灰墙（自由摆放）：墙上没有颜色，铺砖时由你为每一个完成的行选择放在哪一列，但每一横行、每一竖列中同色只能出现一次；若某行的砖没有任何合法列可放，这一行的砖全部落到地板线。
- 两人对局可以认输。
''';
