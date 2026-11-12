import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/bottom_nav_bar.dart';
import 'package:safepaths_app/widgets/report_history_card.dart';
import 'package:safepaths_app/widgets/report_message_thread.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';
import 'package:safepaths_app/widgets/safe_image.dart';
import 'package:safepaths_app/theme/app_palette.dart';

Widget shell(
  Widget child, {
  String language = 'en',
  bool dark = false,
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
UserReport report({
  String status = 'verified',
  String? reason,
  int points = 10,
}) => UserReport(
  id: 'report',
  userId: 'resident',
  roadId: 'road',
  incidentId: 'incident',
  title: 'Deep Water: Unnamed residential (OSM 552835258)',
  description:
      'Ankle-deep water observed across the road. The full original explanation remains available in report details.',
  createdAt: DateTime.now(),
  observedAt: DateTime.now(),
  reviewedAt: DateTime.now(),
  severity: 'High',
  status: status,
  pointsAwarded: points,
  dismissReason: reason,
  incidentReviewStatus: 'not_passable',
  hasAdminUpdates: true,
);
final road = RoadStatus(
  id: 'road',
  name: 'Unnamed residential',
  status: 'not_passable',
  notes: 'Current check',
  updatedAt: DateTime.now(),
);
List<AdminUpdateMessage> messages(int count) => List.generate(
  count,
  (i) => AdminUpdateMessage(
    id: 'message-$i',
    message:
        'Update $i: The observation and current road condition were reviewed separately. Please check road details before travel.',
    sender: 'Barangay Command Center',
    createdAt: DateTime(2026, 10, 26, 13).subtract(Duration(minutes: i)),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'history has one outcome and reward, with original details available on demand',
    (tester) async {
      final item = report();
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportHistoryCard(report: item, road: road),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Your observation was verified.'), findsOneWidget);
      expect(find.text('+10 trust'), findsNothing);
      expect(
        find.byTooltip('Last recorded road condition: Not passable'),
        findsNothing,
      );
      // The detailed outcome, reward and road condition live in the Report tab.
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: ResidentReportUpdatesContent(
              report: item,
              road: road,
              messages: const [],
              initialMessages: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observation verified'), findsOneWidget);
      expect(find.text('+10 trust'), findsOneWidget);
      expect(find.text('What you sent'), findsOneWidget);
      expect(find.text('When you saw it'), findsOneWidget);
      expect(find.text(item.description), findsOneWidget);
      expect(find.byTooltip('Copy report reference'), findsOneWidget);
    },
  );
  testWidgets(
    'report card and four tabs fit narrow screens and enlarged text in both languages and themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          for (final status in ['verified', 'pending', 'under_review']) {
            var selected = -1;
            await tester.pumpWidget(
              shell(
                Scaffold(
                  body: SingleChildScrollView(
                    child: ReportHistoryCard(
                      report: UserReport.fromJson({
                        ...report().toJson(),
                        'status': status,
                        if (status != 'verified') 'pointsAwarded': null,
                      }),
                      road: road,
                      onEdit: () {},
                    ),
                  ),
                  bottomNavigationBar: BottomNavBar(
                    currentIndex: 3,
                    onTap: (index) => selected = index,
                  ),
                ),
                language: language,
                dark: dark,
                scale: 2,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final label = language == 'fil' ? 'MGA ULAT' : 'REPORTS';
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
            expect(selected, 3);
            // Compact history cards keep their single report-opening target.
            expect(find.byType(ReportHistoryCard), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
  testWidgets(
    'correction requests do not inherit the former false-report penalty label',
    (tester) async {
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: ResidentReportUpdatesContent(
              initialMessages: false,
              messages: const [],
              report: report(
                status: 'dismissed',
                reason: 'needs_correction',
                points: 0,
              ),
              road: road,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Needs correction'), findsOneWidget);
      expect(
        find.textContaining('No trust points were deducted.'),
        findsOneWidget,
      );
      expect(find.textContaining('-15'), findsNothing);
    },
  );
  testWidgets(
    'private updates open separately and Back restores the history scroll position',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 750),
                ReportMessageThread(
                  reportId: 'report',
                  pageBuilder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Admin updates')),
                    body: AdminUpdatesContent(messages: messages(30)),
                  ),
                ),
                const SizedBox(height: 150),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(500);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View private admin updates'));
      await tester.pumpAndSettle();
      final offset = controller.offset;
      expect(find.textContaining('Update 0:'), findsNothing);
      await tester.tap(find.text('View private admin updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update 0:'), findsOneWidget);
      expect(find.textContaining('Update 29:'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.offset, offset);
      expect(find.textContaining('Update 0:'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'long message lists render lazily, wrap, and expose older messages through pagination',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var older = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminUpdatesContent(
              messages: messages(20),
              hasMore: true,
              onLoadOlder: () => older++,
            ),
          ),
          language: 'fil',
          dark: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('message-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-19')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('I-load ang mas lumang mga update'),
        450,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('I-load ang mas lumang mga update'));
      await tester.pumpAndSettle();
      expect(older, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty cached messages do not claim the live conversation is empty',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: AdminUpdatesContent(messages: [], fromCache: true),
          ),
        ),
      );
      expect(
        find.text('No saved admin updates are available on this device.'),
        findsOneWidget,
      );
      expect(find.text('No admin messages are recorded yet.'), findsNothing);
    },
  );

  testWidgets(
    'submission preview expands the actual original evidence without replacing a follow-up',
    (tester) async {
      final item = UserReport.fromJson({
        ...report().toJson(),
        'description': 'Later edited description',
        'originalSubmission': {
          'title': 'Water Alert: Original street',
          'description': 'Original submitted observation',
          'submittedAt': '2026-10-25T13:20:00',
          'observedAt': '2026-10-25T13:10:00',
          'imageUrl': 'unsupported-photo-reference',
        },
      });
      expect(
        submittedReportEvidence(item).description,
        'Original submitted observation',
      );
      final followup = UserReport.fromJson({
        ...item.toJson(),
        'reportType': 'followup',
      });
      expect(
        submittedReportEvidence(followup).description,
        'Later edited description',
      );
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportSubmissionPreview(report: item),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original street'), findsOneWidget);
      expect(find.text('Original submitted observation'), findsOneWidget);
      expect(find.text('Later edited description'), findsNothing);
      await tester.tap(find.text('View submitted report'));
      await tester.pumpAndSettle();
      expect(find.text('Original submitted observation'), findsNWidgets(2));
      expect(find.textContaining('Submitted:'), findsOneWidget);
      expect(find.textContaining('1:20 PM'), findsOneWidget);
      expect(find.byType(SafeImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'report timeline keeps submission context, message order, lazy paging and large-text support',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var older = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminUpdatesContent(
              report: report(),
              messages: messages(25),
              hasMore: true,
              onLoadOlder: () => older++,
            ),
          ),
          language: 'fil',
          dark: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('submission-preview-report')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('message-24')), findsNothing);
      expect(
        tester
            .widget<Text>(find.text('Pag-uusap tungkol sa ulat'))
            .style!
            .color,
        AppPalette.dark.primary,
      );
      expect(find.text('Your report was verified'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('message-0')),
        350,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportUpdateTimelineEntry), findsWidgets);
      expect(find.textContaining('Update 0:'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('I-load ang mas lumang mga update'),
        450,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('I-load ang mas lumang mga update'));
      await tester.pumpAndSettle();
      expect(older, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'report progress does not invent verification or a reward for pending and expired records',
    (tester) async {
      for (final status in ['pending', 'expired']) {
        final item = UserReport.fromJson({
          ...report().toJson(),
          'status': status,
          'reviewedAt': null,
          'pointsAwarded': null,
          'incidentReviewStatus': null,
        });
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: SingleChildScrollView(
                child: ReportHistoryCard(report: item),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Verified'), findsNothing);
        expect(find.text('+10 trust'), findsNothing);
        expect(find.byType(ReportStatusProgress), findsNothing);
        expect(
          find.text(status == 'pending' ? 'Sent' : 'Outdated'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'loading and failed messages retain the report preview without claiming the thread is empty',
    (tester) async {
      for (final loading in [true, false]) {
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: AdminUpdatesContent(
                report: report(),
                messages: const [],
                loading: loading,
                error: loading ? null : 'Admin updates could not be loaded.',
                onRetry: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('submission-preview-report')),
          findsOneWidget,
        );
        expect(find.text('No admin messages are recorded yet.'), findsNothing);
        if (!loading) expect(find.text('Retry updates'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'an open submitted-photo viewer clears old evidence after an account switch',
    (tester) async {
      final changes = StreamController<String?>();
      var uid = 'owner';
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: ReportPhotoViewer(
              currentViewer: () => uid,
              viewerChanges: changes.stream,
              child: const Text('Private submitted photo'),
            ),
          ),
        ),
      );
      expect(find.text('Private submitted photo'), findsOneWidget);
      uid = 'another-account';
      changes.add(uid);
      await tester.pump();
      expect(find.text('Private submitted photo'), findsNothing);
      uid = 'owner';
      changes.add(uid);
      await tester.pump();
      expect(find.text('Private submitted photo'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(changes.close());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'submission timestamps combine only when their displayed minute matches',
    (tester) async {
      final submitted = DateTime(2026, 10, 26, 13, 28);
      for (final same in [true, false]) {
        final item = UserReport.fromJson({
          ...report().toJson(),
          'createdAt': submitted.toIso8601String(),
          'observedAt': submitted
              .subtract(Duration(minutes: same ? 0 : 8))
              .toIso8601String(),
          'imageUrl': 'unsupported-photo-reference',
        });
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: SingleChildScrollView(
                child: ReportSubmissionPreview(report: item),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Observed and submitted:'),
          same ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('View submitted report'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Submitted:'),
          same ? findsNothing : findsOneWidget,
        );
        expect(find.byType(SafeImage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
