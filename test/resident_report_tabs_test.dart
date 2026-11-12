import 'package:safepaths_app/widgets/resident_report_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/widgets/report_message_thread.dart';
import 'report_history_layout_test.dart' as fixtures;

UserReport sample(String status) => UserReport(
  id: 'real-reference-longer-than-24-characters',
  userId: 'resident',
  roadId: 'road',
  title: 'Flooding: Sample road',
  description: 'Water near the intersection.',
  createdAt: DateTime(2026, 11, 8, 18),
  observedAt: DateTime(2026, 11, 8, 17, 55),
  severity: 'High',
  status: status,
  clarificationRequestId: status == 'waiting_resident' ? 'question' : null,
  reviewedAt: status == 'verified' ? DateTime(2026, 11, 8, 18, 10) : null,
  pointsAwarded: status == 'verified' ? 10 : null,
  incidentReviewStatus: status == 'verified' ? 'not_passable' : null,
);
const messageText = 'Please identify the affected side from a safe place.';
List<AdminUpdateMessage> messages() => [
  AdminUpdateMessage(
    id: 'latest',
    sender: 'Barangay Command Center',
    message: messageText,
    createdAt: DateTime(2026, 11, 8, 18, 20),
  ),
  AdminUpdateMessage(
    id: 'earlier',
    sender: 'Barangay Command Center',
    message: 'Earlier update.',
    createdAt: DateTime(2026, 11, 8, 18, 5),
  ),
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'message colors follow recorded workflow events, not the words in a message',
    () {
      final time = DateTime(2026, 11, 8, 18, 20);
      final question = UserReport.fromJson({
        ...sample('waiting_resident').toJson(),
        'clarificationRequestedAt': time.toIso8601String(),
      });
      expect(
        residentMessageTone(
          report: question,
          sender: 'SafePaths administrator',
          createdAt: time,
        ),
        ResidentMessageTone.question,
      );
      expect(
        residentMessageTone(
          report: question,
          sender: 'SafePaths administrator',
          createdAt: time.subtract(const Duration(minutes: 1)),
        ),
        ResidentMessageTone.routine,
      );
      expect(
        residentMessageTone(
          report: question,
          sender: 'Resident clarification',
          createdAt: time,
        ),
        ResidentMessageTone.reply,
      );
      final verified = sample('verified');
      expect(
        residentMessageTone(
          report: verified,
          sender: 'SafePaths administrator',
          createdAt: verified.reviewedAt,
        ),
        ResidentMessageTone.verified,
      );
      expect(
        residentMessageTone(
          report: verified,
          sender: 'SafePaths administrator',
          createdAt: time,
        ),
        ResidentMessageTone.routine,
      );
    },
  );
  testWidgets(
    'messages are chronological; report evidence and rewards have their own tab',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: ResidentReportUpdatesContent(
              report: sample('verified'),
              messages: messages(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('+10 trust'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Earlier update.')).dy,
        lessThan(tester.getTopLeft(find.text(messageText)).dy),
      );
      expect(
        find.byKey(const ValueKey('report-question-action')),
        findsNothing,
      );
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(find.text(messageText), findsNothing);
      expect(find.byTooltip('Copy report reference'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('+10 trust'), 200);
      expect(find.text('Observation verified'), findsOneWidget);
      expect(find.text('+10 trust'), findsOneWidget);
      expect(
        find.textContaining('Road condition at this review: Not passable'),
        findsOneWidget,
      );
      expect(find.text('Latest recorded road condition'), findsNothing);
    },
  );
  testWidgets(
    'unverified road defaults cannot look like a current confirmed passable road',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: ResidentReportUpdatesContent(
              report: sample('verified'),
              messages: const [],
              initialMessages: false,
              road: RoadStatus(
                id: 'road',
                name: 'Sample road',
                status: 'passable',
                notes: 'Imported from OSM',
                isVerified: false,
                source: 'osm',
                updatedAt: DateTime(2026, 10, 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Latest recorded road condition'),
        200,
      );
      expect(find.text('Current condition unknown'), findsOneWidget);
      expect(find.text('Passable'), findsNothing);
      expect(find.text('Observation verified'), findsOneWidget);
    },
  );
  testWidgets(
    'resident tabs and persistent question action fit enlarged text in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true])
        for (final language in ['en', 'fil'])
          for (final status in ['waiting_resident', 'verified']) {
            final report = sample(status);
            await tester.pumpWidget(
              fixtures.shell(
                Scaffold(
                  appBar: ResidentReportUpdatesHeader(report: report, scale: 2),
                  body: ResidentReportUpdatesContent(
                    report: report,
                    messages: messages(),
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
              find.byKey(const ValueKey('report-question-action')),
              status == 'waiting_resident' ? findsOneWidget : findsNothing,
            );
            await tester.tap(find.text(language == 'fil' ? 'Ulat' : 'Report'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('report-question-action')),
              findsNothing,
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
    },
  );
  testWidgets(
    'cache and failure notices never claim the empty thread has no messages',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: ResidentReportUpdatesContent(
              report: sample('pending'),
              messages: const [],
              fromCache: true,
              error: 'Admin updates could not be loaded.',
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No admin messages are recorded yet.'), findsNothing);
      expect(find.text('Retry updates'), findsOneWidget);
      expect(
        find.text('Saved information; reconnect to check the latest update.'),
        findsOneWidget,
      );
      expect(find.text('+10 trust'), findsNothing);
    },
  );
}
