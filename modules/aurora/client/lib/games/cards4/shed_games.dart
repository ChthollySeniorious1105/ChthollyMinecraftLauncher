import 'package:aurora_shared/games/cards4/sets.dart';
import 'package:aurora_shared/games/cards4/sk_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c4_widgets.dart';
import 'shed_board.dart';

int _cv(String c) {
  switch (c) {
    case 'BJ':
      return 16;
    case 'RJ':
    case 'GJ':
      return 17;
    case 'EJ':
      return 18;
  }
  return '3456789TJQKA2'.indexOf(c[0]) + 3;
}

Color _teamColor(int t) => t == 0 ? Colors.blue.shade700 : Colors.pink.shade600;

// ---------------------------------------------------------------- 够级

const _placeNames = ['头科', '二科', '三科', '四科', '二落', '大落'];

List<List<String>> _goujiHints(GameContext g, List<String> hand) {
  final v = g.view;
  final lead = v['lead'] == true;
  final locked = v['fourLocked'] == true;
  bool ok(List<String> c) {
    final whole = c.length == hand.length;
    if (c.any((x) => _cv(x) == 3) && (!whole || c.any((x) => _cv(x) != 3))) return false;
    final s = classifySet(c);
    if (s == null) return false;
    if (s.rank == 4 && !s.allJokers && locked) return false;
    if (!lead && (v['table'] as Map?)?['gouji'] == true) {
      final ts = c4Int(v['tableSeat']);
      if (g.seat != (ts + 3) % 6 && !whole && s.jokers == 0) return false;
    }
    return true;
  }

  if (lead) {
    if (hand.every((c) => _cv(c) == 3)) return [hand];
    final out = setCandidates(hand).where(ok).toList();
    // bigger groups of the same rank first within a rank is fine; keep cheapest order
    return out;
  }
  final t = SetCombo.fromJson(v['table']);
  if (t == null) return const [];
  return setCandidates(hand, size: t.size, above: t.rank).where(ok).toList();
}

final C4ShedConfig goujiConfig = C4ShedConfig(
  title: '够级',
  tint: const Color(0xFF1B5E20),
  hints: _goujiHints,
  classify: (g, cards) {
    final s = classifySet(cards);
    if (s == null) return null;
    const gj = {10: 5, 11: 4, 12: 3, 13: 2, 14: 2, 15: 1};
    final isG = s.jokers > 0 || (gj[s.rank] != null && s.size >= gj[s.rank]!);
    return '${s.label}${isG ? ' · 够级' : ''}';
  },
  pills: (g) {
    final v = g.view;
    final ts = c4Ints(v['teamScores']);
    return [
      c4Pill('第 ${v['round']}/${v['rounds']} 局', Colors.brown),
      if (ts.length == 2) ...[
        c4Pill('蓝队 ${ts[0]}', _teamColor(0)),
        c4Pill('红队 ${ts[1]}', _teamColor(1)),
      ],
      if (v['fourLocked'] == true && v['phase'] == 'play') c4Pill('未开点：不能出4', Colors.deepOrange, fontSize: 11),
    ];
  },
  sub: (g, s) {
    final op = (g.view['opened'] as List?);
    final opened = op != null && s < op.length && op[s] == true;
    return '${s % 2 == 0 ? '蓝队' : '红队'}${opened ? ' · 已开点' : ''}';
  },
  badge: (g, s) {
    final me = g.seat;
    if (me >= 0 && s == (me + 3) % 6) return c4Pill('对头', Colors.deepOrange, fontSize: 10);
    final lf = c4Ints(g.view['lastFinish']);
    final i = lf.indexOf(s);
    if (i >= 0 && g.view['phase'] != 'roundEnd' && g.view['phase'] != 'over') {
      return c4Pill(_placeNames[i], _teamColor(s % 2), fontSize: 10);
    }
    return Container(
        width: 10, height: 10, decoration: BoxDecoration(color: _teamColor(s % 2), shape: BoxShape.circle));
  },
  status: (g) {
    final v = g.view;
    if (v['phase'] != 'tribute') return null;
    final me = g.seat;
    final mine = [for (final t in (v['tributes'] as List? ?? const [])) if (t['to'] == me && t['back'] == null) t];
    if (mine.isNotEmpty) return '收到进贡：选 ${mine.first['n']} 张牌还给 ${g.name(c4Int(mine.first['from']))}';
    return '等待还贡…';
  },
  phaseMine: (g) =>
      g.view['phase'] == 'tribute' &&
      (g.view['tributes'] as List? ?? const []).any((t) => t['to'] == g.seat && t['back'] == null),
  phaseActions: (g, sel) {
    final t = (g.view['tributes'] as List).firstWhere((t) => t['to'] == g.seat && t['back'] == null);
    final n = c4Int(t['n']);
    return FilledButton(
      onPressed: sel.length == n ? () => g.act({'type': 'return', 'cards': sel}) : null,
      child: Text('还贡（$n 张）'),
    );
  },
  phaseCenter: (g, w) {
    final v = g.view;
    if (v['phase'] != 'tribute') return null;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('进贡', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final t in (v['tributes'] as List))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                c4Pill('${t['why']}', Colors.deepOrange, fontSize: 11),
                const SizedBox(width: 6),
                Text('${g.name(c4Int(t['from']))} → ${g.name(c4Int(t['to']))}',
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(width: 6),
                c4Row(c4Strs(t['give']), w * 0.7),
                const SizedBox(width: 8),
                Text(t['back'] == null ? '等待还贡' : '已还', style: const TextStyle(color: Colors.white70)),
                if (t['back'] != null) ...[const SizedBox(width: 4), c4Row(c4Strs(t['back']), w * 0.7)],
              ]),
            ),
        ]),
      ),
    );
  },
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final ts = c4Ints(v['teamScores']);
    final over = v['phase'] == 'over';
    final order = r == null ? List.generate(g.players, (i) => i) : c4Ints(r['order']);
    final delta = r == null ? List.filled(g.players, 0) : c4Ints(r['delta']);
    final td = r == null ? [0, 0] : c4Ints(r['teamDelta']);
    String title;
    if (over) {
      title = ts[0] == ts[1] ? '比赛结束 · 双方战平' : '比赛结束 · ${ts[0] > ts[1] ? '蓝队' : '红队'}获胜';
    } else {
      title = '本局结束 · 头科 ${g.name(order.first)}${r?['men'] == true ? ' · 闷！' : ''}';
    }
    return c4ResultTable(g,
        title: title,
        order: order,
        header: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 8, children: [
              c4Pill('蓝队 ${td[0] >= 0 ? '+' : ''}${td[0]} → ${ts[0]}', _teamColor(0)),
              c4Pill('红队 ${td[1] >= 0 ? '+' : ''}${td[1]} → ${ts[1]}', _teamColor(1)),
            ]),
          ),
        ],
        cells: (s) {
          final i = order.indexOf(s);
          return [
            SizedBox(width: 44, child: c4Pill(i >= 0 ? _placeNames[i] : '', _teamColor(s % 2), fontSize: 11)),
            const SizedBox(width: 6),
            SizedBox(width: 36, child: c4Delta(delta[s])),
            if (r != null) c4Row(c4Strs((r['hands'] as List)[s]), 20, gap: 0.4),
          ];
        });
  },
);

// ---------------------------------------------------------------- 保皇

List<List<String>> _bhHints(GameContext g, List<String> hand) {
  final v = g.view;
  final bombs = v['bombs'] == true;
  bool isBomb(List<String> c) => bombs && c.length >= 4 && c.every((x) => !setWild(x) && x != 'EJ');
  if (v['lead'] == true) return setCandidates(hand);
  final t = SetCombo.fromJson(v['table']);
  if (t == null) return const [];
  final tb = (v['table'] as Map)['bomb'] == true;
  final out = tb ? <List<String>>[] : setCandidates(hand, size: t.size, above: t.rank);
  if (bombs) {
    for (final c in setCandidates(hand)) {
      if (!isBomb(c)) continue;
      final s = classifySet(c)!;
      if (tb ? (s.size > t.size || (s.size == t.size && s.rank > t.rank)) : s.size > t.size) out.add(c);
    }
  }
  return out;
}

final C4ShedConfig baohuangConfig = C4ShedConfig(
  title: '保皇',
  tint: const Color(0xFF6D4C41),
  hints: _bhHints,
  classify: (g, cards) {
    final s = classifySet(cards);
    if (s == null) return null;
    final bomb = g.view['bombs'] == true && s.jokers == 0 && s.size >= 4 && s.rank <= 15;
    return bomb ? '${s.size}张炸弹' : s.label;
  },
  pills: (g) {
    final v = g.view;
    return [
      c4Pill('第 ${v['round']}/${v['rounds']} 局', Colors.brown),
      if (v['du'] == true) c4Pill('独保', Colors.red.shade700),
      if (v['bao'] == true) c4Pill('暴保', Colors.deepOrange),
      if (v['amGuard'] == true && v['du'] != true) c4Pill('你是保子（侍卫）', Colors.amber.shade800),
    ];
  },
  sub: (g, s) {
    final sc = c4Ints(g.view['scores']);
    return '${s < sc.length ? sc[s] : 0}分';
  },
  badge: (g, s) {
    final v = g.view;
    if (c4Int(v['emperor']) == s) return c4Pill('皇帝', const Color(0xFFB8860B), fontSize: 10);
    if (c4Int(v['guard'], -2) == s) return c4Pill('保子', Colors.red.shade400, fontSize: 10);
    return null;
  },
  status: (g) {
    final v = g.view;
    final me = g.seat;
    if (v['phase'] == 'declare') {
      return me == c4Int(v['emperor']) ? '你是皇帝：是否独保（1 打 4，分数翻倍）？' : '等待皇帝 ${g.name(c4Int(v['emperor']))} 决定是否独保';
    }
    if (v['phase'] == 'reveal') {
      final ans = v['answered'] as List?;
      final mine = me >= 0 && ans != null && ans[me] != true;
      if (!mine) return '等待其他人选择…';
      return v['amGuard'] == true ? '你是保子：是否暴保（亮明身份，分数翻倍）？' : '你是平民：确认（不暴）';
    }
    return null;
  },
  phaseMine: (g) {
    final v = g.view;
    if (v['phase'] == 'declare') return g.seat == c4Int(v['emperor']);
    if (v['phase'] == 'reveal') {
      final ans = v['answered'] as List?;
      return ans != null && g.seat < ans.length && ans[g.seat] != true;
    }
    return false;
  },
  phaseActions: (g, sel) {
    final v = g.view;
    if (v['phase'] == 'declare') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton(onPressed: () => g.act({'type': 'du', 'yes': false}), child: const Text('不独保')),
        const SizedBox(width: 8),
        FilledButton(onPressed: () => g.act({'type': 'du', 'yes': true}), child: const Text('独保！')),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton(onPressed: () => g.act({'type': 'bao', 'yes': false}), child: const Text('不暴')),
      if (v['amGuard'] == true) ...[
        const SizedBox(width: 8),
        FilledButton(onPressed: () => g.act({'type': 'bao', 'yes': true}), child: const Text('暴保！')),
      ],
    ]);
  },
  phaseCenter: (g, w) {
    final v = g.view;
    if (v['phase'] != 'declare' && v['phase'] != 'reveal') return null;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          c4Card('EJ', w * 1.1),
          const SizedBox(height: 6),
          Text('皇帝：${g.name(c4Int(v['emperor']))}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(v['phase'] == 'declare' ? '皇帝正在考虑是否独保' : '保子可以选择暴保', style: const TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  },
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final sc = c4Ints(v['scores']);
    final over = v['phase'] == 'over';
    final order = over
        ? (List.generate(g.players, (i) => i)..sort((a, b) => sc[b] - sc[a]))
        : (r == null ? List.generate(g.players, (i) => i) : c4Ints(r['order']));
    final delta = r == null ? List.filled(g.players, 0) : c4Ints(r['delta']);
    final finishOrder = r == null ? <int>[] : c4Ints(r['order']);
    final emp = c4Int(v['emperor']), guard = c4Int(v['guard'], -2);
    final title = over
        ? '比赛结束 · ${g.name(order.first)} 夺冠'
        : '${r?['royalWin'] == true ? '皇帝方' : '平民方'}获胜 ${c4Strs(r?['notes']).join(' ')}';
    return c4ResultTable(g,
        title: title,
        order: order,
        cells: (s) => [
              SizedBox(
                  width: 44,
                  child: s == emp
                      ? c4Pill('皇帝', const Color(0xFFB8860B), fontSize: 10)
                      : (s == guard ? c4Pill('保子', Colors.red.shade400, fontSize: 10) : const Text('平民', style: TextStyle(fontSize: 12)))),
              SizedBox(width: 44, child: Text(finishOrder.contains(s) ? '第${finishOrder.indexOf(s) + 1}' : '', style: const TextStyle(fontSize: 12))),
              SizedBox(width: 36, child: c4Delta(delta[s])),
              SizedBox(width: 52, child: Text('${sc[s]}分', textAlign: TextAlign.right)),
              const SizedBox(width: 8),
              if (r != null) c4Row(c4Strs((r['hands'] as List)[s]), 20, gap: 0.4),
            ]);
  },
);

// ---------------------------------------------------------------- 双扣

final C4ShedConfig shuangkouConfig = C4ShedConfig(
  title: '双扣',
  tint: const Color(0xFF0D47A1),
  hints: (g, hand) => skCandidates(hand, g.view['lead'] == true ? null : SkCombo.fromJson(g.view['table'])),
  classify: (g, cards) => skClassify(cards)?.label,
  pills: (g) {
    final v = g.view;
    final ts = c4Ints(v['teamScores']);
    final me = g.seat;
    String tn(int t) => '${g.name(t)}/${g.name(t + 2)}';
    return [
      c4Pill('第 ${v['round']} 局 · 目标 ${v['target']} 分', Colors.brown),
      if (ts.length == 2) ...[
        c4Pill('${me >= 0 && me % 2 == 0 ? '我方' : tn(0)} ${ts[0]}', _teamColor(0)),
        c4Pill('${me >= 0 && me % 2 == 1 ? '我方' : tn(1)} ${ts[1]}', _teamColor(1)),
      ],
    ];
  },
  sub: (g, s) => s % 2 == 0 ? '蓝队' : '红队',
  badge: (g, s) {
    final me = g.seat;
    if (me >= 0 && s == (me + 2) % 4) return c4Pill('对家', _teamColor(s % 2), fontSize: 10);
    return Container(
        width: 10, height: 10, decoration: BoxDecoration(color: _teamColor(s % 2), shape: BoxShape.circle));
  },
  result: (g, w) {
    final v = g.view;
    final r = v['result'] as Map?;
    final ts = c4Ints(v['teamScores']);
    final over = v['phase'] == 'over';
    final order = r == null ? List.generate(g.players, (i) => i) : c4Ints(r['order']);
    final td = r == null ? [0, 0] : c4Ints(r['teamDelta']);
    const names = ['上游', '二游', '三游', '下游'];
    final title = over
        ? '比赛结束 · ${ts[0] > ts[1] ? '${g.name(0)}/${g.name(2)}' : '${g.name(1)}/${g.name(3)}'} 获胜'
        : '${r?['kind'] ?? ''} · ${g.name(order.first)} 上游';
    return c4ResultTable(g,
        title: title,
        order: order,
        header: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 8, children: [
              c4Pill('${g.name(0)}/${g.name(2)} +${td[0]} → ${ts[0]}', _teamColor(0)),
              c4Pill('${g.name(1)}/${g.name(3)} +${td[1]} → ${ts[1]}', _teamColor(1)),
            ]),
          ),
        ],
        cells: (s) {
          final i = order.indexOf(s);
          final h = r == null ? <String>[] : c4Strs((r['hands'] as List)[s]);
          return [
            SizedBox(width: 44, child: c4Pill(i >= 0 ? names[i] : '', _teamColor(s % 2), fontSize: 11)),
            const SizedBox(width: 8),
            if (h.isNotEmpty) c4Row(h, 20, gap: 0.4) else const Text('已出完', style: TextStyle(fontSize: 12)),
          ];
        });
  },
);

Widget goujiBoard(GameContext g) => C4ShedBoard(g, goujiConfig);
Widget baohuangBoard(GameContext g) => C4ShedBoard(g, baohuangConfig);
Widget shuangkouBoard(GameContext g) => C4ShedBoard(g, shuangkouConfig);
