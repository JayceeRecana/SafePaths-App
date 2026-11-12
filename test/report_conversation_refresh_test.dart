import 'package:safepaths_app/widgets/admin_report_messages.dart';
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as store;
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/widgets/report_message_thread.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:safepaths_app/screens/user/report_clarification_screen.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

class ConversationStore extends fixtures.TestStore {
  bool hasMessages = true;
  @override
  store.QuerySnapshotPlatform messagePage() => hasMessages
      ? super.messagePage()
      : store.QuerySnapshotPlatform(
          [],
          [],
          store.SnapshotMetadataPlatform(false, false),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  late ConversationStore db;
  late fixtures.TestAuth identity;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    identity = fixtures.TestAuth();
    auth.FirebaseAuthPlatform.instance = identity;
    db = ConversationStore();
    store.FirebaseFirestorePlatform.instance = db;
  });
  setUp(() {
    identity.signIn('resident');
    db.docs.clear();
    db.cached.clear();
    db.messageQueries.clear();
    db.hasMessages = true;
    db.docs['reports/report'] = {...fixtures.record(), 'status': 'pending'};
  });
  tearDownAll(() async {
    await identity.events.close();
    await db.messages.close();
    for (final event in db.events.values) {
      await event.close();
    }
  });
  UserReport original() => UserReport(
    id: 'report',
    userId: 'resident',
    title: 'Sample road',
    description: 'Original observation',
    severity: 'High',
    status: 'pending',
    createdAt: DateTime(2026, 11, 2, 10),
    hasAdminUpdates: true,
  );

  testWidgets(
    'An open history conversation gets the new clarification action and loses stale state',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          ReportUpdatesPage(reportId: 'report', report: original()),
        ),
      );
      await tester.pumpAndSettle();
      expect(db.events.containsKey('reports/report'), isTrue);
      expect(find.text('Waiting for barangay review'), findsOneWidget);
      db.update('reports/report', {
        ...fixtures.record(),
        'status': 'waiting_resident',
        'clarificationRequestId': 'question-A',
      });
      await tester.pumpAndSettle();
      expect(find.text('Needs your reply'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('report-question-action')),
        findsOneWidget,
      );
      expect(find.text('Waiting for barangay review'), findsNothing);
      db.update('reports/report', {
        ...fixtures.record(),
        'status': 'pending',
        'clarificationRequestId': 'question-A',
        'clarificationRepliedAt': DateTime(
          2026,
          11,
          2,
          10,
          15,
        ).toIso8601String(),
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Reply sent. Waiting for barangay review.'),
        findsOneWidget,
      );
      expect(find.text('Needs your reply'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A legacy-only page receives the first live message without reopening',
    (tester) async {
      db.hasMessages = false;
      db.docs['reports/report'] = {
        ...fixtures.record(updates: false),
        'status': 'pending',
        'adminReply': 'Older stored update',
      };
      await tester.pumpWidget(
        fixtures.shell(
          ReportUpdatesPage(
            reportId: 'report',
            report: original(),
            hasServerUpdates: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(db.messageQueries, isNotEmpty);
      db.hasMessages = true;
      db.update('reports/report', {
        ...fixtures.record(),
        'status': 'pending',
        'adminReply': 'Older stored update',
      });
      db.messages.add(db.messagePage());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Current private update from the barangay.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Current private update from the barangay.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Changing accounts clears the open history conversation', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.shell(ReportUpdatesPage(reportId: 'report', report: original())),
    );
    await tester.pumpAndSettle();
    identity.signIn('other');
    await tester.pumpAndSettle();
    expect(find.byType(AdminUpdatesContent), findsNothing);
    expect(find.byType(ResidentReportUpdatesContent), findsNothing);
    expect(
      find.text('Account changed. Reopen updates from your own reports.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Admin account switch cannot expose a cached report to the next account',
    (tester) async {
      for (final embedded in [false, true]) {
        identity.signIn('admin');
        db.cached.add('reports/report');
        await tester.pumpWidget(
          fixtures.shell(
            ReportUpdatesPage(
              reportId: 'report',
              report: original(),
              isAdmin: true,
              embeddedAdmin: embedded,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(embedded ? AdminReportMessages : AdminUpdatesContent),
          findsOneWidget,
        );
        final queries = db.messageQueries.length;
        identity.signIn('other');
        await tester.pumpAndSettle();
        expect(find.byType(AdminUpdatesContent), findsNothing);
        expect(find.byType(AdminReportMessages), findsNothing);
        expect(db.messageQueries.length, queries);
        expect(
          find.text('Account changed. Reopen updates from your own reports.'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'An old draft cannot be rebound to a new question after refresh',
    (tester) async {
      var loads = 0;
      final sent = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            report: original(),
            loadContext: () async => {
              'requestId': ++loads == 1 ? 'question-A' : 'question-B',
              'canReply': true,
              'question': loads == 1
                  ? 'When did you take the photo?'
                  : 'Which street is shown?',
            },
            send: (data) async {
              sent.add(Map.of(data));
              throw StateError('Injected uncertain save');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      const draft = 'The photo was taken at eight in the morning.';
      await tester.enterText(find.byType(TextField), draft);
      await tester.ensureVisible(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Refresh latest details'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh latest details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('The barangay question changed'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(TextField), findsNothing);
      expect(sent, hasLength(1));
      await tester.scrollUntilVisible(
        find.text('Start a new reply'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start a new reply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text(draft), findsOneWidget);
      await tester.tap(find.text('Start a new reply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new reply'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        find.byType(TextField),
        'This photo shows the corner of Sample Road.',
      );
      await tester.ensureVisible(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send clarification'));
      await tester.pumpAndSettle();
      expect(sent.last['clarificationRequestId'], 'question-B');
      expect(
        sent.last['message'],
        'This photo shows the corner of Sample Road.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Message starters explain their purpose and protect the admin draft',
    (tester) async {
      final controller = TextEditingController(
        text: 'A manually written private update.',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: AdminReplyDialog(reportId: 'report', controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.getRect(
        find.byKey(const ValueKey('report-action-fixed-heading')),
      );
      final starter = find.text('Your report has been received.');
      await tester.ensureVisible(starter);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(
          find.byKey(const ValueKey('report-action-fixed-heading')),
        ),
        heading,
      );
      await tester.tap(starter);
      await tester.pumpAndSettle();
      expect(find.text('Replace your draft?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(controller.text, 'A manually written private update.');
      await tester.tap(starter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace text'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Your report has been received.');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('Leaving an unsent clarification asks before discarding it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportClarificationScreen(
                    reportId: 'report',
                    loadContext: () async => {
                      'requestId': 'question-A',
                      'canReply': true,
                      'question': 'When did you see the water?',
                    },
                  ),
                ),
              ),
              child: const Text('Open clarification'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open clarification'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'My unsent observation details.',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your unsent reply?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('My unsent observation details.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportClarificationScreen), findsNothing);
    expect(find.text('Open clarification'), findsOneWidget);
  });
  testWidgets(
    'An admin sees the answer arrive on the open clarification page',
    (tester) async {
      final changes = StreamController<Map<String, dynamic>?>.broadcast();
      var answered = false;
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            report: original(),
            isAdmin: true,
            reportChanges: changes.stream,
            loadContext: () async => {
              'requestId': 'question-A',
              'canReply': false,
              'question': 'When did you take the photo?',
              if (answered)
                'response': {
                  'message': 'The photo was taken this morning.',
                  'repliedAt': '2026-11-02T02:15:00Z',
                },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      changes.add({
        'clarificationRequestId': 'question-A',
        'status': 'waiting_resident',
      });
      await tester.pumpAndSettle();
      expect(find.text('Resident reply'), findsNothing);
      answered = true;
      changes.add({
        'clarificationRequestId': 'question-A',
        'status': 'pending',
        'clarificationRepliedAt': '2026-11-02T02:15:00Z',
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Resident reply'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('The photo was taken this morning.'), findsOneWidget);
      expect(find.text('Send clarification'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await changes.close();
    },
  );

  testWidgets(
    'A new question arriving during drafting protects the previous text automatically',
    (tester) async {
      final changes = StreamController<Map<String, dynamic>?>.broadcast();
      var question = 'question-A';
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            reportChanges: changes.stream,
            loadContext: () async => {
              'requestId': question,
              'canReply': true,
              'question': question == 'question-A'
                  ? 'When did you see the water?'
                  : 'Which street is shown?',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      changes.add({
        'clarificationRequestId': question,
        'status': 'waiting_resident',
      });
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'I saw the water at eight in the morning.',
      );
      question = 'question-B';
      changes.add({
        'clarificationRequestId': question,
        'status': 'waiting_resident',
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('The barangay question changed'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('I saw the water at eight in the morning.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await changes.close();
    },
  );

  testWidgets(
    'Live reply metadata waits for an uncertain save before refreshing its confirmed response',
    (tester) async {
      final changes = StreamController<Map<String, dynamic>?>.broadcast();
      final pending = Completer<void>();
      var loads = 0, answered = false;
      const draft = 'The water was visible at eight in the morning.';
      await tester.pumpWidget(
        fixtures.shell(
          ReportClarificationScreen(
            reportId: 'report',
            reportChanges: changes.stream,
            loadContext: () async {
              loads++;
              return {
                'requestId': 'question-A',
                'canReply': !answered,
                'question': 'When did you see the water?',
                if (answered)
                  'response': {
                    'message': draft,
                    'repliedAt': '2026-11-02T02:15:00Z',
                  },
              };
            },
            send: (_) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      changes.add({
        'clarificationRequestId': 'question-A',
        'status': 'waiting_resident',
      });
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), draft);
      await tester.ensureVisible(find.text('Send clarification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send clarification'));
      await tester.pump();
      answered = true;
      changes.add({
        'clarificationRequestId': 'question-A',
        'status': 'pending',
        'clarificationRepliedAt': '2026-11-02T02:15:00Z',
      });
      await tester.pump();
      expect(loads, 1);
      expect(find.text('Saving...'), findsOneWidget);
      pending.completeError(
        StateError('Injected response loss after server save'),
      );
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.scrollUntilVisible(
        find.text('Resident reply'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(draft), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await changes.close();
    },
  );
}
