import 'package:aurora_shared/games/bang/bang_cards.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'bg_widgets.dart';

const _brown = Color(0xFF8D5A2B);
const _blue = Color(0xFF1565C0);

const Map<String, Color> _roleColor = {
  'sheriff': Color(0xFFF9A825),
  'deputy': Color(0xFF1E88E5),
  'outlaw': Color(0xFFC62828),
  'renegade': Color(0xFF6A1B9A),
};

/// One Bang! card drawn from scratch: suit/rank corner, emoji, name; blue or brown border.
class BangCardW extends StatelessWidget {
  final int id;
  final double w;
  final bool glow;
  final bool selected;
  final bool dim;
  const BangCardW(this.id, {super.key, this.w = 56, this.glow = false, this.selected = false, this.dim = false});

  @override
  Widget build(BuildContext context) {
    if (id < 0 || id >= bangDeck.length) {
      return Container(
        width: w,
        height: w * 1.4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.1),
          gradient: const LinearGradient(colors: [Color(0xFF6D4C41), Color(0xFF3E2723)]),
          border: Border.all(color: const Color(0xFFFFCC80), width: 1.5),
        ),
        alignment: Alignment.center,
        child: FittedBox(child: Padding(padding: const EdgeInsets.all(4), child: bgEmoji('🤠', w * 0.45))),
      );
    }
    final c = bangDeck[id];
    final blue = bangBlueKinds.contains(c.kind);
    final red = c.suit == 'H' || c.suit == 'D';
    final border = blue ? _blue : _brown;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Container(
        width: w,
        height: w * 1.4,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(w * 0.1),
          border: Border.all(color: selected ? Colors.amber : border, width: selected ? 3 : w * 0.06),
          boxShadow: [
            if (glow) const BoxShadow(color: Colors.lightGreenAccent, blurRadius: 8, spreadRadius: 1.5),
            if (selected) const BoxShadow(color: Colors.amberAccent, blurRadius: 10, spreadRadius: 2),
            const BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2)),
          ],
        ),
        child: Stack(children: [
          Positioned(
            left: w * 0.06,
            top: w * 0.03,
            child: Text('${bangRankLabel(c.rank)}${bangSuitSym[c.suit]}',
                style: TextStyle(
                    fontSize: w * 0.2, fontWeight: FontWeight.bold, color: red ? Colors.red.shade700 : Colors.black87, fontFamilyFallback: kFontFallback)),
          ),
          Positioned.fill(
            top: w * 0.22,
            bottom: w * 0.32,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: bgEmoji(bangKindEmoji[c.kind] ?? '?', w * 0.48))),
          ),
          Positioned(
            left: 2,
            right: 2,
            bottom: w * 0.05,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(w * 0.06)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(' ${bangKindName[c.kind]} ',
                    style: TextStyle(fontSize: w * 0.19, color: Colors.white, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 西部无间道
class BangBoard extends StatefulWidget {
  final GameContext g;
  const BangBoard(this.g, {super.key});
  @override
  State<BangBoard> createState() => _BangBoardState();
}

class _BangBoardState extends State<BangBoard> {
  int _sel = -1;
  int _target = -1;
  final Set<int> _multi = {};
  bool _sidMode = false;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<Map> get _ps => [for (final p in (v['players'] as List)) p as Map];

  void _reset() {
    _sel = -1;
    _target = -1;
    _multi.clear();
    _sidMode = false;
  }

  @override
  Widget build(BuildContext context) {
    final me = g.seat;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = bgInt(v['turn']);
    final hand = bgInts(v['hand']);
    final ps = _ps;
    final waiting = bgInts(v['waiting']);
    final myWait = !over && me >= 0 && waiting.contains(me);
    final playable = <int, List<int>>{
      for (final p in (v['playable'] as List? ?? const [])) bgInt((p as Map)['card']): bgInts(p['targets']),
    };
    final respond = bgInts(v['respondCards']);
    final discardNeed = bgInt(v['discardNeed'], 0);
    final myPlay = myWait && phase == 'play';
    final myRespond = myWait && phase == 'respond';
    final myDiscard = myWait && phase == 'discard';

    if (!myPlay) {
      _sel = -1;
      _target = -1;
      _sidMode = false;
    }
    if (!myDiscard && !_sidMode) _multi.clear();
    if (_sel >= 0 && !playable.containsKey(_sel)) {
      _sel = -1;
      _target = -1;
    }
    _multi.removeWhere((c) => !hand.contains(c));
    final targets = _sel >= 0 ? playable[_sel]! : const <int>[];
    if (!targets.contains(_target)) _target = -1;

    final status = _status(phase, turn, me, myPlay, myRespond, myDiscard, discardNeed, targets);
    final others = g.seatsFromMe().where((s) => s != me).toList();
    final logs = [for (final l in (v['log'] as List? ?? const [])) '$l'];

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        final rows = others.length > (narrow ? 2 : 4) ? 2 : 1;
        final panelH = (c.maxHeight * (rows == 2 ? 0.3 : 0.26)).clamp(84.0, 240.0).toDouble();
        final cardW = [c.maxHeight * 0.1, c.maxWidth / 6.2].reduce((a, b) => a < b ? a : b).clamp(40.0, 74.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: bgPanelGrid([for (final s in others) _panel(s, ps[s], turn, targets.contains(s), me)], rows, panelH),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : c.maxWidth * 0.05, vertical: 3),
                child: BgFelt(felt: Color.lerp(g.table, const Color(0xFF8D6E3F), 0.45)!, child: _center(logs, me, phase, turn, targets)),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: StatusBar(status, highlight: myWait)),
            const SizedBox(height: 3),
            if (me >= 0) ...[
              _myBar(me, ps[me], turn, myPlay, myRespond, myDiscard, discardNeed, playable, targets),
              const SizedBox(height: 2),
              _hand(hand, cardW, c.maxWidth - 12, playable, respond, myPlay, myRespond, myDiscard),
            ],
            const SizedBox(height: 6),
          ]),
          if (over) Center(child: _result()),
        ]);
      }),
    );
  }

  String _status(String phase, int turn, int me, bool myPlay, bool myRespond, bool myDiscard, int need, List<int> targets) {
    final rtype = '${v['rtype']}';
    final rsrc = bgInt(v['rsrc']);
    final responder = bgInt(v['responder']);
    if (phase == 'over') return '游戏结束';
    if (myDiscard) return '手牌超过生命值：请弃掉 $need 张牌（已选 ${_multi.length}）';
    if (myRespond) {
      return switch (rtype) {
        'shot' => '${g.name(rsrc)} 向你开枪！打出闪避（还需 ${v['rneed']} 张）或承受伤害',
        'indians' => '印第安人来袭！弃一张 BANG! 或失去 1 点生命',
        'duel' => '决斗中！打出一张 BANG! 或认输失去 1 点生命',
        _ => '请回应',
      };
    }
    if (phase == 'store') return responder == me ? '杂货铺：挑一张你想要的牌' : '杂货铺：等待 ${g.name(responder)} 挑牌';
    if (phase == 'drawchoice') return turn == me ? '摸牌阶段：选择摸牌方式' : '${g.name(turn)} 正在选择摸牌方式';
    if (myPlay) {
      if (_sidMode) return '席德·凯臣：选 2 张手牌弃掉，回复 1 点生命';
      if (_sel < 0) return '你的回合：点亮的牌可以打出，打完点“结束回合”';
      if (targets.isNotEmpty && _target < 0) return '选择 ${bangKindName[bangDeck[_sel].kind]} 的目标（点玩家面板）';
      return '确认打出 ${bangCardLabel(_sel)}';
    }
    if (phase == 'respond') return '等待 ${g.name(responder)} 回应';
    if (phase == 'discard') return '${g.name(turn)} 正在弃牌';
    return '${g.name(turn)} 的回合';
  }

  Widget _hpRow(int hp, int maxHp, {double size = 13}) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < maxHp; i++)
          Padding(
            padding: const EdgeInsets.only(right: 1.5),
            child: Text(i < hp ? '❤️' : '🖤', style: TextStyle(fontSize: size, fontFamilyFallback: kFontFallback)),
          ),
      ]);

  Widget _roleBadge(String? role, {double fs = 11}) {
    if (role == null) return bgChip('身份 ?', Colors.grey.shade700, fontSize: fs);
    return bgChip('${bangRoleEmoji[role]} ${bangRoleName[role]}', _roleColor[role]!, fontSize: fs);
  }

  Widget _equipRow(List<int> eq, {double w = 34}) => Wrap(spacing: 3, runSpacing: 3, children: [
        for (final c in eq)
          Tooltip(
            message: '${bangCardLabel(c)}：${bangKindDesc[bangDeck[c].kind]}',
            child: BangCardW(c, w: w),
          ),
      ]);

  Widget _charLine(int ch, {double fs = 12}) {
    if (ch < 0) return Text('无角色', style: TextStyle(fontSize: fs, color: Colors.grey));
    final c = bangChars[ch];
    return Tooltip(
      message: c.desc,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        bgEmoji(c.emoji, fs + 4),
        const SizedBox(width: 2),
        Text(c.name, style: TextStyle(fontSize: fs, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback)),
      ]),
    );
  }

  Widget _panel(int s, Map p, int turn, bool pickable, int me) {
    final alive = p['alive'] == true;
    final eq = bgInts(p['equip']);
    final dist = p['dist'];
    final ch = bgInt(p['char']);
    return bgPanel(context,
        active: s == turn && alive,
        picked: s == _target,
        pickable: pickable,
        dead: !alive,
        onTap: pickable ? () => setState(() => _target = s) : null,
        child: SizedBox(
          width: 190,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: g.tag(s, active: s == turn && alive, size: 28, sub: alive ? '手牌 ${p['hand']} · 射程 ${p['range']}' : '已死亡')),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _charLine(ch))),
              _roleBadge(p['role'] as String?),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              alive ? _hpRow(bgInt(p['hp'], 0), bgInt(p['maxHp'], 4)) : const Text('☠️', style: TextStyle(fontSize: 14, fontFamilyFallback: kFontFallback)),
              const Spacer(),
              if (alive && dist is num && me >= 0) bgChip('距离 $dist', Colors.brown.shade600, fontSize: 10),
            ]),
            if (eq.isNotEmpty) ...[const SizedBox(height: 3), _equipRow(eq, w: 30)],
          ]),
        ));
  }

  Widget _center(List<String> logs, int me, String phase, int turn, List<int> targets) {
    final store = bgInts(v['store']);
    final kit = bgInts(v['kit']);
    final responder = bgInt(v['responder']);
    final rcard = bgInt(v['rcard']);
    final deck = bgInt(v['deck'], 0);
    final top = bgInt(v['discardTop']);
    return LayoutBuilder(builder: (context, fc) {
      final cw = (fc.maxHeight * 0.3).clamp(30.0, 66.0).toDouble();
      Widget? action;
      if (phase == 'store' && store.isNotEmpty) {
        action = _cardChoice('杂货铺', store, cw, responder == me ? (c) => g.act({'type': 'pick', 'card': c}) : null);
      } else if (phase == 'drawchoice' && turn == me) {
        action = _drawChoice(kit, cw);
      } else if (_sel >= 0 && _target >= 0 && const {'panic', 'catbalou'}.contains(bangDeck[_sel].kind)) {
        action = _pickChoice(cw);
      } else if (phase == 'respond' && rcard >= 0) {
        final src = bgInt(v['rsrc']);
        action = Row(mainAxisSize: MainAxisSize.min, children: [
          BangCardW(rcard, w: cw),
          const SizedBox(width: 10),
          Text('${g.name(src)} → ${g.name(responder)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ]);
      }
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                BangCardW(-1, w: cw * 0.8),
                const SizedBox(width: 6),
                top >= 0 ? BangCardW(top, w: cw * 0.8) : SizedBox(width: cw * 0.8),
              ]),
              const SizedBox(height: 3),
              Text('牌堆 $deck', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: action != null
                ? Center(child: FittedBox(fit: BoxFit.scaleDown, child: action))
                : ClipRect(child: Align(alignment: Alignment.centerLeft, child: bgLog(logs, max: ((fc.maxHeight - 20) / 19).floor().clamp(1, 7), fontSize: 12.5))),
          ),
        ]),
      );
    });
  }

  Widget _cardChoice(String title, List<int> cards, double cw, void Function(int c)? onPick) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(onTap: onPick == null ? null : () => onPick(c), child: BangCardW(c, w: cw, glow: onPick != null)),
            ),
        ]),
      ]);

  Widget _drawChoice(List<int> kit, double cw) {
    if (kit.isNotEmpty) return _cardChoice('基特·卡尔森：点一张放回牌堆顶，另外两张收入手牌', kit, cw, (c) => g.act({'type': 'draw', 'back': c}));
    final jesse = bgInts(v['drawJesse']);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('摸牌：第一张从哪里拿？', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        FilledButton(onPressed: () => g.act({'type': 'draw', 'src': 'deck'}), child: const Text('牌堆摸 2 张')),
        if (v['drawPedro'] == true)
          FilledButton.tonal(onPressed: () => g.act({'type': 'draw', 'src': 'discard'}), child: Text('拿弃牌堆顶 ${bangCardLabel(bgInt(v['discardTop']))}')),
        for (final t in jesse) FilledButton.tonal(onPressed: () => g.act({'type': 'draw', 'src': t}), child: Text('抽 ${g.name(t)} 的手牌')),
      ]),
    ]);
  }

  Widget _pickChoice(double cw) {
    final p = _ps[_target];
    final eq = bgInts(p['equip']);
    final hn = bgInt(p['hand'], 0);
    void go(int pick) {
      g.act({'type': 'play', 'card': _sel, 'target': _target, 'pick': pick});
      setState(_reset);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${bangKindName[bangDeck[_sel].kind]}：选择 ${g.name(_target)} 的哪张牌', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (hn > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(onTap: () => go(-1), child: Column(children: [BangCardW(-1, w: cw), const Text('随机手牌', style: TextStyle(color: Colors.white, fontSize: 11))])),
          ),
        for (final c in eq)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(onTap: () => go(c), child: Column(children: [BangCardW(c, w: cw, glow: true), const Text('装备', style: TextStyle(color: Colors.white, fontSize: 11))])),
          ),
      ]),
    ]);
  }

  Widget _myBar(int me, Map p, int turn, bool myPlay, bool myRespond, bool myDiscard, int need, Map<int, List<int>> playable, List<int> targets) {
    final eq = bgInts(p['equip']);
    final alive = p['alive'] == true;
    final buttons = <Widget>[];
    if (myPlay) {
      if (_sidMode) {
        buttons.add(FilledButton(
          onPressed: _multi.length == 2
              ? () {
                  g.act({'type': 'sid', 'cards': _multi.toList()});
                  setState(_reset);
                }
              : null,
          child: const Text('弃 2 张回血'),
        ));
        buttons.add(TextButton(onPressed: () => setState(_reset), child: const Text('取消')));
      } else {
        final kind = _sel >= 0 ? bangDeck[_sel].kind : '';
        final needsPick = const {'panic', 'catbalou'}.contains(kind);
        final ready = _sel >= 0 && (targets.isEmpty || (_target >= 0 && !needsPick));
        if (_sel >= 0) {
          buttons.add(FilledButton.icon(
            onPressed: ready
                ? () {
                    g.act({'type': 'play', 'card': _sel, if (_target >= 0) 'target': _target, 'pick': -1});
                    setState(_reset);
                  }
                : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(_target >= 0 ? '对 ${g.name(_target)} 打出' : '打出'),
          ));
        }
        if (v['canSid'] == true) {
          buttons.add(OutlinedButton(onPressed: () => setState(() {
                _reset();
                _sidMode = true;
              }), child: const Text('席德回血')));
        }
        buttons.add(FilledButton.tonal(onPressed: () {
          g.act({'type': 'end'});
          setState(_reset);
        }, child: const Text('结束回合')));
      }
    } else if (myRespond) {
      buttons.add(FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
        onPressed: () => g.act({'type': 'take'}),
        child: Text(v['rtype'] == 'duel' ? '认输 -1 生命' : '承受 -1 生命'),
      ));
    } else if (myDiscard) {
      buttons.add(FilledButton(
        onPressed: _multi.length == need
            ? () {
                g.act({'type': 'discard', 'cards': _multi.toList()});
                setState(_reset);
              }
            : null,
        child: Text('弃牌 ${_multi.length}/$need'),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          g.tag(me, active: me == turn && alive, size: 30, sub: alive ? '射程 ${p['range']}' : '已死亡'),
          const SizedBox(width: 6),
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [_charLine(bgInt(p['char'])), const SizedBox(width: 6), _roleBadge(p['role'] as String?)]),
            const SizedBox(height: 2),
            _hpRow(bgInt(p['hp'], 0), bgInt(p['maxHp'], 4), size: 15),
          ]),
          if (eq.isNotEmpty) ...[const SizedBox(width: 8), Row(mainAxisSize: MainAxisSize.min, children: [for (final c in eq) Padding(padding: const EdgeInsets.only(right: 3), child: BangCardW(c, w: 32))])],
          for (final b in buttons) ...[const SizedBox(width: 6), b],
        ]),
      ),
    );
  }

  Widget _hand(List<int> hand, double cw, double maxW, Map<int, List<int>> playable, List<int> respond, bool myPlay, bool myRespond, bool myDiscard) {
    final n = hand.length;
    if (n == 0) return SizedBox(height: cw * 1.4 + 10, child: const Center(child: Text('没有手牌', style: TextStyle(color: Colors.white70))));
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.3, cw * 1.06).toDouble();
    final total = cw + step * (n - 1);
    return SizedBox(
      width: total,
      height: cw * 1.4 + 10,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < n; i++)
          () {
            final c = hand[i];
            final multiMode = myDiscard || _sidMode;
            final can = multiMode || (myPlay && playable.containsKey(c)) || (myRespond && respond.contains(c));
            final sel = multiMode ? _multi.contains(c) : c == _sel;
            return Positioned(
              left: step * i,
              top: sel ? 0 : 10,
              child: Tooltip(
                message: '${bangCardLabel(c)}：${bangKindDesc[bangDeck[c].kind]}',
                waitDuration: const Duration(milliseconds: 600),
                child: GestureDetector(
                  onTap: !can
                      ? null
                      : () {
                          if (myRespond) {
                            g.act({'type': 'respond', 'card': c});
                            return;
                          }
                          setState(() {
                            if (multiMode) {
                              if (!_multi.remove(c)) _multi.add(c);
                            } else {
                              _sel = _sel == c ? -1 : c;
                              _target = -1;
                              final t = _sel >= 0 ? playable[_sel]! : const <int>[];
                              if (t.length == 1) _target = t.first;
                            }
                          });
                        },
                  child: BangCardW(c, w: cw, glow: can && !sel && !multiMode, selected: sel, dim: (myPlay || myRespond) && !can),
                ),
              ),
            );
          }(),
      ]),
    );
  }

  Widget _result() {
    final res = v['result'] as Map?;
    if (res == null) return const SizedBox();
    final winners = bgInts(res['winners']);
    final roles = [for (final r in (res['roles'] as List)) '$r'];
    final pl = [for (var s = 0; s < g.players; s++) winners.contains(s) ? 1 : 2];
    final wr = winners.isEmpty ? '' : roles[winners.first];
    final title = switch (wr) {
      'sheriff' || 'deputy' => '⭐ 警长阵营获胜！',
      'outlaw' => '🦹 歹徒获胜！',
      'renegade' => '🐍 叛徒获胜！',
      _ => '游戏结束',
    };
    return bgResult(g, title, pl, (s) {
      final ch = bgInt(_ps[s]['char']);
      return '${bangRoleEmoji[roles[s]]}${bangRoleName[roles[s]]} · ${ch >= 0 ? bangChars[ch].name : ''}';
    });
  }
}
