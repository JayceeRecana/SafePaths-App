// ignore_for_file: depend_on_referenced_packages
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
import 'package:safepaths_app/services/admin_dashboard_signals.dart';
import 'package:safepaths_app/services/admin_insights.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/screens/admin/admin_panel_screen.dart';
import 'package:safepaths_app/screens/admin/admin_diagnostics_screen.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

final now = DateTime.now();
RoadStatus road(
  String id,
  String status, {
  bool old = false,
  String risk = 'Safe',
}) => RoadStatus(
  id: id,
  name: 'Road $id',
  status: status,
  notes: 'Recorded finding',
  isVerified: true,
  updatedAt: old ? now.subtract(const Duration(days: 11)) : now,
  riskCategory: risk,
);
UserReport report(String id, String status, {bool urgent = false}) =>
    UserReport(
      id: id,
      title: id,
      description: 'Recorded observation',
      createdAt: now.subtract(const Duration(minutes: 20)),
      severity: 'High',
      status: status,
      userId: 'resident',
      isEmergency: urgent,
    );
Future<AdminInsightsData> load(int days) async => AdminInsightsData(
  start: DateTime(now.year, now.month, now.day - 6),
  end: DateTime(now.year, now.month, now.day + 1),
  checkedAt: now,
  reports: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    auth.FirebaseAuthPlatform.instance = fixtures.TestAuth()..signIn('admin');
    store.FirebaseFirestorePlatform.instance = fixtures.TestStore();
    dotenv.loadFromString(envString: 'DASHBOARD_PRIORITY_TEST=true');
  });
  setUp(() {
    final state = AppStateService.instance;
    state.reports.clear();
    state.roads.clear();
    state.alerts.clear();
    state.syncHealth.reset(clearHistory: true);
    state.syncHealth.channels.updateAll((k, v) => SyncCondition.live);
  });
  test(
    'prediction freshness requires live road, weather and calculation data; drills and future clocks never qualify',
    () {
      AdminPredictionSummary summary({
        DateTime? time,
        SyncCondition sync = SyncCondition.live,
        bool roadsLive = true,
        bool weather = true,
        bool drill = false,
        List<RoadStatus>? roads,
      }) => AdminPredictionSummary(
        roads: roads ?? [road('critical', 'passable', risk: 'Critical')],
        computedAt: time ?? now,
        now: now,
        riskSync: sync,
        roadsLive: roadsLive,
        weatherFresh: weather,
        drill: drill,
      );
      expect(summary().current, isTrue);
      expect(summary().count('Critical'), 1);
      for (final result in [
        summary(time: now.subtract(const Duration(minutes: 5))),
        summary(time: now.add(const Duration(seconds: 1))),
        summary(sync: SyncCondition.cached),
        summary(sync: SyncCondition.failed),
        summary(roadsLive: false),
        summary(weather: false),
        summary(drill: true),
        summary(roads: []),
      ]) {
        expect(result.current, isFalse);
      }
      expect(summary(drill: true).label, 'Weather drill active');
    },
  );
  testWidgets(
    'urgent row comes first and opens only urgent open records, including waiting residents',
    (tester) async {
      final state = AppStateService.instance;
      state.roads.add(
        RoadStatus(
          id: 'unrelated',
          name: 'Unrelated road',
          status: 'passable',
          notes: 'Recorded finding',
          updatedAt: now,
          isVerified: true,
          communityCondition: 'reported_flooding',
        ),
      );
      state.reports.addAll([
        report('ordinary', 'pending'),
        report('urgent-review', 'under_review', urgent: true),
        report('urgent-waiting', 'waiting_resident', urgent: true),
        report('closed', 'verified', urgent: true),
      ]);
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: load)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Urgent open reports: 2')).dy,
        lessThan(tester.getTopLeft(find.text('2 reports to review')).dy),
      );
      await tester.ensureVisible(find.text('Urgent open reports: 2'));
      await tester.tap(find.text('Urgent open reports: 2'));
      await tester.pumpAndSettle();
      final scroll = find.byKey(const ValueKey('report-list-scroll'));
      await tester.drag(scroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<UserReportCard>(find.byType(UserReportCard))
          .map((c) => c.report.id)
          .toList();
      expect(cards, contains('urgent-review'));
      expect(cards, contains('urgent-waiting'));
      expect(cards, isNot(contains('ordinary')));
      expect(cards, isNot(contains('closed')));
      await tester.drag(scroll, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Check current road conditions'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'restriction recheck shortcut excludes fresh restrictions and stale passability',
    (tester) async {
      final state = AppStateService.instance;
      state.roads.addAll([
        road('old-closed', 'not_passable', old: true),
        road('old-partial', 'partial', old: true),
        road('fresh-closed', 'not_passable'),
        road('old-open', 'passable', old: true),
      ]);
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: load)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restricted roads to recheck: 2'));
      await tester.tap(find.text('Restricted roads to recheck: 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin-road-old-closed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-road-old-partial')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-road-fresh-closed')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('admin-road-old-open')), findsNothing);
      expect(state.roads.first.status, 'not_passable');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'weekly heading and action are within its card and empty chart space is removed',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: load)),
      );
      await tester.pumpAndSettle();
      final heading = find.text('Last 7 days');
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      final card = find
          .ancestor(of: heading, matching: find.byType(Container))
          .first;
      expect(tester.getRect(card).contains(tester.getCenter(heading)), isTrue);
      expect(
        tester
            .getRect(card)
            .contains(tester.getCenter(find.text('See insights'))),
        isTrue,
      );
      expect(
        tester
            .getRect(card)
            .contains(tester.getCenter(find.text('Reports received'))),
        isTrue,
      );
      expect(find.text('Oct 26'), findsNothing);
      await tester.ensureVisible(find.text('More details'));
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();
      expect(find.text('Predictions not confirmed'), findsOneWidget);
      expect(find.text('Critical: 0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'diagnostics stay separate, show unavailable measurements honestly and fit large text',
    (tester) async {
      final state = AppStateService.instance;
      state.syncHealth.channels['risk'] = SyncCondition.cached;
      state.lastRiskEngineRun = null;
      state.lastRiskEngineExecutionMs = 0;
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              const AdminDiagnosticsScreen(),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -1600));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('OPERATIONAL'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets(
    'technical diagnostics is reachable through a scrollable tools sheet',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(AdminPanelScreen(loadInsights: load)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Technical diagnostics'));
      await tester.tap(find.text('Technical diagnostics'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDiagnosticsScreen), findsOneWidget);
      expect(
        find.text(
          'Feed information does not confirm push delivery or the health of every service.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'priority cards fit both themes and languages at large text and cached risk never becomes current',
    (tester) async {
      final state = AppStateService.instance;
      state.reports.add(report('urgent', 'pending', urgent: true));
      state.roads.add(
        road('restricted', 'not_passable', old: true, risk: 'Critical'),
      );
      state.syncHealth.lastRiskCompute = now;
      state.syncHealth.channels['risk'] = SyncCondition.cached;
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              AdminPanelScreen(loadInsights: load),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Critical: 1'), findsNothing);
          expect(find.text('Current model output'), findsNothing);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
