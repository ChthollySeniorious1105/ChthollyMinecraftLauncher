import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';
import 'arcade_common.dart';

class SudokuBoard extends StatefulWidget {
  final GameContext g;
  const SudokuBoard(this.g, {super.key});
  @override
  State<SudokuBoard> createState() => _SudokuBoardState();
}

class _SudokuBoardState extends State<SudokuBoard> {
  GameContext get g => widget.g;
  int _sel = -1;
  bool _notesMode = false;
  final Map<int, Set<int>> _notes = {}; // client-side pencil marks

  String get _grid {
    final gr = aStr(g.view['g']);
    return gr.length == 81 ? gr : aStr(g.view['puzzle']);
  }

  bool get _canPlay {
    final ps = aMaps(g.view['ps']);
    return !g.over && g.seat >= 0 && g.seat < ps.length && ps[g.seat]['out'] != true && ps[g.seat]['done'] != true;
  }

  void _input(int d) {
    if (!_canPlay || _sel < 0) return;
    final gr = _grid;
    if (gr.length != 81 || gr[_sel] != '0') return;
    if (_notesMode) {
      setState(() {
        final s = _notes.putIfAbsent(_sel, () => <int>{});
        if (!s.remove(d)) s.add(d);
      });
      return;
    }
    g.act({'type': 'fill', 'i': _sel, 'd': d});
  }

  void _erase() {
    if (_sel >= 0) setState(() => _notes.remove(_sel));
  }

  bool _onKey(LogicalKeyboardKey k, bool repeat) {
    final label = k.keyLabel;
    final d = int.tryParse(label.length == 1 ? label : (label.startsWith('Numpad ') ? label.substring(7) : ''));
    if (d != null && d >= 1 && d <= 9) {
      _input(d);
      return true;
    }
    int? move;
    if (k == LogicalKeyboardKey.arrowLeft) move = -1;
    if (k == LogicalKeyboardKey.arrowRight) move = 1;
    if (k == LogicalKeyboardKey.arrowUp) move = -9;
    if (k == LogicalKeyboardKey.arrowDown) move = 9;
    if (move != null) {
      setState(() => _sel = _sel < 0 ? 40 : (_sel + move! + 81) % 81);
      return true;
    }
    if (k == LogicalKeyboardKey.keyN) {
      setState(() => _notesMode = !_notesMode);
      return true;
    }
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      _erase();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final ps = aMaps(v['ps']);
    final phase = aStr(v['phase']);
    final puzzle = aStr(v['puzzle']);
    final sol = aStr(v['sol']);
    final grid = _grid;
    final sec = aInt(v['sec'], 0);
    final empty = math.max(1, aInt(v['empty'], 1));
    final maxMis = aInt(v['maxMis'], 0);
    final me = g.seat >= 0 && g.seat < ps.length ? ps[g.seat] : null;
    final wrong = aInts(v['wrong']);
    // drop notes for cells that got filled
    for (var i = 0; i < 81 && grid.length == 81; i++) {
      if (grid[i] != '0') _notes.remove(i);
    }
    // digit counts for the number pad
    final counts = List.filled(10, 0);
    for (var i = 0; i < grid.length; i++) {
      final d = grid.codeUnitAt(i) - 48;
      if (d >= 0 && d <= 9) counts[d]++;
    }

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (me == null) {
      status = '观战中 · ${mmss(sec)}';
    } else if (me['out'] == true) {
      status = '失误过多，你已出局';
    } else {
      status = '${_notesMode ? '笔记模式 · ' : ''}选格子后填数字 · 失误 ${me['mis']}${maxMis > 0 ? '/$maxMis' : ''} · ${mmss(sec)}';
    }

    return ArcadeKeys(
      onKey: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.1;
        final showPad = me != null && phase != 'over';
        final availH = box.maxHeight - 44 - (wide ? 0 : (showPad ? 118 : 0) + 60);
        final availW = box.maxWidth - (wide ? 170 + (showPad ? 200 : 0) : 0) - 16;
        final size = math.max(120.0, math.min(availH, availW));
        final progress = Wrap(
          direction: wide ? Axis.vertical : Axis.horizontal,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in g.seatsFromMe())
              if (s < ps.length)
                ProgressTile(g, s,
                    width: wide ? 160 : math.min(140.0, (box.maxWidth - 24) / math.min(3, ps.length)),
                    pct: aInt(ps[s]['f'], 0) / empty,
                    out: ps[s]['out'] == true,
                    done: ps[s]['done'] == true,
                    sub: '${ps[s]['f']}/$empty · 失误 ${ps[s]['mis']}${ps[s]['time'] != null ? ' · ${mmss(aInt(ps[s]['time'], 0))}' : ''}'),
          ],
        );
        final board = SizedBox(
          width: size,
          height: size,
          child: GestureDetector(
            onTapUp: (d) {
              final c = size / 9;
              final x = (d.localPosition.dx / c).floor(), y = (d.localPosition.dy / c).floor();
              if (x >= 0 && y >= 0 && x < 9 && y < 9) setState(() => _sel = y * 9 + x);
            },
            child: CustomPaint(
              painter: _SudokuPainter(
                puzzle: puzzle,
                grid: grid,
                sol: sol,
                sel: _sel,
                notes: _notes,
                wrongCell: wrong.length >= 3 && wrong[1] >= 0 && wrong[1] < 81 && grid.length == 81 && grid[wrong[1]] == '0' ? wrong[1] : -1,
                wrongDigit: wrong.length >= 3 ? wrong[2] : 0,
                accent: cs.primary,
              ),
            ),
          ),
        );
        final pad = !showPad
            ? null
            : _NumPad(
                counts: counts,
                notes: _notesMode,
                enabled: _canPlay,
                onDigit: _input,
                onNotes: () => setState(() => _notesMode = !_notesMode),
                onErase: _erase,
                vertical: wide,
              );
        Widget body = wide
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 170, child: SingleChildScrollView(child: progress)),
                board,
                if (pad != null) SizedBox(width: 200, child: Center(child: pad)),
              ])
            : Column(children: [
                SizedBox(height: 60, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: progress))),
                Expanded(child: Center(child: board)),
                if (pad != null) SizedBox(height: 118, child: Center(child: pad)),
              ]);
        return Column(children: [
          SizedBox(height: 40, child: aStatus(status, highlight: _canPlay)),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: body),
              if (phase == 'over')
                Positioned.fill(
                  child: aRanking(g, aMaps(v['final']),
                      (r) => r['done'] == true ? '完成 ${mmss(aInt(r['time'], 0))}' : '${r['filled']}/$empty${r['out'] == true ? ' · 出局' : ''}',
                      alignment: Alignment.bottomCenter),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _NumPad extends StatelessWidget {
  final List<int> counts;
  final bool notes, enabled, vertical;
  final void Function(int) onDigit;
  final VoidCallback onNotes, onErase;
  const _NumPad({required this.counts, required this.notes, required this.enabled, required this.onDigit, required this.onNotes, required this.onErase, required this.vertical});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(int d) {
      final full = counts[d] >= 9;
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: full ? cs.surfaceContainerHighest.withValues(alpha: 0.5) : cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled && !full ? () => onDigit(d) : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$d', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: full ? cs.onSurface.withValues(alpha: 0.3) : cs.onPrimaryContainer)),
                Text('${9 - counts[d]}', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.5))),
              ]),
            ),
          ),
        ),
      );
    }

    final tools = [
      Padding(
        padding: const EdgeInsets.all(3),
        child: FilterChip(label: const Text('✏️ 笔记'), selected: notes, onSelected: enabled ? (_) => onNotes() : null),
      ),
      Padding(
        padding: const EdgeInsets.all(3),
        child: ActionChip(label: const Text('清除笔记'), onPressed: enabled ? onErase : null),
      ),
    ];
    final digits = [for (var d = 1; d <= 9; d++) key(d)];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: vertical
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              for (var r = 0; r < 3; r++) Row(mainAxisSize: MainAxisSize.min, children: digits.sublist(r * 3, r * 3 + 3)),
              const SizedBox(height: 6),
              ...tools,
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: tools),
              Row(mainAxisSize: MainAxisSize.min, children: digits),
            ]),
    );
  }
}

class _SudokuPainter extends CustomPainter {
  final String puzzle, grid, sol;
  final int sel;
  final Map<int, Set<int>> notes;
  final int wrongCell, wrongDigit;
  final Color accent;
  _SudokuPainter({required this.puzzle, required this.grid, required this.sol, required this.sel, required this.notes, required this.wrongCell, required this.wrongDigit, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 9;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFFFFDF7));
    final selDigit = sel >= 0 && grid.length == 81 ? grid[sel] : '0';
    for (var i = 0; i < 81; i++) {
      final r = Rect.fromLTWH((i % 9) * c, (i ~/ 9) * c, c, c);
      if (sel >= 0) {
        final same = i ~/ 9 == sel ~/ 9 || i % 9 == sel % 9 || (i ~/ 27 == sel ~/ 27 && (i % 9) ~/ 3 == (sel % 9) ~/ 3);
        if (same) canvas.drawRect(r, Paint()..color = accent.withValues(alpha: 0.08));
        if (selDigit != '0' && grid.length == 81 && grid[i] == selDigit) canvas.drawRect(r, Paint()..color = accent.withValues(alpha: 0.22));
      }
      if (i == sel) canvas.drawRect(r, Paint()..color = accent.withValues(alpha: 0.35));
      if (i == wrongCell) canvas.drawRect(r, Paint()..color = Colors.red.withValues(alpha: 0.25));
      final given = puzzle.length == 81 && puzzle[i] != '0';
      final ch = grid.length == 81 ? grid[i] : '0';
      if (ch != '0') {
        _text(canvas, r.center, ch, c * 0.62, given ? const Color(0xFF263238) : const Color(0xFF1565C0), given);
      } else if (sol.length == 81) {
        _text(canvas, r.center, sol[i], c * 0.62, const Color(0xFF9E9E9E), false);
      } else if (i == wrongCell) {
        _text(canvas, r.center, '$wrongDigit', c * 0.62, Colors.red, false);
      } else {
        final ns = notes[i];
        if (ns != null) {
          for (final n in ns) {
            final o = Offset(r.left + ((n - 1) % 3 + 0.5) * c / 3, r.top + ((n - 1) ~/ 3 + 0.5) * c / 3);
            _text(canvas, o, '$n', c * 0.24, const Color(0xFF607D8B), false);
          }
        }
      }
    }
    final thin = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 2.2;
    for (var k = 1; k < 9; k++) {
      final p = k % 3 == 0 ? thick : thin;
      canvas.drawLine(Offset(k * c, 0), Offset(k * c, size.height), p);
      canvas.drawLine(Offset(0, k * c), Offset(size.width, k * c), p);
    }
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF37474F));
  }

  void _text(Canvas canvas, Offset center, String s, double fs, Color col, bool bold) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: fs, color: col, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontFamily: kFontFallback.first, fontFamilyFallback: kFontFallback)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SudokuPainter o) => true;
}
