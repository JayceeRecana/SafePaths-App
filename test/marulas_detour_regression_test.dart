import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/planned_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/marulas-serrano-detour.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final data = fixture['closure'];
  final road = RoadStatus(
    id: data['id'],
    name: data['name'],
    status: 'not_passable',
    notes: 'Controlled test closure',
    updatedAt: DateTime(2026, 11, 9),
    geometry: Map<String, dynamic>.from(data['geometry']),
    riskScore: 80,
    isVerified: true,
  );
  Position point(List p) => Position(p[0], p[1]);
  Future<List<PlannedRoute>> calculate({required bool allowTurnback}) async {
    var initial = true;
    return RoutingService.instance.computeRoutes(
      origin: point(fixture['origin']),
      destination: point(fixture['destination']),
      headingDegrees: 90,
      roadsOverride: [road],
      weatherStateOverride: WeatherState.clear,
      avoidRoadIds: {road.id},
      maxDetourCandidates: 3,
      directionsFetcher:
          (
            a,
            b, {
            waypoints = const [],
            vehicleType = 'Sedan',
            headingDeg,
          }) async {
            if (waypoints.isEmpty) {
              expect(initial, isTrue);
              initial = false;
              expect(headingDeg, 90);
              return [Map<String, dynamic>.from(fixture['direct'])];
            }
            final expected = fixture['westWaypoints'] as List;
            final west =
                waypoints.length == expected.length &&
                (waypoints.first.lng - expected.first[0]).abs() < 1e-6 &&
                (waypoints.first.lat - expected.first[1]).abs() < 1e-6;
            return [
              Map<String, dynamic>.from(
                allowTurnback && west && headingDeg == null
                    ? fixture['turnbackDetour']
                    : fixture['constrainedDetour'],
              ),
            ];
          },
    );
  }

  test(
    'Serrano closure detour can turn back toward MacArthur instead of retaining the forward bearing',
    () async {
      final routes = await calculate(allowTurnback: true);
      final clear = routes.where((r) => !r.isBlocked).toList();
      expect(
        clear,
        isNotEmpty,
        reason:
            'A valid MacArthur detour exists when the forward bearing is released.',
      );
      expect(clear.first.distanceMeters, fixture['turnbackDetour']['distance']);
      expect(
        clear.first.points.any((p) => p.lng < 120.9805),
        isTrue,
        reason: 'The accepted geometry goes west to the MacArthur corridor.',
      );
      for (final route in clear)
        expect(
          RoutingService.doesRouteCrossGeometry(route.points, road.geometry),
          isFalse,
        );
    },
  );
  test(
    'Relaxing the detour bearing never admits a route through the confirmed closure',
    () async {
      final routes = await calculate(allowTurnback: false);
      expect(routes, isNotEmpty);
      expect(routes.every((r) => r.isBlocked), isTrue);
    },
  );
}
