import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/screens/user/route_planner_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/widgets/planner_route_card.dart';
import 'package:safepaths_app/widgets/planner_travel_selector.dart';
import 'map_home_controls_test.dart' as fixtures;

PlannedRoute route({
  bool blocked = false,
  bool critical = false,
  List<String> roadNames = const [],
}) => PlannedRoute(
  points: [Position(120.98, 14.67), Position(120.981, 14.671)],
  durationMin: 7,
  distanceMiles: 99,
  distanceMeters: 920,
  summary: 'Via Sample Road',
  roadNames: roadNames,
  hazardAlerts: [],
  safetyStatus: critical ? 'critical' : 'unverified_risk',
  unverifiedRoadCount: critical ? 0 : 3,
  isBlocked: blocked,
  steps: [],
);
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'PLANNER_DESIGN_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  testWidgets('explains missing names and uses only verified record times', (
    tester,
  ) async {
    final planned = route().copyWith(summary: 'Suggested route');
    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: SingleChildScrollView(
            child: PlannerRouteCard(
              route: planned,
              map: const SizedBox.expand(),
              roadRecords: [
                RoadStatus(
                  id: 'import',
                  name: 'Imported road',
                  status: 'passable',
                  notes: '',
                  updatedAt: DateTime.now(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Directions did not supply street names for this route.'),
      findsOneWidget,
    );
    expect(find.text('Check time unavailable'), findsOneWidget);
    expect(find.byTooltip('Distance'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('planner-route-preview')))
          .height,
      greaterThanOrEqualTo(180),
    );
    await tester.ensureVisible(find.text('Route details'));
    await tester.tap(find.text('Route details'));
    await tester.pumpAndSettle();
    expect(find.text('No verified check time'), findsOneWidget);
    expect(find.textContaining('Recorded check:'), findsNothing);

    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: SingleChildScrollView(
            child: PlannerRouteCard(
              key: const ValueKey('verified-record-card'),
              route: route(roadNames: ['Actual Provider Road']),
              roadRecords: [
                RoadStatus(
                  id: 'checked',
                  name: 'Checked road',
                  status: 'passable',
                  notes: '',
                  isVerified: true,
                  updatedAt: DateTime(2026, 10, 26, 13, 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Via Actual Provider Road'), findsOneWidget);
    expect(find.text('Road checks have individual times'), findsOneWidget);
    expect(find.textContaining('Directions did not supply'), findsNothing);
    await tester.ensureVisible(find.text('Route details'));
    await tester.tap(find.text('Route details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recorded check:'), findsOneWidget);
    expect(find.textContaining('1:28 PM'), findsOneWidget);
  });
  testWidgets(
    'selected card uses actual route metrics and unconfirmed assessment without decorative claims',
    (tester) async {
      var started = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: SingleChildScrollView(
              child: PlannerRouteCard(
                route: route(),
                map: const SizedBox.expand(),
                onNavigate: () => started++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7 min'), findsOneWidget);
      expect(find.text('920 m'), findsOneWidget);
      expect(find.text('Unconfirmed'), findsOneWidget);
      expect(find.text('Navigate with Caution'), findsOneWidget);
      expect(find.textContaining('LIVE UPDATES ACTIVE'), findsNothing);
      expect(find.textContaining('checked 20'), findsNothing);
      expect(find.textContaining('Safest'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('planner-start-navigation')),
      );
      await tester.tap(find.byKey(const ValueKey('planner-start-navigation')));
      expect(started, 1);
    },
  );
  testWidgets(
    'blocked cards disable navigation and alternatives select without starting navigation',
    (tester) async {
      var selected = 0, started = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: PlannerRouteCard(
              route: route(blocked: true),
              onNavigate: () => started++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('planner-start-navigation')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: PlannerRouteCard(
              route: route(critical: true),
              compact: true,
              onSelect: () => selected++,
              onNavigate: () => started++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Via Sample Road'));
      expect(selected, 1);
      expect(started, 0);
      expect(find.text('Critical risk'), findsOneWidget);
    },
  );
  testWidgets(
    'travel modes and route cards fit 320 pixels with large text in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        PlannerTravelSelector(
                          selected: 'Sedan',
                          onSelected: (mode) => selected = mode,
                        ),
                        const SizedBox(height: 12),
                        PlannerRouteCard(
                          route: route(critical: true),
                          map: const SizedBox.expand(),
                          onNavigate: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.airport_shuttle));
          expect(selected, 'SUV / Pickup');
          expect(
            tester.getSize(find.byType(InkWell).first).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'planner opens dedicated local road search and keeps its draft on Back without selecting it',
    (tester) async {
      final lat = AppEnvironment.area.latitude,
          lng = AppEnvironment.area.longitude;
      AppStateService.instance.roads
        ..clear()
        ..add(
          RoadStatus(
            id: 'design-road',
            name: 'Planner Design Road',
            status: 'passable',
            notes: '',
            updatedAt: DateTime.now(),
            geometry: {
              'type': 'LineString',
              'coordinates': [
                [lng, lat],
                [lng + .001, lat],
              ],
            },
          ),
        );
      AppStateService.instance.roads.add(
        RoadStatus(
          id: 'design-road-2',
          name: 'Planner Design Street',
          status: 'passable',
          notes: '',
          updatedAt: DateTime.now(),
          geometry: AppStateService.instance.roads.first.geometry,
        ),
      );
      await tester.pumpWidget(
        fixtures.shell(
          RoutePlannerScreen(
            locate: () async => Position(lng, lat),
            routeMapBuilder: (_) => const SizedBox.expand(),
            quickLandmarks: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Where are you going?'), findsOneWidget);
      expect(find.text('LIVE UPDATES ACTIVE'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('planner-destination-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planner-destination-search')),
        'Planner Design',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Roads we monitor'), findsOneWidget);
      expect(find.text('Planner Design Road'), findsOneWidget);
      expect(find.text('Planner Design Street'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(RoutingService.instance.destinationPoint, isNull);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('planner-destination-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('planner-destination-field')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('planner-destination-search')),
            )
            .controller!
            .text,
        'Planner Design',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
