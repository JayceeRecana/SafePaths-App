import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/l10n/app_strings.dart';
import 'package:safepaths_app/screens/user/report_followup_screen.dart';
import 'package:safepaths_app/widgets/admin_clarification_dialog.dart';
import 'package:safepaths_app/services/report_submission_repository.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  Widget followup({
    Future<ReportSaveResult> Function(Map<String, dynamic>)? save,
  }) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ReportFollowupScreen(
              rootReportId: fixtures.rootId,
              loadContext: () async => fixtures.data(),
              submitFollowup: save,
            ),
          ),
        ),
        child: const Text('Open follow-up'),
      ),
    ),
  );
  testWidgets(
    'system and header Back protect a text-only follow-up until discard is confirmed',
    (tester) async {
      await tester.pumpWidget(fixtures.shell(followup()));
      await tester.tap(find.text('Open follow-up'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('followup-description')),
        'A draft observation to keep.',
      );
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your unsent changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('A draft observation to keep.'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your unsent changes?'), findsOneWidget);
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportFollowupScreen), findsNothing);
      await tester.tap(find.text('Open follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('A draft observation to keep.'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a confirmed follow-up save clears its draft and permits leaving without a discard prompt',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          followup(
            save: (_) async => const ReportSaveResult('saved-followup', false),
          ),
        ),
      );
      await tester.tap(find.text('Open follow-up'));
      await tester.pumpAndSettle();
      await fixtures.chooseCleared(tester);
      await fixtures.revealFollowupControl(
        tester,
        find.text('Submit follow-up'),
      );
      await tester.tap(find.text('Submit follow-up'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Follow-up saved for admin review. The road condition has not been changed.',
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ReportFollowupScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'admin question Cancel and Android Back preserve text until explicit discard',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AdminClarificationDialog(
                    reportId: fixtures.rootId,
                    loadContext: () async => {
                      'workflowVersion': 2,
                      'selfReview': false,
                      'token': fixtures.token,
                    },
                  ),
                ),
                child: const Text('Ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Which crossing does this observation show?',
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        find.text('Which crossing does this observation show?'),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your unsent changes?'), findsOneWidget);
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminClarificationDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'discard confirmation fits enlarged English and Filipino text with the keyboard open',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final language in ['en', 'fil']) {
        String label(String text) =>
            language == 'fil' ? filipinoMessages[text] ?? text : text;
        await tester.pumpWidget(
          fixtures.shell(
            followup(),
            language: language,
            dark: language == 'fil',
            scale: 2,
          ),
        );
        await tester.tap(find.text('Open follow-up'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('followup-description')),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.enterText(
          find.byKey(const ValueKey('followup-description')),
          'Unsent observation.',
        );
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(label('Keep editing')));
        await tester.tap(find.text(label('Keep editing')));
        await tester.pumpAndSettle();
        expect(find.text('Unsent observation.'), findsOneWidget);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
