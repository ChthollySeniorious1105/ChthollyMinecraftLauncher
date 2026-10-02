import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tile_widgets.dart';

const _windNames = ['东', '南', '西', '北'];

/// Result panel shown after every hand (和了 / 流局) and the final ranking.
class RiichiResultPanel extends StatelessWidget {
  final GameContext g;
  final Map<String, dynamic> v;
  const RiichiResultPanel(this.g, this.v, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final res = (v['result'] as Map).cast<String, dynamic>();
    final fin = (v['final'] as Map?)?.cast<String, dynamic>();
    final wins = (res['wins'] as List).cast<Map>();
    final deltas = (res['deltas'] as List).cast<num>();
    final scores = (res['scores'] as List).cast<num>();
    final n = scores.length;
    final me = (v['me'] as Map?)?.cast<String, dynamic>();
    final confirmed = me?['confirmed'] == true;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.clamp(280.0, 720.0);
      final tileW = (w / 20).clamp(14.0, 32.0);
      return Center(
        child: Container(
          width: w,
          constraints: BoxConstraints(maxHeight: c.maxHeight * 0.95),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade600, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black54)],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${res['round'] ?? ''}${(res['honba'] ?? 0) > 0 ? ' ${res['honba']}本场' : ''}',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7))),
              if (wins.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                      res['abort'] == true ? '${res['drawName']} 流局' : (res['drawName'] as String? ?? '流局'),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
                ),
              if (res['nagashi'] is List)
                for (final nm in (res['nagashi'] as List).cast<Map>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${g.name((nm['seat'] as num).toInt())}  流局满贯  ${nm['points']}点',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                  ),
              for (final win in wins) _winBlock(context, win.cast<String, dynamic>(), tileW, n),
              if (wins.isNotEmpty && res['type'] == 'win' && res['drawName'] != null)
                Text(res['drawName'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (res['tenpai'] is List && wins.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      (res['tenpai'] as List).isEmpty
                          ? '全员未听'
                          : '听牌：${(res['tenpai'] as List).map((s) => g.name((s as num).toInt())).join('、')}'),
                ),
              if (res['tenpai'] is List && wins.isEmpty) _revealBlock(res, tileW),
              const Divider(),
              Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
                for (var s = 0; s < n; s++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(g.name(s), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${scores[s].toInt()}'),
                      Text(
                        deltas[s] == 0 ? '±0' : (deltas[s] > 0 ? '+${deltas[s].toInt()}' : '${deltas[s].toInt()}'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: deltas[s] > 0 ? Colors.green : (deltas[s] < 0 ? Colors.redAccent : cs.onSurface),
                        ),
                      ),
                    ]),
                  ),
              ]),
              if (fin != null) ...[const Divider(), _ranking(context, fin)],
              const SizedBox(height: 10),
              if (fin == null && g.seat >= 0)
                FilledButton(
                  onPressed: confirmed ? null : () => g.act({'t': 'ok'}),
                  child: Text(confirmed ? '等待其他玩家…' : '继续'),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _revealBlock(Map<String, dynamic> res, double tileW) {
    final reveal = (res['reveal'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final e in reveal.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${g.name(int.parse(e.key))} ', style: const TextStyle(fontSize: 12)),
            Flexible(
              child: FittedBox(
                child: Row(children: [for (final t in (e.value as List).cast<String>()) RTile(t, width: tileW * 0.8)]),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _winBlock(BuildContext context, Map<String, dynamic> w, double tileW, int n) {
    final cs = Theme.of(context).colorScheme;
    final seat = (w['seat'] as num).toInt();
    final from = (w['from'] as num).toInt();
    final tsumo = w['tsumo'] == true;
    final yaku = (w['yaku'] as List).cast<Map>();
    final yakuman = (w['yakuman'] as num).toInt();
    final han = (w['han'] as num).toInt();
    final fu = (w['fu'] as num).toInt();
    final limit = w['limit'] as String? ?? '';
    final hand = (w['hand'] as List).cast<String>();
    final melds = (w['melds'] as List).cast<Map>();
    final dora = (w['dora'] as List).cast<String>();
    final ura = (w['ura'] as List).cast<String>();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Avatar(g.avatar(seat), size: 28),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${g.name(seat)}  ${tsumo ? '自摸' : '荣和'}${!tsumo && from >= 0 ? '（${g.name(from)} 放铳）' : ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final t in hand) RTile(t, width: tileW),
            SizedBox(width: tileW * 0.4),
            RTile(w['win'] as String, width: tileW, highlight: true),
            for (final m in melds) ...[
              SizedBox(width: tileW * 0.4),
              MeldView(m, owner: seat, players: n, width: tileW),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('宝牌 ', style: TextStyle(fontSize: 12)),
          for (final d in dora) RTile(d, width: tileW * 0.7),
          if (ura.isNotEmpty) ...[
            const Text('  里宝牌 ', style: TextStyle(fontSize: 12)),
            for (final d in ura) RTile(d, width: tileW * 0.7),
          ],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (final y in yaku)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
              ),
              child: Text(
                yakuman > 0
                    ? '${y['name']}${(y['han'] as num) > 1 ? ' 双倍役满' : ' 役满'}'
                    : '${y['name']} ${y['han']}番',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ]),
        if (w['pao'] is Map)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${(w['pao'] as Map)['yaku']} 包牌：${g.name(((w['pao'] as Map)['seat'] as num).toInt())}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          ),
        const SizedBox(height: 6),
        Text(
          yakuman > 0
              ? '$limit  ${w['points']}点'
              : '$han番 $fu符${limit.isNotEmpty ? '  $limit' : ''}  ${w['points']}点',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
        ),
      ]),
    );
  }

  Widget _ranking(BuildContext context, Map<String, dynamic> fin) {
    final rk = (fin['ranking'] as List).cast<Map>();
    const medals = ['一位', '二位', '三位', '四位'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('最终排名', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 6),
      for (final r in rk)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 44,
                child: Text(medals[((r['rank'] as num).toInt() - 1).clamp(0, 3)],
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            Avatar(g.avatar((r['seat'] as num).toInt()), size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: SizedBox(
                  width: 120, child: Text(g.name((r['seat'] as num).toInt()), overflow: TextOverflow.ellipsis)),
            ),
            SizedBox(
                width: 64,
                child: Text('${r['score']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right)),
            if (r['final'] is num) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(
                  _fmt((r['final'] as num).toDouble()),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: (r['final'] as num) > 0
                        ? Colors.green
                        : ((r['final'] as num) < 0 ? Colors.redAccent : null),
                  ),
                ),
              ),
            ],
          ]),
        ),
      if (fin['returnPoints'] is num)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '返点 ${fin['returnPoints']}  马点 ${[for (final r in rk) '${r['uma']}'].join('/')}'
            '  头名奖励 +${(fin['oka'] as num).toStringAsFixed(0)}',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
    ]);
  }

  static String _fmt(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}';
}

String windName(int i) => _windNames[i % 4];
