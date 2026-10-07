import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Shared helpers for the arcade2 boards.

int aInt(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> aInts(Object? o) => o is List ? [for (final e in o) aInt(e)] : <int>[];
Map<String, dynamic>? aMap(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
List<Map<String, dynamic>> aMaps(Object? o) =>
    o is List ? [for (final e in o) if (e is Map) e.cast<String, dynamic>()] : <Map<String, dynamic>>[];
String aStr(Object? o) => o is String ? o : '';

String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Top status line, scaled down when narrow.
Widget aStatus(String text, {bool highlight = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(text, highlight: highlight)),
    );

/// Final ranking banner (rows of {'s', 'rank', ...}), scrollable if needed.
Widget aRanking(GameContext g, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) sub) {
  final me = rows.where((r) => r['s'] == g.seat).firstOrNull;
  final title = me == null ? '游戏结束' : (me['rank'] == 1 ? '你赢了！' : '游戏结束 · 你是第 ${me['rank']} 名');
  return Align(
    alignment: Alignment.center,
    child: SingleChildScrollView(
      child: ResultBanner(
        title,
        child: Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final r in rows)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(r['rank'] == 1 ? '🏆 ' : '#${r['rank']} ', style: const TextStyle(fontWeight: FontWeight.bold)),
              Flexible(child: g.tag(aInt(r['s']), size: 26, sub: sub(r), active: r['rank'] == 1)),
            ]),
        ]),
      ),
    ),
  );
}
