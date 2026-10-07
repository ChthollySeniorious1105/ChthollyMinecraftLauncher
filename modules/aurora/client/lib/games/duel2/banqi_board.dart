import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'd2_common.dart';

// Same piece codes as xiangqi: 1 帅 2 仕 3 相 4 马 5 车 6 炮 7 兵; 99 = face-down.
const _redChars = ['', '帥', '仕', '相', '傌', '俥', '炮', '兵'];
const _blackChars = ['', '將', '士', '象', '馬', '車', '砲', '卒'];
const _hidden = 99;

/// Round wooden piece (adapted from the xiangqi board), or its face-down back.
class BqPiece extends StatelessWidget {
  final int piece;
  final double size;
  final bool selected;
  const BqPiece(this.piece, {super.key, required this.size, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final back = piece == _hidden;
    final red = piece > 0;
    final ink = red ? const Color(0xFFC62828) : const Color(0xFF1B1B1B);
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: selected ? 1.08 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.35),
            radius: 0.95,
            colors: back
                ? const [Color(0xFF9C7A4E), Color(0xFF6E4E2A), Color(0xFF4A3218)]
                : const [Color(0xFFFBE7C2), Color(0xFFE2BB7E), Color(0xFFB88A4A)],
            stops: const [0, 0.7, 1],
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: selected ? 0.55 : 0.4), blurRadius: selected ? 8 : 3, offset: Offset(0, selected ? 4 : 2)),
          ],
          border: Border.all(color: selected ? const Color(0xFF2E7D32) : const Color(0xFF5A3B1A), width: size * (selected ? 0.07 : 0.03)),
        ),
        child: Container(
          margin: EdgeInsets.all(size * 0.09),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: back ? const Color(0xFFD9B77E).withValues(alpha: 0.6) : ink.withValues(alpha: 0.75), width: size * 0.03),
          ),
          alignment: Alignment.center,
          child: back
              ? Icon(Icons.blur_on, size: size * 0.42, color: const Color(0xFFD9B77E).withValues(alpha: 0.7))
              : Text(
                  (red ? _redChars : _blackChars)[piece.abs().clamp(0, 7)],
                  style: TextStyle(fontSize: size * 0.5, height: 1.0, fontWeight: FontWeight.w900, color: ink, fontFamilyFallback: kFontFallback),
                ),
        ),
      ),
    );
  }
}

class BanqiBoard extends StatefulWidget {
  final GameContext g;
  const BanqiBoard(this.g, {super.key});
  @override
  State<BanqiBoard> createState() => _BanqiBoardState();
}

const _rows = 4, _cols = 8, _size = 32;
const _rank = [0, 7, 6, 5, 3, 4, 2, 1];

bool _canTake(int a, int t) {
  final x = a.abs(), y = t.abs();
  if (x == 7) return y == 7 || y == 1;
  if (x == 1) return y != 7;
  return _rank[x] >= _rank[y];
}

/// Legal destinations of the revealed piece on [s] (client-side hint only;
/// the engine validates).
Set<int> _targets(List<int> b, int s) {
  final p = b[s];
  final out = <int>{};
  if (p == 0 || p == _hidden) return out;
  final r = s ~/ _cols, c = s % _cols;
  for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
    final nr = r + dr, nc = c + dc;
    if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols) continue;
    final t = b[nr * _cols + nc];
    if (t == 0) {
      out.add(nr * _cols + nc);
    } else if (p.abs() != 6 && t != _hidden && (t > 0) != (p > 0) && _canTake(p, t)) {
      out.add(nr * _cols + nc);
    }
    if (p.abs() == 6) {
      var rr = r + dr, cc = c + dc, screens = 0;
      while (rr >= 0 && rr < _rows && cc >= 0 && cc < _cols) {
        final t2 = b[rr * _cols + cc];
        if (t2 != 0) {
          if (screens == 1) {
            if (t2 != _hidden && (t2 > 0) != (p > 0)) out.add(rr * _cols + cc);
            break;
          }
          screens++;
        }
        rr += dr;
        cc += dc;
      }
    }
  }
  return out;
}

class _BanqiBoardState extends State<BanqiBoard> {
  int? sel;
  int _plies = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = dInts(v['board']);
    if (board.length != _size) return const SizedBox();
    final plies = dInt(v['plies']);
    if (plies != _plies) {
      _plies = plies;
      sel = null;
    }
    final turn = dInt(v['turn']);
    final color0 = dInt(v['color0']);
    final winner = dInt(v['winner'], -1);
    final reason = '${v['reason'] ?? ''}';
    final me = g.seat;
    final player = me >= 0 && me < 2;
    final myColor = color0 == 0 || !player ? 0 : (me == 0 ? color0 : -color0);
    final myTurn = player && !g.over && turn == me;
    final last = dInts(v['last']);
    final quiet = dInt(v['quiet']);
    final drawLimit = dInt(v['drawLimit']);
    String colorName(int s) {
      if (color0 == 0) return '未定色';
      final c = s == 0 ? color0 : -color0;
      return c > 0 ? '红方' : '黑方';
    }

    String status;
    if (g.over || winner != -1) {
      status = winner == -2 ? '和棋：$reason' : '${g.name(winner)} 获胜（$reason）';
    } else if (myTurn) {
      status = color0 == 0 ? '轮到你：翻开一枚棋子决定颜色' : '轮到你（${colorName(me)}）：翻棋或走棋';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）';
    }

    final targets = sel == null ? <int>{} : _targets(board, sel!);

    void tap(int s) {
      if (!myTurn) return;
      final p = board[s];
      if (sel != null && targets.contains(s)) {
        final from = sel!;
        setState(() => sel = null);
        g.act({'type': 'move', 'from': from, 'to': s});
        return;
      }
      if (p == _hidden) {
        setState(() => sel = null);
        g.act({'type': 'flip', 'sq': s});
        return;
      }
      final mine = p != 0 && myColor != 0 && (p > 0) == (myColor > 0);
      setState(() => sel = mine && sel != s ? s : null);
    }

    final captured = dList<Object?>(v['captured']);
    Widget capturedRow(int c) {
      // pieces of colour c that were captured
      final list = c > 0 ? (captured.isNotEmpty ? dInts(captured[0]) : <int>[]) : (captured.length > 1 ? dInts(captured[1]) : <int>[]);
      list.sort((a, b) => a.abs() - b.abs());
      return Wrap(spacing: 1, runSpacing: 1, children: [for (final p in list) BqPiece(p, size: 16)]);
    }

    Widget tagFor(int s) {
      final c = color0 == 0 ? 0 : (s == 0 ? color0 : -color0);
      return g.tag(s,
          active: !g.over && turn == s,
          sub: colorName(s),
          trailing: c == 0
              ? null
              : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: capturedRow(-c)));
    }

    final pool = dInts(v['hiddenPool']);
    Widget poolWidget() {
      final counts = <int, int>{};
      for (final p in pool) {
        counts[p] = (counts[p] ?? 0) + 1;
      }
      final keys = counts.keys.toList()..sort((a, b) => a != b && a.sign != b.sign ? b.sign - a.sign : a.abs() - b.abs());
      final cs = Theme.of(context).colorScheme;
      return DPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('未翻开 ${pool.length} 枚${drawLimit > 0 ? ' · 无吃翻 $quiet/$drawLimit 步' : ''}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 2, children: [
            for (final k in keys)
              Row(mainAxisSize: MainAxisSize.min, children: [
                BqPiece(k, size: 20),
                Text('×${counts[k]}', style: TextStyle(fontSize: 11, color: cs.onSurface)),
              ]),
          ]),
        ]),
      );
    }

    Widget boardWidget(bool portrait) {
      // portrait: transposed to 4 columns × 8 rows
      final vRows = portrait ? _cols : _rows;
      final vCols = portrait ? _rows : _cols;
      return AspectRatio(
        aspectRatio: vCols / vRows,
        child: LayoutBuilder(builder: (context, c) {
          final cell = c.maxWidth / vCols;
          Offset posOf(int s) {
            final r = s ~/ _cols, col = s % _cols;
            return portrait ? Offset(r * cell, col * cell) : Offset(col * cell, r * cell);
          }

          final pieceSize = cell * 0.86;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF1D29A), Color(0xFFE0B46C), Color(0xFFEBC685)],
              ),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter(vRows, vCols))),
              for (final s in last)
                if (s >= 0 && s < _size)
                  Positioned(
                    left: posOf(s).dx + cell * 0.04,
                    top: posOf(s).dy + cell * 0.04,
                    width: cell * 0.92,
                    height: cell * 0.92,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: board[s] == 0 ? Colors.blue.withValues(alpha: 0.18) : null,
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.8), width: 2),
                        ),
                      ),
                    ),
                  ),
              for (var s = 0; s < _size; s++)
                Positioned(
                  left: posOf(s).dx,
                  top: posOf(s).dy,
                  width: cell,
                  height: cell,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tap(s),
                    child: Center(
                      child: board[s] != 0
                          ? Stack(alignment: Alignment.center, children: [
                              BqPiece(board[s], size: pieceSize, selected: sel == s),
                              if (targets.contains(s))
                                Container(
                                  width: pieceSize,
                                  height: pieceSize,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.red.shade700, width: cell * 0.07)),
                                ),
                            ])
                          : (targets.contains(s)
                              ? Container(
                                  width: cell * 0.26,
                                  height: cell * 0.26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green.shade700.withValues(alpha: 0.75),
                                    border: Border.all(color: Colors.white70, width: 1.5),
                                  ),
                                )
                              : const SizedBox()),
                    ),
                  ),
                ),
            ]),
          );
        }),
      );
    }

    final bottomSeat = player ? me : 0;
    final topSeat = 1 - bottomSeat;
    final result = g.over || winner != -1
        ? (winner == -2 ? '和棋 · $reason' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜'))
        : null;
    final notation = dList<String>(v['notation']);

    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.15;
      final banner = result == null ? null : ResultBanner(result);
      if (landscape) {
        final panelW = (c.maxWidth * 0.32).clamp(210.0, 330.0);
        return Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Center(child: boardWidget(false)))),
          SizedBox(
            width: panelW,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(alignment: Alignment.centerLeft, child: tagFor(topSeat)),
                const SizedBox(height: 8),
                StatusBar(status, highlight: myTurn),
                ?banner,
                const SizedBox(height: 6),
                if (pool.isNotEmpty) poolWidget(),
                const SizedBox(height: 6),
                Expanded(child: _MoveLog(notation)),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: tagFor(bottomSeat)),
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [Flexible(child: tagFor(topSeat))])),
        const SizedBox(height: 4),
        StatusBar(status, highlight: myTurn),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(6), child: Center(child: boardWidget(true)))),
            if (banner != null) Positioned(left: 0, right: 0, top: 0, child: Center(child: banner)),
          ]),
        ),
        if (pool.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SizedBox(width: double.infinity, child: poolWidget())),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [Flexible(child: tagFor(bottomSeat))])),
        SizedBox(height: 30, child: _MoveLog(notation)),
        const SizedBox(height: 4),
      ]);
    });
  }
}

class _GridPainter extends CustomPainter {
  final int rows, cols;
  _GridPainter(this.rows, this.cols);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;
    final line = Paint()
      ..color = const Color(0xFF5B3A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final thick = Paint()
      ..color = const Color(0xFF5B3A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(Rect.fromLTWH(cell * 0.06, cell * 0.06, size.width - cell * 0.12, size.height - cell * 0.12), thick);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(c * cell + cell * 0.1, r * cell + cell * 0.1, cell * 0.8, cell * 0.8), Radius.circular(cell * 0.1)),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.rows != rows || old.cols != cols;
}

class _MoveLog extends StatelessWidget {
  final List<String> moves;
  const _MoveLog(this.moves);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final vertical = c.maxHeight > 60;
      return Container(
        decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
        child: moves.isEmpty
            ? Center(child: Text('暂无着法', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))))
            : ListView.builder(
                scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.all(4),
                itemCount: moves.length,
                itemBuilder: (_, i) {
                  final idx = moves.length - 1 - i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text('${idx + 1}. ${moves[idx]}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: idx == moves.length - 1 ? FontWeight.bold : FontWeight.normal,
                            color: cs.onSurface)),
                  );
                },
              ),
      );
    });
  }
}
