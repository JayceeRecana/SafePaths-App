import 'dart:convert';
import 'dart:developer';
import '../models/road_status.dart';
import 'weather_service.dart' show WeatherState;

/// Retains geometry only for current roads, and rebuilds GeoJSON only when its
/// visible properties change. Non-map app events do not enter this pipeline.
class MapRoadData {
  final Map<String, _RoadDrawing> _roads = {};
  String _json = '{"type":"FeatureCollection","features":[]}';
  int geometryBuilds = 0;
  int dataBuilds = 0;
  int get retainedRoads => _roads.length;
  String project(
    List<RoadStatus> roads,
    WeatherState weather, {
    DateTime? now,
  }) => Timeline.timeSync('SafePaths.mapProjection', () {
    var changed = roads.length != _roads.length;
    final current = <String>{};
    for (final road in roads) {
      current.add(road.id);
      final old = _roads[road.id];
      final geometryKey = old != null && identical(old.geometry, road.geometry)
          ? old.geometryKey
          : jsonEncode(road.geometry);
      final status = road.getEffectiveStatus(weather, currentTime: now);
      final unconfirmed = road.needsStatusConfirmation(
        weather,
        currentTime: now,
      );
      final key = jsonEncode([
        road.name,
        status,
        road.riskCategory,
        unconfirmed,
      ]);
      if (old != null && old.geometryKey == geometryKey && old.key == key) {
        // Retain the new immutable model's geometry reference after a snapshot.
        old.geometry = road.geometry;
        continue;
      }
      changed = true;
      final segments = old != null && old.geometryKey == geometryKey
          ? old.segments
          : _segments(road.geometry);
      if (old == null || old.geometryKey != geometryKey) geometryBuilds++;
      _roads[road.id] = _RoadDrawing(
        road.geometry,
        geometryKey,
        key,
        segments,
        [
          for (var i = 0; i < segments.length; i++)
            {
              'type': 'Feature',
              'id': '${road.id}_$i',
              'geometry': {'type': 'LineString', 'coordinates': segments[i]},
              'properties': {
                'id': road.id,
                'name': road.name,
                'status': status,
                'color': unconfirmed
                    ? '#EAB308'
                    : status == 'not_passable'
                    ? '#B81311'
                    : status == 'partial'
                    ? '#EAB308'
                    : status == 'passable'
                    ? '#006E1C'
                    : '#EAB308',
                'glowColor': switch (road.riskCategory) {
                  'Critical' => 'rgba(255, 0, 0, 0.5)',
                  'Warning' => 'rgba(255, 165, 0, 0.4)',
                  'Watch' => 'rgba(255, 255, 0, 0.3)',
                  _ => 'rgba(0, 0, 0, 0.0)',
                },
                'isUnconfirmed': unconfirmed,
              },
            },
        ],
      );
    }
    _roads.removeWhere((id, _) => !current.contains(id));
    if (changed) {
      _json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [for (final road in roads) ..._roads[road.id]!.features],
      });
      dataBuilds++;
    }
    return _json;
  });

  static List<List<List<double>>> _segments(Map<String, dynamic>? geometry) {
    if (geometry == null) return [];
    List<List<double>> points(dynamic input) {
      if (input is! List) return [];
      final result = <List<double>>[];
      for (final point in input) {
        final dynamic lng = point is Map
            ? point['lon'] ?? point['lng']
            : point is List && point.length >= 2
            ? point[0]
            : null;
        final dynamic lat = point is Map
            ? point['lat']
            : point is List && point.length >= 2
            ? point[1]
            : null;
        if (lng is num &&
            lat is num &&
            lng.isFinite &&
            lat.isFinite &&
            lng.abs() <= 180 &&
            lat.abs() <= 90) {
          result.add([lng.toDouble(), lat.toDouble()]);
        }
      }
      return result;
    }

    final dynamic raw = geometry['segments'];
    final dynamic coordinates = geometry['coordinates'];
    if (raw is List) {
      return [
        for (final segment in raw)
          if (segment is Map) points(segment['points']),
      ].where((line) => line.length >= 2).toList();
    }
    if (geometry['type'] == 'MultiLineString' && coordinates is List) {
      return coordinates.map(points).where((line) => line.length >= 2).toList();
    }
    final line = points(coordinates);
    return line.length >= 2 ? [line] : [];
  }
}

class _RoadDrawing {
  Map<String, dynamic>? geometry;
  final String geometryKey, key;
  final List<List<List<double>>> segments;
  final List<Map<String, dynamic>> features;
  _RoadDrawing(
    this.geometry,
    this.geometryKey,
    this.key,
    this.segments,
    this.features,
  );
}
