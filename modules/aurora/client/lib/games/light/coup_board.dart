import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

const _roles = {
  'duke': ('公爵', Icons.account_balance, Color(0xFF7B1FA2), '征税 +3；阻止外援'),
  'assassin': ('刺客', Icons.dangerous, Color(0xFF212121), '付 3 金刺杀'),
  'captain': ('队长', Icons.anchor, Color(0xFF1565C0), '勒索 2 金；阻止勒索'),
  'ambassador': ('大使', Icons.swap_horiz, Color(0xFF2E7D32), '交换牌；阻止勒索'),
  'contessa': ('伯爵夫人', Icons.shield, Color(0xFFC62828), '阻止刺杀'),
};
const _actNames = {'income': '收入', 'foreignaid': '外援', 'coup': '政变', 'tax': '征税', 'assassinate': '刺杀', 'steal': '勒索', 'exchange': '交换'};

String _rn(String r) => _roles[r]?.$1 ?? r;

class CoupCard extends StatelessWidget {
  final String? role; // null = face down
  final double width;
  final bool dead;
  final bool selected;
  final VoidCallback? onTap;
  const CoupCard(this.role, {super.key, this.width = 64, this.dead = false, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = role == null ? null : _roles[role];
    final h = width * 1.4;
    Widget body;
    if (info == null) {
      body = Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF263238), Color(0xFF546E7A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: const Color(0xFFFFD54F), width: width * 0.04),
        ),
        child: Center(child: Icon(Icons.local_police, color: const Color(0xFFFFD54F), size: width * 0.45)),
      );
    } else {
      body = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [info.$3, Color.lerp(info.$3, Colors.black, 0.35)!], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: const Color(0xFFFFD54F), width: width * 0.04),
        ),
        padding: EdgeInsets.all(width * 0.06),
        child: Column(children: [
          Expanded(child: FittedBox(child: Icon(info.$2, color: Colors.white))),
          SizedBox(
            height: h * 0.18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(info.$1, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: width * 0.22)),
            ),
          ),
          if (width >= 56)
            SizedBox(
              height: h * 0.14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(info.$4, style: TextStyle(color: Colors.white70, fontSize: width * 0.13)),
              ),
            ),
        ]),
      );
    }
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.14 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.12),
        boxShadow: [BoxShadow(color: selected ? Colors.amber : Colors.black45, blurRadius: selected ? 12 : 4, offset: const Offset(1, 2))],
      ),
      child: body,
    );
    if (dead) {
      w = Stack(children: [
        Opacity(opacity: 0.5, child: w),
        Positioned.fill(child: Icon(Icons.close, color: Colors.redAccent.withValues(alpha: 0.9), size: width * 0.8)),
      ]);
    }
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class CoupBoard extends StatefulWidget {
  final GameContext g;
  const CoupBoard(this.g, {super.key});
  @override
  State<CoupBoard> createState() => _CoupBoardState();
}

class _CoupBoardState extends State<CoupBoard> {
  String pendingAction = '';
  Set<int> keep = {};
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final phase = v['phase'] as String? ?? 'action';
    final turn = lInt(v['turn']);
    final action = v['action'] as String? ?? '';
    final actor = lInt(v['actor'], -1);
    final target = lInt(v['target'], -1);
    final blocker = lInt(v['blocker'], -1);
    final blockRole = v['blockRole'] as String? ?? '';
    final claimRole = v['claimRole'] as String?;
    final coins = lInts(v['coins']);
    final handCounts = lInts(v['handCounts']);
    final revealed = [for (final r in lList<List>(v['revealed'])) r.whereType<String>().toList()];
    final alive = lBools(v['alive']);
    final claims = [for (final r in lList<List>(v['claims'])) r.whereType<String>().toList()];
    final hand = lList<String>(v['hand']);
    final allHands = v['hands'] == null ? null : [for (final r in lList<List>(v['hands'])) r.whereType<String>().toList()];
    final waiting = lInts(v['waiting']);
    final loser = lInt(v['loser'], -1);
    final me = lMe(g, n);
    final iWait = me && !g.replay && waiting.contains(g.seat);
    final exchange = lList<String>(v['exchange']);
    final k = '$phase/$turn/$action/$actor/$blocker/${hand.join()}';
    if (k != key) {
      key = k;
      pendingAction = '';
      keep = {};
    }

    String actDesc() {
      final a = _actNames[action] ?? action;
      final cr = claimRole == null ? '' : '（宣称${_rn(claimRole)}）';
      return '${g.name(actor)} 发动$a$cr${target >= 0 ? ' → ${g.name(target)}' : ''}';
    }

    String status;
    switch (phase) {
      case 'over':
        status = '游戏结束';
      case 'action':
        status = iWait ? '轮到你行动${(coins.elementAtOrNull(g.seat) ?? 0) >= 10 ? '（必须政变）' : ''}' : '等待 ${g.name(turn)} 行动';
      case 'respond':
        status = iWait ? '${actDesc()}：质疑还是放行？' : '${actDesc()}，等待其他人回应';
      case 'block':
        status = iWait ? '${actDesc()}：要阻止吗？' : '${actDesc()}，等待是否有人阻止';
      case 'respondBlock':
        status = iWait
            ? '${g.name(blocker)} 宣称${_rn(blockRole)}阻止：质疑还是放行？'
            : '${g.name(blocker)} 宣称${_rn(blockRole)}阻止，等待回应';
      case 'lose':
        status = iWait ? '你必须翻开一张角色牌（${v['loseWhy']}）' : '等待 ${g.name(loser)} 选择失去的影响力';
      case 'exchange':
        status = iWait ? '交换：选择保留 ${hand.length} 张' : '${g.name(actor)} 正在交换角色';
      default:
        status = '';
    }

    Widget seat(int s, double cw) {
      final dead = !(alive.elementAtOrNull(s) ?? true);
      final isActive = !g.over && (waiting.contains(s) || (phase == 'action' && s == turn));
      final rev = revealed.elementAtOrNull(s) ?? const <String>[];
      final hidden = handCounts.elementAtOrNull(s) ?? 0;
      final shown = allHands?.elementAtOrNull(s);
      final cl = claims.elementAtOrNull(s) ?? const <String>[];
      final isMe = s == g.seat;
      return LPanel(
        highlight: isActive,
        padding: const EdgeInsets.all(6),
        color: dead ? cs.surface.withValues(alpha: 0.4) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(
              child: g.tag(s,
                  size: 26,
                  active: isActive,
                  sub: dead ? '已出局' : (s == actor ? '行动中' : (s == target ? '目标' : (s == blocker ? '阻止者' : '影响力 $hidden')))),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.monetization_on, size: 16, color: Color(0xFFFFB300)),
            Text('${coins.elementAtOrNull(s) ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (isMe)
              for (final r in hand) Padding(padding: const EdgeInsets.only(right: 3), child: CoupCard(r, width: cw))
            else if (shown != null)
              for (final r in shown) Padding(padding: const EdgeInsets.only(right: 3), child: CoupCard(r, width: cw))
            else
              for (var i = 0; i < hidden; i++) Padding(padding: const EdgeInsets.only(right: 3), child: CoupCard(null, width: cw)),
            for (final r in rev) Padding(padding: const EdgeInsets.only(right: 3), child: CoupCard(r, width: cw, dead: true)),
          ]),
          if (cl.isNotEmpty && !dead)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('宣称过：${cl.map(_rn).join('、')}', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
            ),
        ]),
      );
    }

    List<Widget> controls() {
      if (!iWait) return const [];
      final myCoins = coins.elementAtOrNull(g.seat) ?? 0;
      final targets = [for (var s = 0; s < n; s++) if (s != g.seat && (alive.elementAtOrNull(s) ?? false)) s];
      switch (phase) {
        case 'action':
          if (pendingAction.isNotEmpty) {
            return [
              Text('选择${_actNames[pendingAction]}的目标：'),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                for (final t in targets)
                  if (pendingAction != 'steal' || (coins.elementAtOrNull(t) ?? 0) > 0)
                    FilledButton.tonal(onPressed: () => g.act({'type': pendingAction, 'target': t}), child: Text(g.name(t))),
                TextButton(onPressed: () => setState(() => pendingAction = ''), child: const Text('返回')),
              ]),
            ];
          }
          final must = myCoins >= 10;
          Widget b(String type, String label, IconData icon, {bool ok = true, String? role}) {
            final needsT = type == 'coup' || type == 'assassinate' || type == 'steal';
            final enabled = ok && (!must || type == 'coup');
            final has = role != null && hand.contains(role);
            return Tooltip(
              message: role == null ? '' : (has ? '你有${_rn(role)}' : '虚张声势：你没有${_rn(role)}'),
              child: FilledButton.tonalIcon(
                style: role != null && !has ? FilledButton.styleFrom(foregroundColor: Colors.deepOrange) : null,
                onPressed: enabled ? () => needsT ? setState(() => pendingAction = type) : g.act({'type': type}) : null,
                icon: Icon(icon, size: 18),
                label: Text(label),
              ),
            );
          }

          return [
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              b('income', '收入 +1', Icons.savings),
              b('foreignaid', '外援 +2', Icons.volunteer_activism),
              b('coup', '政变 -7', Icons.gavel, ok: myCoins >= 7),
              b('tax', '征税 +3（公爵）', Icons.account_balance, role: 'duke'),
              b('assassinate', '刺杀 -3（刺客）', Icons.dangerous, ok: myCoins >= 3, role: 'assassin'),
              b('steal', '勒索 2（队长）', Icons.anchor, role: 'captain'),
              b('exchange', '交换（大使）', Icons.swap_horiz, role: 'ambassador'),
            ]),
          ];
        case 'respond':
        case 'respondBlock':
          return [
            Wrap(spacing: 10, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () => g.act({'type': 'challenge'}),
                icon: const Icon(Icons.report),
                label: const Text('质疑！'),
              ),
              OutlinedButton.icon(onPressed: () => g.act({'type': 'pass'}), icon: const Icon(Icons.check), label: const Text('放行')),
            ]),
          ];
        case 'block':
          final roles = lList<String>(v['blockRoles']);
          return [
            Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final r in roles)
                FilledButton.icon(
                  style: hand.contains(r) ? null : FilledButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  onPressed: () => g.act({'type': 'block', 'role': r}),
                  icon: Icon(_roles[r]?.$2 ?? Icons.block),
                  label: Text('阻止（宣称${_rn(r)}${hand.contains(r) ? '' : '·虚张'}）'),
                ),
              OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('不阻止')),
            ]),
          ];
        case 'lose':
          return [
            Wrap(spacing: 8, children: [
              for (final r in hand.toSet()) FilledButton.tonal(onPressed: () => g.act({'type': 'lose', 'card': r}), child: Text('翻开 ${_rn(r)}')),
            ]),
          ];
        case 'exchange':
          return [
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (var i = 0; i < exchange.length; i++)
                CoupCard(exchange[i],
                    width: 60,
                    selected: keep.contains(i),
                    onTap: () => setState(() {
                          if (keep.contains(i)) {
                            keep.remove(i);
                          } else if (keep.length < hand.length) {
                            keep.add(i);
                          }
                        })),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: keep.length == hand.length ? () => g.act({'type': 'exchange', 'keep': [for (final i in keep) exchange[i]]}) : null,
              child: Text('保留选中的 ${keep.length}/${hand.length} 张'),
            ),
          ];
      }
      return const [];
    }

    Widget? result;
    if (phase == 'over') {
      final w = lInt(v['winner'], -1);
      result = ResultBanner(w >= 0 ? '${g.name(w)} 获胜！' : '游戏结束', child: const Text('最后保有影响力的人掌控了政权'));
    }

    final ev = v['lastEvent'] == null ? null : lMap(v['lastEvent']);
    String? evText;
    if (ev != null) {
      switch (ev['type']) {
        case 'challengeWin':
          evText = '质疑成功：${g.name(lInt(ev['against']))} 没有${_rn('${ev['role']}')}';
        case 'challengeFail':
          evText = '质疑失败：${g.name(lInt(ev['against']))} 真的有${_rn('${ev['role']}')}';
        case 'blocked':
          evText = '${g.name(lInt(ev['seat']))} 以${_rn('${ev['role']}')}阻止成功';
      }
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final others = lOthers(g, n);
      final sw = wide ? 250.0 : (c.maxWidth - 24) / 2;
      final cw = wide ? 44.0 : (sw - 30) / 4.3;
      return LFrame(
        status: status,
        highlight: iWait,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final s in others) SizedBox(width: sw, child: seat(s, cw.clamp(26.0, 48.0))),
          ]),
          const SizedBox(height: 8),
          LPanel(
            color: g.table.withValues(alpha: 0.9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const CoupCard(null, width: 28),
                const SizedBox(width: 6),
                Text('牌堆 ${lInt(v['deck'])}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ]),
              if (phase != 'action' && phase != 'over' && actor >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(actDesc(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              if (blocker >= 0 && phase == 'respondBlock')
                Text('${g.name(blocker)} 宣称${_rn(blockRole)}阻止', style: const TextStyle(color: Colors.amberAccent)),
              if (evText != null) Text(evText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          ...controls(),
          if (me) ...[const SizedBox(height: 8), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: seat(g.seat, wide ? 70 : 60))],
        ],
      );
    });
  }
}
