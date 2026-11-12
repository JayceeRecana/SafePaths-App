import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:safepaths_app/config/study_area.dart';
import 'package:safepaths_app/services/mapbox_place_search.dart';

Map<String, dynamic> feature(
  String name, {
  String type = 'poi',
  double lat = 14.675,
  double lng = 120.984,
}) => {
  'properties': {
    'name': name,
    'feature_type': type,
    'full_address': 'Marulas, Valenzuela',
    'mapbox_id': name,
  },
  'geometry': {
    'type': 'Point',
    'coordinates': [lng, lat],
  },
};
Future<List<MapboxPlace>> search(
  List<Map<String, dynamic>> rows, {
  List<String> names = const [],
}) => MapboxPlaceSearch.search(
  query: 'public place',
  token: 'pk.synthetic',
  area: StudyArea.marulas,
  expectedNames: names,
  isInScope: (lat, lng) =>
      lat > 14.66 && lat < 14.69 && lng > 120.96 && lng < 121,
  get: (uri) async {
    expect(uri.path, '/search/searchbox/v1/forward');
    expect(uri.queryParameters['country'], 'PH');
    expect(uri.queryParameters['bbox'], StudyArea.marulas.bbox);
    return http.Response(jsonEncode({'features': rows}), 200);
  },
);
void main() {
  test('removed-site queries never call the provider', () async {
    var calls = 0;
    final results = await MapboxPlaceSearch.search(
      query: 'Dona Ata Covered Court Marulas',
      token: 'pk.synthetic',
      area: StudyArea.marulas,
      isInScope: (_, __) => true,
      get: (_) async {
        calls++;
        return http.Response('{"features":[]}', 200);
      },
    );
    expect(results, isEmpty);
    expect(calls, 0);
  });
  test(
    'keeps named POIs and translates provider coordinate order accurately',
    () async {
      final results = await search(
        [feature('Serrano Elementary School')],
        names: ['Serrano Elementary School'],
      );
      expect(results.single.lat, 14.675);
      expect(results.single.lng, 120.984);
      expect(results.single.toFeatureMap()['center'], [120.984, 14.675]);
    },
  );
  test(
    'unrelated courts and broad address matches cannot stand in for a listed site',
    () async {
      expect(
        await search(
          [
            feature('Potrero Covered Court'),
            feature('Youngstown Village Covered Court'),
          ],
          names: ['Dona Ata Covered Court'],
        ),
        isEmpty,
      );
      expect(
        await search(
          [feature('Serrano Elementary School', type: 'street')],
          names: ['Serrano Elementary School'],
        ),
        isEmpty,
      );
    },
  );
  test('known official-name aliases still reject unrelated schools', () async {
    final results = await search(
      [
        feature('Capirpiriwan Elementary School'),
        feature('Marulas Central School'),
      ],
      names: ['Marulas Central Elementary School', 'Marulas Central School'],
    );
    expect(results.map((p) => p.name), ['Marulas Central School']);
  });
  test(
    'removed sites and out-of-area points are excluded from general searches',
    () async {
      expect(
        await search([
          feature('Dona Ata Covered Court'),
          feature('Outside School', lng: 122),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'provider failures do not become a fabricated no-match result or expose the token',
    () async {
      await expectLater(
        MapboxPlaceSearch.search(
          query: 'school',
          token: 'pk.private',
          area: StudyArea.marulas,
          isInScope: (_, __) => true,
          get: (_) async => http.Response('unavailable', 503),
        ),
        throwsA(isA<MapboxPlaceSearchUnavailable>()),
      );
      expect(
        const MapboxPlaceSearchUnavailable().toString(),
        isNot(contains('pk.private')),
      );
    },
  );
}
