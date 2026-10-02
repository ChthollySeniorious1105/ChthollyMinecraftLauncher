import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tr_common.dart';

/// Bridge-specific widgets: auction table, bidding box, score sheet, hand listing.

const List<String> brSeatNames = ['北', '东', '南', '西'];
const String brStrains = 'CDHSN';
const Map<String, String> brStrainSym = {'C': '♣', 'D': '♦', 'H': '♥', 'S': '♠', 'N': 'NT'};

Color brStrainColor(String s) => trRed(s) ? const Color(0xFFD32F2F) : (s == 'N' ? const Color(0xFF3949AB) : Colors.black87);

String brSide(int side) => side == 0 ? '南北' : '东西';

/// Rich text of a call.
Widget brCallText(String call, {double size = 14, Color? plain}) {
  if (call == 'P') return Text('不叫', style: TextStyle(fontSize: size * 0.9, color: plain ?? Colors.green.shade700));
  if (call == 'X') return Text('加倍', style: TextStyle(fontSize: size * 0.9, color: Colors.red.shade700, fontWeight: FontWeight.bold));
  if (call == 'XX') return Text('再加倍', style: TextStyle(fontSize: size * 0.9, color: Colors.blue.shade700, fontWeight: FontWeight.bold));
  return Text.rich(TextSpan(children: [
    TextSpan(text: call[0], style: TextStyle(color: plain ?? Colors.black87)),
    TextSpan(text: brStrainSym[call[1]], style: TextStyle(color: brStrainColor(call[1]))),
  ]), style: TextStyle(fontSize: size, fontWeight: FontWeight.bold));
}

/// Auction grid (columns 西 北 东 南 — rotated so the viewer's seat is last... we keep fixed N E S W).
class BrAuctionTable extends StatelessWidget {
  final List calls; // [{seat, call}]
  final int dealer;
  final int turn; // -1 when auction is over
  final List<bool> vul;
  final double cellW;
  const BrAuctionTable({super.key, required this.calls, required this.dealer, required this.turn, required this.vul, this.cellW = 54});

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[];
    var row = <Widget>[for (var i = 0; i < dealer; i++) const SizedBox()];
    for (final c in calls) {
      row.add(brCallText('${(c as Map)['call']}'));
      if (row.length == 4) {
        rows.add(row);
        row = [];
      }
    }
    if (turn >= 0) {
      row.add(Container(
        width: 26,
        height: 18,
        decoration: BoxDecoration(color: Colors.amber.shade300, borderRadius: BorderRadius.circular(5)),
        child: const Center(child: Text('?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87))),
      ));
    }
    if (row.isNotEmpty) rows.add(row);
    while (rows.isNotEmpty && rows.last.length < 4) {
      rows.last.add(const SizedBox());
    }
    Widget head(int s) {
      final v = vul[s % 2];
      return Container(
        width: cellW,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: v ? Colors.red.shade600 : Colors.green.shade600,
          borderRadius: BorderRadius.vertical(top: Radius.circular(s == 0 ? 8 : 0)),
        ),
        alignment: Alignment.center,
        child: Text('${brSeatNames[s]}${s == dealer ? '·发' : ''}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF7),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [for (var s = 0; s < 4; s++) head(s)]),
        for (final r in rows.length > 8 ? rows.sublist(rows.length - 8) : rows)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final w in r) SizedBox(width: cellW, height: 22, child: Center(child: w)),
          ]),
        if (rows.isEmpty) SizedBox(width: cellW * 4, height: 22),
        const SizedBox(height: 3),
      ]),
    );
  }
}

/// Bidding box: pick a level, then a strain; plus 不叫 / 加倍 / 再加倍.
class BrBiddingBox extends StatefulWidget {
  final List<String> legal;
  final void Function(String call) onCall;
  const BrBiddingBox({super.key, required this.legal, required this.onCall});
  @override
  State<BrBiddingBox> createState() => _BrBiddingBoxState();
}

class _BrBiddingBoxState extends State<BrBiddingBox> {
  int _level = 0;

  @override
  Widget build(BuildContext context) {
    final legal = widget.legal.toSet();
    int minLevel() {
      for (var l = 1; l <= 7; l++) {
        if (brStrains.split('').any((s) => legal.contains('$l$s'))) return l;
      }
      return 8;
    }

    final lo = minLevel();
    var level = _level;
    if (level < lo || level > 7) level = lo <= 7 ? lo : 0;

    Widget btn(Widget child, bool enabled, VoidCallback onTap, {Color? bg, bool sel = false, double w = 40}) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: !enabled ? Colors.grey.shade400 : (sel ? Colors.amber.shade400 : (bg ?? const Color(0xFFFFFDF7))),
          borderRadius: BorderRadius.circular(7),
          elevation: enabled ? 2 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: enabled ? onTap : null,
            child: SizedBox(width: w, height: 34, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child))),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var l = 1; l <= 7; l++)
            btn(Text('$l', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)), l >= lo,
                () => setState(() => _level = l),
                sel: l == level, w: 34),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (final s in brStrains.split(''))
            btn(
              Text.rich(TextSpan(children: [
                TextSpan(text: level > 0 ? '$level' : '', style: const TextStyle(color: Colors.black87)),
                TextSpan(text: brStrainSym[s], style: TextStyle(color: brStrainColor(s))),
              ]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              level > 0 && legal.contains('$level$s'),
              () => widget.onCall('$level$s'),
              w: 47,
            ),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          btn(const Text('不叫', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), legal.contains('P'),
              () => widget.onCall('P'),
              bg: Colors.green.shade600, w: 78),
          btn(const Text('加倍', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), legal.contains('X'),
              () => widget.onCall('X'),
              bg: Colors.red.shade600, w: 78),
          btn(const Text('再加倍', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), legal.contains('XX'),
              () => widget.onCall('XX'),
              bg: Colors.blue.shade600, w: 78),
        ]),
      ]),
    );
  }
}

/// One hand as text rows "♠ A K 5".
Widget brHandText(List<String> cards, {double size = 13}) {
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final s in trDispSuits)
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${trSym[s]} ', style: TextStyle(color: brStrainColor(s))),
          TextSpan(
              text: [for (final c in cards) if (c[1] == s) c[0] == 'T' ? '10' : c[0]].join(' ').ifEmpty('—')),
        ]),
        style: TextStyle(fontSize: size, height: 1.25),
      ),
  ]);
}

extension _Empty on String {
  String ifEmpty(String d) => isEmpty ? d : this;
}

/// Rubber-bridge score sheet ("我们/他们" style with the line) or Chicago list.
Widget brScoreSheet(BuildContext context, Map<String, dynamic> v, String Function(int) name) {
  final cs = Theme.of(context).colorScheme;
  final mode = '${v['mode']}';
  final sheet = (v['sheet'] as List?) ?? const [];
  final totals = [for (final x in (v['totals'] as List? ?? const [0, 0])) (x as num).toInt()];
  final hist = (v['history'] as List?) ?? const [];
  final st = TextStyle(fontSize: 13, color: cs.onSurface);
  Widget col(int side) {
    final above = [for (final e in sheet) if ((e as Map)['side'] == side && e['line'] == 'above') e].reversed.toList();
    final below = [for (final e in sheet) if ((e as Map)['side'] == side && e['line'] == 'below') e];
    Widget item(Map e) => Text('${e['pts']}  ${e['label']}', style: st);
    final games = <int, List<Map>>{};
    for (final e in below) {
      games.putIfAbsent(e['game'] as int, () => []).add(e);
    }
    final gameIds = games.keys.toList()..sort();
    return SizedBox(
      width: 150,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(brSide(side), style: st.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        for (final e in above.take(10)) item(e),
        if (above.isEmpty) Text('—', style: st),
        Container(height: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: cs.primary),
        for (final gId in gameIds) ...[
          for (final e in games[gId]!) item(e),
          Container(height: 1, width: 80, margin: const EdgeInsets.symmetric(vertical: 2), color: cs.outline),
        ],
        if (below.isEmpty) Text('—', style: st),
        const SizedBox(height: 4),
        Text('合计 ${totals[side]}', style: st.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
      ]),
    );
  }

  if (mode == 'chicago') {
    final rows = <List<String>>[
      for (final h in hist)
        [
          '${(h as Map)['no']}',
          '${brSeatNames[h['declarer'] as int]} ${h['contract']}',
          (h['diff'] as int) >= 0 ? ((h['diff'] as int) == 0 ? '=' : '+${h['diff']}') : '${h['diff']}',
          '${h['ns']}',
          '${h['ew']}',
        ],
      ['合计', '', '', '${totals[0]}', '${totals[1]}'],
    ];
    return trGrid(['副', '定约', '结果', '南北', '东西'], rows, colW: 72, style: st);
  }
  return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    col(0),
    Container(width: 2, height: 160, color: cs.primary),
    col(1),
  ]);
}

/// Chip describing vulnerability.
Widget brVulChip(List<bool> vul) {
  final t = vul[0] && vul[1]
      ? '双方有局'
      : vul[0]
          ? '南北有局'
          : vul[1]
              ? '东西有局'
              : '双方无局';
  return trChip(t, vul[0] || vul[1] ? Colors.red.shade700 : Colors.green.shade700);
}

/// Contract chip e.g. "4♥ X · 庄 南".
Widget brContractChip(Map c) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFFFFDF7), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('定约 ', style: TextStyle(fontSize: 13, color: Colors.black87)),
      brCallText('${c['level']}${c['strain']}', size: 14),
      if ((c['doubled'] as num) > 0)
        Text((c['doubled'] as num) == 1 ? ' X' : ' XX', style: TextStyle(fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
      Text(' · 庄 ${brSeatNames[c['declarer'] as int]}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
    ]),
  );
}

/// Wrap the board-level [GameContext] name helper for seat labels.
String brSeatLabel(GameContext g, int s) => '${brSeatNames[s]} · ${g.name(s)}';
