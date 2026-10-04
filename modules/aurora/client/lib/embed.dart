import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';
import 'net/connection.dart';
import 'screens/connect_screen.dart';
import 'screens/local_game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/room_screen.dart';
import 'state/app_state.dart';
import 'theme/themes.dart';
import 'widgets/mahjong_table.dart';
import 'platform/resume_scope.dart';

export 'theme/themes.dart' show AuroraTheme, hostTheme, assetPrefix;

/// Aurora running inside a host app (CML). The state lives for the whole process so a room / game
/// survives switching launcher pages.
class AuroraHost {
  static AppState? _app;
  static Future<AppState>? _starting;

  static AppState? get app => _app;

  static Future<AppState> start() => _starting ??= () async {
        final app = AppState();
        await app.load();
        await MjAutoState.load(app.prefs);
        return _app = app;
      }();
}

/// The Aurora UI as a widget with its own Navigator, sized by the parent.
class AuroraEmbed extends StatefulWidget {
  final AuroraTheme theme;
  const AuroraEmbed({super.key, required this.theme});
  @override
  State<AuroraEmbed> createState() => _AuroraEmbedState();
}

class _AuroraEmbedState extends State<AuroraEmbed> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _toastSub;
  AppState? _app;

  @override
  void initState() {
    super.initState();
    hostTheme = widget.theme;
    assetPrefix = 'packages/aurora_client/';
    AuroraHost.start().then((a) {
      if (!mounted) return;
      a.addListener(_rebuild);
      _toastSub = a.toasts.listen((t) {
        _messenger.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
      });
      setState(() => _app = a);
    });
  }

  @override
  void didUpdateWidget(AuroraEmbed old) {
    super.didUpdateWidget(old);
    hostTheme = widget.theme;
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _app?.removeListener(_rebuild);
    _toastSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final app = _app;
    if (app == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, panel) => AppScope(
      app: app,
      child: Theme(
        data: theme.toThemeData(),
        child: ScaffoldMessenger(
          key: _messenger,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(panel.maxWidth, panel.maxHeight), textScaler: TextScaler.linear(app.uiScale)),
            child: DecoratedBox(
              decoration: theme.backgroundDecoration,
              child: HeroControllerScope.none(
                // The route is generated once; _AuroraHome re-reads AppState on every notification.
                child: ResumeScope(app: app, child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _AuroraHome()))),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}


/// Picks the current Aurora screen from AppState (listens via AppScope, so it switches immediately).
class _AuroraHome extends StatelessWidget {
  const _AuroraHome();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget home;
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(home.runtimeType), child: home),
    );
  }
}
