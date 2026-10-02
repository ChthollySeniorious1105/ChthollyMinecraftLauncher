import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';

/// Circular avatar: initial on a palette colour + optional presence dot and
/// a green "speaking" ring.
class Avatar extends StatelessWidget {
  final Member? member;
  final double size;
  final bool showPresence;
  final bool speaking;
  const Avatar(this.member, {super.key, this.size = 32, this.showPresence = false, this.speaking = false});

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final m = member;
    final name = m?.display ?? '?';
    final color = avatarColors[(m?.avatar ?? 0) % avatarColors.length];
    final initial = name.isEmpty ? '?' : String.fromCharCodes(name.runes.take(1)).toUpperCase();
    final app = AppScope.maybeOf(context);
    if (m != null && m.avatarHash.isNotEmpty && app != null) {
      // listen to the cache so the image appears as soon as it is downloaded
      return ListenableBuilder(
        listenable: app.avatars,
        builder: (context, _) => _build(context, t, m, color, initial, app.avatars.get(m.id, m.avatarHash)),
      );
    }
    return _build(context, t, m, color, initial, null);
  }

  Widget _build(BuildContext context, PulseTheme t, Member? m, Color color, String initial, Uint8List? bytes) {
    Widget a = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bytes == null ? color : t.sidebar,
        shape: BoxShape.circle,
        border: speaking ? Border.all(color: t.online, width: 2.5) : null,
        boxShadow: speaking ? [BoxShadow(color: t.online.withValues(alpha: 0.5), blurRadius: 6)] : null,
        image: bytes == null
            ? null
            : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover, filterQuality: FilterQuality.medium),
      ),
      child: bytes == null ? Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42)) : null,
    );
    if (showPresence && m != null) {
      a = Stack(clipBehavior: Clip.none, children: [
        a,
        Positioned(right: -2, bottom: -2, child: PresenceDot(m.presence, size: size * 0.38, border: t.sidebar)),
      ]);
    }
    return a;
  }
}

class PresenceDot extends StatelessWidget {
  final String status;
  final double size;
  final Color border;
  const PresenceDot(this.status, {super.key, this.size = 10, required this.border});

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final c = switch (status) { 'online' => t.online, 'idle' => t.idle, 'dnd' => t.dnd, _ => t.muted };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: status == 'offline' || status == 'invisible' ? border : c,
        shape: BoxShape.circle,
        border: Border.all(color: status == 'offline' || status == 'invisible' ? t.muted : border, width: size * 0.22),
      ),
    );
  }
}

String statusLabel(String s) => switch (s) {
      'online' => '在线',
      'idle' => '离开',
      'dnd' => '请勿打扰',
      'invisible' => '隐身',
      _ => '离线',
    };

/// Name colour: custom member colour or role colour.
Color nameColor(BuildContext context, Member? m) {
  final t = PulseColors.of(context);
  if (m == null) return t.text;
  if (m.color != 0) return Color(m.color);
  final r = AppScope.maybeOf(context)?.colorRole(m);
  if (r != null) return Color(r.color);
  if (m.role == Role.owner) return const Color(0xFFF0B232);
  if (m.role == Role.admin) return t.accent;
  return t.text;
}

/// Small hover-highlight list row used for channels and members.
class HoverTile extends StatefulWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final void Function(Offset)? onSecondaryTapAt;
  final EdgeInsets padding;
  const HoverTile({super.key, required this.child, this.selected = false, this.onTap, this.onSecondaryTap, this.onSecondaryTapAt,
      this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6)});

  @override
  State<HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<HoverTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) {
          widget.onSecondaryTap?.call();
          widget.onSecondaryTapAt?.call(d.globalPosition);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected ? t.hover : (_hover ? t.hover.withValues(alpha: 0.55) : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Icon button with tooltip that turns red when [active] (mute / deafen buttons).
class BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  const BarButton(this.icon, this.tooltip, this.onTap, {super.key, this.active = false, this.color});

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: color ?? (active ? t.danger : t.muted)),
        ),
      ),
    );
  }
}

Future<void> showContextMenu(BuildContext context, Offset at, List<PopupMenuEntry<VoidCallback>> items) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final r = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: items,
  );
  r?.call();
}

PopupMenuItem<VoidCallback> menuItem(String label, VoidCallback onTap, {IconData? icon, bool danger = false}) => PopupMenuItem<VoidCallback>(
      value: onTap,
      height: 36,
      child: Builder(builder: (context) {
        final t = PulseColors.of(context);
        final c = danger ? t.danger : t.text;
        return Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 10)],
          Text(label, style: TextStyle(color: c, fontSize: 13)),
        ]);
      }),
    );

Future<bool> confirm(BuildContext context, String title, String body, {String ok = '确定', bool danger = false}) async {
  final r = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) {
      final t = PulseColors.of(c);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: t.danger, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok),
          ),
        ],
      );
    },
  );
  return r == true;
}

Future<String?> prompt(BuildContext context, String title, {String initial = '', String hint = '', int maxLength = 100, bool multiline = false}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(useRootNavigator: false, 
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: maxLength,
          maxLines: multiline ? 4 : 1,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: multiline ? null : (v) => Navigator.pop(c, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('确定')),
      ],
    ),
  );
}

/// Section label in sidebars ("文字频道" etc).
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 4),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(color: t.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ),
        ?trailing,
      ]),
    );
  }
}

String formatTime(int ms, {bool seconds = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}${seconds ? ':${two(d.second)}' : ''}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '今天 $hm';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return '昨天 $hm';
  return '${d.year}/${two(d.month)}/${two(d.day)} $hm';
}

/// Level meter bar (0..1) with optional threshold marker.
class LevelMeter extends StatelessWidget {
  final double level;
  final double? threshold;
  final bool active;
  const LevelMeter(this.level, {super.key, this.threshold, this.active = true});

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    // dBFS-ish visual scale: -60 dB .. 0 dB
    double vis(double v) => v <= 1e-6 ? 0 : ((20 * math.log(v) / math.ln10 + 60) / 60).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return Container(
        height: 8,
        decoration: BoxDecoration(color: t.input, borderRadius: BorderRadius.circular(4)),
        child: Stack(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: w * vis(level),
            decoration: BoxDecoration(color: active ? t.online : t.muted, borderRadius: BorderRadius.circular(4)),
          ),
          if (threshold != null) Positioned(left: (w * threshold!).clamp(0, w - 2), top: 0, bottom: 0, child: Container(width: 2, color: t.idle)),
        ]),
      );
    });
  }
}

/// Convenience accessor.
AppState appOf(BuildContext context) => AppScope.of(context);
