import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'arcade_common.dart';

const _numColors = [
  Colors.transparent, Color(0xFF1976D2), Color(0xFF388E3C), Color(0xFFD32F2F), Color(0xFF512DA8),
  Color(0xFF8D6E63), Color(0xFF00838F), Color(0xFF212121), Color(0xFF757575),
];

class MinesweeperBoard extends StatefulWidget {
  final GameContext g;
  const MinesweeperBoard(this.g, {super.key});
  @override
  State<MinesweeperBoard> createState() => _MinesweeperBoardState();
}

class _MinesweeperBoardState extends State<MinesweeperBoard> {
  bool _flagMode = false;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final w = aInt(v['w'], 9), h = aInt(v['h'], 9);
    final board = aStr(v['board']);
    final ps = aMaps(v['ps']);
    final phase = aStr(v['phase']);
    final sec = aInt(v['sec'], 0);
    final me = g.seat >= 0 && g.seat < ps.length ? ps[g.seat] : null;
    final canPlay = phase != 'over' && me != null && me['out'] != true && me['done'] != true && board.length == w * h;
    final flags = board.split('').where((c) => c == 'F').length;
    final lastHit = aInts(v['lastHit']);
    final hitCells = lastHit.length > 1 ? lastHit.sublist(1).toSet() : <int>{};

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (me == null) {
      status = '观战中 · 各玩家进度见上方';
    } else if (me['out'] == true) {
      status = '你踩雷出局了，等待其他玩家…';
    } else {
      status = _flagMode ? '插旗模式：点格子插/拔旗' : '点击翻开 · 长按/右键插旗 · 点数字快速翻开';
    }

    void tap(int i) {
      if (!canPlay) return;
      final c = board[i];
      final x = i % w, y = i ~/ w;
      if (c == '.' || c == 'F') {
        if (_flagMode || c == 'F') {
          g.act({'type': 'flag', 'x': x, 'y': y});
        } else {
          g.act({'type': 'reveal', 'x': x, 'y': y});
        }
      } else if ('12345678'.contains(c)) {
        g.act({'type': 'chord', 'x': x, 'y': y});
      }
    }

    void flag(int i) {
      if (!canPlay) return;
      final c = board[i];
      if (c == '.' || c == 'F') g.act({'type': 'flag', 'x': i % w, 'y': i ~/ w});
    }

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.2;
      final tileW = wide ? 150.0 : math.min(150.0, (box.maxWidth - 24) / (ps.length <= 4 ? ps.length : 3));
      final progress = Wrap(
        direction: wide ? Axis.vertical : Axis.horizontal,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in g.seatsFromMe())
            if (s < ps.length)
              ProgressTile(g, s,
                  width: tileW,
                  pct: aInt(ps[s]['pct'], 0) / 100,
                  out: ps[s]['out'] == true,
                  done: ps[s]['done'] == true,
                  sub: '${ps[s]['pct']}%${aInt(ps[s]['pen'], 0) > 0 ? ' · 罚 ${ps[s]['pen']}s' : ''}${ps[s]['time'] != null ? ' · ${ps[s]['time']}s' : ''}'),
        ],
      );
      final infoBar = Row(mainAxisSize: MainAxisSize.min, children: [
        AChip('💣 ${aInt(v['mines'], 0) - flags}', Colors.black87, size: 13),
        const SizedBox(width: 8),
        AChip('⏱ ${mmss(sec)} / ${mmss(aInt(v['max'], 0))}', cs.primary, size: 13),
        if (v['penalty'] == true && me != null && aInt(me['pen'], 0) > 0) ...[
          const SizedBox(width: 8),
          AChip('罚时 +${me['pen']}s', Colors.redAccent, size: 13),
        ],
        if (me != null) ...[
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('🚩 插旗'),
            selected: _flagMode,
            onSelected: canPlay ? (b) => setState(() => _flagMode = b) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ]);
      final sideW = wide ? 170.0 : 0.0;
      final perRow = math.max(1, ((box.maxWidth - 12) / (tileW + 6)).floor());
      final topH = wide ? 0.0 : math.min(box.maxHeight * 0.25, ((ps.length + perRow - 1) ~/ perRow) * 78.0);
      final availW = box.maxWidth - sideW - 16;
      final availH = box.maxHeight - 40 - 44 - topH - 8;
      final cell = math.max(8.0, math.min(availW / w, availH / h));
      final grid = SizedBox(
        width: cell * w,
        height: cell * h,
        child: board.length != w * h
            ? Center(child: Text('观战中', style: TextStyle(color: cs.onSurface)))
            : _Grid(w: w, h: h, board: board, cell: cell, hits: hitCells, onTap: tap, onFlag: flag),
      );
      final body = wide
          ? Row(children: [
              SizedBox(width: sideW, child: SingleChildScrollView(padding: const EdgeInsets.all(6), child: progress)),
              Expanded(child: Center(child: grid)),
            ])
          : Column(children: [
              SizedBox(height: topH, child: SingleChildScrollView(child: Center(child: progress))),
              Expanded(child: Center(child: grid)),
            ]);
      return Column(children: [
        SizedBox(height: 40, child: aStatus(status, highlight: canPlay)),
        SizedBox(height: 40, child: FittedBox(fit: BoxFit.scaleDown, child: infoBar)),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: body),
            if (phase == 'over')
              Positioned.fill(
                child: aRanking(g, aMaps(v['final']),
                    (r) => r['done'] == true ? '完成 · ${r['time']}s' : '${r['pct']}%${r['out'] == true ? ' · 踩雷' : ''}',
                    alignment: Alignment.bottomCenter),
              ),
          ]),
        ),
      ]);
    });
  }
}

class _Grid extends StatelessWidget {
  final int w, h;
  final String board;
  final double cell;
  final Set<int> hits;
  final void Function(int) onTap, onFlag;
  const _Grid({required this.w, required this.h, required this.board, required this.cell, required this.hits, required this.onTap, required this.onFlag});

  int? _at(Offset p) {
    final x = (p.dx / cell).floor(), y = (p.dy / cell).floor();
    if (x < 0 || y < 0 || x >= w || y >= h) return null;
    return y * w + x;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapUp: (d) {
          final i = _at(d.localPosition);
          if (i != null) onTap(i);
        },
        onLongPressStart: (d) {
          final i = _at(d.localPosition);
          if (i != null) onFlag(i);
        },
        onSecondaryTapUp: (d) {
          final i = _at(d.localPosition);
          if (i != null) onFlag(i);
        },
        child: CustomPaint(painter: _MinePainter(w, h, board, hits)),
      );
}

class _MinePainter extends CustomPainter {
  final int w, h;
  final String board;
  final Set<int> hits;
  _MinePainter(this.w, this.h, this.board, this.hits);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / w;
    canvas.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).inflate(3), const Radius.circular(6)), Paint()..color = const Color(0xFF546E7A));
    final hidden = Paint()..color = const Color(0xFFB0BEC5);
    final hiLite = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.25);
    final open = Paint()..color = const Color(0xFFECEFF1);
    final line = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 0.6;
    for (var i = 0; i < w * h; i++) {
      final ch = board[i];
      final r = Rect.fromLTWH((i % w) * c, (i ~/ w) * c, c, c);
      if (ch == '.' || ch == 'F' || ch == 'x' || ch == '*') {
        canvas.drawRect(r, hidden);
        final b = c * 0.1;
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, c, b), hiLite);
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, b, c), hiLite);
        canvas.drawRect(Rect.fromLTWH(r.left, r.bottom - b, c, b), shade);
        canvas.drawRect(Rect.fromLTWH(r.right - b, r.top, b, c), shade);
        if (ch == 'F' || ch == 'x') _flag(canvas, r, wrong: ch == 'x');
        if (ch == '*') _mine(canvas, r);
      } else {
        canvas.drawRect(r, ch == 'X' ? (Paint()..color = hits.contains(i) ? Colors.red : Colors.red.shade300) : open);
        canvas.drawRect(r, line..style = PaintingStyle.stroke);
        line.style = PaintingStyle.fill;
        if (ch == 'X') {
          _mine(canvas, r);
        } else {
          final n = int.tryParse(ch) ?? 0;
          if (n > 0) _text(canvas, r, '$n', _numColors[n]);
        }
      }
    }
  }

  void _text(Canvas canvas, Rect r, String s, Color col) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: col, fontSize: r.width * 0.66, fontWeight: FontWeight.w900, fontFamily: kFontFallback.first, fontFamilyFallback: kFontFallback)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _mine(Canvas canvas, Rect r) {
    final p = Paint()..color = Colors.black87;
    canvas.drawCircle(r.center, r.width * 0.26, p);
    final s = Paint()
      ..color = Colors.black87
      ..strokeWidth = r.width * 0.08;
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a)) * r.width * 0.36;
      canvas.drawLine(r.center - d, r.center + d, s);
    }
    canvas.drawCircle(r.center - Offset(r.width * 0.08, r.width * 0.08), r.width * 0.07, Paint()..color = Colors.white);
  }

  void _flag(Canvas canvas, Rect r, {bool wrong = false}) {
    final pole = Paint()
      ..color = Colors.black87
      ..strokeWidth = math.max(1, r.width * 0.07);
    final x = r.left + r.width * 0.55;
    canvas.drawLine(Offset(x, r.top + r.height * 0.2), Offset(x, r.bottom - r.height * 0.22), pole);
    canvas.drawRect(Rect.fromLTWH(r.left + r.width * 0.3, r.bottom - r.height * 0.26, r.width * 0.45, r.height * 0.07), pole);
    final path = Path()
      ..moveTo(x, r.top + r.height * 0.18)
      ..lineTo(r.left + r.width * 0.22, r.top + r.height * 0.36)
      ..lineTo(x, r.top + r.height * 0.52)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE53935));
    if (wrong) {
      final x2 = Paint()
        ..color = Colors.black
        ..strokeWidth = r.width * 0.1;
      canvas.drawLine(r.topLeft + Offset(r.width * 0.2, r.width * 0.2), r.bottomRight - Offset(r.width * 0.2, r.width * 0.2), x2);
      canvas.drawLine(r.topRight + Offset(-r.width * 0.2, r.width * 0.2), r.bottomLeft + Offset(r.width * 0.2, -r.width * 0.2), x2);
    }
  }

  @override
  bool shouldRepaint(_MinePainter o) => o.board != board || o.w != w || o.hits.length != hits.length;
}
