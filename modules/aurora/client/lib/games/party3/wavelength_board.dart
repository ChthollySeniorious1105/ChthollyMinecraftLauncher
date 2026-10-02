import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p3_common.dart';

const _teamColors = [Color(0xFFE53935), Color(0xFF1E88E5)];
const _teamNames = ['红队', '蓝队'];

class WavelengthBoard extends StatefulWidget {
  final GameContext g;
  const WavelengthBoard(this.g, {super.key});
  @override
  State<WavelengthBoard> createState() => _WavelengthBoardState();
}

class _WavelengthBoardState extends State<WavelengthBoard> {
  double? _pos; // my local marker while dragging
  int _round = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = p3Str(v['phase']);
    final team = v['mode'] == 'team';
    final psychic = p3Int(v['psychic'], 0);
    final me = g.seat;
    final guessers = p3Ints(v['guessers']).toSet();
    final opponents = p3Ints(v['opponents']).toSet();
    final locked = p3Ints(v['locked']).toSet();
    final teams = p3Ints(v['teams']);
    final activeTeam = p3Int(v['activeTeam'], 0);
    final round = p3Int(v['round'], 0);
    if (round != _round) {
      _round = round;
      _pos = null;
    }
    final markers = <int, int>{
      for (final e in (p3Map(v['markers']) ?? const {}).entries) int.tryParse(e.key) ?? -1: p3Int(e.value, 50),
    };
    final target = v['target'] is num ? p3Int(v['target']) : null;
    final dial = v['dial'] is num ? p3Int(v['dial']) : null;
    final clue = v['clue'] as String?;
    final result = p3Map(v['result']);
    final votesDone = phase == 'counter' ? p3Ints(v['votes']).toSet() : <int>{};
    final canDial = phase == 'guess' && guessers.contains(me) && !locked.contains(me);
    final myPos = _pos ?? (markers[me] ?? 50).toDouble();

    String status;
    var hl = false;
    final tname = team ? '（${_teamNames[activeTeam]}）' : '';
    switch (phase) {
      case 'clue':
        hl = me == psychic;
        status = me == psychic ? '你是通灵者：看好目标位置，给出一个线索' : '等待通灵者 ${g.name(psychic)}$tname 给线索…';
      case 'guess':
        hl = canDial;
        status = canDial ? '拖动指针到你认为的位置，然后锁定' : (guessers.contains(me) ? '已锁定，等待队友…' : '${team ? _teamNames[activeTeam] : '大家'}正在猜位置…');
      case 'counter':
        hl = opponents.contains(me) && !votesDone.contains(me);
        status = hl ? '目标在指针的左边还是右边？' : '${_teamNames[1 - activeTeam]}判断左右中…';
      case 'result':
        status = '第 $round 轮结果：${result?['points'] ?? 0} 分';
      default:
        status = '游戏结束';
    }

    final showTarget = target != null && (phase == 'result' || phase == 'over' || me == psychic);
    final showDial = phase == 'counter' || phase == 'result' || phase == 'over' || (phase == 'guess' && dial != null);
    final resDial = result != null && (phase == 'result' || phase == 'over') ? (result['dial'] is num ? p3Int(result['dial']) : null) : null;

    Widget dialArea() => LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final h = math.min(box.maxHeight, w / 2 + 30);
          void setFrom(Offset p) {
            final r = math.min(w / 2, h - 24) - 6;
            final c = Offset(w / 2, h - 16);
            final d = p - c;
            var a = math.atan2(-d.dy, d.dx); // 0 = right, pi = left
            if (a < 0) a = d.dx < 0 ? math.pi : 0;
            if (r <= 0) return;
            setState(() => _pos = ((math.pi - a) / math.pi * 100).clamp(0, 100));
          }

          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                onPanDown: canDial ? (d) => setFrom(d.localPosition) : null,
                onPanUpdate: canDial ? (d) => setFrom(d.localPosition) : null,
                child: CustomPaint(
                  painter: _DialPainter(
                    cs: cs,
                    target: showTarget ? (resDial != null || phase != 'over' ? target : target) : null,
                    dial: showDial ? (resDial ?? dial) : null,
                    mine: canDial ? myPos : null,
                    others: phase == 'guess' ? {for (final e in markers.entries) if (e.key != me && locked.contains(e.key)) e.key: e.value} : const {},
                  ),
                ),
              ),
            ),
          );
        });

    Widget main() => P3Panel(
          child: Column(children: [
            Row(children: [
              P3Chip(team ? '第 $round 轮' : '第 $round / ${v['totalCards']} 轮', cs.primary, fg: cs.onPrimary),
              const Spacer(),
              if (team) ...[
                P3Chip('红 ${p3Ints(v['teamScore']).first}', _teamColors[0]),
                const SizedBox(width: 4),
                P3Chip('蓝 ${p3Ints(v['teamScore']).last}', _teamColors[1]),
                const SizedBox(width: 4),
                P3Chip('目标 ${v['goal']}', Colors.blueGrey),
              ] else
                P3Chip('总分 ${v['coopScore']}', Colors.green.shade700),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _endLabel('${v['left']}', Colors.indigo, TextAlign.left)),
              const Text('←→', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: _endLabel('${v['right']}', Colors.deepOrange, TextAlign.right)),
            ]),
            Expanded(child: dialArea()),
            if (clue != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('线索：「$clue」', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.primary)),
              )
            else if (me == psychic && target != null)
              Text('目标位置：$target', style: TextStyle(fontWeight: FontWeight.bold, color: cs.tertiary)),
          ]),
        );

    Widget controls() {
      if (me < 0) return const SizedBox.shrink();
      switch (phase) {
        case 'clue':
          if (me != psychic) return const SizedBox.shrink();
          return P3Input(
            hint: '一个线索（不能含数字）',
            button: '给出',
            maxLength: 20,
            onSubmit: (t) => g.act({'type': 'clue', 'text': t}),
            extra: p3Int(v['skipsLeft'], 0) > 0
                ? IconButton(tooltip: '换光谱（剩 ${v['skipsLeft']}）', onPressed: () => g.act({'type': 'skip'}), icon: const Icon(Icons.refresh))
                : null,
          );
        case 'guess':
          if (!canDial) return const SizedBox.shrink();
          return Row(children: [
            Expanded(
              child: Slider(
                value: myPos,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${myPos.round()}',
                onChanged: (x) => setState(() => _pos = x),
                onChangeEnd: (x) => g.act({'type': 'dial', 'pos': x.round()}),
              ),
            ),
            FilledButton.icon(onPressed: () => g.act({'type': 'lock', 'pos': myPos.round()}), icon: const Icon(Icons.lock), label: Text('锁定 ${myPos.round()}')),
          ]);
        case 'counter':
          if (!opponents.contains(me) || votesDone.contains(me)) return const SizedBox.shrink();
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(onPressed: () => g.act({'type': 'side', 'side': 'left'}), icon: const Icon(Icons.arrow_back), label: const Text('在左边')),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: () => g.act({'type': 'side', 'side': 'right'}), icon: const Icon(Icons.arrow_forward), label: const Text('在右边')),
          ]);
      }
      return const SizedBox.shrink();
    }

    Widget feed() => p3Feed(context, '历史', [
          for (final h in p3Maps(v['history']).reversed)
            p3FeedRow(
              context,
              lead: P3Chip('${h['points']}分', h['team'] is num ? _teamColors[p3Int(h['team'])] : Colors.green.shade700),
              text: '${h['left']} ←→ ${h['right']}',
              sub: '线索「${h['clue']}」 目标 ${h['target']} · 指针 ${h['dial'] ?? '-'}${p3Int(h['counterPt'], 0) > 0 ? ' · 对方 +1' : ''}',
            ),
        ], empty: '还没有结果');

    Widget? banner;
    if (phase == 'over') {
      final w = v['winnerTeam'];
      banner = ResultBanner(
        team ? (w is num ? '${_teamNames[w.toInt()]}获胜！' : '平局') : '合作总分 ${v['coopScore']}',
        child: Text(team ? '红 ${p3Ints(v['teamScore']).first} : 蓝 ${p3Ints(v['teamScore']).last}' : '${v['rating'] ?? ''}'),
      );
    }

    return p3Layout(
      status: P3Status(status, view: v, highlight: hl, replay: g.replay),
      players: p3Players(g,
          active: (s) => s == psychic,
          sub: (s) {
            final t = team && s < teams.length ? _teamNames[teams[s]] : '';
            if (s == psychic) return '$t通灵者';
            if (phase == 'guess' && guessers.contains(s)) return locked.contains(s) ? '$t已锁定' : '$t猜测中';
            if (phase == 'counter' && opponents.contains(s)) return votesDone.contains(s) ? '$t已判断' : '$t判断中';
            return t.isEmpty ? '队友' : t;
          }),
      main: main(),
      feed: feed(),
      controls: controls(),
      banner: banner,
    );
  }

  Widget _endLabel(String t, Color c, TextAlign a) => Text(t,
      textAlign: a, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c));
}

class _DialPainter extends CustomPainter {
  final ColorScheme cs;
  final int? target;
  final int? dial;
  final double? mine;
  final Map<int, int> others;
  _DialPainter({required this.cs, this.target, this.dial, this.mine, this.others = const {}});

  double _ang(num p) => math.pi - p / 100 * math.pi; // 0 → left (pi), 100 → right (0)

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height - 24) - 6;
    if (r <= 10) return;
    final c = Offset(size.width / 2, size.height - 16);
    final rect = Rect.fromCircle(center: c, radius: r);
    // face
    final face = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF8E24AA), Color(0xFFF4511E)]).createShader(rect);
    canvas.drawArc(rect, math.pi, math.pi, true, face);
    canvas.drawArc(rect, math.pi, math.pi, true, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white70);
    // target bands
    if (target != null) {
      void band(int half, Color col, String label) {
        final a0 = _ang((target! + half).clamp(0, 100));
        final a1 = _ang((target! - half).clamp(0, 100));
        canvas.drawArc(rect.deflate(4), -a1, a1 - a0, true, Paint()..color = col);
      }

      band(18, const Color(0xFFFFE082), '2');
      band(11, const Color(0xFFFFB74D), '3');
      band(4, const Color(0xFFE53935), '4');
      for (final (off, lbl) in const [(-14.5, '2'), (-7.5, '3'), (0.0, '4'), (7.5, '3'), (14.5, '2')]) {
        final p = target! + off;
        if (p < 0 || p > 100) continue;
        final a = _ang(p);
        final pos = c + Offset(math.cos(a), -math.sin(a)) * (r * 0.82);
        final tp = TextPainter(
          text: TextSpan(text: lbl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black87, fontFamilyFallback: kFontFallback)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
    // ticks
    final tick = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.5;
    for (var p = 0; p <= 100; p += 10) {
      final a = _ang(p);
      final dir = Offset(math.cos(a), -math.sin(a));
      canvas.drawLine(c + dir * (r - 8), c + dir * r, tick);
    }
    void needle(num p, Color col, double w, {double len = 0.92}) {
      final a = _ang(p);
      final end = c + Offset(math.cos(a), -math.sin(a)) * (r * len);
      canvas.drawLine(c, end, Paint()
        ..color = Colors.black38
        ..strokeWidth = w + 2
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(c, end, Paint()
        ..color = col
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round);
    }

    for (final p in others.values) {
      needle(p, Colors.white60, 2, len: 0.7);
    }
    if (dial != null) needle(dial!, Colors.white, 5);
    if (mine != null) needle(mine!, Colors.amberAccent, 4);
    canvas.drawCircle(c, 9, Paint()..color = Colors.white);
    canvas.drawCircle(c, 5, Paint()..color = cs.primary);
  }

  @override
  bool shouldRepaint(covariant _DialPainter o) =>
      o.target != target || o.dial != dial || o.mine != mine || o.others.length != others.length || o.cs != cs;
}
