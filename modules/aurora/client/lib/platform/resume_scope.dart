import 'package:flutter/widgets.dart';

import '../state/app_state.dart';

/// Reconnect using the same server-issued identity when a suspended tab resumes.
class ResumeScope extends StatefulWidget {
  final AppState app;
  final Widget child;
  const ResumeScope({super.key, required this.app, required this.child});
  @override
  State<ResumeScope> createState() => _ResumeScopeState();
}

class _ResumeScopeState extends State<ResumeScope> {
  late final listener = AppLifecycleListener(
    onResume: () => widget.app.resumeConnection(),
  );
  @override
  void initState() {
    super.initState();
    listener;
  }

  @override
  void dispose() {
    listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
