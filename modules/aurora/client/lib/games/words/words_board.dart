import 'package:aurora_shared/games/words/handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';

int _int(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> _ints(Object? o) => o is List ? [for (final e in o) _int(e, 0)] : <int>[];
List<bool> _bools(Object? o) => o is List ? [for (final e in o) e == true] : <bool>[];
Map<String, dynamic>? _map(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
List<Map<String, dynamic>> _maps(Object? o) =>
    o is List ? [for (final e in o) if (e is Map) e.cast<String, dynamic>()] : <Map<String, dynamic>>[];
List<String> _strs(Object? o) => o is List ? [for (final e in o) '$e'] : <String>[];
List<List<String>> _strss(Object? o) => o is List ? [for (final e in o) _strs(e)] : <List<String>>[];

/// Colour palette for one game.
class _Pal {
  final Color green, yellow, grey;
  const _Pal(this.green, this.yellow, this.grey);
  Color of(String m, Color none) => switch (m) { 'g' => green, 'y' => yellow, 'x' => grey, _ => none };
}

const _wordlePal = _Pal(Color(0xFF6AAA64), Color(0xFFC9B458), Color(0xFF787C7E));
const _handlePal = _Pal(Color(0xFF1D9C9C), Color(0xFFDE7525), Color(0xFF9E9E9E));

String _toneMark(String t) => switch (t) { '1' => 'ˉ', '2' => 'ˊ', '3' => 'ˇ', '4' => 'ˋ', _ => '·' };
String _fin(String f) => f.replaceAll('v', 'ü');

/// Shared board for Wordle (`handle == false`) and 汉兜 (`handle == true`).
class WordsBoard extends StatefulWidget {
  final GameContext g;
  final bool handle;
  const WordsBoard(this.g, {super.key, required this.handle});
  @override
  State<WordsBoard> createState() => _WordsBoardState();
}

class _WordsBoardState extends State<WordsBoard> {
  final FocusNode _focus = FocusNode(debugLabel: 'wordle');
  final TextEditingController _text = TextEditingController();
  String _typed = '';
  String _stamp = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  bool get handle => widget.handle;
  _Pal get pal => handle ? _handlePal : _wordlePal;
  int get cols => handle ? 4 : 5;
  int get maxRows => _int(v['max'], 6);
  String get phase => '${v['phase'] ?? 'play'}';
  int get me => g.seat;
  bool get seated => me >= 0 && me < g.players;
  List<Map<String, dynamic>> get mine => _maps(v['mine']);
  List<List<String>> get marks => _strss(v['marks']);
  List<String> get myMarks => seated && me < marks.length ? marks[me] : const [];
  bool get myDone => seated && me < _bools(v['done']).length && _bools(v['done'])[me];
  bool get canPlay => seated && phase == 'play' && !myDone && !g.replay;

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _syncStamp() {
    final s = '${v['round']}:${mine.length}';
    if (s != _stamp) {
      _stamp = s;
      _typed = '';
      if (_text.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _text.clear();
        });
      }
    }
  }

  // ---- input ----------------------------------------------------------------

  void _key(String k) {
    if (!canPlay) return;
    if (!_focus.hasFocus) _focus.requestFocus();
    setState(() {
      if (k == 'back') {
        if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
      } else if (k == 'enter') {
        _submitWordle();
      } else if (_typed.length < 5) {
        _typed += k;
      }
    });
  }

  void _submitWordle() {
    if (_typed.length != 5) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('请输入 5 个字母'), duration: Duration(seconds: 1)));
      return;
    }
    g.act({'type': 'guess', 'word': _typed});
  }

  void _submitHandle() {
    final t = _text.text.trim();
    if (t.isEmpty || !canPlay) return;
    g.act({'type': 'guess', 'word': t});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (handle || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) {
      _key('back');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _key('enter');
      return KeyEventResult.handled;
    }
    final ch = e.character?.toLowerCase();
    if (ch != null && ch.length == 1 && RegExp(r'[a-z]').hasMatch(ch)) {
      _key(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _giveUp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃本轮？'),
        content: const Text('放弃后本轮得 0 分，等待其他玩家完成。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('放弃')),
        ],
      ),
    );
    if (ok == true) g.act({'type': 'giveup'});
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _syncStamp();
    return Focus(
      focusNode: _focus,
      autofocus: !handle,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: handle ? null : () => _focus.requestFocus(),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 600 && box.maxWidth > box.maxHeight * 1.15;
          final body = wide ? _wide(context, box) : _tall(context, box);
          final banner = _banner();
          return Stack(children: [
            Positioned.fill(child: body),
            if (banner != null)
              Align(alignment: Alignment.center, child: FittedBox(fit: BoxFit.scaleDown, child: banner)),
          ]);
        }),
      ),
    );
  }

  Widget _tall(BuildContext context, BoxConstraints box) {
    final kbH = handle ? 0.0 : (box.maxHeight * 0.2).clamp(96.0, 168.0);
    return Column(children: [
      _status(context),
      SizedBox(height: box.maxHeight < 500 ? 62 : 88, child: _strip(context)),
      if (v['answer'] != null) Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: _answerCard(context)),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: seated ? _myBoard(context) : _spectate(context),
        ),
      ),
      if (seated && !handle) SizedBox(height: kbH, child: _keyboard(context)),
      if (seated && handle) _handleInput(context),
      const SizedBox(height: 6),
    ]);
  }

  Widget _wide(BuildContext context, BoxConstraints box) {
    final side = (box.maxWidth * 0.3).clamp(220.0, 360.0);
    final kbH = handle ? 0.0 : (box.maxHeight * 0.26).clamp(84.0, 170.0);
    return Column(children: [
      _status(context),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(children: [
              if (v['answer'] != null) Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 0), child: _answerCard(context)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: seated ? _myBoard(context) : _spectate(context),
                ),
              ),
              if (seated && !handle) SizedBox(height: kbH, child: _keyboard(context)),
              if (seated && handle) _handleInput(context),
              const SizedBox(height: 6),
            ]),
          ),
          SizedBox(width: side, child: Padding(padding: const EdgeInsets.fromLTRB(0, 4, 8, 8), child: _sidePanel(context))),
        ]),
      ),
    ]);
  }

  Widget _status(BuildContext context) {
    final round = _int(v['round'], 1), rounds = _int(v['rounds'], 1);
    final solved = _ints(v['solved']);
    final done = _bools(v['done']);
    final left = done.where((d) => !d).length;
    String text;
    var hi = false;
    if (phase == 'over') {
      text = '游戏结束';
    } else if (phase == 'reveal') {
      text = '第 $round/$rounds 轮结束 · 下一轮即将开始';
    } else if (!seated) {
      text = '第 $round/$rounds 轮 · 观战中（$left 人还在猜）';
    } else if (myDone) {
      final n = me < solved.length ? solved[me] : 0;
      text = n > 0 ? '你第 $n 次猜中！等待其他人（$left 人还在猜）' : '本轮机会已用完 · 等待其他人（$left 人还在猜）';
    } else {
      hi = true;
      text = '第 $round/$rounds 轮 · 第 ${mine.length + 1}/$maxRows 次猜测${handle ? '（四字成语）' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(children: [
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(text, highlight: hi))),
        if (canPlay) ...[
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: _giveUp,
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: const Text('放弃本轮'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ]),
    );
  }

  // ---- my board -------------------------------------------------------------

  Widget _myBoard(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 5.0;
      final pyRatio = handle ? 0.42 : 0.0;
      final byW = (c.maxWidth - gap * (cols - 1)) / cols;
      final byH = (c.maxHeight - gap * (maxRows - 1)) / maxRows / (1 + pyRatio);
      final tile = [byW, byH, handle ? 76.0 : 62.0].reduce((a, b) => a < b ? a : b).clamp(6.0, 200.0);
      final rows = <Widget>[];
      for (var r = 0; r < maxRows; r++) {
        if (r > 0) rows.add(const SizedBox(height: gap));
        rows.add(Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < cols; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            handle ? _handleCell(context, r, i, tile) : _wordleTile(context, r, i, tile),
          ],
        ]));
      }
      return Center(child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: rows)));
    });
  }

  Widget _wordleTile(BuildContext context, int r, int i, double size) {
    final cs = Theme.of(context).colorScheme;
    String ch = '';
    Color? bg;
    Color border = cs.outline.withValues(alpha: 0.35);
    var fg = cs.onSurface;
    if (r < mine.length) {
      final w = '${mine[r]['w']}';
      ch = i < w.length ? w[i] : '';
      final m = r < myMarks.length && i < myMarks[r].length ? myMarks[r][i] : 'x';
      bg = pal.of(m, cs.surface);
      border = bg;
      fg = Colors.white;
    } else if (r == mine.length && canPlay) {
      ch = i < _typed.length ? _typed[i] : '';
      border = ch.isEmpty ? cs.primary.withValues(alpha: 0.45) : cs.onSurface.withValues(alpha: 0.75);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(size * 0.1),
        border: Border.all(color: border, width: 2),
        boxShadow: bg != null ? const [BoxShadow(blurRadius: 3, color: Colors.black26, offset: Offset(0, 1))] : null,
      ),
      child: ch.isEmpty
          ? null
          : Text(ch.toUpperCase(), style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w800, color: fg, height: 1.1)),
    );
  }

  Widget _handleCell(BuildContext context, int r, int i, double size) {
    final cs = Theme.of(context).colorScheme;
    final pyH = size * 0.42;
    String ch = '';
    List<String>? py;
    String m = '';
    if (r < mine.length) {
      final w = '${mine[r]['w']}';
      final runes = w.runes.toList();
      ch = i < runes.length ? String.fromCharCode(runes[i]) : '';
      final pys = _strss(mine[r]['py']);
      py = i < pys.length ? pys[i] : null;
      final mk = r < myMarks.length ? myMarks[r] : '';
      m = mk.length >= i * 4 + 4 ? mk.substring(i * 4, i * 4 + 4) : '';
    } else if (r == mine.length && canPlay) {
      final runes = _text.text.trim().runes.toList();
      ch = i < runes.length ? String.fromCharCode(runes[i]) : '';
      if (runes.length == 4) {
        final idiom = HandleDict.byWord[String.fromCharCodes(runes)];
        if (idiom != null) py = idiom.py[i];
      }
    }
    final charMark = m.isEmpty ? '' : m[0];
    final bg = charMark == 'g' || charMark == 'y' ? pal.of(charMark, cs.surface) : null;
    final current = r == mine.length && canPlay;
    Color layer(int k) {
      if (m.isEmpty) return cs.onSurface.withValues(alpha: 0.6);
      final c = m[k];
      if (c == 'g') return pal.green;
      if (c == 'y') return pal.yellow;
      return cs.onSurface.withValues(alpha: 0.3);
    }

    Widget pinyin() {
      if (py == null || py.length < 3) return SizedBox(height: pyH);
      final fs = pyH * 0.62;
      TextStyle st(int k) => TextStyle(fontSize: fs, fontWeight: m.isNotEmpty && m[k] != 'x' ? FontWeight.w900 : FontWeight.w600, color: layer(k), height: 1.1);
      return SizedBox(
        height: pyH,
        width: size,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(TextSpan(children: [
            if (py[0].isNotEmpty) TextSpan(text: py[0], style: st(1)),
            TextSpan(text: _fin(py[1]), style: st(2)),
            TextSpan(text: _toneMark(py[2]), style: st(3).copyWith(fontSize: fs * 1.15)),
          ])),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      pinyin(),
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ?? (m.isNotEmpty ? cs.surfaceContainerHighest : cs.surface.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(size * 0.12),
          border: Border.all(
              color: bg ?? (current ? cs.primary.withValues(alpha: ch.isEmpty ? 0.45 : 0.85) : cs.outline.withValues(alpha: 0.35)),
              width: 2),
          boxShadow: bg != null || m.isNotEmpty ? const [BoxShadow(blurRadius: 3, color: Colors.black26, offset: Offset(0, 1))] : null,
        ),
        child: ch.isEmpty
            ? null
            : Text(ch,
                style: TextStyle(
                    fontSize: size * 0.56,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: bg != null ? Colors.white : (charMark == 'x' ? cs.onSurface.withValues(alpha: 0.55) : cs.onSurface))),
      ),
    ]);
  }

  // ---- input widgets --------------------------------------------------------

  Map<String, String> _letterStates() {
    final best = <String, String>{};
    const rank = {'g': 3, 'y': 2, 'x': 1};
    for (var r = 0; r < mine.length && r < myMarks.length; r++) {
      final w = '${mine[r]['w']}';
      for (var i = 0; i < w.length && i < myMarks[r].length; i++) {
        final m = myMarks[r][i];
        if ((rank[m] ?? 0) > (rank[best[w[i]]] ?? 0)) best[w[i]] = m;
      }
    }
    return best;
  }

  Widget _keyboard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = _letterStates();
    const rows = ['qwertyuiop', 'asdfghjkl', '<zxcvbnm>'];
    return LayoutBuilder(builder: (context, c) {
      const gap = 4.0;
      final keyW = ((c.maxWidth - 16 - gap * 9) / 10).clamp(10.0, 46.0);
      final keyH = ((c.maxHeight - gap * 4) / 3).clamp(14.0, 54.0);
      Widget key(String k) {
        final special = k == '<' || k == '>';
        final id = k == '<' ? 'enter' : (k == '>' ? 'back' : k);
        final m = st[k] ?? '';
        final bg = special ? cs.secondaryContainer : pal.of(m, cs.surfaceContainerHighest);
        final fg = special ? cs.onSecondaryContainer : (m.isEmpty ? cs.onSurface : Colors.white);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: gap / 2),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: canPlay ? () => _key(id) : null,
              child: SizedBox(
                width: special ? keyW * 1.5 + gap / 2 : keyW,
                height: keyH,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: k == '>'
                        ? Icon(Icons.backspace_outlined, size: keyH * 0.45, color: fg)
                        : Text(k == '<' ? '提交' : k.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: keyH * 0.38, color: fg)),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Opacity(
        opacity: canPlay ? 1 : 0.55,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: gap / 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < row.length; i++) key(row[i])]),
              ),
            ),
        ]),
      );
    });
  }

  Widget _handleInput(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _knownHints(context),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              enabled: canPlay,
              maxLength: 8,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitHandle(),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: canPlay ? '输入四字成语' : (phase == 'play' ? '等待其他玩家…' : '本轮已结束'),
                isDense: true,
                counterText: '',
                filled: true,
                fillColor: cs.surface.withValues(alpha: 0.9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(onPressed: canPlay ? _submitHandle : null, child: const Text('提交')),
        ]),
      ]),
    );
  }

  /// Compact strip of the initials / finals I have learned so far (汉兜).
  Widget _knownHints(BuildContext context) {
    if (mine.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    const rank = {'g': 3, 'y': 2, 'x': 1};
    final ini = <String, String>{}, fin = <String, String>{};
    for (var r = 0; r < mine.length && r < myMarks.length; r++) {
      final pys = _strss(mine[r]['py']);
      final mk = myMarks[r];
      for (var i = 0; i < 4 && i < pys.length && mk.length >= i * 4 + 4; i++) {
        if (pys[i].length < 3) continue;
        void put(Map<String, String> into, String key, String m) {
          if (key.isEmpty || m == '-') return;
          if ((rank[m] ?? 0) > (rank[into[key]] ?? 0)) into[key] = m;
        }

        put(ini, pys[i][0], mk[i * 4 + 1]);
        put(fin, _fin(pys[i][1]), mk[i * 4 + 2]);
      }
    }
    Widget chip(String t, String m) => Container(
          margin: const EdgeInsets.only(right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: m == 'x' ? cs.onSurface.withValues(alpha: 0.12) : pal.of(m, cs.surface),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: m == 'x' ? cs.onSurface.withValues(alpha: 0.4) : Colors.white,
                  decoration: m == 'x' ? TextDecoration.lineThrough : null)),
        );
    List<MapEntry<String, String>> sorted(Map<String, String> m) =>
        m.entries.toList()..sort((a, b) => (rank[b.value] ?? 0) - (rank[a.value] ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 20,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          Center(child: Text('声母 ', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
          for (final e in sorted(ini)) Center(child: chip(e.key, e.value)),
          const SizedBox(width: 8),
          Center(child: Text('韵母 ', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
          for (final e in sorted(fin)) Center(child: chip(e.key, e.value)),
        ]),
      ),
    );
  }

  // ---- others ---------------------------------------------------------------

  List<int> get _order => seated ? [for (final s in g.seatsFromMe()) if (s != me) s] : g.seatsFromMe();

  Widget _strip(BuildContext context) {
    final order = _order;
    if (order.isEmpty) return _soloInfo(context);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final s in order)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
            child: FittedBox(fit: BoxFit.scaleDown, child: _playerCard(context, s, compact: true)),
          ),
      ],
    );
  }

  Widget _soloInfo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = _ints(v['score']);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(14)),
        child: Text('单人练习 · 总分 ${me >= 0 && me < score.length ? score[me] : 0}',
            style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
      ),
    );
  }

  Widget _sidePanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = _maps(v['history']);
    final score = _ints(v['score']);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: ListView(children: [
        Text('玩家', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in g.seatsFromMe()) _playerCard(context, s, compact: false),
        ]),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('往轮答案', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
          for (var i = 0; i < history.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${i + 1}. ${_answerText(_map(history[i]['info']))}  '
                '${[for (var s = 0; s < _ints(history[i]['pts']).length; s++) if (_ints(history[i]['pts'])[s] > 0) '${g.name(s)}+${_ints(history[i]['pts'])[s]}'].join(' ')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        if (seated && score.length > me && g.players == 1) ...[
          const SizedBox(height: 8),
          Text('总分 ${score[me]}', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
        ],
      ]),
    );
  }

  String _answerText(Map<String, dynamic>? info) {
    if (info == null) return '';
    final w = '${info['w']}';
    return handle ? w : w.toUpperCase();
  }

  /// Name + score + colour-only mini board of a player (words visible after the round).
  Widget _playerCard(BuildContext context, int s, {required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    final score = _ints(v['score']);
    final solved = _ints(v['solved']);
    final done = _bools(v['done']);
    final roundPts = _ints(v['roundPts']);
    final ms = s < marks.length ? marks[s] : const <String>[];
    final words = phase != 'play' ? _strss(v['words']) : const <List<String>>[];
    final ws = s < words.length ? words[s] : const <String>[];
    final cell = compact ? 8.0 : 15.0;
    final isMe = s == me;
    final active = phase == 'play' && s < done.length && !done[s];
    final n = s < solved.length ? solved[s] : 0;
    final badge = n > 0
        ? Icon(Icons.check_circle, size: compact ? 12 : 15, color: pal.green)
        : (s < done.length && done[s] ? Icon(Icons.cancel, size: compact ? 12 : 15, color: cs.error) : null);

    Widget mini() {
      final rows = <Widget>[];
      for (var r = 0; r < maxRows; r++) {
        final m = r < ms.length ? ms[r] : '';
        final w = r < ws.length ? ws[r] : '';
        final runes = w.runes.toList();
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 1.5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < cols; i++)
              Container(
                width: cell,
                height: cell,
                margin: const EdgeInsets.only(right: 1.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m.isEmpty
                      ? cs.onSurface.withValues(alpha: 0.08)
                      : (handle
                          ? (m.length >= i * 4 + 1 && m[i * 4] != 'x' ? pal.of(m[i * 4], cs.surface) : _handleMiniGrey(cs, m, i))
                          : pal.of(i < m.length ? m[i] : 'x', cs.surface)),
                  borderRadius: BorderRadius.circular(cell * 0.18),
                ),
                child: !compact && i < runes.length
                    ? Text(handle ? String.fromCharCode(runes[i]) : String.fromCharCode(runes[i]).toUpperCase(),
                        style: TextStyle(fontSize: cell * 0.62, height: 1.1, color: Colors.white, fontWeight: FontWeight.bold))
                    : null,
              ),
          ]),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    final scoreText = '${s < score.length ? score[s] : 0}分'
        '${phase != 'play' && s < roundPts.length && roundPts[s] > 0 ? ' (+${roundPts[s]})' : ''}';
    return Container(
      padding: EdgeInsets.all(compact ? 4 : 6),
      decoration: BoxDecoration(
        color: (isMe ? cs.primaryContainer : cs.surface).withValues(alpha: compact ? 0.85 : 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? cs.primary : cs.outline.withValues(alpha: 0.25), width: active ? 1.5 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(g.avatar(s), size: compact ? 16 : 20, bot: g.bot(s)),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 52 : 70),
              child: Text(isMe ? '我' : g.name(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(scoreText, style: TextStyle(fontSize: compact ? 10 : 11, color: cs.onSurface.withValues(alpha: 0.75))),
            if (badge != null) ...[const SizedBox(width: 2), badge],
          ]),
          if (compact) ...[const SizedBox(height: 2), mini()],
        ]),
        if (!compact) ...[const SizedBox(width: 6), mini()],
      ]),
    );
  }

  /// Mini cell colour for a 汉兜 char that's not in the answer: tint by the
  /// best pinyin layer so others can still see progress (but no characters).
  Color _handleMiniGrey(ColorScheme cs, String m, int i) {
    if (m.length < i * 4 + 4) return pal.grey;
    final layers = m.substring(i * 4 + 1, i * 4 + 4);
    if (layers.contains('g')) return Color.lerp(pal.grey, pal.green, 0.45)!;
    if (layers.contains('y')) return Color.lerp(pal.grey, pal.yellow, 0.45)!;
    return pal.grey;
  }

  Widget _spectate(BuildContext context) => SingleChildScrollView(
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final s in g.seatsFromMe()) _playerCard(context, s, compact: false),
        ]),
      );

  // ---- results --------------------------------------------------------------

  Widget _answerCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ans = _map(v['answer']);
    if (ans == null) return const SizedBox.shrink();
    final w = '${ans['w']}';
    final py = _strss(ans['py']);
    final runes = w.runes.toList();
    final solved = _ints(v['solved']);
    final mineN = seated && me < solved.length ? solved[me] : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('答案  ', style: TextStyle(fontSize: 13, color: cs.onTertiaryContainer)),
          for (var i = 0; i < runes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (handle && i < py.length && py[i].length >= 3)
                  Text('${py[i][0]}${_fin(py[i][1])}${_toneMark(py[i][2])}', style: TextStyle(fontSize: 10, color: cs.onTertiaryContainer)),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: pal.green, borderRadius: BorderRadius.circular(5)),
                  child: Text(handle ? String.fromCharCode(runes[i]) : String.fromCharCode(runes[i]).toUpperCase(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
                ),
              ]),
            ),
          if (seated) ...[
            const SizedBox(width: 10),
            Text(mineN > 0 ? '你用了 $mineN 次' : '你没猜中', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onTertiaryContainer)),
          ],
        ]),
      ),
    );
  }

  Widget? _banner() {
    final pl = v['placings'];
    if (phase != 'over' || pl is! List) return null;
    final p = _ints(pl);
    final score = _ints(v['score']);
    final order = [for (var s = 0; s < p.length; s++) s]..sort((a, b) => p[a] - p[b]);
    final win = [for (final s in order) if (p[s] == 1) g.name(s)];
    final title = g.players == 1 ? '练习结束 · 总分 ${score.isEmpty ? 0 : score[0]}' : '${win.join('、')} 获胜！';
    return ResultBanner(
      title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final s in order)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('#${p[s]} ', style: const TextStyle(fontWeight: FontWeight.bold)),
              g.tag(s, size: 26, sub: '${s < score.length ? score[s] : 0} 分', active: p[s] == 1),
            ]),
        ]),
      ),
    );
  }
}
