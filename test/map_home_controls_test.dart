import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/map_road_data.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/theme/app_palette.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/home_alert_banner.dart';
import 'package:safepaths_app/widgets/map_home_controls.dart';
import 'package:safepaths_app/widgets/road_condition_overview.dart';
import 'package:safepaths_app/services/map_load_state.dart';
import 'package:safepaths_app/widgets/map_status_banner.dart';

Widget shell(
  Widget child, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
RoadStatus road({
  String status = 'passable',
  bool verified = false,
  String source = 'osm',
}) => RoadStatus(
  id: 'road',
  name: 'Unnamed residential road with a long recorded name',
  status: status,
  notes: '',
  source: source,
  isVerified: verified,
  updatedAt: DateTime.now(),
  geometry: {
    'type': 'LineString',
    'coordinates': [
      [120.984, 14.676],
      [120.986, 14.676],
    ],
  },
);
MapHomeHeader header(
  TextEditingController controller, {
  bool searching = false,
  bool busy = false,
  VoidCallback? search,
  VoidCallback? close,
}) => MapHomeHeader(
  searching: searching,
  busy: busy,
  controller: controller,
  weatherLabel: 'Severe weather estimate',
  weatherIcon: Icons.thunderstorm_outlined,
  severeWeather: true,
  onProfile: () {},
  onSettings: () {},
  onStartSearch: () {},
  onCloseSearch: close ?? () {},
  onSearch: search ?? () {},
  onWeather: () {},
  onWeatherInfo: () {},
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'unreviewed imports and absent statuses are uncertain; recorded closures stay closed',
    () {
      final imported = road();
      expect(imported.needsStatusConfirmation(WeatherState.clear), isTrue);
      expect(
        road(verified: true).needsStatusConfirmation(WeatherState.clear),
        isFalse,
      );
      final missing = RoadStatus.fromJson({
        'id': 'missing',
        'name': 'Missing',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(missing.status, 'unknown');
      expect(missing.needsStatusConfirmation(WeatherState.clear), isTrue);
      expect(
        road(status: 'not_passable').getEffectiveStatus(WeatherState.clear),
        'not_passable',
      );
      expect(
        road(
          status: 'not_passable',
        ).needsStatusConfirmation(WeatherState.clear),
        isFalse,
      );
    },
  );
  test(
    'map draws uncertain roads dashed amber, then updates verification without rebuilding geometry',
    () {
      final cache = MapRoadData();
      final imported = road();
      Map properties(String data) =>
          jsonDecode(data)['features'][0]['properties'] as Map;
      final uncertain = properties(
        cache.project([imported], WeatherState.clear),
      );
      expect(uncertain['isUnconfirmed'], isTrue);
      expect(uncertain['color'], '#EAB308');
      final verified = properties(
        cache.project([
          imported.copyWith(isVerified: true),
        ], WeatherState.clear),
      );
      expect(verified['isUnconfirmed'], isFalse);
      expect(verified['color'], '#006E1C');
      expect(cache.geometryBuilds, 1);
      final closure = properties(
        cache.project([road(status: 'not_passable')], WeatherState.clear),
      );
      expect(closure['color'], '#B81311');
      expect(closure['isUnconfirmed'], isFalse);
    },
  );
  test(
    'planner treats unreviewed and unknown roads as advisories rather than automatic closures',
    () {
      final route = [Position(120.984, 14.676), Position(120.986, 14.676)];
      for (final uncertain in [road(), road(status: 'unknown')]) {
        final result = RoutingService.instance.evaluateRouteSafety(
          route,
          [uncertain],
          'Sedan',
          weatherState: WeatherState.clear,
        );
        expect(result['status'], 'unverified_risk');
        expect(result['isBlocked'], isFalse);
        expect(result['unconfirmedCount'], 1);
      }
      final closure = RoutingService.instance.evaluateRouteSafety(
        route,
        [road(status: 'not_passable')],
        'Sedan',
        weatherState: WeatherState.clear,
      );
      expect(closure['isBlocked'], isTrue);
    },
  );
  test('an unreviewed road cannot erase a critical predicted risk', () {
    final result = RoutingService.instance.evaluateRouteSafety(
      [Position(120.984, 14.676), Position(120.986, 14.676)],
      [road().copyWith(riskScore: 95, riskCategory: 'Critical')],
      'Sedan',
      weatherState: WeatherState.clear,
    );
    expect(result['status'], 'critical');
    expect(result['isBlocked'], isFalse);
    expect(result['unconfirmedCount'], 1);
    expect(result['maxRisk'], 95);
    expect(result['averageRisk'], 95);
    expect(result['highestRiskSegmentId'], 'road');
  });
  testWidgets(
    'map panels use the current palette, and imported roads never say no recent reports',
    (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: MapRoadPreview(
                road: road(),
                weather: WeatherState.clear,
                onOpen: () {},
              ),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(MapOverlayPanel),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          surface.color,
          (dark ? AppPalette.dark : AppPalette.light).surfaceContainerLowest,
        );
        expect(find.text('Needs confirmation'), findsOneWidget);
        expect(find.text('No recent reports'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'header, selected road and alert fit 320 pixels at 200 percent in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      HomeAlertBanner(
                        key: const ValueKey('alert'),
                        title: 'A current update on a long road name',
                        severity: 'Critical',
                        roadName: 'Synthetic road',
                        onOpen: () {},
                        onDismiss: () {},
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: header(controller),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: MapRoadPreview(
                          road: road(),
                          weather: WeatherState.clear,
                          onOpen: () {},
                        ),
                      ),
                      MapQuickActions(
                        horizontal: true,
                        onLocate: () {},
                        onFullscreen: () {},
                        onReport: () {},
                      ),
                    ],
                  ),
                ),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.byType(HomeAlertBanner)).bottom,
            lessThanOrEqualTo(tester.getRect(find.byType(MapHomeHeader)).top),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets(
    'road legend opens a scrollable explanation with Browse roads at large Filipino text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var browsed = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(body: RoadConditionsButton(onBrowseRoads: () => browsed++)),
          dark: true,
          language: 'fil',
          scale: 2,
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kailangang kumpirmahin'), findsOneWidget);
      await tester.ensureVisible(find.text('Tingnan ang mga kalsada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tingnan ang mga kalsada'));
      await tester.pumpAndSettle();
      expect(browsed, 1);
      expect(find.byType(RoadConditionsSheet), findsNothing);
    },
  );
  testWidgets(
    'busy search does not resubmit and locate can be disabled independently',
    (tester) async {
      final controller = TextEditingController(text: 'Synthetic');
      addTearDown(controller.dispose);
      var searches = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  header(
                    controller,
                    searching: true,
                    busy: true,
                    search: () => searches++,
                  ),
                  MapQuickActions(
                    horizontal: true,
                    locating: true,
                    onLocate: () {},
                    onFullscreen: () {},
                    onReport: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(searches, 0);
      final locate = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Locate me',
        ),
      );
      expect(locate.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'closing a selected preview does not also open its road details',
    (tester) async {
      var opened = 0, dismissed = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: MapRoadPreview(
              road: road(),
              weather: WeatherState.clear,
              onOpen: () => opened++,
              onDismiss: () => dismissed++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Hide road preview'));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(opened, 0);
    },
  );
  testWidgets(
    'map errors and retry stay above the home header and clear after recovery',
    (tester) async {
      final status = MapLoadState();
      addTearDown(status.dispose);
      status.failed();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var retried = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MapStatusBanner(
                    status: status,
                    onRetry: () {
                      retried++;
                      status.loaded();
                    },
                  ),
                  header(controller),
                ],
              ),
            ),
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(MapStatusBanner)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(MapHomeHeader)).top),
      );
      await tester.tap(find.text('Retry map'));
      await tester.pumpAndSettle();
      expect(retried, 1);
      expect(find.text('Retry map'), findsNothing);
    },
  );
  testWidgets(
    'primary selected-road status precedes metadata and remains reachable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                key: const ValueKey('preview-viewport'),
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      MapQuickActions(
                        horizontal: true,
                        onLocate: () {},
                        onFullscreen: () {},
                        onReport: () {},
                      ),
                      const SizedBox(height: 12),
                      MapRoadPreview(
                        road: road(),
                        weather: WeatherState.clear,
                        onOpen: () {},
                        onDismiss: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          dark: true,
          language: 'fil',
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final statusFinder = find.text('Kailangang kumpirmahin');
      expect(
        tester.getRect(statusFinder).top,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('road-update-age'))).top,
        ),
      );
      await tester.ensureVisible(statusFinder);
      await tester.pumpAndSettle();
      final status = tester.getRect(statusFinder);
      expect(
        status.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('preview-viewport'))).bottom,
        ),
      );
    },
  );
  testWidgets(
    'map reload disables location movement without disabling report access',
    (tester) async {
      var reports = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: MapQuickActions(
              canLocate: false,
              horizontal: true,
              onLocate: () {},
              onFullscreen: () {},
              onReport: () => reports++,
            ),
          ),
        ),
      );
      final locate = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Locate me',
        ),
      );
      expect(locate.onPressed, isNull);
      await tester.tap(find.byTooltip('Report road conditions'));
      await tester.pumpAndSettle();
      expect(reports, 1);
    },
  );
  testWidgets(
    'reference preview opens details once and keeps a stale closure distinct from its note',
    (tester) async {
      var opened = 0;
      final clock = DateTime(2026, 10, 27, 14);
      final closure = RoadStatus(
        id: 'road',
        name: 'Unnamed residential (OSM 552835258)',
        status: 'not_passable',
        notes: 'Not passable for all vehicles',
        isVerified: true,
        updatedAt: clock.subtract(const Duration(hours: 22)),
      );
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: MapRoadPreview(
              road: closure,
              weather: WeatherState.clear,
              now: clock,
              onOpen: () => opened++,
            ),
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unnamed residential road'), findsOneWidget);
      expect(find.text('Not passable'), findsOneWidget);
      expect(find.byKey(const ValueKey('road-recheck-notice')), findsOneWidget);
      expect(find.text('BARANGAY NOTE'), findsOneWidget);
      expect(find.text('Not passable for all vehicles'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preview-view-details')));
      await tester.pump();
      expect(opened, 1);
      expect(closure.status, 'not_passable');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'compact card keeps its footer visible with long notes, actions and large translated text',
    (tester) async {
      tester.view.physicalSize = const Size(368, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = DateTime(2026, 10, 27, 14);
      for (final language in ['en', 'fil']) {
        for (final scale in [1.0, 2.0]) {
          final note = List.filled(
            80,
            'Long barangay message about current conditions.\n',
          ).join();
          final closure = RoadStatus(
            id: 'long-note',
            name: 'Unnamed residential (OSM 552835258)',
            status: 'not_passable',
            notes: note,
            isVerified: true,
            updatedAt: clock.subtract(const Duration(days: 1)),
          );
          var opened = 0;
          final overlay = MapHomeBottomOverlay(
            actions: MapQuickActions(
              horizontal: true,
              onLocate: () {},
              onFullscreen: () {},
              onReport: () {},
            ),
            preview: MapRoadPreview(
              road: closure,
              weather: WeatherState.clear,
              now: clock,
              onOpen: () => opened++,
              onDismiss: () {},
            ),
          );
          final host = Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: scale > 1 ? 264 : 280,
                  key: const ValueKey('actual-overlay-viewport'),
                  child: overlay,
                ),
              ),
            ),
          );
          await tester.pumpWidget(
            shell(
              host,
              language: language,
              scale: scale,
              dark: language == 'fil',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$language/$scale');
          final viewport = tester.getRect(
            find.byKey(const ValueKey('actual-overlay-viewport')),
          );
          final footer = tester.getRect(
            find.byKey(const ValueKey('preview-view-details')),
          );
          expect(footer.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(footer.top, greaterThanOrEqualTo(viewport.top));
          expect(
            tester.getSize(find.byType(MapRoadPreview)).height,
            lessThanOrEqualTo(280),
          );
          final title = tester.getRect(find.byType(RoadIdentityHeader));
          final close = tester.getRect(
            find.byKey(const ValueKey('preview-close')),
          );
          expect(close.center.dy, closeTo(title.center.dy, .5));
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('preview-note')))
                .maxLines,
            2,
          );
          await tester.tap(find.byKey(const ValueKey('preview-view-details')));
          await tester.pump();
          expect(opened, 1);
          expect(closure.notes, note);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'read more opens the existing details action when a note is truncated',
    (tester) async {
      var opened = 0;
      final note = List.filled(30, 'A longer note from the barangay. ').join();
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: MapRoadPreview(
              road: RoadStatus(
                id: 'road',
                name: 'A road',
                status: 'not_passable',
                notes: note,
                updatedAt: DateTime.now(),
              ),
              weather: WeatherState.clear,
              onOpen: () => opened++,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final hint = find.byKey(const ValueKey('preview-read-more'));
      expect(hint, findsOneWidget);
      await tester.ensureVisible(hint);
      await tester.pumpAndSettle();
      await tester.tap(hint);
      await tester.pump();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
