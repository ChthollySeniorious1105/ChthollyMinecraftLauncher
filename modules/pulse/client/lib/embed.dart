import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';
import 'native/native.dart';
import 'net/connection.dart';
import 'screens/connect_screen.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart' show voicesDirOverride;
import 'state/app_state.dart';
import 'state/settings.dart';
import 'theme/themes.dart';

export 'theme/themes.dart' show PulseTheme, hostTheme;

/// Pulse running inside a host app (CML): no tray / window management — the host owns the window.
/// The AppState is kept alive across page switches so voice chat continues in the background.
class PulseHost {
  static AppState? _app;
  static Future<AppState>? _starting;

  /// Running instance, if [start] has completed.
  static AppState? get app => _app;

  /// Starts Pulse once. [voicesDir] replaces `<exe>\ai\voices`; the base models are found via the
  /// `PULSE_MODELS_DIR` environment variable, which the host must set before starting the process.
  static Future<AppState> start({String? voicesDir}) {
    voicesDirOverride = voicesDir;
    return _starting ??= () async {
      final native = Native.load();
      final settings = await Settings.load(native);
      final app = AppState(native, settings);
      await app.start();
      return _app = app;
    }();
  }

  static void shutdown() {
    final a = _app;
    _app = null;
    _starting = null;
    a?.leaveVoice();
    a?.dispose();
  }
}

/// The Pulse UI as a widget: its own Navigator / theme, sized by the parent.
class PulseEmbed extends StatefulWidget {
  final PulseTheme theme;
  final String? voicesDir;
  const PulseEmbed({super.key, required this.theme, this.voicesDir});
  @override
  State<PulseEmbed> createState() => _PulseEmbedState();
}

class _PulseEmbedState extends State<PulseEmbed> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _toastSub;
  AppState? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    hostTheme = widget.theme;
    PulseHost.start(voicesDir: widget.voicesDir).then((a) {
      if (!mounted) return;
      a.addListener(_rebuild);
      _toastSub = a.toasts.listen((t) {
        _messenger.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3), width: 420));
      });
      setState(() => _app = a);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void didUpdateWidget(PulseEmbed old) {
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
    final theme = widget.theme.toThemeData();
    final app = _app;
    if (app == null) {
      return Theme(
        data: theme,
        child: Center(child: _error == null ? const CircularProgressIndicator() : Text('Pulse 启动失败：$_error')),
      );
    }
    app.windowFocused = true;
    return AppScope(
      app: app,
      child: Theme(
        data: theme,
        child: ScaffoldMessenger(
          key: _messenger,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(app.settings.uiScale)),
            child: HeroControllerScope.none(
              // The route is generated once; _PulseHome re-reads AppState on every notification.
              child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _PulseHome())),
            ),
          ),
        ),
      ),
    );
  }
}


/// Picks the current Pulse screen from AppState (listens via AppScope, so it switches immediately).
class _PulseHome extends StatelessWidget {
  const _PulseHome();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget home = app.authed && app.state == ConnState.connected ? const MainScreen() : const ConnectScreen();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(home.runtimeType), child: home),
    );
  }
}
