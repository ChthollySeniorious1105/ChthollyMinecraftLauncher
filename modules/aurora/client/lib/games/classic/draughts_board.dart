import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _lightPiece = Color(0xFFF3E6CC);
const _darkPiece = Color(0xFF7A1F1F);

class _DraughtsPainter extends CustomPainter {
  final int n;
  final List<int> board;
  final bool flip;
  final List<int> lastPath;
  final Set<int> lastCaps;
  final Set<int> movable;
  final List<int> selected;
  final Set<int> targets;

  _DraughtsPainter({
    required this.n,
    required this.board,
    required this.flip,
    required this.lastPath,
    required this.lastCaps,
    required this.movable,
    required this.selected,
    required this.targets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / n;
    Rect sq(int p) {
      var r = p ~/ n, c = p % n;
      if (flip) {
        r = n - 1 - r;
        c = n - 1 - c;
      }
      return Rect.fromLTWH(c * cell, r * cell, cell, cell);
    }

    for (var p = 0; p < n * n; p++) {
      final dark = (p ~/ n + p % n).isOdd;
      canvas.drawRect(sq(p), Paint()..color = dark ? const Color(0xFF8B5A2B) : const Color(0xFFF0D9B5));
    }
    // last move trail
    if (lastPath.length >= 2) {
      for (final p in lastPath) {
        canvas.drawRect(sq(p), Paint()..color = const Color(0x66FFD54F));
      }
      final trail = Paint()
        ..color = const Color(0xAAFFB300)
        ..strokeWidth = max(2, cell * 0.08)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i + 1 < lastPath.length; i++) {
        canvas.drawLine(sq(lastPath[i]).center, sq(lastPath[i + 1]).center, trail);
      }
    }
    for (final p in lastCaps) {
      final c = sq(p).center;
      final h = cell * 0.18;
      final x = Paint()
        ..color = const Color(0xCCD32F2F)
        ..strokeWidth = max(2, cell * 0.07)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + Offset(-h, -h), c + Offset(h, h), x);
      canvas.drawLine(c + Offset(-h, h), c + Offset(h, -h), x);
    }
    for (final p in movable) {
      canvas.drawRect(
          sq(p).deflate(cell * 0.04),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, cell * 0.05)
            ..color = const Color(0xAA66BB6A));
    }
    // selected path
    if (selected.isNotEmpty) {
      final sel = Paint()
        ..color = const Color(0xCC42A5F5)
        ..strokeWidth = max(2, cell * 0.09)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i + 1 < selected.length; i++) {
        canvas.drawLine(sq(selected[i]).center, sq(selected[i + 1]).center, sel);
      }
      canvas.drawRect(
          sq(selected.first).deflate(cell * 0.03),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2, cell * 0.08)
            ..color = const Color(0xFF42A5F5));
    }
    final r = cell * 0.4;
    for (var p = 0; p < n * n; p++) {
      final v = board[p];
      if (v == 0) continue;
      final c = sq(p).center;
      final base = v > 0 ? _lightPiece : _darkPiece;
      paintStone(canvas, c, r, base);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, cell * 0.035)
        ..color = Colors.black.withValues(alpha: 0.25);
      canvas.drawCircle(c, r * 0.72, ring);
      canvas.drawCircle(c, r * 0.45, ring);
      if (v.abs() == 2) {
        final tp = classicText('♛', r * 1.05, v > 0 ? const Color(0xFFB8860B) : const Color(0xFFFFD54F),
            weight: FontWeight.bold);
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
    if (selected.length > 1) {
      final last = sq(selected.last).center;
      paintStone(canvas, last, r, board[selected.first] > 0 ? _lightPiece : _darkPiece, opacity: 0.5, shadow: false);
    }
    for (final p in targets) {
      canvas.drawCircle(sq(p).center, cell * 0.16, Paint()..color = const Color(0xCC42A5F5));
    }
  }

  @override
  bool shouldRepaint(covariant _DraughtsPainter o) => true;
}

class DraughtsBoardView extends StatefulWidget {
  final GameContext g;
  const DraughtsBoardView(this.g, {super.key});
  @override
  State<DraughtsBoardView> createState() => _DraughtsBoardViewState();
}

class _DraughtsBoardViewState extends State<DraughtsBoardView> {
  List<int> sel = [];
  int _ply = -1;
  GameContext get g => widget.g;

  static bool _prefix(List<int> path, List<int> pre) {
    if (path.length < pre.length) return false;
    for (var i = 0; i < pre.length; i++) {
      if (path[i] != pre[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final intl = v['variant'] == 'intl';
    final board = (v['board'] as List).cast<int>();
    final firstSeat = v['firstSeat'] as int;
    final turn = v['turn'] as int;
    final ply = v['ply'] as int;
    final lastPath = (v['lastPath'] as List).cast<int>();
    final lastCaps = (v['lastCaps'] as List).cast<int>().toSet();
    final moves = [for (final m in v['moves'] as List) (m as List).cast<int>()];
    final mustCapture = v['mustCapture'] as bool;
    final counts = (v['counts'] as List).cast<int>();
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final over = v['over'] as bool;
    final log = (v['log'] as List).cast<String>();
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myTurn = !over && turn == me;
    if (ply != _ply) {
      _ply = ply;
      sel = [];
    }
    final flip = player && me != firstSeat;
    String colorName(int s) => s == firstSeat ? '白' : '黑';

    final valid = sel.isEmpty ? <List<int>>[] : [for (final m in moves) if (_prefix(m, sel)) m];
    final targets = {for (final m in valid) if (m.length > sel.length) m[sel.length]};
    final movable = myTurn && sel.isEmpty ? {for (final m in moves) m.first} : <int>{};

    void tap(int p) {
      if (!myTurn) return;
      if (targets.contains(p)) {
        final next = [...sel, p];
        final cont = [for (final m in moves) if (_prefix(m, next)) m];
        final exact = cont.where((m) => m.length == next.length).toList();
        if (exact.isNotEmpty && cont.length == 1) {
          setState(() => sel = []);
          g.act({'type': 'move', 'path': next});
        } else if (exact.isNotEmpty && cont.every((m) => m.length == next.length)) {
          setState(() => sel = []);
          g.act({'type': 'move', 'path': next});
        } else {
          setState(() => sel = next);
        }
        return;
      }
      if (moves.any((m) => m.first == p)) {
        setState(() => sel = sel.length == 1 && sel.first == p ? [] : [p]);
      } else {
        setState(() => sel = []);
      }
    }

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      status = sel.length > 1
          ? '继续选择下一跳落点'
          : mustCapture
              ? (intl ? '必须吃子（须吃最多），选择棋子' : '必须吃子，选择棋子')
              : '轮到你（${colorName(me)}），选择棋子再点落点';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: '${colorName(s)} · ${counts[s == firstSeat ? 0 : 1]} 子',
        trailing: StoneDot(s == firstSeat ? _lightPiece : _darkPiece));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / n;
      int at(Offset o) {
        var col = (o.dx / cell).floor(), row = (o.dy / cell).floor();
        if (col < 0 || row < 0 || col >= n || row >= n) return -1;
        if (flip) {
          col = n - 1 - col;
          row = n - 1 - row;
        }
        return row * n + col;
      }

      return Container(
        decoration: BoxDecoration(
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
          border: Border.all(color: const Color(0xFF4E2E12), width: 3),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final p = at(d.localPosition);
            if (p >= 0) tap(p);
          },
          child: CustomPaint(
            size: Size(side, side),
            painter: _DraughtsPainter(
              n: n,
              board: board,
              flip: flip,
              lastPath: lastPath,
              lastCaps: lastCaps,
              movable: movable,
              selected: sel,
              targets: myTurn ? targets : const {},
            ),
          ),
        ),
      );
    });

    final actions = <Widget>[];
    if (player && !over) {
      final offer = v['drawOffer'] as int;
      if (offer == 1 - me) {
        actions.add(classicButton(context, '同意和棋', Icons.handshake, () => g.act({'type': 'acceptDraw'}), primary: true));
        actions.add(classicButton(context, '拒绝', Icons.close, () => g.act({'type': 'declineDraw'})));
      } else {
        actions.add(classicButton(context, offer == me ? '已提和' : '提和', Icons.handshake_outlined,
            offer == me ? null : () => g.act({'type': 'offerDraw'})));
      }
      if (sel.isNotEmpty) actions.add(classicButton(context, '重选', Icons.undo, () => setState(() => sel = [])));
      final rb = resignButton(context, g);
      if (rb != null) actions.add(rb);
    }

    String? banner;
    if (over) {
      banner = winner == 2 ? '和棋' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜');
    }
    final bottom = player ? me : firstSeat;
    return ClassicShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      actions: actions,
      info: InfoPanel([
        '${intl ? '国际 10×10' : '英式 8×8'} · 第 $ply 步 / 上限 300',
        if (log.isNotEmpty) '着法：${log.reversed.take(12).toList().reversed.join('  ')}',
      ]),
      result: banner,
    );
  }
}
