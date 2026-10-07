import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'd2_common.dart';

const _colNames = ['黄', '蓝', '白', '绿', '红'];
const _colFull = ['沙漠', '海底', '雪山', '雨林', '火山'];
const _colIcons = ['🏜️', '🌊', '🏔️', '🌴', '🌋'];
const _colColors = [
  Color(0xFFE8B923),
  Color(0xFF2F6BD8),
  Color(0xFFB8C4CE),
  Color(0xFF2E9B4E),
  Color(0xFFD83A34),
];
int _color(int c) => c ~/ 12;
bool _invest(int c) => c % 12 < 3;
int _value(int c) => _invest(c) ? 0 : c % 12 - 1;
String _label(int c) => _invest(c) ? '🤝' : '${_value(c)}';

/// One Lost Cities card; -1 = face-down back.
class LcCard extends StatelessWidget {
  final int code;
  final double w;
  final bool selected;
  final bool dim;
  final bool glow;
  const LcCard(this.code, {super.key, this.w = 52, this.selected = false, this.dim = false, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final h = w * 1.42;
    if (code < 0) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.1),
          gradient: const LinearGradient(colors: [Color(0xFF3E2C1C), Color(0xFF6B4A2B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: const Color(0xFFE6C88A), width: w * 0.04),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: dFit('🧭', TextStyle(fontSize: w * 0.45)),
      );
    }
    final col = _colColors[_color(code)];
    final dark = _color(code) == 2 ? const Color(0xFF37474F) : Colors.white;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: w,
        height: h,
        transform: Matrix4.translationValues(0, selected ? -w * 0.2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.1),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(col, Colors.white, 0.18)!, col, Color.lerp(col, Colors.black, 0.3)!],
          ),
          border: Border.all(color: selected ? Colors.white : Colors.black26, width: selected ? w * 0.06 : 1),
          boxShadow: [
            BoxShadow(
                color: selected || glow ? Colors.yellowAccent.withValues(alpha: 0.85) : Colors.black38,
                blurRadius: selected || glow ? 9 : 2,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Stack(children: [
          // corner value (visible when cards overlap)
          Positioned(
            left: w * 0.08,
            top: w * 0.02,
            height: w * 0.3,
            right: w * 0.08,
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: dFit(_label(code), TextStyle(fontSize: w * 0.26, fontWeight: FontWeight.w900, color: dark)),
                ),
              ),
              dFit(_colIcons[_color(code)], TextStyle(fontSize: w * 0.18)),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.3,
            bottom: h * 0.08,
            child: Center(
              child: dFit(
                _invest(code) ? '🤝' : '${_value(code)}',
                TextStyle(fontSize: w * 0.5, fontWeight: FontWeight.w900, color: dark, shadows: const [Shadow(blurRadius: 3, color: Colors.black26)]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class LostCitiesBoard extends StatefulWidget {
  final GameContext g;
  const LostCitiesBoard(this.g, {super.key});
  @override
  State<LostCitiesBoard> createState() => _LostCitiesBoardState();
}

class _LostCitiesBoardState extends State<LostCitiesBoard> {
  int? sel;
  String _sig = '';
  GameContext get g => widget.g;
  bool get player => g.seat >= 0 && g.seat < 2;
  int get me => player ? g.seat : 0;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final sig = '${v['round']}|${v['phase']}|${v['turn']}|${v['hand']}';
    if (sig != _sig) {
      _sig = sig;
      sel = null;
    }
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.05;
      final design = landscape ? const Size(1000, 560) : const Size(410, 780);
      final banner = _banner(context, v);
      return Stack(children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: design.width, height: design.height, child: landscape ? _landscape(context, v) : _portrait(context, v)),
          ),
        ),
        if (banner != null) Positioned(left: 0, right: 0, top: 4, child: Center(child: banner)),
      ]);
    });
  }

  bool _myTurn(Map<String, dynamic> v) =>
      player && !g.over && (v['phase'] == 'play' || v['phase'] == 'draw') && dInt(v['turn']) == g.seat;

  List<int> _exp(Map<String, dynamic> v, int s, int col) {
    final e = dList<Object?>(v['exped']);
    if (s >= e.length) return const [];
    final p = dList<Object?>(e[s]);
    return col < p.length ? dInts(p[col]) : const [];
  }

  bool _canPlay(Map<String, dynamic> v, int card) {
    final e = _exp(v, me, _color(card));
    if (e.isEmpty) return true;
    if (_invest(card)) return _invest(e.last);
    return _value(card) > _value(e.last);
  }

  String _status(Map<String, dynamic> v) {
    final phase = v['phase'];
    final rounds = dInt(v['rounds'], 1);
    final pre = rounds > 1 ? '第 ${v['round']}/$rounds 局 · ' : '';
    if (phase == 'over') {
      final w = dInt(v['winner'], -1);
      return w == -2 ? '平局' : (w == g.seat ? '你赢了！' : '${g.name(w)} 获胜');
    }
    if (phase == 'roundEnd') return '$pre本局结束';
    final turn = dInt(v['turn']);
    if (_myTurn(v)) {
      if (phase == 'play') return sel == null ? '$pre选择一张手牌出牌或弃牌' : '$pre点自己的探险列出牌，或点弃牌堆弃牌';
      return '$pre摸一张牌：牌堆或任一弃牌堆顶';
    }
    return '$pre等待 ${g.name(turn)} ${phase == 'draw' ? '摸牌' : '出牌'}';
  }

  /// Vertical fan of expedition cards (grows downward or upward).
  Widget _column(Map<String, dynamic> v, int s, int col, double w, double height, {required bool up, VoidCallback? onTap, bool target = false}) {
    final cards = _exp(v, s, col);
    final h = w * 1.42;
    final strip = cards.length <= 1 ? 0.0 : min(w * 0.36, (height - h) / (cards.length - 1));
    final last = dMap(v['last']);
    final lastCard = last['type'] == 'play' && dInt(last['seat'], -1) == s ? dInt(last['card'], -1) : -1;
    final scores = dList<Object?>(v['scores']);
    final sc = s < scores.length ? dInts(scores[s]) : <int>[];
    final score = col < sc.length ? sc[col] : 0;
    final cs = Theme.of(context).colorScheme;
    final stack = SizedBox(
      width: w + 6,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: [
        // slot outline
        Positioned(
          left: 3,
          width: w,
          height: h,
          top: up ? height - h : 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.1),
              color: _colColors[col].withValues(alpha: target ? 0.45 : 0.18),
              border: Border.all(color: target ? Colors.yellowAccent : _colColors[col].withValues(alpha: 0.7), width: target ? 2.5 : 1.5),
            ),
            alignment: Alignment.center,
            child: dFit(_colIcons[col], TextStyle(fontSize: w * 0.4)),
          ),
        ),
        for (var i = 0; i < cards.length; i++)
          Positioned(
            left: 3,
            top: up ? height - h - i * strip : i * strip,
            child: LcCard(cards[i], w: w, glow: cards[i] == lastCard),
          ),
      ]),
    );
    final label = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
      child: Text(cards.isEmpty ? '—' : (score >= 0 ? '+$score' : '$score'),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cards.isEmpty ? cs.onSurface.withValues(alpha: 0.5) : (score >= 0 ? Colors.green.shade700 : Colors.red.shade700))),
    );
    final col0 = Column(mainAxisSize: MainAxisSize.min, children: up ? [stack, label] : [label, stack]);
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: col0);
  }

  Widget _discardRow(Map<String, dynamic> v, double w) {
    final discard = dList<Object?>(v['discard']);
    final phase = v['phase'];
    final myTurn = _myTurn(v);
    final jd = dInt(v['justDiscarded'], -1);
    final deck = dInt(v['deck']);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      for (var col = 0; col < 5; col++)
        Builder(builder: (context) {
          final pile = col < discard.length ? dInts(discard[col]) : <int>[];
          final canDiscard = myTurn && phase == 'play' && sel != null && _color(sel!) == col;
          final canDraw = myTurn && phase == 'draw' && pile.isNotEmpty && col != jd;
          return GestureDetector(
            onTap: canDiscard
                ? () => g.act({'type': 'discard', 'card': sel})
                : canDraw
                    ? () => g.act({'type': 'draw', 'from': col})
                    : null,
            child: SizedBox(
              width: w + 6,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: w,
                  height: w * 1.42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(w * 0.1),
                    border: Border.all(
                        color: canDiscard || canDraw ? Colors.yellowAccent : Colors.white24, width: canDiscard || canDraw ? 2.5 : 1),
                    color: Colors.black.withValues(alpha: 0.15),
                  ),
                  alignment: Alignment.center,
                  child: pile.isEmpty
                      ? Text('弃${_colNames[col]}', style: const TextStyle(color: Colors.white54, fontSize: 11))
                      : LcCard(pile.last, w: w, dim: col == jd && myTurn && phase == 'draw'),
                ),
                Text(pile.isEmpty ? ' ' : '×${pile.length}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ]),
            ),
          );
        }),
      GestureDetector(
        onTap: myTurn && phase == 'draw' && deck > 0 ? () => g.act({'type': 'draw', 'from': -1}) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.1),
              boxShadow: myTurn && phase == 'draw' ? const [BoxShadow(color: Colors.yellowAccent, blurRadius: 10)] : null,
            ),
            child: LcCard(-1, w: w),
          ),
          Text('牌堆 $deck', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
    ]);
  }

  Widget _expRow(Map<String, dynamic> v, int s, double w, double height, {required bool up}) {
    final mine = s == g.seat && _myTurn(v) && v['phase'] == 'play' && sel != null;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      for (var col = 0; col < 5; col++)
        _column(v, s, col, w, height,
            up: up,
            target: mine && _color(sel!) == col && _canPlay(v, sel!),
            onTap: mine && _color(sel!) == col && _canPlay(v, sel!) ? () => g.act({'type': 'play', 'card': sel}) : null),
      SizedBox(width: w + 6),
    ]);
  }

  Widget _hand(Map<String, dynamic> v, double w) {
    final hand = dInts(v['hand']);
    final playPhase = _myTurn(v) && v['phase'] == 'play';
    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final c in hand)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: GestureDetector(
            onTap: playPhase ? () => setState(() => sel = sel == c ? null : c) : null,
            child: LcCard(c, w: w, selected: sel == c, dim: playPhase && !_canPlay(v, c) && sel != c),
          ),
        ),
    ]);
  }

  List<Widget> _buttons(Map<String, dynamic> v) {
    if (!_myTurn(v) || v['phase'] != 'play' || sel == null) return const [];
    return [
      DButton('打出', icon: Icons.flag, onTap: _canPlay(v, sel!) ? () => g.act({'type': 'play', 'card': sel}) : null),
      DButton('弃牌', icon: Icons.delete_outline, primary: false, onTap: () => g.act({'type': 'discard', 'card': sel})),
    ];
  }

  Widget _info(Map<String, dynamic> v, int s) {
    final scores = dList<Object?>(v['scores']);
    final sc = s < scores.length ? dInts(scores[s]) : <int>[];
    final total = dInts(v['total']);
    final rounds = dInt(v['rounds'], 1);
    final cur = sc.fold(0, (a, b) => a + b);
    final hc = dInts(v['handCount']);
    return g.tag(s,
        active: !g.over && (v['phase'] == 'play' || v['phase'] == 'draw') && dInt(v['turn']) == s,
        sub: '本局 $cur${rounds > 1 ? ' · 累计 ${s < total.length ? total[s] : 0}' : ''}${s != g.seat ? ' · 手牌 ${s < hc.length ? hc[s] : 0}' : ''}');
  }

  Widget _felt(Widget child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3F5A3C), Color(0xFF2B3F2A)],
          ),
          border: Border.all(color: const Color(0xFFC9A66B), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: child,
      );

  Widget _portrait(BuildContext context, Map<String, dynamic> v) {
    final opp = player ? 1 - me : 1;
    final btns = _buttons(v);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Flexible(child: _info(v, opp))]),
        const SizedBox(height: 4),
        StatusBar(_status(v), highlight: _myTurn(v)),
        const SizedBox(height: 4),
        Expanded(
          child: _felt(Column(children: [
            _expRow(v, opp, 50, 168, up: true),
            const SizedBox(height: 4),
            _discardRow(v, 50),
            const SizedBox(height: 4),
            _expRow(v, me, 50, 168, up: false),
          ])),
        ),
        const SizedBox(height: 4),
        if (player) ...[
          SizedBox(height: 82, child: FittedBox(fit: BoxFit.scaleDown, child: _hand(v, 44))),
          SizedBox(height: 38, child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: btns)),
        ],
        Row(children: [
          Flexible(child: _info(v, me)),
          const SizedBox(width: 6),
          Expanded(child: SizedBox(height: 44, child: DLog(dList<String>(v['recent']), max: 3))),
        ]),
      ]),
    );
  }

  Widget _landscape(BuildContext context, Map<String, dynamic> v) {
    final opp = player ? 1 - me : 1;
    final btns = _buttons(v);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 560,
          child: _felt(Column(children: [
            _expRow(v, opp, 52, 160, up: true),
            const SizedBox(height: 6),
            _discardRow(v, 52),
            const SizedBox(height: 6),
            _expRow(v, me, 52, 160, up: false),
          ])),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: _info(v, opp)),
            const SizedBox(height: 8),
            StatusBar(_status(v), highlight: _myTurn(v)),
            const SizedBox(height: 8),
            DPanel(child: SizedBox(width: double.infinity, child: DLog(dList<String>(v['recent']), max: 5))),
            const Spacer(),
            if (player) ...[
              SizedBox(height: 100, child: FittedBox(fit: BoxFit.scaleDown, child: _hand(v, 46))),
              SizedBox(height: 40, child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: btns)),
            ],
            Align(alignment: Alignment.centerLeft, child: _info(v, me)),
          ]),
        ),
      ]),
    );
  }

  Widget? _banner(BuildContext context, Map<String, dynamic> v) {
    final phase = v['phase'];
    if (phase != 'roundEnd' && phase != 'over') return null;
    final rr = dMap(v['roundResult']);
    final resigned = dInt(v['resigned'], -1);
    final w = dInt(v['winner'], -1);
    final total = dInts(v['total']);
    String title;
    if (phase == 'over') {
      if (resigned >= 0) {
        title = '${g.name(resigned)} 认输，${g.name(w)} 获胜';
      } else {
        title = w == -2 ? '平局！' : (w == g.seat ? '你赢了！' : '${g.name(w)} 获胜');
      }
    } else {
      title = '第 ${dInt(rr['round'])} 局结束';
    }
    Widget? table;
    final exp = dList<Object?>(rr['exp']);
    final sc = dInts(rr['score']);
    if (exp.length == 2 && sc.length == 2) {
      List<String> row(int s) => [g.name(s), for (final x in dInts(exp[s])) '$x', '${sc[s]}', if (dInt(v['rounds'], 1) > 1) '${total[s]}'];
      table = dTable(context, ['玩家', ..._colFull, '本局', if (dInt(v['rounds'], 1) > 1) '累计'], [row(0), row(1)]);
    }
    final ready = dList<Object?>(v['ready']);
    final canContinue = phase == 'roundEnd' && player && me < ready.length && ready[me] != true;
    return ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ?table,
        if (canContinue) ...[
          const SizedBox(height: 6),
          DButton('下一局', icon: Icons.play_arrow, onTap: () => g.act({'type': 'continue'})),
        ] else if (phase == 'roundEnd')
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('等待双方继续…', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}
