import 'dart:async';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';

// ------------------------------------------------------------------ rules

/// Scrollable rules text: `# ` lines are headings, `- ` lines bullets.
class RulesView extends StatelessWidget {
  final String rules;
  const RulesView(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = rules.trim().split('\n');
    if (rules.trim().isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('该游戏暂无规则说明'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final l = lines[i].trimRight();
        final t = l.trimLeft();
        if (t.isEmpty) return const SizedBox(height: 6);
        if (t.startsWith('#')) {
          final level = RegExp(r'^#+').stringMatch(t)!.length;
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 4),
            child: Text(t.substring(level).trim(),
                style: TextStyle(fontSize: level <= 1 ? 18 : 15, fontWeight: FontWeight.bold, color: cs.primary)),
          );
        }
        if (t.startsWith('- ') || t.startsWith('* ')) {
          final indent = (l.length - t.length) * 6.0;
          return Padding(
            padding: EdgeInsets.only(left: 4 + indent, bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Container(width: 5, height: 5, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
              ),
              Expanded(child: Text(t.substring(2).trim(), style: const TextStyle(height: 1.45))),
            ]),
          );
        }
        return Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(t, style: const TextStyle(height: 1.45)));
      },
    );
  }
}

Future<void> showRulesDialog(BuildContext context, Map<String, dynamic>? gameInfo) {
  final name = '${gameInfo?['name'] ?? '游戏'}';
  final local = findGame('${gameInfo?['id']}');
  final rules = '${gameInfo?['rules'] ?? local?.rules ?? ''}';
  return showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) {
      final size = MediaQuery.of(c).size;
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.85),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(children: [
                const Icon(Icons.menu_book, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('$name · 规则', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(child: RulesView(rules)),
          ]),
        ),
      );
    },
  );
}

// ------------------------------------------------------------------ emotes

/// Grid of quick emotes / phrases; returns the chosen index.
Future<int?> pickEmote(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) {
      final emojis = [for (var i = 0; i < kEmotes.length; i++) if (kEmotes[i].runes.length <= 2) i];
      final phrases = [for (var i = 0; i < kEmotes.length; i++) if (kEmotes[i].runes.length > 2) i];
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
              for (final i in emojis)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(c, i),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(child: Text(kEmotes[i], style: const TextStyle(fontSize: 30, fontFamilyFallback: kFontFallback))),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final i in phrases) ActionChip(label: Text(kEmotes[i]), onPressed: () => Navigator.pop(c, i)),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Floating "name: 😂" bubbles at the top-center, fading after 2.5 s.
class EmoteOverlay extends StatefulWidget {
  final Stream<EmoteEvent> events;
  const EmoteOverlay({super.key, required this.events});
  @override
  State<EmoteOverlay> createState() => _EmoteOverlayState();
}

class _Bubble {
  final int id;
  final EmoteEvent e;
  bool fading = false;
  _Bubble(this.id, this.e);
}

class _EmoteOverlayState extends State<EmoteOverlay> {
  final List<_Bubble> _items = [];
  final List<Timer> _timers = [];
  StreamSubscription<EmoteEvent>? _sub;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.events.listen(_add);
  }

  @override
  void didUpdateWidget(covariant EmoteOverlay old) {
    super.didUpdateWidget(old);
    if (old.events != widget.events) {
      _sub?.cancel();
      _sub = widget.events.listen(_add);
    }
  }

  void _add(EmoteEvent e) {
    if (!mounted) return;
    final b = _Bubble(_n++, e);
    setState(() {
      _items.add(b);
      if (_items.length > 4) _items.removeAt(0);
    });
    _timers.add(Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => b.fading = true);
    }));
    _timers.add(Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _items.remove(b));
    }));
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final b in _items)
              AnimatedOpacity(
                key: ValueKey(b.id),
                duration: const Duration(milliseconds: 300),
                opacity: b.fading ? 0 : 1,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (context, s, child) => Transform.scale(scale: s, child: child),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.6)),
                      boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(b.e.avatar, size: 28),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${b.e.name}：', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
                            TextSpan(
                                text: b.e.text,
                                style: TextStyle(
                                    fontSize: b.e.text.runes.length <= 2 ? 24 : 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamilyFallback: kFontFallback),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ toolbar

/// What the in-game toolbar can do (network room or local session).
class GameActionsModel {
  final bool canPlay; // I have a seat in a running game
  final bool auto;
  final bool canResign;
  final bool canDraw;
  final bool canUndo;
  final bool requestPending;
  final VoidCallback onEmote;
  final ValueChanged<bool> onAuto;
  final VoidCallback onResign;
  final VoidCallback onDraw;
  final VoidCallback onUndo;
  final VoidCallback onRules;
  const GameActionsModel({
    required this.canPlay,
    required this.auto,
    required this.canResign,
    required this.canDraw,
    required this.canUndo,
    this.requestPending = false,
    required this.onEmote,
    required this.onAuto,
    required this.onResign,
    required this.onDraw,
    required this.onUndo,
    required this.onRules,
  });
}

Future<bool> confirmDialog(BuildContext context, String title, String body, String ok) async {
  final r = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// App-bar actions: 表情 button + 对局 menu (托管 / 认输 / 求和 / 悔棋 / 规则).
class GameActionsBar extends StatelessWidget {
  final GameActionsModel m;
  const GameActionsBar(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: '表情 / 快捷语',
        visualDensity: VisualDensity.compact,
        onPressed: m.onEmote,
        icon: const Icon(Icons.emoji_emotions_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: '对局操作',
        icon: Badge(
          isLabelVisible: m.auto,
          label: const Text('托'),
          backgroundColor: cs.tertiary,
          child: const Icon(Icons.more_vert),
        ),
        onSelected: (v) async {
          switch (v) {
            case 'auto':
              m.onAuto(!m.auto);
            case 'resign':
              if (await confirmDialog(context, '认输？', '确定要认输吗？本局将判负。', '认输')) m.onResign();
            case 'draw':
              m.onDraw();
            case 'undo':
              m.onUndo();
            case 'rules':
              m.onRules();
          }
        },
        itemBuilder: (_) => [
          if (m.canPlay)
            CheckedPopupMenuItem(value: 'auto', checked: m.auto, child: const Text('托管（电脑代打）')),
          if (m.canPlay && m.canResign)
            const PopupMenuItem(value: 'resign', child: ListTile(dense: true, leading: Icon(Icons.flag_outlined), title: Text('认输'))),
          if (m.canPlay && m.canDraw)
            PopupMenuItem(
                value: 'draw',
                enabled: !m.requestPending,
                child: const ListTile(dense: true, leading: Icon(Icons.handshake_outlined), title: Text('求和'))),
          if (m.canPlay && m.canUndo)
            PopupMenuItem(
                value: 'undo',
                enabled: !m.requestPending,
                child: const ListTile(dense: true, leading: Icon(Icons.undo), title: Text('悔棋'))),
          const PopupMenuItem(value: 'rules', child: ListTile(dense: true, leading: Icon(Icons.menu_book), title: Text('规则说明'))),
        ],
      ),
    ]);
  }
}

/// "托管中" indicator (tap to take back control).
class AutoPlayChip extends StatelessWidget {
  final VoidCallback onCancel;
  const AutoPlayChip({super.key, required this.onCancel});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(Icons.smart_toy, size: 16, color: cs.onTertiaryContainer),
      backgroundColor: cs.tertiaryContainer,
      label: Text('托管中 · 点击取消', style: TextStyle(color: cs.onTertiaryContainer)),
      onPressed: onCancel,
    );
  }
}

/// Pending 悔棋/求和 request: an answer card for players in `need`, a status
/// chip for everyone else.
class RequestOverlay extends StatelessWidget {
  final Map<String, dynamic> request;
  final int myId;
  final void Function(bool yes) onRespond;
  const RequestOverlay({super.key, required this.request, required this.myId, required this.onRespond});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = request['kind'] == 'undo' ? '悔棋' : '和棋';
    final need = asIntList(request['need']);
    final yes = asIntList(request['yes']);
    final from = asStr(request['fromName'], '对方');
    final mustAnswer = need.contains(myId) && !yes.contains(myId);
    if (!mustAnswer) {
      final mine = request['fromId'] == myId;
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Chip(
            avatar: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            label: Text(mine
                ? '已请求$kind，等待回应（${yes.length}/${need.length}）'
                : '$from 请求$kind（${yes.length}/${need.length} 同意）'),
          ),
        ),
      );
    }
    return Stack(children: [
      const Positioned.fill(child: ModalBarrier(color: Colors.black38, dismissible: false)),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(request['kind'] == 'undo' ? Icons.undo : Icons.handshake_outlined, size: 36, color: cs.primary),
                const SizedBox(height: 8),
                Text('$from 请求$kind', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('是否同意？30 秒内不回应视为拒绝', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton(onPressed: () => onRespond(false), child: const Text('拒绝')),
                  const SizedBox(width: 16),
                  FilledButton(onPressed: () => onRespond(true), child: const Text('同意')),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

String formatDuration(int ms) {
  final s = (ms / 1000).round();
  final m = s ~/ 60;
  return m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '$m:${(s % 60).toString().padLeft(2, '0')}';
}

String formatDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
