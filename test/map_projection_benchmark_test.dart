import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/map_road_data.dart';
import 'package:safepaths_app/services/weather_service.dart';

void main() {
  test('repeatable host map-projection benchmark', () {
    final results = <Map<String, dynamic>>[];
    for (final count in [50, 200, 1000]) {
      final now = DateTime.now();
      final roads = List.generate(
        count,
        (i) => RoadStatus(
          id: 'r$i',
          name: 'Road $i',
          status: 'passable',
          notes: '',
          updatedAt: now,
          geometry: {
            'type': 'LineString',
            'coordinates': List.generate(
              40,
              (p) => [
                120.98 + i * 0.000001 + p * 0.00001,
                14.67 + i * 0.000001 + p * 0.00001,
              ],
            ),
          },
        ),
      );
      final cache = MapRoadData();
      final watch = Stopwatch()..start();
      cache.project(roads, WeatherState.clear, now: now);
      final cold = watch.elapsedMicroseconds;
      watch.reset();
      for (var i = 0; i < 100; i++) {
        cache.project(roads, WeatherState.clear, now: now);
      }
      final cached = watch.elapsedMicroseconds / 100;
      final freshGeometries = cache.geometryBuilds;
      expect(cache.dataBuilds, 1);
      expect(freshGeometries, count);
      // Empty a map repeatedly as screens are entered/left: removed roads must not accumulate.
      cache.project([], WeatherState.clear, now: now);
      expect(cache.retainedRoads, 0);
      results.add({
        'roads': count,
        'pointsPerRoad': 40,
        'coldProjectionMs': cold / 1000,
        'unchangedProjectionMeanMs': cached / 1000,
        'geometryBuildsDuring100UnchangedUpdates':
            cache.geometryBuilds - freshGeometries,
      });
    }
    final directory = Directory('.performance-results')
      ..createSync(recursive: true);
    File('${directory.path}/map-projection.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'hostOnly': true,
        'limitations':
            'Flutter test runner CPU measurements, not Android frame time, GPU, or production load.',
        'results': results,
      }),
    );
    // Only synthetic aggregate measurements are printed, never user data.
    // This opt-in test prints only synthetic benchmark aggregates.
    // ignore: avoid_print
    print(jsonEncode(results));
  }, skip: !const bool.fromEnvironment('RUN_PERFORMANCE_BENCHMARKS'));
}
