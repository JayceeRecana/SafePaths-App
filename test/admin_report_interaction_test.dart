// ignore_for_file: depend_on_referenced_packages, invalid_use_of_protected_member
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as store;
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'package:safepaths_app/widgets/admin_report_workspace.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  late fixtures.TestAuth identity;
  late fixtures.TestStore db;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    identity = fixtures.TestAuth();
    db = fixtures.TestStore();
    auth.FirebaseAuthPlatform.instance = identity;
    store.FirebaseFirestorePlatform.instance = db;
  });
  UserReport record(String id) => UserReport(
    id: id,
    userId: 'resident-$id',
    title: 'Road $id',
    description: 'Water observed at crossing $id.',
    severity: 'High',
    status: 'under_review',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  );
  Future<Map<String, dynamic>> load(String id) async => {
    'report': record(id).toJson(),
  };
  setUp(() {
    identity.signIn('admin');
    db.docs.clear();
    db.cached.clear();
    AppStateService.instance.reports
      ..clear()
      ..addAll([record('a'), record('b')]);
    AppStateService.instance.roads.clear();
    for (final id in ['a', 'b']) {
      db.docs['reports/$id'] = record(id).toJson();
    }
  });
  tearDownAll(() async {
    await identity.events.close();
    await db.messages.close();
    for (final controller in db.events.values) {
      await controller.close();
    }
  });
  AdminReportWorkspace inspector(WidgetTester tester) =>
      tester.widget<AdminReportWorkspace>(find.byType(AdminReportWorkspace));
  Future<void> openMessage(WidgetTester tester) async {
    inspector(tester).onMessage!();
    await tester.pumpAndSettle();
    expect(find.byType(AdminReplyDialog), findsOneWidget);
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester,
    String id,
    int revision, {
    Future<Map<String, dynamic>> Function(String)? loader,
  }) async {
    await tester.pumpWidget(
      fixtures.shell(
        UserReportsScreen(
          key: const ValueKey('reports'),
          initialReportId: id,
          openRequestRevision: revision,
          loadReport: loader ?? load,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'notification entry isolates drafts per report and repeated entry preserves the current draft',
    (tester) async {
      await show(tester, 'a', 1);
      await openMessage(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Message intended only for resident A.',
      );
      await cancel(tester);
      await show(tester, 'b', 2);
      await openMessage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Message intended only for resident B.',
      );
      await cancel(tester);
      await show(tester, 'a', 3);
      await openMessage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Message intended only for resident A.',
      );
      await cancel(tester);
      await show(tester, 'a', 4);
      await openMessage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Message intended only for resident A.',
      );
      await cancel(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'report ID search uses the target report draft instead of the previous report draft',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          UserReportsScreen(
            loadReport: load,
            historyLoader: (_) async => ReportPage([record('a'), record('b')]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final a = find.byWidgetPredicate(
        (w) => w is UserReportCard && w.report.id == 'a',
      );
      await tester.scrollUntilVisible(
        a,
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      tester.widget<UserReportCard>(a).onTap!();
      await tester.pumpAndSettle();
      await openMessage(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'A message for report A, not report B.',
      );
      await cancel(tester);
      inspector(tester).onClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find report'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Paste report reference',
      );
      await tester.enterText(field, 'b');
      tester.widget<TextField>(field).onSubmitted!('b');
      await tester.pumpAndSettle();
      expect(inspector(tester).report.id, 'b');
      await openMessage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await cancel(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a notification waits for the open message dialog and cannot change its report',
    (tester) async {
      final calls = <String>[];
      Future<Map<String, dynamic>> loader(String id) async {
        calls.add(id);
        return load(id);
      }

      await show(tester, 'a', 1, loader: loader);
      await openMessage(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'A draft kept while another notice arrives.',
      );
      await show(tester, 'b', 2, loader: loader);
      expect(calls, ['a']);
      expect(
        tester.widget<AdminReplyDialog>(find.byType(AdminReplyDialog)).reportId,
        'a',
      );
      await cancel(tester);
      expect(calls, ['a', 'b']);
      expect(inspector(tester).report.id, 'b');
      await show(tester, 'a', 3, loader: loader);
      await openMessage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'A draft kept while another notice arrives.',
      );
      await cancel(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('late search results cannot replace a newer list selection', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    await show(tester, 'a', 1, loader: (_) => pending.future);
    final card = find.byWidgetPredicate(
      (w) => w is UserReportCard && w.report.id == 'b',
    );
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('report-list-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    tester.widget<UserReportCard>(card).onTap!();
    await tester.pumpAndSettle();
    expect(inspector(tester).report.id, 'b');
    pending.complete(await load('a'));
    await tester.pumpAndSettle();
    expect(inspector(tester).report.id, 'b');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'history inspector follows review completion, fails closed, retries, and detects deletion',
    (tester) async {
      final report = record('a');
      await tester.pumpWidget(
        fixtures.shell(
          UserReportsScreen(
            initiallyHistory: true,
            historyLoader: (_) async => ReportPage([report]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<UserReportCard>(find.byType(UserReportCard)).onTap!();
      await tester.pumpAndSettle();
      expect(inspector(tester).report.status, 'under_review');
      db.update('reports/a', {
        ...report.toJson(),
        'status': 'verified',
        'reviewedAt': DateTime.now().toIso8601String(),
      });
      AppStateService.instance.reports.clear();
      AppStateService.instance.notifyListeners();
      await tester.pumpAndSettle();
      expect(inspector(tester).report.status, 'verified');
      db.events['reports/a']!.addError(
        StateError('Synthetic unavailable stream'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminReportWorkspace), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(inspector(tester).report.status, 'verified');
      db.docs.remove('reports/a');
      db.events['reports/a']!.add(db.snapshot('reports/a'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminReportWorkspace), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'switching accounts clears selected report details and prevents reopening an old draft',
    (tester) async {
      await show(tester, 'a', 1);
      await openMessage(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Private admin draft.',
      );
      await cancel(tester);
      identity.signIn('resident');
      await tester.pumpAndSettle();
      expect(find.byType(AdminReportWorkspace), findsNothing);
      await show(tester, 'a', 2);
      expect(find.byType(AdminReportWorkspace), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
