import 'dart:math';

import 'package:aurora_shared/games/race/battleship.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'race_common.dart';

const _planeColors = [Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFF8E24AA)];

class BattleshipBoard extends StatefulWidget {
  final GameContext g;
  const BattleshipBoard(this.g, {super.key});
  @override
  State<BattleshipBoard> createState() => _BattleshipBoardState();
}

class _BattleshipBoardState extends State<BattleshipBoard> {
  final List<(int, int, int)> draft = [];
  int dir = 0;
  (int, int)? hover;
  bool showMine = false; // during battle on narrow screens: which grid to show
  final _rng = Random();

  List<(int, int, int)> _randomLayout(int count) {
    while (true) {
      final out = <(int, int, int)>[];
      final used = <int>{};
      var tries = 0;
      while (out.length < count && tries++ < 300) {
        final p = PlaneGeo.all[_rng.nextInt(PlaneGeo.all.length)];
        final cs = PlaneGeo.cells(p.$1, p.$2, p.$3);
        if (cs.any((q) => used.contains(q.$1 * 10 + q.$2))) continue;
        used.addAll(cs.map((q) => q.$1 * 10 + q.$2));
        out.add(p);
      }
      if (out.length == count) return out;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final phase = v['phase'] as String;
    final count = v['count'] as int;
    final ready = (v['ready'] as List).cast<bool>();
    final turn = v['turn'] as int;
    final winner = v['winner'] as int;
    final shots = [for (final s in v['shots'] as List) (s as List).cast<int>()];
    final destroyed = (v['destroyed'] as List).cast<int>();
    final last = (v['last'] as List?)?.cast<int>();
    final mine = (v['mine'] as List?)?.map((p) => (p as List).cast<int>()).map((l) => (l[0], l[1], l[2])).toList();
    final allPlanes = (v['planes'] as List?)
        ?.map((ps) => [for (final p in ps as List) (p as List).cast<int>()].map((l) => (l[0], l[1], l[2])).toList())
        .toList();
    final me = g.seat;
    final player = me == 0 || me == 1;
    final opp = player ? 1 - me : 1;
    final myTurn = !g.over && winner < 0 && phase == 'play' && turn == me;
    final cs = Theme.of(context).colorScheme;

    final tags = [
      for (var s = 0; s < 2; s++)
        g.tag(s,
            active: winner < 0 && (phase == 'place' ? !ready[s] : turn == s),
            sub: phase == 'place' ? (ready[s] ? '已布置' : '布置中…') : '击毁 ${destroyed[s]}/$count'),
    ];

    // ---------------- placement ----------------
    if (phase == 'place') {
      if (!player || ready[me]) {
        return RaceScaffold(
          tags: tags,
          status: player ? '已布置完成，等待对手…' : '双方正在布置飞机',
          board: player && mine != null ? _Grid(planes: mine, shots: null, cs: cs) : _Grid(cs: cs),
        );
      }
      final valid = PlaneGeo.validate(draft, count) == null;
      final used = <int>{for (final p in draft) ...PlaneGeo.cells(p.$1, p.$2, p.$3).map((q) => q.$1 * 10 + q.$2)};
      (int, int, int)? ghost;
      var ghostOk = false;
      if (hover != null && draft.length < count) {
        ghost = (hover!.$1, hover!.$2, dir);
        ghostOk = PlaneGeo.inBounds(ghost.$1, ghost.$2, dir) &&
            PlaneGeo.cells(ghost.$1, ghost.$2, dir).every((q) => !used.contains(q.$1 * 10 + q.$2));
      }
      final controls = Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => dir = (dir + 1) % 4),
          icon: Transform.rotate(angle: dir * pi / 2, child: const Icon(Icons.flight)),
          label: const Text('旋转'),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            draft
              ..clear()
              ..addAll(_randomLayout(count));
          }),
          icon: const Icon(Icons.shuffle),
          label: const Text('随机布局'),
        ),
        OutlinedButton.icon(
          onPressed: draft.isEmpty ? null : () => setState(draft.clear),
          icon: const Icon(Icons.delete_outline),
          label: const Text('清空'),
        ),
        FilledButton.icon(
          onPressed: valid ? () => g.act({'t': 'place', 'planes': [for (final p in draft) [p.$1, p.$2, p.$3]]}) : null,
          icon: const Icon(Icons.check),
          label: const Text('确认布置'),
        ),
      ]);
      return RaceScaffold(
        tags: tags,
        status: draft.length < count ? '布置飞机 ${draft.length}/$count：点击格子放置机头，点击已放的飞机可移除' : '布置完成，点击确认',
        highlight: true,
        controls: controls,
        board: _Grid(
          cs: cs,
          planes: draft,
          ghost: ghost,
          ghostOk: ghostOk,
          onHover: (p) => setState(() => hover = p),
          onTap: (r, c) {
            final i = draft.indexWhere((p) => PlaneGeo.cells(p.$1, p.$2, p.$3).contains((r, c)));
            setState(() {
              hover = (r, c);
              if (i >= 0) {
                draft.removeAt(i);
              } else if (draft.length < count &&
                  PlaneGeo.inBounds(r, c, dir) &&
                  PlaneGeo.cells(r, c, dir).every((q) => !used.contains(q.$1 * 10 + q.$2))) {
                draft.add((r, c, dir));
              }
            });
          },
        ),
      );
    }

    // ---------------- battle ----------------
    final status = winner >= 0
        ? '${g.name(winner)} 获胜！'
        : myTurn
            ? '轮到你轰炸：点击对方空域'
            : player
                ? '等待 ${g.name(turn)} 轰炸'
                : '${g.name(turn)} 正在轰炸';
    String lastText = '';
    if (last != null) {
      final cell = last[1];
      lastText = '${g.name(last[0])} 轰炸 ${String.fromCharCode(65 + cell % 10)}${cell ~/ 10 + 1}：${const ['空', '伤', '毁'][last[2]]}';
    }

    // attack grid: my shots on opponent; defence grid: opponent's shots on me
    final attackSeat = player ? me : 0;
    final defendSeat = 1 - attackSeat;
    final attack = _Grid(
      cs: cs,
      title: player ? '对方空域（${g.name(opp)}）' : '${g.name(1)} 的空域',
      shots: shots[attackSeat],
      planes: allPlanes?[1 - attackSeat],
      reveal: allPlanes != null,
      lastCell: last != null && last[0] == attackSeat ? last[1] : null,
      onTap: myTurn ? (r, c) {
        if (shots[me][r * 10 + c] < 0) g.act({'t': 'shoot', 'cell': r * 10 + c});
      } : null,
    );
    final defence = _Grid(
      cs: cs,
      title: player ? '我方空域' : '${g.name(0)} 的空域',
      shots: shots[defendSeat],
      planes: player ? mine : allPlanes?[attackSeat],
      lastCell: last != null && last[0] == defendSeat ? last[1] : null,
    );
    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      if (lastText.isNotEmpty) Text(lastText, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Wrap(spacing: 10, alignment: WrapAlignment.center, children: [
        _legend(Colors.white70, '空', cs),
        _legend(Colors.orange, '伤', cs),
        _legend(Colors.red, '毁（机头）', cs),
      ]),
    ]);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.5;
      Widget boards;
      if (wide) {
        boards = Row(children: [
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1 / 1.08, child: attack))),
          const SizedBox(width: 12),
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1 / 1.08, child: defence))),
        ]);
      } else {
        boards = Column(children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(player ? '对方空域' : g.name(1))),
              ButtonSegment(value: true, label: Text(player ? '我方空域' : g.name(0))),
            ],
            selected: {showMine},
            onSelectionChanged: (s) => setState(() => showMine = s.first),
          ),
          const SizedBox(height: 6),
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1 / 1.08, child: showMine ? defence : attack))),
        ]);
      }
      return Stack(children: [
        Column(children: [
          const SizedBox(height: 4),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: tags),
          const SizedBox(height: 6),
          StatusBar(status, highlight: myTurn),
          const SizedBox(height: 6),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: boards)),
          Padding(padding: const EdgeInsets.all(8), child: controls),
        ]),
        if (winner >= 0)
          Positioned(
            left: 0,
            right: 0,
            top: c.maxHeight * 0.3,
            child: Center(child: DismissibleResult(winner == me ? '你炸毁了对方全部飞机！' : '${g.name(winner)} 获胜！')),
          ),
      ]);
    });
  }

  Widget _legend(Color c, String t, ColorScheme cs) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black26))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

class _Grid extends StatelessWidget {
  final ColorScheme cs;
  final String? title;
  final List<(int, int, int)>? planes;
  final List<int>? shots;
  final bool reveal;
  final (int, int, int)? ghost;
  final bool ghostOk;
  final int? lastCell;
  final void Function(int r, int c)? onTap;
  final void Function((int, int)? p)? onHover;
  const _Grid({
    required this.cs,
    this.title,
    this.planes,
    this.shots,
    this.reveal = false,
    this.ghost,
    this.ghostOk = false,
    this.lastCell,
    this.onTap,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final titleH = title == null ? 0.0 : 22.0;
      final size = min(c.maxWidth, c.maxHeight - titleH);
      final cell = size / 11; // 1 cell margin for labels
      (int, int)? at(Offset p) {
        final col = (p.dx / cell).floor() - 1, row = (p.dy / cell).floor() - 1;
        if (row < 0 || row > 9 || col < 0 || col > 9) return null;
        return (row, col);
      }

      final grid = SizedBox(
        width: size,
        height: size,
        child: MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          onHover: onHover == null ? null : (e) => onHover!(at(e.localPosition)),
          onExit: onHover == null ? null : (_) => onHover!(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTap == null
                ? null
                : (d) {
                    final p = at(d.localPosition);
                    if (p != null) onTap!(p.$1, p.$2);
                  },
            child: CustomPaint(
              painter: _GridPainter(
                cell: cell,
                planes: planes ?? const [],
                shots: shots,
                reveal: reveal,
                ghost: ghost,
                ghostOk: ghostOk,
                lastCell: lastCell,
                cs: cs,
              ),
            ),
          ),
        ),
      );
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          SizedBox(height: titleH, child: Text(title!, style: const TextStyle(fontWeight: FontWeight.bold))),
        grid,
      ]);
    });
  }
}

class _GridPainter extends CustomPainter {
  final double cell;
  final List<(int, int, int)> planes;
  final List<int>? shots;
  final bool reveal;
  final (int, int, int)? ghost;
  final bool ghostOk;
  final int? lastCell;
  final ColorScheme cs;
  _GridPainter({
    required this.cell,
    required this.planes,
    required this.shots,
    required this.reveal,
    required this.ghost,
    required this.ghostOk,
    required this.lastCell,
    required this.cs,
  });

  Rect _r(int r, int c) => Rect.fromLTWH((c + 1) * cell, (r + 1) * cell, cell, cell);

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTWH(cell, cell, cell * 10, cell * 10);
    canvas.drawRRect(RRect.fromRectAndRadius(area.inflate(2), const Radius.circular(6)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4FC3F7), Color(0xFF0277BD)],
          ).createShader(area));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      canvas.drawLine(Offset((i + 1) * cell, cell), Offset((i + 1) * cell, cell * 11), line);
      canvas.drawLine(Offset(cell, (i + 1) * cell), Offset(cell * 11, (i + 1) * cell), line);
    }
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < 10; i++) {
      for (final (label, off) in [
        (String.fromCharCode(65 + i), Offset((i + 1.5) * cell, cell * 0.5)),
        ('${i + 1}', Offset(cell * 0.5, (i + 1.5) * cell)),
      ]) {
        tp.text = TextSpan(text: label, style: TextStyle(fontFamilyFallback: kFontFallback, fontSize: cell * 0.42, color: cs.onSurface, fontWeight: FontWeight.bold));
        tp.layout();
        tp.paint(canvas, off - Offset(tp.width / 2, tp.height / 2));
      }
    }
    for (var k = 0; k < planes.length; k++) {
      final (r, c, d) = planes[k];
      _plane(canvas, r, c, d, _planeColors[k % _planeColors.length].withValues(alpha: reveal ? 0.55 : 0.85));
    }
    if (ghost != null) {
      final (r, c, d) = ghost!;
      _plane(canvas, r, c, d, (ghostOk ? Colors.white : Colors.redAccent).withValues(alpha: 0.5), clip: true);
    }
    final s = shots;
    if (s != null) {
      for (var i = 0; i < 100; i++) {
        final res = s[i];
        if (res < 0) continue;
        final rect = _r(i ~/ 10, i % 10);
        final c = rect.center;
        switch (res) {
          case 0:
            canvas.drawCircle(c, cell * 0.14, Paint()..color = Colors.white70);
          case 1:
            canvas.drawCircle(c, cell * 0.32, Paint()..color = Colors.orange);
            _cross(canvas, c, cell * 0.2, Colors.white);
          default:
            canvas.drawRect(rect.deflate(1), Paint()..color = Colors.red);
            _cross(canvas, c, cell * 0.3, Colors.white);
        }
      }
    }
    if (lastCell != null) {
      canvas.drawRect(_r(lastCell! ~/ 10, lastCell! % 10).deflate(1), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.yellowAccent);
    }
  }

  void _cross(Canvas canvas, Offset c, double r, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = r * 0.35
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), p);
    canvas.drawLine(c + Offset(r, -r), c + Offset(-r, r), p);
  }

  void _plane(Canvas canvas, int r, int c, int d, Color color, {bool clip = false}) {
    final cells = PlaneGeo.cells(r, c, d);
    for (var k = 0; k < cells.length; k++) {
      final (pr, pc) = cells[k];
      if (pr < 0 || pr > 9 || pc < 0 || pc > 9) continue;
      final rect = _r(pr, pc).deflate(cell * 0.06);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * (k == 0 ? 0.45 : 0.15)));
      canvas.drawRRect(rr, Paint()..color = k == 0 ? Color.lerp(color, Colors.black, 0.35)! : color);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => true;
}
