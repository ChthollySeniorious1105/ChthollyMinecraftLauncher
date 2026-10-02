import 'dart:math' as math;

import 'package:aurora_shared/games/military/animalchess.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _sideColors = [Color(0xFFD32F2F), Color(0xFF1565C0)];
const _emoji = {8: '🐘', 7: '🦁', 6: '🐯', 5: '🐆', 4: '🐺', 3: '🐶', 2: '🐱', 1: '🐭'};

class AnimalChessBoard extends StatefulWidget {
  final GameContext g;
  const AnimalChessBoard(this.g, {super.key});
  @override
  State<AnimalChessBoard> createState() => _AnimalChessBoardState();
}

class _AnimalChessBoardState extends State<AnimalChessBoard> {
  int sel = -1;
  GameContext get g => widget.g;

  @override
  void didUpdateWidget(covariant AnimalChessBoard old) {
    super.didUpdateWidget(old);
    if (!(g.view['moves'] as Map).containsKey('$sel')) sel = -1;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cells = (v['cells'] as List).cast<int>();
    final turn = v['turn'] as int;
    final winner = v['winner'] as int;
    final moves = (v['moves'] as Map).map((k, e) => MapEntry(int.parse(k as String), (e as List).cast<int>()));
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final me = g.seat;
    final myTurn = !g.over && winner < 0 && turn == me;
    final flipBoard = me == 1;
    final cs = Theme.of(context).colorScheme;

    String status;
    if (winner >= 0) {
      status = v['result'] as String;
    } else {
      status = myTurn ? '轮到你：选择棋子，再点目标格' : '等待 ${g.name(turn)} 走棋';
    }
    final dests = sel >= 0 ? (moves[sel] ?? const <int>[]) : const <int>[];

    void tap(int i) {
      if (!myTurn) return;
      if (sel >= 0 && dests.contains(i)) {
        g.act({'from': sel, 'to': i});
        setState(() => sel = -1);
      } else if (moves.containsKey(i)) {
        setState(() => sel = sel == i ? -1 : i);
      } else {
        setState(() => sel = -1);
      }
    }

    int count(int s) => cells.where((c) => c >= 0 && c ~/ 10 == s).length;

    return Column(children: [
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final s in g.seatsFromMe())
          g.tag(s,
              active: winner < 0 && turn == s,
              sub: '${s == 0 ? "红方" : "蓝方"} · 剩 ${count(s)} 子',
              trailing: Container(
                  width: 12, height: 12, decoration: BoxDecoration(color: _sideColors[s], shape: BoxShape.circle))),
      ]),
      const SizedBox(height: 6),
      StatusBar(status, highlight: myTurn),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '步数 ${v['plies']}/${v['cap']}'
          '${last != null && (last['cap'] as int) >= 0 ? '  · 上一步吃掉了${animalNames[(last['cap'] as int) % 10]}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final cell = math.min(box.maxWidth / 7, box.maxHeight / 9);
          return Center(
            child: Container(
              width: cell * 7,
              height: cell * 9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cell * 0.2),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black38, offset: Offset(2, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var vr = 0; vr < 9; vr++)
                  Row(children: [
                    for (var vc = 0; vc < 7; vc++)
                      _square(
                        flipBoard ? AnimalChess.idx(8 - vr, 6 - vc) : AnimalChess.idx(vr, vc),
                        cells,
                        cell,
                        dests,
                        last,
                        tap,
                        cs,
                      ),
                  ]),
              ]),
            ),
          );
        }),
      ),
      if (winner >= 0) ResultBanner(v['result'] as String),
    ]);
  }

  Widget _square(int i, List<int> cells, double size, List<int> dests, Map<String, dynamic>? last,
      void Function(int) tap, ColorScheme cs) {
    final water = AnimalChess.isWater(i);
    final trapOf = AnimalChess.traps(0).contains(i)
        ? 0
        : AnimalChess.traps(1).contains(i)
            ? 1
            : -1;
    final denOf = AnimalChess.den(0) == i
        ? 0
        : AnimalChess.den(1) == i
            ? 1
            : -1;
    final r = i ~/ 7, c = i % 7;
    Color bg;
    if (water) {
      bg = const Color(0xFF4FA3D9);
    } else if (denOf >= 0) {
      bg = Color.lerp(_sideColors[denOf], Colors.white, 0.55)!;
    } else if (trapOf >= 0) {
      bg = const Color(0xFFBCAAA4);
    } else {
      bg = (r + c).isEven ? const Color(0xFFB7D98B) : const Color(0xFFA5CF79);
    }
    final p = cells[i];
    final isLast = last != null && (last['from'] == i || last['to'] == i);
    final isDest = dests.contains(i);
    final isSel = i == sel;
    Widget? label;
    if (denOf >= 0) {
      label = Text('兽穴', style: TextStyle(fontSize: size * 0.24, color: Colors.black54, fontWeight: FontWeight.bold));
    } else if (trapOf >= 0) {
      label = Icon(Icons.grid_on, size: size * 0.45, color: Colors.black38);
    } else if (water) {
      label = Icon(Icons.waves, size: size * 0.4, color: Colors.white38);
    }
    return GestureDetector(
      onTap: () => tap(i),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
              color: isLast ? Colors.amber : Colors.black12, width: isLast ? 2.5 : 0.5),
        ),
        child: Stack(alignment: Alignment.center, children: [
          ?label,
          if (p >= 0) _piece(p, size, isSel),
          if (isDest)
            Container(
              width: p >= 0 ? size * 0.9 : size * 0.3,
              height: p >= 0 ? size * 0.9 : size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p >= 0 ? null : Colors.greenAccent.withValues(alpha: 0.8),
                border: p >= 0 ? Border.all(color: Colors.redAccent, width: 3) : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _piece(int p, double size, bool selected) {
    final owner = p ~/ 10, rank = p % 10;
    final color = _sideColors[owner];
    final d = size * 0.84;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: d,
      height: d,
      transform: Matrix4.translationValues(0, selected ? -size * 0.08 : 0, 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Colors.white, Color.lerp(color, Colors.white, 0.7)!], radius: 0.9),
        border: Border.all(color: selected ? Colors.amber : color, width: selected ? 3.5 : 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: selected ? 8 : 3, offset: const Offset(1, 2))],
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_emoji[rank]!, style: const TextStyle(fontSize: 20, height: 1.1)),
            Text('${animalNames[rank]}$rank',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color, height: 1.0)),
          ]),
        ),
      ),
    );
  }
}
