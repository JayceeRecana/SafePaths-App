import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../utils/location_fix.dart';

class LocationService {
  /// Request location permissions and get the current position.
  static Future<geo.Position?> getCurrentFix() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled, return null or handle gracefully.
      return null;
    }

    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        // Permissions are denied, return null.
        return null;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return null;
    }

    // When we reach here, permissions are granted and we can continue accessing the position of the device.
    try {
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      // Timeout or error, try last known position
      final lastKnown = await geo.Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 3),
      );
      return lastKnown;
    }
  }

  /// Planner callers retain the validated coordinate-only contract. Navigation
  /// needs the raw timestamp/accuracy to validate and explain rejected fixes.
  static Future<Position?> getCurrentPosition() async {
    final fix = await getCurrentFix();
    return fix != null && usableLocationFix(fix, now: DateTime.now())
        ? Position(fix.longitude, fix.latitude)
        : null;
  }

  // The Android plugin shares its first stream across subscribers. All callers
  // must use these settings; consumer features throttle their own work instead.
  static const trackingSettings = geo.LocationSettings(
    accuracy: geo.LocationAccuracy.high,
    distanceFilter: 0,
  );

  /// Returns a continuous stream of the device's location updates exposing accuracy and heading.
  static Stream<geo.Position> getPositionStream() {
    return geo.Geolocator.getPositionStream(locationSettings: trackingSettings);
  }
}
