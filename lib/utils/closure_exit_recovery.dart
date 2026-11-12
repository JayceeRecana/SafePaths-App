/// Requires distinct, sustained reliable fixes before rechecking a trip whose
/// origin was on/near a closure. This never approves a route or gives an exit
/// maneuver; normal routing and all-closure admission remain authoritative.
class ClosureExitRecovery {
  bool _wasNear = false;
  DateTime? _clearSince, _lastFix;
  int _clearFixes = 0;

  void arm() {
    _wasNear = true;
    _clearSince = null;
    _lastFix = null;
    _clearFixes = 0;
  }

  void reset() {
    _wasNear = false;
    _clearSince = null;
    _lastFix = null;
    _clearFixes = 0;
  }

  void interrupt() {
    _clearSince = null;
    _lastFix = null;
    _clearFixes = 0;
  }

  bool observe({
    required bool paused,
    required bool reliable,
    required bool calculationPending,
    required bool nearClosure,
    required DateTime fixTime,
  }) {
    if (!paused) {
      reset();
      return false;
    }
    if (!reliable || calculationPending) {
      interrupt();
      return false;
    }
    if (nearClosure) {
      arm();
      return false;
    }
    if (!_wasNear || (_lastFix != null && !fixTime.isAfter(_lastFix!))) {
      return false;
    }
    if (_lastFix != null &&
        fixTime.difference(_lastFix!) > const Duration(seconds: 10)) {
      interrupt();
    }
    _lastFix = fixTime;
    _clearSince ??= fixTime;
    _clearFixes++;
    if (_clearFixes < 3 ||
        fixTime.difference(_clearSince!) < const Duration(seconds: 6)) {
      return false;
    }
    reset();
    return true;
  }
}
