import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';
import 'arcade_common.dart';

Color _tileColor(int v) => switch (v) {
      -2 => const Color(0xFF6D6D6D),
      2 => const Color(0xFFEEE4DA),
      4 => const Color(0xFFEDE0C8),
      8 => const Color(0xFFF2B179),
      16 => const Color(0xFFF59563),
      32 => const Color(0xFFF67C5F),
      64 => const Color(0xFFF65E3B),
      128 => const Color(0xFFEDCF72),
      256 => const Color(0xFFEDCC61),
      512 => const Color(0xFFEDC850),
      1024 => const Color(0xFFEDC53F),
      2048 => const Color(0xFFEDC22E),
      _ => v > 2048 ? const Color(0xFF3C3A32) : const Color(0x33EEE4DA),
    };

class Battle2048Board extends StatefulWidget {
  final GameContext g;
  const Battle2048Board(this.g, {super.key});
  @override
  State<Battle2048Board> createState() => _Battle2048BoardState();
}

class _Battle2048BoardState extends State<Battle2048Board> {
  GameContext get g => widget.g;
  Offset _drag = Offset.zero;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _canPlay {
    final ps = aMaps(g.view['ps']);
    return !g.over && g.seat >= 0 && g.seat < ps.length && ps[g.seat]['stuck'] != true;
  }

  void _move(String d) {
    if (!_canPlay) return;
    final now = DateTime.now();
    if (now.difference(_lastSend).inMilliseconds < 70) return; // stay under the rate limit
    _lastSend = now;
    g.act({'type': 'move', 'dir': d});
  }

  bool _onKey(LogicalKeyboardKey k, bool repeat) {
    final d = {
      LogicalKeyboardKey.arrowUp: 'up',
      LogicalKeyboardKey.keyW: 'up',
      LogicalKeyboardKey.arrowDown: 'down',
      LogicalKeyboardKey.keyS: 'down',
      LogicalKeyboardKey.arrowLeft: 'left',
      LogicalKeyboardKey.keyA: 'left',
      LogicalKeyboardKey.arrowRight: 'right',
      LogicalKeyboardKey.keyD: 'right',
    }[k];
    if (d == null) return false;
    if (!repeat) _move(d);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final ps = aMaps(v['ps']);
    final phase = aStr(v['phase']);
    final sec = aInt(v['sec'], 0), max = aInt(v['max'], 0);
    final me = g.seat >= 0 && g.seat < ps.length ? g.seat : -1;
    final focus = me >= 0 ? me : 0;
    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (me < 0) {
      status = '观战中 · 剩余 ${mmss(max - sec)}';
    } else if (ps[me]['stuck'] == true) {
      status = '你已无路可走，最终 ${ps[me]['sc']} 分 · 剩余 ${mmss(max - sec)}';
    } else {
      status = '方向键 / WASD / 滑动 合并方块${v['attack'] == true ? ' · 合成128+给对手扔石块' : ''} · 剩余 ${mmss(max - sec)}';
    }
    final others = [for (final s in g.seatsFromMe()) if (s != focus && s < ps.length) s];

    return ArcadeKeys(
      onKey: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.15;
        final availH = box.maxHeight - 44;
        double big;
        double small;
        if (wide) {
          big = math.min(availH - 50, box.maxWidth * 0.5);
          small = math.min((availH - 20) / math.max(1, others.length) - 36, box.maxWidth * 0.5 - big * 0.3).clamp(60.0, 200.0);
        } else {
          small = math.min((box.maxWidth - 20) / math.max(1, others.length) - 10, availH * 0.2).clamp(50.0, 160.0);
          big = math.min(box.maxWidth - 24, availH - small - 36 - 60);
        }
        big = math.max(big, 100);
        final mine = ps.isEmpty
            ? const SizedBox()
            : GestureDetector(
                onPanStart: (_) => _drag = Offset.zero,
                onPanUpdate: (d) => _drag += d.delta,
                onPanEnd: (_) {
                  if (_drag.distance < 24) return;
                  _move(_drag.dx.abs() > _drag.dy.abs() ? (_drag.dx > 0 ? 'right' : 'left') : (_drag.dy > 0 ? 'down' : 'up'));
                },
                child: _Panel(g, focus, ps[focus], big, large: true),
              );
        final list = Wrap(
          direction: wide ? Axis.vertical : Axis.horizontal,
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in others) _Panel(g, s, ps[s], small, large: false)],
        );
        final body = wide
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                mine,
                const SizedBox(width: 16),
                if (others.isNotEmpty) list,
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (others.isNotEmpty) FittedBox(fit: BoxFit.scaleDown, child: list),
                const SizedBox(height: 8),
                mine,
              ]);
        return Column(children: [
          SizedBox(height: 40, child: aStatus(status, highlight: _canPlay)),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: body))),
              if (phase == 'over')
                Positioned.fill(
                  child: Container(
                    color: Colors.black38,
                    child: aRanking(g, aMaps(v['final']), (r) => '${r['score']} 分 · 最大 ${r['best']}'),
                  ),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _Panel extends StatelessWidget {
  final GameContext g;
  final int seat;
  final Map<String, dynamic> p;
  final double size;
  final bool large;
  const _Panel(this.g, this.seat, this.p, this.size, {required this.large});
  @override
  Widget build(BuildContext context) {
    final stuck = p['stuck'] == true;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: g.tag(seat, size: large ? 30 : 22, active: large && !stuck && seat == g.seat, sub: '${p['sc']} 分 · 最大 ${math.max(aInt(p['best'], 0), 0)}'),
        ),
      ),
      const SizedBox(height: 4),
      Stack(children: [
        _Grid(aInts(p['b']), size, aInt(p['sp'])),
        if (stuck)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(size * 0.04)),
              alignment: Alignment.center,
              child: FittedBox(child: Padding(padding: const EdgeInsets.all(6), child: Text('无路可走', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.1)))),
            ),
          ),
      ]),
    ]);
  }
}

class _Grid extends StatelessWidget {
  final List<int> b;
  final double size;
  final int spawn;
  const _Grid(this.b, this.size, this.spawn);
  @override
  Widget build(BuildContext context) {
    final gap = size * 0.025;
    final cell = (size - gap * 5) / 4;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFBBADA0),
        borderRadius: BorderRadius.circular(size * 0.04),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38, offset: Offset(0, 2))],
      ),
      child: Stack(children: [
        for (var i = 0; i < 16 && i < b.length; i++)
          Positioned(
            left: gap + (i % 4) * (cell + gap),
            top: gap + (i ~/ 4) * (cell + gap),
            child: _Tile(b[i], cell, fresh: i == spawn),
          ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final int v;
  final double s;
  final bool fresh;
  const _Tile(this.v, this.s, {this.fresh = false});
  @override
  Widget build(BuildContext context) {
    final txt = v == -2 ? '🪨' : (v > 0 ? '$v' : '');
    final dark = v == 2 || v == 4;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: _tileColor(v),
        borderRadius: BorderRadius.circular(s * 0.08),
        border: fresh && v != 0 ? Border.all(color: Colors.white, width: math.max(1, s * 0.03)) : null,
        boxShadow: v >= 128 ? [BoxShadow(blurRadius: s * 0.15, color: const Color(0x88EDC22E))] : null,
      ),
      alignment: Alignment.center,
      child: txt.isEmpty
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(s * 0.08),
                child: Text(txt,
                    style: TextStyle(
                      fontSize: s * (v >= 1000 ? 0.34 : 0.44),
                      fontWeight: FontWeight.w900,
                      color: dark ? const Color(0xFF776E65) : Colors.white,
                    )),
              ),
            ),
    );
  }
}
