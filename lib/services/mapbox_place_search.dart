import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/study_area.dart';
import '../data/marulas_evacuation_sites.dart';
import '../utils/place_search.dart';

class MapboxPlace {
  final String id, name, address;
  final double lat, lng;
  final bool isPoi;
  const MapboxPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.isPoi,
  });
  Map<String, dynamic> toFeatureMap() => {
    'id': id,
    'text': name,
    'place_name': address.isEmpty ? name : '$name, $address',
    'center': [lng, lat],
    'category': 'Mapbox Location',
  };
}

class MapboxPlaceSearchUnavailable implements Exception {
  const MapboxPlaceSearchUnavailable();
}

/// Search Box results live only in the active search/navigation session.
/// Do not copy provider coordinates into the bundled catalog or database.
class MapboxPlaceSearch {
  static Future<List<MapboxPlace>> search({
    required String query,
    required String token,
    required StudyArea area,
    required bool Function(double lat, double lng) isInScope,
    List<String> expectedNames = const [],
    Future<http.Response> Function(Uri)? get,
  }) async {
    if (MarulasEvacuationSites.removedNames.any(
      (removed) => matchesPlaceSearch(removed, [query], ignoreAreaWords: true),
    ))
      return [];
    if (token.isEmpty) throw const MapboxPlaceSearchUnavailable();
    final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/forward', {
      'q': '$query ${area.searchSuffix}'.trim(),
      'access_token': token,
      'country': 'PH',
      'bbox': area.bbox,
      'proximity': '${area.longitude},${area.latitude}',
      'limit': '10',
    });
    try {
      final response = await (get ?? http.get)(
        uri,
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200)
        throw const MapboxPlaceSearchUnavailable();
      final data = jsonDecode(response.body);
      if (data is! Map || data['features'] is! List)
        throw const MapboxPlaceSearchUnavailable();
      final result = <String, MapboxPlace>{};
      for (final raw in (data['features'] as List).whereType<Map>()) {
        final p = raw['properties'];
        final geometry = raw['geometry'];
        if (p is! Map || geometry is! Map) continue;
        final c = geometry['coordinates'];
        final name = p['name'];
        if (name is! String ||
            name.trim().isEmpty ||
            c is! List ||
            c.length < 2 ||
            c[0] is! num ||
            c[1] is! num)
          continue;
        final lng = (c[0] as num).toDouble(), lat = (c[1] as num).toDouble();
        if (!lat.isFinite ||
            !lng.isFinite ||
            lat.abs() > 90 ||
            lng.abs() > 180 ||
            !isInScope(lat, lng))
          continue;
        if (MarulasEvacuationSites.removedNames.any(
          (removed) =>
              matchesPlaceSearch(removed, [name], ignoreAreaWords: true),
        ))
          continue;
        final poi = p['feature_type'] == 'poi';
        if (expectedNames.isNotEmpty &&
            (!poi ||
                !expectedNames.any(
                  (expected) => matchesPlaceSearch(expected, [
                    name,
                  ], ignoreAreaWords: true),
                )))
          continue;
        final id =
            p['mapbox_id']?.toString() ??
            raw['id']?.toString() ??
            '$name:$lat:$lng';
        final address =
            p['full_address']?.toString() ??
            p['place_formatted']?.toString() ??
            '';
        result.putIfAbsent(
          id,
          () => MapboxPlace(
            id: id,
            name: name.trim(),
            address: address,
            lat: lat,
            lng: lng,
            isPoi: poi,
          ),
        );
      }
      return result.values.toList();
    } catch (_) {
      throw const MapboxPlaceSearchUnavailable();
    }
  }
}
