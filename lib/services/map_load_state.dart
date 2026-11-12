import 'dart:async';
import 'package:flutter/foundation.dart';

class MapLoadState extends ChangeNotifier {
  final Duration timeout;
  MapLoadState({this.timeout = const Duration(seconds: 20)});
  Timer? _timer;
  bool loading = false;
  String? mapError, overlayError;
  bool _disposed = false;
  void begin() {
    if (_disposed) return;
    _timer?.cancel();
    loading = true;
    mapError = null;
    overlayError = null;
    _timer = Timer(
      timeout,
      () => failed(
        'Map loading is taking too long. Check your connection and retry.',
      ),
    );
    notifyListeners();
  }

  void loaded() {
    if (_disposed) return;
    _timer?.cancel();
    loading = false;
    mapError = null;
    notifyListeners();
  }

  void failed([
    String message =
        'Some map details could not load. Check your connection and retry.',
  ]) {
    if (_disposed) return;
    _timer?.cancel();
    loading = false;
    mapError = message;
    notifyListeners();
  }

  void overlaysFailed() {
    if (_disposed) return;
    overlayError =
        'Road status overlays could not refresh. Current conditions are unconfirmed.';
    notifyListeners();
  }

  void overlaysLoaded() {
    if (_disposed || overlayError == null) return;
    overlayError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
