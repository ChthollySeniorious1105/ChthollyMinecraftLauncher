import 'dart:async';

import 'errors.dart';

enum TaskState { pending, running, done, failed, cancelled }

/// A long-running operation with progress, shown in the launcher's task center.
class Task<T> {
  final String title;
  final CancelToken cancel = CancelToken();
  final _changes = StreamController<Task<T>>.broadcast();
  TaskState state = TaskState.pending;
  double progress = 0; // 0..1, or -1 for indeterminate
  String detail = '';
  int bytesPerSecond = 0;
  Object? error;
  T? result;
  final _done = Completer<T>();

  Task(this.title);

  Stream<Task<T>> get changes => _changes.stream;
  Future<T> get future => _done.future;

  void update({double? progress, String? detail, int? speed}) {
    if (progress != null) this.progress = progress;
    if (detail != null) this.detail = detail;
    if (speed != null) bytesPerSecond = speed;
    _changes.add(this);
  }

  /// Runs [body] and completes the task. Errors are captured into [error].
  Future<T> run(Future<T> Function(Task<T> t) body) async {
    state = TaskState.running;
    _changes.add(this);
    try {
      final r = await body(this);
      result = r;
      state = TaskState.done;
      progress = 1;
      _changes.add(this);
      _done.complete(r);
    } catch (e, st) {
      error = e;
      state = e is CancelledException ? TaskState.cancelled : TaskState.failed;
      _changes.add(this);
      _done.completeError(e, st);
    }
    unawaited(_changes.close());
    return _done.future;
  }
}
