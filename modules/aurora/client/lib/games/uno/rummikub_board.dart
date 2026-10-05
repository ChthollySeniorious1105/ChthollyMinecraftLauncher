import 'package:aurora_shared/games/uno/rummikub.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _tileColors = [Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFFEF8F00), Color(0xFF212121)];

class RummiTile extends StatelessWidget {
  final int id;
  final double width;
  final bool selected;
  final bool highlight;
  final VoidCallback? onTap;
  const RummiTile(this.id, {super.key, this.width = 36, this.selected = false, this.highlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final joker = rkIsJoker(id);
    final col = joker ? const Color(0xFFC2185B) : _tileColors[rkColor(id)];
    Widget t = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: width,
      height: width * 1.35,
      transform: Matrix4.translationValues(0, selected ? -width * 0.2 : 0, 0),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF3C4) : const Color(0xFFFFFBEF),
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: selected ? Colors.amber : Colors.black26, width: selected ? 2.5 : 1),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 2))],
      ),
      alignment: Alignment.center,
      child: joker
          ? Icon(Icons.sentiment_very_satisfied, color: col, size: width * 0.7)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${rkNumber(id)}',
                    style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: width * 0.52, height: 1)),
                Container(
                    margin: EdgeInsets.only(top: width * 0.06),
                    width: width * 0.22,
                    height: width * 0.22,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: col, width: 1.5))),
              ]),
            ),
    );
    if (onTap == null) return t;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: t));
  }
}

class RummikubBoard extends StatefulWidget {
  final GameContext g;
  const RummikubBoard(this.g, {super.key});
  @override
  State<RummikubBoard> createState() => _RummikubBoardState();
}

class _RummikubBoardState extends State<RummikubBoard> {
  String _key = '';
  List<List<int>> _table = [];
  List<int> _rack = [];
  Set<int> _origTable = {};
  int? _sel;
  bool _byNumber = false;

  GameContext get g => widget.g;

  void _sync() {
    final v = g.view;
    final table = [for (final s in v['table'] as List) (s as List).cast<int>()];
    final rack = (v['rack'] as List).cast<int>();
    final key = '${v['turn']}|${table.map((s) => s.join(',')).join(';')}|${rack.join(',')}';
    if (key != _key) {
      _key = key;
      _reset(table, rack);
    }
  }

  void _reset(List<List<int>> table, List<int> rack) {
    _table = [for (final s in table) List.of(s)];
    _rack = List.of(rack);
    _origTable = {for (final s in table) ...s};
    _sel = null;
  }

  bool get _myTurn => !g.over && g.view['turn'] == g.seat;

  void _remove(int id) {
    _rack.remove(id);
    for (final s in _table) {
      if (!s.remove(id)) continue;
      // 拿走一张后剩下的牌可能仍能成组，但顺序被 _sortLoose 打乱过（鬼牌排在末尾），重新整理
      final n = rkNormalize(s);
      if (n != null && !identical(n, s)) {
        s
          ..clear()
          ..addAll(n);
      }
    }
    _table.removeWhere((s) => s.isEmpty);
  }

  void _moveTo(int id, int setIndex) {
    setState(() {
      final target = setIndex >= 0 && setIndex < _table.length ? _table[setIndex] : null;
      _remove(id);
      if (target != null && _table.contains(target)) {
        target.add(id);
        final n = rkNormalize(target);
        if (n != null) {
          target
            ..clear()
            ..addAll(n);
        } else {
          _sortLoose(target);
        }
      } else {
        _table.add([id]);
      }
      _sel = null;
    });
  }

  void _sortLoose(List<int> s) {
    s.sort((a, b) {
      if (rkIsJoker(a) != rkIsJoker(b)) return rkIsJoker(a) ? 1 : -1;
      final c = rkNumber(a).compareTo(rkNumber(b));
      return c != 0 ? c : rkColor(a).compareTo(rkColor(b));
    });
  }

  void _toRack(int id) {
    if (_origTable.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('桌面原有的牌不能拿回手里')));
      return;
    }
    setState(() {
      _remove(id);
      _rack.add(id);
      _sel = null;
    });
  }

  List<int> get _sortedRack {
    final r = List.of(_rack);
    r.sort((a, b) {
      if (rkIsJoker(a) != rkIsJoker(b)) return rkIsJoker(a) ? 1 : -1;
      if (_byNumber) {
        final c = rkNumber(a).compareTo(rkNumber(b));
        return c != 0 ? c : rkColor(a).compareTo(rkColor(b));
      }
      final c = rkColor(a).compareTo(rkColor(b));
      return c != 0 ? c : rkNumber(a).compareTo(rkNumber(b));
    });
    return r;
  }

  Widget _tile(int id, double w, {int setIndex = -1}) {
    final fromTable = setIndex >= 0;
    final v = g.view;
    final added = (v['lastAdded'] as List).cast<int>();
    final canMove = _myTurn && (!fromTable || (v['melded'] as List)[g.seat] == true || !_origTable.contains(id));
    final t = RummiTile(
      id,
      width: w,
      selected: _sel == id,
      highlight: fromTable && (added.contains(id) || !_origTable.contains(id)),
      onTap: canMove
          ? () {
              final sel = _sel;
              // 牌面会抢走组合/手牌区的点击：已选中别的牌时，点这张牌等同于点它所在的区域
              if (sel != null && fromTable && !_table[setIndex].contains(sel)) {
                _moveTo(sel, setIndex);
              } else if (sel != null && !fromTable && !_rack.contains(sel)) {
                _toRack(sel);
              } else {
                setState(() => _sel = sel == id ? null : id);
              }
            }
          : null,
    );
    if (!canMove) return t;
    return Draggable<int>(
      data: id,
      feedback: Material(color: Colors.transparent, child: RummiTile(id, width: w * 1.1)),
      childWhenDragging: Opacity(opacity: 0.3, child: RummiTile(id, width: w)),
      child: t,
    );
  }

  Widget _setBox(int i, double w) {
    final cs = Theme.of(context).colorScheme;
    final s = _table[i];
    final ok = rkNormalize(s) != null;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => _myTurn,
      onAcceptWithDetails: (d) => _moveTo(d.data, i),
      builder: (context, cand, _) => GestureDetector(
        onTap: _sel != null && !s.contains(_sel) ? () => _moveTo(_sel!, i) : null,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? cs.primary.withValues(alpha: 0.3) : cs.surface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ok ? Colors.transparent : Colors.redAccent, width: 2),
          ),
          child: Wrap(spacing: 2, runSpacing: 2, children: [for (final t in s) _tile(t, w, setIndex: i)]),
        ),
      ),
    );
  }

  bool _canSubmit() {
    if (!_table.every((s) => rkNormalize(s) != null)) return false;
    final added = [for (final s in _table) ...s].where((t) => !_origTable.contains(t)).toList();
    return added.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final counts = (v['counts'] as List).cast<int>();
    final melded = (v['melded'] as List).cast<bool>();
    final turn = v['turn'] as int;
    final me = g.seat;
    final myTurn = _myTurn;
    final serverTable = [for (final s in v['table'] as List) (s as List).cast<int>()];
    final serverRack = (v['rack'] as List).cast<int>();
    final dirty = _rack.length != serverRack.length || _table.length != serverTable.length ||
        _table.map((s) => s.join(',')).join(';') != serverTable.map((s) => s.join(',')).join(';');
    final addedPts = [for (final s in _table) if (s.every((t) => !_origTable.contains(t)) && rkNormalize(s) != null) rkSetValue(rkNormalize(s)!)!]
            .fold<int>(0, (a, b) => a + b);

    String status;
    if (g.over) {
      final w = v['winner'] as int;
      status = '${g.name(w)} 获胜！';
    } else if (myTurn) {
      status = me >= 0 && !melded[me] ? '轮到你：首次出牌需≥30分（新组合 $addedPts 分）' : '轮到你：整理桌面或摸牌';
    } else {
      status = '等待 ${g.name(turn)}';
    }

    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth / 18).clamp(24.0, 40.0);
      final tw = (w * 0.85).clamp(22.0, 34.0);
      return Container(
        color: g.table.withValues(alpha: 0.25),
        child: Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (final s in g.seatsFromMe())
                g.tag(s,
                    active: !g.over && s == turn,
                    size: 28,
                    sub: '${counts[s]} 张${melded[s] ? '' : ' · 未破冰'}'),
            ]),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            Text('牌池 ${v['wall']} · ${v['last']}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _table.length; i++) _setBox(i, tw),
                  if (myTurn)
                    DragTarget<int>(
                      onAcceptWithDetails: (d) => _moveTo(d.data, -1),
                      builder: (context, cand, _) => GestureDetector(
                        onTap: _sel != null ? () => _moveTo(_sel!, -1) : null,
                        child: Container(
                          width: tw * 3,
                          height: tw * 1.35 + 8,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cand.isNotEmpty ? cs.primary.withValues(alpha: 0.3) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                          child: Text('+ 新组合', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            if (me >= 0) ...[
              Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                    onPressed: () => setState(() => _byNumber = !_byNumber),
                    child: Text(_byNumber ? '按颜色排序' : '按数字排序')),
                if (myTurn) ...[
                  OutlinedButton(
                      onPressed: dirty ? () => setState(() => _reset(serverTable, serverRack)) : null,
                      child: const Text('撤销重置')),
                  FilledButton(
                      onPressed: _canSubmit()
                          ? () => g.act({'type': 'submit', 'table': _table})
                          : null,
                      child: const Text('确认出牌')),
                  FilledButton.tonal(
                      onPressed: () => g.act({'type': 'draw'}),
                      child: Text((v['wall'] as int) > 0 ? '摸牌结束' : '跳过')),
                ],
              ]),
              const SizedBox(height: 4),
              DragTarget<int>(
                onWillAcceptWithDetails: (d) => !_origTable.contains(d.data),
                onAcceptWithDetails: (d) => _toRack(d.data),
                builder: (context, cand, _) => GestureDetector(
                  onTap: _sel != null && !_rack.contains(_sel) ? () => _toRack(_sel!) : null,
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: w * 1.35 + 16, maxHeight: c.maxHeight * 0.32),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (cand.isNotEmpty ? cs.primary : const Color(0xFF6D4C41)).withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 3,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [for (final t in _sortedRack) _tile(t, w)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          if (g.over)
            Align(
              alignment: Alignment.center,
              child: ResultBanner(
                status,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var s = 0; s < counts.length; s++)
                    Text('${g.name(s)}：${(v['scores'] as List).length > s ? (v['scores'] as List)[s] : 0} 分（剩 ${counts[s]} 张）'),
                ]),
              ),
            ),
        ]),
      );
    });
  }
}
