import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c4_widgets.dart';

/// Per-game configuration for [C4ShedBoard] (够级 / 保皇 / 双扣).
class C4ShedConfig {
  final String title;
  final Color tint;
  final List<Widget> Function(GameContext g) pills;
  final String Function(GameContext g, int s) sub;
  final Widget? Function(GameContext g, int s)? badge;

  /// Candidate plays for the hint button (cheapest first).
  final List<List<String>> Function(GameContext g, List<String> hand) hints;

  /// Label of the selected cards, or null when not a combo.
  final String? Function(GameContext g, List<String> cards) classify;

  /// Status text for phases other than 'play' (null = generic).
  final String? Function(GameContext g)? status;

  /// Whether I have to act in a non-play phase (and the board should show [phaseActions]).
  final bool Function(GameContext g)? phaseMine;

  /// Buttons for non-play phases; [sel] = selected cards.
  final Widget Function(GameContext g, List<String> sel)? phaseActions;

  /// Center content for non-play phases.
  final Widget? Function(GameContext g, double w)? phaseCenter;

  final Widget Function(GameContext g, double w) result;
  const C4ShedConfig({
    required this.title,
    required this.pills,
    required this.sub,
    required this.hints,
    required this.classify,
    required this.result,
    this.badge,
    this.status,
    this.phaseMine,
    this.phaseActions,
    this.phaseCenter,
    this.tint = const Color(0xFF0B6B3A),
  });
}

class C4ShedBoard extends StatefulWidget {
  final GameContext g;
  final C4ShedConfig cfg;
  const C4ShedBoard(this.g, this.cfg, {super.key});
  @override
  State<C4ShedBoard> createState() => _C4ShedBoardState();
}

class _C4ShedBoardState extends State<C4ShedBoard> {
  final Set<int> _sel = {};
  String _handKey = '';
  int _hint = -1;
  String _hintKey = '';

  GameContext get g => widget.g;
  C4ShedConfig get cfg => widget.cfg;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => c4Strs(v['hand']);

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
    return [for (final i in (_sel.toList()..sort())) if (i >= 0 && i < h.length) h[i]];
  }

  void _doHint() {
    final h = hand;
    final cands = cfg.hints(g, h);
    if (cands.isEmpty) {
      c4Toast(context, v['lead'] == true ? '没有可出的组合' : '没有能管上的牌，请选择不要');
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
    final turn = c4Int(v['turn']);
    final me = g.seat;
    final playing = phase == 'play';
    final myPlay = me >= 0 && playing && turn == me && !g.over;
    final myPhase = me >= 0 && !playing && (cfg.phaseMine?.call(g) ?? false);
    final lead = v['lead'] == true;
    String status;
    if (playing) {
      if (myPlay) {
        final t = v['table'] as Map?;
        status = lead || t == null ? '轮到你出牌（任意牌型）' : '轮到你：管上 ${g.name(c4Int(v['tableSeat']))} 的 ${t['label']}，或选择不要';
      } else {
        status = '等待 ${g.name(turn)} 出牌';
      }
    } else {
      status = cfg.status?.call(g) ?? (phase == 'over' ? '比赛结束' : (phase == 'roundEnd' ? '本局结束' : '请稍候'));
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final landscape = c.maxWidth > c.maxHeight * 1.3;
        final cw0 = (c.maxWidth / (c.maxWidth < 600 ? 8.5 : 18)).clamp(30.0, 58.0).toDouble();
        final byH = (c.maxHeight / (landscape ? 9.5 : 11)).clamp(26.0, 58.0).toDouble();
        final w = cw0 < byH ? cw0 : byH;
        final layout = C4HandLayout.compute(hand.length, c.maxWidth - 16, w, maxRows: landscape && c.maxHeight < 500 ? 2 : 3);
        return Stack(fit: StackFit.expand, children: [
          Column(children: [
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  c4Pill(cfg.title, Colors.indigo),
                  for (final p in cfg.pills(g)) Padding(padding: const EdgeInsets.only(left: 6), child: p),
                ]),
              ),
            ),
            const SizedBox(height: 2),
            c4Opponents(others, (s) => _panel(s, w * 0.72), c.maxWidth),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.04, vertical: 2),
                child: C4Felt(
                  felt: c4FeltColor(g, cfg.tint),
                  child: Center(child: playing ? _center(w) : (cfg.phaseCenter?.call(g, w) ?? const SizedBox())),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(status, highlight: myPlay || myPhase)),
            ),
            const SizedBox(height: 3),
            if (me >= 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    g.tag(me, active: myPlay || myPhase, size: 26, sub: cfg.sub(g, me), trailing: cfg.badge?.call(g, me)),
                    if (playing && _act(me)?['pass'] == true) ...[const SizedBox(width: 6), c4Pill('不要', Colors.blueGrey)],
                    const SizedBox(width: 10),
                    if (myPlay) _buttons(lead),
                    if (myPhase && cfg.phaseActions != null) cfg.phaseActions!(g, _selCards),
                  ]),
                ),
              ),
              const SizedBox(height: 2),
              C4Hand(
                cards: hand,
                sel: _sel,
                layout: layout,
                onToggle: (i) => setState(() {
                  if (!_sel.remove(i)) _sel.add(i);
                }),
                label: _sel.isEmpty || !playing ? null : cfg.classify(g, _selCards),
              ),
            ] else
              const SizedBox(height: 16),
            const SizedBox(height: 6),
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
    final counts = c4Ints(v['counts']);
    final playing = v['phase'] == 'play';
    final active = playing && c4Int(v['turn']) == s && !g.over;
    final a = playing ? _act(s) : null;
    final n = s < counts.length ? counts[s] : 0;
    final finish = c4Ints(v['finish']);
    final place = finish.indexOf(s);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s, active: active, size: 28, sub: cfg.sub(g, s), trailing: cfg.badge?.call(g, s)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (n > 0) c4Backs(n, w),
          if (n > 0)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (place >= 0) c4Pill('第${place + 1}个出完', Colors.amber.shade800, fontSize: 11),
          const SizedBox(width: 6),
          if (a != null && a['pass'] == true) c4Pill('不要', Colors.blueGrey),
          if (a != null && a['pass'] != true) c4Pill('${a['label']}', Colors.teal),
          if (n > 0 && n <= 3 && playing)
            Padding(padding: const EdgeInsets.only(left: 4), child: c4Pill('剩$n', Colors.redAccent, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _center(double w) {
    final ts = c4Int(v['tableSeat']);
    final cards = c4Strs(v['tableCards']);
    final log = c4Strs(v['log']);
    if (v['lead'] == true || cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${g.name(c4Int(v['turn']))} 自由出牌',
                style: const TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            c4Log(log, max: 2),
          ]),
        ),
      );
    }
    final t = v['table'] as Map?;
    final label = t?['label'] ?? '';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey('${cards.join(',')}|$ts'),
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, k, child) => Transform.scale(scale: k, child: child),
            child: c4Row(cards, w * 0.95, gap: cards.length > 10 ? 0.35 : 0.5),
          ),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            c4Pill('${g.name(ts)} · $label', Colors.black54, fontSize: 13),
            if (t?['gouji'] == true) ...[const SizedBox(width: 4), c4Pill('够级', Colors.deepOrange, fontSize: 12)],
            if (t?['burn'] == true) ...[const SizedBox(width: 4), c4Pill('烧牌', Colors.red, fontSize: 12)],
            if (t?['bomb'] == true || t?['type'] == 'bomb' || t?['type'] == 'kings') ...[
              const SizedBox(width: 4),
              c4Pill('炸弹', Colors.red.shade700, fontSize: 12),
            ],
          ]),
          const SizedBox(height: 4),
          c4Log(log, max: 1),
        ]),
      ),
    );
  }

  Widget _buttons(bool lead) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton(onPressed: lead ? null : () => g.act({'type': 'pass'}), child: const Text('不要')),
      const SizedBox(width: 6),
      OutlinedButton(onPressed: _doHint, child: const Text('提示')),
      if (_sel.isNotEmpty) ...[
        const SizedBox(width: 6),
        OutlinedButton(onPressed: () => setState(_sel.clear), child: const Text('重选')),
      ],
      const SizedBox(width: 6),
      FilledButton(
        onPressed: _sel.isEmpty ? null : () => g.act({'type': 'play', 'cards': _selCards}),
        child: const Text('出牌'),
      ),
    ]);
  }
}

/// Generic result table rows.
Widget c4ResultTable(GameContext g,
    {required String title, required List<int> order, required List<Widget> Function(int s) cells, List<Widget> header = const []}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 640),
    child: ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ...header,
        for (var k = 0; k < order.length; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 84, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                ...cells(order[k]),
              ]),
            ),
          ),
        c4Continue(g),
      ]),
    ),
  );
}
