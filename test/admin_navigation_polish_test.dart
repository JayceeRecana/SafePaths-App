// ignore_for_file: depend_on_referenced_packages
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
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/screens/admin/admin_home_screen.dart';
import 'package:safepaths_app/screens/admin/admin_panel_screen.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'package:safepaths_app/screens/admin/update_road_status_screen.dart';
import 'package:safepaths_app/screens/admin/weather_simulator_screen.dart';
import 'package:safepaths_app/widgets/admin_bottom_nav_bar.dart';
import 'package:safepaths_app/widgets/admin_choice_field.dart';
import 'package:safepaths_app/widgets/admin_graph_rebuild_dialog.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

UserReport record(String id, {String status = 'under_review'}) => UserReport(
  id: id,
  title: 'Recorded report',
  description: 'Observed water near the crossing.',
  createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
  severity: 'High',
  status: status,
  userId: 'resident',
);
final graph = {
  'totalRoads': 2,
  'avgNeighbors': 1.0,
  'disconnectedRoads': 0,
  'maximumNeighbors': 1,
  'connectedComponents': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    auth.FirebaseAuthPlatform.instance = fixtures.TestAuth()..signIn('admin');
    store.FirebaseFirestorePlatform.instance = fixtures.TestStore();
    dotenv.loadFromString(envString: 'ADMIN_POLISH_TEST=true');
  });
  setUp(() {
    final state = AppStateService.instance;
    state.roads.clear();
    state.reports.clear();
    state.alerts.clear();
    state.syncHealth.channels.updateAll((k, v) => SyncCondition.live);
  });
  test(
    'a failed legacy graph read propagates failure instead of returning empty success',
    () async {
      await expectLater(
        AppStateService.instance.buildAndVerifyRoadGraph(),
        throwsA(anything),
      );
    },
    skip: AppEnvironment.sparkCoreEnabled,
  );
  testWidgets(
    'admin work notification selects the exact report and repeated taps reopen it',
    (tester) async {
      void Function(Map<String, dynamic>?)? tap;
      await tester.pumpWidget(
        fixtures.shell(
          AdminHomeScreen(
            initialize: () async {},
            attachTap: (callback) {
              tap = callback;
              return 99;
            },
            detachTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      var revision = 0;
      for (final kind in ['report_new_admin', 'report_reply_admin']) {
        tap!({'type': kind, 'reportId': 'exact-report'});
        await tester.pumpAndSettle();
        final reports = tester.widget<UserReportsScreen>(
          find.byType(UserReportsScreen),
        );
        expect(reports.initialReportId, 'exact-report');
        expect(reports.isActive, isTrue);
        expect(reports.openRequestRevision, greaterThan(revision));
        revision = reports.openRequestRevision;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'road inspection Back closes selection first; notifications and inactive tabs cannot hide navigation elsewhere',
    (tester) async {
      final state = AppStateService.instance;
      state.roads.add(
        RoadStatus(
          id: 'road',
          name: 'Recorded road',
          status: 'passable',
          notes: 'Verified finding',
          updatedAt: DateTime.now(),
          isVerified: true,
        ),
      );
      void Function(Map<String, dynamic>?)? tap;
      await tester.pumpWidget(
        fixtures.shell(
          AdminHomeScreen(
            initialize: () async {},
            attachTap: (callback) {
              tap = callback;
              return 7;
            },
            detachTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ROADS'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('admin-road-road')));
      await tester.tap(find.byKey(const ValueKey('admin-road-road')));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      expect(find.byType(UpdateRoadStatusScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminPanelScreen), findsOneWidget);
      await tester.tap(find.text('ROADS'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('admin-road-road')));
      await tester.tap(find.byKey(const ValueKey('admin-road-road')));
      await tester.pumpAndSettle();
      tap!({'type': 'broadcast'});
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminPanelScreen), findsOneWidget);
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      tap!({'type': 123});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'report inspection does not trap Back or hide navigation after an alert switches tabs',
    (tester) async {
      AppStateService.instance.reports.add(record('report'));
      void Function(Map<String, dynamic>?)? tap;
      await tester.pumpWidget(
        fixtures.shell(
          AdminHomeScreen(
            initialize: () async {},
            attachTap: (callback) {
              tap = callback;
              return 8;
            },
            detachTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('REPORTS'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(UserReportCard));
      await tester.tap(find.byType(UserReportCard));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsNothing);
      tap!({'type': 'broadcast'});
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminPanelScreen), findsOneWidget);
      await tester.tap(find.text('REPORTS'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminBottomNavBar), findsOneWidget);
      expect(find.byType(UserReportsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'direct history entry actually loads and has one recoverable failure panel',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          UserReportsScreen(
            initiallyHistory: true,
            historyLoader: (cursor) async {
              calls++;
              if (calls == 1) throw StateError('offline');
              return ReportPage([record('saved', status: 'verified')]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Report history unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('History is unavailable.'), findsNothing);
      expect(
        find.text(
          'History could not be loaded. Check your connection and retry.',
        ),
        findsNothing,
      );
      expect(
        find.text('Grouped by submission date, newest first.'),
        findsNothing,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(UserReportCard), findsOneWidget);
      expect(find.text('Report history unavailable'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed refresh keeps loaded report history while explaining it is not confirmed current',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          UserReportsScreen(
            initiallyHistory: true,
            historyLoader: (cursor) async {
              calls++;
              if (calls > 1) throw StateError('offline');
              return ReportPage([record('saved', status: 'verified')]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh reports'));
      await tester.pumpAndSettle();
      expect(find.byType(UserReportCard), findsOneWidget);
      expect(find.text('History could not refresh'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'graph rebuild requires confirmation, blocks repeats and only accepts a validated result',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AdminGraphRebuildDialog(
                    rebuild: () {
                      calls++;
                      return pending.future;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Rebuild connections'));
      await tester.pump();
      expect(calls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AdminGraphRebuildDialog), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      pending.complete(graph);
      await tester.pumpAndSettle();
      expect(find.text('Road connections rebuilt'), findsOneWidget);
      expect(find.text('Roads processed: 2'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'empty graph acknowledgement is a failure and retry can recover without false success',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(const Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AdminGraphRebuildDialog(
          rebuild: () async {
            calls++;
            return calls == 1 ? {} : graph;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rebuild connections'));
      await tester.pumpAndSettle();
      expect(find.text('Road connections rebuilt'), findsNothing);
      expect(
        find.text(
          'The rebuild was not confirmed. Check your connection and retry.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Road connections rebuilt'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'styled road menu retains the matching filter and visible toolbar actions',
    (tester) async {
      AppStateService.instance.roads.add(
        RoadStatus(
          id: 'old',
          name: 'Old restriction',
          status: 'not_passable',
          notes: 'Recorded finding',
          updatedAt: DateTime.now().subtract(const Duration(days: 11)),
          isVerified: true,
        ),
      );
      await tester.pumpWidget(fixtures.shell(const UpdateRoadStatusScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(AdminChoiceField));
      await tester.tap(find.byType(AdminChoiceField));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restricted roads to recheck').last);
      await tester.tap(find.text('Restricted roads to recheck').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'restricted_recheck',
      );
      expect(find.byKey(const ValueKey('admin-road-old')), findsOneWidget);
      expect(find.byTooltip('Select multiple roads'), findsOneWidget);
      expect(find.byTooltip('Live Map'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'drill confirmation identifies the configured area before any mutation',
    (tester) async {
      await tester.pumpWidget(fixtures.shell(const WeatherSimulatorScreen()));
      await tester.pumpAndSettle();
      final chip = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .firstWhere((c) => !c.selected);
      chip.onSelected!(true);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(AppEnvironment.area.name),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('for the test area'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(
            AppEnvironment.sparkCoreEnabled || !AppEnvironment.isFieldTest
                ? '30 minutes'
                : 'until changed or reset',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'history failure panel and styled menus fit large text in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              UserReportsScreen(
                initiallyHistory: true,
                historyLoader: (_) async => throw StateError('offline'),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byKey(const ValueKey('report-list-scroll')),
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            fixtures.shell(
              const UpdateRoadStatusScreen(initialFilter: 'restricted_recheck'),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
