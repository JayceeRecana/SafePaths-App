import '../models/road_status.dart';
import '../utils/place_search.dart';
import '../utils/geo_utils.dart';
import '../config/study_area.dart';

class PinRoadMatch {
  final RoadStatus road;
  final double meters;
  const PinRoadMatch(this.road, this.meters);
}

/// Context only: never moves the pin or invents links between separate ways.
PinRoadMatch? nearestPinRoad(
  Iterable<RoadStatus> roads,
  double lat,
  double lng,
) {
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    return null;
  }
  PinRoadMatch? result;
  for (final road in roads) {
    try {
      final distance = GeoUtils.distanceToGeometryMeters(
        lat,
        lng,
        road.geometry,
      );
      if (distance.isFinite && (result == null || distance < result.meters)) {
        result = PinRoadMatch(road, distance);
      }
    } catch (_) {
      // One malformed road cannot substitute an unrelated road for the pin.
    }
  }
  return result;
}

class PinPlaceSuggestion {
  final String id, title;
  final String? subtitle;
  final bool landmark;
  final double lat, lng;
  const PinPlaceSuggestion({
    required this.id,
    required this.title,
    this.subtitle,
    required this.landmark,
    required this.lat,
    required this.lng,
  });
}

/// Local suggestions only: no per-keystroke geocoding or unresolved facilities.
List<PinPlaceSuggestion> pinPlaceSuggestions(
  String query,
  Iterable<RoadStatus> roads,
  StudyArea area, {
  required bool Function(double lat, double lng) isInScope,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return [];
  bool usable(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      isInScope(lat, lng);
  final choices = <String, PinPlaceSuggestion>{};
  for (final place in area.searchLandmarks(q)) {
    if (!place.routingAvailable || !usable(place.lat, place.lng)) continue;
    choices['place:${place.id}'] = PinPlaceSuggestion(
      id: place.id,
      title: place.name,
      landmark: true,
      lat: place.lat,
      lng: place.lng,
    );
  }
  for (final road in roads) {
    if (!matchesPlaceSearch(q, [road.name], ignoreAreaWords: true)) continue;
    try {
      final segments =
          GeoUtils.extractSegments(road.geometry)
              .map((s) => s.where((p) => usable(p.lat, p.lng)).toList())
              .where((s) => s.isNotEmpty)
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));
      if (segments.isEmpty) continue;
      final line = segments.first;
      final point = line[line.length ~/ 2];
      choices['road:${road.id}'] = PinPlaceSuggestion(
        id: road.id,
        title: road.name,
        landmark: false,
        lat: point.lat,
        lng: point.lng,
      );
    } catch (_) {
      // Invalid geometry is not a usable search destination.
    }
  }
  int rank(PinPlaceSuggestion item) {
    final name = item.title.toLowerCase();
    return name == q
        ? 0
        : name.startsWith(q)
        ? 1
        : name.contains(q)
        ? 2
        : 3;
  }

  final result = choices.values.toList()
    ..sort((a, b) {
      final order = rank(a).compareTo(rank(b));
      return order != 0 ? order : a.title.compareTo(b.title);
    });
  return result.take(6).toList();
}
