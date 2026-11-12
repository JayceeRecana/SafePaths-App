import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/geo_utils.dart';

/// Native map-idle events can be delayed by tile loading. Read the visible pin
/// after camera changes stop too, ignoring duplicate events and late reads.
class PinSelectionState extends ChangeNotifier {
  final Future<GeoCoord> Function() readPoint;
  final Duration quietPeriod;
  PinSelectionState({
    required this.readPoint,
    this.quietPeriod = const Duration(milliseconds: 350),
  });
  Timer? _quiet;
  String? _cameraSignature;
  int revision = 0;
  bool moving = true, failed = false, _disposed = false;
  GeoCoord? point;
  bool get canConfirm => !moving && !failed && point != null;

  void cameraChanged(String signature) {
    if (_disposed || signature == _cameraSignature) return;
    _cameraSignature = signature;
    revision++;
    moving = true;
    failed = false;
    _quiet?.cancel();
    _quiet = Timer(quietPeriod, refresh);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final request = revision;
    try {
      final next = await readPoint().timeout(const Duration(seconds: 5));
      if (_disposed || request != revision) return;
      if (!next.lat.isFinite ||
          !next.lng.isFinite ||
          next.lat.abs() > 90 ||
          next.lng.abs() > 180) {
        throw const FormatException('Invalid map position');
      }
      point = next;
      moving = false;
      failed = false;
    } catch (_) {
      if (_disposed || request != revision) return;
      point = null;
      moving = false;
      failed = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _quiet?.cancel();
    super.dispose();
  }
}
