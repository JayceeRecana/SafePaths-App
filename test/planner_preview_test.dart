import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/screens/user/route_preview_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/planner_preview_controls.dart';

PlannedRoute sample({
  int minutes = 7,
  int metres = 920,
  int unconfirmed = 0,
  bool blocked = false,
  bool critical = false,
  double offset = 0,
}) => PlannedRoute(
  points: [
    Position(
      AppEnvironment.area.longitude - .001,
      AppEnvironment.area.latitude + offset,
    ),
    Position(
      AppEnvironment.area.longitude + .001,
      AppEnvironment.area.latitude + offset,
    ),
  ],
  durationMin: minutes,
  distanceMeters: metres.toDouble(),
  distanceMiles: metres / 1609.34,
  summary: 'Provider route',
  hazardAlerts: critical ? ['Predicted risk'] : [],
  safetyStatus: critical
      ? 'critical'
      : unconfirmed > 0
      ? 'unverified_risk'
      : 'safe',
  totalRisk: critical ? 90 : 0,
  unverifiedRoadCount: unconfirmed,
  isBlocked: blocked,
  steps: [],
  routeExplanations: List.generate(
    unconfirmed,
    (i) => 'Crosses Road ${i + 1} (Unverified Advisory)',
  ),
);

Widget shell(
  Widget child, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  final routing = RoutingService.instance, app = AppStateService.instance;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'PLANNER_PREVIEW_TEST=true');
    SimulatedWeatherService.instance;
  });
  setUp(() {
    routing.exitPlanning();
    app.roads.clear();
  });
  tearDown(() => routing.exitPlanning());
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  testWidgets(
    'options show actual counts and metrics, and selecting a card does not navigate',
    (tester) async {
      var index = 0, navigations = 0;
      final options = [
        PreviewRouteOption(
          sample(minutes: 7, metres: 920, unconfirmed: 3),
          'First option',
        ),
        PreviewRouteOption(
          sample(minutes: 11, metres: 1300, offset: .002),
          'Second option',
        ),
      ];
      await tester.pumpWidget(
        shell(
          StatefulBuilder(
            builder: (context, update) => SizedBox(
              height: 520,
              child: RoutePreviewPanel(
                options: options,
                selectedIndex: index,

                onSelect: (i) => update(() => index = i),
                onNavigate: () => navigations++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 route options'), findsOneWidget);
      expect(find.text('7 min'), findsOneWidget);
      expect(find.text('920 m'), findsOneWidget);
      expect(find.text('3 roads have unconfirmed conditions'), findsOneWidget);
      expect(find.textContaining('No flooded roads reported'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('route-option-1')));
      await tester.pumpAndSettle();
      expect(index, 1);
      expect(navigations, 0);
      expect(find.text('No known route warnings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'condition list scrolls independently while the action stays visible',
    (tester) async {
      await tester.pumpWidget(
        shell(
          SizedBox(
            height: 420,
            child: RoutePreviewPanel(
              options: [
                PreviewRouteOption(sample(unconfirmed: 18), 'Selected route'),
              ],
              selectedIndex: 0,

              onSelect: (_) {},
              onNavigate: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('route-options-panel')),
      );
      final toggle = find.byKey(const ValueKey('route-conditions-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('route-options-scroll')),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      final footer = tester.getRect(
        find.byKey(const ValueKey('preview-start-navigation')),
      );
      expect(footer.top, greaterThanOrEqualTo(panel.top));
      expect(footer.bottom, lessThanOrEqualTo(panel.bottom));
      expect(find.textContaining('Road 18'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('route-options-panel'))),
        panel,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'critical mixed uncertainty stays critical and a closed selection cannot navigate',
    (tester) async {
      var starts = 0;
      final critical = sample(critical: true, unconfirmed: 6);
      await tester.pumpWidget(
        shell(
          SizedBox(
            height: 500,
            child: RoutePreviewPanel(
              options: [PreviewRouteOption(critical, 'Selected route')],
              selectedIndex: 0,

              onSelect: (_) {},
              onNavigate: () => starts++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Critical risk'), findsOneWidget);
      expect(find.text('Critical risk on this route'), findsOneWidget);
      expect(find.text('6 roads have unconfirmed conditions'), findsOneWidget);
      expect(find.text('Navigate with Caution'), findsOneWidget);
      await tester.pumpWidget(
        shell(
          SizedBox(
            height: 500,
            child: RoutePreviewPanel(
              options: [
                PreviewRouteOption(sample(blocked: true), 'Selected route'),
              ],
              selectedIndex: 0,

              onSelect: (_) {},
              onNavigate: () => starts++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('preview-start-navigation')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('All available paths'), findsNothing);
      expect(starts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'missing live data requests caution without inventing unconfirmed-road counts',
    (tester) async {
      await tester.pumpWidget(
        shell(
          SizedBox(
            height: 500,
            child: RoutePreviewPanel(
              options: [PreviewRouteOption(sample(), 'Selected route')],
              selectedIndex: 0,
              liveDataUnavailable: true,

              onSelect: (_) {},
              onNavigate: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Live conditions need confirmation'), findsOneWidget);
      expect(find.text('Unconfirmed'), findsOneWidget);
      expect(find.text('Navigate with Caution'), findsOneWidget);
      expect(find.textContaining('0 roads'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'route cards, warnings and action fit narrow displays with enlarged English and Filipino text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 390,
                  child: RoutePreviewPanel(
                    options: [
                      PreviewRouteOption(
                        sample(unconfirmed: 18),
                        'Long alternative route label',
                      ),
                      PreviewRouteOption(
                        sample(critical: true),
                        'Another route',
                      ),
                    ],
                    selectedIndex: 0,

                    onSelect: (_) {},
                    onNavigate: () {},
                  ),
                ),
              ),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$language/$dark');
          final action = tester.getRect(
            find.byKey(const ValueKey('preview-start-navigation')),
          );
          expect(action.bottom, lessThanOrEqualTo(740));
          await tester.ensureVisible(
            find.byKey(const ValueKey('route-conditions-toggle')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'real expanded view updates map geometry and retains its fixed panel height',
    (tester) async {
      final first = sample(), second = sample(offset: .003, minutes: 11);
      routing.routes = [first, second];
      List<Position>? displayed;
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            route: first,
            routeMapBuilder: (points) {
              displayed = points;
              return const ColoredBox(color: Colors.grey);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(identical(displayed, first.points), isTrue);
      // The provider can publish a reordered list before the next UI frame.
      routing.routes = [second, first];
      await tester.tap(find.byKey(const ValueKey('route-option-1')));
      await tester.pumpAndSettle();
      expect(identical(displayed, second.points), isTrue);
      expect(routing.selectedRouteIndex, 0);
      final panel = find.byKey(const ValueKey('route-options-panel'));
      final height = tester.getSize(panel).height;
      await tester.drag(
        find.byKey(const ValueKey('route-options-scroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, height);
      expect(find.byKey(const ValueKey('route-options-resize')), findsNothing);
      await tester.dragFrom(
        tester.getTopLeft(panel) + const Offset(80, 8),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, height);
      expect(height, lessThanOrEqualTo(tester.view.physicalSize.height * .5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'expanded view still rechecks a closure that arrives during caution confirmation',
    (tester) async {
      final path = sample();
      routing.routes = [path];
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            route: path,
            routeMapBuilder: (_) => const ColoredBox(color: Colors.grey),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-start-navigation')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Confirm Travel Conditions'), findsOneWidget);
      app.roads.add(
        RoadStatus(
          id: 'closure',
          name: 'Closed road',
          status: 'not_passable',
          notes: 'Test closure',
          updatedAt: DateTime.now(),
          isVerified: true,
          geometry: {
            'type': 'LineString',
            'coordinates': [
              [
                AppEnvironment.area.longitude,
                AppEnvironment.area.latitude - .001,
              ],
              [
                AppEnvironment.area.longitude,
                AppEnvironment.area.latitude + .001,
              ],
            ],
          },
        ),
      );
      app.mapChanges.value++;
      await tester.pump();
      await tester.tap(find.text('Continue with Caution'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutePreviewScreen), findsOneWidget);
      expect(
        find.text(
          'Road conditions changed. Review the updated route before starting.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('preview-start-navigation')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'expanded preview keeps back and navigation reachable in short landscape with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = sample();
      routing.routes = [path];
      await tester.pumpWidget(
        shell(
          RoutePreviewScreen(
            route: path,
            routeMapBuilder: (_) => const ColoredBox(color: Colors.grey),
          ),
          language: 'fil',
          dark: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in ['route-preview-back', 'preview-start-navigation']) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(360));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'admin closure and reopening refresh the preview without changing the chosen route',
    (tester) async {
      final first = sample(), alternate = sample(offset: .004, minutes: 12);
      routing.routes = [first, alternate];
      List<Position>? displayed;
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            route: first,
            routeMapBuilder: (points) {
              displayed = points;
              return const ColoredBox(color: Colors.grey);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final closure = RoadStatus(
        id: 'live-closure',
        name: 'Road ahead',
        status: 'not_passable',
        notes: 'Admin update',
        updatedAt: DateTime.now(),
        isVerified: true,
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [
              AppEnvironment.area.longitude,
              AppEnvironment.area.latitude - .0005,
            ],
            [
              AppEnvironment.area.longitude,
              AppEnvironment.area.latitude + .0005,
            ],
          ],
        },
      );
      app.roads.add(closure);
      app.mapChanges.value++;
      await tester.pumpAndSettle();
      expect(identical(displayed, first.points), isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('preview-start-navigation')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Navigation unavailable for this route'),
        findsOneWidget,
      );
      expect(find.text('2 route options'), findsOneWidget);
      app.roads[0] = closure.copyWith(status: 'passable', riskScore: 0);
      app.mapChanges.value++;
      await tester.pumpAndSettle();
      expect(identical(displayed, first.points), isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('preview-start-navigation')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
