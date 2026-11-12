import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/user/report_followup_screen.dart';
import 'package:safepaths_app/services/report_followup_service.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/widgets/report_followup_prompt.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'Follow-up prompt opens history and stays readable with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true])
        for (final lang in ['en', 'fil']) {
          var opens = 0;
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ReportFollowupPrompt(onOpen: () => opens++),
                  ),
                ),
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await fixtures.revealFollowupControl(
            tester,
            find.byType(FilledButton),
          );
          await tester.tap(find.byType(FilledButton));
          expect(opens, 1);
          await tester.pumpWidget(const SizedBox.shrink());
        }
    },
  );
  testWidgets(
    'Follow-up form controls remain reachable with large text and keyboard in either theme and language',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final dark in [false, true])
        for (final lang in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              ReportFollowupScreen(
                rootReportId: fixtures.rootId,
                loadContext: () async => fixtures.data(),
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final text = find.byKey(const ValueKey('followup-description'));
          await fixtures.revealFollowupControl(tester, text);
          await tester.enterText(text, 'A safe observation for this road.');
          await tester.pumpAndSettle();
          await fixtures.revealFollowupControl(
            tester,
            find.byType(FilledButton),
          );
          expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
    },
  );
  testWidgets(
    'History never substitutes submission time for a missing observation time',
    (tester) async {
      final root = UserReport(
        id: 'root',
        userId: 'resident',
        title: 'Flooding: Sample road',
        description: 'Earlier evidence',
        createdAt: DateTime(2026, 11, 10, 19, 23),
        status: 'pending',
        severity: 'High',
      );
      await tester.pumpWidget(
        fixtures.shell(
          ReportFollowupScreen(
            rootReportId: 'root',
            readOnly: true,
            loadContext: () async => ReportFollowupContext(
              root: root,
              updates: [],
              token: 'test',
              canSubmit: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observed: Time not recorded'), findsOneWidget);
      expect(find.textContaining('Observed and submitted'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
