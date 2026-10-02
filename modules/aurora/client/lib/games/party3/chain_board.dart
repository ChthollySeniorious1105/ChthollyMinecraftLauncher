import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p3_common.dart';

/// Board for the turn-based word chains: 成语接龙 (`chengyu`) and 飞花令 (`feihualing`).
class ChainBoard extends StatelessWidget {
  final GameContext g;
  final bool feihua;
  const ChainBoard(this.g, {super.key, required this.feihua});

  Map<String, dynamic> get v => g.view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = p3Str(v['phase']);
    final turn = p3Int(v['turn'], 0);
    final me = g.seat;
    final lives = p3Ints(v['lives']);
    final score = p3Ints(v['score']);
    final maxLives = p3Int(v['maxLives'], 3);
    final pending = p3Map(v['pending']);
    final voters = p3Ints(v['voters']).toSet();
    final voted = p3Ints(v['voted']).toSet();
    final alive = me >= 0 && me < lives.length && lives[me] > 0;
    final myTurn = phase == 'play' && me == turn && alive;
    final canVote = phase == 'vote' && voters.contains(me) && !voted.contains(me);

    String status;
    switch (phase) {
      case 'play':
        status = myTurn ? (feihua ? '轮到你：说一句含「${v['key']}」的诗' : '轮到你：接「${v['need']}」') : '轮到 ${g.name(turn)}';
      case 'vote':
        status = canVote ? '请投票：这句诗算不算？' : '等待投票：${g.name(p3Int(pending?['s']))} 的句子';
      default:
        status = '游戏结束';
    }
    if (me >= 0 && me < lives.length && lives[me] <= 0 && phase != 'over') status = '你已出局 · $status';

    Widget center() {
      if (feihua) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('令字', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 3))],
            ),
            child: Text('${v['key']}', style: const TextStyle(fontSize: 52, color: Color(0xFFFFE082), fontWeight: FontWeight.w900, height: 1.1)),
          ),
          const SizedBox(height: 6),
          Text('${v['check'] == 'strict' ? '严格模式' : '宽松模式（投票）'} · 已说 ${v['answers']} 句 · 库中含令字 ${v['available']} 句',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
          if (pending != null) ...[
            const SizedBox(height: 8),
            P3Panel(
              color: cs.tertiaryContainer,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${g.name(p3Int(pending['s']))}：', style: const TextStyle(fontSize: 12)),
                Text('「${pending['t']}」', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onTertiaryContainer)),
                Text('库中没有这句，投票中（${voted.length}/${voters.length}）', style: const TextStyle(fontSize: 11)),
              ]),
            ),
          ],
        ]);
      }
      final cur = '${v['current']}';
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v['match'] == 'sound' ? '同音接龙' : '同字接龙', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < cur.length; i++)
              Container(
                width: 54,
                height: 54,
                margin: const EdgeInsets.all(3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == cur.length - 1 ? const Color(0xFFB71C1C) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))],
                ),
                child: Text(cur[i],
                    style: TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w900, color: i == cur.length - 1 ? const Color(0xFFFFE082) : cs.onSurface)),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Text('下一个要接：${v['need']}   尾字拼音 ${v['lastPy']}', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
        Text('本链已接 ${v['chain']} 个 · 共用 ${v['usedCount']} 个', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
      ]);
    }

    Widget main() => P3Panel(child: Center(child: SingleChildScrollView(child: center())));

    Widget feed() {
      final rows = <Widget>[];
      for (final h in p3Maps(v['history']).reversed) {
        final s = p3Int(h['s']);
        switch (h['k']) {
          case 'ok':
            final txt = feihua ? '${h['t']}' : '${h['w']}';
            final sub = feihua
                ? (h['a'] != null ? '${g.name(s)} · ${h['a']}《${h['ti']}》' : '${g.name(s)} · 投票通过')
                : '${g.name(s)}${h['dead'] == true ? ' · 接死 +2' : ''}';
            rows.add(p3FeedRow(context, lead: const Icon(Icons.check_circle, color: Colors.green, size: 18), text: txt, sub: sub));
          case 'fail':
            rows.add(p3FeedRow(context,
                lead: const Icon(Icons.heart_broken, color: Colors.redAccent, size: 18),
                text: '${g.name(s)} ${h['why']}',
                sub: p3Int(h['lives'], 0) > 0 ? '剩 ${h['lives']} 条命' : '出局',
                tint: Colors.red));
          case 'out':
            rows.add(p3FeedRow(context, lead: const Icon(Icons.flag, size: 18), text: '${g.name(s)} ${h['why']}出局', tint: Colors.red));
          case 'start':
            rows.add(p3FeedRow(context, lead: const Icon(Icons.play_arrow, size: 18), text: '新接龙：${h['w']}', tint: cs.primaryContainer));
        }
      }
      return p3Feed(context, feihua ? '已说诗句' : '接龙记录', rows, empty: '还没有人作答');
    }

    Widget controls() {
      if (canVote) {
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              onPressed: () => g.act({'type': 'vote', 'ok': true}),
              icon: const Icon(Icons.thumb_up),
              label: const Text('认可')),
          const SizedBox(width: 12),
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => g.act({'type': 'vote', 'ok': false}),
              icon: const Icon(Icons.thumb_down),
              label: const Text('不认可')),
        ]);
      }
      if (!myTurn) return const SizedBox.shrink();
      return P3Input(
        hint: feihua ? '含「${v['key']}」的诗句' : '「${v['lastChar']}」开头的成语',
        button: feihua ? '吟' : '接',
        maxLength: feihua ? 30 : 8,
        onSubmit: (t) => g.act({'type': 'answer', 'text': t}),
        extra: OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('放弃')),
      );
    }

    Widget? banner;
    final pl = v['placings'];
    if (phase == 'over' && pl is List) {
      final p = p3Ints(pl);
      final win = [for (var s = 0; s < p.length; s++) if (p[s] == 1) g.name(s)];
      banner = p3Ranking(g, '${win.join('、')} 获胜！', p, (s) => '${s < score.length ? score[s] : 0} 分');
    }

    return p3Layout(
      status: P3Status(status, view: v, highlight: myTurn || canVote, replay: g.replay),
      players: p3Players(g,
          active: (s) => phase == 'play' && s == turn,
          dim: (s) => s < lives.length && lives[s] <= 0,
          sub: (s) => '${p3Hearts(s < lives.length ? lives[s] : 0, maxLives)} ${s < score.length ? score[s] : 0}分'),
      main: main(),
      feed: feed(),
      controls: controls(),
      banner: banner,
    );
  }
}
