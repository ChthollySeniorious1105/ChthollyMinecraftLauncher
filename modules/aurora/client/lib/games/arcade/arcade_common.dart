import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';

/// Shared helpers for the arcade boards.

int aInt(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> aInts(Object? o) => o is List ? [for (final e in o) aInt(e)] : <int>[];
Map<String, dynamic>? aMap(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
List<Map<String, dynamic>> aMaps(Object? o) =>
    o is List ? [for (final e in o) if (e is Map) e.cast<String, dynamic>()] : <Map<String, dynamic>>[];
String aStr(Object? o) => o is String ? o : '';

String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Top status line, scaled down when narrow.
Widget aStatus(String text, {bool highlight = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(text, highlight: highlight)),
    );

/// Final ranking banner (rows of {'s', 'rank', ...}), scrollable if needed.
Widget aRanking(GameContext g, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) sub,
    {Alignment alignment = Alignment.center}) {
  final me = rows.where((r) => r['s'] == g.seat).firstOrNull;
  final title = me == null
      ? '游戏结束'
      : (me['rank'] == 1 ? '你赢了！' : '游戏结束 · 你是第 ${me['rank']} 名');
  return Align(
    alignment: alignment,
    child: SingleChildScrollView(
      child: ResultBanner(
        title,
        child: Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final r in rows)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(r['rank'] == 1 ? '🏆 ' : '#${r['rank']} ', style: const TextStyle(fontWeight: FontWeight.bold)),
              Flexible(child: g.tag(aInt(r['s']), size: 26, sub: sub(r), active: r['rank'] == 1)),
            ]),
        ]),
      ),
    ),
  );
}

/// Gives the board keyboard focus (desktop) and forwards key-down / repeat
/// events. Tapping anywhere inside re-grabs focus.
class ArcadeKeys extends StatefulWidget {
  final Widget child;
  final bool Function(LogicalKeyboardKey key, bool repeat) onKey;
  const ArcadeKeys({super.key, required this.child, required this.onKey});
  @override
  State<ArcadeKeys> createState() => _ArcadeKeysState();
}

class _ArcadeKeysState extends State<ArcadeKeys> {
  final _node = FocusNode(debugLabel: 'arcade');
  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          return widget.onKey(e.logicalKey, e is KeyRepeatEvent) ? KeyEventResult.handled : KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_node.hasFocus) _node.requestFocus();
          },
          child: widget.child,
        ),
      );
}

/// Round touch control button (fires on press-down for responsiveness).
class PadButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  const PadButton({super.key, this.icon, this.label, this.onTap, this.size = 48, this.color});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    final on = onTap != null;
    return GestureDetector(
      onTapDown: on ? (_) => onTap!() : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? c.withValues(alpha: 0.85) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          boxShadow: on ? const [BoxShadow(blurRadius: 4, color: Colors.black38, offset: Offset(0, 2))] : null,
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: size * 0.5, color: on ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.4))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(label ?? '',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: size * 0.28, color: on ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.4))),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Small colored pill label.
class AChip extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const AChip(this.text, this.color, {super.key, this.size = 11});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, maxLines: 1, style: TextStyle(fontSize: size, color: Colors.white, fontWeight: FontWeight.bold)),
      );
}

/// A compact opponent summary card: name tag + progress bar.
class ProgressTile extends StatelessWidget {
  final GameContext g;
  final int seat;
  final double pct; // 0..1
  final String sub;
  final bool out, done;
  final double width;
  const ProgressTile(this.g, this.seat, {super.key, required this.pct, required this.sub, this.out = false, this.done = false, this.width = 150});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: seat == g.seat ? cs.primary : cs.outline.withValues(alpha: 0.3), width: seat == g.seat ? 2 : 1),
      ),
      child: Opacity(
        opacity: out ? 0.5 : 1,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: g.tag(seat, size: 22))),
            if (out) const AChip('出局', Colors.redAccent, size: 10),
            if (done) const AChip('完成', Colors.green, size: 10),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: cs.onSurface.withValues(alpha: 0.12),
              color: out ? Colors.grey : (done ? Colors.green : cs.primary),
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }
}
