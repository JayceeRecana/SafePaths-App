import '../config/study_area.dart';

class TestRoadCandidate {
  final String id, name;
  final List<Map<String, double>> points;
  const TestRoadCandidate(this.id, this.name, this.points);
}

class TestRoadImport {
  static String segmentKey(List<Map<String, double>> points) {
    final parts = points
        .map(
          (p) =>
              '${p['lng']!.toStringAsFixed(7)},${p['lat']!.toStringAsFixed(7)}',
        )
        .toList();
    final forward = parts.join(';'), reverse = parts.reversed.join(';');
    return forward.compareTo(reverse) < 0 ? forward : reverse;
  }

  static String query(StudyArea area) =>
      '[out:json][timeout:25];'
      'way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|pedestrian|footway|path|cycleway|steps|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)\$"]'
      '["access"!~"^(private|no)\$"](${area.south},${area.west},${area.north},${area.east});out geom;';

  static List<TestRoadCandidate> parse(List<dynamic> elements) {
    final result = <TestRoadCandidate>[];
    final seen = <String>{};
    for (final element in elements.whereType<Map>()) {
      if (element['type'] != 'way' || element['id'] == null) continue;
      final id = 'osm_way_${element['id']}';
      if (!seen.add(id)) continue;
      final tags = element['tags'] as Map? ?? {};
      if (tags['access'] == 'private' || tags['access'] == 'no') continue;
      final points = <Map<String, double>>[];
      for (final point
          in (element['geometry'] as List? ?? []).whereType<Map>()) {
        if (point['lat'] is num && point['lon'] is num) {
          points.add({
            'lat': (point['lat'] as num).toDouble(),
            'lng': (point['lon'] as num).toDouble(),
          });
        }
      }
      if (points.length < 2) continue;
      final name = (tags['name'] as String?)?.trim();
      result.add(
        TestRoadCandidate(
          id,
          '${name == null || name.isEmpty ? "Unnamed ${tags['highway'] ?? 'road'}" : name} (OSM ${element['id']})',
          points,
        ),
      );
    }
    return result;
  }
}
