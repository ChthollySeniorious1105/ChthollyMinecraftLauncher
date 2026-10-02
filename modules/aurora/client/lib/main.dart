import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/connect_screen.dart';
import 'screens/local_game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/room_screen.dart';
import 'state/app_state.dart';
import 'net/connection.dart';
import 'theme/themes.dart';
import 'widgets/mahjong_table.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.load();
  await MjAutoState.load(app.prefs);
  runApp(AuroraApp(app));
}

/// Makes AppState available to the whole tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class AuroraApp extends StatefulWidget {
  final AppState app;
  const AuroraApp(this.app, {super.key});
  @override
  State<AuroraApp> createState() => _AuroraAppState();
}

class _AuroraAppState extends State<AuroraApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _toastSub;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_rebuild);
    _toastSub = widget.app.toasts.listen((t) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.app.removeListener(_rebuild);
    _toastSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = themeById(app.themeId);
    Widget home;
    if (!app.hasProfile) {
      home = const ProfileScreen(firstRun: true);
    } else if (app.local != null) {
      home = const LocalGameScreen();
    } else if (app.state != ConnState.connected && app.myId == 0) {
      home = const ConnectScreen();
    } else if (app.room != null) {
      home = const RoomScreen();
    } else {
      home = const LobbyScreen();
    }
    return AppScope(
      app: app,
      child: MaterialApp(
        title: 'Aurora',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: theme.toThemeData(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(app.uiScale)),
            child: DecoratedBox(
              decoration: theme.backgroundDecoration,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{},
                child: child!,
              ),
            ),
          );
        },
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(home.runtimeType), child: home),
        ),
      ),
    );
  }
}

/// Utility used by screens for copy-to-clipboard.
void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  AppScope.read(context).toast('已复制');
}
