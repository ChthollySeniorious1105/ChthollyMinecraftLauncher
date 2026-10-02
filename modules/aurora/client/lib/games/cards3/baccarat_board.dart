import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c3_widgets.dart';

const _areas = ['P', 'T', 'B', 'PP', 'BP'];
const _areaName = {'B': '庄', 'P': '闲', 'T': '和', 'PP': '闲对', 'BP': '庄对'};
const _areaOdds = {'B': '1:0.95', 'P': '1:1', 'T': '1:8', 'PP': '1:11', 'BP': '1:11'};
const _areaColor = {
  'B': Color(0xFFC62828),
  'P': Color(0xFF1565C0),
  'T': Color(0xFF2E7D32),
  'PP': Color(0xFF283593),
  'BP': Color(0xFF8E0000),
};
const _chipValues = [10, 50, 100, 500, 1000];

class BaccaratBoard extends StatefulWidget {
  final GameContext g;
  const BaccaratBoard(this.g, {super.key});
  @override
  State<BaccaratBoard> createState() => _BaccaratBoardState();
}

class _BaccaratBoardState extends State<BaccaratBoard> {
  final Map<String, int> _bets = {};
  int _chip = 100;
  int _coupKey = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  int get _total => _bets.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final coup = (v['coup'] as num? ?? 0).toInt();
    if (coup != _coupKey) {
      _coupKey = coup;
      _bets.clear();
    }
    final phase = '${v['phase']}';
    final me = g.seat;
    final chips = c3Ints(v['chips']);
    final betDone = (v['betDone'] as List?)?.map((e) => e == true).toList() ?? const [];
    final broke = (v['broke'] as List?)?.map((e) => e == true).toList() ?? const [];
    final canBet = me >= 0 && phase == 'bet' && me < betDone.length && !betDone[me] && !broke[me];
    String status;
    if (phase == 'bet') {
      if (canBet) {
        status = '请下注（已选 $_total / 余 ${chips[me]}）';
      } else if (me >= 0 && me < broke.length && broke[me]) {
        status = '你的筹码已不足，观战中';
      } else {
        final wait = [for (var s = 0; s < betDone.length; s++) if (!betDone[s] && !broke[s]) g.name(s)];
        status = '等待下注：${wait.join('、')}';
      }
    } else if (phase == 'reveal') {
      final w = v['winner'];
      status = '闲 ${v['pTotal']} 点 · 庄 ${v['bTotal']} 点 → ${w == 'B' ? '庄赢' : (w == 'P' ? '闲赢' : '和局')}';
    } else {
      status = '比赛结束';
    }
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.3;
        final cw = (c.maxWidth / (wide ? 22 : 10)).clamp(30.0, 64.0).toDouble();
        final byH = (c.maxHeight / (wide ? 6.5 : 10)).clamp(28.0, 64.0).toDouble();
        final w = cw < byH ? cw : byH;
        final table = C3Felt(
          felt: c3FeltColor(g, const Color(0xFF00695C)),
          child: Center(child: _dealArea(w)),
        );
        final road = _beadRoad();
        return Stack(fit: StackFit.expand, children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              c3Pill('百家乐 第 $coup/${v['rounds']} 局', Colors.indigo),
              c3Pill('第${v['shoeNo']}靴 · 余${v['shoeLeft']}张', Colors.brown),
              if (v['reshuffle'] == true) c3Pill('切牌卡已出，下局换靴', Colors.deepOrange, fontSize: 11),
            ]),
            const SizedBox(height: 4),
            _players(c.maxWidth),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: wide
                    ? Row(children: [
                        Expanded(flex: 3, child: table),
                        const SizedBox(width: 6),
                        Expanded(flex: 2, child: road),
                      ])
                    : Column(children: [
                        Expanded(flex: 3, child: table),
                        const SizedBox(height: 4),
                        Expanded(flex: 2, child: road),
                      ]),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: canBet),
            const SizedBox(height: 4),
            if (canBet) _betPanel(chips[me], c.maxWidth) else const SizedBox(height: 4),
            const SizedBox(height: 6),
          ]),
          if (phase == 'over') Center(child: SingleChildScrollView(child: _result())),
        ]);
      }),
    );
  }

  Widget _players(double width) {
    final chips = c3Ints(v['chips']);
    final net = c3Ints(v['net']);
    final bets = v['bets'] as List? ?? const [];
    final betDone = v['betDone'] as List? ?? const [];
    final phase = v['phase'];
    Widget panel(int s) {
      final b = s < bets.length ? (bets[s] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final txt = b.entries.map((e) => '${_areaName[e.key]}${e.value}').join(' ');
      return Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s,
            active: phase == 'bet' && s < betDone.length && betDone[s] != true,
            size: 28,
            sub: '筹码 ${s < chips.length ? chips[s] : 0}'),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (phase == 'bet' && s < betDone.length && betDone[s] == true && txt.isEmpty) c3Pill('已下注', Colors.teal, fontSize: 11),
          if (txt.isNotEmpty) c3Pill(txt, Colors.black54, fontSize: 11),
          if (phase != 'bet' && s < net.length && (net[s] != 0 || txt.isNotEmpty))
            Padding(padding: const EdgeInsets.only(left: 4), child: c3Delta(net[s], fontSize: 13)),
        ]),
      ]);
    }

    return c3Opponents(List.generate(g.players, (i) => i), panel, width * 1.6);
  }

  Widget _dealArea(double w) {
    final p = c3Strs(v['player']);
    final b = c3Strs(v['banker']);
    final win = v['winner'];
    Widget side(String label, List<String> cards, Object? total, Color col, bool won, bool pair) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: won ? Colors.amberAccent : col.withValues(alpha: 0.7), width: won ? 3 : 1.5),
          color: col.withValues(alpha: 0.18),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, shadows: [Shadow(color: col, blurRadius: 6)])),
            if (total != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(10)),
                child: Text('$total 点', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
            if (pair) ...[const SizedBox(width: 6), c3Pill('对子', Colors.amber.shade800, fontSize: 11)],
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: w * 1.4,
            child: cards.isEmpty
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 2; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: w,
                        height: w * 1.4,
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(w * 0.1)),
                      ),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < cards.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        // 补牌横放
                        child: i == 2
                            ? SizedBox(width: w * 1.4, height: w * 1.4, child: Center(child: RotatedBox(quarterTurns: 1, child: c3Card(cards[i], w))))
                            : c3Card(cards[i], w),
                      ),
                  ]),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          side('闲', p, v['pTotal'], _areaColor['P']!, win == 'P', v['pp'] == true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(win == 'T' ? '和' : 'VS',
                style: TextStyle(color: win == 'T' ? Colors.greenAccent : Colors.white54, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          side('庄', b, v['bTotal'], _areaColor['B']!, win == 'B', v['bp'] == true),
        ]),
      ),
    );
  }

  /// 珠盘路：6 行，按列从上到下填充。
  Widget _beadRoad() {
    final road = [for (final r in (v['road'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
    final counts = {'B': 0, 'P': 0, 'T': 0};
    for (final r in road) {
      counts['${r['w']}'] = (counts['${r['w']}'] ?? 0) + 1;
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F0),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(builder: (context, c) {
        const rows = 6;
        final cell = ((c.maxHeight - 22) / rows).clamp(8.0, 30.0).toDouble();
        final cols = (c.maxWidth / cell).floor().clamp(1, 60);
        final lastCol = road.isEmpty ? 0 : (road.length - 1) ~/ rows;
        final start = lastCol >= cols ? (lastCol - cols + 1) * rows : 0;
        final shown = road.sublist(start);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
                const Text('珠盘路  ', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                _legend('庄', counts['B']!, _areaColor['B']!),
                _legend('闲', counts['P']!, _areaColor['P']!),
                _legend('和', counts['T']!, _areaColor['T']!),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _BeadPainter(shown, cell, rows, cols),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _legend(String t, int n, Color c) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text('$t $n', style: const TextStyle(color: Colors.black87, fontSize: 12)),
        ]),
      );

  Widget _betPanel(int chips, double width) {
    final allowPairs = v['pairs'] == true;
    final areas = [for (final a in _areas) if (allowPairs || (a != 'PP' && a != 'BP')) a];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        for (final a in areas)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (_total + _chip > chips) {
                c3Toast(context, '筹码不足');
                return;
              }
              setState(() => _bets[a] = (_bets[a] ?? 0) + _chip);
            },
            child: Container(
              width: width < 500 ? 66 : 92,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: _areaColor[a]!.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (_bets[a] ?? 0) > 0 ? Colors.amberAccent : Colors.white38, width: 2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_areaName[a]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(_areaOdds[a]!, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                Text((_bets[a] ?? 0) > 0 ? '${_bets[a]}' : ' ',
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
        for (final cv in _chipValues)
          if (cv <= chips)
            ChoiceChip(
              label: Text('$cv'),
              selected: _chip == cv,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _chip = cv),
            ),
        OutlinedButton(onPressed: _bets.isEmpty ? null : () => setState(_bets.clear), child: const Text('清空')),
        OutlinedButton(onPressed: () => g.act({'type': 'skip'}), child: const Text('本局不下')),
        FilledButton(
          onPressed: _bets.isEmpty ? null : () => g.act({'type': 'bet', 'bets': Map<String, int>.of(_bets)}),
          child: const Text('确认下注'),
        ),
      ]),
    ]);
  }

  Widget _result() {
    final chips = c3Ints(v['chips']);
    final order = List.generate(g.players, (i) => i)..sort((a, b) => chips[b] - chips[a]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ResultBanner(
        '比赛结束 · ${g.name(order.first)} 筹码最多',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 28, child: Text('#${k + 1}')),
                SizedBox(width: 100, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 70, child: Text('${chips[order[k]]}', textAlign: TextAlign.right)),
                SizedBox(width: 60, child: Align(alignment: Alignment.centerRight, child: c3Delta(chips[order[k]] - 1000, fontSize: 13))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BeadPainter extends CustomPainter {
  final List<Map<String, dynamic>> road;
  final double cell;
  final int rows, cols;
  _BeadPainter(this.road, this.cell, this.rows, this.cols);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var c = 0; c <= cols; c++) {
      canvas.drawLine(Offset(c * cell, 0), Offset(c * cell, rows * cell), grid);
    }
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(cols * cell, r * cell), grid);
    }
    for (var i = 0; i < road.length; i++) {
      final col = i ~/ rows, row = i % rows;
      if (col >= cols) break;
      final e = road[i];
      final w = '${e['w']}';
      final color = _areaColor[w] ?? Colors.grey;
      final center = Offset(col * cell + cell / 2, row * cell + cell / 2);
      final r = cell * 0.42;
      canvas.drawCircle(center, r, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: _areaName[w],
          style: TextStyle(
              color: Colors.white, fontSize: cell * 0.5, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      final dot = cell * 0.1;
      if (e['bp'] == true) canvas.drawCircle(center + Offset(-r * 0.7, -r * 0.7), dot, Paint()..color = _areaColor['B']!);
      if (e['pp'] == true) canvas.drawCircle(center + Offset(r * 0.7, r * 0.7), dot, Paint()..color = _areaColor['P']!);
      if (e['bp'] == true || e['pp'] == true) {
        final ring = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        if (e['bp'] == true) canvas.drawCircle(center + Offset(-r * 0.7, -r * 0.7), dot, ring);
        if (e['pp'] == true) canvas.drawCircle(center + Offset(r * 0.7, r * 0.7), dot, ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeadPainter old) => true;
}
