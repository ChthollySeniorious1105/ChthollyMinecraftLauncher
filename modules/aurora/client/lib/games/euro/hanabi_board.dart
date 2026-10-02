import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'euro_common.dart';

const _names = ['红', '黄', '绿', '蓝', '白', '彩'];
const _cols = [Color(0xFFE0443C), Color(0xFFF1C232), Color(0xFF3FAE4F), Color(0xFF3A78D6), Color(0xFFEDEDED), Color(0xFFB05CE0)];

Color _col(int c) => c >= 0 && c < _cols.length ? _cols[c] : Colors.grey;

/// One Hanabi card. [c]/[n] null = hidden (show clue knowledge instead).
class HanabiCard extends StatelessWidget {
  final int? c, n;
  final List<int> cc, nn;
  final int nColors;
  final bool clued, selected, highlight;
  final double width;
  final VoidCallback? onTap;
  const HanabiCard({
    super.key,
    this.c,
    this.n,
    this.cc = const [],
    this.nn = const [],
    required this.nColors,
    this.clued = false,
    this.selected = false,
    this.highlight = false,
    this.width = 44,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    final visible = c != null && n != null;
    Widget face;
    if (visible) {
      final base = _col(c!);
      face = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: c == 5
              ? const LinearGradient(colors: [Color(0xFFE0443C), Color(0xFFF1C232), Color(0xFF3FAE4F), Color(0xFF3A78D6), Color(0xFFB05CE0)])
              : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, Color.lerp(base, Colors.black, 0.3)!]),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _BurstPainter(c == 4 ? Colors.black26 : Colors.white38))),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$n',
                  style: TextStyle(
                    fontSize: width * 0.62,
                    fontWeight: FontWeight.w900,
                    color: c == 4 || c == 1 ? Colors.black87 : Colors.white,
                    shadows: const [Shadow(blurRadius: 3, color: Colors.black38)],
                  )),
            ),
          ),
        ]),
      );
    } else {
      face = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF28305A), Color(0xFF121630)]),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _BurstPainter(Colors.white12))),
          if (nn.length == 1)
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${nn.first}',
                    style: TextStyle(
                        fontSize: width * 0.55,
                        fontWeight: FontWeight.w900,
                        color: cc.length == 1 ? _col(cc.first) : Colors.white70)),
              ),
            )
          else if (cc.length == 1)
            Center(child: Container(width: width * 0.4, height: width * 0.4, decoration: BoxDecoration(color: _col(cc.first), shape: BoxShape.circle))),
        ]),
      );
    }
    // knowledge strip
    final strip = (clued || (visible && cc.isNotEmpty && (cc.length < nColors || nn.length < 5)))
        ? Padding(
            padding: EdgeInsets.all(width * 0.04),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var k = 0; k < nColors; k++)
                  Container(
                    width: width * 0.12,
                    height: width * 0.12,
                    margin: EdgeInsets.all(width * 0.01),
                    decoration: BoxDecoration(
                      color: cc.contains(k) ? _col(k) : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 0.6),
                    ),
                  ),
              ])),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  [for (var k = 1; k <= 5; k++) nn.contains(k) ? '$k' : '·'].join(),
                  style: TextStyle(fontSize: width * 0.2, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ]),
          )
        : null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: h,
        transform: Matrix4.translationValues(0, selected ? -width * 0.18 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(
              color: selected ? Colors.white : (highlight ? const Color(0xFFFFE066) : (clued ? const Color(0xFFFFB84D) : Colors.black45)),
              width: selected || highlight || clued ? 2.2 : 1),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38, offset: Offset(1, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width * 0.1),
          child: Column(children: [
            Expanded(child: face),
            if (strip != null) Container(color: Colors.black54, width: double.infinity, child: strip),
          ]),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Color color;
  _BurstPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.42);
    final p = Paint()
      ..color = color
      ..strokeWidth = max(1, size.width * 0.03)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final r1 = size.width * 0.18, r2 = size.width * 0.42;
      canvas.drawLine(c + Offset(cos(a) * r1, sin(a) * r1), c + Offset(cos(a) * r2, sin(a) * r2), p);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.color != color;
}

class HanabiBoard extends StatefulWidget {
  final GameContext g;
  const HanabiBoard(this.g, {super.key});
  @override
  State<HanabiBoard> createState() => _HanabiBoardState();
}

class _HanabiBoardState extends State<HanabiBoard> {
  int? myCard; // selected own card index
  int? target; // selected clue target seat
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final over = v['phase'] == 'over';
    final turn = eInt(v['turn']);
    final myTurn = !over && turn == g.seat;
    final nColors = eInt(v['colors'], 5);
    final hands = eList<dynamic>(v['hands']).map((h) => eList<dynamic>(h).map(eMap).toList()).toList();
    final stacks = eList<int>(v['stacks']);
    final clues = eInt(v['clues']), fuses = eInt(v['fuses']);
    final last = eMap(v['last']);
    final lastIds = eList<int>(last['ids']).toSet();
    final k = '$turn/${eInt(v['deck'])}/$clues/$fuses/${stacks.join()}';
    if (k != key) {
      key = k;
      myCard = null;
      target = null;
    }
    if (target != null && (target! < 0 || target! >= hands.length)) target = null;

    String status;
    if (over) {
      status = '演出结束';
    } else if (myTurn) {
      status = '轮到你：选自己的牌打出/弃掉，或点队友给出提示（提示 $clues）';
    } else {
      status = '等待 ${g.name(turn)} 行动';
    }
    if (!over && eInt(v['finalTurns'], -1) > 0) status += '（最后一轮）';

    Widget tokens() => Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 8; i++)
              Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < clues ? const Color(0xFF4FA3FF) : Colors.transparent,
                  border: Border.all(color: const Color(0xFF4FA3FF), width: 1.5),
                ),
              ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Icon(Icons.local_fire_department, size: 18, color: i < fuses ? Colors.redAccent : cs.onSurface.withValues(alpha: 0.25)),
          ]),
          Text('牌堆 ${eInt(v['deck'])}  得分 ${eInt(v['score'])}/${eInt(v['max'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ]);

    Widget fireworks(double w) => Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (var c = 0; c < nColors; c++)
            Column(mainAxisSize: MainAxisSize.min, children: [
              stacks.elementAtOrNull(c) != null && stacks[c] > 0
                  ? HanabiCard(c: c, n: stacks[c], nColors: nColors, width: w)
                  : Container(
                      width: w,
                      height: w * 1.45,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(w * 0.12),
                        border: Border.all(color: _col(c), width: 2),
                        color: _col(c).withValues(alpha: 0.12),
                      ),
                      child: Center(child: Text(_names[c], style: TextStyle(color: _col(c), fontWeight: FontWeight.bold))),
                    ),
            ]),
        ]);

    Widget discards() {
      final ds = eList<dynamic>(v['discards']).map(eMap).toList()
        ..sort((a, b) => (eInt(a['c']) * 10 + eInt(a['n'])).compareTo(eInt(b['c']) * 10 + eInt(b['n'])));
      if (ds.isEmpty) return Text('弃牌堆：空', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)));
      return Wrap(spacing: 2, runSpacing: 2, children: [
        Text('弃牌：', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
        for (final d in ds)
          Container(
            width: 18,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _col(eInt(d['c'])), borderRadius: BorderRadius.circular(3)),
            child: Text('${eInt(d['n'])}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: eInt(d['c']) == 4 || eInt(d['c']) == 1 ? Colors.black : Colors.white)),
          ),
      ]);
    }

    Widget handRow(int s, double w) {
      final h = s < hands.length ? hands[s] : const <Map<String, dynamic>>[];
      final mine = s == g.seat;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < h.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.05),
            child: HanabiCard(
              c: h[i]['c'] as int?,
              n: h[i]['n'] as int?,
              cc: eList<int>(h[i]['cc']),
              nn: eList<int>(h[i]['nn']),
              clued: h[i]['clued'] == true,
              nColors: nColors,
              width: w,
              highlight: lastIds.contains(eInt(h[i]['id'], -1)),
              selected: mine && myCard == i,
              onTap: mine && myTurn ? () => setState(() => myCard = myCard == i ? null : i) : (myTurn && !mine ? () => setState(() => target = s) : null),
            ),
          ),
      ]);
    }

    Widget playerBlock(int s, double w) {
      final canTarget = myTurn && s != g.seat;
      return GestureDetector(
        onTap: canTarget ? () => setState(() => target = s) : null,
        child: EPanel(
          highlight: target == s || (!over && turn == s),
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            g.tag(s, active: !over && turn == s, size: 24, sub: s == g.seat ? '我的手牌（看不到）' : (canTarget ? '点此提示' : null)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: handRow(s, w)),
          ]),
        ),
      );
    }

    Widget actions() {
      if (!myTurn) return const SizedBox.shrink();
      final t = target;
      final th = t == null ? const <Map<String, dynamic>>[] : hands[t];
      final colorsIn = {for (final c in th) eInt(c['c'], -1)};
      final numsIn = {for (final c in th) eInt(c['n'], -1)};
      return EPanel(
        highlight: true,
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              onPressed: myCard == null ? null : () => g.act({'type': 'play', 'i': myCard}),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('打出'),
            ),
            OutlinedButton.icon(
              onPressed: myCard == null || clues >= 8 ? null : () => g.act({'type': 'discard', 'i': myCard}),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('弃掉'),
            ),
          ]),
          if (t != null && clues > 0) ...[
            const SizedBox(height: 6),
            Text('提示 ${g.name(t)}：', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (var c = 0; c < nColors; c++)
                _clueBtn(_names[c], _col(c), colorsIn.contains(c), () => g.act({'type': 'clue', 'to': t, 'color': c})),
              for (var n = 1; n <= 5; n++)
                _clueBtn('$n', cs.secondary, numsIn.contains(n), () => g.act({'type': 'clue', 'to': t, 'number': n})),
            ]),
          ] else if (clues > 0)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('点击队友的牌可给出提示', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
        ]),
      );
    }

    final result = eMap(v['result']);
    final banner = over
        ? ResultBanner('得分 ${eInt(result['score'])} / ${eInt(result['max'])}',
            child: Text('${result['reason'] ?? ''}  ${_rating(eInt(result['score']), eInt(result['max'], 25))}', textAlign: TextAlign.center))
        : null;

    final order = g.seatsFromMe();
    final others = g.seat >= 0 ? order.skip(1).toList() : order;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 700 && c.maxWidth > c.maxHeight;
      final cardW = wide ? min(52.0, (c.maxWidth * 0.55) / 12) : min(50.0, c.maxWidth / 7.5);
      final center = Column(mainAxisSize: MainAxisSize.min, children: [
        tokens(),
        const SizedBox(height: 6),
        fireworks(cardW * 0.9),
        const SizedBox(height: 6),
        discards(),
      ]);
      final othersW = Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final s in others) playerBlock(s, cardW * 0.9)]);
      final me = g.seat >= 0 ? playerBlock(g.seat, cardW) : const SizedBox.shrink();
      final log = EPanel(child: ELog(eList<String>(v['recent']), max: wide ? 6 : 3, fontSize: 11));
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(children: [StatusBar(status, highlight: myTurn), ?banner, const SizedBox(height: 6), othersW, const SizedBox(height: 8), me]),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(children: [EPanel(child: center), const SizedBox(height: 6), actions(), const SizedBox(height: 6), log]),
            ),
          ),
        ]);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: Column(children: [
          StatusBar(status, highlight: myTurn),
          ?banner,
          const SizedBox(height: 4),
          othersW,
          const SizedBox(height: 6),
          EPanel(child: center),
          const SizedBox(height: 6),
          me,
          const SizedBox(height: 6),
          actions(),
          const SizedBox(height: 6),
          log,
        ]),
      );
    });
  }

  Widget _clueBtn(String label, Color color, bool enabled, VoidCallback onTap) => SizedBox(
        width: 40,
        height: 34,
        child: Material(
          color: enabled ? color : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: enabled ? (color.computeLuminance() > 0.5 ? Colors.black : Colors.white) : Colors.grey)),
            ),
          ),
        ),
      );

  static String _rating(int s, int maxS) {
    final r = s / maxS;
    if (s == maxS) return '传奇演出，观众永生难忘！';
    if (r >= 0.84) return '精彩绝伦！';
    if (r >= 0.64) return '相当出色';
    if (r >= 0.44) return '还算不错';
    if (r >= 0.2) return '勉强及格';
    return '观众都走光了……';
  }
}
