import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native/native.dart';
import 'net/connection.dart';
import 'platform/shell.dart';
import 'screens/connect_screen.dart';
import 'screens/main_screen.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'theme/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final native = Native.load();
  final settings = await Settings.load(native);
  final app = AppState(native, settings);
  final shell = DesktopShell(app);
  await shell.init();
  runApp(ShellScope(shell: shell, child: PulseApp(app)));
  await app.start();
}

/// Makes AppState available to the whole tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}

class PulseApp extends StatefulWidget {
  final AppState app;
  const PulseApp(this.app, {super.key});
  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _toastSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_rebuild);
    _toastSub = widget.app.toasts.listen((t) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3), width: 420));
    });
  }

  void _rebuild() => setState(() {});

  // ThemeData has no value equality for our PulseColors extension, so building a new one on
  // every AppState notification made MaterialApp start a 200 ms theme cross-fade (and rebuild
  // the whole tree every frame) each time anything changed. Rebuild it only when it changes.
  String _themeKey = '';
  ThemeData? _themeData;
  ThemeData _theme(AppState app) {
    final key = '${app.settings.theme}|${app.settings.accent}|${identityHashCode(hostTheme)}';
    if (key != _themeKey || _themeData == null) {
      _themeKey = key;
      _themeData = (hostTheme ?? themeById(app.settings.theme).withAccent(app.settings.accent)).toThemeData();
    }
    return _themeData!;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.app.windowFocused = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_rebuild);
    _toastSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final Widget home = app.authed && app.state == ConnState.connected ? const MainScreen() : const ConnectScreen();
    return AppScope(
      app: app,
      child: MaterialApp(
        title: 'Pulse',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: _theme(app),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(app.settings.uiScale)), child: child!);
        },
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(home.runtimeType), child: home),
        ),
      ),
    );
  }
}

void copyText(BuildContext context, String text, [String done = '已复制']) {
  Clipboard.setData(ClipboardData(text: text));
  AppScope.read(context).toast(done);
}
