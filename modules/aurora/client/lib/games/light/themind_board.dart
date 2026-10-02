import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

class MindCard extends StatelessWidget {
  final int card;
  final double width;
  final bool back;
  final bool bad;
  const MindCard(this.card, {super.key, this.width = 60, this.back = false, this.bad = false});

  @override
  Widget build(BuildContext context) {
    final t = (card.clamp(1, 100) - 1) / 99;
    final col = back ? const Color(0xFF283593) : Color.lerp(const Color(0xFF26C6DA), const Color(0xFFAB47BC), t)!;
    return Container(
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [col, Color.lerp(col, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: bad ? Colors.redAccent : Colors.white, width: bad ? 3 : width * 0.04),
        boxShadow: [BoxShadow(color: bad ? Colors.redAccent : Colors.black45, blurRadius: bad ? 10 : 4, offset: const Offset(1, 2))],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: back
              ? Icon(Icons.psychology, color: Colors.white70, size: width * 0.5)
              : Text('$card',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: width * 0.46, shadows: const [Shadow(color: Colors.black54, blurRadius: 4)])),
        ),
      ),
    );
  }
}

class TheMindBoard extends StatelessWidget {
  final GameContext g;
  const TheMindBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final phase = v['phase'] as String? ?? 'play';
    final level = lInt(v['level']);
    final levels = lInt(v['levels']);
    final lives = lInt(v['lives']);
    final stars = lInt(v['stars']);
    final hand = lInts(v['hand']);
    final counts = lInts(v['handCounts']);
    final votes = lBools(v['votes']);
    final pile = [for (final p in lList<Map>(v['pile'])) lMap(p)];
    final discards = [for (final p in lList<Map>(v['discards'])) lMap(p)];
    final me = lMe(g, n);
    final canPlay = me && phase == 'play' && hand.isNotEmpty && !g.replay;
    final voting = votes.contains(true);
    final myVote = me && (votes.elementAtOrNull(g.seat) ?? false);
    final mistake = v['lastMistake'] == null ? null : lMap(v['lastMistake']);

    String status;
    if (phase == 'over') {
      status = v['won'] == true ? '全部通关！' : '闯关失败';
    } else if (phase == 'levelEnd') {
      status = '第 $level 关通过！${v['reward'] ?? ''}';
    } else if (canPlay) {
      status = voting ? '有人提议使用手里剑：同意吗？' : '感觉轮到你了？按“出牌”打出最小的一张';
    } else if (me && hand.isEmpty) {
      status = '你的牌已出完，等待队友';
    } else {
      status = '第 $level 关进行中';
    }

    Widget? result;
    if (phase == 'over') {
      result = ResultBanner(v['won'] == true ? '心灵完全同步！通关 $levels 关' : '闯关失败：止步第 $level 关',
          child: Text('合作游戏：全队同赢同输（到达 $level/$levels 关）'));
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final top = pile.isEmpty ? null : pile.last;
      final center = Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: RadialGradient(colors: [Color.lerp(g.table, Colors.white, 0.12)!, g.table]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              height: 130,
              child: Stack(alignment: Alignment.center, children: [
                for (var i = 0; i < pile.length && i < 4; i++)
                  Transform.rotate(
                    angle: (i - 2) * 0.08,
                    child: Opacity(
                      opacity: i == (pile.length < 4 ? pile.length : 4) - 1 ? 1 : 0.5,
                      child: MindCard(lInt(pile[pile.length - (pile.length < 4 ? pile.length : 4) + i]['card']), width: 80),
                    ),
                  ),
                if (pile.isEmpty) Text('等待第一张牌', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (top != null) Text('${g.name(lInt(top['seat']))} 打出', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('已出 ${pile.length} 张', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('剩余 ${counts.fold(0, (a, b) => a + b)} 张', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ]),
          if (mistake != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('失误！${g.name(lInt(mistake['seat']))} 打出 ${lInt(mistake['card'])}，弃掉 ${lList<String>(mistake['lost']).join('，')}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          if (discards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
                const Text('弃牌：', style: TextStyle(color: Colors.white70, fontSize: 12)),
                for (final d in discards) MindCard(lInt(d['card']), width: 24, bad: d['why'] == 'mistake'),
              ]),
            ),
        ]),
      );
      return LFrame(
        status: status,
        highlight: canPlay,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
            LChip('第 $level / $levels 关', icon: Icons.stairs),
            LChip('生命 $lives', icon: Icons.favorite, color: Colors.redAccent),
            LChip('手里剑 $stars', icon: Icons.star, color: Colors.amber),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (var s = 0; s < n; s++)
              g.tag(s,
                  size: 28,
                  active: (counts.elementAtOrNull(s) ?? 0) > 0 && phase == 'play',
                  sub: '手牌 ${counts.elementAtOrNull(s) ?? 0}${(votes.elementAtOrNull(s) ?? false) ? ' · ⭐同意' : ''}'),
          ]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: center),
          const SizedBox(height: 10),
          if (me)
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final c0 in hand) MindCard(c0, width: wide ? 64 : 52),
              if (hand.isEmpty) Text('（没有手牌）', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            ]),
          if (canPlay) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => g.act({'type': 'play'}),
                  icon: const Icon(Icons.bolt),
                  label: Text('出牌（${hand.first}）', style: const TextStyle(fontSize: 18)),
                ),
              ),
              if (stars > 0)
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => g.act({'type': myVote ? 'unstar' : 'star'}),
                    icon: Icon(myVote ? Icons.star : Icons.star_border, color: Colors.amber),
                    label: Text(myVote ? '取消手里剑' : (voting ? '同意手里剑' : '提议手里剑')),
                  ),
                ),
            ]),
          ],
        ],
      );
    });
  }
}
