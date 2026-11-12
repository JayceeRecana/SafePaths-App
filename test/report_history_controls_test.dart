import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/widgets/report_history_controls.dart';

Widget shell(ReportHistory history, {bool admin = false}) => MaterialApp(
  home: Scaffold(
    body: ReportHistoryControls(
      history: history,
      hideSinglePage: true,
      showRefresh: !admin,
    ),
  ),
);
UserReport item(String id) => UserReport(
  id: id,
  userId: 'resident',
  title: 'Observation',
  description: 'Recorded conditions',
  severity: 'High',
  status: 'pending',
  createdAt: DateTime(2026, 10, 30),
);
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'loading and failed first load never advertise Page 1; Retry recovers an empty single page',
    (tester) async {
      for (final admin in [false, true]) {
        final pending = Completer<ReportPage>();
        var calls = 0;
        final history = ReportHistory(
          (_) => ++calls == 1
              ? pending.future
              : Future.value(const ReportPage([])),
        );
        await tester.pumpWidget(shell(history, admin: admin));
        unawaited(history.refresh());
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Page 1'), findsNothing);
        expect(find.text('Older'), findsNothing);
        pending.completeError(StateError('offline'));
        await tester.pumpAndSettle();
        expect(find.text('Page 1'), findsNothing);
        expect(find.text('Newer'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text('Page 1'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(
          find.byTooltip('Refresh history'),
          admin ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        history.dispose();
      }
    },
  );
  testWidgets(
    'real older and newer navigation stays available after loading and is hidden during a page request',
    (tester) async {
      final pending = Completer<ReportPage>();
      final cursor = ReportCursor(DateTime(2026, 10, 29), 'first');
      final history = ReportHistory(
        (start) async => start == null
            ? ReportPage([item('first')], next: cursor)
            : pending.future,
      );
      await history.refresh();
      await tester.pumpWidget(shell(history));
      expect(find.text('Page 1'), findsOneWidget);
      await tester.tap(find.text('Older'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);
      pending.complete(ReportPage([item('second')]));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsOneWidget);
      expect(history.page.reports.single.id, 'first');
      await tester.pumpWidget(const SizedBox());
      history.dispose();
    },
  );
  testWidgets(
    'cached single-page history keeps its offline message and refresh without fake navigation',
    (tester) async {
      final history = ReportHistory(
        (_) async => ReportPage([item('saved')], fromCache: true),
      );
      await history.refresh();
      await tester.pumpWidget(shell(history));
      expect(find.text('Page 1'), findsNothing);
      expect(find.text('Older'), findsNothing);
      expect(find.textContaining('Saved history'), findsOneWidget);
      expect(find.byTooltip('Refresh history'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      history.dispose();
    },
  );
}
