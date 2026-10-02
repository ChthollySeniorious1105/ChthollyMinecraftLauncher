import 'dart:async';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import 'i18n/i18n.dart';

/// App-wide state: the core context plus UI-facing notifications.
class AppState extends ChangeNotifier {
  final CmlContext ctx = CmlContext();
  final List<Task> tasks = [];
  final List<String> gameLog = [];
  GameProcess? running;
  bool ready = false;
  String? initError;

  LauncherSettings get settings => ctx.settings;

  Future<void> init() async {
    try {
      await ctx.init();
    } catch (e) {
      initError = '$e';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    ctx.applySettings();
    await settings.save();
    notifyListeners();
  }

  void changed() => notifyListeners();

  /// Starts a task, tracks it in the task center, and surfaces errors via [onError].
  Future<T?> runTask<T>(String title, Future<T> Function(Task<T> t) body, {void Function(Object e)? onError}) async {
    final t = Task<T>(title);
    tasks.insert(0, t);
    notifyListeners();
    final sub = t.changes.listen((_) => notifyListeners());
    try {
      return await t.run(body);
    } catch (e) {
      onError?.call(e);
      return null;
    } finally {
      await sub.cancel();
      notifyListeners();
      // finished tasks stay visible for a while
      Timer(const Duration(seconds: 20), () {
        if (t.state != TaskState.running) {
          tasks.remove(t);
          notifyListeners();
        }
      });
    }
  }

  int get activeTasks => tasks.where((t) => t.state == TaskState.running).length;

  void addLog(String l) {
    gameLog.add(l);
    if (gameLog.length > 3000) gameLog.removeRange(0, 500);
  }
}

/// Inherited access to [AppState].
class App extends InheritedNotifier<AppState> {
  const App({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<App>()!.notifier!;
  static AppState read(BuildContext c) => (c.getElementForInheritedWidgetOfExactType<App>()!.widget as App).notifier!;
}

String fmtBytes(num b) {
  if (b < 1024) return '$b B';
  if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
}

String fmtCount(int n) {
  if (currentLanguage == AppLanguage.en) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
  if (n >= 100000000) return trGlobal('{0} 亿', [(n / 100000000).toStringAsFixed(1)]);
  if (n >= 10000) return trGlobal('{0} 万', [(n / 10000).toStringAsFixed(1)]);
  return '$n';
}

String fmtDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String errText(Object e) => e is CmlException ? trCore(e.message) : '$e';

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    width: 480,
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<bool> confirm(BuildContext context, String title, String body, {String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(trGlobal('取消'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? trGlobal('确定')),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> prompt(BuildContext context, String title, {String initial = '', String hint = '', bool obscure = false}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(controller: ctl, autofocus: true, obscureText: obscure, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(c, v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(trGlobal('取消'))),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(trGlobal('确定'))),
      ],
    ),
  );
}
