import 'package:geolocator/geolocator.dart' as geo;

/// Geometry can be tested without a clock; navigation supplies [now] so cached
/// or future-dated positions cannot become a current rerouting origin.
bool usableLocationFix(geo.Position fix, {DateTime? now}) {
  if (!fix.latitude.isFinite ||
      !fix.longitude.isFinite ||
      fix.latitude.abs() > 90 ||
      fix.longitude.abs() > 180 ||
      !fix.accuracy.isFinite ||
      fix.accuracy < 0 ||
      fix.accuracy > 60)
    return false;
  if (now != null) {
    final age = now.difference(fix.timestamp);
    if (age > const Duration(seconds: 30) || age < const Duration(seconds: -5))
      return false;
  }
  return true;
}
