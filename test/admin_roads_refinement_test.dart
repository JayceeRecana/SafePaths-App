import 'package:safepaths_app/widgets/user_report_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/services/admin_road_overview.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/screens/admin/road_report_queue_screen.dart';
import 'package:safepaths_app/widgets/admin_road_summary.dart';
import 'dart:async';
import 'package:safepaths_app/screens/admin/update_road_status_screen.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/theme/app_theme.dart';

final now = DateTime.now();
RoadStatus road(
  String id,
  String status, {
  bool verified = true,
  Duration age = const Duration(minutes: 5),
  String risk = 'Safe',
  DateTime? time,
}) => RoadStatus(
  id: id,
  name: 'Road $id',
  status: status,
  notes: 'Recorded findings',
  updatedAt: time ?? now.subtract(age),
  isVerified: verified,
  source: verified ? 'manual' : 'osm',
  vulnerability: 'high',
  riskCategory: risk,
  riskScore: risk == 'Safe' ? 0 : 85,
);
UserReport report(
  String id,
  String status,
  String roadId, {
  bool urgent = false,
}) => UserReport(
  id: id,
  userId: 'resident',
  roadId: roadId,
  title: 'Flood observation',
  description: 'Observed water near the crossing.',
  severity: 'High',
  status: status,
  createdAt: now.subtract(const Duration(minutes: 20)),
  isEmergency: urgent,
);
Widget shell(
  Widget page, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  key: ValueKey('$dark:$language:$scale'),
  theme: dark ? AppTheme.darkTheme : AppTheme.theme,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'ADMIN_OPERATIONS_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  late List<RoadStatus> originalRoads;
  late List<UserReport> originalReports;
  late Map<String, SyncCondition> originalSync;
  setUp(() {
    final state = AppStateService.instance;
    originalRoads = [...state.roads];
    originalReports = [...state.reports];
    originalSync = {...state.syncHealth.channels};
    state.roads
      ..clear()
      ..addAll([
        road('fresh', 'passable'),
        road('closed', 'not_passable', age: const Duration(days: 1)),
        road('partial', 'partial'),
        road('unconfirmed', 'passable', verified: false),
        road('future', 'passable', time: now.add(const Duration(hours: 1))),
      ]);
    state.reports
      ..clear()
      ..addAll([
        report('pending', 'pending', 'closed'),
        report('reviewing', 'under_review', 'closed'),
        report('waiting', 'waiting_resident', 'closed'),
        report('urgent', 'waiting_resident', 'partial', urgent: true),
      ]);
    state.syncHealth.channels['roads'] = SyncCondition.live;
    state.syncHealth.channels['reports'] = SyncCondition.live;
  });
  tearDown(() {
    final state = AppStateService.instance;
    state.roads
      ..clear()
      ..addAll(originalRoads);
    state.reports
      ..clear()
      ..addAll(originalReports);
    state.syncHealth.channels
      ..clear()
      ..addAll(originalSync);
  });
  test(
    'road summary partitions confirmed, unknown and restricted records without turning an old closure passable',
    () {
      final list = AppStateService.instance.roads,
          summary = AdminRoadOverview(list, now, WeatherState.clear);
      expect(summary.count('passable'), 1);
      expect(summary.count('not_passable'), 1);
      expect(summary.count('partial'), 1);
      expect(summary.count('unconfirmed'), 2);
      expect(
        summary.checks.map((r) => r.road.id),
        containsAll(['closed', 'unconfirmed', 'future']),
      );
      expect(
        AdminRoadAssessment(
          list[1],
          now.add(const Duration(days: 30)),
          WeatherState.clear,
        ).category,
        'not_passable',
      );
      expect(list[1].status, 'not_passable');
      expect(list[3].status, 'passable');
    },
  );
  test(
    'prediction stays separate, stale rain status needs a check and invalid times cannot become confirmed passable',
    () {
      expect(
        AdminRoadAssessment(
          road('prediction', 'passable', risk: 'Critical'),
          now,
          WeatherState.clear,
        ).category,
        'passable',
      );
      expect(
        AdminRoadAssessment(
          road('rain', 'passable', age: const Duration(minutes: 31)),
          now,
          WeatherState.heavyRain,
        ).category,
        'unconfirmed',
      );
      expect(
        AdminRoadAssessment(
          road(
            'missing',
            'passable',
            time: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          now,
          WeatherState.clear,
        ).category,
        'unconfirmed',
      );
      expect(
        AdminRoadAssessment(
          road('unknown', 'unknown'),
          now,
          WeatherState.clear,
        ).category,
        'unconfirmed',
      );
    },
  );
  test(
    'road workload includes started reviews, keeps resident replies separate and deduplicates reports',
    () {
      final records = AppStateService.instance.reports;
      final counts = reportsByRoad([
        ...records,
        records.first,
        report('done', 'verified', 'closed'),
      ]);
      expect(counts['closed']!.needsAdmin, 2);
      expect(counts['closed']!.waiting, 1);
      expect(counts['closed']!.open.length, 3);
      expect(counts['partial']!.urgent, 1);
      expect(counts['partial']!.needsAdmin, 0);
    },
  );
  testWidgets(
    'selecting a road opens one fresh update form, with no duplicated outer condition picker',
    (tester) async {
      await tester.pumpWidget(
        shell(
          UpdateRoadStatusScreen(
            loadReviewContext: () async => {
              'token': 'test',
              'workflowVersion': 2,
              'roads': [
                {
                  'id': 'closed',
                  'name': 'Road closed',
                  'status': 'not_passable',
                  'vulnerability': 'high',
                },
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-road-closed')));
      await tester.pumpAndSettle();
      expect(find.text('Add Details (Notes & Flood Info)'), findsNothing);
      expect(find.text('Impassable'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-road-review')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-road-review')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AdminReviewDialog>(
        find.byType(AdminReviewDialog),
      );
      expect(dialog.roadIds, ['closed']);
      expect(dialog.initialStatus, isNull);
      expect(dialog.initialNote, isNull);
      expect(dialog.showRoadSettings, true);
      expect(dialog.quickConditions, true);
      expect(
        find.byKey(const ValueKey('quick-condition-passable')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changing road search clears bulk selection so hidden roads cannot be updated',
    (tester) async {
      await tester.pumpWidget(shell(const UpdateRoadStatusScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select multiple roads'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-road-closed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-road-review')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fresh');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-road-review')), findsNothing);
      expect(find.byKey(const ValueKey('admin-road-closed')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'matching-road selection is explicit, bounded to 20 and carries the visible IDs into one form',
    (tester) async {
      await tester.pumpWidget(
        shell(
          UpdateRoadStatusScreen(
            loadReviewContext: () async => {
              'token': 'test',
              'roads': AppStateService.instance.roads
                  .map((r) => {'id': r.id, 'name': r.name, 'status': r.status})
                  .toList(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select multiple roads'));
      await tester.pumpAndSettle();
      final select = find.byKey(const ValueKey('select-matching-roads'));
      await tester.ensureVisible(select);
      await tester.pumpAndSettle();
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-road-review')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-road-review')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AdminReviewDialog>(find.byType(AdminReviewDialog))
            .roadIds,
        containsAll(['closed', 'partial', 'future', 'unconfirmed', 'fresh']),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      AppStateService.instance.roads
        ..clear()
        ..addAll(List.generate(21, (i) => road('bulk$i', 'passable')));
      await tester.pumpWidget(shell(const UpdateRoadStatusScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select multiple roads'));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(select).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'bulk20');
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(select).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'roads expose condition and restriction-recheck filters; vulnerability stays in secondary filters',
    (tester) async {
      await tester.pumpWidget(shell(const UpdateRoadStatusScreen()));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(field.items!.map((item) => item.value), [
        'all',
        'needs_check',
        'restricted_recheck',
        'not_passable',
        'partial',
        'passable',
        'unconfirmed',
      ]);
      await tester.tap(find.byTooltip('More filters'));
      await tester.pumpAndSettle();
      expect(find.text('Flood-prone roads only'), findsOneWidget);
      await tester.tap(find.byType(CheckedPopupMenuItem<bool>));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'road setting changes reset confirmation and are saved only through the checked review',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminReviewDialog(
              roadIds: const ['closed'],
              showRoadSettings: true,
              loadContext: () async => {
                'token': 'test',
                'roads': [
                  {'id': 'closed', 'name': 'Road closed', 'status': 'partial'},
                ],
              },
              perform: (action, data) async {
                saved = data;
                expect(action, 'road_review');
                return const AdminActionResult(
                  action: 'road_review',
                  roadStatus: 'not_passable',
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not passable').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Field staff checked current flooding at the crossing.',
      );
      await tester.pump();
      final confirmation = find.byKey(
        const ValueKey('admin-review-confirmation'),
      );
      await tester.ensureVisible(confirmation);
      await tester.pumpAndSettle();
      await tester.tap(confirmation);
      await tester.pump();
      await tester.ensureVisible(find.text('More road settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More road settings'));
      await tester.pumpAndSettle();
      final setting = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(setting);
      await tester.pumpAndSettle();
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(confirmation).value, false);
      await tester.ensureVisible(confirmation);
      await tester.pumpAndSettle();
      await tester.tap(confirmation);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(saved?['vulnerability'], 'high');
      expect(saved?['roadIds'], ['closed']);
      expect(saved?['verifiedCurrentConditions'], true);
      expect(saved?.containsKey('reportId'), false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'selected roads fit 320 pixels, large text and both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              const UpdateRoadStatusScreen(prefilledRoadId: 'closed'),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );
  testWidgets(
    'road list hides technical references and decorative live indicator, but opens road-scoped reports',
    (tester) async {
      await tester.pumpWidget(shell(const UpdateRoadStatusScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Road reference'), findsNothing);
      expect(find.byType(AdminDataNotice), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-road-closed')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Road reports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road reports'));
      await tester.pumpAndSettle();
      expect(find.byType(RoadReportQueueScreen), findsOneWidget);
      expect(
        tester
            .widgetList<UserReportCard>(find.byType(UserReportCard))
            .map((c) => c.report.id),
        ['pending', 'reviewing'],
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Waiting for resident').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<UserReportCard>(find.byType(UserReportCard))
            .map((c) => c.report.id),
        ['waiting'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'quick road check requires a chosen condition and findings, sends one explicit attestation, preserves failed draft',
    (tester) async {
      var attempts = 0;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminReviewDialog(
              roadIds: const ['closed'],
              quickConditions: true,
              loadContext: () async => {
                'token': 'test',
                'roads': [
                  {'id': 'closed', 'name': 'Road closed', 'status': 'partial'},
                ],
              },
              perform: (action, data) async {
                attempts++;
                saved = data;
                throw StateError('offline');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('admin-review-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField),
        'CCTV operator checked current flooding at this time.',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final choice = find.byKey(const ValueKey('quick-condition-not_passable'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin-review-confirmation')),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(saved?['verifiedCurrentConditions'], true);
      expect(saved?['roadStatus'], 'not_passable');
      expect(saved?['reportId'], isNull);
      expect(
        find.textContaining('The save was not confirmed.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('CCTV operator'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'map editor retains road identity while loading or unavailable, and blocks unconfirmed saves',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SizedBox(
              height: 480,
              child: AdminReviewDialog(
                roadIds: const ['closed'],
                previewRoad: road('closed', 'not_passable'),
                mapSheet: true,
                quickConditions: true,
                loadContext: () => pending.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Road closed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Road closed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'map form fits large text, keyboard-sized viewport, themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil'])
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SizedBox(
                  height: 420,
                  child: AdminReviewDialog(
                    roadIds: const ['closed'],
                    previewRoad: road('closed', 'not_passable'),
                    mapSheet: true,
                    quickConditions: true,
                    loadContext: () async => {
                      'token': 'test',
                      'roads': [
                        {
                          'id': 'closed',
                          'name':
                              'A very long residential road name near the crossing',
                          'status': 'not_passable',
                          'isVerified': true,
                          'updatedAt': now.toIso8601String(),
                        },
                      ],
                    },
                  ),
                ),
              ),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
    },
  );
  testWidgets(
    'eleven-day-old passability is history, not a current green confirmation',
    (tester) async {
      final old = road('old', 'passable', age: const Duration(days: 11));
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: AdminRoadSummary(
                assessment: AdminRoadAssessment(old, now, WeatherState.clear),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current condition unknown'), findsOneWidget);
      expect(find.text('Last confirmed passable: 11 days ago'), findsOneWidget);
      expect(find.text('A new barangay check is needed.'), findsOneWidget);
      expect(find.text('Passable'), findsNothing);
      expect(old.status, 'passable');
      expect(old.isVerified, true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unverified map data never claims an earlier barangay confirmation',
    (tester) async {
      final imported = road(
        'imported',
        'passable',
        verified: false,
        age: const Duration(days: 11),
      );
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminRoadSummary(
              assessment: AdminRoadAssessment(
                imported,
                now,
                WeatherState.clear,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current condition unknown'), findsOneWidget);
      expect(find.text('Map record saved: 11 days ago'), findsOneWidget);
      expect(
        find.text('No barangay verification is recorded for this map data.'),
        findsOneWidget,
      );
      expect(find.textContaining('Last confirmed'), findsNothing);
      expect(find.text('Passable'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recent verified passability stays distinct from a stale restriction and new resident concern',
    (tester) async {
      Future<void> show(RoadStatus r) async {
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: AdminRoadSummary(
                assessment: AdminRoadAssessment(r, now, WeatherState.clear),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(road('fresh', 'passable'));
      expect(find.text('Passable'), findsOneWidget);
      expect(find.text('Current condition unknown'), findsNothing);
      expect(find.text('Last barangay check: 5 minutes ago'), findsOneWidget);
      await show(road('closed', 'not_passable', age: const Duration(days: 11)));
      expect(find.text('Last recorded: Not passable'), findsOneWidget);
      expect(find.text('A new barangay check is needed.'), findsOneWidget);
      expect(find.text('Current condition unknown'), findsNothing);
      await show(
        road(
          'concern',
          'passable',
        ).copyWith(communityCondition: 'reported_flooding'),
      );
      expect(find.text('Current condition unknown'), findsOneWidget);
      expect(
        find.text('Resident observations need a new barangay check.'),
        findsOneWidget,
      );
      expect(find.text('Passable'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'missing verification metadata is unavailable information, not evidence that no check ever happened',
    () {
      final a = AdminRoadAssessment(
        road('record', 'passable'),
        now,
        WeatherState.clear,
        verificationKnown: false,
      );
      expect(a.summaryTitle, 'Current condition unknown');
      expect(
        a.summaryExplanation,
        'Barangay verification details are unavailable for this record.',
      );
      expect(a.historyLabel, 'Road record saved');
    },
  );
  testWidgets(
    'compact status tiles share one row and equal bounds on a normal phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminReviewDialog(
              roadIds: const ['closed'],
              quickConditions: true,
              loadContext: () async => {
                'token': 'test',
                'roads': [
                  {'id': 'closed', 'name': 'Road closed', 'status': 'partial'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final a = find.byKey(const ValueKey('quick-condition-not_passable')),
          b = find.byKey(const ValueKey('quick-condition-partial')),
          c = find.byKey(const ValueKey('quick-condition-passable'));
      await tester.ensureVisible(a);
      await tester.pumpAndSettle();
      expect(tester.getRect(a).top, tester.getRect(b).top);
      expect(tester.getRect(b).top, tester.getRect(c).top);
      expect(tester.getSize(a), tester.getSize(b));
      expect(tester.getSize(b), tester.getSize(c));
      await tester.tap(b);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
