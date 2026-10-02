import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'canvas.dart';
import 'toolbar.dart';
import 'widgets.dart';

class DrawGuessBoard extends StatefulWidget {
  final GameContext g;
  const DrawGuessBoard(this.g, {super.key});
  @override
  State<DrawGuessBoard> createState() => _DrawGuessBoardState();
}

class _DrawGuessBoardState extends State<DrawGuessBoard> {
  final _guess = TextEditingController();
  final _gmWord = TextEditingController();
  final _gmHint = TextEditingController();
  Timer? _tick;
  final _tool = DgTool();
  int _skew = 0; // serverNow - localNow

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

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
  void didUpdateWidget(DrawGuessBoard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final now = dgInt(v['now'], 0);
    if (now > 0) _skew = now - DateTime.now().millisecondsSinceEpoch;
  }

  void _toolChanged() => setState(() {});

  @override
  void dispose() {
    _tick?.cancel();
    _guess.dispose();
    _gmWord.dispose();
    _gmHint.dispose();
    _tool.dispose();
    super.dispose();
  }

  int get _remain {
    final end = dgInt(v['endsAt'], 0);
    if (end <= 0) return -1;
    final ms = end - (DateTime.now().millisecondsSinceEpoch + _skew);
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  String get phase => v['phase'] as String? ?? '';
  String get role => v['myRole'] as String? ?? 'spectator';
  int get drawer => dgInt(v['drawer']);
  int get gm => dgInt(v['gm']);
  bool get _iDraw => role == 'drawer' && phase == 'draw';
  bool get _iGuessed {
    final gs = v['guessed'] as List? ?? const [];
    return g.seat >= 0 && g.seat < gs.length && gs[g.seat] == true;
  }

  bool get _canGuess => phase == 'draw' && role == 'guesser' && !_iGuessed;

  void _sendGuess() {
    final t = _guess.text.trim();
    if (t.isEmpty) return;
    g.act({'type': 'guess', 'text': t});
    _guess.clear();
  }

  // ------------------------------------------------------------ top line

  Widget _topLine(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final round = dgInt(v['round'], 0), total = dgInt(v['totalRounds'], 0);
    final word = v['word'] as String?;
    final remain = _remain;
    String main;
    var hl = false;
    switch (phase) {
      case 'gmword':
        main = role == 'gm' ? '请为 ${g.name(drawer)} 出题' : '等待出题人 ${g.name(gm)} 出题…';
        hl = role == 'gm';
      case 'choose':
        main = role == 'drawer' ? '请选择要画的词' : '${g.name(drawer)} 正在选词…';
        hl = role == 'drawer';
      case 'draw':
        if (word != null) {
          main = '${role == 'drawer' ? '请画' : '答案'}：$word${(v['wordCat'] as String? ?? '').isNotEmpty ? '（${v['wordCat']}）' : ''}';
          hl = role == 'drawer';
        } else {
          main = dgHintText((v['hint'] as Map?)?.cast<String, dynamic>());
          if (_iGuessed) main = '你猜对了！  $main';
        }
      case 'reveal':
        main = '答案：${(v['roundResult'] as Map?)?['word'] ?? ''}';
      case 'over':
        main = '游戏结束';
      default:
        main = '';
    }
    final timeColor = remain >= 0 && remain <= 10 ? Colors.redAccent : cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(16)),
          child: Text('$round/$total', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 6),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(main, highlight: hl))),
        const SizedBox(width: 6),
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.timer_outlined, size: 15, color: timeColor),
            const SizedBox(width: 2),
            Text(remain < 0 ? '--' : '$remain', style: TextStyle(fontWeight: FontWeight.bold, color: timeColor)),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ canvas overlays

  Widget? _overlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (phase) {
      case 'choose':
        final choices = (v['choices'] as List?)?.cast<String>();
        return DgCard(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(choices != null ? '选一个词来画' : '${g.name(drawer)} 正在选词…',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (choices != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                for (final c in choices) FilledButton(onPressed: () => g.act({'type': 'choose', 'word': c}), child: Text(c)),
              ]),
            ],
          ]),
        );
      case 'gmword':
        if (role != 'gm') {
          return DgCard(child: Text('等待出题人 ${g.name(gm)} 为 ${g.name(drawer)} 出题…', textAlign: TextAlign.center));
        }
        return DgCard(child: _gmPanel(context));
      case 'reveal':
        return DgCard(child: _roundResult(context));
      case 'over':
        return DgCard(child: _finalRanking(context));
      case 'draw':
        if ((v['strokes'] as List? ?? const []).isEmpty) {
          return IgnorePointer(
            child: Center(
              child: Text(_iDraw ? '在这里作画' : '${g.name(drawer)} 正在作画…',
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.25), fontSize: 18)),
            ),
          );
        }
        return null;
      default:
        return Center(child: Text('准备中…', style: TextStyle(color: cs.outline)));
    }
  }

  Widget _gmPanel(BuildContext context) {
    void submit() {
      final w = _gmWord.text.trim();
      if (w.isEmpty) return;
      g.act({'type': 'gmword', 'word': w, 'hint': _gmHint.text.trim()});
      _gmWord.clear();
      _gmHint.clear();
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        DgBadge('GM', Colors.amber.shade800),
        const SizedBox(width: 6),
        Expanded(child: Text('为 ${g.name(drawer)} 出题', style: const TextStyle(fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _gmWord,
        maxLength: 12,
        decoration: const InputDecoration(isDense: true, labelText: '词语（最多 12 字）', counterText: ''),
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _gmHint,
        maxLength: 8,
        decoration: const InputDecoration(isDense: true, labelText: '类别提示（可选）', counterText: ''),
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: submit, icon: const Icon(Icons.send, size: 18), label: const Text('出题')),
    ]);
  }

  Widget _roundResult(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = (v['roundResult'] as Map?) ?? const {};
    final gains = <int, int>{
      for (final e in (r['gains'] as List? ?? const []))
        if (e is List && e.length == 2) dgInt(e[0]): dgInt(e[1], 0),
    };
    final correct = dgInts(r['correct']);
    final reason = switch (r['reason']) { 'all' => '全部猜对！', 'gm' => '出题人结束了本轮', _ => '时间到！' };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(reason, style: TextStyle(color: cs.outline)),
      const SizedBox(height: 4),
      Text('${r['word'] ?? ''}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
      if ((r['cat'] as String? ?? '').isNotEmpty) Text('（${r['cat']}）', style: TextStyle(color: cs.outline)),
      const SizedBox(height: 8),
      Text(correct.isEmpty ? '没有人猜对' : '${correct.length} 人猜对'),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final e in gains.entries)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('${g.name(e.key)}${e.key == dgInt(r['drawer']) ? '（画手）' : ''} +${e.value}'),
          ),
      ]),
    ]);
  }

  Widget _finalRanking(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fin = (v['final'] as List? ?? const []).whereType<Map>().toList();
    const medals = ['🥇', '🥈', '🥉'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('最终排名', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
      const SizedBox(height: 8),
      for (final r in fin)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text(dgInt(r['rank']) <= 3 ? medals[dgInt(r['rank']) - 1] : '${r['rank']}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontFamilyFallback: kFontFallback)),
            ),
            Expanded(child: Text(g.name(dgInt(r['s'])), overflow: TextOverflow.ellipsis)),
            Text('${r['score']} 分', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
    ]);
  }

  // ------------------------------------------------------------ bottom controls

  Widget _toolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
      child: DgToolbar(
        tool: _tool,
        send: g.act,
        points: dgInt(v['points'], 0),
        maxPoints: dgInt(v['maxPoints'], 20000),
        canUndo: v['canUndo'] != false,
        canRedo: v['canRedo'] != false,
      ),
    );
  }
  Widget _inputRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (role == 'gm' && phase == 'draw') {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          DgBadge('GM', Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(child: Text('你是出题人，可查看所有猜测', style: TextStyle(color: cs.outline, fontSize: 13), overflow: TextOverflow.ellipsis)),
          OutlinedButton(onPressed: () => g.act({'type': 'gmskip'}), child: const Text('结束本轮')),
        ]),
      );
    }
    if (!_canGuess) {
      final msg = switch (role) {
        _ when phase != 'draw' => '',
        'drawer' => '你是画手，不能猜词',
        'spectator' => '观战中',
        _ => _iGuessed ? '你已猜对，等待其他人…' : '',
      };
      if (msg.isEmpty) return const SizedBox(height: 4);
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(msg, style: TextStyle(color: cs.outline, fontSize: 13)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _guess,
            maxLength: 20,
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(isDense: true, hintText: '输入你的答案', counterText: '', border: OutlineInputBorder()),
            onSubmitted: (_) => _sendGuess(),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: _sendGuess, child: const Text('猜')),
      ]),
    );
  }

  // ------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canvas = DgCanvas(
      strokes: DgStroke.parse(v['strokes']),
      enabled: _iDraw,
      color: _tool.canvasColor,
      width: _tool.canvasWidth,
      fill: _tool.fill,
      send: g.act,
      overlay: _overlay(context),
    );
    final feedBox = Container(
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10)),
      child: DgFeed(g),
    );
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 700 && c.maxWidth > c.maxHeight;
      if (wide) {
        final side = c.maxWidth >= 1100 ? 320.0 : 260.0;
        return Column(children: [
          _topLine(context),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Column(children: [
                  Expanded(child: Padding(padding: const EdgeInsets.all(6), child: canvas)),
                  if (_iDraw) _toolbar(context),
                ]),
              ),
              SizedBox(
                width: side,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 6, 0),
                  child: Column(children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: c.maxHeight * 0.4),
                      child: SingleChildScrollView(child: DgPlayers(g)),
                    ),
                    const SizedBox(height: 6),
                    Expanded(child: feedBox),
                    _inputRow(context),
                  ]),
                ),
              ),
            ]),
          ),
        ]);
      }
      // portrait / narrow: canvas on top, feed below
      final canvasH = (c.maxWidth - 12) * 3 / 4;
      final maxCanvasH = c.maxHeight * 0.5;
      return Column(children: [
        _topLine(context),
        DgPlayers(g, compact: true),
        SizedBox(
          height: canvasH < maxCanvasH ? canvasH + 8 : maxCanvasH,
          child: Padding(padding: const EdgeInsets.all(4), child: canvas),
        ),
        if (_iDraw) _toolbar(context),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: feedBox)),
        _inputRow(context),
      ]);
    });
  }
}
