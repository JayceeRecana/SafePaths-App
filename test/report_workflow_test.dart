import 'package:safepaths_app/widgets/resident_report_details.dart';
import 'package:safepaths_app/widgets/admin_clarification_dialog.dart';
import 'package:flutter/services.dart';
import 'package:safepaths_app/widgets/report_workflow_ui.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/report_workload.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/widgets/report_activity_summary.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';
import 'package:safepaths_app/screens/user/report_clarification_screen.dart';
import 'package:safepaths_app/theme/app_theme.dart';

UserReport report(String id, String status, int age, {bool urgent = false}) =>
    UserReport(
      id: id,
      userId: 'resident',
      title: 'Road observation',
      description: 'Morning floodwater',
      severity: 'High',
      status: status,
      createdAt: DateTime(2026, 10, 30, 12).subtract(Duration(minutes: age)),
      isEmergency: urgent,
    );
Widget shell(
  Widget page, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
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
    dotenv.loadFromString(envString: 'WORKFLOW_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  test(
    'shared queue prioritizes urgency, then waiting age; completed reports do not inflate workload',
    () {
      final queue = ReportWorkload([
        report('new', 'pending', 1),
        report('old', 'under_review', 100),
        report('sos', 'under_review', 5, urgent: true),
        report('waiting', 'waiting_resident', 200),
        report('done', 'verified', 300),
        report('new', 'pending', 1),
      ]);
      expect(queue.open.map((r) => r.id), ['sos', 'old', 'new', 'waiting']);
      expect(queue.needsAdmin, 3);
      expect(queue.waiting, 1);
      expect(queue.oldest!.id, 'old');
      expect(
        reportReviewLabel(report('waiting', 'waiting_resident', 1)),
        'Waiting for resident',
      );
    },
  );
  test(
    'history applies status and dismissal reason before its 30 record page',
    () async {
      final state = AppStateService.instance,
          previous = [...AppStateService.instance.reports];
      state.reports
        ..clear()
        ..addAll(List.generate(40, (i) => report('pending$i', 'pending', i)))
        ..addAll(
          List.generate(35, (i) => report('verified$i', 'verified', 100 + i)),
        );
      final history = state.createReportHistory(statuses: ['verified']);
      await history.refresh();
      expect(history.page.reports.length, 30);
      expect(history.page.reports.every((r) => r.status == 'verified'), true);
      await history.older();
      expect(history.page.reports.length, 5);
      history.dispose();
      state.reports
        ..clear()
        ..addAll(previous);
    },
  );
  testWidgets(
    'v2 verifies the observation alone; selecting road update requires current verification again',
    (tester) async {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminReviewDialog(
              reportId: 'r',
              loadContext: () async => {
                'workflowVersion': 2,
                'token': 'a' * 64,
                'report': {
                  'title': 'Morning flood',
                  'description': 'Water at 8 AM',
                  'severity': 'High',
                },
                'roads': [
                  {'name': 'Road', 'status': 'not_passable'},
                ],
              },
              perform: (action, data) async {
                sent = data;
                return const AdminActionResult(action: 'verify');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        'Checked the morning photograph with the reporter.',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-review-save')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(sent!['observationOnly'], true);
      expect(sent!.containsKey('roadStatus'), false);
      expect(sent!.containsKey('verifiedCurrentConditions'), false);
    },
  );
  testWidgets(
    'resident reply fails honestly, preserves draft and disables repeats while saving',
    (tester) async {
      int attempts = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        shell(
          ReportClarificationScreen(
            reportId: 'r',
            loadContext: () async => {
              'reportId': 'r',
              'requestId': 'request',
              'canReply': true,
              'question': 'When did you see the water?',
            },
            send: (payload) async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
              await pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'I observed the water at eight in the morning.',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send clarification'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reply not confirmed.'), findsOneWidget);
      expect(
        find.text('I observed the water at eight in the morning.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send clarification'));
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('Saving...'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clarification form fits narrow light/dark and large Filipino text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final lang in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              ReportClarificationScreen(
                reportId: 'r',
                loadContext: () async => {
                  'reportId': 'r',
                  'requestId': 'request',
                  'canReply': true,
                  'question': 'Please clarify when the photo was taken.',
                },
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TextField),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(
            find.byType(TextField),
            'The original photo was taken yesterday morning.',
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, -700));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets(
    'analytics fetches only on expansion and failed refresh does not report zero',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportActivitySummary(
                load: (start, end) async {
                  calls++;
                  expect(end.isAfter(start), true);
                  if (calls > 1) throw StateError('offline');
                  return (12, 3);
                },
              ),
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('12'), findsOneWidget);
      await tester.ensureVisible(find.text('Refresh summary'));
      await tester.tap(find.text('Refresh summary'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Summary unavailable.'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('12'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'resident and admin cards copy the same complete reference, never the display abbreviation',
    (tester) async {
      final id = List.filled(8, 'a1b2c3d4').join();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final item = UserReport(
        id: id,
        userId: 'resident',
        title: 'Flood: Sample road',
        description: 'Earlier water at the intersection.',
        severity: 'High',
        status: 'pending',
        createdAt: DateTime(2026, 10, 30, 10),
      );
      for (final card in [
        ResidentReportEvidenceCard(report: item),
        UserReportCard(report: item, onTap: () {}),
      ]) {
        await tester.pumpWidget(
          shell(Scaffold(body: SingleChildScrollView(child: card))),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReportReference), findsOneWidget);
        expect(find.textContaining(id), findsNothing);
        await tester.ensureVisible(find.byTooltip('Copy report reference'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Copy report reference'));
        await tester.pumpAndSettle();
        expect(copied, id);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'an answered clarification shows both speakers and no reply composer',
    (tester) async {
      await tester.pumpWidget(
        shell(
          ReportClarificationScreen(
            reportId: 'report-123',
            loadContext: () async => {
              'canReply': false,
              'question': 'Which entrance is shown in the original photo?',
              'createdAt': '2026-10-30T13:00:00',
              'response': {
                'message': 'The entrance beside the school gate.',
                'repliedAt': '2026-10-30T13:10:00',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportConversationCard), findsNWidgets(2));
      expect(find.text('The barangay asked'), findsOneWidget);
      expect(find.text('Resident reply'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Send clarification'), findsNothing);
      expect(find.textContaining('1:10 PM'), findsOneWidget);
    },
  );
  testWidgets(
    'Find report explains an invalid reference without attempting a backend lookup',
    (tester) async {
      await tester.pumpWidget(shell(const UserReportsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find report'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'short...reference');
      await tester.ensureVisible(find.byTooltip('Open report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open report'));
      await tester.pumpAndSettle();
      expect(
        find.text('Paste the full report reference using its Copy button.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'admin question dialog fits large text in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final lang in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: AdminClarificationDialog(
                  reportId: List.filled(64, 'b').join(),
                  loadContext: () async => {
                    'workflowVersion': 2,
                    'token': 'preview',
                  },
                ),
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TextField),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(
            find.byType(TextField),
            'Please clarify the location shown in the original photo.',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets(
    'fresh verification context exposes observation time and clarification access',
    (tester) async {
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminReviewDialog(
              reportId: 'report',
              loadContext: () async => {
                'workflowVersion': 2,
                'token': 'fresh',
                'roads': [],
                'report': {
                  'id': 'report',
                  'status': 'pending',
                  'title': 'Flood: Sample road',
                  'description': 'Earlier water beside the crossing.',
                  'severity': 'High',
                  'createdAt': '2026-10-30T13:28:00',
                  'observedAt': '2026-10-29T10:00:00',
                  'clarificationRequestId': 'request',
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observed'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.textContaining('10:00 AM'), findsOneWidget);
      expect(
        find.text('Read question and reply before deciding'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'road-update steps fit small screens in both themes and languages at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final lang in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: AdminReviewDialog(
                  roadIds: const ['road'],
                  loadContext: () async => {
                    'workflowVersion': 2,
                    'token': 'preview',
                    'report': null,
                    'roads': [
                      {
                        'id': 'road',
                        'name': 'Unnamed residential (OSM 123)',
                        'status': 'passable',
                        'updatedAt': '2026-10-30T13:00:00',
                      },
                    ],
                  },
                ),
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TextField),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(
            find.byType(TextField),
            'Checked the crossing this afternoon with the barangay team.',
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('admin-review-confirmation')),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
