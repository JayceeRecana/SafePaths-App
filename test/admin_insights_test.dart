import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as store;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safepaths_app/services/admin_insights.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/screens/admin/admin_insights_screen.dart';
import 'package:safepaths_app/screens/admin/admin_panel_screen.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'package:safepaths_app/screens/admin/broadcast_alert_screen.dart';
import 'package:safepaths_app/screens/admin/update_road_status_screen.dart';
import 'package:safepaths_app/widgets/admin_bottom_nav_bar.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/screens/admin/weather_simulator_screen.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

final clock = DateTime(2026, 11, 1, 14);
UserReport report(
  String id, {
  String status = 'pending',
  DateTime? created,
  DateTime? reviewed,
  String? road = 'road',
  bool followup = false,
}) => UserReport(
  id: id,
  title: 'Synthetic report',
  description: 'Observed water',
  createdAt: created ?? clock.subtract(const Duration(hours: 1)),
  severity: 'High',
  status: status,
  userId: 'resident',
  roadId: road,
  reviewedAt: reviewed,
  reportType: followup ? 'followup' : 'original',
);
AdminInsightsData data({int days = 7, List<UserReport> reports = const []}) =>
    AdminInsightsData(
      start: DateTime(2026, 11, 2 - days),
      end: DateTime(2026, 11, 2),
      checkedAt: clock,
      reports: reports,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    auth.FirebaseAuthPlatform.instance = fixtures.TestAuth()..signIn('admin');
    store.FirebaseFirestorePlatform.instance = fixtures.TestStore();
    dotenv.loadFromString(envString: 'INSIGHTS_TEST=true');
  });
  testWidgets(
    'weather status never opens or changes a drill and unavailable weather has no invented temperature',
    (tester) async {
      final weather = SimulatedWeatherService.instance;
      final wasDrill = weather.isOverrideMode;
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: (d) async => data())),
      );
      await tester.pumpAndSettle();
      if (weather.isDataStale) {
        expect(find.text('Weather unavailable'), findsOneWidget);
        expect(find.textContaining('32°'), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('dashboard-weather-status')));
      await tester.pumpAndSettle();
      expect(find.byType(WeatherSimulatorScreen), findsNothing);
      expect(weather.isOverrideMode, wasDrill);
      expect(find.byType(AdminPanelScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'shared header and original navigation remain; road counts and recent See all open matching views',
    (tester) async {
      final state = AppStateService.instance;
      state.reports.clear();
      state.roads.clear();
      state.alerts.clear();
      state.syncHealth.channels.updateAll((k, v) => SyncCondition.live);
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: AdminPanelScreen(loadInsights: (d) async => data()),
            bottomNavigationBar: AdminBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SafePaths Admin'), findsOneWidget);
      expect(find.byTooltip('Profile'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('ROADS'), findsOneWidget);
      expect(find.text('ALERTS'), findsOneWidget);
      expect(find.text('REPORTS'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-road-unconfirmed')),
      );
      await tester.tap(
        find.byKey(const ValueKey('dashboard-road-unconfirmed')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<UpdateRoadStatusScreen>(find.byType(UpdateRoadStatusScreen))
            .initialFilter,
        'unconfirmed',
      );
      Navigator.of(tester.element(find.byType(UpdateRoadStatusScreen))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('See all').last);
      await tester.tap(find.text('See all').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<UserReportsScreen>(find.byType(UserReportsScreen))
            .initiallyHistory,
        isTrue,
      );
      expect(find.text('History'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('empty cohort is zero with unavailable rate and review time', () {
    final result = data();
    expect(result.received, 0);
    expect(result.verifiedPercent, isNull);
    expect(result.averageReviewMinutes, isNull);
    expect(result.buckets.fold<int>(0, (n, b) => n + b.count), 0);
    expect(result.roadCounts, isEmpty);
  });
  test(
    'every status is accounted for; waiting residents are separate and invalid review clocks are excluded',
    () {
      final reports = [
        report(
          'v',
          status: 'verified',
          reviewed: clock.subtract(const Duration(minutes: 30)),
        ),
        report(
          'd',
          status: 'dismissed',
          reviewed: clock.subtract(const Duration(minutes: 10)),
        ),
        report('p'),
        report('u', status: 'under_review'),
        report('w', status: 'waiting_resident'),
        report('e', status: 'expired'),
        report(
          'f',
          status: 'verified',
          reviewed: clock.subtract(const Duration(days: 3)),
          followup: true,
        ),
        report(
          'future-review',
          status: 'verified',
          reviewed: clock.add(const Duration(hours: 1)),
        ),
      ];
      final result = data(reports: reports);
      expect(result.received, 8);
      expect(result.verified, 3);
      expect(result.needsReview, 2);
      expect(result.waitingResident, 1);
      expect(result.notVerified, 1);
      expect(result.other, 1);
      expect(result.originals, 7);
      expect(result.followups, 1);
      expect(result.averageReviewMinutes, 40);
      expect(result.verifiedPercent, 38);
    },
  );
  test(
    'calendar boundaries, duplicate IDs, future submissions and all 30 days are handled consistently',
    () {
      final result = data(
        days: 30,
        reports: [
          report('first', created: DateTime(2026, 10, 3)),
          report('last', created: clock),
          report('old', created: DateTime(2026, 10, 2, 23, 59)),
          report('future', created: clock.add(const Duration(minutes: 1))),
          report('last', created: clock),
        ],
      );
      expect(result.received, 2);
      expect(result.buckets.first.start, DateTime(2026, 10, 3));
      expect(result.buckets.last.end, DateTime(2026, 11, 2));
      expect(result.buckets.fold<int>(0, (n, b) => n + b.count), 2);
      expect(result.roadCounts['road'], 2);
    },
  );
  test(
    'server repository rejects cache, oversized partial results, changed accounts and missing sign-in',
    () async {
      String? uid = 'admin';
      var calls = 0;
      AdminInsightsRepository repo(InsightsPage page) =>
          AdminInsightsRepository(
            currentUid: () => uid,
            now: () => clock,
            fetch: (start, end, limit) async {
              calls++;
              expect(start, DateTime(2026, 10, 26));
              expect(end, DateTime(2026, 11, 2));
              expect(limit, 1001);
              return page;
            },
          );
      await expectLater(
        repo(const InsightsPage([], fromCache: true)).load(7),
        throwsStateError,
      );
      await expectLater(
        repo(InsightsPage(List.generate(1001, (i) => report('$i')))).load(7),
        throwsStateError,
      );
      final pending = Completer<InsightsPage>();
      final changed = AdminInsightsRepository(
        currentUid: () => uid,
        now: () => clock,
        fetch: (s, e, l) => pending.future,
      ).load(7);
      uid = 'another-admin';
      pending.complete(const InsightsPage([]));
      await expectLater(changed, throwsStateError);
      uid = null;
      await expectLater(repo(const InsightsPage([])).load(7), throwsStateError);
      expect(calls, 2);
    },
  );
  testWidgets(
    'workload shortcuts open waiting replies, active alerts and roads needing checks',
    (tester) async {
      final state = AppStateService.instance;
      state.reports
        ..clear()
        ..add(report('waiting', status: 'waiting_resident'));
      state.roads.clear();
      state.alerts.clear();
      state.syncHealth.channels.updateAll((k, v) => SyncCondition.live);
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: (d) async => data())),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Waiting for resident'));
      await tester.tap(find.text('Waiting for resident'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<UserReportsScreen>(find.byType(UserReportsScreen))
            .initiallyWaitingResident,
        isTrue,
      );
      expect(find.text('Waiting for resident'), findsWidgets);
      Navigator.of(tester.element(find.byType(UserReportsScreen))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('0 alerts are still live'));
      await tester.tap(find.text('0 alerts are still live'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BroadcastAlertScreen>(find.byType(BroadcastAlertScreen))
            .initiallyActive,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(BroadcastAlertScreen))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('0 roads need a check'));
      await tester.tap(find.text('0 roads need a check'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<UpdateRoadStatusScreen>(find.byType(UpdateRoadStatusScreen))
            .initialFilter,
        'needs_check',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Insights shows empty states and real zeros, then reloads the full selected period once',
    (tester) async {
      var calls = 0;
      final ranges = <int>[];
      await tester.pumpWidget(
        fixtures.shell(
          AdminInsightsScreen(
            load: (days) async {
              calls++;
              ranges.add(days);
              return data(days: days);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No reports in this period.'), findsOneWidget);
      expect(find.text('82%'), findsNothing);
      expect(find.text('12 min'), findsNothing);
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(ranges, [7, 30]);
      await tester.tap(find.text('View as table'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'switching periods hides old metrics and a failed refresh never displays them',
    (tester) async {
      final first = Completer<AdminInsightsData>();
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          AdminInsightsScreen(
            load: (days) {
              calls++;
              return calls == 1
                  ? Future.value(data(reports: [report('a')]))
                  : calls == 2
                  ? first.future
                  : Future.error(StateError('offline'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 days'));
      await tester.pump();
      expect(find.text('No reports in this period.'), findsNothing);
      first.complete(data(days: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Insights unavailable. Connect and refresh; no totals are assumed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reports received'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Dashboard never invents work or recent activity when all live feeds are empty',
    (tester) async {
      final state = AppStateService.instance;
      state.reports.clear();
      state.roads.clear();
      state.alerts.clear();
      state.syncHealth.channels.updateAll((k, v) => SyncCondition.live);
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          AdminPanelScreen(
            loadInsights: (d) async {
              calls++;
              return data();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No outstanding checks in the live feeds'),
        findsOneWidget,
      );
      expect(find.text('3 reports to review'), findsNothing);
      expect(find.textContaining('Admin Maria'), findsNothing);
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(calls, 1);
      state.syncHealth.channels['reports'] = SyncCondition.cached;
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Workload needs a connection check'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Insights fits a narrow phone in both themes and languages at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              AdminInsightsScreen(
                load: (d) async =>
                    data(reports: [report('a', status: 'waiting_resident')]),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('100%'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          expect(find.text('100%'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
