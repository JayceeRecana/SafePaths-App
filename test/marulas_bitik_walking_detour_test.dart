import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final f = jsonDecode(
    File('test/fixtures/marulas-bitik-walking-detour.json').readAsStringSync(),
  );
  final data = f['closure'];
  final closure = RoadStatus(
    id: data['id'],
    name: data['name'],
    status: 'not_passable',
    notes: 'Captured virtual scenario only',
    updatedAt: DateTime.now(),
    geometry: Map<String, dynamic>.from(data['geometry']),
    riskScore: 80,
    isVerified: true,
  );
  final origin = Position(f['origin'][0], f['origin'][1]);
  final destination = Position(f['destination'][0], f['destination'][1]);

  for (final blockedCorridor in [false, true]) {
    test(
      blockedCorridor
          ? 'A corridor response crossing the closure remains blocked'
          : 'Bitik walking detour spans the corridor without exceeding six diversion requests',
      () async {
        final calls = <List<Position>>[];
        final routes = await RoutingService.instance.computeRoutes(
          origin: origin,
          destination: destination,
          vehicleType: 'Walking',
          headingDegrees: 90,
          roadsOverride: [closure],
          weatherStateOverride: WeatherState.clear,
          maxDetourCandidates: RoutingService.navigationDetourCandidateLimit,
          directionsFetcher:
              (
                a,
                b, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                expect(a.lng, origin.lng);
                expect(a.lat, origin.lat);
                expect(b.lng, destination.lng);
                expect(b.lat, destination.lat);
                expect(vehicleType, 'Walking');
                if (waypoints.isNotEmpty) expect(headingDeg, isNull);
                calls.add(List<Position>.from(waypoints));
                final match = (f['requests'] as List).firstWhere((x) {
                  final w = x['waypoints'] as List;
                  if (w.length != waypoints.length) return false;
                  for (var i = 0; i < w.length; i++) {
                    if ((w[i][0] - waypoints[i].lng).abs() > 1e-6 ||
                        (w[i][1] - waypoints[i].lat).abs() > 1e-6)
                      return false;
                  }
                  return true;
                });
                return List<Map<String, dynamic>>.from(
                  blockedCorridor && waypoints.length == 2
                      ? f['requests'][0]['routes']
                      : match['routes'],
                );
              },
        );
        final clear = RoutingService.routesAvoidingConfirmedClosures(routes, [
          closure,
        ]);
        if (blockedCorridor) {
          expect(clear, isEmpty);
          expect(routes.any(RoutingService.canAdoptAutomatically), isFalse);
        } else {
          expect(
            clear,
            isNotEmpty,
            reason:
                'Captured northern corridor avoids the closure but single-point sampling missed it',
          );
          expect(
            clear.any((r) => (r.distanceMeters! - 3542.038).abs() < .01),
            isTrue,
          );
        }
        expect(calls.where((w) => w.isNotEmpty), hasLength(6));
        expect(calls.where((w) => w.length == 2), hasLength(2));
        for (final route in clear) {
          expect(
            RoutingService.doesRouteCrossGeometry(
              route.points,
              closure.geometry,
            ),
            isFalse,
          );
          expect(route.requestedDestination!.lng, destination.lng);
          expect(route.requestedDestination!.lat, destination.lat);
        }
      },
    );
  }
}
