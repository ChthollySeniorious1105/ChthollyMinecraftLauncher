import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'common.dart';

part 'backgammon_painter.dart';

class BackgammonBoardView extends StatefulWidget {
  final GameContext g;
  const BackgammonBoardView(this.g, {super.key});
  @override
  State<BackgammonBoardView> createState() => _BackgammonBoardViewState();
}

class _BackgammonBoardViewState extends State<BackgammonBoardView> {
  int sel = -1; // 选中的起点（绝对点位 0..23，24=中柱）
  String _stamp = '';
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final phase = v['phase'] as String;
    final board = (v['board'] as List).cast<int>();
    final bar = (v['bar'] as List).cast<int>();
    final off = (v['off'] as List).cast<int>();
    final pip = (v['pip'] as List).cast<int>();
    final turn = v['turn'] as int;
    final dice = (v['dice'] as List).cast<int>();
    final rem = (v['rem'] as List).cast<int>();
    final legal = [for (final m in v['legal'] as List) (m as Map).cast<String, dynamic>()];
    final played = [for (final m in v['played'] as List) (m as Map).cast<String, dynamic>()];
    final score = (v['score'] as List).cast<int>();
    final matchTo = v['matchTo'] as int;
    final cube = v['cube'] as int;
    final cubeOwner = v['cubeOwner'] as int;
    final cubeOn = v['cubeOn'] as bool;
    final crawford = v['crawford'] as bool;
    final lastTurn = (v['lastTurn'] as Map?)?.cast<String, dynamic>();
    final lastGame = (v['lastGame'] as Map?)?.cast<String, dynamic>();
    final over = v['over'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final view = player ? me : 0;
    final myTurn = !over && turn == me;
    final canMove = myTurn && phase == 'move';

    final stamp = '${v['gameNo']}-$turn-${rem.length}-${played.length}-$phase';
    if (stamp != _stamp) {
      _stamp = stamp;
      sel = -1;
    }
    final sources = canMove ? {for (final m in legal) m['from'] as int} : <int>{};
    if (canMove && sel == -1 && sources.length == 1) sel = sources.first;
    final targetMoves = canMove && sel >= 0 ? [for (final m in legal) if (m['from'] == sel) m] : const <Map<String, dynamic>>[];
    final targets = {for (final m in targetMoves) m['to'] as int};

    // 高亮：我方本回合已走（或对手上一回合）的落点
    final Set<int> lastTo = {
      if (played.isNotEmpty)
        for (final m in played) m['to'] as int
      else if (lastTurn != null)
        for (final m in (lastTurn['moves'] as List)) (m as Map)['to'] as int,
    };

    void tapPoint(int p) {
      if (!canMove) return;
      if (targets.contains(p)) {
        final cands = targetMoves.where((m) => m['to'] == p).toList()
          ..sort((a, b) => (a['die'] as int).compareTo(b['die'] as int));
        final m = cands.first;
        g.act({'type': 'move', 'from': m['from'], 'to': m['to'], 'die': m['die']});
        setState(() => sel = -1);
        return;
      }
      if (sources.contains(p)) {
        setState(() => sel = sel == p ? -1 : p);
      } else {
        setState(() => sel = -1);
      }
    }

    String colorName(int s) => s == 0 ? '白' : '黑';
    String status;
    if (over) {
      status = v['result'] as String? ?? '比赛结束';
    } else if (phase == 'gameover') {
      final w = lastGame?['winner'] as int? ?? 0;
      status = '${w == me ? '你' : g.name(w)}赢得本局（${lastGame?['how']}，+${lastGame?['points']}），即将开始下一局…';
    } else if (phase == 'double') {
      status = me == 1 - turn ? '${g.name(turn)} 提出加倍至 ${cube * 2}，接受还是放弃？' : '等待 ${g.name(1 - turn)} 回应加倍';
    } else if (myTurn && phase == 'roll') {
      status = '轮到你：掷骰${v['canDouble'] == true ? '或加倍' : ''}';
    } else if (canMove) {
      if (legal.isEmpty) {
        status = played.isEmpty ? '无子可走，请确认' : '走完了，请确认或撤销';
      } else if (bar[me] > 0) {
        status = '中柱有子，必须先进入对方内盘';
      } else {
        status = sel >= 0 ? '点击绿色标记的落点' : '选择一枚发光的棋子';
      }
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）${phase == 'roll' ? '掷骰' : '走子'}';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && (phase == 'double' ? s == 1 - turn : s == turn),
        sub: '${colorName(s)} · $matchTo分制 ${score[s]}分 · 点数 ${pip[s]}',
        trailing: AbsDot(s == 0 ? _whiteChecker : _blackChecker));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final u = c.maxWidth / _bgW;
      final geo = _Geo(u, view == 1);
      final h = u * _bgH;
      void onTap(Offset o) {
        final x = o.dx, y = o.dy;
        if (x >= geo.trayX - u * 0.1) {
          if (targets.contains(25)) tapPoint(25);
          return;
        }
        if (x >= geo.barX && x < geo.barX + u) {
          tapPoint(24);
          return;
        }
        var k = ((x / u) - _fr).floor();
        if (k >= 6) k = ((x / u) - _fr - 1).floor();
        if (k < 0 || k > 11) return;
        final bottom = y > geo.midY;
        tapPoint(geo.idxAt(k, bottom));
      }

      // 骰子位置：当前行动方的半区（右半区=我方行动，左半区=对方）
      final ds = (u * 0.95).clamp(18.0, 64.0);
      final diceRow = dice.isEmpty
          ? const SizedBox()
          : Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (i, d) in _usedFlags(dice, rem).indexed)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: ds * 0.08),
                  child: Opacity(opacity: d.$2 ? 0.35 : 1, child: DieFace(d.$1, size: ds, key: ValueKey('d$i'))),
                ),
            ]);
      final diceOnRight = turn == view;
      final halfLeft = diceOnRight ? geo.barX + u : _fr * u;
      final halfW = 6 * u;
      return SizedBox(
        width: c.maxWidth,
        height: h,
        child: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => onTap(d.localPosition),
            child: CustomPaint(
              size: Size(c.maxWidth, h),
              painter: _BgPainter(
                geo: geo,
                board: board,
                bar: bar,
                off: off,
                me: view,
                sources: sel >= 0 ? const {} : sources,
                selected: sel,
                targets: targets,
                lastTo: lastTo,
                cube: cube,
                cubeOwner: cubeOwner,
                cubeOn: cubeOn,
                felt: Color.lerp(g.table, const Color(0xFF1E5631), 0.35)!,
              ),
            ),
          ),
          if (dice.isNotEmpty)
            Positioned(
              left: halfLeft,
              width: halfW,
              top: geo.midY - ds / 2,
              height: ds,
              child: IgnorePointer(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: diceRow))),
            ),
        ]),
      );
    });

    final actions = <Widget>[];
    if (player && !over) {
      if (myTurn && phase == 'roll') {
        actions.add(absButton(context, '掷骰', Icons.casino, () => g.act({'type': 'roll'}), primary: true));
        if (v['canDouble'] == true) {
          actions.add(absButton(context, '加倍至 ${cube * 2}', Icons.exposure_plus_2, () => g.act({'type': 'double'})));
        }
      }
      if (phase == 'double' && me == 1 - turn) {
        actions.add(absButton(context, '接受', Icons.check, () => g.act({'type': 'take'}), primary: true));
        actions.add(absButton(context, '放弃（输 $cube 分）', Icons.close, () => g.act({'type': 'drop'})));
      }
      if (canMove) {
        if (v['canConfirm'] == true) {
          actions.add(absButton(context, '确认', Icons.done_all, () => g.act({'type': 'confirm'}), primary: true));
        }
        if (played.isNotEmpty) actions.add(absButton(context, '撤销', Icons.undo, () => g.act({'type': 'undo'})));
      }
      final rb = absResign(context, g, label: '认输');
      if (rb != null) actions.add(rb);
    }

    String? banner;
    if (over) banner = absBanner(g, v);
    final lastLine = lastTurn == null
        ? null
        : '${g.name(lastTurn['seat'] as int)} 上回合：${(lastTurn['dice'] as List).take(2).join('-')}'
            '${lastTurn['noMove'] == true ? ' 无子可走' : ' · ${_fmt(lastTurn['moves'] as List, lastTurn['seat'] as int)}'}';
    return AbsShell(
      tags: [tagFor(1 - view), tagFor(view)],
      status: status,
      statusHighlight: myTurn && phase != 'gameover' || (phase == 'double' && me == 1 - turn),
      aspect: _bgW / _bgH,
      board: boardWidget,
      actions: actions,
      info: [
        '第 ${v['gameNo']} 局 · 比分 ${score[0]} : ${score[1]}（$matchTo 分胜）'
            '${cubeOn ? ' · 赌注 $cube' : ''}${crawford ? ' · 克劳福德局' : ''}',
        ?lastLine,
      ],
      result: banner,
      resultSub: over ? '最终比分 ${score[0]} : ${score[1]}' : null,
    );
  }

  static List<(int, bool)> _usedFlags(List<int> dice, List<int> rem) {
    final left = List.of(rem);
    final out = <(int, bool)>[];
    for (final d in dice) {
      if (left.remove(d)) {
        out.add((d, false));
      } else {
        out.add((d, true));
      }
    }
    // 已用的放前面
    out.sort((a, b) => (a.$2 ? 0 : 1) - (b.$2 ? 0 : 1));
    return out;
  }

  static String _fmt(List moves, int seat) {
    String p(int a) => a == 24 ? '中柱' : a == 25 ? '出' : '${seat == 0 ? a + 1 : 24 - a}';
    return [
      for (final m in moves) '${p((m as Map)['from'] as int)}/${p(m['to'] as int)}${m['hit'] == true ? '*' : ''}'
    ].join(' ');
  }
}
