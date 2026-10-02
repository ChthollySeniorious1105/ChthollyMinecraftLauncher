import 'dart:math';

import 'package:aurora_shared/games/social/catan_geo.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

const _resNames = ['木材', '砖块', '羊毛', '小麦', '矿石'];
const _resEmoji = ['🌲', '🧱', '🐑', '🌾', '⛰'];
const _resColors = [Color(0xFF2E7D32), Color(0xFFC1502E), Color(0xFF9CCC65), Color(0xFFF9C22E), Color(0xFF78909C)];
const _desertColor = Color(0xFFE6D3A3);
const _playerColors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFB8C00), Color(0xFFF5F5F5)];
const _devNames = {'knight': '骑士', 'vp': '胜利点', 'road': '道路建设', 'plenty': '丰收之年', 'mono': '垄断'};
const _devDesc = {
  'knight': '移动强盗并抢夺一张牌',
  'vp': '胜利点 +1（自动计分）',
  'road': '免费修建两条道路',
  'plenty': '从银行拿取任意两张资源',
  'mono': '指定一种资源，所有人把该资源交给你',
};

List<int> _ints(Object? v) => v is List ? [for (final e in v) (e as num).toInt()] : <int>[];

class CatanBoard extends StatefulWidget {
  final GameContext g;
  const CatanBoard(this.g, {super.key});
  @override
  State<CatanBoard> createState() => _CatanBoardState();
}

class _CatanBoardState extends State<CatanBoard> {
  String mode = ''; // '' road settle city
  final geo = CatanGeo.instance;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<Map<String, dynamic>> get pl => [for (final p in v['players'] as List) (p as Map).cast<String, dynamic>()];

  bool get myTurn => !g.over && v['turn'] == g.seat;
  String get phase => v['phase'] as String;
  Map<String, dynamic>? get offer => (v['offer'] as Map?)?.cast<String, dynamic>();

  /// Which build mode is effectively active.
  String get effMode {
    if (!myTurn) return '';
    if (phase == 'setup') return v['setupStep'] as String;
    if (phase == 'roads') return 'road';
    if (phase == 'robber') return 'robber';
    if (phase == 'main' && offer == null) return mode;
    return '';
  }

  List<int> legal(String k) => _ints((v['legal'] as Map?)?[k]);

  String _status() {
    final turn = v['turn'] as int;
    if (g.over || phase == 'over') {
      final w = v['winner'] as int;
      return w >= 0 ? '${g.name(w)} 获胜！' : '对局结束';
    }
    final me = g.seat >= 0 ? pl[g.seat] : null;
    switch (phase) {
      case 'setup':
        if (!myTurn) return '等待 ${g.name(turn)} 初始布置';
        return v['setupStep'] == 'settle' ? '初始布置：点击高亮位置放置村庄' : '初始布置：放置一条连接村庄的道路';
      case 'roll':
        return myTurn ? '轮到你：请掷骰子' : '等待 ${g.name(turn)} 掷骰子';
      case 'discard':
        if (me != null && (me['discard'] as int) > 0) return '掷出 7！请弃掉 ${me['discard']} 张牌';
        return '掷出 7，等待玩家弃牌';
      case 'robber':
        return myTurn ? '点击一个地块移动强盗' : '等待 ${g.name(turn)} 移动强盗';
      case 'roads':
        return myTurn ? '道路建设：还可免费修 ${v['freeRoads']} 条路' : '${g.name(turn)} 正在免费修路';
      default:
        if (!myTurn) return '${g.name(turn)} 的回合';
        return switch (effMode) {
          'road' => '选择高亮的边修路',
          'settle' => '选择高亮的路口建村庄',
          'city' => '选择要升级的村庄',
          _ => '你的回合：建造、交易或结束回合',
        };
    }
  }

  void _tapBoard(Offset unit) {
    final m = effMode;
    if (m == 'settle' || m == 'city') {
      final spots = legal(m);
      final i = _nearest(spots, (x) => Offset(geo.vx[x], geo.vy[x]), unit, 0.5);
      if (i != null) {
        g.act({'type': m, 'v': i});
        if (phase == 'main') setState(() => mode = '');
      }
    } else if (m == 'road') {
      final spots = legal('road');
      final i = _nearest(spots, (e) {
        final [a, b] = geo.edgeVerts[e];
        return Offset((geo.vx[a] + geo.vx[b]) / 2, (geo.vy[a] + geo.vy[b]) / 2);
      }, unit, 0.45);
      if (i != null) {
        g.act({'type': 'road', 'e': i});
        if (phase == 'main') setState(() => mode = '');
      }
    } else if (m == 'robber') {
      final hexes = [for (var h = 0; h < geo.nHex; h++) if (h != v['robber']) h];
      final h = _nearest(hexes, (h) => Offset(geo.hx[h], geo.hy[h]), unit, 0.9);
      if (h != null) _robber(h);
    }
  }

  int? _nearest(List<int> items, Offset Function(int) pos, Offset p, double maxD) {
    int? best;
    var bd = maxD;
    for (final i in items) {
      final d = (pos(i) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  Future<void> _robber(int h) async {
    final owners = _ints(v['vertOwner']);
    final cands = <int>{};
    for (final x in geo.hexVerts[h]) {
      final o = owners[x];
      if (o >= 0 && o != g.seat && (pl[o]['cards'] as int) > 0) cands.add(o);
    }
    if (cands.length <= 1) {
      g.act({'type': 'robber', 'hex': h, 'target': cands.isEmpty ? -1 : cands.first});
      return;
    }
    final t = await showDialog<int>(useRootNavigator: false, 
      context: context,
      builder: (c) => SimpleDialog(title: const Text('抢夺谁的资源？'), children: [
        for (final s in cands)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, s),
            child: Row(children: [
              _dot(s),
              const SizedBox(width: 8),
              Text('${g.name(s)}（${pl[s]['cards']} 张）'),
            ]),
          ),
      ]),
    );
    if (t != null) g.act({'type': 'robber', 'hex': h, 'target': t});
  }

  Widget _dot(int s, [double size = 14]) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: _playerColors[s % 4], shape: BoxShape.circle, border: Border.all(color: Colors.black54)),
      );

  // ------------------------------------------------------------- widgets
  Widget _playerTag(int s, {bool compact = false}) {
    final p = pl[s];
    final badges = <String>[
      if (v['longestRoad'] == s) '🛣最长道路',
      if (v['largestArmy'] == s) '⚔最大骑士团',
    ];
    final sub = '${p['vp']}分 · 手牌${p['cards']} · 发展卡${p['devCount']}'
        '${compact ? '' : '\n骑士${p['knights']} · 道路${p['road']}'}'
        '${badges.isEmpty ? '' : '\n${badges.join(' ')}'}';
    return g.tag(s,
        active: !g.over && v['turn'] == s,
        size: compact ? 28 : 34,
        sub: sub,
        trailing: _dot(s, compact ? 12 : 16));
  }

  Widget _resChip(int r, int n, {VoidCallback? onTap, bool dim = false}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: _resColors[r].withValues(alpha: dim ? 0.35 : 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_resEmoji[r], style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 3),
        Text('$n', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15)),
      ]),
    );
    return Tooltip(
      message: _resNames[r],
      child: onTap == null ? chip : InkWell(onTap: onTap, child: chip),
    );
  }

  Widget _hand() {
    final hand = _ints(v['hand']);
    if (hand.isEmpty) return const SizedBox();
    final dev = (v['dev'] as List).cast<String>();
    final devNew = (v['devNew'] as List).cast<String>();
    return Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var r = 0; r < 5; r++) _resChip(r, hand[r]),
      ActionChip(
        avatar: const Icon(Icons.style, size: 16),
        label: Text('发展卡 ${dev.length + devNew.length}'),
        onPressed: _devDialog,
        visualDensity: VisualDensity.compact,
      ),
    ]);
  }

  List<Widget> _actions() {
    if (!myTurn || g.seat < 0) return const [];
    final hand = _ints(v['hand']);
    bool afford(List<int> c) => [for (var r = 0; r < 5; r++) hand[r] >= c[r]].every((x) => x);
    final me = pl[g.seat];
    Widget btn(String label, IconData icon, VoidCallback? onTap, {bool selected = false}) => Padding(
          padding: const EdgeInsets.all(2),
          child: selected
              ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label))
              : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label)),
        );
    if (phase == 'roll') {
      final dev = (v['dev'] as List).cast<String>();
      return [
        btn('掷骰子', Icons.casino, () => g.act({'type': 'roll'}), selected: true),
        if (dev.contains('knight') && v['playedDev'] != true)
          btn('使用骑士', Icons.shield, () => g.act({'type': 'playDev', 'card': 'knight'})),
      ];
    }
    if (phase == 'roads') return [btn('结束修路', Icons.check, () => g.act({'type': 'end'}))];
    if (phase != 'main' || offer != null) return const [];
    void toggle(String m) => setState(() => mode = mode == m ? '' : m);
    return [
      btn('道路', Icons.horizontal_rule,
          afford(const [1, 1, 0, 0, 0]) && (me['roads'] as int) > 0 && legal('road').isNotEmpty ? () => toggle('road') : null,
          selected: mode == 'road'),
      btn('村庄', Icons.home,
          afford(const [1, 1, 1, 1, 0]) && (me['settlements'] as int) > 0 && legal('settle').isNotEmpty
              ? () => toggle('settle')
              : null,
          selected: mode == 'settle'),
      btn('城市', Icons.location_city,
          afford(const [0, 0, 0, 2, 3]) && (me['cities'] as int) > 0 && legal('city').isNotEmpty ? () => toggle('city') : null,
          selected: mode == 'city'),
      btn('买发展卡', Icons.style,
          afford(const [0, 0, 1, 1, 1]) && (v['devLeft'] as int) > 0 ? () => g.act({'type': 'buyDev'}) : null),
      btn('银行交易', Icons.account_balance, _bankDialog),
      btn('玩家交易', Icons.handshake, _tradeDialog),
      btn('结束回合', Icons.skip_next, () {
        setState(() => mode = '');
        g.act({'type': 'end'});
      }, selected: true),
    ];
  }

  Widget _costHint() => Text(
        '费用：道路🌲🧱 · 村庄🌲🧱🐑🌾 · 城市🌾×2⛰×3 · 发展卡🐑🌾⛰',
        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
      );

  Widget _dice() {
    final d = _ints(v['dice']);
    if (d.length != 2) return const SizedBox();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      DieFace(d[0], size: 28),
      const SizedBox(width: 4),
      DieFace(d[1], size: 28),
      const SizedBox(width: 6),
      Text('= ${d[0] + d[1]}', style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _info() {
    final bank = _ints(v['bank']);
    final cs = Theme.of(context).colorScheme;
    return Text(
      '银行：${[for (var r = 0; r < 5; r++) '${_resEmoji[r]}${bank[r]}'].join(' ')}  发展卡剩 ${v['devLeft']}  '
      '回合 ${v['turnCount']}/${v['maxTurns']}  目标 ${v['target']} 分',
      style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.8)),
    );
  }

  // ------------------------------------------------------------- overlays
  Widget? _offerPanel() {
    final o = offer;
    if (o == null) return null;
    final from = o['from'] as int;
    final give = _ints(o['give']), get = _ints(o['get']);
    final resp = (o['responses'] as Map).map((k, val) => MapEntry(int.parse(k as String), val as String));
    String fmt(List<int> c) => [for (var r = 0; r < 5; r++) if (c[r] > 0) '${_resEmoji[r]}×${c[r]}'].join(' ');
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[
      Text('${g.name(from)} 发起交易', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('给出 ${fmt(give)}  换取 ${fmt(get)}'),
      const SizedBox(height: 4),
      Wrap(spacing: 6, children: [
        for (final e in resp.entries)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: _dot(e.key),
            label: Text('${g.name(e.key)}：${const {'pending': '考虑中', 'accept': '接受', 'decline': '拒绝'}[e.value]}'),
          ),
      ]),
    ];
    if (g.seat == from) {
      children.add(Wrap(spacing: 6, children: [
        for (final e in resp.entries)
          if (e.value == 'accept')
            FilledButton(
                onPressed: () => g.act({'type': 'confirmTrade', 'with': e.key}), child: Text('与 ${g.name(e.key)} 成交')),
        OutlinedButton(onPressed: () => g.act({'type': 'cancelOffer'}), child: const Text('取消交易')),
      ]));
    } else if (resp[g.seat] == 'pending') {
      final hand = _ints(v['hand']);
      final can = [for (var r = 0; r < 5; r++) hand[r] >= get[r]].every((x) => x);
      children.add(Wrap(spacing: 6, children: [
        FilledButton(onPressed: can ? () => g.act({'type': 'respond', 'accept': true}) : null, child: const Text('接受')),
        OutlinedButton(onPressed: () => g.act({'type': 'respond', 'accept': false}), child: const Text('拒绝')),
      ]));
    }
    return Card(
      color: cs.surface.withValues(alpha: 0.95),
      elevation: 6,
      child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisSize: MainAxisSize.min, children: children)),
    );
  }

  Widget? _discardPanel() {
    if (phase != 'discard' || g.seat < 0) return null;
    final need = pl[g.seat]['discard'] as int;
    if (need <= 0) return null;
    return _DiscardPanel(
      key: ValueKey('discard${v['turnCount']}'),
      hand: _ints(v['hand']),
      need: need,
      onSubmit: (c) => g.act({'type': 'discard', 'cards': c}),
    );
  }

  // ------------------------------------------------------------- dialogs
  Future<void> _bankDialog() async {
    final hand = _ints(v['hand']);
    final ratios = _ints(v['ratios']);
    final bank = _ints(v['bank']);
    int? give, get;
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return AlertDialog(
          title: const Text('与银行交易'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('给出（按港口比例）：'),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var r = 0; r < 5; r++)
                ChoiceChip(
                  label: Text('${_resEmoji[r]} ${ratios[r]}:1'),
                  selected: give == r,
                  onSelected: hand[r] >= ratios[r] ? (_) => set(() => give = r) : null,
                ),
            ]),
            const SizedBox(height: 10),
            const Text('换取 1 张：'),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var r = 0; r < 5; r++)
                ChoiceChip(
                  label: Text('${_resEmoji[r]} ${_resNames[r]}'),
                  selected: get == r,
                  onSelected: bank[r] > 0 && r != give ? (_) => set(() => get = r) : null,
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: give != null && get != null && give != get
                  ? () {
                      Navigator.pop(c);
                      g.act({'type': 'bank', 'give': give, 'get': get});
                    }
                  : null,
              child: const Text('交易'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _tradeDialog() async {
    final hand = _ints(v['hand']);
    final give = List.filled(5, 0), get = List.filled(5, 0);
    var to = -1;
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Widget row(List<int> arr, int r, int maxN) => Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 28, child: Text(_resEmoji[r], style: const TextStyle(fontSize: 18))),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: arr[r] > 0 ? () => set(() => arr[r]--) : null,
                  icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(width: 18, child: Text('${arr[r]}', textAlign: TextAlign.center)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: arr[r] < maxN ? () => set(() => arr[r]++) : null,
                  icon: const Icon(Icons.add_circle_outline)),
            ]);
        final ok = give.any((x) => x > 0) && get.any((x) => x > 0) && [for (var r = 0; r < 5; r++) !(give[r] > 0 && get[r] > 0)].every((x) => x);
        return AlertDialog(
          title: const Text('发起玩家交易'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 16, children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('我给出', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (var r = 0; r < 5; r++) row(give, r, hand[r]),
                ]),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('我想要', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (var r = 0; r < 5; r++) row(get, r, 9),
                ]),
              ]),
              const SizedBox(height: 8),
              DropdownButton<int>(
                value: to,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('所有玩家')),
                  for (var s = 0; s < g.players; s++)
                    if (s != g.seat) DropdownMenuItem(value: s, child: Text(g.name(s))),
                ],
                onChanged: (x) => set(() => to = x ?? -1),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: ok
                  ? () {
                      Navigator.pop(c);
                      g.act({'type': 'offer', 'give': give, 'get': get, 'to': to});
                    }
                  : null,
              child: const Text('发起'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _devDialog() async {
    final dev = (v['dev'] as List).cast<String>();
    final devNew = (v['devNew'] as List).cast<String>();
    final canPlay = myTurn && (phase == 'main' && offer == null || phase == 'roll') && v['playedDev'] != true;
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (c) {
        Widget item(String card, bool fresh) {
          final playable = canPlay && !fresh && card != 'vp' && (phase == 'main' || card == 'knight');
          return ListTile(
            leading: Icon(card == 'knight' ? Icons.shield : (card == 'vp' ? Icons.star : Icons.auto_awesome)),
            title: Text('${_devNames[card]}${fresh ? '（本回合购买）' : ''}'),
            subtitle: Text(_devDesc[card] ?? ''),
            trailing: playable
                ? FilledButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await _playDev(card);
                    },
                    child: const Text('使用'))
                : null,
          );
        }

        return AlertDialog(
          title: const Text('我的发展卡'),
          content: SizedBox(
            width: 360,
            child: dev.isEmpty && devNew.isEmpty
                ? const Text('你还没有发展卡')
                : ListView(shrinkWrap: true, children: [
                    for (final d in dev) item(d, false),
                    for (final d in devNew) item(d, true),
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
        );
      },
    );
  }

  Future<void> _playDev(String card) async {
    if (card == 'knight' || card == 'road') {
      g.act({'type': 'playDev', 'card': card});
      return;
    }
    final picks = <int>[];
    final n = card == 'plenty' ? 2 : 1;
    final res = await showDialog<List<int>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(card == 'plenty' ? '丰收之年：选择两张资源' : '垄断：选择一种资源'),
          content: Wrap(spacing: 6, runSpacing: 6, children: [
            for (var r = 0; r < 5; r++)
              ActionChip(
                label: Text('${_resEmoji[r]} ${_resNames[r]}'),
                onPressed: picks.length < n ? () => set(() => picks.add(r)) : null,
              ),
            if (picks.isNotEmpty) Text('已选：${picks.map((r) => _resEmoji[r]).join(' ')}'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            TextButton(onPressed: () => set(picks.clear), child: const Text('重选')),
            FilledButton(
                onPressed: picks.length == n ? () => Navigator.pop(c, List.of(picks)) : null, child: const Text('确定')),
          ],
        ),
      ),
    );
    if (res == null) return;
    g.act({'type': 'playDev', 'card': card, 'res': card == 'plenty' ? res : res.first});
  }

  // ------------------------------------------------------------- build
  Widget _boardArea() {
    final m = effMode;
    final highV = m == 'settle' || m == 'city' ? legal(m).toSet() : <int>{};
    final highE = m == 'road' ? legal('road').toSet() : <int>{};
    final highH = m == 'robber' ? {for (var h = 0; h < geo.nHex; h++) if (h != v['robber']) h} : <int>{};
    final overlays = [_offerPanel(), _discardPanel()].whereType<Widget>().toList();
    return LayoutBuilder(builder: (context, c) {
      final painter = _CatanPainter(v, geo, highV, highE, highH, Theme.of(context).colorScheme);
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tapBoard(painter.toUnit(d.localPosition, c.biggest)),
            child: CustomPaint(painter: painter, size: c.biggest),
          ),
        ),
        if (overlays.isNotEmpty)
          Positioned(
            top: 4,
            left: 4,
            right: 4,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: overlays),
              ),
            ),
          ),
        if (g.over || phase == 'over')
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Center(child: ResultBanner(_status(), child: _finalScores())),
          ),
      ]);
    });
  }

  Widget _finalScores() {
    final order = [for (var s = 0; s < g.players; s++) s]..sort((a, b) => (pl[b]['vp'] as int).compareTo(pl[a]['vp'] as int));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final s in order)
        Row(mainAxisSize: MainAxisSize.min, children: [
          _dot(s),
          const SizedBox(width: 6),
          Text('${g.name(s)}：${pl[s]['vp']} 分'),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (phase != 'main' && mode.isNotEmpty) mode = '';
    final status = StatusBar(_status(), highlight: myTurn || (phase == 'discard' && g.seat >= 0 && (pl[g.seat]['discard'] as int) > 0));
    final event = (v['event'] as String?) ?? '';
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760 && c.maxWidth > c.maxHeight * 1.05;
      final seats = g.seatsFromMe();
      if (wide) {
        return Row(children: [
          Expanded(
            child: Column(children: [
              const SizedBox(height: 6),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.center, children: [status, _dice()]),
              if (event.isNotEmpty) Text(event, style: const TextStyle(fontSize: 12)),
              Expanded(child: _boardArea()),
            ]),
          ),
          Container(
            width: 330,
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
            child: ListView(padding: const EdgeInsets.all(8), children: [
              for (final s in seats) Padding(padding: const EdgeInsets.only(bottom: 4), child: Align(alignment: Alignment.centerLeft, child: _playerTag(s))),
              const Divider(),
              _info(),
              const SizedBox(height: 6),
              if (g.seat >= 0) ...[
                const Text('我的资源', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _hand(),
                const SizedBox(height: 6),
              ],
              Wrap(children: _actions()),
              const SizedBox(height: 4),
              _costHint(),
            ]),
          ),
        ]);
      }
      return Column(children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(4),
            children: [for (final s in seats) Padding(padding: const EdgeInsets.only(right: 4), child: _playerTag(s, compact: true))],
          ),
        ),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.center, children: [status, _dice()]),
        if (event.isNotEmpty) Text(event, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
        Expanded(child: _boardArea()),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (g.seat >= 0) _hand(),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _actions())),
            _info(),
          ]),
        ),
      ]);
    });
  }
}

class _DiscardPanel extends StatefulWidget {
  final List<int> hand;
  final int need;
  final void Function(List<int>) onSubmit;
  const _DiscardPanel({super.key, required this.hand, required this.need, required this.onSubmit});
  @override
  State<_DiscardPanel> createState() => _DiscardPanelState();
}

class _DiscardPanelState extends State<_DiscardPanel> {
  final sel = List.filled(5, 0);
  @override
  Widget build(BuildContext context) {
    final total = sel.fold(0, (a, b) => a + b);
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('弃掉 ${widget.need} 张牌（已选 $total）', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (var r = 0; r < 5; r++)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${_resEmoji[r]} ${sel[r]}/${widget.hand[r]}'),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: sel[r] > 0 ? () => setState(() => sel[r]--) : null,
                      icon: const Icon(Icons.remove)),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: sel[r] < widget.hand[r] && total < widget.need ? () => setState(() => sel[r]++) : null,
                      icon: const Icon(Icons.add)),
                ]),
              ]),
          ]),
          FilledButton(onPressed: total == widget.need ? () => widget.onSubmit(List.of(sel)) : null, child: const Text('确认弃牌')),
        ]),
      ),
    );
  }
}

class _CatanPainter extends CustomPainter {
  final Map<String, dynamic> v;
  final CatanGeo geo;
  final Set<int> highV, highE, highH;
  final ColorScheme cs;
  _CatanPainter(this.v, this.geo, this.highV, this.highE, this.highH, this.cs);

  static const _bx = 5.35, _by = 5.35;

  (double, Offset) _xf(Size size) {
    final s = min(size.width / (2 * _bx), size.height / (2 * _by));
    return (s, Offset(size.width / 2, size.height / 2));
  }

  Offset toUnit(Offset p, Size size) {
    final (s, o) = _xf(size);
    return (p - o) / s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (s, o) = _xf(size);
    Offset P(double x, double y) => o + Offset(x, y) * s;
    Offset V(int i) => P(geo.vx[i], geo.vy[i]);

    final tileRes = _ints(v['tileRes']);
    final tileNum = _ints(v['tileNum']);
    final vertOwner = _ints(v['vertOwner']);
    final vertLevel = _ints(v['vertLevel']);
    final edgeOwner = _ints(v['edgeOwner']);
    final robber = v['robber'] as int;
    final lastV = v['lastV'] as int? ?? -1;
    final lastE = v['lastE'] as int? ?? -1;

    // sea
    final sea = Path()..addOval(Rect.fromCircle(center: o, radius: s * 5.3));
    canvas.drawShadow(sea, Colors.black, 6, false);
    canvas.drawPath(sea, Paint()..color = const Color(0xFF3F8FC5));
    canvas.drawPath(
        sea,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.08
          ..color = const Color(0xFF2B6A96));

    // harbors
    for (final h in (v['harbors'] as List)) {
      final e = (h['e'] as num).toInt();
      final t = (h['t'] as num).toInt();
      final [a, b] = geo.edgeVerts[e];
      final mx = (geo.vx[a] + geo.vx[b]) / 2, my = (geo.vy[a] + geo.vy[b]) / 2;
      final len = sqrt(mx * mx + my * my);
      final c = P(mx + mx / len * 0.62, my + my / len * 0.62);
      final dock = Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = s * 0.09
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c, V(a), dock);
      canvas.drawLine(c, V(b), dock);
      canvas.drawCircle(c, s * 0.34, Paint()..color = t < 0 ? const Color(0xFFFFF8E1) : _resColors[t]);
      canvas.drawCircle(
          c,
          s * 0.34,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.04
            ..color = const Color(0xFF5D4037));
      _text(canvas, t < 0 ? '3:1' : '2:1', c + Offset(0, t < 0 ? 0 : s * 0.13), s * 0.2, Colors.black87, bold: true);
      if (t >= 0) _text(canvas, _resEmoji[t], c - Offset(0, s * 0.11), s * 0.2, Colors.black);
    }

    // tiles
    for (var h = 0; h < geo.nHex; h++) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final p = V(geo.hexVerts[h][i]);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      final r = tileRes[h];
      final c = P(geo.hx[h], geo.hy[h]);
      final base = r < 0 ? _desertColor : _resColors[r];
      canvas.drawPath(
          path,
          Paint()
            ..shader = RadialGradient(colors: [Color.lerp(base, Colors.white, 0.25)!, base])
                .createShader(Rect.fromCircle(center: c, radius: s)));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.06
            ..color = const Color(0xFFF3E5C0));
      if (highH.contains(h)) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.1
              ..color = Colors.yellowAccent.withValues(alpha: 0.9));
      }
      _text(canvas, r < 0 ? '🏜' : _resEmoji[r], c - Offset(0, s * 0.5), s * 0.34, Colors.black);
      final n = tileNum[h];
      if (n > 0) {
        final tc = c + Offset(0, s * 0.12);
        canvas.drawCircle(tc + Offset(s * 0.02, s * 0.03), s * 0.32, Paint()..color = Colors.black26);
        canvas.drawCircle(tc, s * 0.32, Paint()..color = const Color(0xFFFFF3D6));
        final red = n == 6 || n == 8;
        _text(canvas, '$n', tc - Offset(0, s * 0.05), s * (red ? 0.3 : 0.26), red ? const Color(0xFFC62828) : Colors.black87,
            bold: true);
        final pips = CatanGeo.pips(n);
        for (var k = 0; k < pips; k++) {
          canvas.drawCircle(tc + Offset((k - (pips - 1) / 2) * s * 0.07, s * 0.17), s * 0.025,
              Paint()..color = red ? const Color(0xFFC62828) : Colors.black87);
        }
      }
    }

    // robber
    {
      final c = P(geo.hx[robber], geo.hy[robber]) + Offset(s * 0.48, s * 0.1);
      final paint = Paint()..color = const Color(0xFF263238);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(0, s * 0.12), width: s * 0.3, height: s * 0.38), paint);
      canvas.drawCircle(c - Offset(0, s * 0.14), s * 0.11, paint);
      canvas.drawOval(
          Rect.fromCenter(center: c + Offset(0, s * 0.3), width: s * 0.36, height: s * 0.1), Paint()..color = Colors.black54);
    }

    // roads
    for (var e = 0; e < geo.nEdge; e++) {
      final [a, b] = geo.edgeVerts[e];
      final pa = V(a), pb = V(b);
      final qa = Offset.lerp(pa, pb, 0.14)!, qb = Offset.lerp(pa, pb, 0.86)!;
      final o = edgeOwner[e];
      if (o >= 0) {
        if (e == lastE) {
          canvas.drawLine(qa, qb, Paint()
            ..color = Colors.yellowAccent
            ..strokeWidth = s * 0.26
            ..strokeCap = StrokeCap.round);
        }
        canvas.drawLine(qa, qb, Paint()
          ..color = Colors.black87
          ..strokeWidth = s * 0.19
          ..strokeCap = StrokeCap.round);
        canvas.drawLine(qa, qb, Paint()
          ..color = _playerColors[o % 4]
          ..strokeWidth = s * 0.12
          ..strokeCap = StrokeCap.round);
      } else if (highE.contains(e)) {
        canvas.drawLine(qa, qb, Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = s * 0.13
          ..strokeCap = StrokeCap.round);
        canvas.drawLine(qa, qb, Paint()
          ..color = cs.primary
          ..strokeWidth = s * 0.06
          ..strokeCap = StrokeCap.round);
      }
    }

    // buildings
    for (var i = 0; i < geo.nVert; i++) {
      final o = vertOwner[i];
      final p = V(i);
      if (o >= 0) {
        final col = _playerColors[o % 4];
        final path = Path();
        final u = s * (vertLevel[i] == 2 ? 0.2 : 0.16);
        if (vertLevel[i] == 2) {
          // city: tall house + wide base
          path
            ..moveTo(p.dx - u * 1.3, p.dy + u)
            ..lineTo(p.dx + u * 1.3, p.dy + u)
            ..lineTo(p.dx + u * 1.3, p.dy - u * 0.2)
            ..lineTo(p.dx, p.dy - u * 0.2)
            ..lineTo(p.dx, p.dy - u * 0.9)
            ..lineTo(p.dx - u * 0.65, p.dy - u * 1.5)
            ..lineTo(p.dx - u * 1.3, p.dy - u * 0.9)
            ..close();
        } else {
          path
            ..moveTo(p.dx - u, p.dy + u)
            ..lineTo(p.dx + u, p.dy + u)
            ..lineTo(p.dx + u, p.dy - u * 0.3)
            ..lineTo(p.dx, p.dy - u * 1.2)
            ..lineTo(p.dx - u, p.dy - u * 0.3)
            ..close();
        }
        if (i == lastV) canvas.drawCircle(p, s * 0.33, Paint()..color = Colors.yellowAccent.withValues(alpha: 0.6));
        canvas.drawShadow(path, Colors.black, 3, false);
        canvas.drawPath(path, Paint()..color = col);
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.035
              ..color = Colors.black87);
      }
      if (highV.contains(i)) {
        canvas.drawCircle(p, s * 0.17, Paint()..color = Colors.white.withValues(alpha: 0.9));
        canvas.drawCircle(
            p,
            s * 0.17,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.05
              ..color = cs.primary);
      }
    }
  }

  void _text(Canvas canvas, String t, Offset center, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamilyFallback: kFontFallback, fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : null, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CatanPainter old) => true;
}
