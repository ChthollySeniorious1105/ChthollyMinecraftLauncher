/// Error surfaced to the UI. [message] is user-facing (Chinese).
class CmlException implements Exception {
  final String code;
  final String message;
  final Object? cause;
  const CmlException(this.code, this.message, [this.cause]);
  @override
  String toString() => cause == null ? '$message ($code)' : '$message ($code): $cause';
}

/// Thrown when a [CancelToken] is cancelled.
class CancelledException extends CmlException {
  const CancelledException() : super('cancelled', '已取消');
}

class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() f) => _cancelled ? f() : _listeners.add(f);
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}
