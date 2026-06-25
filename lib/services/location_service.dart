import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class LocationService {
  /// Request location permissions and get the current position.
  static Future<Position?> getCurrentPosition() async {
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
    final geoPosition = await geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
      )
    );

    return Position(geoPosition.longitude, geoPosition.latitude);
  }

  /// Returns a continuous stream of the device's location updates.
  static Stream<Position>? getPositionStream() {
    // Only return a stream if permissions are likely granted
    return geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).map((geoPosition) => Position(geoPosition.longitude, geoPosition.latitude));
  }
}
