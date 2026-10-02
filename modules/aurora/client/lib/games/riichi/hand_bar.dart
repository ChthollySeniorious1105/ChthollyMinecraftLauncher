import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import 'tile_widgets.dart';

/// Bottom area: my hand, my melds and Mahjong-Soul style action buttons.
class RiichiHandBar extends StatefulWidget {
  final GameContext g;
  final Map v;
  final double tileW;
  const RiichiHandBar({super.key, required this.g, required this.v, required this.tileW});
  @override
  State<RiichiHandBar> createState() => _RiichiHandBarState();
}

class _RiichiHandBarState extends State<RiichiHandBar> {
  bool riichiMode = false;
  bool darkMode = false;
  String? subMenu; // 'chi' | 'kan' | 'pon'
  final Set<int> exch = {};
  String _stateKey = '';
  final _auto = MjAutoRunner();

  @override
  void initState() {
    super.initState();
    for (final n in [MjAutoState.autoWin, MjAutoState.noCall, MjAutoState.tsumogiri]) {
      n.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    for (final n in [MjAutoState.autoWin, MjAutoState.noCall, MjAutoState.tsumogiri]) {
      n.removeListener(_rebuild);
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// 雀魂 auto toggles: win automatically, skip calls, tsumogiri.
  void _autoPlay(Map v, Map<String, dynamic> me, bool myTurn, String phase, int drawnId, Set<int> discardable) {
    final key = '$phase|${v['turn']}|${v['last']?['seq']}|$drawnId';
    final c = (me['call'] as Map?)?.cast<String, dynamic>();
    if (MjAutoState.autoWin.value) {
      if (myTurn && me['tsumo'] == true) return _auto.run('$key|tsumo', () => g.act({'t': 'tsumo'}));
      if (c != null && c['ron'] == true) return _auto.run('$key|ron', () => g.act({'t': 'ron'}));
    }
    if (c != null && c['ron'] != true && MjAutoState.noCall.value) {
      return _auto.run('$key|skip', () => g.act({'t': 'skip'}), delayMs: 250);
    }
    if (myTurn && MjAutoState.tsumogiri.value && drawnId >= 0 && discardable.contains(drawnId) && me['tsumo'] != true) {
      _auto.run('$key|giri', () => g.act({'t': 'discard', 'tile': drawnId}), delayMs: 600);
    }
  }

  GameContext get g => widget.g;

  void _resetIfChanged(String key) {
    if (key != _stateKey) {
      _stateKey = key;
      riichiMode = false;
      subMenu = null;
      if (!key.startsWith('exchange')) exch.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final me = (v['me'] as Map?)?.cast<String, dynamic>();
    if (me == null) {
      return const Center(child: Text('观战中', style: TextStyle(color: Colors.white70)));
    }
    final phase = v['phase'] as String;
    final seat = (v['seats'] as List)[g.seat] as Map;
    final n = (v['n'] as num).toInt();
    final hand = (me['hand'] as List).cast<Map>();
    final drawnId = (me['drawnId'] as num?)?.toInt() ?? -1;
    final myTurn = phase == 'turn' && (v['turn'] as num).toInt() == g.seat;
    _resetIfChanged('$phase|${v['turn']}|${hand.length}|${(seat['river'] as List).length}|$drawnId');
    final discardable = ((me['discardable'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    final riichiIds0 = ((me['riichi'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    _autoPlay(v, me, myTurn, phase, drawnId, riichiIds0.isEmpty ? discardable : const {});
    final riichiIds = ((me['riichi'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    final tw = widget.tileW;

    final exchanging = phase == 'exchange' && me['exchPicked'] != true;
    // Order: drawn tile last.
    final ordered = [...hand.where((t) => (t['id'] as num).toInt() != drawnId), ...hand.where((t) => (t['id'] as num).toInt() == drawnId)];
    final melds = (seat['melds'] as List).cast<Map>();
    final kita = (seat['kita'] as List).cast<String>();

    final handRow = MjHand(
      tileWidth: tw,
      active: myTurn,
      selectedIds: exchanging ? exch.cast<Object>() : const {},
      onToggle: exchanging
          ? (id) {
              final t = hand.firstWhere((t) => t['id'] == id);
              if ((t['c'] as String).startsWith('W')) return;
              setState(() {
                if (!exch.remove(id as int) && exch.length < 3) exch.add(id);
              });
            }
          : null,
      onDiscard: (id) {
        g.act({'t': 'discard', 'tile': id, if (riichiMode) 'riichi': true, if (darkMode) 'dark': true});
        setState(() {
          riichiMode = false;
          darkMode = false;
        });
      },
      tiles: [
        for (final t in ordered)
          MjHandTile(
            id: (t['id'] as num).toInt(),
            drawn: (t['id'] as num).toInt() == drawnId,
            enabled: riichiMode ? riichiIds.contains((t['id'] as num).toInt()) : discardable.contains((t['id'] as num).toInt()),
            marked: riichiMode && riichiIds.contains((t['id'] as num).toInt()),
            tile: (w, {dim = false}) => RTile(t['c'] as String, width: w, glass: t['glass'] == true, dim: dim),
          ),
      ],
      trailing: [
        if (kita.isNotEmpty) ...[SizedBox(width: tw * 0.5), for (final k in kita) RTile(k, width: tw * 0.75)],
        ...mjMelds('me', [for (final m in melds) MeldView(m, owner: g.seat, players: n, width: tw * 0.8)], gap: tw * 0.35),
      ],
    );

    final buttons = _buttons(context, v, me, myTurn, phase, riichiIds);
    final waits = (me['waits'] as List?)?.cast<String>() ?? const [];
    return Stack(children: [
      const Positioned(left: 8, top: 0, bottom: 0, child: Center(child: Opacity(opacity: 0.95, child: MjAutoToggles()))),
      Positioned.fill(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (buttons.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6, right: 12, left: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: MjActionBar(actions: buttons, scale: (tw / 44).clamp(0.75, 1.2)),
          ),
        ),
      if (waits.isNotEmpty && !myTurn)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(me['furiten'] == true ? '振听 听：' : '听：',
                style: TextStyle(color: me['furiten'] == true ? Colors.redAccent : Colors.white, fontSize: 12)),
            for (final w in waits.take(13)) RTile(w, width: 14),
          ]),
        ),
      Padding(padding: const EdgeInsets.only(bottom: 4), child: handRow),
    ])),
    ]);
  }

  List<MjAction> _buttons(BuildContext context, Map v, Map<String, dynamic> me, bool myTurn, String phase, Set<int> riichiIds) {
    final out = <MjAction>[];
    Row tiles(List<String> cs) => Row(mainAxisSize: MainAxisSize.min, children: [for (final t in cs) RTile(t, width: 18)]);
    if (phase == 'exchange' && me['exchPicked'] != true) {
      out.add(MjAction.call('换三张 ${exch.length}/3', () {
        if (exch.length != 3) return;
        g.act({'t': 'exchange', 'tiles': exch.toList()});
      }));
      return out;
    }
    if (myTurn) {
      if (subMenu == 'kan') {
        for (final k in (me['ankan'] as List).cast<Map>()) {
          out.add(MjAction.kan('暗杠', () => g.act({'t': 'ankan', 'kind': k['kind']}), preview: tiles([k['c'] as String])));
        }
        for (final k in (me['kakan'] as List).cast<Map>()) {
          out.add(MjAction.kan('加杠', () => g.act({'t': 'kakan', 'kind': k['kind']}), preview: tiles([k['c'] as String])));
        }
        out.add(MjAction.skip(() => setState(() => subMenu = null), '返回'));
        return out;
      }
      if (me['tsumo'] == true) out.add(MjAction.win('自摸', () => g.act({'t': 'tsumo'})));
      if (riichiIds.isNotEmpty) {
        out.add(MjAction.riichi(riichiMode ? '取消' : '立直', () => setState(() {
              riichiMode = !riichiMode;
                    })));
      }
      final kans = (me['ankan'] as List).length + (me['kakan'] as List).length;
      if (kans > 0) {
        out.add(MjAction.kan('杠', () {
          final a = (me['ankan'] as List).cast<Map>(), b = (me['kakan'] as List).cast<Map>();
          if (kans == 1) {
            if (a.isNotEmpty) {
              g.act({'t': 'ankan', 'kind': a.first['kind']});
            } else {
              g.act({'t': 'kakan', 'kind': b.first['kind']});
            }
          } else {
            setState(() => subMenu = 'kan');
          }
        }));
      }
      if (me['kita'] == true) out.add(MjAction.call('拔北', () => g.act({'t': 'kita'})));
      if (me['kyuushu'] == true) out.add(MjAction.skip(() => g.act({'t': 'kyuushu'}), '九种九牌'));
      if (me['canDark'] == true) {
        out.add(MjAction(darkMode ? '暗牌：开' : '暗牌：关', darkMode ? Colors.deepPurple : MjColors.skip, () => setState(() => darkMode = !darkMode)));
      }
      return out;
    }
    final c = (me['call'] as Map?)?.cast<String, dynamic>();
    if (c != null) {
      final chi = (c['chi'] as List).cast<Map>();
      final pon = (c['pon'] as List).cast<Map>();
      if (subMenu == 'chi' || subMenu == 'pon') {
        final list = subMenu == 'chi' ? chi : pon;
        for (final o in list) {
          out.add(MjAction.call(subMenu == 'chi' ? '吃' : '碰', () => g.act({'t': subMenu, 'tiles': o['ids']}),
              preview: tiles((o['c'] as List).cast<String>())));
        }
        out.add(MjAction.skip(() => setState(() => subMenu = null), '返回'));
        return out;
      }
      if (c['ron'] == true) {
        out.add(MjAction.win(v['phase'] == 'chankan' && v['respKind'] != 'kita' ? '抢杠' : '荣和', () => g.act({'t': 'ron'})));
      }
      if (chi.isNotEmpty) {
        out.add(MjAction.call('吃', () {
          if (chi.length == 1) {
            g.act({'t': 'chi', 'tiles': chi.first['ids']});
          } else {
            setState(() => subMenu = 'chi');
          }
        }));
      }
      if (pon.isNotEmpty) {
        out.add(MjAction.call('碰', () {
          if (pon.length == 1) {
            g.act({'t': 'pon', 'tiles': pon.first['ids']});
          } else {
            setState(() => subMenu = 'pon');
          }
        }));
      }
      if (c['kan'] == true) out.add(MjAction.kan('杠', () => g.act({'t': 'kan'})));
      out.add(MjAction.skip(() => g.act({'t': 'skip'})));
      return out;
    }
    if (me['canOpen'] == true) {
      out.add(MjAction('开牌 2000', Colors.deepPurple, () => g.act({'t': 'open'})));
      out.add(MjAction.skip(() => g.act({'t': 'skip'})));
    }
    if (me['canLock'] == true) {
      out.add(MjAction('锁定 4000', Colors.deepPurple, () => g.act({'t': 'lock'})));
      out.add(MjAction.skip(() => g.act({'t': 'nolock'}), '不锁定'));
    }
    return out;
  }
}
