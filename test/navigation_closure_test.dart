import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';

RoadStatus closure(String id, double latitude) => RoadStatus(
  id: id,
  name: id,
  status: 'not_passable',
  notes: '',
  updatedAt: DateTime.now(),
  geometry: {
    'type': 'LineString',
    'coordinates': [
      [120.984, latitude],
      [120.986, latitude],
    ],
  },
);

PlannedRoute route(List<Position> points) => PlannedRoute(
  points: points,
  durationMin: 1,
  distanceMiles: 0.1,
  summary: '',
  hazardAlerts: [],
  safetyStatus: 'safe',
  steps: [],
);

void main() {
  test('Detects a flood crossing between sparse route vertices', () {
    expect(
      RoutingService.doesRouteCrossRoad(
        [Position(120.985, 14.674), Position(120.985, 14.678)],
        [Position(120.984, 14.676), Position(120.986, 14.676)],
      ),
      isTrue,
    );
  });

  test(
    'Detects a short closed segment inside a long parallel route segment',
    () {
      expect(
        RoutingService.doesRouteCrossRoad(
          [Position(120.980, 14.6761), Position(120.990, 14.6761)],
          [Position(120.984, 14.676), Position(120.986, 14.676)],
        ),
        isTrue,
      );
    },
  );

  test('Does not reject a parallel street outside the flood buffer', () {
    expect(
      RoutingService.doesRouteCrossRoad(
        [Position(120.980, 14.677), Position(120.990, 14.677)],
        [Position(120.984, 14.676), Position(120.986, 14.676)],
      ),
      isFalse,
    );
  });

  test(
    'Confirmed closure is detected even when predicted status was identical',
    () {
      final road = closure('a', 14.676);
      expect(
        RoutingService.findStatusChangedRoads(
          [road],
          {'a': 'not_passable'},
          WeatherState.typhoon,
          confirmedStatusCache: {'a': 'passable'},
        ),
        [road],
      );
    },
  );

  test(
    'First GPS check detects closures with no prior confirmed-status cache',
    () {
      final road = closure('a', 14.676);
      expect(
        RoutingService.findStatusChangedRoads(
          [road],
          {'a': 'not_passable'},
          WeatherState.clear,
          confirmedStatusCache: {},
        ),
        [road],
      );
    },
  );

  test('Rejects both flooded alternatives and keeps the third clear route', () {
    final a = route([Position(120.983, 14.676), Position(120.987, 14.676)]);
    final b = route([Position(120.983, 14.678), Position(120.987, 14.678)]);
    final clear = route([Position(120.983, 14.680), Position(120.987, 14.680)]);
    expect(
      RoutingService.routesAvoidingConfirmedClosures(
        [a, b, clear],
        [closure('a', 14.676), closure('b', 14.678)],
      ),
      [clear],
    );
  });

  test('Does not ignore a closure within the first 50 metres', () {
    final shortRoute = route([
      Position(120.9848, 14.676),
      Position(120.9852, 14.676),
    ]);
    expect(
      RoutingService.routesAvoidingConfirmedClosures(
        [shortRoute],
        [closure('a', 14.676)],
      ),
      isEmpty,
    );
  });

  test(
    'remaining-path display preserves geometry and cannot bypass full-route admission',
    () {
      final original = route([
        Position(120.980, 14.676),
        Position(120.990, 14.676),
      ]);
      final roads = [closure('Behind', 14.676)];
      final refreshed = RoutingService.instance.refreshRoute(
        original,
        roads: roads,
        weather: WeatherState.clear,
        evaluationPoints: [
          Position(120.988, 14.676),
          Position(120.990, 14.676),
        ],
      );
      expect(refreshed.isBlocked, isFalse);
      expect(refreshed.points, same(original.points));
      expect(refreshed.steps, same(original.steps));
      final admission = RoutingService.instance.navigationAdmission(
        refreshed,
        roads: roads,
        weather: WeatherState.clear,
        liveDataUnavailable: false,
      );
      expect(admission.route.canStartNavigation, isFalse);
      final invalid = RoutingService.instance.refreshRoute(
        original,
        roads: roads,
        weather: WeatherState.clear,
        evaluationPoints: [Position(double.nan, 14.676)],
      );
      expect(invalid.canStartNavigation, isFalse);
    },
  );
}
