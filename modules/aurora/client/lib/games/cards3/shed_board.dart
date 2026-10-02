import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c3_widgets.dart';

/// Per-game configuration for [ShedBoard].
class ShedConfig {
  final String title;

  /// Candidate plays (cheapest first) for the hint button.
  final List<List<String>> Function(List<String> hand, Map<String, dynamic> v) hints;

  /// Label for the currently selected cards (null = not a combo).
  final String? Function(List<String> cards, Map<String, dynamic> v) classify;
  final List<Widget> Function(GameContext g) pills;
  final String Function(GameContext g, int s) sub;
  final Widget? Function(GameContext g, int s)? badge;
  final Widget Function(GameContext g, double w) result;
  final Color tint;
  const ShedConfig({
    required this.title,
    required this.hints,
    required this.classify,
    required this.pills,
    required this.sub,
    required this.result,
    this.badge,
    this.tint = const Color(0xFF0B6B3A),
  });
}

class ShedBoard extends StatefulWidget {
  final GameContext g;
  final ShedConfig cfg;
  const ShedBoard(this.g, this.cfg, {super.key});
  @override
  State<ShedBoard> createState() => _ShedBoardState();
}

class _ShedBoardState extends State<ShedBoard> {
  final Set<int> _sel = {};
  String _handKey = '';
  int _hint = -1;
  String _hintKey = '';

  GameContext get g => widget.g;
  ShedConfig get cfg => widget.cfg;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => c3Strs(v['hand']);

  void _sync() {
    final k = hand.join(',');
    if (k != _handKey) {
      _handKey = k;
      _sel.clear();
    }
    final hk = '$k|${v['tableSeat']}|${(v['tableCards'] as List?)?.join(',')}|${v['turn']}|${v['phase']}';
    if (hk != _hintKey) {
      _hintKey = hk;
      _hint = -1;
    }
  }

  List<String> get _selCards {
    final h = hand;
    return [for (final i in _sel) if (i >= 0 && i < h.length) h[i]];
  }

  void _doHint() {
    final h = hand;
    final cands = cfg.hints(h, v);
    if (cands.isEmpty) {
      c3Toast(context, v['lead'] == true ? '没有可出的组合' : '没有能管上的牌，请选择不要');
      return;
    }
    _hint = (_hint + 1) % cands.length;
    final used = <int>{};
    for (final c in cands[_hint]) {
      for (var i = 0; i < h.length; i++) {
        if (!used.contains(i) && h[i] == c) {
          used.add(i);
          break;
        }
      }
    }
    setState(() {
      _sel
        ..clear()
        ..addAll(used);
    });
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final phase = '${v['phase']}';
    final turn = (v['turn'] as num? ?? -1).toInt();
    final me = g.seat;
    final playing = phase == 'play';
    final tribute = phase == 'tribute';
    final myTurn = me >= 0 && (playing || tribute) && turn == me;
    final lead = v['lead'] == true;
    String status;
    if (playing) {
      if (myTurn) {
        final t = v['table'] as Map?;
        status = lead || t == null ? '轮到你出牌（任意牌型）' : '轮到你：管上 ${t['label']}，或选择不要';
      } else {
        status = '等待 ${g.name(turn)} 出牌';
      }
    } else if (tribute) {
      status = myTurn ? '你是上游：选一张牌还给下游 ${g.name((v['down'] as num).toInt())}' : '等待上游 ${g.name(turn)} 还贡';
    } else {
      status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 8.5 : 16)).clamp(30.0, 62.0).toDouble();
        final byH = (c.maxHeight / 7.4).clamp(28.0, 62.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(fit: StackFit.expand, children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              c3Pill('${cfg.title} 第 ${v['round']}/${v['rounds']} 局', Colors.indigo),
              ...cfg.pills(g),
            ]),
            const SizedBox(height: 4),
            c3Opponents(others, (s) => _panel(s, w * 0.72), c.maxWidth),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.05, vertical: 2),
                child: C3Felt(felt: c3FeltColor(g, cfg.tint), child: Center(child: _center(w))),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                g.tag(me, active: myTurn, size: 28, sub: cfg.sub(g, me), trailing: cfg.badge?.call(g, me)),
                if (playing && _act(me)?['pass'] == true) c3Pill('不要', Colors.blueGrey),
              ]),
              const SizedBox(height: 4),
              if (myTurn) (tribute ? _tributeButtons() : _buttons(lead)),
              const SizedBox(height: 4),
              C3Hand(
                cards: hand,
                sel: _sel,
                cw: w,
                maxW: c.maxWidth - 16,
                onToggle: (i) => setState(() {
                  if (tribute) {
                    final had = _sel.contains(i);
                    _sel.clear();
                    if (!had) _sel.add(i);
                  } else if (!_sel.remove(i)) {
                    _sel.add(i);
                  }
                }),
                label: _sel.isEmpty || tribute ? null : cfg.classify(_selCards, v),
              ),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase == 'roundEnd' || phase == 'over')
            Center(child: SingleChildScrollView(child: cfg.result(g, w))),
        ]);
      }),
    );
  }

  Map? _act(int s) {
    final acts = v['acts'] as List?;
    if (acts == null || s < 0 || s >= acts.length) return null;
    return acts[s] as Map?;
  }

  Widget _panel(int s, double w) {
    final counts = c3Ints(v['counts']);
    final playing = v['phase'] == 'play';
    final active = (playing || v['phase'] == 'tribute') && (v['turn'] as num? ?? -1).toInt() == s;
    final a = playing ? _act(s) : null;
    final n = s < counts.length ? counts[s] : 0;
    final finish = c3Ints(v['finish']);
    final place = finish.indexOf(s);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s, active: active, size: 30, sub: cfg.sub(g, s), trailing: cfg.badge?.call(g, s)),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (n > 0) c3Backs(n, w),
        if (n > 0) Padding(padding: const EdgeInsets.only(left: 4), child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        if (place >= 0) c3Pill('第${place + 1}个出完', Colors.amber.shade800, fontSize: 11),
        const SizedBox(width: 6),
        if (a != null && a['pass'] == true) c3Pill('不要', Colors.blueGrey),
        if (a != null && a['pass'] != true) c3Pill('${a['label']}', Colors.teal),
        if (n > 0 && n <= 2 && playing) Padding(padding: const EdgeInsets.only(left: 4), child: c3Pill('报$n', Colors.redAccent, fontSize: 11)),
      ]),
    ]);
  }

  Widget _center(double w) {
    final phase = v['phase'];
    if (phase == 'tribute') {
      final t = v['tribute'] as String?;
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('进贡', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (t != null) c3Card(t, w, highlight: true),
            const SizedBox(height: 6),
            Text('下游 ${g.name((v['down'] as num).toInt())} → 上游 ${g.name((v['up'] as num).toInt())}',
                style: const TextStyle(color: Colors.white70)),
          ]),
        ),
      );
    }
    if (phase != 'play') return const SizedBox();
    final ts = (v['tableSeat'] as num? ?? -1).toInt();
    final cards = c3Strs(v['tableCards']);
    final extra = v['lastDraw'] is String && (v['lastDraw'] as String).isNotEmpty ? v['lastDraw'] as String : null;
    if (v['lead'] == true || cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${g.name((v['turn'] as num).toInt())} 自由出牌',
                style: const TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.bold)),
            if (extra != null) Text(extra, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
      );
    }
    final label = (v['table'] as Map?)?['label'] ?? '';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          c3Row(cards, w * 0.95, gap: 0.5),
          const SizedBox(height: 4),
          c3Pill('${g.name(ts)} · $label', Colors.black54, fontSize: 13),
        ]),
      ),
    );
  }

  Widget _buttons(bool lead) {
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
      OutlinedButton(onPressed: lead ? null : () => g.act({'type': 'pass'}), child: const Text('不要')),
      OutlinedButton(onPressed: _doHint, child: const Text('提示')),
      if (_sel.isNotEmpty) OutlinedButton(onPressed: () => setState(_sel.clear), child: const Text('重选')),
      FilledButton(
        onPressed: _sel.isEmpty ? null : () => g.act({'type': 'play', 'cards': _selCards}),
        child: const Text('出牌'),
      ),
    ]);
  }

  Widget _tributeButtons() {
    return FilledButton(
      onPressed: _sel.length != 1 ? null : () => g.act({'type': 'return', 'cards': _selCards}),
      child: const Text('还贡'),
    );
  }
}

/// Generic result table: [cols] builds extra cells for each seat.
Widget c3ResultTable(GameContext g,
    {required String title, required List<int> order, required List<Widget> Function(int s) cells, bool rank = false}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560),
    child: ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var k = 0; k < order.length; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 28, child: Text(rank ? '#${k + 1}' : '')),
                SizedBox(width: 84, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                ...cells(order[k]),
              ]),
            ),
          ),
        c3Continue(g),
      ]),
    ),
  );
}
