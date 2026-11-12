import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/models/road_incident.dart';
import 'package:safepaths_app/screens/user/road_details_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/road_incident_service.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/utils/report_freshness.dart';
import 'package:safepaths_app/widgets/road_incident_panel.dart';
import 'package:safepaths_app/widgets/road_reports_section.dart';
import 'package:safepaths_app/widgets/road_condition_overview.dart';

final now = DateTime(2026, 10, 26, 12);
UserReport report(
  String id, {
  String status = 'pending',
  String roadId = 'road',
  DateTime? observed,
  DateTime? created,
}) => UserReport(
  id: id,
  userId: 'resident',
  title: 'Test observation',
  description: 'Observation $id',
  roadId: roadId,
  createdAt: created ?? now,
  observedAt: observed,
  status: status,
  severity: 'High',
);

Widget shell(Widget child, {String language = 'en', bool dark = false}) =>
    MaterialApp(
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('fil')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'ROAD_DETAILS_TEST=true');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDownAll(() async {
    await AppStateService.instance.clearSession();
    SimulatedWeatherService.instance.dispose();
  });

  test(
    'awaiting-review list uses observation freshness and road, not submission age',
    () {
      final items = [
        report('older', observed: now.subtract(const Duration(hours: 2))),
        report(
          'fresh-observation',
          status: 'under_review',
          observed: now.subtract(const Duration(minutes: 1)),
          created: now.subtract(const Duration(days: 2)),
        ),
        report(
          'new-submission-old-observation',
          observed: now.subtract(const Duration(hours: 24)),
        ),
        report('future', observed: now.add(const Duration(minutes: 2))),
        report('other-road', roadId: 'another'),
        for (final status in ['verified', 'resolved', 'dismissed', 'expired'])
          report(status, status: status),
      ];
      expect(
        ReportFreshness.awaitingReviewForRoad(
          items,
          'road',
          now,
        ).map((r) => r.id),
        ['fresh-observation', 'older'],
      );
    },
  );

  testWidgets(
    'loading, cache and failure never claim an empty live report list',
    (tester) async {
      var retries = 0;
      for (final condition in [
        SyncCondition.connecting,
        SyncCondition.cached,
        SyncCondition.failed,
      ]) {
        await tester.pumpWidget(
          shell(
            RoadReportsSection(
              roadId: 'road',
              reports: const [],
              syncCondition: condition,
              now: now,
              onRetry: () => retries++,
              onOpen: (_) {},
            ),
          ),
        );
        expect(
          find.text('No recent reports are awaiting review for this road.'),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('road-report-count')), findsNothing);
        if (condition == SyncCondition.connecting) {
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
        } else {
          await tester.tap(find.text('Retry reports'));
        }
      }
      expect(retries, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cached reports remain readable and taps identify the right report',
    (tester) async {
      UserReport? opened;
      await tester.pumpWidget(
        shell(
          RoadReportsSection(
            roadId: 'road',
            reports: [report('saved')],
            syncCondition: SyncCondition.cached,
            now: now,
            onRetry: () {},
            onOpen: (value) => opened = value,
          ),
        ),
      );
      expect(find.textContaining('Showing saved reports.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('road-report-saved')));
      expect(opened?.id, 'saved');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'verified reports leave the review list while the road can remain closed',
    (tester) async {
      final road = RoadStatus(
        id: 'road',
        name: 'Test road',
        status: 'not_passable',
        notes: 'Closure retained',
        updatedAt: now,
      );
      Future<void> render(List<UserReport> reports) => tester.pumpWidget(
        shell(
          RoadReportsSection(
            roadId: road.id,
            reports: reports,
            syncCondition: SyncCondition.live,
            now: now,
            onRetry: () {},
            onOpen: (_) {},
          ),
        ),
      );
      await render([report('reviewing', status: 'under_review')]);
      expect(find.text('Observation reviewing'), findsOneWidget);
      await render([report('reviewing', status: 'verified')]);
      expect(find.text('Observation reviewing'), findsNothing);
      expect(
        find.text('No recent reports are awaiting review for this road.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('road-report-count')), findsNothing);
      expect(road.status, 'not_passable');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'embedded observations omit the duplicate admin note and retain responses',
    (tester) async {
      final stream = StreamController<RoadIncidentSnapshot>();
      addTearDown(stream.close);
      String? selected;
      await tester.pumpWidget(
        shell(
          RoadIncidentPanel(
            roadId: 'road',
            showAdminReview: false,
            stream: stream.stream,
            onObserve: (_, choice) async {
              selected = choice;
            },
          ),
        ),
      );
      stream.add(
        RoadIncidentSnapshot(
          RoadIncident(
            roadId: 'road',
            incidentId: 'incident',
            revision: 1,
            state: 'admin_confirmed',
            lastObservedAt: DateTime.now(),
            reviewedAt: DateTime.now(),
            reviewNote: 'Duplicate note',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Duplicate note'), findsNothing);
      expect(find.text('Quick observations'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('incident-observe-appears_passable')),
      );
      await tester.tap(
        find.byKey(const ValueKey('incident-observe-appears_passable')),
      );
      await tester.pump();
      expect(selected, 'appears_passable');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'road details put status, one admin note and report action before predictions',
    (tester) async {
      await AppStateService.instance.initialize();
      final service = AppStateService.instance;
      service.syncHealth.update('roads', fromCache: false);
      service.syncHealth.update('reports', fromCache: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: const RoadDetailsScreen(roadId: 'macarthur'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flooded'), findsOneWidget);
      expect(find.text('Current Conditions'), findsNothing);
      expect(find.textContaining('Accuracy'), findsNothing);
      expect(find.text('100%'), findsNothing);
      expect(
        tester.getTopLeft(find.text('NOT PASSABLE')).dy,
        lessThan(tester.getTopLeft(find.text('BARANGAY UPDATE')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Report Update')).dy,
        lessThan(tester.getTopLeft(find.text('Prediction details')).dy),
      );
      expect(find.text('PREDICTIVE INTELLIGENCE'), findsNothing);
      await tester.ensureVisible(find.text('Prediction details'));
      await tester.tap(find.text('Prediction details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scores are not measured accuracy'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'road details start below full screen and keep close available after scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppStateService.instance.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(RoadDetailsScreen.route('macarthur')),
                child: const Text('Open road details'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open road details'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('road-details-sheet'));
      expect(tester.getSize(sheet).height, closeTo(800 * .6 - 12, 1));
      final viewport = find.byKey(const ValueKey('road-details-viewport'));
      expect(
        tester.getBottomRight(sheet).dy,
        closeTo(tester.getBottomRight(viewport).dy - 12, 1),
      );
      expect(tester.getTopLeft(sheet).dy, closeTo(800 * .4, 1));
      expect(tester.getSize(viewport).height, closeTo(800, 1));
      expect(tester.getTopLeft(sheet).dx, closeTo(16, 1));
      expect(tester.getSize(sheet).width, closeTo(328, 1));
      final content = find.byKey(const ValueKey('road-details-content'));
      await tester.drag(content, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, closeTo(800 * .6 - 12, 1));
      expect(
        tester.getBottomRight(sheet).dy,
        closeTo(tester.getBottomRight(viewport).dy - 12, 1),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: content, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.pixels, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('road-details-handle')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, greaterThan(800 * .6));
      expect(
        tester.getBottomRight(sheet).dy,
        closeTo(tester.getBottomRight(viewport).dy - 12, 1),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('road-prediction-details')),
      );
      await tester.pumpAndSettle();
      final close = find.byKey(const ValueKey('close-road-details'));
      expect(
        tester.getRect(close).top - tester.getRect(sheet).top,
        greaterThanOrEqualTo(8),
      );
      expect(
        tester.getRect(sheet).right - tester.getRect(close).right,
        greaterThanOrEqualTo(8),
      );
      expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
      expect(tester.getCenter(close).dy, inInclusiveRange(0, 800));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Open road details'), findsOneWidget);
      expect(find.byType(RoadDetailsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'road details and expanded predictions fit English and Filipino large text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppStateService.instance.initialize();
      final service = AppStateService.instance;
      service.syncHealth.update('roads', fromCache: false);
      service.syncHealth.update('reports', fromCache: false);
      service.syncHealth.lastRiskCompute = DateTime.now();
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.theme,
              darkTheme: AppTheme.darkTheme,
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('fil')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
              home: const RoadDetailsScreen(roadId: 'macarthur'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$language/$dark initial details',
          );
          final predictions = find.byKey(
            const ValueKey('road-prediction-details'),
          );
          await tester.ensureVisible(predictions);
          await tester.tap(predictions);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$language/$dark expanded predictions',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
  testWidgets(
    'road sheet resize also works when system animations are disabled',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppStateService.instance.initialize();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const RoadDetailsScreen(roadId: 'macarthur'),
        ),
      );
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('road-details-sheet'));
      final toggle = find.byTooltip('Expand or collapse road details');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(sheet).height, closeTo(800 * .95 - 12, 1));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(sheet).height, closeTo(800 * .6 - 12, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'resident labels remove the technical suffix without changing named roads or IDs',
    () {
      expect(
        residentRoadTitle('Unnamed residential (OSM 552835258)'),
        'Unnamed residential road',
      );
      expect(
        residentRoadTitle('MacArthur Highway (OSM 1234)'),
        'MacArthur Highway',
      );
      expect(residentRoadTitle('Road 20'), 'Road 20');
    },
  );

  test(
    'recheck age follows flooded-road inspection policy, without clearing the status',
    () {
      for (final entry in {'high': 3, 'medium': 6, 'low': 12}.entries) {
        final road = RoadStatus(
          id: 'road',
          name: 'A road',
          status: 'not_passable',
          notes: 'Recorded closure',
          vulnerability: entry.key,
          updatedAt: now.subtract(Duration(hours: entry.value)),
        );
        expect(roadNeedsRecheck(road, now), isFalse);
        expect(
          roadNeedsRecheck(road, now.add(const Duration(seconds: 1))),
          isTrue,
        );
        expect(road.status, 'not_passable');
      }
    },
  );

  testWidgets(
    'old closure remains prominent, with recheck notice and a neutral themed admin card',
    (tester) async {
      final road = RoadStatus(
        id: 'preserved-id',
        name: 'Unnamed residential (OSM 552835258)',
        status: 'not_passable',
        notes: 'Keep this actual admin note.',
        updatedAt: now.subtract(const Duration(hours: 23)),
      );
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: Scaffold(
              body: SingleChildScrollView(
                child: RoadConditionOverview(
                  road: road,
                  now: now,
                  statusText: 'NOT PASSABLE',
                  statusBackground: Colors.red.shade100,
                  statusColor: Colors.red.shade900,
                  statusIcon: Icons.warning_rounded,
                  unconfirmed: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unnamed residential road'), findsOneWidget);
        expect(find.text('Unnamed residential (OSM 552835258)'), findsNothing);
        expect(find.text('NOT PASSABLE'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('road-recheck-notice')),
          findsOneWidget,
        );
        expect(find.text('Keep this actual admin note.'), findsOneWidget);
        final age = tester.widget<Text>(
          find.byKey(const ValueKey('road-update-age')),
        );
        expect(age.style!.fontSize, greaterThanOrEqualTo(13));
        expect(tester.takeException(), isNull);
      }
      expect(road.id, 'preserved-id');
      expect(road.name, 'Unnamed residential (OSM 552835258)');
      expect(road.status, 'not_passable');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'observation feedback and selected choice wait for acknowledgement and failures remain retryable',
    (tester) async {
      final stream = StreamController<RoadIncidentSnapshot>();
      addTearDown(stream.close);
      var save = Completer<void>();
      await tester.pumpWidget(
        shell(
          RoadIncidentPanel(
            roadId: 'road',
            showAdminReview: false,
            stream: stream.stream,
            onObserve: (_, _) => save.future,
          ),
        ),
      );
      stream.add(
        RoadIncidentSnapshot(
          RoadIncident(
            roadId: 'road',
            incidentId: 'incident',
            revision: 1,
            state: 'reported_flooding',
            lastObservedAt: DateTime.now(),
          ),
        ),
      );
      await tester.pump();
      final choice = find.byKey(
        const ValueKey('incident-observe-still_flooded'),
      );
      bool selected() =>
          tester
              .widget<Semantics>(
                find
                    .ancestor(of: choice, matching: find.byType(Semantics))
                    .first,
              )
              .properties
              .selected ==
          true;
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
      expect(find.textContaining('Salamat!'), findsNothing);
      expect(selected(), isFalse);
      save.completeError(StateError('Connection failed'));
      await tester.pump();
      expect(find.textContaining('Salamat!'), findsNothing);
      expect(selected(), isFalse);
      save = Completer<void>();
      await tester.tap(choice);
      await tester.pump();
      save.complete();
      await tester.pump();
      expect(find.textContaining('Salamat!'), findsOneWidget);
      expect(selected(), isTrue);
      expect(
        tester.getTopLeft(find.textContaining('Salamat!')).dy,
        lessThan(tester.getTopLeft(find.text('More details')).dy),
      );
      stream.add(
        RoadIncidentSnapshot(
          RoadIncident(
            roadId: 'road',
            incidentId: 'next-incident',
            revision: 1,
            state: 'reported_flooding',
            lastObservedAt: DateTime.now(),
          ),
        ),
      );
      await tester.pump();
      expect(selected(), isFalse);
      expect(find.textContaining('Salamat!'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'sheet stays at the bottom of the available area with a test banner and navigation reserved',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppStateService.instance.initialize();
      AppStateService.instance.syncHealth.update('roads', fromCache: false);
      AppStateService.instance.syncHealth.update('reports', fromCache: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: const SizedBox(height: 64),
            body: const Column(
              children: [
                SizedBox(height: 52),
                Expanded(child: RoadDetailsScreen(roadId: 'macarthur')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('road-details-viewport')),
      );
      final sheet = tester.getRect(
        find.byKey(const ValueKey('road-details-sheet')),
      );
      expect(viewport.top, closeTo(52, 1));
      expect(viewport.bottom, closeTo(736, 1));
      expect(sheet.bottom, closeTo(viewport.bottom - 12, 1));
      expect(sheet.top, closeTo(viewport.top + viewport.height * .4, 1));
      expect(sheet.height, closeTo(viewport.height * .6 - 12, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'inset details stay centered and respect width and bottom safe area on a large display',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppStateService.instance.initialize();
      AppStateService.instance.syncHealth.update('roads', fromCache: false);
      AppStateService.instance.syncHealth.update('reports', fromCache: false);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(bottom: 24)),
            child: child!,
          ),
          home: const RoadDetailsScreen(roadId: 'macarthur'),
        ),
      );
      await tester.pumpAndSettle();
      final sheet = tester.getRect(
        find.byKey(const ValueKey('road-details-sheet')),
      );
      expect(sheet.width, closeTo(680, 1));
      expect(sheet.left, closeTo((1024 - 680) / 2, 1));
      expect(sheet.bottom, closeTo(800 - 24 - 12, 1));
      expect(sheet.top, closeTo(800 * .4, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'grouped community card preserves unavailable observations and the separate live report result',
    (tester) async {
      final stream = StreamController<RoadIncidentSnapshot>();
      addTearDown(stream.close);
      await tester.pumpWidget(
        shell(
          RoadCommunityCard(
            observations: RoadIncidentPanel(
              roadId: 'road',
              embedded: true,
              showAdminReview: false,
              stream: stream.stream,
            ),
            reports: RoadReportsSection(
              roadId: 'road',
              reports: const [],
              embedded: true,
              syncCondition: SyncCondition.live,
              onRetry: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      stream.addError(StateError('Connection failed'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('road-community-updates')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Community observations are unavailable'),
        findsOneWidget,
      );
      expect(
        find.text('No recent reports are awaiting review for this road.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('incident-observe-still_flooded')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
