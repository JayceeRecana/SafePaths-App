import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Display-only model configuration. No positions or routing decisions live here.
abstract final class NavigationCarModel {
  // Native Mapbox SIGSEGV observed on Pixel_9 x86_64, 2026-11-02.
  // Dart try/catch cannot recover from it. Keep every normal build on 2D
  // until an isolated native reproduction and device acceptance are complete.
  static const enabled = false;
  static const asset = 'assets/navigation/safepaths-sedan-v1.glb';
  static Future<void>? _validation;

  static bool supports(String? mode) => enabled && mode == 'Sedan';

  static Future<void> ensureBundled() => _validation ??= _validate();

  static Future<void> _validate() async {
    try {
      final bytes = await rootBundle.load(asset);
      if (bytes.lengthInBytes < 20 ||
          bytes.getUint32(0, Endian.little) != 0x46546c67 ||
          bytes.getUint32(4, Endian.little) != 2 ||
          bytes.getUint32(8, Endian.little) != bytes.lengthInBytes) {
        throw const FormatException('Invalid navigation model');
      }
    } catch (_) {
      _validation = null;
      rethrow;
    }
  }

  static LocationPuck puck(double bearing) => LocationPuck(
    locationPuck3D: LocationPuck3D(
      // The installed SDK resolves asset:// to its native Flutter asset path.
      modelUri: 'asset://$asset',
      modelScaleMode: ModelScaleMode.VIEWPORT,
      // 4.18m long model, about 38px long regardless of map zoom.
      modelScale: [9, 9, 9],
      modelRotation: rotation(bearing),
      modelCastShadows: false,
      modelReceiveShadows: false,
      modelEmissiveStrength: 0.6,
    ),
  );

  // Model faces -Z in glTF (north after Mapbox's Y-up conversion).
  // Positive compass bearings are clockwise; model yaw is counterclockwise.
  static List<double> rotation(double bearing) => [0, 0, -bearing];
}

/// Holds the last trustworthy travel direction instead of using compass jitter.
class NavigationMarkerHeading {
  double bearing = 0;

  void update({
    required double heading,
    required double speed,
    required double accuracy,
    required double headingAccuracy,
    required Duration age,
  }) {
    if (!heading.isFinite ||
        heading < 0 ||
        heading > 360 ||
        !speed.isFinite ||
        speed < 2 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 25 ||
        !headingAccuracy.isFinite ||
        headingAccuracy < 0 ||
        headingAccuracy > 35 ||
        age > const Duration(seconds: 5) ||
        age < const Duration(seconds: -5)) {
      return;
    }
    final next = heading % 360;
    final difference = ((next - bearing + 540) % 360 - 180).abs();
    if (difference >= 3) bearing = next;
  }
}
