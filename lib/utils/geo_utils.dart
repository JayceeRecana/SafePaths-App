import 'dart:math' show cos, sqrt, asin, sin;
import '../config/app_environment.dart';

class GeoCoord {
  final double lat;
  final double lng;
  GeoCoord(this.lat, this.lng);
}

class GeoUtils {
  /// Report proximity must not bridge disconnected road ways.
  static double distanceToGeometryMeters(
    double lat,
    double lng,
    Map<String, dynamic>? geometry,
  ) {
    var best = double.infinity;
    final longitudeScale = cos(lat * 3.141592653589793 / 180);
    for (final segment in extractSegments(geometry)) {
      for (var i = 0; i < segment.length - 1; i++) {
        final a = segment[i], b = segment[i + 1];
        final dx = (b.lng - a.lng) * longitudeScale, dy = b.lat - a.lat;
        final length = dx * dx + dy * dy;
        final t = length == 0
            ? 0.0
            : ((((lng - a.lng) * longitudeScale) * dx + (lat - a.lat) * dy) /
                      length)
                  .clamp(0.0, 1.0);
        final distance = haversineMeters(
          lat,
          lng,
          a.lat + t * (b.lat - a.lat),
          a.lng + t * (b.lng - a.lng),
        );
        if (distance < best) best = distance;
      }
    }
    return best;
  }

  /// Preserve disconnected ways instead of inventing connecting road segments.
  static List<List<GeoCoord>> extractSegments(Map<String, dynamic>? geometry) {
    if (geometry == null) return [];
    if (geometry['segments'] is List) {
      return (geometry['segments'] as List)
          .whereType<Map>()
          .map((segment) {
            final result = <GeoCoord>[];
            for (final point in (segment['points'] as List? ?? [])) {
              _extractFromDynamic(point, result);
            }
            return result;
          })
          .where((points) => points.length >= 2)
          .toList();
    }
    if (geometry['type'] == 'MultiLineString' &&
        geometry['coordinates'] is List) {
      return (geometry['coordinates'] as List)
          .map((segment) {
            final result = <GeoCoord>[];
            _extractFromDynamic(segment, result);
            return result;
          })
          .where((points) => points.length >= 2)
          .toList();
    }
    final points = extractPoints(geometry);
    return points.length >= 2 ? [points] : [];
  }

  static List<GeoCoord> extractPoints(Map<String, dynamic>? geometry) {
    List<GeoCoord> pts = [];
    if (geometry == null) return pts;

    // 1. Check for multi-segment format ('segments')
    if (geometry.containsKey('segments')) {
      final segments = geometry['segments'] as List<dynamic>?;
      if (segments != null) {
        for (var segment in segments) {
          if (segment is Map && segment.containsKey('points')) {
            var pointsList = segment['points'];
            if (pointsList is List) {
              for (var pt in pointsList) {
                if (pt is Map) {
                  final lon =
                      (pt['lon'] as num?)?.toDouble() ??
                      (pt['lng'] as num?)?.toDouble();
                  final lat = (pt['lat'] as num?)?.toDouble();
                  if (lon != null && lat != null) pts.add(GeoCoord(lat, lon));
                }
              }
            }
          }
        }
      }
    }

    // 2. Check for standard GeoJSON 'coordinates' (LineString, MultiLineString, etc.)
    if (geometry.containsKey('coordinates')) {
      final coords = geometry['coordinates'] as List<dynamic>?;
      if (coords != null) {
        _extractFromDynamic(coords, pts);
      }
    }

    return pts;
  }

  static void _extractFromDynamic(dynamic item, List<GeoCoord> pts) {
    if (item is List) {
      if (item.length >= 2 && item[0] is num && item[1] is num) {
        // [lon, lat]
        final lon = (item[0] as num).toDouble();
        final lat = (item[1] as num).toDouble();
        pts.add(GeoCoord(lat, lon));
      } else {
        for (var sub in item) {
          _extractFromDynamic(sub, pts);
        }
      }
    } else if (item is Map) {
      final lon =
          (item['lon'] as num?)?.toDouble() ??
          (item['lng'] as num?)?.toDouble();
      final lat = (item['lat'] as num?)?.toDouble();
      if (lon != null && lat != null) {
        pts.add(GeoCoord(lat, lon));
      }
    }
  }

  static double haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    final dLng = (lng2 - lng1) * 3.141592653589793 / 180.0;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * 3.141592653589793 / 180.0) *
            cos(lat2 * 3.141592653589793 / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  static double pointToSegmentDistanceMeters(
    double pLng,
    double pLat,
    double aLng,
    double aLat,
    double bLng,
    double bLat,
  ) {
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

  /// Extracts the canonical middle point (lon, lat) of a road geometry for camera positioning.
  /// Handles GeoJSON LineString coordinates, multi-segment formats, and lat/lon or lat/lng maps.
  static GeoCoord? getRoadCenter(Map<String, dynamic>? geometry) {
    if (geometry == null) return null;

    // 1. If geometry has multi-segments, pick the midpoint of the LONGEST continuous segment
    // to avoid landing in gaps between disconnected OSM ways.
    if (geometry.containsKey('segments')) {
      final segments = geometry['segments'] as List<dynamic>?;
      if (segments != null && segments.isNotEmpty) {
        List<GeoCoord> bestSegmentPoints = [];
        for (var seg in segments) {
          if (seg is Map && seg.containsKey('points')) {
            var ptsList = seg['points'];
            if (ptsList is List) {
              List<GeoCoord> segPts = [];
              for (var pt in ptsList) {
                if (pt is Map) {
                  final lon =
                      (pt['lon'] as num?)?.toDouble() ??
                      (pt['lng'] as num?)?.toDouble();
                  final lat = (pt['lat'] as num?)?.toDouble();
                  if (lon != null && lat != null)
                    segPts.add(GeoCoord(lat, lon));
                }
              }
              if (segPts.length > bestSegmentPoints.length) {
                bestSegmentPoints = segPts;
              }
            }
          }
        }
        if (bestSegmentPoints.isNotEmpty) {
          return bestSegmentPoints[bestSegmentPoints.length ~/ 2];
        }
      }
    }

    // 2. Standard GeoJSON coordinates list
    final coordsDyn = geometry['coordinates'] as List<dynamic>?;
    if (coordsDyn != null && coordsDyn.isNotEmpty) {
      final middleIndex = coordsDyn.length ~/ 2;
      final middleCoord = coordsDyn[middleIndex];
      double? lon;
      double? lat;
      if (middleCoord is Map) {
        lon =
            (middleCoord['lon'] as num?)?.toDouble() ??
            (middleCoord['lng'] as num?)?.toDouble();
        lat = (middleCoord['lat'] as num?)?.toDouble();
      } else if (middleCoord is List && middleCoord.length >= 2) {
        lon = (middleCoord[0] as num?)?.toDouble();
        lat = (middleCoord[1] as num?)?.toDouble();
      }
      if (lon != null && lat != null) {
        return GeoCoord(lat, lon);
      }
    }

    // 3. Fallback: extract all points and pick the middle one
    final allPoints = extractPoints(geometry);
    if (allPoints.isNotEmpty) {
      return allPoints[allPoints.length ~/ 2];
    }
    return null;
  }

  static List<GeoCoord>? _marulasPolygonCache;

  /// Returns the parsed polygon points of Barangay Marulas
  static List<GeoCoord> get marulasPolygon {
    if (_marulasPolygonCache != null) return _marulasPolygonCache!;
    final tokens = AppEnvironment.area.polygon.trim().split(RegExp(r'\s+'));
    List<GeoCoord> pts = [];
    for (int i = 0; i < tokens.length - 1; i += 2) {
      final lat = double.tryParse(tokens[i]);
      final lng = double.tryParse(tokens[i + 1]);
      if (lat != null && lng != null) {
        pts.add(GeoCoord(lat, lng));
      }
    }
    _marulasPolygonCache = pts;
    return pts;
  }

  // Barangay Marulas Bounding Box Coordinates
  static double get marulasMinLng => AppEnvironment.area.west;
  static double get marulasMaxLng => AppEnvironment.area.east;
  static double get marulasMinLat => AppEnvironment.area.south;
  static double get marulasMaxLat => AppEnvironment.area.north;
  static String get studyAreaBBox => AppEnvironment.area.bbox;

  /// Determines if a coordinate (lat, lng) is strictly within Barangay Marulas scope.
  /// Includes an optional buffer in meters to account for road widths and GPS tolerance.
  static bool isInsideStudyArea(
    double lat,
    double lng, {
    double bufferMeters = 75.0,
  }) {
    // 1. Fast Bounding Box check
    if (lng < marulasMinLng ||
        lng > marulasMaxLng ||
        lat < marulasMinLat ||
        lat > marulasMaxLat) {
      return false;
    }

    final poly = marulasPolygon;
    if (poly.isEmpty) {
      return true;
    }

    // 2. Ray-casting point-in-polygon algorithm
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].lng, yi = poly[i].lat;
      final xj = poly[j].lng, yj = poly[j].lat;
      final intersect =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }

    if (inside) return true;

    // 3. Proximity buffer check for boundary roads
    if (bufferMeters > 0) {
      for (int i = 0; i < poly.length; i++) {
        final nextIdx = (i + 1) % poly.length;
        final d = pointToSegmentDistanceMeters(
          lng,
          lat,
          poly[i].lng,
          poly[i].lat,
          poly[nextIdx].lng,
          poly[nextIdx].lat,
        );
        if (d <= bufferMeters) return true;
      }
    }

    return false;
  }
}
