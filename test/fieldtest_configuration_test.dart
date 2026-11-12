import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/config/study_area.dart';
import 'package:safepaths_app/services/navigation_diagnostics.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/test_road_import.dart';
import 'package:safepaths_app/utils/geo_utils.dart';

void main() {
  test(
    'Environment defaults to production and rejects contradictory builds',
    () {
      expect(AppEnvironment.resolve(null, ''), 'production');
      expect(AppEnvironment.resolve('fieldtest', ''), 'fieldtest');
      expect(
        () => AppEnvironment.resolve('fieldtest', 'production'),
        throwsStateError,
      );
      expect(() => AppEnvironment.resolve('unknown', ''), throwsStateError);
    },
  );

  test(
    'Test Firebase configuration fails closed for missing or production projects',
    () {
      void validate(Map<String, String> env, String actual) =>
          AppEnvironment.validateTestConfiguration(
            env: env,
            actualProjectId: actual,
            productionProjectId: 'production-project',
          );
      expect(() => validate({}, 'production-project'), throwsStateError);
      expect(
        () => validate({
          'FIELDTEST_FIREBASE_PROJECT_ID': 'production-project',
          'MAPBOX_ACCESS_TOKEN': 'pk.test',
        }, 'production-project'),
        throwsStateError,
      );
      final env = {
        'FIELDTEST_FIREBASE_PROJECT_ID': 'test-project',
        'MAPBOX_ACCESS_TOKEN': 'pk.test',
      };
      expect(() => validate(env, 'different-project'), throwsStateError);
      expect(
        () => validate({...env, 'FCM_PRIVATE_KEY': 'secret'}, 'test-project'),
        throwsStateError,
      );
      expect(() => validate(env, 'test-project'), returnsNormally);
    },
  );

  test(
    'Selected area, restrictions, landmarks and facilities match the build',
    () {
      final area = AppEnvironment.area;
      expect(GeoUtils.isInsideStudyArea(area.latitude, area.longitude), isTrue);
      expect(
        GeoUtils.isInsideStudyArea(area.north + 0.01, area.longitude),
        isFalse,
      );
      expect(
        GeoUtils.isInsideStudyArea(area.latitude, area.east + 0.01),
        isFalse,
      );
      if (AppEnvironment.isFieldTest) {
        expect(area, StudyArea.fieldtest);
        expect(area.latitude, 14.676139);
        expect(area.longitude, 121.009417);
        expect(area.landmarks, isEmpty);
        expect(area.stagingFacilities, isEmpty);
        expect(AppEnvironment.uploadsEnabled, isFalse);
        expect(AppEnvironment.pushEnabled, isFalse);
        expect(AppEnvironment.envAsset, '.env.fieldtest');
        expect(GeoUtils.isInsideStudyArea(14.6761, 120.9842), isFalse);
      } else {
        expect(area, StudyArea.marulas);
        expect(area.landmarks, isNotEmpty);
        expect(area.stagingFacilities, isEmpty); // Await beneficiary approval.
        expect(GeoUtils.isInsideStudyArea(14.676139, 121.009417), isFalse);
      }
    },
  );

  test(
    'Planning never substitutes a camera center for missing GPS in either flavor',
    () async {
      final service = RoutingService.instance;
      service.originPoint = null;
      service.destinationPoint = AppEnvironment.isFieldTest
          ? Position(121.011, 14.679)
          : null;
      await service.calculateRoute();
      expect(service.originPoint, isNull);
      expect(service.routes, isEmpty);
      expect(service.routeErrorMessage, contains('real GPS'));
      service.exitPlanning();
      service.originPoint = null;
    },
  );

  test(
    'OSM import keeps identical names and unnamed roads under stable IDs',
    () {
      Map<String, Object> way(int id, {String? name, String? access}) => {
        'type': 'way',
        'id': id,
        'tags': {
          'highway': 'residential',
          if (name != null) 'name': name,
          if (access != null) 'access': access,
        },
        'geometry': [
          {'lat': 14.676, 'lon': 121.009},
          {'lat': 14.677, 'lon': 121.009},
        ],
      };
      final parsed = TestRoadImport.parse([
        way(1, name: 'Main'),
        way(2, name: 'Main'),
        way(3),
        way(3),
        way(4, access: 'private'),
      ]);
      expect(parsed.map((r) => r.id), ['osm_way_1', 'osm_way_2', 'osm_way_3']);
      expect(parsed.last.name, contains('Unnamed'));
      expect(
        TestRoadImport.query(StudyArea.fieldtest),
        contains('14.667156,121.000131,14.685122,121.018703'),
      );
    },
  );

  for (final geometry in [
    {
      'type': 'MultiLineString',
      'coordinates': [
        [
          [121.0, 14.67],
          [121.001, 14.67],
        ],
        [
          [121.009, 14.67],
          [121.010, 14.67],
        ],
      ],
    },
    {
      'type': 'MultiLineString',
      'segments': [
        {
          'points': [
            {'lng': 121.0, 'lat': 14.67},
            {'lng': 121.001, 'lat': 14.67},
          ],
        },
        {
          'points': [
            {'lng': 121.009, 'lat': 14.67},
            {'lng': 121.010, 'lat': 14.67},
          ],
        },
      ],
    },
  ]) {
    test(
      'Disconnected ${geometry.containsKey('segments') ? 'Firestore' : 'GeoJSON'} ways do not create a phantom barrier',
      () {
        expect(GeoUtils.extractSegments(geometry), hasLength(2));
        expect(
          RoutingService.doesRouteCrossGeometry([
            Position(121.005, 14.669),
            Position(121.005, 14.671),
          ], geometry),
          isFalse,
        );
        expect(
          RoutingService.doesRouteCrossGeometry([
            Position(121.0005, 14.669),
            Position(121.0005, 14.671),
          ], geometry),
          isTrue,
        );
      },
    );
  }

  test('Diagnostics export only allowed fields and cap log size', () {
    final log = NavigationDiagnostics(now: () => DateTime.utc(2026));
    log.record('gps', {
      'accuracyMeters': 5,
      'apiKey': 'SECRET',
      'password': 'SECRET',
    });
    expect(log.exportJson(), contains('accuracyMeters'));
    expect(log.exportJson(), isNot(contains('SECRET')));
    for (int i = 0; i < 2001; i++) {
      log.record('gps', {'accuracyMeters': i});
    }
    expect(RegExp('"event"').allMatches(log.exportJson()).length, 2000);
    log.dispose();
  });
}
