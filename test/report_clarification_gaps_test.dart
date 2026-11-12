import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/user/report_clarification_screen.dart';
import 'package:safepaths_app/widgets/user_avatar.dart';
import 'package:safepaths_app/widgets/safe_image.dart';
import 'package:safepaths_app/services/report_clarification_service.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'closed unanswered question explains why the resident cannot reply',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            loadContext: () async => {
              'requestId': 'question',
              'canReply': false,
              'question': 'Which side was affected?',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This question no longer accepts replies'),
        findsOneWidget,
      );
      expect(find.text('Send clarification'), findsNothing);
    },
  );
  testWidgets(
    'short reply explains the minimum instead of silently disabling Send',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            loadContext: () async => {
              'requestId': 'question',
              'canReply': true,
              'question': 'Which side was affected?',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Left');
      await fixtures.revealFollowupControl(
        tester,
        find.text('Send clarification'),
      );
      expect(find.text('Write at least 10 characters.'), findsOneWidget);
      final button = find.ancestor(
        of: find.text('Send clarification'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    },
  );
  for (final endpoint in ['safepaths-main', 'safepaths-report-proof'])
    testWidgets('$endpoint avatar chooses the authenticated media reader', (
      tester,
    ) async {
      late Widget tree;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              tree = UserAvatar(
                photoUrl:
                    'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/$endpoint/media/avatar/resident/${'a' * 64}',
              ).build(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect((tree as ClipOval).child, isA<SafeImage>());
    });
  test(
    'attachment validation explains future time, missing time and confirmation',
    () {
      final now = DateTime(2026, 11, 10, 15);
      String? issue({
        DateTime? time,
        bool confirmed = false,
        bool photo = true,
      }) => clarificationDraftProblem(
        text: 'The left side of the intersection.',
        now: now,
        hasPhoto: photo,
        photoObservedAt: time,
        photoConfirmed: confirmed,
      );
      expect(issue(photo: false), isNull);
      expect(issue(), 'Choose when the attached photo was observed.');
      expect(
        issue(time: now.add(const Duration(minutes: 1)), confirmed: true),
        'Photo observation time must be in the past or now.',
      );
      expect(
        issue(time: now),
        'Confirm that the photo supports the observation time selected.',
      );
      expect(issue(time: now, confirmed: true), isNull);
    },
  );
}
