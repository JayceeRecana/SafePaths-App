import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/screens/user/navigation_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';

// Real navigation screen, with only the GPS/network/native-map boundaries replaced.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<geo.Position> gps;
  late DateTime time;
  late List<Set<String>> requests;
  late List<Position> origins, destinations;
  late List<String> modes;
  late List<String> speech;
  late List<Position> displayedRoute;
  late Future<List<PlannedRoute>> Function() respond;
  late Future<Map<String, dynamic>?> Function(Position) stagingSearch;
  final app = AppStateService.instance;
  setUpAll(() {
    dotenv.loadFromString(envString: 'NAVIGATION_TEST=true');
    // Keep the app-wide weather poll outside each widget test's fake clock.
    SimulatedWeatherService.instance;
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  PlannedRoute path(double latitude) => PlannedRoute(
    points: [
      Position(120.980, 14.676),
      Position(120.980, latitude),
      Position(120.990, latitude),
      Position(120.990, 14.676),
    ],
    durationMin: 10,
    distanceMiles: 1,
    summary: '',
    hazardAlerts: [],
    safetyStatus: 'safe',
    steps: [],
  );
  final mainRoute = path(14.676);
  final detour = path(14.680);
  final thirdRoute = path(14.683);
  final stagingRoute = PlannedRoute(
    points: [
      Position(120.980, 14.676),
      Position(120.980, 14.682),
      Position(120.990, 14.682),
    ],
    durationMin: 8,
    distanceMiles: 1,
    summary: 'Staging option',
    hazardAlerts: [],
    safetyStatus: 'safe',
    steps: [],
    vehicleType: 'Sedan',
    requestedDestination: Position(120.990, 14.682),
  );
  Map<String, dynamic> stagingOption([PlannedRoute? route]) => {
    'name': 'Test staging location',
    'lat': 14.682,
    'lng': 120.990,
    'reachableRoute': route ?? stagingRoute,
  };

  Future<void> tick(WidgetTester tester, int seconds) async {
    time = time.add(Duration(seconds: seconds));
    await tester.pump(Duration(seconds: seconds));
    await tester.pump();
  }

  geo.Position reading({
    double lng = 120.980,
    double accuracy = 5,
    int ageSeconds = 0,
  }) => geo.Position(
    latitude: 14.676,
    longitude: lng,
    timestamp: time.subtract(Duration(seconds: ageSeconds)),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Future<void> fix(
    WidgetTester tester, {
    double lat = 14.676,
    double lng = 120.980,
    double accuracy = 5,
  }) async {
    gps.add(
      geo.Position(
        latitude: lat,
        longitude: lng,
        timestamp: time,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 1,
        speedAccuracy: 0,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> closeRoad(String id, double latitude) => app.updateRoadStatus(
    id,
    'not_passable',
    'Simulated test closure',
    name: id,
    geometry: {
      'type': 'LineString',
      'coordinates': [
        [120.984, latitude],
        [120.986, latitude],
      ],
    },
  );

  Future<void> predictRoad(double risk) async {
    final road = RoadStatus(
      id: 'Predicted',
      name: 'Predicted high risk',
      status: 'passable',
      notes: 'Synthetic risk',
      updatedAt: DateTime.now(),
      riskScore: risk,
      geometry: {
        'type': 'LineString',
        'coordinates': [
          [120.984, 14.680],
          [120.986, 14.680],
        ],
      },
    );
    final index = app.roads.indexWhere((r) => r.id == road.id);
    if (index < 0) {
      app.roads.add(road);
    } else {
      app.roads[index] = road;
    }
    await app.updateRoadStatus(
      road.id,
      'passable',
      'Synthetic prediction update',
    );
  }

  Future<void> start(
    WidgetTester tester, {
    bool firstFix = true,
    PlannedRoute? initialRoute,
    String? reviewedRiskKey,
    double width = 1080,
    double textScale = 1,
    Future<geo.Position?> Function()? currentFix,
  }) async {
    tester.view.physicalSize = Size(width, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: NavigationScreen(
          route: initialRoute ?? mainRoute,
          positionStream: gps.stream,
          currentFix: currentFix,
          now: () => time,
          mapBuilder: (points) {
            displayedRoute = points;
            return const SizedBox.expand();
          },
          stagingSearch: (origin) => stagingSearch(origin),
          reviewedRiskKey: reviewedRiskKey,
          routeComputer:
              ({
                required origin,
                required destination,
                required vehicleType,
                headingDegrees,
                required avoidRoadIds,
                required maxDetourCandidates,
              }) {
                requests.add(Set.of(avoidRoadIds));
                origins.add(origin);
                destinations.add(destination);
                modes.add(vehicleType);
                return respond();
              },
        ),
      ),
    );
    if (firstFix) {
      await fix(tester);
      await tick(tester, 1);
    }
  }

  Future<void> showCriticalAlternative(WidgetTester tester) async {
    await predictRoad(85);
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    expect(displayedRoute, same(mainRoute.points));
    expect(
      find.text('Critical predicted risk: review required'),
      findsOneWidget,
    );
  }

  Future<void> openRiskReview(WidgetTester tester) async {
    await tester.tap(find.text('Review alternative'));
    await tester.pump(); // Start the modal's entrance animation.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Use reviewed alternative'), findsOneWidget);
  }

  Future<void> showStaging(WidgetTester tester) async {
    stagingSearch = (_) async => stagingOption();
    respond = () async => [mainRoute];
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Go to Test staging location'), findsOneWidget);
  }

  Future<void> chooseStaging(WidgetTester tester) async {
    await tester.tap(find.text('Go to Test staging location'));
    await tester.pump();
    if (find.text('Start with Caution').evaluate().isNotEmpty) {
      await tester.tap(find.text('Start with Caution'));
      await tester.pump();
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    unawaited(gps.close());
    await tester.pump();
  }

  setUp(() {
    gps = StreamController<geo.Position>();
    time = DateTime(2026, 1, 1);
    requests = [];
    origins = [];
    destinations = [];
    modes = [];
    speech = [];
    displayedRoute = [];
    respond = () async => [detour];
    stagingSearch = (_) async => null;
    app.roads.clear();
    RoutingService.instance.destinationPoint = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        if (call.method == 'speak') {
          speech.add(
            call.arguments is String
                ? call.arguments as String
                : (call.arguments as Map)['text'] as String,
          );
        }
        return 1;
      },
    );
  });

  testWidgets(
    'departure direction, live remaining estimates and details fit a narrow screen',
    (tester) async {
      final a = Position(120.980, 14.676),
          b = Position(120.976, 14.676),
          c = Position(120.976, 14.680);
      final west = PlannedRoute(
        points: [a, b, c],
        durationMin: 6,
        durationSeconds: 360,
        distanceMiles: 1,
        summary: 'Safe Detour',
        hazardAlerts: [],
        safetyStatus: 'safe',
        destinationName: 'Selected destination',
        vehicleType: 'Walking',
        steps: [
          RouteStep(
            instruction: 'Head west on this road',
            modifier: 'straight',
            type: 'depart',
            distance: 430,
            durationSeconds: 120,
            location: a,
          ),
          RouteStep(
            instruction: 'Turn right onto the next road',
            modifier: 'right',
            type: 'turn',
            distance: 445,
            durationSeconds: 240,
            location: b,
          ),
          RouteStep(
            instruction: 'Arrive',
            modifier: '',
            type: 'arrive',
            distance: 0,
            durationSeconds: 0,
            location: c,
          ),
        ],
      );
      await start(tester, initialRoute: west, width: 360, textScale: 1.5);
      expect(find.text('Head west on this road'), findsOneWidget);
      expect(find.text('Start in this direction'), findsOneWidget);
      expect(speech.any((s) => s.contains('Head west')), isTrue);
      expect(speech.any((s) => s.contains('In 200 meters')), isFalse);
      expect(find.text('6 min'), findsOneWidget);
      await fix(tester, lng: 120.978);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('Turn right onto the next road'), findsOneWidget);
      expect(speech.last, startsWith('In '));
      expect(speech.last, contains('Turn right onto the next road'));
      expect(find.text('Estimated time remaining'), findsOneWidget);
      await fix(tester, lng: 120.97603);
      expect(find.text('Turn now'), findsOneWidget);
      expect(find.text('In 0 meters'), findsNothing);
      await tester.tap(find.byTooltip('Trip details'));
      await tester.pumpAndSettle();
      expect(find.text('Destination: Selected destination'), findsOneWidget);
      expect(find.text('Travel mode: Walking'), findsOneWidget);
      expect(
        find.textContaining('does not include live traffic'),
        findsNothing,
      );
      await tester.ensureVisible(find.text('About estimates'));
      await tester.tap(find.text('About estimates'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not include live traffic'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await finish(tester);
    },
  );

  testWidgets(
    'remaining estimates are clearly paused when GPS becomes unreliable',
    (tester) async {
      await start(tester, width: 360, textScale: 1.5);
      expect(find.text('Estimated time remaining'), findsOneWidget);
      await fix(tester, accuracy: 200);
      expect(find.text('Estimates paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'a failed later calculation cannot retain an earlier success notice',
    (tester) async {
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(find.textContaining('Route updated to avoid A'), findsOneWidget);
      respond = () async => throw StateError('Synthetic route service failure');
      await closeRoad('B', 14.680);
      await tick(tester, 9);
      expect(requests.length, greaterThanOrEqualTo(2));
      expect(find.textContaining('Route updated to avoid A'), findsNothing);
      expect(find.textContaining('Route updated to avoid B'), findsNothing);
      expect(displayedRoute, same(detour.points));
      expect(find.text('Retry Now'), findsOneWidget);
      await finish(tester);
    },
  );

  for (final mode in ['Walking', 'Sedan']) {
    testWidgets(
      'Sudden closure warns and changes route while walking in $mode mode',
      (tester) async {
        RoutingService.instance.selectedVehicleType = mode;
        final result = Completer<List<PlannedRoute>>();
        respond = () => result.future;
        await start(tester);
        await closeRoad('A', 14.676);
        await tick(tester, 1);
        expect(requests, [
          {'A'},
        ]);
        expect(find.text('Guidance paused'), findsOneWidget);
        expect(find.text('Road ahead not passable'), findsOneWidget);
        expect(speech.any((s) => s.contains('Confirmed: A')), isTrue);
        result.complete([detour]);
        await tester.pump();
        expect(displayedRoute, same(detour.points));
        expect(find.textContaining('Route updated to avoid A'), findsOneWidget);
        expect(find.text('Guidance paused'), findsNothing);
        expect(find.textContaining('Confirmed: A'), findsNothing);
        expect(find.text('Road ahead not passable'), findsNothing);
        await finish(tester);
      },
    );
  }

  testWidgets(
    'near-closure pause labels the old route and rechecks only after sustained GPS clearance',
    (tester) async {
      respond = () async => [mainRoute];
      await start(tester);
      await app.updateRoadStatus(
        'AtOrigin',
        'not_passable',
        'Virtual closure at current location',
        name: 'Origin road',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.9799, 14.676],
            [120.9802, 14.676],
          ],
        },
      );
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(requests, hasLength(1));
      expect(find.text('Closure near your location'), findsWidgets);
      expect(
        find.text('Gray dashed line: previous route. Guidance is paused.'),
        findsOneWidget,
      );
      expect(find.text('Guidance paused'), findsOneWidget);
      final recovered = PlannedRoute(
        points: [
          Position(120.981, 14.676),
          Position(120.981, 14.680),
          Position(120.990, 14.680),
          Position(120.990, 14.676),
        ],
        durationMin: 8,
        distanceMiles: 1,
        summary: 'Checked alternative',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
        requestedDestination: Position(120.990, 14.676),
      );
      respond = () async => [recovered];
      // Accuracy uncertainty still overlaps the closure despite the point
      // being outside the ordinary 35 m intersection buffer.
      for (var i = 0; i < 3; i++) {
        await fix(tester, lng: 120.9808, accuracy: 60);
        await tick(tester, 3);
      }
      expect(requests, hasLength(1));
      await fix(tester, lng: 120.981);
      await tick(tester, 3);
      await fix(tester, lng: 120.981);
      expect(requests, hasLength(1));
      await tick(tester, 3);
      await fix(tester, lng: 120.981);
      await tester.pump();
      expect(requests, hasLength(2));
      expect(requests.last, contains('AtOrigin'));
      expect(origins.last.lng, 120.981);
      expect(destinations.last.lng, 120.990);
      expect(destinations.last.lat, 14.676);
      expect(displayedRoute, same(recovered.points));
      expect(find.text('Guidance paused'), findsNothing);
      expect(
        find.text('Gray dashed line: previous route. Guidance is paused.'),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'near-closure reference warning fits a short screen with large text',
    (tester) async {
      respond = () async => [mainRoute];
      await start(tester, width: 320, textScale: 2);
      tester.view.physicalSize = const Size(320, 800);
      await tester.pump();
      await app.updateRoadStatus(
        'AtOrigin',
        'not_passable',
        'Virtual current-position closure',
        name: 'Origin road',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.9799, 14.676],
            [120.9802, 14.676],
          ],
        },
      );
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Closure near your location'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Dismiss Warning'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gray dashed line: previous route. Guidance is paused.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('Closure received before GPS is checked on the first fix', (
    tester,
  ) async {
    await start(tester, firstFix: false);
    await closeRoad('A', 14.676);
    await tick(tester, 2);
    expect(requests, isEmpty);
    await fix(tester);
    await tick(tester, 1);
    expect(requests, [
      {'A'},
    ]);
    expect(displayedRoute, same(detour.points));
    await finish(tester);
  });

  testWidgets('Second flood during cooldown fires without another GPS fix', (
    tester,
  ) async {
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    respond = () async => [thirdRoute];
    await closeRoad('B', 14.680);
    await tick(tester, 1);
    expect(requests.length, 1);
    await tick(tester, 8);
    expect(requests.last, {'A', 'B'});
    expect(displayedRoute, same(thirdRoute.points));
    await finish(tester);
  });

  testWidgets(
    'Sidewalk and street entrance do not trigger; sustained deviation does',
    (tester) async {
      await start(tester);
      await fix(tester, lat: 14.6761);
      await tick(tester, 3);
      await fix(tester, lat: 14.6762);
      await tick(tester, 3);
      await fix(tester, lat: 14.6762);
      expect(requests, isEmpty);
      await fix(tester, lat: 14.677);
      await tick(tester, 3);
      await fix(tester, lat: 14.677);
      await tick(tester, 3);
      await fix(tester, lat: 14.677);
      expect(requests.length, 1);
      expect(displayedRoute, same(detour.points));
      await finish(tester);
    },
  );

  testWidgets(
    'No clear route shows a halt and does not adopt a blocked result',
    (tester) async {
      respond = () async => [mainRoute];
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No Clear Route Found'), findsOneWidget);
      expect(displayedRoute, same(mainRoute.points));
      expect(speech.any((s) => s.contains('New route found')), isFalse);
      await finish(tester);
    },
  );

  testWidgets(
    'Failed request retries after failure backoff, then adopts recovery',
    (tester) async {
      respond = () async => throw TimeoutException('simulated outage');
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(requests.length, 1);
      respond = () async => [detour];
      await tick(tester, 15);
      expect(requests.length, 1);
      await tick(tester, 1);
      expect(requests.length, 2);
      expect(displayedRoute, same(detour.points));
      await finish(tester);
    },
  );

  testWidgets('Queued closure reopening clears the warning without rerouting', (
    tester,
  ) async {
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    await closeRoad('B', 14.680);
    await tick(tester, 1);
    await app.updateRoadStatus('B', 'passable', 'Reopened');
    await tick(tester, 8);
    expect(requests.length, 1);
    expect(find.text('Road ahead not passable'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'Closure on a returned detour during the request triggers a fresh search',
    (tester) async {
      final first = Completer<List<PlannedRoute>>();
      respond = () => first.future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await closeRoad('B', 14.680);
      await tick(tester, 1);
      respond = () async => [thirdRoute];
      first.complete([detour]);
      await tester.pump();
      await tester.pump();
      expect(displayedRoute, same(mainRoute.points));
      await tick(tester, 8);
      expect(requests.length, 2);
      expect(requests.last, {'A', 'B'});
      expect(displayedRoute, same(thirdRoute.points));
      await finish(tester);
    },
  );

  testWidgets('Poor GPS accuracy does not invent an off-route event', (
    tester,
  ) async {
    await start(tester);
    for (var i = 0; i < 4; i++) {
      await fix(tester, lat: 14.677, accuracy: 80);
      await tick(tester, 3);
    }
    expect(requests, isEmpty);
    await finish(tester);
  });

  testWidgets('A hanging request times out and retries successfully', (
    tester,
  ) async {
    respond = () => Completer<List<PlannedRoute>>().future;
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    expect(find.text('Guidance paused'), findsOneWidget);
    await tick(tester, 18);
    expect(find.text('Guidance paused'), findsOneWidget);
    expect(find.text('Retry Now'), findsOneWidget);
    respond = () async => [detour];
    await fix(tester); // Recovery still requires a current, usable position.
    await tick(tester, 16);
    expect(requests.length, 2);
    expect(displayedRoute, same(detour.points));
    await finish(tester);
  });

  testWidgets(
    'Ending navigation during a request does not update a disposed screen',
    (tester) async {
      final result = Completer<List<PlannedRoute>>();
      respond = () => result.future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await finish(tester);
      result.complete([detour]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(speech.any((s) => s.contains('New route found')), isFalse);
    },
  );

  testWidgets(
    'poor GPS never becomes the origin of a closure reroute; recovery uses a fresh fix',
    (tester) async {
      await start(tester);
      await fix(tester, lng: 120.995, accuracy: 80);
      await closeRoad('A', 14.676);
      await tick(tester, 2);
      expect(requests, isEmpty);
      expect(find.text('Retry GPS'), findsOneWidget);
      await fix(tester);
      await tick(tester, 1);
      expect(requests, hasLength(1));
      expect(origins.single.lng, 120.980);
      expect(find.text('Retry GPS'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'Retry GPS consumes a one-shot fix without waiting for movement or another stream event',
    (tester) async {
      gps = StreamController<geo.Position>.broadcast();
      var calls = 0;
      await start(
        tester,
        firstFix: false,
        currentFix: () async {
          calls++;
          if (calls == 1) return null;
          return geo.Position(
            latitude: 14.676,
            longitude: 120.980,
            timestamp: time,
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        },
      );
      await tester.pump();
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(requests, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry GPS'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      expect(requests, hasLength(1));
      expect(origins.single.lng, 120.980);
      expect(find.text('Retry GPS'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'navigation keeps its selected destination and mode when the planner changes',
    (tester) async {
      RoutingService.instance.selectedVehicleType = 'Sedan';
      RoutingService.instance.destinationPoint = Position(120.900, 14.700);
      await start(tester);
      RoutingService.instance.selectedVehicleType = 'Walking';
      RoutingService.instance.destinationPoint = Position(120.950, 14.700);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(modes.single, 'Sedan');
      expect(destinations.single.lng, mainRoute.points.last.lng);
      expect(destinations.single.lat, mainRoute.points.last.lat);
      await finish(tester);
    },
  );
  testWidgets(
    'navigation seeds its initial GPS from a fresh one-shot without a stream event',
    (tester) async {
      await start(tester, firstFix: false, currentFix: () async => reading());
      await tester.pump();
      expect(find.text('Retry GPS'), findsNothing);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(requests, hasLength(1));
      expect(origins.single.lng, 120.980);
      await finish(tester);
    },
  );
  for (final scenario in ['accuracy', 'age', 'future']) {
    testWidgets(
      'one-shot GPS rejects $scenario problems with an explanation and preserves the queued closure',
      (tester) async {
        final sample = scenario == 'accuracy'
            ? reading(accuracy: 80)
            : reading(ageSeconds: scenario == 'age' ? 120 : -10);
        await start(tester, firstFix: false, currentFix: () async => sample);
        await tester.pump();
        expect(find.text('Retry GPS'), findsOneWidget);
        expect(
          find.textContaining(
            scenario == 'accuracy'
                ? '80 m'
                : scenario == 'age'
                ? '120 seconds old'
                : 'phone clock',
          ),
          findsOneWidget,
        );
        await closeRoad('A', 14.676);
        await tick(tester, 1);
        expect(requests, isEmpty);
        await fix(tester);
        await tick(tester, 1);
        expect(requests, hasLength(1));
        await finish(tester);
      },
    );
  }
  testWidgets(
    'GPS acquisition shows progress, suppresses duplicate retries and times out recoverably',
    (tester) async {
      final pending = Completer<geo.Position?>();
      var calls = 0;
      await start(
        tester,
        firstFix: false,
        currentFix: () {
          calls++;
          return pending.future;
        },
      );
      expect(find.text('Checking GPS...'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Checking GPS...'),
      );
      expect(button.onPressed, isNull);
      expect(calls, 1);
      await tick(tester, 21);
      expect(find.text('Retry GPS'), findsOneWidget);
      expect(find.textContaining('No current GPS fix'), findsOneWidget);
      expect(requests, isEmpty);
      pending.complete(null);
      await tester.pump();
      await finish(tester);
    },
  );
  for (final result in ['older fix', 'error']) {
    testWidgets(
      'a late one-shot $result cannot overwrite a newer reliable stream position',
      (tester) async {
        final pending = Completer<geo.Position?>();
        await start(tester, firstFix: false, currentFix: () => pending.future);
        await fix(tester);
        await tick(tester, 1);
        await fix(tester, lng: 120.9803);
        if (result == 'error') {
          pending.completeError(StateError('Synthetic provider error'));
        } else {
          pending.complete(reading(lng: 120.9799, ageSeconds: 1));
        }
        await tester.pump();
        expect(find.text('Retry GPS'), findsNothing);
        await closeRoad('A', 14.676);
        await tick(tester, 1);
        expect(requests, hasLength(1));
        expect(origins.single.lng, closeTo(120.9803, 0.000001));
        await finish(tester);
      },
    );
  }
  testWidgets(
    'stationary fresh stream fixes keep GPS usable without fabricated movement',
    (tester) async {
      await start(tester);
      for (var i = 0; i < 8; i++) {
        await tick(tester, 5);
        await fix(tester);
      }
      expect(find.text('Retry GPS'), findsNothing);
      expect(requests, isEmpty);
      expect(find.text('You Have Arrived!'), findsNothing);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(requests, hasLength(1));
      await finish(tester);
    },
  );
  testWidgets(
    'an older one-shot cannot recover GPS after a newer stream fix becomes unreliable',
    (tester) async {
      final pending = Completer<geo.Position?>();
      await start(tester, firstFix: false, currentFix: () => pending.future);
      await fix(tester, lng: 120.9803);
      await tick(tester, 1);
      await fix(tester, lng: 120.995, accuracy: 80);
      pending.complete(reading(lng: 120.979, ageSeconds: 2));
      await tester.pump();
      await tester
          .pump(); // Render the retry completion after its continuation.
      expect(find.text('Retry GPS'), findsOneWidget);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(requests, isEmpty);
      await fix(tester, lng: 120.9803);
      await tick(tester, 1);
      expect(requests, hasLength(1));
      expect(origins.single.lng, closeTo(120.9803, 0.000001));
      await finish(tester);
    },
  );
  testWidgets(
    'a disposed navigation ignores the in-flight one-shot GPS result',
    (tester) async {
      final pending = Completer<geo.Position?>();
      await start(tester, firstFix: false, currentFix: () => pending.future);
      await tester.pumpWidget(const SizedBox());
      pending.complete(reading());
      await tester.pump();
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
      unawaited(gps.close());
      await tester.pump();
    },
  );
  testWidgets('an outdated arrival fix cannot finish the trip', (tester) async {
    await start(tester, firstFix: false);
    gps.add(
      geo.Position(
        latitude: 14.676,
        longitude: 120.990,
        timestamp: time.subtract(const Duration(minutes: 2)),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(speech.any((s) => s.contains('reached')), false);
    expect(find.text('Retry GPS'), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
    'a GPS stream error pauses rerouting and can resume after retry',
    (tester) async {
      gps = StreamController<geo.Position>.broadcast();
      await start(tester);
      gps.addError(StateError('Synthetic GPS interruption'));
      await tester.pump();
      await closeRoad('A', 14.676);
      await tick(tester, 2);
      expect(requests, isEmpty);
      // Subscription cancellation can complete outside the widget fake clock.
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry GPS'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      expect(gps.hasListener, isTrue);
      await fix(tester);
      expect(find.text('Retry GPS'), findsNothing);
      await tick(tester, 1);
      expect(requests, hasLength(1));
      await finish(tester);
    },
  );
  testWidgets(
    'stale GPS after a timeout does not start another request until reliable telemetry returns',
    (tester) async {
      respond = () => Completer<List<PlannedRoute>>().future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await tick(tester, 18);
      respond = () async => [detour];
      await tick(tester, 16);
      expect(requests, hasLength(1));
      expect(find.text('Retry GPS'), findsOneWidget);
      await fix(tester);
      await tick(tester, 8);
      expect(requests, hasLength(2));
      expect(displayedRoute, same(detour.points));
      await finish(tester);
    },
  );
  testWidgets(
    'a result that no longer joins the current GPS position is discarded and recomputed',
    (tester) async {
      final response = Completer<List<PlannedRoute>>();
      respond = () => response.future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await fix(tester, lng: 120.999, lat: 14.679);
      final fresh = PlannedRoute(
        points: [
          Position(120.999, 14.679),
          Position(120.999, 14.683),
          Position(120.990, 14.683),
          Position(120.990, 14.676),
        ],
        durationMin: 10,
        distanceMiles: 1,
        summary: 'Fresh origin',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      respond = () async => [fresh];
      response.complete([detour]);
      await tester.pump();
      await tester.pump();
      expect(displayedRoute, same(mainRoute.points));
      await tick(tester, 8);
      expect(requests, hasLength(2));
      expect(origins.last.lng, 120.999);
      expect(displayedRoute, same(fresh.points));
      await finish(tester);
    },
  );
  testWidgets(
    'a stale-origin candidate cannot be adopted merely because another alternative joins current GPS',
    (tester) async {
      final response = Completer<List<PlannedRoute>>();
      respond = () => response.future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await fix(tester, lng: 120.999, lat: 14.679);
      final joining = PlannedRoute(
        points: [
          Position(120.999, 14.679),
          Position(120.999, 14.683),
          Position(120.990, 14.683),
          Position(120.990, 14.676),
        ],
        durationMin: 10,
        distanceMiles: 10,
        routeCost: 99999,
        summary: 'Connected alternative',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      response.complete([detour, joining]);
      await tester.pump();
      await tester.pump();
      expect(requests, hasLength(1));
      expect(displayedRoute, same(joining.points));
      await finish(tester);
    },
  );
  testWidgets('an unrelated closure does not recalculate this trip', (
    tester,
  ) async {
    await start(tester);
    await closeRoad('Elsewhere', 14.690);
    await tick(tester, 2);
    expect(requests, isEmpty);
    expect(displayedRoute, same(mainRoute.points));
    expect(find.text('Road ahead not passable'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'a resolved unconfirmed road removes its advisory without a reroute',
    (tester) async {
      final geometry = {
        'type': 'LineString',
        'coordinates': [
          [120.984, 14.676],
          [120.986, 14.676],
        ],
      };
      app.roads.add(
        RoadStatus(
          id: 'Unconfirmed',
          name: 'Unconfirmed road',
          status: 'passable',
          notes: '',
          updatedAt: time,
          communityCondition: 'outdated',
          geometry: geometry,
        ),
      );
      await start(tester);
      expect(find.text('1 road segment unconfirmed'), findsOneWidget);
      app.roads[0] = RoadStatus(
        id: 'Unconfirmed',
        name: 'Unconfirmed road',
        status: 'passable',
        notes: 'Confirmed',
        updatedAt: time,
        geometry: geometry,
        isVerified: true,
      );
      await app.updateRoadStatus('Unconfirmed', 'passable', 'Confirmed');
      await tick(tester, 1);
      expect(find.text('1 road segment unconfirmed'), findsNothing);
      expect(requests, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'a fresh timestamp alone cannot clear an unresolved community advisory',
    (tester) async {
      app.roads.add(
        RoadStatus(
          id: 'Unconfirmed',
          name: 'Unconfirmed road',
          status: 'passable',
          notes: '',
          updatedAt: time,
          communityCondition: 'under_verification',
          geometry: {
            'type': 'LineString',
            'coordinates': [
              [120.984, 14.676],
              [120.986, 14.676],
            ],
          },
        ),
      );
      await start(tester);
      await app.updateRoadStatus(
        'Unconfirmed',
        'passable',
        'Timestamp refreshed only',
      );
      await tick(tester, 1);
      expect(find.text('1 road segment unconfirmed'), findsOneWidget);
      expect(requests, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'the first failed closure reroute shows a persistent warning and retry',
    (tester) async {
      respond = () async =>
          throw TimeoutException('Synthetic unavailable route');
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(find.text('Road ahead not passable'), findsOneWidget);
      expect(find.text('Retry Now'), findsOneWidget);
      expect(displayedRoute, same(mainRoute.points));
      expect(speech.any((s) => s.contains('Continuing on last route')), false);
      await finish(tester);
    },
  );

  testWidgets(
    'an off-route service error is visible without falsely claiming offline or a checked old route',
    (tester) async {
      respond = () async => throw StateError('Synthetic route service failure');
      await start(tester);
      await fix(tester, lat: 14.679, lng: 120.995);
      await tick(tester, 3);
      await fix(tester, lat: 14.679, lng: 120.995);
      await tick(tester, 3);
      await fix(tester, lat: 14.679, lng: 120.995);
      expect(requests, hasLength(1));
      expect(find.text('Could not update route'), findsOneWidget);
      expect(find.text('OFFLINE MODE'), findsNothing);
      expect(
        find.textContaining('previous route is shown for reference'),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'a reopening waits through unusable GPS and resumes the pending check after recovery',
    (tester) async {
      respond = () async => [mainRoute];
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No Clear Route Found'), findsOneWidget);
      await fix(tester, accuracy: 80);
      await app.updateRoadStatus('A', 'passable', 'Reopened');
      await tick(tester, 1);
      expect(requests, hasLength(1));
      expect(find.text('No Clear Route Found'), findsOneWidget);
      respond = () async => [detour];
      await fix(tester);
      await tester.pump();
      expect(requests, hasLength(2));
      expect(requests.last, isEmpty);
      expect(find.text('No Clear Route Found'), findsNothing);
      expect(displayedRoute, same(detour.points));
      await finish(tester);
    },
  );

  testWidgets(
    'a staging option is rechecked against a closure received just before the button press',
    (tester) async {
      await showStaging(tester);
      await closeRoad('B', 14.682);
      await tester.tap(find.text('Go to Test staging location'));
      await tester.pump();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.textContaining('Road conditions changed. Refresh staging options'),
        findsOneWidget,
      );
      expect(find.text('Go to Test staging location'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'a closure between staging caution review and confirmation prevents adoption',
    (tester) async {
      await showStaging(tester);
      await tester.tap(find.text('Go to Test staging location'));
      await tester.pump();
      expect(find.text('Start with Caution'), findsOneWidget);
      await closeRoad('B', 14.682);
      await tester.tap(find.text('Start with Caution'));
      await tester.pump();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.textContaining('Road conditions changed. Refresh staging options'),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets('a staging option cannot start after GPS becomes unusable', (
    tester,
  ) async {
    await showStaging(tester);
    await fix(tester, accuracy: 80);
    await tester.tap(find.text('Go to Test staging location'));
    await tester.pump();
    expect(displayedRoute, same(mainRoute.points));
    expect(
      find.text('A reliable GPS fix is needed before starting this route.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets(
    'moving away from a suggested staging path requires refreshed options from current GPS',
    (tester) async {
      await showStaging(tester);
      await fix(tester, lat: 14.679, lng: 120.999);
      await tester.tap(find.text('Go to Test staging location'));
      await tester.pump();
      expect(displayedRoute, same(mainRoute.points));
      expect(find.textContaining('Your position changed.'), findsOneWidget);
      Position? searchedFrom;
      final connected = PlannedRoute(
        points: [
          Position(120.999, 14.679),
          Position(120.999, 14.682),
          stagingRoute.points.last,
        ],
        durationMin: 5,
        distanceMiles: 1,
        summary: 'Fresh staging path',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      stagingSearch = (origin) async {
        searchedFrom = origin;
        return stagingOption(connected);
      };
      await tester.tap(find.text('Refresh staging options'));
      await tester.pump();
      await tester.pump();
      expect(searchedFrom!.lng, 120.999);
      await chooseStaging(tester);
      expect(displayedRoute, same(connected.points));
      await finish(tester);
    },
  );

  testWidgets(
    'a chosen staging location remains the destination after a later wrong turn',
    (tester) async {
      await showStaging(tester);
      await chooseStaging(tester);
      expect(displayedRoute, same(stagingRoute.points));
      respond = () async => [
        PlannedRoute(
          points: [
            Position(120.995, 14.679),
            Position(120.995, 14.682),
            stagingRoute.points.last,
          ],
          durationMin: 5,
          distanceMiles: 1,
          summary: '',
          hazardAlerts: [],
          safetyStatus: 'safe',
          steps: [],
        ),
      ];
      await fix(tester, lat: 14.679, lng: 120.995);
      await tick(tester, 4);
      await fix(tester, lat: 14.679, lng: 120.995);
      await tick(tester, 4);
      await fix(tester, lat: 14.679, lng: 120.995);
      expect(requests, hasLength(2));
      expect(destinations.last.lat, 14.682);
      expect(destinations.last.lng, 120.990);
      await finish(tester);
    },
  );

  testWidgets(
    'a late staging result cannot resurrect a dialog closed by a reopened road',
    (tester) async {
      final result = Completer<Map<String, dynamic>?>();
      stagingSearch = (_) => result.future;
      respond = () async => [mainRoute];
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Checking listed staging locations...'), findsOneWidget);
      respond = () async => [detour];
      await app.updateRoadStatus('A', 'passable', 'Reopened');
      await tick(tester, 1);
      result.complete(stagingOption());
      await tester.pump();
      expect(requests, hasLength(2));
      expect(displayedRoute, same(detour.points));
      expect(find.text('Go to Test staging location'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('a later valid reroute closes obsolete halt and staging UI', (
    tester,
  ) async {
    await showStaging(tester);
    respond = () async => [detour];
    await closeRoad('C', 14.676);
    await tick(tester, 9);
    await tester.pump();
    expect(requests, hasLength(2));
    expect(displayedRoute, same(detour.points));
    expect(find.text('No Clear Route Found'), findsNothing);
    expect(find.text('Go to Test staging location'), findsNothing);
    await finish(tester);
  });

  testWidgets('a staging search timeout leaves an honest recovery state', (
    tester,
  ) async {
    stagingSearch = (_) => Completer<Map<String, dynamic>?>().future;
    respond = () async => [mainRoute];
    await start(tester);
    await closeRoad('A', 14.676);
    await tick(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await tick(tester, 22);
    expect(find.text('Checking listed staging locations...'), findsNothing);
    expect(
      find.textContaining('Staging options could not be checked.'),
      findsOneWidget,
    );
    expect(find.text('Refresh staging options'), findsOneWidget);
    expect(displayedRoute, same(mainRoute.points));
    await finish(tester);
  });

  testWidgets(
    'critical-only alternatives are not adopted automatically and do not announce continued navigation',
    (tester) async {
      await showCriticalAlternative(tester);
      expect(requests, hasLength(1));
      expect(speech.any((s) => s.contains('New route found')), false);
      await fix(tester, lng: 120.990);
      expect(find.text('You Have Arrived!'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'critical review actions remain reachable on a narrow screen with large text',
    (tester) async {
      await predictRoad(85);
      await start(tester, width: 360, textScale: 1.5);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await openRiskReview(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel review'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'a noncritical alternative is preferred even when a critical candidate has lower cost',
    (tester) async {
      await predictRoad(85);
      final expensive = RoutingService.instance
          .refreshRoute(thirdRoute)
          .copyWith(routeCost: 999999);
      respond = () async => [detour, expensive];
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(displayedRoute, same(thirdRoute.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'cancelling a critical alternative review restores the previous map and keeps guidance paused',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      expect(displayedRoute, same(detour.points));
      expect(
        find.text('Alternative preview — guidance paused'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel review'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsOneWidget,
      );
      await fix(tester, lng: 120.990);
      expect(find.text('You Have Arrived!'), findsNothing);
      expect(speech.any((s) => s.contains('New route found')), false);
      await finish(tester);
    },
  );

  testWidgets(
    'explicit current critical-risk review can adopt the alternative without claiming automatic safety',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      await tester.tap(find.text('Use reviewed alternative'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(detour.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      expect(
        speech.any((s) => s.contains('Reviewed alternative selected')),
        true,
      );
      expect(speech.any((s) => s.contains('New route found')), false);
      await app.updateRoadStatus(
        'Predicted',
        'passable',
        'Unchanged reviewed conditions',
      );
      await tick(tester, 1);
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'a closure arriving during critical review prevents confirmation from adopting the alternative',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      await closeRoad('B', 14.680);
      await tester.tap(find.text('Use reviewed alternative'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.textContaining('Conditions or your location changed.'),
        findsOneWidget,
      );
      expect(
        speech.any((s) => s.contains('Reviewed alternative selected')),
        false,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'a changed critical prediction requires another review instead of using an old acknowledgement',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      await predictRoad(90);
      await tester.tap(find.text('Use reviewed alternative'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(mainRoute.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsOneWidget,
      );
      expect(
        speech.any((s) => s.contains('Reviewed alternative selected')),
        false,
      );
      await finish(tester);
    },
  );

  testWidgets('losing reliable GPS during critical review prevents adoption', (
    tester,
  ) async {
    await showCriticalAlternative(tester);
    await openRiskReview(tester);
    await fix(tester, accuracy: 80);
    await tester.tap(find.text('Use reviewed alternative'));
    await tester.pumpAndSettle();
    expect(displayedRoute, same(mainRoute.points));
    expect(
      find.text('Critical predicted risk: review required'),
      findsOneWidget,
    );
    expect(
      speech.any((s) => s.contains('Reviewed alternative selected')),
      false,
    );
    await finish(tester);
  });

  testWidgets(
    'movement during critical review requires a fresh route and retry uses current GPS',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      await fix(tester, lng: 120.999, lat: 14.679);
      await tester.tap(find.text('Use reviewed alternative'));
      await tester.pumpAndSettle();
      expect(displayedRoute, same(mainRoute.points));
      final connected = PlannedRoute(
        points: [
          Position(120.999, 14.679),
          Position(120.999, 14.683),
          Position(120.990, 14.683),
          mainRoute.points.last,
        ],
        durationMin: 8,
        distanceMiles: 1,
        summary: '',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      respond = () async => [connected];
      await tester.tap(find.text('Retry route'));
      await tester.pump();
      await tester.pump();
      expect(origins.last.lng, 120.999);
      expect(displayedRoute, same(connected.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'a cleared prediction triggers a fresh noncritical route check and resumes after adoption',
    (tester) async {
      await showCriticalAlternative(tester);
      await predictRoad(0);
      await tick(tester, 8);
      expect(requests, hasLength(2));
      expect(displayedRoute, same(detour.points));
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      expect(speech.any((s) => s.contains('New route found')), true);
      await finish(tester);
    },
  );

  testWidgets(
    'initial critical routes require a matching review key and later escalation pauses them again',
    (tester) async {
      await predictRoad(85);
      final admission = RoutingService.instance.navigationAdmission(detour);
      await start(
        tester,
        initialRoute: admission.route,
        reviewedRiskKey: admission.key,
      );
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      await predictRoad(90);
      await tick(tester, 1);
      expect(
        find.text('Critical predicted risk: review required'),
        findsOneWidget,
      );
      expect(speech.any((s) => s.contains('New route found')), false);
      await finish(tester);
    },
  );

  testWidgets(
    'closing navigation while critical review is open cannot adopt its preview later',
    (tester) async {
      await showCriticalAlternative(tester);
      await openRiskReview(tester);
      await finish(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        speech.any((s) => s.contains('Reviewed alternative selected')),
        false,
      );
    },
  );

  testWidgets('turn instructions wait for a usable GPS fix', (tester) async {
    final withSteps = PlannedRoute(
      points: mainRoute.points,
      durationMin: 5,
      distanceMiles: 1,
      summary: 'Step route',
      hazardAlerts: [],
      safetyStatus: 'safe',
      steps: [
        RouteStep(
          instruction: 'Turn onto the planned street',
          modifier: 'right',
          type: 'turn',
          distance: 200,
          location: Position(120.985, 14.676),
        ),
      ],
    );
    await start(tester, firstFix: false, initialRoute: withSteps);
    expect(speech.any((s) => s.contains('Turn onto')), false);
    await fix(tester, accuracy: 80);
    expect(speech.any((s) => s.contains('Turn onto')), false);
    await fix(tester);
    await tester.pump();
    expect(speech.any((s) => s.contains('Turn onto')), true);
    await finish(tester);
  });

  PlannedRoute routeWithInstruction() => PlannedRoute(
    points: mainRoute.points,
    durationMin: 10,
    distanceMiles: 1,
    hazardAlerts: [],
    summary: 'Instruction test route',
    safetyStatus: 'safe',
    steps: [
      RouteStep(
        instruction: 'Continue toward the planned street',
        modifier: 'straight',
        type: 'depart',
        distance: 1000,
        location: mainRoute.points.first,
      ),
    ],
  );

  testWidgets(
    'closure and GPS loss share one status and never keep the old maneuver',
    (tester) async {
      final pending = Completer<List<PlannedRoute>>();
      respond = () => pending.future;
      await start(
        tester,
        initialRoute: routeWithInstruction(),
        width: 360,
        textScale: 1.5,
      );
      expect(find.text('Continue toward the planned street'), findsOneWidget);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(find.text('Continue toward the planned street'), findsNothing);
      expect(find.byKey(const ValueKey('navigation-status')), findsOneWidget);
      expect(find.text('Previous route estimate'), findsOneWidget);
      expect(find.textContaining('Arrival:'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await fix(tester, accuracy: 200);
      expect(find.text('Guidance paused'), findsOneWidget);
      expect(find.text('Road ahead not passable'), findsOneWidget);
      expect(find.text('Retry GPS'), findsOneWidget);
      expect(
        find.textContaining('Waiting for GPS before checking'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('navigation-status')), findsOneWidget);
      final footer = tester.getRect(
        find.byKey(const ValueKey('navigation-trip-panel')),
      );
      expect(
        tester.getRect(find.byTooltip('Recenter')).bottom,
        lessThan(footer.top),
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
      pending.complete([detour]);
      await tester.pump();
    },
  );

  testWidgets(
    'fast reroute has a readable success notice and retains its reason in trip details',
    (tester) async {
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      expect(find.text('Route updated'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tick(tester, 4);
      expect(find.text('Route updated'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('Route updated'), findsNothing);
      await tester.tap(find.byTooltip('Trip details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Route updated to avoid A'), findsOneWidget);
      expect(find.textContaining('Updated at'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('GPS-only pause uses one card and no duplicate warning', (
    tester,
  ) async {
    await start(tester, initialRoute: routeWithInstruction());
    await fix(tester, accuracy: 150);
    expect(find.text('Guidance paused'), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-status')), findsNothing);
    expect(find.text('Continue toward the planned street'), findsNothing);
    expect(find.text('Estimates paused'), findsOneWidget);
    expect(find.textContaining('Arrival:'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'failed closure retry remains paused and cannot speak old turns',
    (tester) async {
      respond = () async => throw StateError('Synthetic failed request');
      await start(tester, initialRoute: routeWithInstruction());
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      final speechCount = speech.length;
      await fix(tester, lng: 120.9801);
      expect(find.text('Continue toward the planned street'), findsNothing);
      expect(find.text('Guidance paused'), findsOneWidget);
      expect(
        find.textContaining('previous route contains a confirmed hazard'),
        findsOneWidget,
      );
      expect(
        speech
            .skip(speechCount)
            .any((value) => value.contains('Continue toward')),
        isFalse,
      );
      expect(find.text('Retry Now'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'dismissed no-clear-route dialog retains a pause and a way back to options',
    (tester) async {
      respond = () async => [mainRoute];
      await start(tester, initialRoute: routeWithInstruction());
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Dismiss Warning'));
      await tester.pumpAndSettle();
      expect(find.text('No clear route found'), findsOneWidget);
      expect(find.text('Guidance paused'), findsOneWidget);
      expect(find.text('Continue toward the planned street'), findsNothing);
      expect(find.text('View options'), findsOneWidget);
      await tester.tap(find.text('View options'));
      await tester.pumpAndSettle();
      expect(find.text('No Clear Route Found'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('audit: detour survives GPS loss while the request is pending', (
    tester,
  ) async {
    app.roads.add(
      RoadStatus(
        id: 'Unconfirmed',
        name: 'Unconfirmed road',
        status: 'passable',
        notes: '',
        updatedAt: time,
        communityCondition: 'under_verification',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.984, 14.676],
            [120.986, 14.676],
          ],
        },
      ),
    );
    final pending = Completer<List<PlannedRoute>>();
    respond = () => pending.future;
    await start(tester);
    await tester.tap(find.text('View conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find detour'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(requests, hasLength(1));
    expect(requests.single, contains('Unconfirmed'));
    await fix(tester, accuracy: 200);
    respond = () async => [detour];
    pending.complete([detour]);
    await tester.pump();
    await tester.pump();
    await fix(tester);
    await tick(tester, 8);
    expect(requests, hasLength(2));
    expect(requests.last, contains('Unconfirmed'));
    expect(displayedRoute, same(detour.points));
    await finish(tester);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'audit: unresolved closure cannot become arrival, failed=$failed',
      (tester) async {
        final pending = Completer<List<PlannedRoute>>();
        respond = failed
            ? () async => throw StateError('Synthetic route failure')
            : () => pending.future;
        await start(tester);
        await closeRoad('A', 14.676);
        await tick(tester, 1);
        await fix(tester, lng: 120.990);
        expect(find.text('You Have Arrived!'), findsNothing);
        expect(find.text('Road ahead not passable'), findsOneWidget);
        expect(
          speech.any((value) => value.contains('reached the end')),
          isFalse,
        );
        await finish(tester);
        if (!failed) {
          pending.complete([detour]);
          await tester.pump();
        }
      },
    );
  }

  testWidgets(
    'audit: critical prediction behind progress does not interrupt the remaining trip',
    (tester) async {
      final pending = Completer<List<PlannedRoute>>();
      respond = () => pending.future;
      await start(tester);
      await fix(tester, lng: 120.988);
      app.roads.add(
        RoadStatus(
          id: 'Behind',
          name: 'Already travelled road',
          status: 'passable',
          notes: 'Synthetic prediction',
          updatedAt: time,
          riskScore: 85,
          geometry: {
            'type': 'LineString',
            'coordinates': [
              [120.984, 14.676],
              [120.986, 14.676],
            ],
          },
        ),
      );
      await app.updateRoadStatus('Behind', 'passable', 'Synthetic prediction');
      await tick(tester, 1);
      expect(
        find.text('Critical predicted risk: review required'),
        findsNothing,
      );
      expect(find.text('Guidance paused'), findsNothing);
      expect(requests, isEmpty);
      await finish(tester);
      pending.complete([detour]);
      await tester.pump();
    },
  );

  testWidgets(
    'audit: open trip details receives a closure and its calculation result',
    (tester) async {
      final pending = Completer<List<PlannedRoute>>();
      respond = () => pending.future;
      await start(tester);
      await tester.tap(find.byTooltip('Trip details'));
      await tester.pumpAndSettle();
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Road ahead not passable'),
        ),
        findsOneWidget,
      );
      pending.complete([detour]);
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining('Route updated to avoid A'),
        ),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets('audit: a current normal trip can still complete its arrival', (
    tester,
  ) async {
    await start(tester);
    await fix(tester, lng: 120.990);
    expect(find.text('You Have Arrived!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(
      speech.where((value) => value.contains('reached the end')),
      hasLength(1),
    );
    await fix(tester, lng: 120.990);
    expect(
      speech.where((value) => value.contains('reached the end')),
      hasLength(1),
    );
    await finish(tester);
  });

  testWidgets(
    'audit: new critical prediction ahead still pauses and checks alternatives',
    (tester) async {
      final pending = Completer<List<PlannedRoute>>();
      respond = () => pending.future;
      await start(tester);
      await fix(tester, lng: 120.982);
      app.roads.add(
        RoadStatus(
          id: 'Ahead',
          name: 'Road ahead',
          status: 'passable',
          notes: 'Synthetic prediction',
          updatedAt: time,
          riskScore: 85,
          geometry: {
            'type': 'LineString',
            'coordinates': [
              [120.984, 14.676],
              [120.986, 14.676],
            ],
          },
        ),
      );
      await app.updateRoadStatus('Ahead', 'passable', 'Synthetic prediction');
      await tick(tester, 1);
      expect(
        find.text('Critical predicted risk: review required'),
        findsOneWidget,
      );
      expect(find.text('Guidance paused'), findsOneWidget);
      expect(requests, hasLength(1));
      await finish(tester);
      pending.complete([detour]);
      await tester.pump();
    },
  );

  testWidgets('audit: manual retry retains the requested detour exclusions', (
    tester,
  ) async {
    app.roads.add(
      RoadStatus(
        id: 'Unconfirmed',
        name: 'Unconfirmed road',
        status: 'passable',
        notes: '',
        updatedAt: time,
        communityCondition: 'under_verification',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.984, 14.676],
            [120.986, 14.676],
          ],
        },
      ),
    );
    respond = () async => throw StateError('Synthetic detour failure');
    await start(tester);
    await tester.tap(find.text('View conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find detour'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    respond = () async => [detour];
    await tester.tap(find.text('Retry Now'));
    await tester.pump();
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests.last, contains('Unconfirmed'));
    expect(displayedRoute, same(detour.points));
    await finish(tester);
  });

  testWidgets(
    'audit: stale weather remains visible even on a route without road warnings',
    (tester) async {
      final weather = SimulatedWeatherService.instance;
      final override = weather.isOverrideMode,
          lastFetch = weather.lastSuccessfulFetch;
      weather.isOverrideMode = false;
      weather.lastSuccessfulFetch = null;
      addTearDown(() {
        weather.isOverrideMode = override;
        weather.lastSuccessfulFetch = lastFetch;
      });
      final area = AppEnvironment.area;
      final route = PlannedRoute(
        points: [
          Position(area.longitude, area.latitude),
          Position(area.longitude + .002, area.latitude),
        ],
        durationMin: 3,
        distanceMiles: .15,
        summary: 'No known road warnings',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      await start(tester, firstFix: false, initialRoute: route);
      await fix(tester, lng: area.longitude, lat: area.latitude);
      expect(find.text('Live conditions need confirmation'), findsOneWidget);
      expect(find.text('Guidance paused'), findsNothing);
      expect(find.text('View conditions'), findsOneWidget);
      expect(requests, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'audit: a failed request after ending the trip cannot speak into the next screen',
    (tester) async {
      final pending = Completer<List<PlannedRoute>>();
      respond = () => pending.future;
      await start(tester);
      await closeRoad('A', 14.676);
      await tick(tester, 1);
      await finish(tester);
      final speechCount = speech.length;
      pending.completeError(StateError('Late request failure'));
      await tester.pump();
      await tester.pump();
      expect(speech, hasLength(speechCount));
      expect(tester.takeException(), isNull);
    },
  );
}
