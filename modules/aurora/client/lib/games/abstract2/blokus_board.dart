import 'dart:math';

import 'package:aurora_shared/games/abstract2/blokus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _colors4 = [Color(0xFF1E6FD9), Color(0xFFF2B705), Color(0xFFE0393E), Color(0xFF2FA84F)];
const _colors2 = [Color(0xFF7B4FD0), Color(0xFFF08A24)];
const _names4 = ['蓝', '黄', '红', '绿'];
const _names2 = ['紫', '橙'];

Color blokusColor(int c, int players) => players == 2 ? _colors2[c % 2] : _colors4[c % 4];
String blokusColorName(int c, int players) => players == 2 ? _names2[c % 2] : _names4[c % 4];

void _paintSquare(Canvas canvas, Rect r, Color color, {double opacity = 1}) {
  final rr = RRect.fromRectAndRadius(r.deflate(r.width * 0.04), Radius.circular(r.width * 0.16));
  canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
            Color.lerp(color, Colors.black, 0.25)!.withValues(alpha: opacity),
          ],
        ).createShader(r));
  canvas.drawRRect(
      rr.deflate(r.width * 0.16),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, r.width * 0.06)
        ..color = Colors.white.withValues(alpha: 0.28 * opacity));
}

class _BoardPainter extends CustomPainter {
  final int n, players;
  final List<int> cells;
  final Set<int> lastCells;
  final Set<int> anchors;
  final List<(int, int)> ghost;
  final bool ghostOk;
  final int myColor;
  final List<(int, int)> starts;
  final Color bg;
  _BoardPainter(this.n, this.players, this.cells, this.lastCells, this.anchors, this.ghost, this.ghostOk, this.myColor, this.starts, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * 0.02;
    final cell = (size.width - 2 * m) / n;
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.03));
    canvas.drawRRect(outer.shift(Offset(0, size.width * 0.008)), a2Shadow(size.width * 0.015, alpha: 0.5));
    canvas.drawRRect(
        outer,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4B5563), Color(0xFF374151)],
          ).createShader(Offset.zero & size));
    final inner = Rect.fromLTWH(m, m, cell * n, cell * n);
    canvas.drawRect(inner, Paint()..color = const Color(0xFFE5E7EB));
    final grid = Paint()
      ..color = const Color(0xFFC4C9D1)
      ..strokeWidth = max(0.5, cell * 0.04);
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(Offset(m + i * cell, m), Offset(m + i * cell, m + n * cell), grid);
      canvas.drawLine(Offset(m, m + i * cell), Offset(m + n * cell, m + i * cell), grid);
    }
    Rect rc(int x, int y) => Rect.fromLTWH(m + x * cell, m + y * cell, cell, cell);
    // start markers
    for (final (x, y) in starts) {
      if (cells[y * n + x] != -1) continue;
      final c = rc(x, y).center;
      canvas.drawCircle(c, cell * 0.3, Paint()..color = const Color(0xFF9CA3AF));
      canvas.drawCircle(c, cell * 0.14, Paint()..color = const Color(0xFFE5E7EB));
    }
    if (n == 20) {
      for (var c = 0; c < min(players, 4); c++) {
        final (x, y) = [(0, 0), (n - 1, 0), (n - 1, n - 1), (0, n - 1)][c];
        if (cells[y * n + x] != -1) continue;
        canvas.drawRect(rc(x, y).deflate(cell * 0.12), Paint()..color = blokusColor(c, players).withValues(alpha: 0.35));
      }
    }
    for (var i = 0; i < n * n; i++) {
      final v = cells[i];
      if (v < 0) continue;
      _paintSquare(canvas, rc(i % n, i ~/ n), blokusColor(v, players));
    }
    for (final i in lastCells) {
      canvas.drawRect(
          rc(i % n, i ~/ n).deflate(cell * 0.02),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.2, cell * 0.1)
            ..color = Colors.white.withValues(alpha: 0.9));
    }
    if (myColor >= 0) {
      final col = blokusColor(myColor, players);
      for (final a in anchors) {
        final c = rc(a % n, a ~/ n).center;
        canvas.drawCircle(c, cell * 0.16, Paint()..color = col.withValues(alpha: 0.7));
      }
    }
    if (ghost.isNotEmpty && myColor >= 0) {
      final col = ghostOk ? blokusColor(myColor, players) : const Color(0xFFEF4444);
      for (final (x, y) in ghost) {
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        _paintSquare(canvas, rc(x, y), col, opacity: ghostOk ? 0.6 : 0.45);
        canvas.drawRect(
            rc(x, y).deflate(cell * 0.04),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1, cell * 0.07)
              ..color = ghostOk ? Colors.white : const Color(0xFF7F1D1D));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class _PieceIcon extends CustomPainter {
  final List<(int, int)> cells;
  final Color color;
  final double opacity;
  _PieceIcon(this.cells, this.color, {this.opacity = 1});
  @override
  void paint(Canvas canvas, Size size) {
    var w = 0, h = 0;
    for (final (x, y) in cells) {
      w = max(w, x + 1);
      h = max(h, y + 1);
    }
    final u = min(size.width / max(w, 3), size.height / max(h, 3)) * 0.92;
    final ox = (size.width - u * w) / 2, oy = (size.height - u * h) / 2;
    for (final (x, y) in cells) {
      _paintSquare(canvas, Rect.fromLTWH(ox + x * u, oy + y * u, u, u), color, opacity: opacity);
    }
  }

  @override
  bool shouldRepaint(covariant _PieceIcon o) => o.cells != cells || o.color != color || o.opacity != opacity;
}

class BlokusBoardView extends StatefulWidget {
  final GameContext g;
  const BlokusBoardView(this.g, {super.key});
  @override
  State<BlokusBoardView> createState() => _BlokusBoardViewState();
}

class _BlokusBoardViewState extends State<BlokusBoardView> {
  int piece = -1;
  int rot = 0;
  bool flip = false;
  int hoverCell = -1;
  Object? _memoKey;
  Set<int> _playable = {};
  BlokusBoard? _board;
  GameContext get g => widget.g;

  void _rotate() => setState(() => rot = (rot + 1) % 4);
  void _flip() => setState(() => flip = !flip);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = g.view;
    final n = v['n'] as int;
    final players = g.players;
    final cells = (v['board'] as List).cast<int>();
    final used = [for (final u in v['used'] as List) (u as List).cast<bool>()];
    final turn = v['turn'] as int;
    final done = (v['done'] as List).cast<bool>();
    final resigned = (v['resigned'] as List).cast<bool>();
    final remaining = (v['remaining'] as List).cast<int>();
    final scores = (v['scores'] as List).cast<int>();
    final anchors = (v['anchors'] as List).cast<int>().toSet();
    final last = v['last'] as Map?;
    final lastCells = last == null ? <int>{} : (last['cells'] as List).cast<int>().toSet();
    final note = v['note'] as String;
    final result = v['result'] as String;
    final over = v['over'] == true;
    final me = g.seat;
    final isPlayer = me >= 0 && me < players;
    final myTurn = !over && isPlayer && turn == me && !g.replay;

    // memo: board + which of my pieces can still be played somewhere
    final key = '${v['placed']}|$turn|$over|$me';
    if (_memoKey != key) {
      _memoKey = key;
      _board = BlokusBoard.from(n, players, cells, used);
      _playable = {};
      if (myTurn) {
        for (final m in _board!.legalMoves(me)) {
          _playable.add(m.piece);
        }
      }
      if (piece >= 0 && (!isPlayer || used[me][piece])) piece = -1;
    }
    final board = _board!;

    // ghost preview
    var ghost = <(int, int)>[];
    var ghostOk = false;
    int orient = 0;
    if (myTurn && piece >= 0 && hoverCell >= 0) {
      final pc = blokusPieces[piece];
      orient = pc.orientOf(rot, flip);
      final shape = pc.orients[orient];
      final hx = hoverCell % n, hy = hoverCell ~/ n;
      var w = 0, h = 0;
      for (final (x, y) in shape) {
        w = max(w, x + 1);
        h = max(h, y + 1);
      }
      // default: centred on the hovered cell; snap to any legal alignment covering it
      final cands = <(int, int)>[
        (hx - (w - 1) ~/ 2, hy - (h - 1) ~/ 2),
        for (final (cx, cy) in shape) (hx - cx, hy - cy),
      ];
      var pick = cands.first;
      for (final (ox, oy) in cands) {
        final cs2 = [for (final (x, y) in shape) (ox + x, oy + y)];
        if (board.check(me, cs2) == null) {
          pick = (ox, oy);
          ghostOk = true;
          break;
        }
      }
      ghost = [for (final (x, y) in shape) (pick.$1 + x, pick.$2 + y)];
    }

    void place() {
      if (!ghostOk || ghost.isEmpty) return;
      final shape = blokusPieces[piece].orients[orient];
      var mx = 1 << 20, my = 1 << 20;
      for (final (x, y) in ghost) {
        mx = min(mx, x);
        my = min(my, y);
      }
      // shape is normalised so its min is (0,0)
      assert(shape.isNotEmpty);
      g.act({'type': 'place', 'piece': piece, 'orient': orient, 'x': mx, 'y': my});
      setState(() {
        piece = -1;
        hoverCell = -1;
      });
    }

    final myColor = isPlayer ? me : -1;
    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final m = side * 0.02;
      final cell = (side - 2 * m) / n;
      int at(Offset o) {
        final x = ((o.dx - m) / cell).floor(), y = ((o.dy - m) / cell).floor();
        if (x < 0 || y < 0 || x >= n || y >= n) return -1;
        return y * n + x;
      }

      return Listener(
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton && piece >= 0) _rotate();
        },
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && piece >= 0 && myTurn) {
            setState(() => rot = (rot + (e.scrollDelta.dy > 0 ? 1 : 3)) % 4);
          }
        },
        child: MouseRegion(
          onHover: (e) {
            final p = at(e.localPosition);
            if (p != hoverCell) setState(() => hoverCell = p);
          },
          onExit: (_) => setState(() => hoverCell = -1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (!myTurn || piece < 0) return;
              final p = at(d.localPosition);
              if (p < 0) return;
              if (p == hoverCell && ghostOk) {
                place();
              } else {
                setState(() => hoverCell = p); // touch: first tap previews
              }
            },
            child: CustomPaint(
              size: Size(side, side),
              painter: _BoardPainter(n, players, cells, lastCells, myTurn ? anchors : const {}, ghost, ghostOk, myColor,
                  n == 14 ? board.startCells(0) : const [], g.table),
            ),
          ),
        ),
      );
    });

    // tray
    Widget? tray;
    if (isPlayer) {
      final col = blokusColor(me, players);
      tray = A2Panel(
        highlight: myTurn,
        padding: const EdgeInsets.all(4),
        child: Column(children: [
          SizedBox(
            height: 32,
            child: Row(children: [
              IconButton(
                  tooltip: '旋转（右键/滚轮）',
                  visualDensity: VisualDensity.compact,
                  onPressed: piece >= 0 ? _rotate : null,
                  icon: const Icon(Icons.rotate_right, size: 20)),
              IconButton(
                  tooltip: '翻转',
                  visualDensity: VisualDensity.compact,
                  onPressed: piece >= 0 ? _flip : null,
                  icon: const Icon(Icons.flip, size: 20)),
              if (piece >= 0)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CustomPaint(painter: _PieceIcon(blokusPieces[piece].orients[blokusPieces[piece].orientOf(rot, flip)], col)),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('剩 ${remaining[me]} 格 · ${scores[me]} 分',
                      style: TextStyle(fontSize: 12, color: cs.onSurface, fontWeight: FontWeight.w600)),
                ),
              ),
              if (myTurn)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () async {
                    if (await a2Confirm(context, '停止放置', '确定不再放置任何棋子吗？剩余方格都会扣分。')) g.act({'type': 'pass'});
                  },
                  child: const Text('停止'),
                ),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final avail = [for (var p = 20; p >= 0; p--) if (!used[me][p]) p];
              if (avail.isEmpty) return const Center(child: Text('全部放完！'));
              var best = 8.0;
              for (var cols = 1; cols <= avail.length; cols++) {
                final rows = (avail.length / cols).ceil();
                final t = min(c.maxWidth / cols, c.maxHeight / rows);
                if (t > best) best = t;
              }
              final t = best.floorToDouble().clamp(8.0, 72.0);
              return SingleChildScrollView(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final p in avail)
                      GestureDetector(
                        onTap: myTurn
                            ? () => setState(() {
                                  if (piece == p) {
                                    _rotate();
                                  } else {
                                    piece = p;
                                    rot = 0;
                                    flip = false;
                                  }
                                })
                            : null,
                        child: Container(
                          width: t,
                          height: t,
                          padding: EdgeInsets.all(t * 0.08),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(t * 0.15),
                            color: piece == p ? cs.primary.withValues(alpha: 0.25) : null,
                            border: piece == p ? Border.all(color: cs.primary, width: 2) : null,
                          ),
                          child: CustomPaint(
                            painter: _PieceIcon(
                              blokusPieces[p].orients[piece == p ? blokusPieces[p].orientOf(rot, flip) : 0],
                              col,
                              opacity: !myTurn || _playable.contains(p) ? 1 : 0.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ]),
      );
    }

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      status = piece < 0
          ? '轮到你（${blokusColorName(me, players)}）：从托盘选一块棋子'
          : (ghostOk ? '点击放下 · 右键/滚轮旋转' : '移动到小圆点附近：须与同色角对角、不能边相邻');
      if (!board.started[me]) status = piece < 0 ? '轮到你：选一块棋子，覆盖你的起始点' : '第一块必须覆盖起始点';
    } else {
      status = '等待 ${g.name(turn)}（${blokusColorName(turn, players)}）';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        size: players > 2 ? 30 : 36,
        sub: '${resigned[s] ? '认输' : (done[s] && !over ? '已停' : '剩${remaining[s]}格')} · ${scores[s]}分',
        trailing: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: blokusColor(s, players), borderRadius: BorderRadius.circular(3))));

    String? banner;
    if (over) {
      if (v['draw'] == true) {
        banner = '和棋';
      } else {
        final best = [for (var s = 0; s < players; s++) if (!resigned[s]) scores[s]].fold<int>(-1 << 30, max);
        final winners = [for (var s = 0; s < players; s++) if (!resigned[s] && scores[s] == best) s];
        banner = winners.contains(me) ? (winners.length > 1 ? '并列第一！' : '你赢了！') : '${winners.map(g.name).join('、')} 获胜';
      }
    }

    return A2Shell(
      tags: [for (final s in g.seatsFromMe()) tagFor(s)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      tray: tray,
      trayFraction: 0.3,
      info: [
        if (note.isNotEmpty) '上一步：$note',
        '小圆点=可落角位置 · 同色只能角对角 · 剩一格扣一分，全放完+15（最后放单格再+5）',
      ],
      result: banner,
      resultSub: over ? [for (var s = 0; s < players; s++) '${g.name(s)} ${scores[s]}'].join('  ') : null,
    );
  }
}
