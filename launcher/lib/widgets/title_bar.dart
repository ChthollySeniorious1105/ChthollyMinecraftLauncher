import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../i18n/i18n.dart';

import '../theme.dart';

/// Custom window title bar (the native one is hidden) that follows the app theme.
class CmlTitleBar extends StatefulWidget {
  final Widget? leading;
  const CmlTitleBar({super.key, this.leading});
  @override
  State<CmlTitleBar> createState() => _CmlTitleBarState();
}

class _CmlTitleBarState extends State<CmlTitleBar> with WindowListener {
  bool maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => maximized = false);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cml = CmlColors.of(context);
    return SizedBox(
      height: 36,
      child: Row(children: [
        Expanded(
          child: DragToMoveArea(
            child: Container(
              color: Colors.transparent,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 14),
              child: widget.leading ??
                  Text('ChthollyMinecraftLauncher', style: t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
            ),
          ),
        ),
        _WinButton(icon: Icons.remove_rounded, onTap: windowManager.minimize, tooltip: trGlobal('最小化')),
        _WinButton(
          icon: maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
          iconSize: maximized ? 13 : 16,
          tooltip: maximized ? trGlobal('还原') : trGlobal('最大化'),
          onTap: () async => maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _WinButton(icon: Icons.close_rounded, onTap: windowManager.close, tooltip: trGlobal('关闭'), danger: true, hoverColor: cml.gradientA),
      ]),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool danger;
  final double iconSize;
  final Color? hoverColor;
  const _WinButton({required this.icon, required this.onTap, required this.tooltip, this.danger = false, this.iconSize = 16, this.hoverColor});
  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = hover ? (widget.danger ? const Color(0xFFE81123) : t.colorScheme.onSurface.withValues(alpha: 0.08)) : Colors.transparent;
    final fg = hover && widget.danger ? Colors.white : t.colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: 36,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
