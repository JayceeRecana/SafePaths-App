import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/utils/location_fix.dart';
import 'package:safepaths_app/widgets/route_navigation.dart';

Position point(double x, double y) => Position(
  AppEnvironment.area.longitude + x,
  AppEnvironment.area.latitude + y,
);
List<Position> get direct => [point(-0.002, 0), point(0.002, 0)];
List<Position> get detour => [
  point(-0.002, 0),
  point(-0.002, 0.004),
  point(0.002, 0.004),
  point(0.002, 0),
];
String encoded(List<Position> points) {
  final out = StringBuffer();
  var lat = 0, lng = 0;
  void part(int d) {
    var v = d < 0 ? ~(d << 1) : d << 1;
    while (v >= 32) {
      out.writeCharCode((32 | (v & 31)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in points) {
    final a = (p.lat * 1e5).round(), b = (p.lng * 1e5).round();
    part(a - lat);
    part(b - lng);
    lat = a;
    lng = b;
  }
  return out.toString();
}

Map<String, dynamic> raw(List<Position> p, {double distance = 1000}) => {
  'geometry': encoded(p),
  'distance': distance,
  'duration': 300,
  'legs': [],
};
PlannedRoute route(List<Position> p) => PlannedRoute(
  points: p,
  durationMin: 5,
  distanceMiles: 1,
  summary: 'Selected route',
  hazardAlerts: [],
  safetyStatus: 'safe',
  steps: [],
  vehicleType: 'Sedan',
  requestedDestination: p.last,
);
RoadStatus road(String status, {String? community}) => RoadStatus(
  id: 'crossing',
  name: 'Crossing road',
  status: status,
  notes: 'Synthetic test',
  updatedAt: DateTime.now(),
  riskScore: status == 'not_passable'
      ? 100
      : status == 'partial'
      ? 50
      : 0,
  communityCondition: community,
  geometry: {
    'type': 'LineString',
    'coordinates': [
      [point(0, -0.0003).lng, point(0, -0.0003).lat],
      [point(0, 0.0003).lng, point(0, 0.0003).lat],
    ],
  },
);
void main() {
  final service = RoutingService.instance, app = AppStateService.instance;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(
      envString: 'MAPBOX_ACCESS_TOKEN=pk.synthetic-no-network',
    );
    SimulatedWeatherService.instance;
  });
  setUp(() {
    service.exitPlanning();
    app.roads.clear();
    service.selectedVehicleType = 'Sedan';
  });
  tearDown(() => service.exitPlanning());
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  test(
    'staging options never fabricate a destination when none are configured',
    () async {
      var calls = 0;
      final selected = await RoutingService.findNearestReachableStagingFacility(
        origin: direct.first,
        facilities: [],
        routingService: service,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              calls++;
              return [raw(direct)];
            },
      );
      expect(selected, isNull);
      expect(calls, 0);
    },
  );

  test(
    'a critical predicted route cannot be recommended as a staging option',
    () {
      final predicted = road('passable').copyWith(riskScore: 85);
      final evaluated = service.refreshRoute(
        route(direct),
        roads: [predicted],
        weather: WeatherState.clear,
      );
      expect(evaluated.isBlocked, false);
      expect(evaluated.safetyStatus, 'critical');
      expect(RoutingService.isStagingRouteCandidate(evaluated), false);
    },
  );

  test(
    'staging selection prefers a clear route over a faster route with known partial flooding',
    () async {
      final clearGoal = point(0.002, 0.0008);
      final clearPath = [
        direct.first,
        point(-0.002, 0.001),
        point(0.002, 0.001),
        clearGoal,
      ];
      final selected = await RoutingService.findNearestReachableStagingFacility(
        origin: direct.first,
        facilities: [
          {
            'name': 'Short flooded option',
            'lat': direct.last.lat,
            'lng': direct.last.lng,
          },
          {'name': 'Clear option', 'lat': clearGoal.lat, 'lng': clearGoal.lng},
        ],
        routingService: service,
        roadsOverride: [road('partial')],
        weatherStateOverride: WeatherState.clear,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [
              if (b.lat == clearGoal.lat)
                raw(clearPath)
              else
                (raw(direct)..['duration'] = 60),
            ],
      );
      expect(selected?['name'], 'Clear option');
      expect((selected?['reachableRoute'] as PlannedRoute).needsCaution, false);
    },
  );

  test(
    'a staging result is checked against a closure received while its directions were pending',
    () async {
      final response = Completer<List<Map<String, dynamic>>>();
      var calls = 0;
      final work = RoutingService.findNearestReachableStagingFacility(
        origin: direct.first,
        facilities: [
          {
            'name': 'Test option',
            'lat': direct.last.lat,
            'lng': direct.last.lng,
          },
        ],
        routingService: service,
        weatherStateOverride: WeatherState.clear,
        directionsFetcher:
            (a, b, {waypoints = const [], vehicleType = 'Sedan', headingDeg}) {
              calls++;
              return calls == 1 ? response.future : Future.value([]);
            },
      );
      app.roads.add(road('not_passable'));
      response.complete([raw(direct)]);
      expect(await work, isNull);
      expect(calls, 2);
    },
  );

  test('cancelling a staging search prevents its fallback pass', () async {
    var current = true, calls = 0;
    final selected = await RoutingService.findNearestReachableStagingFacility(
      origin: direct.first,
      facilities: [
        {'name': 'Test option', 'lat': direct.last.lat, 'lng': direct.last.lng},
      ],
      routingService: service,
      weatherStateOverride: WeatherState.clear,
      isCurrent: () => current,
      directionsFetcher:
          (
            a,
            b, {
            waypoints = const [],
            vehicleType = 'Sedan',
            headingDeg,
          }) async {
            calls++;
            current = false;
            return [];
          },
    );
    expect(selected, isNull);
    expect(calls, 1);
  });

  test(
    'GPS unavailable leaves both flavors without a fabricated origin; manual selection wins over a late fix',
    () async {
      final gps = Completer<Position?>(), manual = direct.first;
      service.startPlanning(locate: () => gps.future);
      expect(service.originPoint, isNull);
      service.setOrigin(manual, 'Manual start');
      gps.complete(point(0.001, 0.001));
      await Future<void>.delayed(Duration.zero);
      expect(service.originPoint, same(manual));
    },
  );
  test(
    'a failed GPS lookup preserves a useful manual-start recovery state',
    () async {
      service.startPlanning(locate: () async => null);
      await Future<void>.delayed(Duration.zero);
      expect(service.originPoint, isNull);
      expect(service.isLocatingGps, false);
      expect(service.routeErrorMessage, contains('choose a start point'));
    },
  );
  test(
    'starting another planning session cancels an earlier route result and loading state',
    () async {
      service.originPoint = direct.first;
      service.destinationPoint = direct.last;
      final response = Completer<List<Map<String, dynamic>>>();
      final work = service.calculateRoute(
        directionsFetcher:
            (a, b, {waypoints = const [], vehicleType = 'Sedan', headingDeg}) =>
                response.future,
      );
      expect(service.isRouteLoading, true);
      final gps = Completer<Position?>();
      service.startPlanning(locate: () => gps.future);
      response.complete([raw(direct)]);
      await work;
      expect(service.routes, isEmpty);
      expect(service.isRouteLoading, false);
      gps.complete(null);
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'clearing or editing the destination cancels an in-flight plan and cannot restore its old routes',
    () async {
      service.originPoint = direct.first;
      service.destinationPoint = direct.last;
      final response = Completer<List<Map<String, dynamic>>>();
      final work = service.calculateRoute(
        directionsFetcher:
            (a, b, {waypoints = const [], vehicleType = 'Sedan', headingDeg}) =>
                response.future,
      );
      service.clearDestination();
      response.complete([raw(direct)]);
      await work;
      expect(service.destinationPoint, isNull);
      expect(service.routes, isEmpty);
      expect(service.isRouteLoading, false);
    },
  );
  test(
    'current closures are rechecked when a pending planner response returns',
    () async {
      service.originPoint = direct.first;
      service.destinationPoint = direct.last;
      final response = Completer<List<Map<String, dynamic>>>();
      final work = service.calculateRoute(
        directionsFetcher:
            (a, b, {waypoints = const [], vehicleType = 'Sedan', headingDeg}) =>
                response.future,
      );
      app.roads.add(road('not_passable'));
      response.complete([raw(direct)]);
      await work;
      expect(service.routes.single.isBlocked, true);
      expect(service.routes.single.canStartNavigation, false);
      expect(service.routeErrorMessage, contains('closed'));
    },
  );
  test(
    'visible planner safety refreshes after road updates without another route HTTP request',
    () async {
      service.startPlanning(locate: () async => null);
      service.setOrigin(direct.first, 'Chosen start');
      service.destinationPoint = direct.last;
      var calls = 0;
      await service.calculateRoute(
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              calls++;
              return [raw(direct)];
            },
      );
      expect(service.routes.single.isBlocked, false);
      app.roads.add(road('not_passable'));
      app.mapChanges.value++;
      expect(service.routes.single.isBlocked, true);
      expect(calls, 1);
      expect(service.routes.single.riskReductionPercentage, isNull);
    },
  );
  test(
    'an open alternative always ranks before a closed shortcut, even when far longer',
    () async {
      final routes = await service.computeRoutes(
        origin: direct.first,
        destination: direct.last,
        roadsOverride: [road('not_passable')],
        weatherStateOverride: WeatherState.clear,
        allowDetourGeneration: false,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [
              raw(direct, distance: 100),
              raw(detour, distance: 1000000),
            ],
      );
      expect(routes.first.isBlocked, false);
      expect(routes.first.distanceMiles, greaterThan(500));
      expect(routes.last.isBlocked, true);
    },
  );
  test('cancelled work never launches its later detour batch', () async {
    var current = true, calls = 0;
    final response = Completer<List<Map<String, dynamic>>>();
    final work = service.computeRoutes(
      origin: direct.first,
      destination: direct.last,
      roadsOverride: [road('not_passable')],
      weatherStateOverride: WeatherState.clear,
      isCurrent: () => current,
      directionsFetcher:
          (a, b, {waypoints = const [], vehicleType = 'Sedan', headingDeg}) {
            calls++;
            return response.future;
          },
    );
    current = false;
    response.complete([raw(direct)]);
    await expectLater(work, throwsA(isA<RouteComputationCancelled>()));
    expect(calls, 1);
  });
  test(
    'the whole route calculation has a deadline when its provider never responds',
    () async {
      var calls = 0;
      await expectLater(
        service.computeRoutes(
          origin: direct.first,
          destination: direct.last,
          roadsOverride: [],
          weatherStateOverride: WeatherState.clear,
          timeBudget: const Duration(milliseconds: 10),
          directionsFetcher:
              (
                a,
                b, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) {
                calls++;
                return Completer<List<Map<String, dynamic>>>().future;
              },
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
    },
  );
  test(
    'failed detour requests remain service failures rather than a false no-alternative verdict',
    () async {
      var calls = 0;
      await expectLater(
        service.computeRoutes(
          origin: direct.first,
          destination: direct.last,
          roadsOverride: [road('not_passable')],
          weatherStateOverride: WeatherState.clear,
          maxDetourCandidates: 2,
          directionsFetcher:
              (
                a,
                b, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                calls++;
                if (waypoints.isNotEmpty) throw const RoutingUnavailable();
                return [raw(direct)];
              },
        ),
        throwsA(isA<RoutingUnavailable>()),
      );
      expect(calls, 3);
    },
  );
  test(
    'malformed provider alternatives and optional instructions cannot discard a valid route or create a degenerate trip',
    () async {
      final valid = raw(direct);
      valid['legs'] = [
        {
          'steps': [
            {
              'maneuver': {
                'location': [double.nan, 1],
              },
              'distance': 'bad',
            },
          ],
        },
      ];
      final routes = await service.computeRoutes(
        origin: direct.first,
        destination: direct.last,
        roadsOverride: [],
        weatherStateOverride: WeatherState.clear,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [
              {'geometry': 'bad', 'distance': double.nan, 'duration': 0},
              valid,
            ],
      );
      expect(routes, hasLength(1));
      expect(routes.single.steps, isEmpty);
      expect(route([direct.first, direct.first]).canStartNavigation, false);
    },
  );
  test(
    'safety refresh retains exact route distance and requested avoidance costs',
    () async {
      final original = await service.computeRoutes(
        origin: direct.first,
        destination: direct.last,
        roadsOverride: [road('partial')],
        weatherStateOverride: WeatherState.clear,
        avoidRoadIds: {'crossing'},
        allowDetourGeneration: false,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [raw(direct, distance: 1234.56)],
      );
      final updated = RoadStatus(
        id: 'crossing',
        name: 'Crossing road',
        status: 'partial',
        notes: 'Updated synthetic prediction',
        updatedAt: DateTime.now(),
        riskScore: 60,
        geometry: road('partial').geometry,
      );
      final fresh = service.refreshRoute(
        original.single,
        roads: [updated],
        weather: WeatherState.clear,
      );
      expect(fresh.routeCost, closeTo(1234.56 + 600 + 3000 + 20000, 0.001));
      expect(fresh.requestedAvoidRoadIds, {'crossing'});
      expect(fresh.distanceMeters, 1234.56);
    },
  );
  test(
    'identical start and destination are rejected without a provider request',
    () async {
      service.originPoint = direct.first;
      service.destinationPoint = service.originPoint;
      var calls = 0;
      await service.calculateRoute(
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              calls++;
              return [raw(direct)];
            },
      );
      expect(calls, 0);
      expect(service.routes, isEmpty);
      expect(service.isRouteLoading, false);
      expect(service.routeErrorMessage, contains('different start'));
    },
  );
  test(
    'predicted risk requires caution even below the critical model threshold',
    () {
      final geometry = road('passable').geometry;
      final predicted = RoadStatus(
        id: 'predicted',
        name: 'Predicted risk road',
        status: 'passable',
        notes: 'Synthetic test',
        updatedAt: DateTime.now(),
        riskScore: 65,
        geometry: geometry,
      );
      final state = service.navigationAdmission(
        route(direct),
        roads: [predicted],
        weather: WeatherState.clear,
        liveDataUnavailable: false,
      );
      expect(state.route.isBlocked, false);
      expect(state.route.totalRisk, greaterThan(0));
      expect(state.requiresCaution, true);
      expect(state.route.needsCaution, true);
      expect(state.route.conditionSummary, contains('predicted'));
    },
  );
  test(
    'partial, unresolved and outside-area routes require a caution acknowledgement',
    () {
      for (final r in [
        road('partial'),
        road('passable', community: 'outdated'),
      ]) {
        final state = service.navigationAdmission(
          route(direct),
          roads: [r],
          weather: WeatherState.clear,
          liveDataUnavailable: false,
        );
        expect(state.requiresCaution, true);
      }
      final outside = route([
        direct.first,
        Position(
          AppEnvironment.area.longitude,
          AppEnvironment.area.north + 0.01,
        ),
        direct.last,
      ]);
      final state = service.navigationAdmission(
        outside,
        roads: [],
        weather: WeatherState.clear,
        liveDataUnavailable: false,
      );
      expect(state.route.outsideStudyArea, true);
      expect(state.route.safetyScoreLabel, 'Unconfirmed');
      expect(state.requiresCaution, true);
    },
  );
  testWidgets(
    'closure arriving while a caution dialog is open prevents navigation on confirmation',
    (tester) async {
      var navigateCount = 0;
      final selected = route(direct);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => startRouteNavigation(
                  context,
                  selected,
                  onNavigate: (_) {
                    navigateCount++;
                  },
                  assess: (r) => service.navigationAdmission(
                    r,
                    roads: app.roads,
                    weather: WeatherState.clear,
                    liveDataUnavailable: true,
                  ),
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Caution'), findsOneWidget);
      app.roads.add(road('not_passable'));
      await tester.tap(find.text('Continue with Caution'));
      await tester.pumpAndSettle();
      expect(navigateCount, 0);
      expect(find.textContaining('Road conditions changed'), findsOneWidget);
    },
  );
  testWidgets(
    'unchanged caution confirmation hands off current route metadata once',
    (tester) async {
      PlannedRoute? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => startRouteNavigation(
                  context,
                  route(direct),
                  onNavigate: (r) => accepted = r,
                  assess: (r) => service.navigationAdmission(
                    r,
                    roads: [road('partial')],
                    weather: WeatherState.clear,
                    liveDataUnavailable: false,
                  ),
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Caution'));
      await tester.pumpAndSettle();
      expect(accepted, isNotNull);
      expect(accepted!.safetyStatus, 'partial');
      expect(accepted!.vehicleType, 'Sedan');
    },
  );
  test(
    'invalid, inaccurate and stale GPS fixes cannot become a navigation origin',
    () {
      final now = DateTime.utc(2026, 1, 1);
      geo.Position fix({
        double accuracy = 5,
        double lat = 14.676,
        DateTime? timestamp,
      }) => geo.Position(
        latitude: lat,
        longitude: 120.984,
        timestamp: timestamp ?? now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      expect(usableLocationFix(fix(), now: now), true);
      for (final p in [
        fix(accuracy: 80),
        fix(accuracy: -1),
        fix(lat: double.nan),
        fix(timestamp: now.subtract(const Duration(minutes: 2))),
        fix(timestamp: now.add(const Duration(minutes: 1))),
      ])
        expect(usableLocationFix(p, now: now), false);
    },
  );
}
