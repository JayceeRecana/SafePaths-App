import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/l10n/formatters.dart';
import 'package:safepaths_app/utils/time_utils.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'package:safepaths_app/widgets/admin_report_inspector.dart';
import 'package:safepaths_app/theme/app_theme.dart';

UserReport record(
  String id,
  DateTime submitted, {
  DateTime? observed,
  bool emergency = false,
  String status = 'pending',
  DateTime? reviewed,
}) => UserReport(
  id: id,
  userId: 'resident',
  title: 'Flood: Road $id',
  description: 'Observation $id',
  severity: 'High',
  status: status,
  createdAt: submitted,
  observedAt: observed ?? submitted,
  isEmergency: emergency,
  reviewedAt: reviewed,
);
Widget shell(
  Widget child, {
  String language = 'en',
  bool dark = false,
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
void replaceReports(List<UserReport> reports) {
  final state = AppStateService.instance,
      previous = [...AppStateService.instance.reports];
  state.reports
    ..clear()
    ..addAll(reports);
  addTearDown(() {
    state.reports
      ..clear()
      ..addAll(previous);
  });
}

List<String> visibleIds(WidgetTester tester) => tester
    .widgetList<UserReportCard>(find.byType(UserReportCard))
    .map((c) => c.report.id)
    .toList();
Future<void> allReports(WidgetTester tester, {bool fil = false}) async {
  await tester.tap(find.text(fil ? 'Kasaysayan' : 'History'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byType(DropdownButtonFormField<String>).first,
  );
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  final option = find.text(fil ? 'Lahat ng ulat' : 'All reports');
  await tester.scrollUntilVisible(
    option,
    120,
    scrollable: find.byType(Scrollable).last,
  );
  for (
    var attempt = 0;
    attempt < 12 && option.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(option.hitTestable().last);
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

Future<void> recentReports(WidgetTester tester, {bool fil = false}) async {
  await allReports(tester, fil: fil);
  await tester.ensureVisible(find.byType(SwitchListTile));
  await tester.tap(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'TIMEKEEPING_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  test(
    'calendar grouping distinguishes yesterday across midnight, month and year boundaries',
    () {
      final today = DateTime(2027, 1, 1, 0, 2),
          yesterday = DateTime(2026, 12, 31, 23, 59);
      expect(today.difference(yesterday).inDays, 0);
      expect(
        TimeUtils.submissionDayKey(today, today),
        isNot(TimeUtils.submissionDayKey(yesterday, today)),
      );
      expect(
        TimeUtils.submissionDayKey(yesterday.toUtc(), today),
        TimeUtils.submissionDayKey(yesterday, today),
      );
      expect(
        TimeUtils.submissionDayKey(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 1, 12),
        ),
        '2026-11-1',
      );
      expect(
        TimeUtils.submissionDayKey(
          DateTime.fromMillisecondsSinceEpoch(0),
          today,
        ),
        'unknown',
      );
      expect(TimeUtils.submissionDayKey(DateTime(2027, 1, 2), today), 'future');
    },
  );
  test(
    'submission ordering ignores later observations/reviews and uses stable ID ties',
    () {
      final now = DateTime(2026, 10, 30, 12);
      final reports = [
        record(
          'old',
          now.subtract(const Duration(days: 2)),
          observed: now,
          reviewed: now,
          status: 'verified',
        ),
        record('a', now),
        record('z', now),
        record('unknown', DateTime.fromMillisecondsSinceEpoch(0)),
      ];
      reports.sort(compareReportSubmissions);
      expect(reports.map((r) => r.id), ['z', 'a', 'old', 'unknown']);
    },
  );
  testWidgets(
    'date labels localize Today/Yesterday and retain the year for older records',
    (tester) async {
      final now = DateTime(2027, 1, 1, 0, 2);
      for (final language in ['en', 'fil']) {
        await tester.pumpWidget(
          shell(
            Builder(
              builder: (context) => Column(
                children: [
                  Text(localizedSubmissionDay(context, now, now)),
                  Text(
                    localizedSubmissionDay(
                      context,
                      DateTime(2026, 12, 31, 23, 59),
                      now,
                    ),
                  ),
                  Text(
                    localizedSubmissionDay(
                      context,
                      DateTime(2026, 12, 30),
                      now,
                    ),
                  ),
                  Text(
                    localizedSubmissionDay(
                      context,
                      DateTime.fromMillisecondsSinceEpoch(0),
                      now,
                    ),
                  ),
                ],
              ),
            ),
            language: language,
          ),
        );
        expect(
          find.text(language == 'fil' ? 'Ngayon' : 'Today'),
          findsOneWidget,
        );
        expect(
          find.text(language == 'fil' ? 'Kahapon' : 'Yesterday'),
          findsOneWidget,
        );
        expect(find.textContaining('2026'), findsOneWidget);
        expect(find.textContaining('1970'), findsNothing);
      }
    },
  );
  testWidgets(
    'All reports groups by submission date while the attention queue stays urgent-first',
    (tester) async {
      final now = DateTime(2026, 10, 30, 12);
      replaceReports([
        record(
          'old-sos',
          now.subtract(const Duration(days: 1)),
          emergency: true,
        ),
        record('new', now),
        record('earlier', now.subtract(const Duration(hours: 1))),
      ]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => now)));
      await tester.pumpAndSettle();
      expect(visibleIds(tester).first, 'old-sos');
      expect(find.text('Today'), findsNothing);
      await allReports(tester);
      expect(
        find.text('Grouped by submission date, newest first.'),
        findsOneWidget,
      );
      expect(find.text('Today'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (w) => w is UserReportCard && w.report.id == 'earlier',
        ),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(visibleIds(tester).take(2), ['new', 'earlier']);
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (w) => w is UserReportCard && w.report.id == 'old-sos',
        ),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'late-uploaded old evidence stays in its submission day and shows its separate observation age',
    (tester) async {
      final now = DateTime(2026, 10, 30, 12);
      replaceReports([
        record(
          'late-upload',
          now,
          observed: now.subtract(const Duration(days: 1)),
        ),
      ]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => now)));
      await tester.pumpAndSettle();
      await allReports(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);
      expect(find.text('Observed: 1 day ago'), findsOneWidget);
      expect(find.text('Submitted: 12:00 PM'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'open date groups change after midnight and resume without a new backend record',
    (tester) async {
      var clock = DateTime(2026, 10, 30, 23, 59);
      replaceReports([record('before-midnight', clock)]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => clock)));
      await tester.pumpAndSettle();
      await allReports(tester);
      expect(find.text('Today'), findsOneWidget);
      clock = clock.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(days: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsNothing);
      expect(find.text('Oct 30'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'page boundaries repeat the day heading without inventing daily totals',
    (tester) async {
      final now = DateTime(2026, 10, 30, 12);
      replaceReports(
        List.generate(
          35,
          (i) => record('report-$i', now.subtract(Duration(minutes: i))),
        ),
      );
      await tester.pumpWidget(shell(UserReportsScreen(now: () => now)));
      await tester.pumpAndSettle();
      await allReports(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);
      await tester.tap(find.text('Older'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.textContaining('Today ('), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'missing and future-day timestamps stay explicit in list and inspector',
    (tester) async {
      final now = DateTime(2026, 10, 30, 12);
      final missing = UserReport.fromJson({
        'id': 'missing',
        'userId': 'resident',
        'title': 'Unknown-time road',
        'status': 'pending',
      });
      replaceReports([record('future', DateTime(2026, 10, 31)), missing]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => now)));
      await tester.pumpAndSettle();
      await allReports(tester);
      expect(find.text('Submission time needs confirmation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (w) => w is UserReportCard && w.report.id == 'missing',
        ),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Submission time not recorded'), findsWidgets);
      expect(find.textContaining('1970'), findsNothing);
      await tester.pumpWidget(
        shell(
          AdminReportInspector(report: missing, now: () => now, onClose: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Submission time not recorded'), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'recent calendar groups and their hint fit enlarged Filipino text on a narrow dark display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 10, 30, 0, 2);
      replaceReports([
        record('now', now),
        record('yesterday', now.subtract(const Duration(minutes: 4))),
      ]);
      await tester.pumpWidget(
        shell(
          UserReportsScreen(now: () => now),
          language: 'fil',
          dark: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await recentReports(tester, fil: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Ngayon'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ngayon'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'date-group cards use one labelled 12-hour time when observation and submission share a minute',
    (tester) async {
      final time = DateTime(2026, 10, 30, 13, 28);
      await tester.pumpWidget(
        shell(
          SingleChildScrollView(
            child: UserReportCard(
              report: record('same-minute', time),
              showSubmissionClock: true,
              now: () => time,
            ),
          ),
        ),
      );
      expect(find.text('Observed and submitted: 1:28 PM'), findsOneWidget);
      expect(find.textContaining('13:28'), findsNothing);
      expect(find.text('Submitted: 1:28 PM'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Last 48 hours removes a boundary report as the open window advances',
    (tester) async {
      var clock = DateTime(2026, 10, 30, 12);
      replaceReports([
        record('boundary', clock.subtract(const Duration(hours: 48))),
      ]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => clock)));
      await tester.pumpAndSettle();
      await recentReports(tester);
      await tester.pumpAndSettle();
      expect(find.byType(UserReportCard), findsOneWidget);
      clock = clock.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(find.byType(UserReportCard), findsNothing);
      expect(find.text('No matching reports'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'urgent report cards stay above routine road-condition reminders',
    (tester) async {
      final now = DateTime(2026, 10, 30, 12), state = AppStateService.instance;
      final roads = [...state.roads];
      state.roads
        ..clear()
        ..add(
          RoadStatus(
            id: 'road-reminder',
            name: 'Routine road check',
            status: 'partial',
            notes: 'Needs a current check',
            updatedAt: now,
            communityCondition: 'outdated',
          ),
        );
      addTearDown(() {
        state.roads
          ..clear()
          ..addAll(roads);
      });
      replaceReports([record('urgent', now, emergency: true)]);
      await tester.pumpWidget(shell(UserReportsScreen(now: () => now)));
      await tester.pumpAndSettle();
      final urgent = find.byType(UserReportCard),
          reminders = find.text('Check current road conditions');
      expect(urgent, findsOneWidget);
      await tester.scrollUntilVisible(
        reminders,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(reminders, findsOneWidget);
      expect(
        tester.getTopLeft(urgent).dy,
        lessThan(tester.getTopLeft(reminders).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
