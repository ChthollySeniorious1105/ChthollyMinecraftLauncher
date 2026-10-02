import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';

/// System tray icon + "close to tray" so voice chat and global hotkeys keep working
/// with the window closed. Left click restores the window; right click shows a menu
/// with mute / deafen / quit.
class DesktopShell with TrayListener, WindowListener {
  final AppState app;
  DesktopShell(this.app);

  bool _quitting = false;
  bool _ready = false;
  String _lastMenuKey = '';

  Future<void> init() async {
    if (!Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      await trayManager.setIcon('assets/tray.ico');
      trayManager.addListener(this);
      _ready = true;
      app.addListener(_sync);
      await _sync();
    } catch (e) {
      app.logEvent('tray init failed: $e');
    }
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final mentions = app.histories.values.fold<int>(0, (a, h) => a + h.mentions);
    final unread = app.histories.values.fold<int>(0, (a, h) => a + h.unread);
    final voice = app.channels[app.voiceChannel]?.name;
    final tip = [
      'Pulse',
      if (app.authed) app.serverName,
      if (voice != null) '语音：$voice${app.selfMute ? '（已静音）' : ''}${app.selfDeaf ? '（已闭麦）' : ''}',
      if (mentions > 0) '$mentions 条 @提及' else if (unread > 0) '$unread 条未读',
    ].join('\n');
    final key = '$tip|${app.selfMute}|${app.selfDeaf}|${voice != null}';
    if (key == _lastMenuKey) return;
    _lastMenuKey = key;
    try {
      await trayManager.setToolTip(tip);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '打开 Pulse'),
        MenuItem.separator(),
        MenuItem.checkbox(key: 'mute', label: '静音麦克风', checked: app.selfMute),
        MenuItem.checkbox(key: 'deaf', label: '闭麦（不听不说）', checked: app.selfDeaf),
        if (voice != null) MenuItem(key: 'leave', label: '断开语音（$voice）'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出 Pulse'),
      ]));
    } catch (_) {}
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    _quitting = true;
    app.leaveVoice();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
    exit(0);
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (app.settings.closeToTray) {
      await windowManager.hide();
      if (!app.settings.trayHintShown) {
        app.settings.trayHintShown = true;
        app.settings.save();
        try {
          await trayManager.setToolTip('Pulse 仍在后台运行（语音和快捷键继续工作），右键托盘图标可退出');
        } catch (_) {}
      }
    } else {
      await quit();
    }
  }

  @override
  void onWindowFocus() => app.windowFocused = true;
  @override
  void onWindowBlur() => app.windowFocused = false;

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        show();
      case 'mute':
        app.toggleMute();
      case 'deaf':
        app.toggleDeafen();
      case 'leave':
        app.leaveVoice();
      case 'quit':
        quit();
    }
  }
}

/// Exposes the shell to widgets (e.g. a "quit" button in settings).
class ShellScope extends InheritedWidget {
  final DesktopShell shell;
  const ShellScope({super.key, required this.shell, required super.child});
  static DesktopShell? of(BuildContext c) => c.getInheritedWidgetOfExactType<ShellScope>()?.shell;
  @override
  bool updateShouldNotify(ShellScope old) => false;
}
