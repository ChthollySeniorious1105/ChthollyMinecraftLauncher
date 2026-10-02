import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

/// 24 个点位在 7×7 网格中的坐标。
const _pos = <(int, int)>[
  (0, 0), (3, 0), (6, 0), (1, 1), (3, 1), (5, 1), (2, 2), (3, 2), (4, 2), //
  (0, 3), (1, 3), (2, 3), (4, 3), (5, 3), (6, 3), //
  (2, 4), (3, 4), (4, 4), (1, 5), (3, 5), (5, 5), (0, 6), (3, 6), (6, 6),
];

const _adj = <List<int>>[
  [1, 9], [0, 2, 4], [1, 14], [4, 10], [1, 3, 5, 7], [4, 13], [7, 11], [4, 6, 8], [7, 12], //
  [0, 10, 21], [3, 9, 11, 18], [6, 10, 15], [8, 13, 17], [5, 12, 14, 20], [2, 13, 23], //
  [11, 16], [15, 17, 19], [12, 16], [10, 19], [16, 18, 20, 22], [13, 19], [9, 22], [19, 21, 23], [14, 22],
];

const _mills = <List<int>>[
  [0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], //
  [0, 9, 21], [3, 10, 18], [6, 11, 15], [1, 4, 7], [16, 19, 22], [8, 12, 17], [5, 13, 20], [2, 14, 23],
];

class _MorrisPainter extends CustomPainter {
  final List<int> board;
  final int sel;
  final Set<int> targets, removable, sources;
  final int lastFrom, lastTo, lastRemoved;

  _MorrisPainter(this.board, this.sel, this.targets, this.removable, this.sources, this.lastFrom, this.lastTo,
      this.lastRemoved);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 7;
    Offset pt(int p) => Offset((_pos[p].$1 + 0.5) * cell, (_pos[p].$2 + 0.5) * cell);
    const ink = Color(0xFF3B2A14);
    final line = Paint()
      ..color = ink
      ..strokeWidth = max(1.5, cell * 0.06)
      ..strokeCap = StrokeCap.round;
    for (var p = 0; p < 24; p++) {
      for (final q in _adj[p]) {
        if (q > p) canvas.drawLine(pt(p), pt(q), line);
      }
    }
    // 形成的三连高亮
    for (final m in _mills) {
      final c = board[m[0]];
      if (c != 0 && board[m[1]] == c && board[m[2]] == c) {
        canvas.drawLine(
            pt(m[0]),
            pt(m[2]),
            Paint()
              ..color = (c == 1 ? const Color(0xFFFFB300) : const Color(0xFF42A5F5)).withValues(alpha: 0.55)
              ..strokeWidth = cell * 0.22
              ..strokeCap = StrokeCap.round);
      }
    }
    final r = cell * 0.34;
    if (lastFrom >= 0 && board[lastFrom] == 0) {
      canvas.drawCircle(
          pt(lastFrom),
          r * 0.7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.2, r * 0.1)
            ..color = const Color(0x9942A5F5));
    }
    if (lastRemoved >= 0 && board[lastRemoved] == 0) {
      final c = pt(lastRemoved), h = r * 0.45;
      final xp = Paint()
        ..color = const Color(0xCCE53935)
        ..strokeWidth = max(1.5, r * 0.14)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + Offset(-h, -h), c + Offset(h, h), xp);
      canvas.drawLine(c + Offset(-h, h), c + Offset(h, -h), xp);
    }
    for (var p = 0; p < 24; p++) {
      final c = pt(p);
      final v = board[p];
      if (v == 0) {
        canvas.drawCircle(c, max(2.5, cell * 0.09), Paint()..color = ink);
        if (targets.contains(p)) {
          canvas.drawCircle(c, r * 0.5, Paint()..color = const Color(0xCC66BB6A));
        }
        continue;
      }
      absStone(canvas, c, r, v == 1 ? kAbsWhite : kAbsBlack);
      canvas.drawCircle(
          c,
          r * 0.62,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, r * 0.08)
            ..color = (v == 1 ? Colors.brown.shade300 : Colors.white24));
      if (p == lastTo) canvas.drawCircle(c, r * 0.2, Paint()..color = const Color(0xFFE53935));
      Color? ring;
      if (p == sel) {
        ring = const Color(0xFFFF7043);
      } else if (removable.contains(p)) {
        ring = const Color(0xFFE53935);
      } else if (sources.contains(p)) {
        ring = const Color(0xFFFFD54F);
      }
      if (ring != null) {
        canvas.drawCircle(
            c,
            r * 1.08,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, r * 0.16)
              ..color = ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MorrisPainter o) => true;
}

class NineMenBoardView extends StatefulWidget {
  final GameContext g;
  const NineMenBoardView(this.g, {super.key});
  @override
  State<NineMenBoardView> createState() => _NineMenBoardViewState();
}

class _NineMenBoardViewState extends State<NineMenBoardView> {
  int sel = -1;
  int _ply = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final inHand = (v['inHand'] as List).cast<int>();
    final onBoard = (v['onBoard'] as List).cast<int>();
    final turn = v['turn'] as int;
    final phase = v['phase'] as String;
    final over = v['over'] as bool;
    final removable = (v['removable'] as List).cast<int>().toSet();
    final moves = [for (final m in v['moves'] as List) (m as List).cast<int>()];
    final ply = v['ply'] as int;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myTurn = !over && turn == me;
    if (ply != _ply) {
      _ply = ply;
      sel = -1;
    }
    final sources = myTurn && (phase == 'move' || phase == 'fly') ? {for (final m in moves) m[0]} : <int>{};
    final targets = <int>{
      if (myTurn && phase == 'place')
        for (var p = 0; p < 24; p++)
          if (board[p] == 0) p,
      if (myTurn && sel >= 0)
        for (final m in moves)
          if (m[0] == sel) m[1],
    };

    void tap(int p) {
      if (!myTurn) return;
      switch (phase) {
        case 'remove':
          if (removable.contains(p)) g.act({'type': 'remove', 'point': p});
        case 'place':
          if (board[p] == 0) g.act({'type': 'place', 'point': p});
        default:
          if (sel >= 0 && targets.contains(p)) {
            g.act({'type': 'move', 'from': sel, 'to': p});
            setState(() => sel = -1);
          } else if (sources.contains(p)) {
            setState(() => sel = sel == p ? -1 : p);
          } else {
            setState(() => sel = -1);
          }
      }
    }

    String colorName(int s) => s == 0 ? '白' : '黑';
    String status;
    if (over) {
      status = v['result'] as String? ?? '对局结束';
    } else if (myTurn) {
      status = switch (phase) {
        'remove' => '形成三连！点击红圈标记的对方棋子将其移除',
        'place' => '放置阶段：点击空位放子（手中还剩 ${inHand[me]} 子）',
        'fly' => sel >= 0 ? '点击任意空位飞子' : '只剩三子，可飞到任意空位：先选一枚棋子',
        _ => sel >= 0 ? '点击绿色标记的相邻空位' : '移动阶段：选择一枚黄圈棋子',
      };
    } else {
      final what = const {'remove': '移除棋子', 'place': '放子', 'fly': '飞子'}[phase] ?? '走子';
      status = '等待 ${g.name(turn)}（${colorName(turn)}）$what';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: '${colorName(s)}${s == v['firstSeat'] ? ' · 先手' : ''} · 手中 ${inHand[s]} · 盘上 ${onBoard[s]}',
        trailing: AbsDot(s == 0 ? kAbsWhite : kAbsBlack));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / 7;
      int hit(Offset o) {
        for (var p = 0; p < 24; p++) {
          final q = Offset((_pos[p].$1 + 0.5) * cell, (_pos[p].$2 + 0.5) * cell);
          if ((q - o).distance < cell * 0.45) return p;
        }
        return -1;
      }

      return Container(
        decoration: absWood(radius: 10),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final p = hit(d.localPosition);
            if (p >= 0) tap(p);
          },
          child: CustomPaint(
            size: Size(side, side),
            painter: _MorrisPainter(
              board,
              sel,
              targets,
              myTurn ? removable : const {},
              sel >= 0 ? const {} : sources,
              v['lastFrom'] as int,
              v['lastTo'] as int,
              v['lastRemoved'] as int,
            ),
          ),
        ),
      );
    });

    final bottom = player ? me : 0;
    return AbsShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      actions: [?absResign(context, g)],
      info: [
        '第 ${v['ply']} 手 / 上限 ${v['plyCap']} 手 · ${v['flying'] == true ? '剩三子可飞' : '不可飞子'}',
        '连成三子可移除对方一子（优先不在三连中的子）；对方只剩两子或无路可走即胜',
      ],
      result: absBanner(g, v),
    );
  }
}
