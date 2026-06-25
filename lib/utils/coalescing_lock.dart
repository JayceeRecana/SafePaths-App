import 'dart:async';

/// A lock that coalesces multiple rapid requests into a single delayed execution.
/// If a request is already pending, subsequent requests within the delay window
/// are ignored (coalesced), and only one execution happens after the delay.
class CoalescingLock {
  final Duration delay;
  Timer? _timer;
  bool _isPending = false;
  Future<void>? _currentExecution;

  CoalescingLock({this.delay = const Duration(seconds: 1)});

  /// Schedules the [action] to run. If an action is already scheduled or running,
  /// this call returns the Future of the currently scheduled/running action.
  Future<void> run(Future<void> Function() action) {
    if (_isPending || _currentExecution != null) {
      // Coalesce: wait for the existing execution to finish.
      return _currentExecution ?? Future.value();
    }

    _isPending = true;
    final completer = Completer<void>();
    _currentExecution = completer.future;

    _timer = Timer(delay, () async {
      _isPending = false;
      try {
        await action();
      } finally {
        _currentExecution = null;
        completer.complete();
      }
    });

    return completer.future;
  }

  void cancel() {
    _timer?.cancel();
    _isPending = false;
    _currentExecution = null;
  }
}
