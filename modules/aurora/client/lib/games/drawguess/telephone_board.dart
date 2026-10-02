import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'canvas.dart';
import 'toolbar.dart';
import 'widgets.dart';

/// 传话画画 board: write / draw / describe screens, waiting list, page-by-page
/// reveal of every book and a final gallery.
class TelephoneBoard extends StatefulWidget {
  final GameContext g;
  const TelephoneBoard(this.g, {super.key});
  @override
  State<TelephoneBoard> createState() => _TelephoneBoardState();
}

/// Read-only stroke parsing, memoised per raw view list (so rebuilds from the
/// countdown don't rebake the bitmaps). Kept apart from [DgStroke.parse],
/// whose cache belongs to the live drawing.
final _parsed = Expando<List<DgStroke>>();
List<DgStroke> _strokesOf(Object? raw) {
  if (raw is! List) return const [];
  return _parsed[raw] ??= [
    for (final e in raw)
      if (e is Map)
        DgStroke(
          dgInt(e['id'], 0),
          dgInt(e['c'], 0xFF000000),
          dgInt(e['w'], 6),
          e['p'] is List ? [for (final v in e['p'] as List) dgInt(v, 0)] : <int>[],
        ),
  ];
}

void _noSend(Map<String, dynamic> _) {}

class _TelephoneBoardState extends State<TelephoneBoard> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _tick;
  Timer? _draft;
  final _tool = DgTool();
  int _skew = 0;
  String _taskKey = '';
  int _shownKey = -1;
  int _galleryBook = 0;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  String get phase => v['phase'] as String? ?? '';
  Map<String, dynamic>? get task => (v['task'] as Map?)?.cast<String, dynamic>();
  bool get _working => phase == 'write' || phase == 'draw' || phase == 'describe';
  int get revealer => dgInt(v['revealer'], 0);
  int get maxText => dgInt(v['maxText'], 40);

  @override
  void initState() {
    super.initState();
    _tool.addListener(_toolChanged);
    _sync();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && dgInt(v['endsAt'], 0) > 0) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TelephoneBoard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final now = dgInt(v['now'], 0);
    if (now > 0) _skew = now - DateTime.now().millisecondsSinceEpoch;
    final key = '${v['round']}-$phase';
    if (key != _taskKey) {
      _taskKey = key;
      _draft?.cancel();
      _text.text = task?['text'] as String? ?? '';
      _tool.resetMode();
    }
    final r = (v['reveal'] as Map?) ?? const {};
    final shown = dgInt(r['book'], 0) * 100 + dgInt(r['shown'], 0);
    if (phase == 'reveal' && shown != _shownKey) {
      _shownKey = shown;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        }
      });
    }
  }

  void _toolChanged() => setState(() {});

  @override
  void dispose() {
    _tick?.cancel();
    _draft?.cancel();
    _text.dispose();
    _scroll.dispose();
    _tool.dispose();
    super.dispose();
  }

  int get _remain {
    final end = dgInt(v['endsAt'], 0);
    if (end <= 0) return -1;
    final ms = end - (DateTime.now().millisecondsSinceEpoch + _skew);
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _onTyping(String _) {
    _draft?.cancel();
    _draft = Timer(const Duration(milliseconds: 800), () {
      if (mounted && task?['done'] == false) g.act({'type': 'draft', 'text': _text.text});
    });
  }

  void _submit() {
    _draft?.cancel();
    if (phase == 'draw') {
      g.act({'type': 'done'});
    } else {
      g.act({'type': 'done', 'text': _text.text.trim()});
    }
  }

  // ------------------------------------------------------------ header

  String get _phaseName => switch (phase) {
        'write' => '写题目',
        'draw' => '作画',
        'describe' => '描述',
        'reveal' => '揭晓',
        'over' => '画廊',
        _ => '准备中',
      };

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final round = dgInt(v['round'], 0), total = dgInt(v['totalRounds'], 0);
    final remain = _remain;
    final t = task;
    String main;
    var hl = false;
    if (_working) {
      final done = (v['done'] as List? ?? const []).where((e) => e == true).length;
      if (t == null) {
        main = '$_phaseName中… 已完成 $done/${g.players}';
      } else if (t['done'] == true) {
        main = '已完成，等待其他人（$done/${g.players}）';
      } else {
        main = switch (phase) {
          'write' => '写一句话，让下一位来画',
          'draw' => '画出你收到的句子',
          _ => '这幅画画的是什么？',
        };
        hl = true;
      }
    } else if (phase == 'reveal') {
      final r = (v['reveal'] as Map?) ?? const {};
      main = '第 ${dgInt(r['book'], 0) + 1}/${dgInt(r['bookCount'], 0)} 本：${g.name(dgInt(r['owner'], 0))} 的本子';
    } else if (phase == 'over') {
      main = '游戏结束，看看大家的本子吧';
    } else {
      main = '准备中…';
    }
    final timeColor = remain >= 0 && remain <= 10 ? Colors.redAccent : cs.primary;
    final pill = BoxDecoration(color: cs.surface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(16));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pill,
          child: Text(_working ? '$round/$total · $_phaseName' : _phaseName, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 6),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(main, highlight: hl))),
        const SizedBox(width: 6),
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: pill,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.timer_outlined, size: 15, color: timeColor),
            const SizedBox(width: 2),
            Text(remain < 0 ? '--' : '$remain', style: TextStyle(fontWeight: FontWeight.bold, color: timeColor)),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ pieces

  Widget _card(BuildContext context, Widget child, {double maxWidth = 520}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.2),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      child: child,
    );
  }

  Widget _promptBox(BuildContext context, String label, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
        Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
      ]),
    );
  }

  Widget _textInput(String hint) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _text,
          maxLength: maxText,
          textInputAction: TextInputAction.done,
          onChanged: _onTyping,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(isDense: true, hintText: hint, border: const OutlineInputBorder(), counterText: ''),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check, size: 18), label: const Text('完成')),
    ]);
  }

  /// Read-only 4:3 drawing.
  Widget _drawing(Object? raw, {Widget? overlay}) =>
      DgCanvas(strokes: _strokesOf(raw), enabled: false, color: 0, width: 1, send: _noSend, overlay: overlay);

  Widget _progress(BuildContext context, {String? title}) {
    final cs = Theme.of(context).colorScheme;
    final done = (v['done'] as List? ?? const []).map((e) => e == true).toList();
    final n = done.where((d) => d).length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: _card(
          context,
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title ?? '等待其他人完成…', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('已完成 $n/${g.players}', style: TextStyle(color: cs.outline)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (var s = 0; s < g.players; s++)
                g.tag(
                  s,
                  size: 28,
                  active: s < done.length && !done[s],
                  sub: s < done.length && done[s] ? '已完成' : '进行中…',
                  trailing: Icon(
                    s < done.length && done[s] ? Icons.check_circle : Icons.edit_note,
                    size: 18,
                    color: s < done.length && done[s] ? Colors.green.shade600 : cs.outline,
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ work screens

  Widget _writeScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: _card(
          context,
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.menu_book, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(child: Text('写下一句有趣的话', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 6),
            Text('它会传给下一位玩家来画。留空将随机给出一个词语。', style: TextStyle(color: cs.outline, fontSize: 13)),
            const SizedBox(height: 12),
            _textInput('例如：一只企鹅在沙漠里卖冰淇淋'),
          ]),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
      child: DgToolbar(
        tool: _tool,
        send: g.act,
        points: dgInt(task?['points'], 0),
        maxPoints: dgInt(v['maxPoints'], 20000),
        canUndo: task?['canUndo'] != false,
        canRedo: task?['canRedo'] != false,
      ),
    );
  }
  Widget _drawScreen(BuildContext context) {
    final t = task!;
    final prev = (t['prev'] as Map?) ?? const {};
    final canvas = DgCanvas(
      strokes: DgStroke.parse(t['strokes']),
      enabled: true,
      color: _tool.canvasColor,
      width: _tool.canvasWidth,
      fill: _tool.fill,
      send: g.act,
      overlay: (t['strokes'] as List? ?? const []).isEmpty
          ? IgnorePointer(
              child: Center(child: Text('在这里作画', style: TextStyle(color: Colors.black.withValues(alpha: 0.25), fontSize: 18))),
            )
          : null,
    );
    final prompt = _promptBox(context, '请画出：', '${prev['t'] ?? ''}');
    final done = FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check, size: 18), label: const Text('完成'));
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 600;
      if (wide) {
        final side = c.maxWidth >= 1100 ? 320.0 : 250.0;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: canvas)),
          SizedBox(
            width: side,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                prompt,
                const SizedBox(height: 8),
                _toolbar(context),
                const SizedBox(height: 8),
                done,
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: prompt),
        Expanded(child: Padding(padding: const EdgeInsets.all(6), child: canvas)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _toolbar(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: SizedBox(width: double.infinity, child: done),
        ),
      ]);
    });
  }

  Widget _describeScreen(BuildContext context) {
    final t = task!;
    final prev = (t['prev'] as Map?) ?? const {};
    final pic = _drawing(prev['strokes']);
    final input = _card(
      context,
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('这幅画画的是什么？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _textInput('用一句话描述它'),
      ]),
    );
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 600;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: pic)),
          SizedBox(
            width: c.maxWidth >= 1100 ? 360 : 280,
            child: Center(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 6, 8, 6), child: input)),
          ),
        ]);
      }
      return Column(children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(6), child: pic)),
        Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: input),
      ]);
    });
  }

  // ------------------------------------------------------------ books

  Widget _page(BuildContext context, Map page, int book, int idx, double maxW, double maxH) {
    final cs = Theme.of(context).colorScheme;
    final s = dgInt(page['s'], 0);
    final likes = dgInts(page['likes']);
    final liked = likes.contains(g.seat);
    final canLike = g.seat >= 0 && g.seat != s;
    final isDraw = page['k'] == 'draw';
    final label = idx == 0 ? '题目' : (isDraw ? '画了' : '描述');
    // a drawing (4:3) must fit in ~75% of the list height
    final drawMax = (maxH * 0.75 * 4 / 3 + 16).clamp(120.0, 380.0);
    final bubbleW = (maxW - 16).clamp(120.0, isDraw ? drawMax : 460.0);
    final Widget body = isDraw
        ? SizedBox(width: bubbleW - 16, height: (bubbleW - 16) * 3 / 4, child: _drawing(page['strokes']))
        : Text('${page['t'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: g.tag(s, size: 24, sub: label)),
          const Spacer(),
          if (canLike || likes.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: canLike ? () => g.act({'type': 'like', 'book': book, 'page': idx}) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(liked ? Icons.favorite : Icons.favorite_border, size: 18, color: liked || likes.isNotEmpty ? Colors.pink : cs.outline),
                  if (likes.isNotEmpty) ...[const SizedBox(width: 2), Text('${likes.length}', style: const TextStyle(fontSize: 12))],
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Container(
          constraints: BoxConstraints(maxWidth: bubbleW),
          margin: const EdgeInsets.only(left: 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDraw ? cs.surface.withValues(alpha: 0.9) : cs.primaryContainer.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
              topLeft: Radius.circular(4),
            ),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
          ),
          child: body,
        ),
      ]),
    );
  }

  Widget _bookList(BuildContext context, List pages, int book, {ScrollController? controller}) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.clamp(0.0, 560.0);
      return ListView.builder(
        controller: controller,
        padding: EdgeInsets.symmetric(horizontal: ((c.maxWidth - w) / 2).clamp(0.0, double.infinity) + 8, vertical: 6),
        itemCount: pages.length,
        itemBuilder: (context, i) => _page(context, (pages[i] as Map?) ?? const {}, book, i, w - 16, c.maxHeight),
      );
    });
  }

  Widget _revealScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = (v['reveal'] as Map?) ?? const {};
    final pages = r['pages'] as List? ?? const [];
    final book = dgInt(r['book'], 0);
    final shown = dgInt(r['shown'], 0), count = dgInt(r['pageCount'], 0);
    final books = dgInt(r['bookCount'], 0);
    final iHost = g.seat == revealer;
    final label = shown < count ? '下一页' : (book + 1 < books ? '下一本' : '结束展示');
    return Column(children: [
      Expanded(child: _bookList(context, pages, book, controller: _scroll)),
      Container(
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Text(
              '第 $shown/$count 页${iHost ? '' : ' · 等待 ${g.name(revealer)} 翻页'}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
            ),
          ),
          if (iHost)
            FilledButton.icon(
              onPressed: () => g.act({'type': 'next'}),
              icon: Icon(shown < count ? Icons.arrow_downward : Icons.menu_book, size: 18),
              label: Text(label),
            ),
        ]),
      ),
    ]);
  }

  Widget _galleryScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gal = (v['gallery'] as List? ?? const []).whereType<Map>().toList();
    if (gal.isEmpty) return Center(child: Text('没有本子', style: TextStyle(color: cs.outline)));
    final sel = _galleryBook.clamp(0, gal.length - 1);
    final best = (v['final'] as List? ?? const []).whereType<Map>().toList();
    final bestText = best.isEmpty
        ? null
        : '最受欢迎：${{for (final b in best) g.name(dgInt(b['s'], 0))}.join('、')}（${best.first['likes']} 赞）';
    return Column(children: [
      if (bestText != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(bestText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback)),
        ),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: gal.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            visualDensity: VisualDensity.compact,
            selected: i == sel,
            label: Text('${g.name(dgInt(gal[i]['owner'], i))} 的本子'),
            onSelected: (_) => setState(() => _galleryBook = i),
          ),
        ),
      ),
      Expanded(
        child: _bookList(context, gal[sel]['pages'] as List? ?? const [], dgInt(gal[sel]['owner'], sel),
            controller: null),
      ),
    ]);
  }

  // ------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final t = task;
    Widget body;
    if (_working) {
      if (t == null) {
        body = _progress(context, title: '观战中：大家正在$_phaseName');
      } else if (t['done'] == true) {
        body = _progress(context);
      } else {
        body = switch (phase) {
          'write' => _writeScreen(context),
          'draw' => _drawScreen(context),
          _ => _describeScreen(context),
        };
      }
    } else if (phase == 'reveal') {
      body = _revealScreen(context);
    } else if (phase == 'over') {
      body = _galleryScreen(context);
    } else {
      body = const Center(child: Text('准备中…'));
    }
    return Column(children: [
      _header(context),
      Expanded(child: body),
    ]);
  }
}
