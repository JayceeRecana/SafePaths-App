import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/user/report_followup_screen.dart';
import 'package:safepaths_app/services/report_followup_service.dart';
import 'package:safepaths_app/services/report_submission_repository.dart';
import 'report_followup_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'follow-up cannot reload the old report after an account switch or sign-in again',
    (tester) async {
      final accounts = StreamController<String?>.broadcast();
      var uid = 'resident', loads = 0;
      addTearDown(accounts.close);
      await tester.pumpWidget(
        fixtures.shell(
          ReportFollowupScreen(
            rootReportId: fixtures.rootId,
            currentViewer: () => uid,
            viewerChanges: accounts.stream,
            loadContext: () async {
              loads++;
              return fixtures.data();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await fixtures.chooseCleared(tester);
      uid = 'other';
      accounts.add(uid);
      await tester.pumpAndSettle();
      expect(find.text('Original flooding'), findsNothing);
      uid = 'resident';
      accounts.add(uid);
      await tester.pumpAndSettle();
      final retry = find.text('Refresh history');
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry.first);
        await tester.pumpAndSettle();
      }
      expect(
        loads,
        1,
        reason: 'An account change must require opening a fresh report screen.',
      );
      expect(find.byKey(const ValueKey('followup-description')), findsNothing);
    },
  );
  testWidgets(
    'late follow-up load cannot reopen evidence after the account changes',
    (tester) async {
      final accounts = StreamController<String?>.broadcast();
      var uid = 'resident';
      final pending = Completer<ReportFollowupContext>();
      addTearDown(accounts.close);
      await tester.pumpWidget(
        fixtures.shell(
          ReportFollowupScreen(
            rootReportId: fixtures.rootId,
            currentViewer: () => uid,
            viewerChanges: accounts.stream,
            loadContext: () => pending.future,
          ),
        ),
      );
      await tester.pump();
      uid = 'other';
      accounts.add(uid);
      await tester.pump();
      pending.complete(fixtures.data());
      await tester.pumpAndSettle();
      expect(find.text('Original flooding'), findsNothing);
      expect(
        find.text('Account changed. Reopen this report from your own history.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'a save finishing after sign-out never shows success or restores the form',
    (tester) async {
      final accounts = StreamController<String?>.broadcast();
      String? uid = 'resident';
      var sends = 0;
      final pending = Completer<ReportSaveResult>();
      addTearDown(accounts.close);
      await tester.pumpWidget(
        fixtures.shell(
          ReportFollowupScreen(
            rootReportId: fixtures.rootId,
            currentViewer: () => uid,
            viewerChanges: accounts.stream,
            loadContext: () async => fixtures.data(),
            submitFollowup: (payload) {
              sends++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await fixtures.chooseCleared(tester);
      await fixtures.revealFollowupControl(
        tester,
        find.text('Submit follow-up'),
      );
      await tester.tap(find.text('Submit follow-up'));
      await tester.pump();
      expect(sends, 1);
      uid = null;
      accounts.add(null);
      await tester.pump();
      pending.complete(ReportSaveResult(fixtures.childId, false));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Follow-up saved for admin review. The road condition has not been changed.',
        ),
        findsNothing,
      );
      expect(find.text('Original flooding'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
