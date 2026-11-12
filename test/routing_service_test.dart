import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/models/planned_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to create RoadStatus test objects
  RoadStatus createTestRoad({
    required String id,
    required String name,
    required List<Position> points,
    String status = 'passable',
    String notes = '',
    double riskScore = 0.0,
    String vulnerability = 'low',
    DateTime? updatedAt,
  }) {
    return RoadStatus(
      id: id,
      name: name,
      status: status,
      notes: notes,
      riskScore: riskScore,
      vulnerability: vulnerability,
      updatedAt: updatedAt ?? DateTime.now(),
      geometry: {
        'type': 'LineString',
        'coordinates': points
            .map((p) => [p.lng.toDouble(), p.lat.toDouble()])
            .toList(),
      },
    );
  }

  group('RoutingService.doesRouteCrossRoad Characterization Tests', () {
    // Reference base coordinates around Marulas, Valenzuela: (120.9840, 14.6760)
    // 0.0001 deg lat is approx 11.1 meters
    // 0.0001 deg lng is approx 10.7 meters

    final roadSegment = [
      Position(120.9840, 14.6760),
      Position(120.9860, 14.6760),
    ];

    test('Route point exactly on the road segment returns true', () {
      final routePts = [Position(120.9850, 14.6760)];
      expect(RoutingService.doesRouteCrossRoad(routePts, roadSegment), isTrue);
    });

    test('Route point within 35m buffer (~15m away) returns true', () {
      // 0.00013 deg lat ~ 14.4 meters north
      final routePts = [Position(120.9850, 14.67613)];
      expect(RoutingService.doesRouteCrossRoad(routePts, roadSegment), isTrue);
    });

    test('Route point outside 35m buffer (~55m away) returns false', () {
      // 0.0005 deg lat ~ 55.5 meters north
      final routePts = [Position(120.9850, 14.67650)];
      expect(RoutingService.doesRouteCrossRoad(routePts, roadSegment), isFalse);
    });

    test(
      'Route crossing perpendicularly across road segment mid-point returns true',
      () {
        final routePts = [
          Position(120.9850, 14.6750), // 110m south
          Position(120.9850, 14.6759), // ~11m south (inside 35m buffer)
          Position(120.9850, 14.6770), // 110m north
        ];
        expect(
          RoutingService.doesRouteCrossRoad(routePts, roadSegment),
          isTrue,
        );
      },
    );

    test('Empty route or road with < 2 points returns false', () {
      expect(RoutingService.doesRouteCrossRoad([], roadSegment), isFalse);
      expect(
        RoutingService.doesRouteCrossRoad([Position(120.9850, 14.6760)], []),
        isFalse,
      );
      expect(
        RoutingService.doesRouteCrossRoad(
          [Position(120.9850, 14.6760)],
          [Position(120.9840, 14.6760)],
        ),
        isFalse,
      );
    });

    test('Custom threshold parameter is respected', () {
      // Point is ~38.8m away (0.00035 deg lat north) - inside bbox prefilter (0.0004)
      final routePts = [Position(120.9850, 14.67635)];
      // Default 35m buffer rejects it (38.8m > 35m)
      expect(
        RoutingService.doesRouteCrossRoad(
          routePts,
          roadSegment,
          thresholdMeters: 35.0,
        ),
        isFalse,
      );
      // Expanded 45m buffer accepts it (38.8m < 45m)
      expect(
        RoutingService.doesRouteCrossRoad(
          routePts,
          roadSegment,
          thresholdMeters: 45.0,
        ),
        isTrue,
      );
    });
  });

  group('RoutingService.evaluateRouteSafety Characterization Tests', () {
    final routingService = RoutingService.instance;

    final sampleRoute = [
      Position(120.9840, 14.6760),
      Position(120.9850, 14.6760),
      Position(120.9860, 14.6760),
    ];

    test('Empty route returns safe default status', () {
      final res = routingService.evaluateRouteSafety(
        [],
        [],
        'Sedan',
        weatherState: WeatherState.clear,
      );
      expect(res['status'], equals('safe'));
      expect(res['isBlocked'], isFalse);
      expect(res['hazardAlerts'], isEmpty);
      expect(res['crossedRoads'], isEmpty);
      expect(res['maxRisk'], equals(0.0));
      expect(res['totalRisk'], equals(0.0));
    });

    test('Route crossing no hazardous roads returns safe', () {
      final safeRoad = createTestRoad(
        id: 'road_1',
        name: 'Safe Street',
        points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
        status: 'passable',
        riskScore: 0.0,
      );

      final res = routingService.evaluateRouteSafety(
        sampleRoute,
        [safeRoad],
        'Sedan',
        weatherState: WeatherState.clear,
      );
      expect(res['status'], equals('safe'));
      expect(res['isBlocked'], isFalse);
      expect(res['hazardAlerts'], isEmpty);
      expect(res['crossedRoads'], isEmpty);
    });

    test(
      'Route crossing not_passable road sets status to critical and isBlocked to true',
      () {
        final floodedRoad = createTestRoad(
          id: 'flooded_road_1',
          name: 'Flooded Highway',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 75.0,
        );

        final res = routingService.evaluateRouteSafety(
          sampleRoute,
          [floodedRoad],
          'Sedan',
          weatherState: WeatherState.clear,
        );
        expect(res['status'], equals('critical'));
        expect(res['isBlocked'], isTrue);
        expect(res['hazardAlerts'], contains('Flooded Highway'));
        expect(res['highestRiskSegmentId'], equals('flooded_road_1'));
        expect(res['maxRisk'], equals(75.0));

        final crossed = res['crossedRoads'] as List<Map<String, dynamic>>;
        expect(crossed.length, equals(1));
        expect(crossed.first['id'], equals('flooded_road_1'));
        expect(crossed.first['name'], equals('Flooded Highway'));
        expect(crossed.first['cat'], equals('Critical Risk'));
      },
    );

    test(
      'Route crossing high predicted risk (>= 80) triggers critical even if status is passable',
      () {
        final highRiskRoad = createTestRoad(
          id: 'risk_road_1',
          name: 'High Risk Boulevard',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 85.0,
        );

        final res = routingService.evaluateRouteSafety(
          sampleRoute,
          [highRiskRoad],
          'Sedan',
          weatherState: WeatherState.clear,
        );
        expect(res['status'], equals('critical'));
        // Note: isBlocked is only true if effective status is not_passable
        expect(res['isBlocked'], isFalse);
        expect(res['hazardAlerts'], contains('High Risk Boulevard'));
        expect(res['maxRisk'], equals(85.0));
      },
    );

    test(
      'Route crossing partial road evaluates to partial for Sedan but passable_partial for SUV',
      () {
        final partialRoad = createTestRoad(
          id: 'partial_road_1',
          name: 'Puddle Lane',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'partial',
          riskScore: 40.0,
        );

        // For Sedan: partial
        final sedanRes = routingService.evaluateRouteSafety(
          sampleRoute,
          [partialRoad],
          'Sedan',
          weatherState: WeatherState.clear,
        );
        expect(sedanRes['status'], equals('partial'));
        expect(sedanRes['isBlocked'], isFalse);
        expect(sedanRes['hazardAlerts'], contains('Puddle Lane'));

        // For SUV / Pickup: passable_partial
        final suvRes = routingService.evaluateRouteSafety(
          sampleRoute,
          [partialRoad],
          'SUV / Pickup',
          weatherState: WeatherState.clear,
        );
        expect(suvRes['status'], equals('passable_partial'));
        expect(suvRes['isBlocked'], isFalse);
        expect(
          suvRes['hazardAlerts'],
          contains('Puddle Lane (High Clearance)'),
        );
      },
    );

    test(
      'Severe weather with stale road evaluates to unverified_risk without hard isBlocked',
      () {
        // Stale road: updated 5 hours ago (high vuln stale threshold is 0.5 hours in severe weather)
        final staleRoad = createTestRoad(
          id: 'stale_road_1',
          name: 'Lowland Alley',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 0.0,
          vulnerability: 'high',
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        );

        final res = routingService.evaluateRouteSafety(
          sampleRoute,
          [staleRoad],
          'Sedan',
          weatherState: WeatherState.heavyRain,
        );
        expect(res['status'], equals('unverified_risk'));
        expect(res['isBlocked'], isFalse);
        expect(res['unconfirmedCount'], equals(1));
        expect(res['totalRisk'], equals(0.0));
        expect(res['averageRisk'], equals(0.0));
        expect(
          res['hazardAlerts'],
          contains('Lowland Alley (Unverified Risk)'),
        );
      },
    );

    test(
      'averageRisk of a route is unchanged by adding stale unconfirmed roads to it',
      () {
        final hazardRoad = createTestRoad(
          id: 'hazard_1',
          name: 'Hazard Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'partial',
          riskScore: 50.0,
          vulnerability: 'low',
          updatedAt: DateTime.now(),
        );

        final staleRoad = createTestRoad(
          id: 'stale_road_2',
          name: 'Stale Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 0.0,
          vulnerability: 'high',
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        );

        // Route with only hazardRoad
        final resWithoutStale = routingService.evaluateRouteSafety(
          sampleRoute,
          [hazardRoad],
          'Sedan',
          weatherState: WeatherState.heavyRain,
        );
        expect(resWithoutStale['averageRisk'], equals(50.0));

        // Route with hazardRoad AND staleRoad
        final resWithStale = routingService.evaluateRouteSafety(
          sampleRoute,
          [hazardRoad, staleRoad],
          'Sedan',
          weatherState: WeatherState.heavyRain,
        );
        expect(resWithStale['averageRisk'], equals(50.0)); // Unchanged!
        expect(resWithStale['unconfirmedCount'], equals(1));
      },
    );

    test(
      'Route crossing road with moderate predicted risk (risk 45.0, passable) records alert and risk metrics',
      () {
        final predictedRoad = createTestRoad(
          id: 'pred_road_1',
          name: 'Moderate Ave',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 45.0,
          vulnerability: 'low',
          updatedAt: DateTime.now(),
        );

        final res = routingService.evaluateRouteSafety(
          sampleRoute,
          [predictedRoad],
          'Sedan',
          weatherState: WeatherState.clear,
        );
        expect(res['status'], equals('safe'));
        expect(res['isBlocked'], isFalse);
        expect(res['hazardAlerts'], contains('Moderate Ave (Predicted Risk)'));
        expect(res['maxRisk'], equals(45.0));
        expect(res['averageRisk'], equals(45.0));
        expect(res['totalRisk'], equals(45.0));

        final crossed = res['crossedRoads'] as List<Map<String, dynamic>>;
        expect(crossed.length, equals(1));
        expect(crossed.first['id'], equals('pred_road_1'));
        expect(crossed.first['cat'], equals('Predicted Watch'));
      },
    );
  });

  // ─── Polyline Encoder Helper for Unit Tests ──────────────────────────────
  String encodePolyline(List<Position> points) {
    final buffer = StringBuffer();
    int prevLat = 0;
    int prevLng = 0;

    void encodeValue(int val) {
      int v = val < 0 ? ~(val << 1) : (val << 1);
      while (v >= 0x20) {
        buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
        v >>= 5;
      }
      buffer.writeCharCode(v + 63);
    }

    for (final p in points) {
      int lat = (p.lat * 1e5).round();
      int lng = (p.lng * 1e5).round();
      encodeValue(lat - prevLat);
      encodeValue(lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
  }

  Map<String, dynamic> createMockMapboxRoute({
    required List<Position> points,
    double distance = 1000.0,
    double duration = 300.0,
  }) {
    return {
      'geometry': encodePolyline(points),
      'distance': distance,
      'duration': duration,
      'legs': [
        {
          'steps': [
            {
              'distance': distance,
              'maneuver': {
                'type': 'depart',
                'instruction': 'Head toward destination',
                'location': [
                  points.first.lng.toDouble(),
                  points.first.lat.toDouble(),
                ],
              },
            },
            {
              'distance': 0.0,
              'maneuver': {
                'type': 'arrive',
                'instruction': 'Arrive at destination',
                'location': [
                  points.last.lng.toDouble(),
                  points.last.lat.toDouble(),
                ],
              },
            },
          ],
        },
      ],
    };
  }

  group('RoutingService.computeRoutes Orchestration Tests', () {
    final routingService = RoutingService.instance;
    final origin = Position(120.9800, 14.6760);
    final destination = Position(120.9900, 14.6760);

    test(
      'provider time and bearings survive parsing and safety re-evaluation',
      () async {
        final raw = createMockMapboxRoute(
          points: [origin, destination],
          duration: 210,
        );
        final step = raw['legs'][0]['steps'][0] as Map<String, dynamic>;
        step['duration'] = 210.0;
        step['maneuver']['bearing_before'] = -90;
        step['maneuver']['bearing_after'] = 450;
        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: false,
          roadsOverride: [],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                a,
                b, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async => [raw],
        );
        final route = routes.single.copyWith(summary: 'Updated');
        expect(route.durationSeconds, 210);
        expect(route.steps.first.durationSeconds, 210);
        expect(route.steps.first.bearingBefore, 270);
        expect(route.steps.first.bearingAfter, 90);
      },
    );

    test(
      'invalid optional step timing and bearings use honest fallback metadata',
      () async {
        final raw = createMockMapboxRoute(points: [origin, destination]);
        final step = raw['legs'][0]['steps'][0] as Map<String, dynamic>;
        step['duration'] = -1;
        step['maneuver']['bearing_before'] = double.nan;
        step['maneuver']['bearing_after'] = 'unknown';
        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: false,
          roadsOverride: [],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                a,
                b, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async => [raw],
        );
        expect(routes.single.steps.first.durationSeconds, isNull);
        expect(routes.single.steps.first.bearingBefore, isNull);
        expect(routes.single.steps.first.bearingAfter, isNull);
      },
    );

    test(
      'Direct route calculation sorts by cost formula (dist + avgRisk*10 + maxRisk*50)',
      () async {
        // Direct Route A: 1200m, completely clear -> Cost = 1200
        final pathClear = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6800), // Bypasses south road
          Position(120.9900, 14.6760),
        ];
        // Direct Route B: 800m, but crosses a road with risk 30 -> Cost = 800 + (30*10) + (30*50) = 2600
        final pathRisky = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // Crosses south road
          Position(120.9900, 14.6760),
        ];

        final riskyRoad = createTestRoad(
          id: 'road_risk_30',
          name: 'Watch Street',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 30.0,
        );

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          roadsOverride: [riskyRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: pathRisky,
                    distance: 800.0,
                    duration: 180.0,
                  ),
                  createMockMapboxRoute(
                    points: pathClear,
                    distance: 1200.0,
                    duration: 240.0,
                  ),
                ];
              },
        );

        expect(routes.length, equals(2));
        // pathClear should be sorted 1st because Cost 1200 < Cost 2600
        expect(
          routes[0].distanceMiles,
          equals(double.parse((1200 / 1609.34).toStringAsFixed(1))),
        );
        expect(routes[0].routeCost, equals(1200.0));
        expect(routes[0].safetyScore, equals(100));
        expect(routes[0].summary, equals('Safest Route'));

        // pathRisky should be 2nd
        expect(routes[1].routeCost, equals(2600.0));
        expect(
          routes[1].hazardAlerts,
          contains('Watch Street (Predicted Risk)'),
        );
      },
    );

    test(
      'avoidRoadIds applies +20,000 penalty per crossed avoided road and reranks route',
      () async {
        // Route 1: 500m, crosses 'road_avoid_me'
        final path1 = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];
        // Route 2: 1500m, clear
        final path2 = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6850),
          Position(120.9900, 14.6760),
        ];

        final avoidedRoad = createTestRoad(
          id: 'road_avoid_me',
          name: 'Avoided Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'partial',
          riskScore: 30.0,
        );

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          avoidRoadIds: {'road_avoid_me'},
          roadsOverride: [avoidedRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: path1,
                    distance: 500.0,
                    duration: 100.0,
                  ),
                  createMockMapboxRoute(
                    points: path2,
                    distance: 1500.0,
                    duration: 300.0,
                  ),
                ];
              },
        );

        expect(routes.length, equals(2));
        // path2 (cost 1500) must beat path1 (cost 500 + 30*10 + 30*50 + 20000 = 22300)
        expect(routes[0].routeCost, equals(1500.0));
        expect(routes[1].routeCost, equals(22300.0));
      },
    );

    test(
      'Critical direct route triggers detour generator and returns safe detour when allowDetourGeneration is true',
      () async {
        final directCriticalPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // Hits impassable road
          Position(120.9900, 14.6760),
        ];

        final detourSafePath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6850), // Goes north around flood
          Position(120.9900, 14.6760),
        ];

        final floodedRoad = createTestRoad(
          id: 'flood_center',
          name: 'Flooded Center',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 90.0,
        );

        int fetchCallsWithWaypoints = 0;

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: true,
          roadsOverride: [floodedRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                if (waypoints.isEmpty) {
                  // Direct route: returns the flooded path
                  return [
                    createMockMapboxRoute(
                      points: directCriticalPath,
                      distance: 1000.0,
                      duration: 200.0,
                    ),
                  ];
                } else {
                  // Detour candidate
                  fetchCallsWithWaypoints++;
                  return [
                    createMockMapboxRoute(
                      points: detourSafePath,
                      distance: 1400.0,
                      duration: 280.0,
                    ),
                  ];
                }
              },
        );

        expect(fetchCallsWithWaypoints, greaterThan(0));
        expect(routes.isNotEmpty, isTrue);

        final bestRoute = routes.first;
        expect(bestRoute.safetyStatus, equals('safe'));
        expect(bestRoute.summary, equals('Safe Detour (Auto-Generated)'));
        expect(bestRoute.isBlocked, isFalse);
        expect(bestRoute.routeCost, equals(1400.0));
      },
    );

    test(
      'Critical direct route does NOT call detour generator when allowDetourGeneration is false',
      () async {
        final directCriticalPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];

        final floodedRoad = createTestRoad(
          id: 'flood_center',
          name: 'Flooded Center',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 90.0,
        );

        int waypointCalls = 0;

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: false,
          roadsOverride: [floodedRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                if (waypoints.isNotEmpty) waypointCalls++;
                return [
                  createMockMapboxRoute(
                    points: directCriticalPath,
                    distance: 1000.0,
                    duration: 200.0,
                  ),
                ];
              },
        );

        expect(waypointCalls, equals(0));
        expect(routes.length, equals(1));
        expect(routes.first.safetyStatus, equals('critical'));
        expect(routes.first.isBlocked, equals(true));
        expect(routes.first.summary, equals('Caution: Flooded Segment Ahead'));
      },
    );

    test(
      'Cross-hazard validation downgrades safe detour crossing secondary hazardous road to partial with +5000 penalty',
      () async {
        final directCriticalPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];

        // Detour avoids primary flood at lat 14.6760, but crosses secondary hazard at lat 14.6850
        final detourCrossingSecondary = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6850),
          Position(120.9900, 14.6760),
        ];

        final primaryFlood = createTestRoad(
          id: 'primary_flood',
          name: 'Main Canal Flood',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 95.0,
        );

        final secondaryHazard = createTestRoad(
          id: 'secondary_hazard',
          name: 'Secondary Hazardous Road',
          points: [Position(120.9840, 14.6850), Position(120.9860, 14.6850)],
          status: 'passable',
          riskScore: 65.0, // Hazardous road (>= 60.0)
        );

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: true,
          roadsOverride: [primaryFlood, secondaryHazard],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                if (waypoints.isEmpty) {
                  return [
                    createMockMapboxRoute(
                      points: directCriticalPath,
                      distance: 1000.0,
                      duration: 200.0,
                    ),
                  ];
                } else {
                  return [
                    createMockMapboxRoute(
                      points: detourCrossingSecondary,
                      distance: 1300.0,
                      duration: 260.0,
                    ),
                  ];
                }
              },
        );

        expect(routes.isNotEmpty, isTrue);
        final bestDetour = routes.first;
        // Should be downgraded to partial due to secondary hazard crossing
        expect(bestDetour.safetyStatus, equals('partial'));
        expect(bestDetour.summary, equals('Detour (Partial Risk Remains)'));
        // Cost: 1300 + (65*10) + (65*50) + 5000 (cross-hazard penalty) = 1300 + 650 + 3250 + 5000 = 10200
        expect(bestDetour.routeCost, equals(10200.0));
        expect(bestDetour.safetyScore, lessThanOrEqualTo(70));
      },
    );

    test(
      'Vehicle type clearance allows SUV to remain passable_partial on partial flood without critical status',
      () async {
        final pathThroughPuddle = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];

        final partialRoad = createTestRoad(
          id: 'puddle_road',
          name: 'Puddle Ave',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'partial',
          riskScore: 40.0,
        );

        // 1. Sedan evaluates as partial
        final sedanRoutes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          vehicleType: 'Sedan',
          roadsOverride: [partialRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: pathThroughPuddle,
                    distance: 1000.0,
                    duration: 200.0,
                  ),
                ];
              },
        );
        expect(sedanRoutes.first.safetyStatus, equals('partial'));

        // 2. SUV evaluates as passable_partial
        final suvRoutes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          vehicleType: 'SUV / Pickup',
          roadsOverride: [partialRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: pathThroughPuddle,
                    distance: 1000.0,
                    duration: 200.0,
                  ),
                ];
              },
        );
        expect(suvRoutes.first.safetyStatus, equals('passable_partial'));
        expect(
          suvRoutes.first.hazardAlerts,
          contains('Puddle Ave (High Clearance)'),
        );
      },
    );

    test(
      'avoidRoadIds triggers detour generation even when route status is safe/partial',
      () async {
        final roadToAvoid = createTestRoad(
          id: 'stale_road_1',
          name: 'Stale Road 1',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 20.0,
        );

        final directPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses stale_road_1
          Position(120.9900, 14.6760),
        ];

        final cleanDetourPath = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
          Position(120.9900, 14.6850),
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          avoidRoadIds: {'stale_road_1'},
          allowDetourGeneration: true,
          roadsOverride: [roadToAvoid],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                if (waypoints.isEmpty) {
                  return [
                    createMockMapboxRoute(
                      points: directPath,
                      distance: 1000.0,
                      duration: 200.0,
                    ),
                  ];
                } else {
                  return [
                    createMockMapboxRoute(
                      points: cleanDetourPath,
                      distance: 1200.0,
                      duration: 240.0,
                    ),
                  ];
                }
              },
        );

        expect(routes.isNotEmpty, isTrue);
        // The clean detour avoiding stale_road_1 should be selected as the best route
        expect(routes.first.summary, equals('Safe Detour (Auto-Generated)'));
        expect(routes.first.hazardAlerts, isEmpty);
      },
    );

    test(
      'isBlocked distinguishes physical closure from high predicted risk',
      () {
        final highPredictedRiskRoad = createTestRoad(
          id: 'predicted_high_risk',
          name: 'Predicted Risk Blvd',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 85.0, // High predicted risk >= 80
        );

        final impassableRoad = createTestRoad(
          id: 'closed_road',
          name: 'Closed Ave',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        final path = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];

        final evalPredicted = routingService.evaluateRouteSafety(path, [
          highPredictedRiskRoad,
        ], 'Sedan');
        expect(evalPredicted['status'], equals('critical'));
        expect(evalPredicted['isBlocked'], isFalse); // NOT physically closed

        final evalImpassable = routingService.evaluateRouteSafety(path, [
          impassableRoad,
        ], 'Sedan');
        expect(evalImpassable['status'], equals('critical'));
        expect(evalImpassable['isBlocked'], isTrue); // Physically closed
      },
    );

    test(
      'findNearestReachableStagingFacility selects reachable facility over closer blocked facility',
      () async {
        final floodBarrier = createTestRoad(
          id: 'barrier_road',
          name: 'Flood Barrier Rd',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        // Facility A is physically closer but crosses the impassable barrier
        // Facility B is slightly further but is clean and unblocked
        final testFacilities = [
          {'name': 'Facility A (Blocked)', 'lat': 14.6760, 'lng': 120.9880},
          {'name': 'Facility B (Reachable)', 'lat': 14.6850, 'lng': 120.9800},
        ];

        final directToBlocked = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses barrier_road
          Position(120.9880, 14.6760),
        ];

        final directToReachable = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              roadsOverride: [floodBarrier],
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    if (dest.lat == 14.6760) {
                      return [
                        createMockMapboxRoute(
                          points: directToBlocked,
                          distance: 800.0,
                          duration: 120.0,
                        ),
                      ];
                    } else {
                      return [
                        createMockMapboxRoute(
                          points: directToReachable,
                          distance: 1000.0,
                          duration: 150.0,
                        ),
                      ];
                    }
                  },
            );

        expect(selected, isNotNull);
        expect(selected!['name'], equals('Facility B (Reachable)'));
        expect((selected['reachableRoute'] as PlannedRoute).isBlocked, isFalse);
      },
    );

    test(
      'Stale high-vulnerability road in heavy rain: isBlocked false, status unverified_risk, costs +1500, summarized as Best Available (Unverified)',
      () async {
        final staleRoad = createTestRoad(
          id: 'stale_road_marulas',
          name: 'Stale Marulas Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 0.0,
          vulnerability: 'high',
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        );

        final routePts = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses staleRoad
          Position(120.9900, 14.6760),
        ];

        // 1. Without stale road (clean weather)
        final cleanRoutes = await routingService.computeRoutes(
          origin: Position(120.9800, 14.6760),
          destination: Position(120.9900, 14.6760),
          allowDetourGeneration: false,
          roadsOverride: [staleRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: routePts,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                ];
              },
        );

        expect(cleanRoutes.first.safetyStatus, equals('safe'));
        expect(cleanRoutes.first.summary, equals('Safest Route'));

        // 2. In heavy rain (stale high-vulnerability road becomes unconfirmed)
        final staleRoutes = await routingService.computeRoutes(
          origin: Position(120.9800, 14.6760),
          destination: Position(120.9900, 14.6760),
          allowDetourGeneration: false,
          roadsOverride: [staleRoad],
          weatherStateOverride: WeatherState.heavyRain,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: routePts,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                ];
              },
        );

        expect(staleRoutes.first.isBlocked, isFalse);
        expect(staleRoutes.first.safetyStatus, equals('unverified_risk'));
        // Route with unverified roads must NEVER be summarized as "Safest Route"
        expect(
          staleRoutes.first.summary,
          equals('Best Available (Unverified)'),
        );
        expect(staleRoutes.first.summary, isNot(equals('Safest Route')));

        // 3. Compare costs between clean and stale
        // With 2 alternatives of same distance (1000m): Route A crosses stale road (+1500 cost = 2500), Route B avoids it (1000 cost)
        final altPath = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6800),
          Position(120.9900, 14.6760),
        ];

        final rankedRoutes = await routingService.computeRoutes(
          origin: Position(120.9800, 14.6760),
          destination: Position(120.9900, 14.6760),
          allowDetourGeneration: false,
          roadsOverride: [staleRoad],
          weatherStateOverride: WeatherState.heavyRain,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: routePts,
                    distance: 1000.0,
                    duration: 120.0,
                  ), // crosses stale road
                  createMockMapboxRoute(
                    points: altPath,
                    distance: 1000.0,
                    duration: 120.0,
                  ), // clean route
                ];
              },
        );

        // Clean route (cost 1000) ranks before stale route (cost 1000 + 1500 = 2500)
        expect(rankedRoutes.first.safetyStatus, equals('safe'));
        expect(rankedRoutes.last.safetyStatus, equals('unverified_risk'));

        // 4. Same road with stored status 'not_passable' isBlocked == true, status 'critical'
        final closedRoad = createTestRoad(
          id: 'stale_road_marulas',
          name: 'Stale Marulas Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 0.0,
        );

        final closedRoutes = await routingService.computeRoutes(
          origin: Position(120.9800, 14.6760),
          destination: Position(120.9900, 14.6760),
          allowDetourGeneration: false,
          roadsOverride: [closedRoad],
          weatherStateOverride: WeatherState.heavyRain,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: routePts,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                ];
              },
        );

        expect(closedRoutes.first.isBlocked, isTrue);
        expect(closedRoutes.first.safetyStatus, equals('critical'));
      },
    );

    test(
      'Detours are NOT requested when one Mapbox alternative is non-critical and no avoid roads are crossed',
      () async {
        int fetcherCallCount = 0;

        final criticalRoad = createTestRoad(
          id: 'critical_road',
          name: 'Critical Flooded Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        final route1Critical = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses criticalRoad
          Position(120.9900, 14.6760),
        ];

        final route2Safe = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850), // clean path
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: true,
          roadsOverride: [criticalRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                fetcherCallCount++;
                return [
                  createMockMapboxRoute(
                    points: route1Critical,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                  createMockMapboxRoute(
                    points: route2Safe,
                    distance: 1200.0,
                    duration: 150.0,
                  ),
                ];
              },
        );

        // Fetcher should have been called ONLY once for the initial request — no detour fetcher calls!
        expect(fetcherCallCount, equals(1));
        expect(routes.isNotEmpty, isTrue);
        expect(routes.first.safetyStatus, equals('safe'));
        expect(routes.first.summary, equals('Safest Route'));
      },
    );

    test(
      'Detours ARE requested when all Mapbox alternatives are critical',
      () async {
        int fetcherCallCount = 0;

        final criticalRoad = createTestRoad(
          id: 'critical_road',
          name: 'Critical Flooded Road',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        final route1Critical = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses criticalRoad
          Position(120.9900, 14.6760),
        ];

        final route2Critical = [
          Position(120.9800, 14.6760),
          Position(120.9855, 14.6760), // also crosses criticalRoad
          Position(120.9900, 14.6760),
        ];

        final cleanDetourPath = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          allowDetourGeneration: true,
          maxDetourCandidates: 3,
          roadsOverride: [criticalRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                fetcherCallCount++;
                if (waypoints.isEmpty) {
                  return [
                    createMockMapboxRoute(
                      points: route1Critical,
                      distance: 1000.0,
                      duration: 120.0,
                    ),
                    createMockMapboxRoute(
                      points: route2Critical,
                      distance: 1100.0,
                      duration: 130.0,
                    ),
                  ];
                } else {
                  return [
                    createMockMapboxRoute(
                      points: cleanDetourPath,
                      distance: 1300.0,
                      duration: 160.0,
                    ),
                  ];
                }
              },
        );

        // Initial call (1) + detour calls (3) = 4
        expect(fetcherCallCount, equals(4));
        expect(routes.isNotEmpty, isTrue);
        expect(routes.first.summary, equals('Safe Detour (Auto-Generated)'));
      },
    );

    test(
      'Detours ARE requested when avoidRoadIds is non-empty and every non-critical route crosses an avoided road',
      () async {
        int fetcherCallCount = 0;

        final avoidRoad = createTestRoad(
          id: 'avoid_me',
          name: 'Advisory Road to Avoid',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 20.0,
        );

        final route1PassableCrossesAvoid = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses avoid_me
          Position(120.9900, 14.6760),
        ];

        final cleanDetourPath = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850), // avoids avoid_me
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          avoidRoadIds: {'avoid_me'},
          allowDetourGeneration: true,
          maxDetourCandidates: 3,
          roadsOverride: [avoidRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                fetcherCallCount++;
                if (waypoints.isEmpty) {
                  return [
                    createMockMapboxRoute(
                      points: route1PassableCrossesAvoid,
                      distance: 1000.0,
                      duration: 120.0,
                    ),
                  ];
                } else {
                  return [
                    createMockMapboxRoute(
                      points: cleanDetourPath,
                      distance: 1300.0,
                      duration: 160.0,
                    ),
                  ];
                }
              },
        );

        // Initial call (1) + detour calls (3) = 4
        expect(fetcherCallCount, equals(4));
        expect(routes.isNotEmpty, isTrue);
        expect(routes.first.summary, equals('Safe Detour (Auto-Generated)'));
        expect(routes.first.hazardAlerts, isEmpty);
      },
    );

    test(
      'Detours are NOT requested when avoidRoadIds is non-empty but one non-critical route avoids it',
      () async {
        int fetcherCallCount = 0;

        final avoidRoad = createTestRoad(
          id: 'avoid_me',
          name: 'Advisory Road to Avoid',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 20.0,
        );

        final route1CrossesAvoid = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses avoid_me
          Position(120.9900, 14.6760),
        ];

        final route2Avoids = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850), // does NOT cross avoid_me
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          avoidRoadIds: {'avoid_me'},
          allowDetourGeneration: true,
          roadsOverride: [avoidRoad],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                fetcherCallCount++;
                return [
                  createMockMapboxRoute(
                    points: route1CrossesAvoid,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                  createMockMapboxRoute(
                    points: route2Avoids,
                    distance: 1100.0,
                    duration: 130.0,
                  ),
                ];
              },
        );

        // Only 1 initial call, no detour calls because route2 already avoids the avoided road!
        expect(fetcherCallCount, equals(1));
        expect(routes.first.hazardAlerts, isEmpty);
      },
    );

    test(
      'Detour button avoidRoadIds penalty: with avoidRoadIds = {X}, route A crossing X is penalized by 20000 and route B ranks first',
      () async {
        final roadX = createTestRoad(
          id: 'road_X',
          name: 'Road X',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'passable',
          riskScore: 10.0,
        );

        final routeACrossesX = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses road_X
          Position(120.9900, 14.6760),
        ];

        final routeBDoesNotCross = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
          Position(120.9900, 14.6760),
        ];

        final routes = await routingService.computeRoutes(
          origin: origin,
          destination: destination,
          avoidRoadIds: {'road_X'},
          allowDetourGeneration: false,
          roadsOverride: [roadX],
          weatherStateOverride: WeatherState.clear,
          directionsFetcher:
              (
                orig,
                dest, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                return [
                  createMockMapboxRoute(
                    points: routeACrossesX,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                  createMockMapboxRoute(
                    points: routeBDoesNotCross,
                    distance: 1000.0,
                    duration: 120.0,
                  ),
                ];
              },
        );

        expect(routes.length, equals(2));
        // Route B ranks first because Route A received the +20000 avoid penalty
        expect(routes[0].hazardAlerts, isEmpty);
        expect(routes[1].hazardAlerts, contains('Road X (Predicted Risk)'));
        // Route A's cost is at least 20000 higher than Route B's cost
        expect(
          routes[1].routeCost - routes[0].routeCost,
          greaterThanOrEqualTo(20000.0),
        );
      },
    );

    test(
      'findNearestReachableStagingFacility returns null when all facilities are blocked',
      () async {
        final floodBarrier = createTestRoad(
          id: 'barrier_road',
          name: 'Flood Barrier Rd',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        final testFacilities = [
          {'name': 'Facility 1', 'lat': 14.6760, 'lng': 120.9880},
          {'name': 'Facility 2', 'lat': 14.6760, 'lng': 120.9900},
        ];

        final blockedPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760), // crosses barrier_road
          Position(120.9900, 14.6760),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              roadsOverride: [floodBarrier],
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    return [
                      createMockMapboxRoute(
                        points: blockedPath,
                        distance: 800.0,
                        duration: 120.0,
                      ),
                    ];
                  },
            );

        expect(selected, isNull);
      },
    );

    test(
      'findNearestReachableStagingFacility picks shorter duration when two are reachable',
      () async {
        final testFacilities = [
          {'name': 'Facility Slow', 'lat': 14.6800, 'lng': 120.9800},
          {'name': 'Facility Fast', 'lat': 14.6790, 'lng': 120.9800},
        ];

        final pathSlow = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6800),
        ];
        final pathFast = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6790),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    if (dest.lat == 14.6800) {
                      return [
                        createMockMapboxRoute(
                          points: pathSlow,
                          distance: 1000.0,
                          duration: 300.0,
                        ),
                      ]; // 5 min
                    } else {
                      return [
                        createMockMapboxRoute(
                          points: pathFast,
                          distance: 800.0,
                          duration: 120.0,
                        ),
                      ]; // 2 min
                    }
                  },
            );

        expect(selected, isNotNull);
        expect(selected!['name'], equals('Facility Fast'));
        expect(
          (selected['reachableRoute'] as PlannedRoute).durationMin,
          equals(2),
        );
      },
    );

    test(
      'findNearestReachableStagingFacility: one facility throwing/timing out does not stop others',
      () async {
        final testFacilities = [
          {'name': 'Facility Error', 'lat': 14.6800, 'lng': 120.9800},
          {'name': 'Facility Good', 'lat': 14.6850, 'lng': 120.9800},
        ];

        final pathGood = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    if (dest.lat == 14.6800) {
                      throw Exception('Network timeout connecting to provider');
                    } else {
                      return [
                        createMockMapboxRoute(
                          points: pathGood,
                          distance: 800.0,
                          duration: 120.0,
                        ),
                      ];
                    }
                  },
            );

        expect(selected, isNotNull);
        expect(selected!['name'], equals('Facility Good'));
      },
    );

    test(
      'findNearestReachableStagingFacility: when first route in list is blocked but later route is not, counts facility as reachable',
      () async {
        final floodBarrier = createTestRoad(
          id: 'barrier_road',
          name: 'Flood Barrier Rd',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
          riskScore: 100.0,
        );

        final testFacilities = [
          {'name': 'Facility Mixed', 'lat': 14.6850, 'lng': 120.9800},
        ];

        final blockedPath = [
          Position(120.9800, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9900, 14.6760),
        ];
        final cleanPath = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              roadsOverride: [floodBarrier],
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    return [
                      createMockMapboxRoute(
                        points: blockedPath,
                        distance: 600.0,
                        duration: 60.0,
                      ), // Blocked
                      createMockMapboxRoute(
                        points: cleanPath,
                        distance: 900.0,
                        duration: 120.0,
                      ), // Clean
                    ];
                  },
            );

        expect(selected, isNotNull);
        expect(selected!['name'], equals('Facility Mixed'));
        expect((selected['reachableRoute'] as PlannedRoute).isBlocked, isFalse);
      },
    );

    test(
      'findNearestReachableStagingFacility: fallback pass is not called when direct pass succeeds (count fetcher calls)',
      () async {
        int fetcherCallCount = 0;

        final testFacilities = [
          {'name': 'Facility Direct 1', 'lat': 14.6800, 'lng': 120.9800},
          {'name': 'Facility Direct 2', 'lat': 14.6850, 'lng': 120.9800},
        ];

        final path1 = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6800),
        ];
        final path2 = [
          Position(120.9800, 14.6760),
          Position(120.9800, 14.6850),
        ];

        final selected =
            await RoutingService.findNearestReachableStagingFacility(
              origin: Position(120.9800, 14.6760),
              facilities: testFacilities,
              routingService: routingService,
              weatherStateOverride: WeatherState.clear,
              directionsFetcher:
                  (
                    orig,
                    dest, {
                    waypoints = const [],
                    vehicleType = 'Sedan',
                    headingDeg,
                  }) async {
                    fetcherCallCount++;
                    if (dest.lat == 14.6800) {
                      return [
                        createMockMapboxRoute(
                          points: path1,
                          distance: 1000.0,
                          duration: 180.0,
                        ),
                      ];
                    } else {
                      return [
                        createMockMapboxRoute(
                          points: path2,
                          distance: 800.0,
                          duration: 120.0,
                        ),
                      ];
                    }
                  },
            );

        expect(selected, isNotNull);
        // Evaluates 2 facilities in parallel for Pass 1 only: fetcherCallCount == 2
        expect(fetcherCallCount, equals(2));
      },
    );
  });

  group('Task A, B, C, D Pure Helpers & Honesty Tests', () {
    test('routesEffectivelySame: identical polylines return true', () {
      final polyA = [
        Position(120.9840, 14.6760),
        Position(120.9850, 14.6760),
        Position(120.9860, 14.6760),
      ];
      final polyB = [
        Position(120.9840, 14.6760),
        Position(120.9850, 14.6760),
        Position(120.9860, 14.6760),
      ];
      expect(RoutingService.routesEffectivelySame(polyA, polyB), isTrue);
    });

    test('routesEffectivelySame: shifted < 15m returns true', () {
      final polyA = [
        Position(120.9840, 14.6760),
        Position(120.9850, 14.6760),
        Position(120.9860, 14.6760),
      ];
      // Shifted by ~8 meters north (0.00007 deg lat)
      final polyB = [
        Position(120.9840, 14.67607),
        Position(120.9850, 14.67607),
        Position(120.9860, 14.67607),
      ];
      expect(RoutingService.routesEffectivelySame(polyA, polyB), isTrue);
    });

    test(
      'routesEffectivelySame: different route (>15m shifted or different path) returns false',
      () {
        final polyA = [
          Position(120.9840, 14.6760),
          Position(120.9850, 14.6760),
          Position(120.9860, 14.6760),
        ];
        // Shifted by ~55 meters north (0.0005 deg lat)
        final polyB = [
          Position(120.9840, 14.67650),
          Position(120.9850, 14.67650),
          Position(120.9860, 14.67650),
        ];
        expect(RoutingService.routesEffectivelySame(polyA, polyB), isFalse);
      },
    );

    test(
      'findStatusChangedRoads: returns roads whose effective status changed from cache',
      () {
        final road1 = createTestRoad(
          id: 'road_1',
          name: 'Road 1',
          points: [Position(120.9840, 14.6760), Position(120.9860, 14.6760)],
          status: 'not_passable',
        );
        final road2 = createTestRoad(
          id: 'road_2',
          name: 'Road 2',
          points: [Position(120.9840, 14.6770), Position(120.9860, 14.6770)],
          status: 'passable',
        );

        final cache = {
          'road_1': 'passable', // Changed to not_passable
          'road_2': 'passable', // Unchanged
        };

        final changed = RoutingService.findStatusChangedRoads(
          [road1, road2],
          cache,
          WeatherState.clear,
        );
        expect(changed.length, equals(1));
        expect(changed.first.id, equals('road_1'));
      },
    );

    test(
      'buildRouteMessages: all blocked -> error says closed by official flood barriers (no proceed/caution)',
      () {
        final blockedRoute = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Blocked Route',
          hazardAlerts: [],
          routeExplanations: [],
          safetyStatus: 'critical',
          safetyScore: 0,
          routeCost: 99999.0,
          totalRisk: 100.0,
          steps: [],
          isBlocked: true,
        );

        final result = RoutingService.buildRouteMessages(
          [blockedRoute],
          WeatherState.clear,
          usingFallback: false,
        );
        expect(result.error, isNotNull);
        expect(
          result.error!.toLowerCase(),
          contains('closed by official flood barriers'),
        );
        expect(result.error!.toLowerCase(), isNot(contains('proceed')));
        expect(result.error!.toLowerCase(), isNot(contains('caution')));
        expect(result.warning, isNull);
      },
    );

    test(
      'buildRouteMessages: all critical, none blocked -> warning says predicted high-risk (no closed wording)',
      () {
        final criticalRoute = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Critical Route',
          hazardAlerts: [],
          routeExplanations: [],
          safetyStatus: 'critical',
          safetyScore: 10,
          routeCost: 50000.0,
          totalRisk: 80.0,
          steps: [],
          isBlocked: false,
        );

        final result = RoutingService.buildRouteMessages(
          [criticalRoute],
          WeatherState.clear,
          usingFallback: false,
        );
        expect(result.error, isNull);
        expect(result.warning, isNotNull);
        expect(result.warning!.toLowerCase(), contains('predicted high-risk'));
        expect(result.warning!.toLowerCase(), isNot(contains('closed')));
      },
    );

    test(
      'buildRouteMessages: mixed routes in normal weather -> neither error nor warning',
      () {
        final safeRoute = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Safe Route',
          hazardAlerts: [],
          routeExplanations: [],
          safetyStatus: 'safe',
          safetyScore: 95,
          routeCost: 1000.0,
          totalRisk: 0.0,
          steps: [],
          isBlocked: false,
        );
        final critRoute = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 12,
          distanceMiles: 1.2,
          summary: 'Critical Route',
          hazardAlerts: [],
          routeExplanations: [],
          safetyStatus: 'critical',
          safetyScore: 15,
          routeCost: 50000.0,
          totalRisk: 80.0,
          steps: [],
          isBlocked: false,
        );

        final result = RoutingService.buildRouteMessages(
          [safeRoute, critRoute],
          WeatherState.clear,
          usingFallback: false,
        );
        expect(result.error, isNull);
        expect(result.warning, isNull);
      },
    );

    test(
      'buildRouteMessages: severe weather + fallback -> both warnings present and appended',
      () {
        final partialRoute = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Partial Route',
          hazardAlerts: [],
          routeExplanations: [],
          safetyStatus: 'partial',
          safetyScore: 60,
          routeCost: 5000.0,
          totalRisk: 30.0,
          steps: [],
          isBlocked: false,
        );

        final result = RoutingService.buildRouteMessages(
          [partialRoute],
          WeatherState.typhoon,
          usingFallback: true,
        );
        expect(result.error, isNull);
        expect(result.warning, isNotNull);
        expect(result.warning!, contains('Typhoon Active'));
        expect(result.warning!, contains('GPS unavailable'));
      },
    );

    test(
      'routesEffectivelySame: new route = old route plus a 300 m detour returns false',
      () {
        // Old route: straight path along 14.6760 (approx 500m length, 20m steps)
        final polyA = List.generate(
          25,
          (i) => Position(120.9800 + (i * 0.0002), 14.6760),
        );

        // New route: same start and end, but middle 10 points take a 300m detour north (0.003 deg lat ~ 330m)
        final polyB = <Position>[
          ...List.generate(
            7,
            (i) => Position(120.9800 + (i * 0.0002), 14.6760),
          ),
          ...List.generate(
            11,
            (i) => Position(120.9814 + (i * 0.0002), 14.6790),
          ), // 300m detour loop
          ...List.generate(
            7,
            (i) => Position(120.9836 + (i * 0.0002), 14.6760),
          ),
        ];

        expect(RoutingService.routesEffectivelySame(polyA, polyB), isFalse);
      },
    );

    test(
      'PlannedRoute.canStartNavigation: is false for blocked routes and true for non-blocked routes',
      () {
        final blocked = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Blocked',
          hazardAlerts: [],
          safetyStatus: 'critical',
          steps: [],
          isBlocked: true,
        );
        final nonBlockedCritical = PlannedRoute(
          points: [Position(120.9840, 14.6760), Position(120.9850, 14.6760)],
          durationMin: 10,
          distanceMiles: 1.0,
          summary: 'Non-Blocked Critical',
          hazardAlerts: [],
          safetyStatus: 'critical',
          steps: [],
          isBlocked: false,
        );

        expect(blocked.canStartNavigation, isFalse);
        expect(nonBlockedCritical.canStartNavigation, isTrue);
      },
    );

    test(
      'calculateRoute discards older in-flight calculation when _calculationId advances',
      () async {
        final service = RoutingService.instance;
        service.routes = [];
        service.originPoint = Position(120.9842, 14.6761);
        service.destinationPoint = Position(120.9890, 14.6761);

        // Start calculation 1 (which will be superseded)
        final calc1 = service.calculateRoute();
        // Immediately start calculation 2 (bumps _calculationId)
        service.destinationPoint = Position(120.9900, 14.6761);
        final calc2 = service.calculateRoute();

        await Future.wait([calc1, calc2]);

        // State represents calculation 2
        expect(service.destinationPoint, equals(Position(120.9900, 14.6761)));
      },
    );
  });
}
