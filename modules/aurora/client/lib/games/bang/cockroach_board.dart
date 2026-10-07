import 'package:aurora_shared/games/bang/cockroach.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'bg_widgets.dart';

const _bugColors = [
  Color(0xFF8D6E63), Color(0xFF78909C), Color(0xFF7E57C2), Color(0xFF26A69A),
  Color(0xFFEF6C00), Color(0xFF7CB342), Color(0xFF455A64), Color(0xFFD81B60),
];

/// 蟑螂扑克
class CockroachBoard extends StatefulWidget {
  final GameContext g;
  const CockroachBoard(this.g, {super.key});
  @override
  State<CockroachBoard> createState() => _CockroachBoardState();
}

class _CockroachBoardState extends State<CockroachBoard> {
  int _card = -1;
  int _target = -1;
  int _claim = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  Widget build(BuildContext context) {
    final me = g.seat;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = bgInt(v['turn']);
    final holder = bgInt(v['holder']);
    final from = bgInt(v['from']);
    final claim = bgInt(v['claim']);
    final hand = bgInts(v['hand']);
    final counts = bgInts(v['handCounts']);
    final faceUp = [for (final f in (v['faceUp'] as List)) bgInts(f)];
    final eligible = bgInts(v['eligible']);
    final card = bgInt(v['card']);
    final losers = bgInts(v['losers']);
    final iPass = !over && phase == 'pass' && turn == me;
    final iRespond = !over && phase == 'respond' && holder == me;
    final iRepass = !over && phase == 'repass' && holder == me;

    if (!iPass) _card = -1;
    if (!iPass && !iRepass) {
      _target = -1;
      _claim = -1;
    }
    if (_card >= 0 && !hand.contains(_card)) _card = -1;
    final targets = iPass ? [for (var s = 0; s < g.players; s++) if (s != me) s] : (iRepass ? eligible : <int>[]);
    if (!targets.contains(_target)) _target = -1;
    if ((iPass || iRepass) && targets.length == 1) _target = targets.first;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (iPass) {
      status = _card < 0 ? '轮到你：选一张手牌' : (_target < 0 ? '选择递给谁' : (_claim < 0 ? '选择你要宣称的害虫' : '确认递出'));
    } else if (iRespond) {
      status = '${g.name(from)} 说这是「${cockroachNames[claim]}」——你信吗？';
    } else if (iRepass) {
      status = '你偷看了：是${cockroachNames[card]}！选择转给谁并宣称';
    } else if (phase == 'pass') {
      status = '等待 ${g.name(turn)} 递牌';
    } else {
      status = '${g.name(holder)} 正在考虑${phase == 'repass' ? '转手' : '真假'}';
    }

    final others = g.seatsFromMe().where((s) => s != me).toList();
    final logs = [for (final l in (v['log'] as List? ?? const [])) '$l'];

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        final rows = narrow && others.length > 3 ? 2 : 1;
        final panelH = (c.maxHeight * (rows == 2 ? 0.26 : 0.2)).clamp(80.0, 210.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: bgPanelGrid([
                for (final s in others)
                  _panel(s, counts[s], faceUp[s], s == turn || s == holder, targets.contains(s), losers.contains(s)),
              ], rows, panelH),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : c.maxWidth * 0.06, vertical: 4),
                child: BgFelt(felt: Color.lerp(g.table, const Color(0xFF2E5E3A), 0.5)!, child: _center(logs, from, holder, claim, card, iRespond, iPass || iRepass, eligible)),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: StatusBar(status, highlight: iPass || iRespond || iRepass)),
            const SizedBox(height: 4),
            if (me >= 0) _mine(me, hand, counts[me], faceUp[me], iPass, iRepass, c.maxWidth, losers.contains(me)),
            const SizedBox(height: 6),
          ]),
          if (over) Center(child: _result(faceUp, losers)),
        ]);
      }),
    );
  }

  Widget _faceRow(List<int> f, {double size = 20}) {
    final items = [for (var k = 0; k < 8; k++) if (f[k] > 0) k];
    if (items.isEmpty) return Text('面前无牌', style: TextStyle(fontSize: size * 0.6, color: Colors.grey));
    return Wrap(spacing: 3, runSpacing: 3, children: [
      for (final k in items)
        Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.2, vertical: 1),
          decoration: BoxDecoration(
            color: f[k] >= 3 ? Colors.red.shade700 : _bugColors[k].withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(size * 0.4),
            border: f[k] >= 3 ? Border.all(color: Colors.yellowAccent, width: 1.5) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            bgEmoji(cockroachEmoji[k], size * 0.8),
            Text('×${f[k]}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.6)),
          ]),
        ),
    ]);
  }

  Widget _panel(int s, int count, List<int> f, bool active, bool pickable, bool lost) {
    final picked = s == _target;
    return bgPanel(context,
        active: active,
        picked: picked,
        pickable: pickable,
        onTap: pickable ? () => setState(() => _target = s) : null,
        child: SizedBox(
          width: 170,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            g.tag(s, active: active, size: 30, sub: '手牌 $count 张${lost ? ' · 输了' : ''}'),
            const SizedBox(height: 4),
            _faceRow(f, size: 26),
          ]),
        ));
  }

  Widget _bigCard(int k, {double w = 64, bool back = false}) => Container(
        width: w,
        height: w * 1.4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.12),
          gradient: back
              ? const LinearGradient(colors: [Color(0xFF3E2723), Color(0xFF6D4C41)], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : LinearGradient(colors: [Colors.white, _bugColors[k].withValues(alpha: 0.35)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border.all(color: back ? Colors.amber.shade200 : _bugColors[k], width: 2),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(1, 2))],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: back
                ? bgEmoji('❓', w * 0.5)
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    bgEmoji(cockroachEmoji[k], w * 0.55),
                    Text(cockroachNames[k], style: TextStyle(fontWeight: FontWeight.bold, fontSize: w * 0.2, color: Colors.black87)),
                  ]),
          ),
        ),
      );

  Widget _center(List<String> logs, int from, int holder, int claim, int card, bool iRespond, bool choosing, List<int> eligible) {
    final chain = [for (final e in (v['chain'] as List? ?? const [])) e as Map];
    final last = v['lastResult'] as Map?;
    return LayoutBuilder(builder: (context, fc) {
      final cw = (fc.maxHeight * 0.36).clamp(40.0, 90.0).toDouble();
      Widget main;
      if (chain.isNotEmpty) {
        main = Row(mainAxisSize: MainAxisSize.min, children: [
          _bigCard(card < 0 ? 0 : card, w: cw, back: card < 0),
          const SizedBox(width: 14),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < chain.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${g.name(bgInt(chain[i]['from']))} → ${g.name(bgInt(chain[i]['to']))}：“',
                        style: TextStyle(color: i == chain.length - 1 ? Colors.white : Colors.white60, fontSize: 14, fontWeight: FontWeight.bold)),
                    bgEmoji(cockroachEmoji[bgInt(chain[i]['claim'], 0)], 18),
                    Text('${cockroachNames[bgInt(chain[i]['claim'], 0)]}”',
                        style: TextStyle(color: i == chain.length - 1 ? Colors.amberAccent : Colors.white60, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                ),
              if (iRespond) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    onPressed: () => g.act({'type': 'call', 'truth': true}),
                    child: const Text('真的'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                    onPressed: () => g.act({'type': 'call', 'truth': false}),
                    child: const Text('假的'),
                  ),
                  if (eligible.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                      onPressed: () => g.act({'type': 'peek'}),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('偷看并转手'),
                    ),
                ]),
              ],
            ]),
          ),
        ]);
      } else if (last != null) {
        final k = bgInt(last['card'], 0);
        main = Row(mainAxisSize: MainAxisSize.min, children: [
          _bigCard(k, w: cw),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              '上一轮：${g.name(bgInt(last['caller']))} 判断“${last['said'] == true ? '真' : '假'}”，'
              '其实是${cockroachNames[k]}，${last['right'] == true ? '猜对了' : '猜错了'}\n${g.name(bgInt(last['taker']))} 收下了它',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.4),
            ),
          ),
        ]);
      } else {
        main = Text('🪳 蟑螂扑克 🪳', style: TextStyle(color: Colors.white70, fontSize: cw * 0.35, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback));
      }
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: main)))),
          if (choosing) _claimPicker(),
          if (!choosing && fc.maxHeight > 170) Align(alignment: Alignment.centerLeft, child: bgLog(logs, max: 3)),
        ]),
      );
    });
  }

  Widget _claimPicker() => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('宣称：', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          for (var k = 0; k < 8; k++)
            GestureDetector(
              onTap: () => setState(() => _claim = k),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _claim == k ? Colors.amber : Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _claim == k ? Colors.white : Colors.white24),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  bgEmoji(cockroachEmoji[k], 24),
                  Text(cockroachNames[k], style: TextStyle(fontSize: 11, color: _claim == k ? Colors.black : Colors.white)),
                ]),
              ),
            ),
        ]),
      );

  Widget _mine(int me, List<int> hand, int count, List<int> f, bool iPass, bool iRepass, double maxW, bool lost) {
    final byKind = List.filled(8, 0);
    for (final c in hand) {
      byKind[c]++;
    }
    final ready = _target >= 0 && _claim >= 0 && (iRepass || _card >= 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            g.tag(me, active: iPass || iRepass, size: 30, sub: '手牌 $count${lost ? ' · 输了' : ''}'),
            const SizedBox(width: 8),
            _faceRow(f, size: 22),
            if (iPass || iRepass) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: ready
                    ? () {
                        g.act({'type': 'pass', if (iPass) 'card': _card, 'to': _target, 'claim': _claim});
                        setState(() {
                          _card = -1;
                          _claim = -1;
                          _target = -1;
                        });
                      }
                    : null,
                icon: const Icon(Icons.send, size: 18),
                label: Text(_target >= 0 ? '递给 ${g.name(_target)}' : '递出'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var k = 0; k < 8; k++)
              if (byKind[k] > 0)
                GestureDetector(
                  onTap: iPass ? () => setState(() => _card = _card == k ? -1 : k) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(left: 3, right: 3, bottom: _card == k ? 0 : 10, top: _card == k ? 10 : 0),
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [if (_card == k) const BoxShadow(color: Colors.amberAccent, blurRadius: 8, spreadRadius: 2)],
                        ),
                        child: _bigCard(k, w: 54),
                      ),
                      if (byKind[k] > 1)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.red.shade700,
                            child: Text('${byKind[k]}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ]),
                  ),
                ),
            if (hand.isEmpty) const SizedBox(height: 76, child: Center(child: Text('没有手牌', style: TextStyle(color: Colors.white70)))),
          ]),
        ),
      ]),
    );
  }

  Widget _result(List<List<int>> faceUp, List<int> losers) {
    final total = [for (final f in faceUp) f.fold<int>(0, (a, b) => a + b)];
    final pl = bgInts(v['placings']);
    if (pl.length != g.players) return const SizedBox();
    return bgResult(g, '${losers.map(g.name).join('、')} 输了！', pl, (s) => losers.contains(s) ? '输家 · 面前 ${total[s]} 张' : '面前 ${total[s]} 张');
  }
}
