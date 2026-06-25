import 'dart:math' show cos, sqrt, asin, sin;

class GeoPoint {
  final double lat;
  final double lng;
  GeoPoint(this.lat, this.lng);
}

class GeoUtils {
  static List<GeoPoint> extractPoints(Map<String, dynamic>? geometry) {
    List<GeoPoint> pts = [];
    if (geometry == null) return pts;
    final coords = geometry['coordinates'] as List<dynamic>?;
    if (coords == null) return pts;

    for (final c in coords) {
      if (c is Map) {
        final lon = (c['lon'] as num?)?.toDouble() ?? (c['lng'] as num?)?.toDouble();
        final lat = (c['lat'] as num?)?.toDouble();
        if (lon != null && lat != null) pts.add(GeoPoint(lat, lon));
      } else if (c is List && c.length >= 2) {
        final lon = (c[0] as num?)?.toDouble();
        final lat = (c[1] as num?)?.toDouble();
        if (lon != null && lat != null) pts.add(GeoPoint(lat, lon));
      }
    }
    return pts;
  }

  static double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    final dLng = (lng2 - lng1) * 3.141592653589793 / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * 3.141592653589793 / 180.0) * cos(lat2 * 3.141592653589793 / 180.0) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  static double pointToSegmentDistanceMeters(
      double pLng, double pLat, double aLng, double aLat, double bLng, double bLat) {
    final abLng = bLng - aLng;
    final abLat = bLat - aLat;
    final apLng = pLng - aLng;
    final apLat = pLat - aLat;

    final abLenSq = abLng * abLng + abLat * abLat;
    if (abLenSq == 0) {
      return haversineMeters(pLat, pLng, aLat, aLng);
    }

    double t = (apLng * abLng + apLat * abLat) / abLenSq;
    t = t.clamp(0.0, 1.0);

    final closestLng = aLng + t * abLng;
    final closestLat = aLat + t * abLat;

    return haversineMeters(pLat, pLng, closestLat, closestLng);
  }
}
