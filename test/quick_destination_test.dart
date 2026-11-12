import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/data/marulas_landmarks.dart';
import 'package:safepaths_app/screens/user/route_planner_screen.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/mapbox_place_search.dart';
import 'package:safepaths_app/services/weather_service.dart';

void main() {
  final routing = RoutingService.instance;
  final category = QuickDestinationCategory.values;
  const labels = [
    'Hospitals',
    'Evac Centers',
    'Barangay Hall',
    'Emergency/Police',
  ];
  Position point(double dx, double dy) => Position(
    AppEnvironment.area.longitude + dx,
    AppEnvironment.area.latitude + dy,
  );
  MarulasLandmark place(
    String id,
    String name,
    QuickDestinationCategory? group, {
    double dx = 0.001,
  }) => MarulasLandmark(
    id: id,
    name: name,
    category: 'Test catalog',
    address: 'Synthetic address',
    lat: point(dx, 0).lat.toDouble(),
    lng: point(dx, 0).lng.toDouble(),
    tags: ['hospital', 'barangay', 'evacuation', 'police'],
    quickCategories: group == null ? {} : {group},
  );
  List<MarulasLandmark> fixtures() => [
    place('hospital', 'Test Hospital', category[0]),
    place('clinic', 'Test Clinic', null),
    place('pharmacy', 'Test Pharmacy', null),
    place('shelter', 'Test Shelter', category[1]),
    place('hall', 'Test Barangay Hall', category[2]),
    place('fire', 'Test Fire Station', category[3]),
    place('police', 'Test Police Station', category[3]),
    place('rescue', 'Test Rescue Office', category[3]),
  ];
  late List<Position> requested;
  late List<String> reviewed;
  late Future<Position?> Function(MarulasLandmark) picker;
  late Future<List<MapboxPlace>> Function(String, List<String>) lookup;

  String encode(List<Position> points) {
    var lat = 0, lng = 0;
    final out = StringBuffer();
    void write(int difference) {
      var v = difference < 0 ? ~(difference << 1) : difference << 1;
      while (v >= 32) {
        out.writeCharCode((32 | (v & 31)) + 63);
        v >>= 5;
      }
      out.writeCharCode(v + 63);
    }

    for (final p in points) {
      final a = (p.lat * 1e5).round(), b = (p.lng * 1e5).round();
      write(a - lat);
      write(b - lng);
      lat = a;
      lng = b;
    }
    return out.toString();
  }

  Future<void> start(
    WidgetTester tester, {
    bool realCatalog = false,
    bool gps = true,
    double width = 1080,
    double textScale = 1,
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
        home: RoutePlannerScreen(
          locate: () async => gps ? point(-0.001, 0) : null,
          placeLookup: (query, names) => lookup(query, names),
          quickLandmarks: realCatalog ? null : fixtures(),
          quickDestinationPicker: (context, selected) {
            reviewed.add(selected.name);
            return picker(selected);
          },
          routeMapBuilder: (_) => const SizedBox.expand(),
          directionsFetcher:
              (
                origin,
                destination, {
                waypoints = const [],
                vehicleType = 'Sedan',
                headingDeg,
              }) async {
                requested.add(destination);
                return [
                  {
                    'geometry': encode([origin, destination]),
                    'distance': 500,
                    'duration': 120,
                    'legs': [],
                  },
                ];
              },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump();
  }

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(
      envString:
          'NAVIGATION_TEST=true\nMAPBOX_ACCESS_TOKEN=pk.synthetic-no-network',
    );
    SimulatedWeatherService.instance;
  });
  setUp(() {
    routing.exitPlanning();
    requested = [];
    reviewed = [];
    picker = (selected) async => Position(selected.lng, selected.lat);
    lookup = (_, __) async => throw const MapboxPlaceSearchUnavailable();
  });
  tearDown(() => routing.exitPlanning());
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  final expected = [
    {'fumc'},
    <String>{},
    <String>{},
    <String>{},
  ];
  for (var i = 0; i < category.length; i++) {
    test(
      '${labels[i]} uses explicit category membership instead of broad descriptive tags',
      () {
        final matches = MarulasLandmarksCatalog.quickDestinations(
          category[i],
          MarulasLandmarksCatalog.all,
          isInScope: (_, _) => true,
        );
        expect(matches.map((p) => p.id).toSet(), expected[i]);
      },
    );
  }
  test(
    'unresolved facility pins cannot leak through search or popular picks',
    () {
      final held = MarulasLandmarksCatalog.all
          .where((p) => !p.routingAvailable)
          .toList();
      expect(held.map((p) => p.id).toSet(), {
        'marulas_health_center',
        'marulas_central_school',
        'constantino_elem_school',
        'red_cross_valenzuela',
        'marulas_elem_school',
        'san_lorenzo_school',
        'marulas_brgy_hall',
        'marulas_3s_center',
        'police_station_3',
        'fire_station_marulas',
      });
      for (final query in [
        'hospital',
        'school',
        'police',
        'fire',
        'red cross',
        '3s',
        'hall',
      ]) {
        expect(
          MarulasLandmarksCatalog.search(
            query,
          ).every((p) => p.routingAvailable),
          isTrue,
        );
      }
      expect(
        MarulasLandmarksCatalog.popularQuickPicks.every(
          (p) => p.routingAvailable,
        ),
        isTrue,
      );
      expect(
        MarulasLandmarksCatalog.all.any(
          (p) => p.quickCategories.contains(
            QuickDestinationCategory.evacuationCenters,
          ),
        ),
        isFalse,
      );
    },
  );
  test('the hospital mapped POI is at the corroborated Valenzuela branch', () {
    final hospital = MarulasLandmarksCatalog.all.singleWhere(
      (p) => p.id == 'fumc',
    );
    expect(hospital.lat, closeTo(14.6780548, 0.000001));
    expect(hospital.lng, closeTo(120.9802868, 0.000001));
    expect(hospital.address, startsWith('120 MacArthur Highway'));
    final chapter = MarulasLandmarksCatalog.all.singleWhere(
      (p) => p.id == 'red_cross_valenzuela',
    );
    expect(chapter.address, contains('Dahlia Street'));
    expect(chapter.category, isNot(contains('Hospital')));
  });
  test(
    'invalid, outside-area and duplicate catalog entries cannot become quick destinations',
    () {
      final valid = fixtures().first;
      final invalid = MarulasLandmark(
        id: 'invalid',
        name: 'Invalid',
        category: '',
        address: '',
        lat: double.nan,
        lng: 120,
        tags: [],
        quickCategories: {category[0]},
      );
      final outside = place('outside', 'Outside', category[0], dx: 1);
      final matches = MarulasLandmarksCatalog.quickDestinations(
        category[0],
        [valid, valid, invalid, outside],
        isInScope: (lat, lng) =>
            (lng - AppEnvironment.area.longitude).abs() < 0.01,
      );
      expect(matches.map((p) => p.id), ['hospital']);
    },
  );

  final names = [
    'Test Hospital',
    'Test Shelter',
    'Test Barangay Hall',
    'Test Fire Station',
  ];
  for (var i = 0; i < category.length; i++) {
    testWidgets(
      '${labels[i]} shows named choices and never automatically routes to the first result',
      (tester) async {
        await start(tester);
        await tap(tester, labels[i]);
        expect(find.text(names[i]), findsOneWidget);
        expect(find.text('Test Clinic'), findsNothing);
        expect(find.text('Test Pharmacy'), findsNothing);
        expect(requested, isEmpty);
        expect(routing.destinationPoint, isNull);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .controller!
              .text,
          isEmpty,
        );
        if (i == 3) {
          expect(find.text('Test Police Station'), findsOneWidget);
          expect(find.text('Test Rescue Office'), findsOneWidget);
        }
      },
    );
  }
  testWidgets(
    'submitting the destination field while browsing a category cannot select its first place',
    (tester) async {
      await start(tester);
      await tap(tester, 'Hospitals');
      await tester.ensureVisible(find.byType(TextField).at(1));
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(reviewed, isEmpty);
      expect(requested, isEmpty);
      expect(routing.destinationPoint, isNull);
    },
  );

  testWidgets(
    'a specific place is reviewed before routing; the confirmed entrance and chosen name are retained',
    (tester) async {
      final approval = Completer<Position?>();
      picker = (_) => approval.future;
      await start(tester);
      await tap(tester, 'Hospitals');
      await tap(tester, 'Test Hospital');
      expect(reviewed, ['Test Hospital']);
      expect(requested, isEmpty);
      expect(routing.destinationPoint, isNull);
      final entrance = point(0.0012, 0.0002);
      approval.complete(entrance);
      await tester.pump();
      await tester.pump();
      expect(requested.single.lng, entrance.lng);
      expect(requested.single.lat, entrance.lat);
      expect(routing.destinationName, 'Test Hospital');
      expect(routing.routes.single.destinationName, 'Test Hospital');
      expect(routing.routes.single.requestedDestination!.lng, entrance.lng);
    },
  );
  testWidgets(
    'destination search preserves the existing trip on Back and replaces it after confirming a new place',
    (tester) async {
      await start(tester);
      await tap(tester, 'Hospitals');
      await tap(tester, 'Test Hospital');
      expect(routing.routes, isNotEmpty);
      final original = routing.destinationPoint;
      await tap(tester, 'Change');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tap(tester, 'Emergency/Police');
      expect(identical(routing.destinationPoint, original), isTrue);
      expect(routing.destinationName, 'Test Hospital');
      expect(requested, hasLength(1));
      expect(find.text('Test Fire Station'), findsOneWidget);
      // The previous route is behind the opaque search page, never relabelled
      // as the newly browsed category's route.
      expect(
        find.byKey(const ValueKey('planner-start-navigation')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(identical(routing.destinationPoint, original), isTrue);
      expect(routing.routes.single.destinationName, 'Test Hospital');
      await tap(tester, 'Change');
      await tester.pumpAndSettle();
      await tap(tester, 'Emergency/Police');
      await tap(tester, 'Test Fire Station');
      await tester.pumpAndSettle();
      await tester.pump();
      expect(routing.destinationName, 'Test Fire Station');
      expect(routing.routes.single.destinationName, 'Test Fire Station');
      expect(requested, hasLength(2));
      expect(
        find.byKey(const ValueKey('planner-destination-search')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'typed catalog landmarks use the same entrance review as quick picks',
    (tester) async {
      await start(tester, realCatalog: true);
      await tester.tap(find.byKey(const ValueKey('planner-destination-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planner-destination-search')),
        'FUMC',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requested, isEmpty);
      await tap(tester, 'Fatima University Medical Center (FUMC)');
      await tester.pumpAndSettle();
      expect(reviewed, ['Fatima University Medical Center (FUMC)']);
      expect(requested, hasLength(1));
    },
    skip: AppEnvironment.isFieldTest,
  );

  testWidgets(
    'LGU-listed sites support live lookup and the removed court is absent',
    (tester) async {
      await start(tester, realCatalog: true);
      await tap(tester, 'Evac Centers');
      expect(find.text('Elysian Covered Court'), findsOneWidget);
      final tile = find.ancestor(
        of: find.text('Elysian Covered Court'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);
      expect(find.text('Do\u00f1a Ata Covered Court'), findsNothing);
      expect(requested, isEmpty);
      expect(routing.destinationPoint, isNull);
    },
    skip: AppEnvironment.isFieldTest,
  );

  testWidgets(
    'listed sites resolve via provider then review a mapped location',
    (tester) async {
      final seen = <String>[];
      lookup = (query, names) async {
        seen.add(query);
        expect(names, ['Elysian Covered Court']);
        return [
          MapboxPlace(
            id: 'mapped',
            name: query,
            address: 'Sample address',
            lat: point(.001, 0).lat.toDouble(),
            lng: point(.001, 0).lng.toDouble(),
            isPoi: true,
          ),
        ];
      };
      await start(tester, realCatalog: true);
      await tap(tester, 'Evac Centers');
      await tap(tester, 'Elysian Covered Court');
      await tester.pumpAndSettle();
      expect(seen, ['Elysian Covered Court']);
      expect(reviewed, ['Elysian Covered Court']);
      expect(requested, hasLength(1));
    },
    skip: AppEnvironment.isFieldTest,
  );

  testWidgets('a late mapped site lookup cannot override a newer category', (
    tester,
  ) async {
    final pending = Completer<List<MapboxPlace>>();
    lookup = (_, __) => pending.future;
    await start(tester, realCatalog: true);
    await tap(tester, 'Evac Centers');
    await tap(tester, 'Elysian Covered Court');
    await tap(tester, 'Hospitals');
    pending.complete([
      MapboxPlace(
        id: 'old',
        name: 'Elysian Covered Court',
        address: '',
        lat: point(.001, 0).lat.toDouble(),
        lng: point(.001, 0).lng.toDouble(),
        isPoi: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(reviewed, isEmpty);
    expect(requested, isEmpty);
    expect(
      find.text('Fatima University Medical Center (FUMC)'),
      findsOneWidget,
    );
  }, skip: AppEnvironment.isFieldTest);

  testWidgets(
    'typed LGU school names resolve live instead of using an old catalog pin',
    (tester) async {
      final lookedUp = <String>[];
      lookup = (query, names) async {
        lookedUp.add(query);
        return [
          MapboxPlace(
            id: 'fresh',
            name: query,
            address: 'Sample mapped address',
            lat: point(.002, 0).lat.toDouble(),
            lng: point(.002, 0).lng.toDouble(),
            isPoi: true,
          ),
        ];
      };
      await start(tester, realCatalog: true);
      await tester.tap(find.byKey(const ValueKey('planner-destination-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planner-destination-search')),
        'Constantino Elementary',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requested, isEmpty);
      await tap(tester, 'Constantino Elementary School');
      await tester.pumpAndSettle();
      expect(lookedUp, ['Constantino Elementary School']);
      expect(reviewed, ['Constantino Elementary School']);
      expect(requested.single.lng, point(.002, 0).lng);
    },
    skip: AppEnvironment.isFieldTest,
  );

  testWidgets('cancelling destination pin review does not calculate a route', (
    tester,
  ) async {
    picker = (_) async => null;
    await start(tester);
    await tap(tester, 'Barangay Hall');
    await tap(tester, 'Test Barangay Hall');
    expect(requested, isEmpty);
    expect(routing.destinationPoint, isNull);
    expect(routing.routes, isEmpty);
  });
  testWidgets(
    'a late pin confirmation cannot overwrite a newer quick category',
    (tester) async {
      final approval = Completer<Position?>();
      picker = (_) => approval.future;
      await start(tester);
      await tap(tester, 'Hospitals');
      await tap(tester, 'Test Hospital');
      await tap(tester, 'Emergency/Police');
      approval.complete(point(0.001, 0));
      await tester.pump();
      await tester.pump();
      expect(requested, isEmpty);
      expect(routing.destinationPoint, isNull);
      expect(find.text('Test Fire Station'), findsOneWidget);
    },
  );
  testWidgets('a pin confirmation from an older planner session is ignored', (
    tester,
  ) async {
    final approval = Completer<Position?>();
    picker = (_) => approval.future;
    await start(tester);
    await tap(tester, 'Hospitals');
    await tap(tester, 'Test Hospital');
    routing.startPlanning(locate: () async => null);
    approval.complete(point(0.001, 0));
    await tester.pump();
    await tester.pump();
    expect(requested, isEmpty);
    expect(routing.destinationPoint, isNull);
  });
  testWidgets(
    'a confirmed pin outside the active area is rejected without a route request',
    (tester) async {
      picker = (_) async => point(1, 1);
      await start(tester);
      await tap(tester, 'Evac Centers');
      await tap(tester, 'Test Shelter');
      expect(requested, isEmpty);
      expect(routing.destinationPoint, isNull);
      expect(
        find.textContaining('confirmed pin must be within'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'a quick destination does not fabricate an origin when GPS is unavailable',
    (tester) async {
      await start(tester, gps: false);
      await tap(tester, 'Hospitals');
      await tap(tester, 'Test Hospital');
      expect(routing.destinationName, 'Test Hospital');
      expect(routing.originPoint, isNull);
      expect(requested, isEmpty);
      expect(routing.routes, isEmpty);
      expect(routing.routeErrorMessage, contains('real GPS'));
    },
  );
  testWidgets(
    'the default catalog respects the active flavor and never substitutes main-area data',
    (tester) async {
      await start(tester, realCatalog: true);
      await tap(tester, 'Hospitals');
      if (AppEnvironment.isFieldTest) {
        expect(
          find.textContaining(
            'No confirmed catalog locations in this category',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Fatima University Medical Center (FUMC)'),
          findsNothing,
        );
      } else {
        expect(
          find.text('Fatima University Medical Center (FUMC)'),
          findsOneWidget,
        );
        expect(find.text('Mercury Drug - Fatima MacArthur'), findsNothing);
      }
      expect(requested, isEmpty);
    },
  );
  testWidgets(
    'unresolved quick categories explain the missing data without routing to an arbitrary place',
    (tester) async {
      await start(tester, realCatalog: true);
      for (final label in labels.skip(1)) {
        await tap(tester, label);
        expect(
          find.textContaining(
            !AppEnvironment.isFieldTest && label == 'Evac Centers'
                ? 'Choose a listed site to find its mapped location'
                : 'No confirmed catalog locations in this category',
          ),
          findsOneWidget,
        );
        expect(routing.destinationPoint, isNull);
        expect(requested, isEmpty);
      }
    },
  );
  testWidgets(
    'quick-category browsing remains usable with a narrow screen and large text',
    (tester) async {
      await start(tester, width: 360, textScale: 1.5);
      await tap(tester, 'Emergency/Police');
      expect(find.text('Test Fire Station'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
