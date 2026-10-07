import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'd2_common.dart';

const _goodNames = ['钻石', '黄金', '白银', '布料', '香料', '皮革', '骆驼'];
const _goodEmoji = ['💎', '🥇', '🥈', '🧵', '🌶️', '👜', '🐪'];
const _goodColors = [
  Color(0xFFC2185B), // diamond – ruby red
  Color(0xFFF2A900), // gold
  Color(0xFF8A9BB0), // silver
  Color(0xFF7B3FA0), // cloth – purple
  Color(0xFF2E8B3E), // spice – green
  Color(0xFF8B5A2B), // leather – brown
  Color(0xFFD9A35B), // camel – sand
];
const _camel = 6;

/// One Jaipur card (goods, camel or face-down back).
class JpCard extends StatelessWidget {
  final int code; // 0..6, -1 = back
  final double w;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;
  final String? badge;
  const JpCard(this.code, {super.key, this.w = 60, this.selected = false, this.dim = false, this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final h = w * 1.4;
    final back = code < 0;
    final c = back ? const Color(0xFF6D2E1F) : _goodColors[code];
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: w,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -w * 0.16 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: back
              ? const [Color(0xFF8E3B26), Color(0xFF5A2015)]
              : [Color.lerp(c, Colors.white, 0.28)!, c, Color.lerp(c, Colors.black, 0.25)!],
        ),
        border: Border.all(color: selected ? Colors.white : const Color(0xFFF7E7C6), width: selected ? w * 0.06 : w * 0.035),
        boxShadow: [
          BoxShadow(
              color: selected ? Colors.yellowAccent.withValues(alpha: 0.8) : Colors.black38,
              blurRadius: selected ? 10 : 3,
              offset: const Offset(0, 2)),
        ],
      ),
      child: back
          ? Center(
              child: Container(
                width: w * 0.62,
                height: w * 0.62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFF2C46D), width: w * 0.04),
                ),
                alignment: Alignment.center,
                child: dFit('斋', TextStyle(fontSize: w * 0.3, color: const Color(0xFFF2C46D), fontWeight: FontWeight.w900)),
              ),
            )
          : Stack(children: [
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                top: h * 0.14,
                height: w * 0.84,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.85)),
                  alignment: Alignment.center,
                  child: dFit(_goodEmoji[code], TextStyle(fontSize: w * 0.46)),
                ),
              ),
              Positioned(
                left: 2,
                right: 2,
                bottom: h * 0.05,
                height: h * 0.2,
                child: Center(
                  child: dFit(_goodNames[code],
                      TextStyle(fontSize: w * 0.22, color: Colors.white, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 2)])),
                ),
              ),
            ]),
    );
    final out = Opacity(opacity: dim ? 0.45 : 1, child: card);
    final withBadge = badge == null
        ? out
        : Stack(clipBehavior: Clip.none, children: [
            out,
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(9)),
                child: Text(badge!, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]);
    return onTap == null ? withBadge : GestureDetector(onTap: onTap, child: withBadge);
  }
}

/// Round goods token.
class _Token extends StatelessWidget {
  final int good; // -1 bonus, 7 camel token
  final String text;
  final double size;
  const _Token(this.good, this.text, {this.size = 34});
  @override
  Widget build(BuildContext context) {
    final c = good >= 0 && good < 7 ? _goodColors[good] : (good == 7 ? _goodColors[6] : const Color(0xFF263238));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Color.lerp(c, Colors.white, 0.35)!, c], center: const Alignment(-0.3, -0.3)),
        border: Border.all(color: const Color(0xFFF7E7C6), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: dFit(text, TextStyle(fontSize: size * 0.45, color: Colors.white, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 2)])),
      ),
    );
  }
}

class JaipurBoard extends StatefulWidget {
  final GameContext g;
  const JaipurBoard(this.g, {super.key});
  @override
  State<JaipurBoard> createState() => _JaipurBoardState();
}

class _JaipurBoardState extends State<JaipurBoard> {
  final Set<int> selMarket = {};
  final Set<int> selHand = {};
  int camels = 0;
  String _sig = '';
  GameContext get g => widget.g;

  void _reset() {
    selMarket.clear();
    selHand.clear();
    camels = 0;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final market = dInts(v['market']);
    final hand = dInts(v['hand']);
    final sig = '${v['round']}|$market|$hand|${v['turn']}|${v['phase']}';
    if (sig != _sig) {
      _sig = sig;
      _reset();
    }
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.05;
      final design = landscape ? const Size(980, 560) : const Size(410, 780);
      final body = landscape ? _landscape(context, v) : _portrait(context, v);
      final banner = _banner(context, v);
      return Stack(children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: design.width, height: design.height, child: body),
          ),
        ),
        if (banner != null) Positioned(left: 0, right: 0, top: 4, child: Center(child: banner)),
      ]);
    });
  }

  // ------------------------------------------------------------ pieces
  int get me => g.seat >= 0 && g.seat < 2 ? g.seat : 0;
  bool get player => g.seat >= 0 && g.seat < 2;

  bool _myTurn(Map<String, dynamic> v) => player && !g.over && v['phase'] == 'play' && dInt(v['turn']) == g.seat;

  String _status(Map<String, dynamic> v) {
    final phase = v['phase'];
    final turn = dInt(v['turn']);
    final round = dInt(v['round']);
    final single = v['single'] == true;
    final pre = single ? '' : '第 $round 局 · ';
    if (phase == 'over') {
      final w = dInt(v['winner'], -1);
      return w == g.seat ? '你赢得了比赛！' : '${g.name(w)} 赢得比赛';
    }
    if (phase == 'roundEnd') return '$pre本局结束';
    if (_myTurn(v)) return '$pre轮到你：拿牌 / 交换 / 出售';
    return '$pre等待 ${g.name(turn)} 行动';
  }

  Widget _seals(int n, int need) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < need; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(i < n ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                size: 20, color: i < n ? const Color(0xFFF2B630) : Colors.grey),
          ),
      ]);

  Widget _chip(BuildContext context, String text, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (color ?? cs.surface).withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color == null ? cs.onSurface : Colors.white)),
    );
  }

  /// Player summary: tag + seals + herd + tokens.
  Widget _playerInfo(BuildContext context, Map<String, dynamic> v, int s, {bool showHandBacks = false}) {
    final goods = dList<Object?>(v['goods']);
    final gs = s < goods.length ? dInts(goods[s]) : <int>[];
    final bonusCount = dInts(v['bonusCount']);
    final bv = dList<Object?>(v['bonusValues']);
    final myBonus = s < bv.length && bv[s] != null ? dInts(bv[s]) : null;
    final herd = dInts(v['herd']);
    final handCount = dInts(v['handCount']);
    final need = v['single'] == true ? 1 : 2;
    final seals = dInts(v['seals']);
    final goodsSum = gs.fold(0, (a, b) => a + b);
    final bonusSum = myBonus?.fold(0, (a, b) => a + b);
    return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      g.tag(s, active: !g.over && v['phase'] == 'play' && dInt(v['turn']) == s, sub: '手牌 ${s < handCount.length ? handCount[s] : 0}'),
      _seals(s < seals.length ? seals[s] : 0, need),
      _chip(context, '🐪 ${s < herd.length ? herd[s] : 0}', color: const Color(0xFFB07A3A)),
      _chip(context, '货物币 $goodsSum（${gs.length} 枚）', color: const Color(0xFF5D4037)),
      _chip(context, myBonus == null ? '奖励币 ${s < bonusCount.length ? bonusCount[s] : 0} 枚 ?' : '奖励币 ${myBonus.length} 枚 = $bonusSum',
          color: const Color(0xFF263238)),
      if (showHandBacks)
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < (s < handCount.length ? handCount[s] : 0); i++)
            Align(widthFactor: 0.55, child: const JpCard(-1, w: 26)),
        ]),
    ]);
  }

  Widget _tokens(BuildContext context, Map<String, dynamic> v, {required double size}) {
    final tokens = dList<Object?>(v['tokens']);
    final bonusLeft = dInts(v['bonusLeft']);
    final deck = dInt(v['deck']);
    Widget pile(int g0) {
      final t = g0 < tokens.length ? dInts(tokens[g0]) : <int>[];
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: size * 1.15,
          height: size * 1.15,
          child: Stack(alignment: Alignment.center, children: [
            if (t.length > 1) Positioned(left: 0, top: 0, child: Opacity(opacity: 0.6, child: _Token(g0, '', size: size))),
            if (t.isNotEmpty)
              Positioned(right: 0, bottom: 0, child: _Token(g0, '${t.first}', size: size))
            else
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 2)),
                  alignment: Alignment.center,
                  child: const Text('空', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
              ),
          ]),
        ),
        Text('${_goodEmoji[g0]}×${t.length}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        if (t.length > 1)
          Text(t.skip(1).join(' '),
              maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 9, color: Colors.white70)),
      ]);
    }

    Widget bag(int i) => Column(mainAxisSize: MainAxisSize.min, children: [
          _Token(-1, '${i + 3}${i == 2 ? '+' : ''}', size: size * 0.85),
          Text('剩 ${i < bonusLeft.length ? bonusLeft[i] : 0}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ]);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 6; i++) SizedBox(width: size * 1.55, child: pile(i)),
      ]),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (var i = 0; i < 3; i++) bag(i),
        Column(mainAxisSize: MainAxisSize.min, children: [
          _Token(7, '5', size: size * 0.85),
          const Text('骆驼王', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        Column(mainAxisSize: MainAxisSize.min, children: [
          JpCard(-1, w: size * 0.7),
          Text('牌堆 $deck', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ]),
    ]);
  }

  Widget _market(Map<String, dynamic> v, double w) {
    final market = dInts(v['market']);
    final myTurn = _myTurn(v);
    final last = dMap(v['last']);
    final lastCards = last['seat'] != g.seat && last['type'] == 'exchange' ? dInts(last['gave']) : <int>[];
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < market.length; i++)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.06),
          child: JpCard(
            market[i],
            w: w,
            selected: selMarket.contains(i),
            badge: lastCards.contains(market[i]) ? '新' : null,
            onTap: !myTurn
                ? null
                : () => setState(() {
                      if (market[i] == _camel) {
                        _reset();
                        return;
                      }
                      selMarket.contains(i) ? selMarket.remove(i) : selMarket.add(i);
                    }),
          ),
        ),
      for (var i = market.length; i < 5; i++)
        Padding(padding: EdgeInsets.symmetric(horizontal: w * 0.06), child: SizedBox(width: w, height: w * 1.4)),
    ]);
  }

  Widget _hand(Map<String, dynamic> v, double w) {
    final hand = dInts(v['hand']);
    final myTurn = _myTurn(v);
    final herd = dInts(v['herd']);
    final myHerd = player && me < herd.length ? herd[me] : 0;
    if (!player) return const SizedBox();
    final exchanging = selMarket.length >= 2;
    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (hand.isEmpty)
        SizedBox(height: w * 1.4, child: const Center(child: Text('（没有手牌）', style: TextStyle(color: Colors.white70)))),
      for (var i = 0; i < hand.length; i++)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: JpCard(
            hand[i],
            w: w,
            selected: selHand.contains(i),
            onTap: !myTurn ? null : () => setState(() => selHand.contains(i) ? selHand.remove(i) : selHand.add(i)),
          ),
        ),
      SizedBox(width: w * 0.3),
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (myTurn && exchanging && myHerd > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            _miniBtn(Icons.remove, camels > 0 ? () => setState(() => camels--) : null),
            _miniBtn(Icons.add, camels < myHerd ? () => setState(() => camels++) : null),
          ]),
        JpCard(_camel, w: w, selected: camels > 0, badge: camels > 0 ? '换出 $camels/$myHerd' : '×$myHerd', dim: myHerd == 0),
      ]),
    ]);
  }

  Widget _miniBtn(IconData icon, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: onTap == null ? Colors.black26 : Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(3), child: Icon(icon, size: 16, color: onTap == null ? Colors.white38 : Colors.black87)),
          ),
        ),
      );

  /// Action buttons + hint for the current selection.
  (List<Widget>, String) _actions(Map<String, dynamic> v) {
    if (!_myTurn(v)) return (const [], '');
    final market = dInts(v['market']);
    final hand = dInts(v['hand']);
    final camelsInMarket = market.where((c) => c == _camel).length;
    final btns = <Widget>[];
    String hint;
    final selM = [for (final i in selMarket) if (i < market.length) market[i]];
    final selH = [for (final i in selHand) if (i < hand.length) hand[i]];
    if (selM.isEmpty && selH.isEmpty) {
      hint = '点市场上的货物拿取/交换，点手牌出售';
    } else if (selM.isEmpty) {
      final types = selH.toSet();
      if (types.length > 1) {
        hint = '一次只能出售同一种货物';
      } else {
        final t = types.first;
        final ok = t >= 3 || selH.length >= 2;
        hint = ok ? '出售 ${selH.length} 张${_goodNames[t]}${selH.length >= 3 ? '（得奖励币）' : ''}' : '${_goodNames[t]}至少一次卖 2 张';
        btns.add(DButton('出售 ×${selH.length}', icon: Icons.sell, onTap: ok ? () => g.act({'type': 'sell', 'good': t, 'count': selH.length}) : null));
      }
    } else if (selM.length == 1 && selH.isEmpty && camels == 0) {
      final full = hand.length >= 7;
      hint = full ? '手牌已满 7 张，无法拿取' : '拿取 1 张${_goodNames[selM.first]}（再多选可交换）';
      btns.add(DButton('拿取', icon: Icons.pan_tool_alt, onTap: full ? null : () => g.act({'type': 'take', 'idx': selMarket.first})));
    } else {
      final give = selH.length + camels;
      final clash = selH.any(selM.contains);
      final over = hand.length - selH.length + selM.length > 7;
      if (selM.length < 2) {
        hint = '交换至少要从市场选 2 张';
      } else if (clash) {
        hint = '不能用同种货物交换';
      } else if (give != selM.length) {
        hint = '交换：拿 ${selM.length} 张，需换出 ${selM.length} 张（已选 $give，可用骆驼）';
      } else if (over) {
        hint = '交换后手牌会超过 7 张';
      } else {
        hint = '用 $give 张牌交换 ${selM.length} 张货物';
      }
      final ok = selM.length >= 2 && !clash && give == selM.length && !over;
      btns.add(DButton('交换', icon: Icons.swap_horiz, onTap: ok
          ? () => g.act({'type': 'exchange', 'market': selMarket.toList(), 'hand': selHand.toList(), 'camels': camels})
          : null));
    }
    if (camelsInMarket > 0) {
      btns.add(DButton('拿走骆驼 ×$camelsInMarket', icon: Icons.pets, primary: false, onTap: () => g.act({'type': 'camels'})));
    }
    if (selM.isNotEmpty || selH.isNotEmpty || camels > 0) {
      btns.add(DButton('取消', primary: false, onTap: () => setState(_reset)));
    }
    return (btns, hint);
  }

  Widget _felt(Widget child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB5542C), Color(0xFF8A3418)],
          ),
          border: Border.all(color: const Color(0xFFE9B949), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.all(8),
        child: child,
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s, style: const TextStyle(color: Color(0xFFFCE7B2), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
      );

  Widget _portrait(BuildContext context, Map<String, dynamic> v) {
    final (btns, hint) = _actions(v);
    final opp = player ? 1 - me : 1;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DPanel(child: _playerInfo(context, v, opp, showHandBacks: true)),
        const SizedBox(height: 6),
        StatusBar(_status(v), highlight: _myTurn(v)),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 398,
                child: _felt(Column(children: [
                  _tokens(context, v, size: 34),
                  const SizedBox(height: 10),
                  _label('市 场'),
                  _market(v, 64),
                ])),
              ),
            ),
          ),
        ),
        if (player) ...[
          _label('  我的手牌'),
          SizedBox(height: 92, child: FittedBox(fit: BoxFit.scaleDown, child: _hand(v, 46))),
          const SizedBox(height: 4),
          SizedBox(
            height: 20,
            child: Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface)),
          ),
          SizedBox(height: 40, child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: btns)),
        ],
        DPanel(child: _playerInfo(context, v, player ? me : 0)),
        const SizedBox(height: 4),
        SizedBox(height: 46, child: DLog(dList<String>(v['recent']), max: 3)),
      ]),
    );
  }

  Widget _landscape(BuildContext context, Map<String, dynamic> v) {
    final (btns, hint) = _actions(v);
    final opp = player ? 1 - me : 1;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DPanel(child: _playerInfo(context, v, opp, showHandBacks: true)),
            const SizedBox(height: 8),
            Expanded(
              child: _felt(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _label('市 场'),
                _market(v, 78),
              ])),
            ),
            const SizedBox(height: 8),
            if (player) SizedBox(height: 104, child: Center(child: _hand(v, 58))),
            const SizedBox(height: 4),
            DPanel(child: _playerInfo(context, v, player ? me : 0)),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 300,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StatusBar(_status(v), highlight: _myTurn(v)),
            const SizedBox(height: 8),
            // short landscape windows: shrink the token piles rather than overflow
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: 310, child: _felt(_tokens(context, v, size: 30))),
              ),
            ),
            const SizedBox(height: 8),
            if (hint.isNotEmpty)
              Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: btns),
            const Spacer(),
            DPanel(child: SizedBox(width: double.infinity, height: 84, child: DLog(dList<String>(v['recent']), max: 5))),
          ]),
        ),
      ]),
    );
  }

  Widget? _banner(BuildContext context, Map<String, dynamic> v) {
    final phase = v['phase'];
    if (phase != 'roundEnd' && phase != 'over') return null;
    final rr = dMap(v['roundResult']);
    final ready = dList<Object?>(v['ready']);
    final resigned = dInt(v['resigned'], -1);
    final w = dInt(v['winner'], -1);
    String title;
    if (phase == 'over') {
      title = resigned >= 0 ? '${g.name(resigned)} 认输，${g.name(w)} 获胜' : (w == g.seat ? '你赢得了比赛！' : '${g.name(w)} 赢得比赛');
    } else {
      title = '第 ${dInt(rr['round'])} 局：${g.name(dInt(rr['winner']))} 获得印章';
    }
    final rows = dList<Object?>(rr['rows']);
    Widget? table;
    if (rows.length == 2) {
      List<String> row(int s) {
        final r = dMap(rows[s]);
        final b = dInts(r['bonus']);
        return [g.name(s), '${r['goods']}', b.isEmpty ? '0' : '${b.join('+')}=${r['bonusSum']}', '${r['herd']}→${r['camel']}', '${r['score']}'];
      }

      table = dTable(context, ['玩家', '货物币', '奖励币', '骆驼', '合计'], [row(0), row(1)], bold: [dInt(rr['winner'])]);
    }
    final canContinue = phase == 'roundEnd' && player && me < ready.length && ready[me] != true;
    return ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (rr.isNotEmpty) Text('${rr['why'] ?? ''}${rr['tie'] ?? ''}', style: const TextStyle(fontSize: 12)),
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
