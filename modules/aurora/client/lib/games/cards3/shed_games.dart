import 'package:aurora_shared/games/cards3/gdy_rules.dart';
import 'package:aurora_shared/games/cards3/shed_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c3_widgets.dart';
import 'shed_board.dart';

// ---------------- 干瞪眼 ----------------

GdyCombo? _gdyTable(Map<String, dynamic> v) => v['lead'] == true ? null : GdyCombo.fromJson(v['table']);

final ShedConfig gandengyanConfig = ShedConfig(
  title: '干瞪眼',
  tint: const Color(0xFF1B5E20),
  hints: (h, v) => [for (final p in gdyPlays(h, _gdyTable(v))) p.$1],
  classify: (cards, v) {
    final t = _gdyTable(v);
    if (t != null) {
      final f = gdyFollowAs(cards, t);
      if (f != null) return f.label;
    }
    return gdyBestLead(cards)?.label;
  },
  pills: (g) {
    final v = g.view;
    return [
      c3Pill('牌堆 ${v['pile']} 张', Colors.brown),
      if ((v['bombs'] as num? ?? 0) > 0) c3Pill('炸弹 ${v['bombs']} · ×${v['mult']}', Colors.redAccent),
      c3Pill('跟牌须大一级 · 王百搭', Colors.teal.shade700, fontSize: 11),
    ];
  },
  sub: (g, s) {
    final sc = c3Ints(g.view['scores']);
    return '${s < sc.length ? sc[s] : 0}分';
  },
  badge: (g, s) => g.view['dealer'] == s && g.view['phase'] == 'play' ? c3Pill('庄', Colors.deepOrange, fontSize: 11) : null,
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final scores = c3Ints(v['scores']);
    final over = v['phase'] == 'over';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    final winner = r == null ? -1 : (r['winner'] as num).toInt();
    return c3ResultTable(g,
        title: over ? '比赛结束 · ${g.name(order.first)} 夺冠' : '${g.name(winner)} 先出完！${r != null && (r['bombs'] as num) > 0 ? '（炸弹×${r['mult']}）' : ''}',
        order: order,
        rank: over,
        cells: (s) => [
              if (r != null) ...[
                SizedBox(
                    width: 64,
                    child: Text('剩${(r['left'] as List)[s]}张${(r['closed'] as List)[s] == true ? '·闷' : ''}',
                        style: const TextStyle(fontSize: 12))),
                SizedBox(width: 48, child: c3Delta(((r['delta'] as List)[s] as num).toInt())),
              ],
              SizedBox(width: 56, child: Text('${scores[s]}分', textAlign: TextAlign.right)),
              if (r != null) ...[const SizedBox(width: 8), c3Row(c3Strs((r['hands'] as List)[s]), 22, gap: 0.45)],
            ]);
  },
);

// ---------------- 五十K / 争上游 shared ----------------

ShedCombo? _shTable(Map<String, dynamic> v) => v['lead'] == true ? null : ShedCombo.fromJson(v['table']);

const _wsRules = ShedRules(k510: true, rocketLen: 2);
ShedRules _zsyRules(Map<String, dynamic> v) => ShedRules(rocketLen: ((v['decks'] as num?) ?? 1).toInt() * 2);

int _wsPts(String c) {
  final r = c[0];
  if (r == '5') return 5;
  if (r == 'T' || r == 'K') return 10;
  return 0;
}

final ShedConfig wushikConfig = ShedConfig(
  title: '五十K',
  tint: const Color(0xFF004D40),
  hints: (h, v) => shedCandidates(h, _shTable(v), _wsRules),
  classify: (cards, v) => shedClassify(cards, _wsRules)?.label,
  pills: (g) {
    final v = g.view;
    final pts = c3Ints(v['pts']);
    return [
      if (v['phase'] == 'play') c3Pill('本墩 ${v['trickPts']} 分', Colors.deepOrange),
      if (v['teams'] == true && pts.length == 4)
        c3Pill('${g.name(0)}/${g.name(2)} ${pts[0] + pts[2]} : ${pts[1] + pts[3]} ${g.name(1)}/${g.name(3)}', Colors.purple,
            fontSize: 11),
    ];
  },
  sub: (g, s) {
    final pts = c3Ints(g.view['pts']);
    final sc = c3Ints(g.view['scores']);
    return '本局${s < pts.length ? pts[s] : 0}分 · 累计${s < sc.length ? sc[s] : 0}';
  },
  badge: (g, s) {
    if (g.view['teams'] != true) return null;
    return c3Pill(s % 2 == 0 ? '甲' : '乙', s % 2 == 0 ? Colors.blue : Colors.pink, fontSize: 11);
  },
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final scores = c3Ints(v['scores']);
    final over = v['phase'] == 'over';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    final finish = r == null ? <int>[] : c3Ints(r['finish']);
    String title;
    if (over) {
      if (v['teams'] == true) {
        final a = scores[0], b = scores[1];
        title = a == b ? '比赛结束 · 双方战平' : '比赛结束 · ${a > b ? '${g.name(0)}/${g.name(2)}' : '${g.name(1)}/${g.name(3)}'} 获胜';
      } else {
        title = '比赛结束 · ${g.name(order.first)} 夺冠';
      }
    } else {
      title = '${r?['title'] ?? '本局结束'}';
    }
    return c3ResultTable(g,
        title: title,
        order: order,
        rank: over,
        cells: (s) => [
              if (r != null) ...[
                SizedBox(
                    width: 52,
                    child: Text(finish.contains(s) ? '第${finish.indexOf(s) + 1}' : '末游', style: const TextStyle(fontSize: 12))),
                SizedBox(width: 56, child: Text('得${(r['pts'] as List)[s]}分', style: const TextStyle(fontSize: 12))),
              ],
              SizedBox(width: 64, child: Text('累计${scores[s]}', textAlign: TextAlign.right)),
              if (r != null) ...[
                const SizedBox(width: 8),
                c3Row(c3Strs((r['hands'] as List)[s]), 22,
                    gap: 0.45, hi: {for (final c in c3Strs((r['hands'] as List)[s])) if (_wsPts(c) > 0) c}),
              ],
            ]);
  },
);

final ShedConfig zhengshangyouConfig = ShedConfig(
  title: '争上游',
  tint: const Color(0xFF1A237E),
  hints: (h, v) => shedCandidates(h, _shTable(v), _zsyRules(v)),
  classify: (cards, v) => shedClassify(cards, _zsyRules(v))?.label,
  pills: (g) {
    final v = g.view;
    return [
      c3Pill('${v['decks']}副牌', Colors.brown),
      if (v['phase'] == 'play' && v['returned'] != null && (v['down'] as num) >= 0)
        c3Pill('已进贡/还贡', Colors.teal.shade700, fontSize: 11),
    ];
  },
  sub: (g, s) {
    final sc = c3Ints(g.view['scores']);
    return '${s < sc.length ? sc[s] : 0}分';
  },
  badge: (g, s) {
    final lf = c3Ints(g.view['lastFinish']);
    if (lf.isEmpty || g.view['phase'] == 'roundEnd' || g.view['phase'] == 'over') return null;
    if (lf.first == s) return c3Pill('上游', Colors.amber.shade800, fontSize: 11);
    if (lf.last == s) return c3Pill('下游', Colors.blueGrey, fontSize: 11);
    return null;
  },
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final scores = c3Ints(v['scores']);
    final over = v['phase'] == 'over';
    final finish = r == null ? <int>[] : c3Ints(r['finish']);
    final order = over
        ? (List.generate(g.players, (i) => i)..sort((a, b) => scores[b] - scores[a]))
        : (finish.length == g.players ? finish : List.generate(g.players, (i) => i));
    return c3ResultTable(g,
        title: over ? '比赛结束 · ${g.name(order.first)} 夺冠' : '上游 ${finish.isEmpty ? '' : g.name(finish.first)}',
        order: order,
        rank: true,
        cells: (s) => [
              if (r != null) ...[
                SizedBox(
                    width: 48,
                    child: Text(finish.isNotEmpty && finish.first == s ? '上游' : (finish.isNotEmpty && finish.last == s ? '下游' : ''),
                        style: const TextStyle(fontSize: 12))),
                SizedBox(width: 44, child: c3Delta(((r['delta'] as List)[s] as num).toInt())),
              ],
              SizedBox(width: 56, child: Text('${scores[s]}分', textAlign: TextAlign.right)),
              if (r != null) ...[const SizedBox(width: 8), c3Row(c3Strs((r['hands'] as List)[s]), 22, gap: 0.45)],
            ]);
  },
);

Widget gandengyanBoard(GameContext g) => ShedBoard(g, gandengyanConfig);
Widget wushikBoard(GameContext g) => ShedBoard(g, wushikConfig);
Widget zhengshangyouBoard(GameContext g) => ShedBoard(g, zhengshangyouConfig);
