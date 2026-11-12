import 'package:safepaths_app/widgets/user_avatar.dart';
import 'package:safepaths_app/models/user_profile.dart';
import 'package:safepaths_app/theme/app_palette.dart';
import 'package:safepaths_app/widgets/admin_dismiss_dialog.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/widgets/admin_report_workspace.dart';
import 'package:safepaths_app/widgets/admin_report_messages.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/widgets/admin_clarification_dialog.dart';
import 'package:safepaths_app/widgets/report_message_thread.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'report_history_layout_test.dart' as fixtures;

final now = DateTime(2026, 11, 8, 20);
UserReport report({String status = 'pending'}) => UserReport(
  id: 'report',
  userId: 'resident',
  roadId: 'road',
  title: 'Flooding: Rizal Avenue',
  description: 'Water near the intersection.',
  severity: 'High',
  status: status,
  createdAt: now,
  observedAt: now,
  clarificationRequestedAt: now,
  clarificationRepliedAt: status == 'pending'
      ? now.add(const Duration(minutes: 1))
      : null,
  clarificationRequestId: 'question',
);
Map<String, dynamic> contextData({
  bool self = false,
  bool originalPending = false,
}) => {
  'workflowVersion': 2,
  'token': 'private-test-token',
  'selfReview': self,
  'report': report().toJson(),
  'roads': [
    {
      'id': 'road',
      'name': 'Rizal Avenue',
      'status': 'not_passable',
      'isVerified': true,
    },
  ],
  if (originalPending) 'rootReport': {'id': 'original', 'status': 'pending'},
};
Widget messages(UserReport item) => AdminReportMessages(
  report: item,
  messages: [
    AdminUpdateMessage(
      id: 'question',
      sender: 'SafePaths administrator',
      message: 'Which side is affected?',
      createdAt: now,
    ),
    AdminUpdateMessage(
      id: 'reply',
      sender: 'Resident clarification',
      message: 'Near the intersection.',
      createdAt: now.add(const Duration(minutes: 1)),
    ),
  ],
);
Future<void> openSheet(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    fixtures.shell(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => child,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'workspace separates evidence and private messages and keeps actions visible',
    (tester) async {
      final item = report();
      var decisions = 0, questions = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: AdminReportWorkspace(
              report: item,
              road: RoadStatus(
                id: 'road',
                name: 'Rizal Avenue',
                status: 'not_passable',
                notes: 'Water across the road.',
                updatedAt: now,
                isVerified: true,
              ),
              messagesPane: messages(item),
              onClose: () {},
              onDecision: () => decisions++,
              onAsk: () => questions++,
              onMessage: () {},
              now: () => now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What the resident sent'), findsOneWidget);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      expect(find.text('What the resident sent'), findsNothing);
      expect(
        find.text(
          'The resident replied. Read the answer before making a decision.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reply received'), findsOneWidget);
      await tester.tap(find.text('Make a decision'));
      expect(decisions, 1);
      await tester.tap(find.text('Ask another question'));
      expect(questions, 1);
    },
  );
  testWidgets(
    'question action is disabled while a resident answer is outstanding',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: AdminReportWorkspace(
              report: report(status: 'waiting_resident'),
              onClose: () {},
              onAsk: () => calls++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask the resident'));
      expect(calls, 0);
    },
  );
  testWidgets('decision uses a fresh token and verifies only the observation', (
    tester,
  ) async {
    final sent = <Map<String, dynamic>>[];
    await openSheet(
      tester,
      AdminReviewDialog(
        reportId: 'report',
        decisionSheet: true,
        loadContext: () async => contextData(),
        perform: (action, data) async {
          expect(action, 'verify');
          sent.add(data);
          return const AdminActionResult(action: 'verify');
        },
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('admin-review-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Verified'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Photo and observation time support the earlier conditions.',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-review-save')));
    await tester.pumpAndSettle();
    expect(sent.single['contextToken'], 'private-test-token');
    expect(sent.single['observationOnly'], true);
    expect(sent.single.containsKey('roadStatus'), false);
    expect(sent.single.containsKey('verifiedCurrentConditions'), false);
  });
  testWidgets('self review and unresolved originals cannot be approved', (
    tester,
  ) async {
    for (final own in [true, false]) {
      await openSheet(
        tester,
        AdminReviewDialog(
          reportId: 'report',
          decisionSheet: true,
          loadContext: () async =>
              contextData(self: own, originalPending: !own),
        ),
      );
      await tester.tap(find.text('Verified'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('question presets protect manually written text', (tester) async {
    await openSheet(
      tester,
      AdminClarificationDialog(
        reportId: 'report',
        asSheet: true,
        loadContext: () async => contextData(),
      ),
    );
    await tester.ensureVisible(find.text('Which side of the road is this?'));
    await tester.tap(find.text('Which side of the road is this?'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.text, contains('Which side'));
    await tester.enterText(
      find.byType(TextField),
      'My own carefully written question.',
    );
    await tester.ensureVisible(find.text('When was the photo taken?'));
    await tester.tap(find.text('When was the photo taken?'));
    await tester.pumpAndSettle();
    expect(find.text('Replace your draft?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(controller.text, 'My own carefully written question.');
  });
  testWidgets(
    'workspace fits narrow enlarged text in both languages and themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true])
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: AdminReportWorkspace(
                  report: report(),
                  messagesPane: messages(report()),
                  onClose: () {},
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
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is IconButton &&
                        w.icon is Icon &&
                        (w.icon as Icon).icon == Icons.arrow_back,
                  ),
                )
                .color,
            dark ? AppPalette.dark.onSurface : AppPalette.light.onSurface,
          );
          await tester.tap(
            find.text(language == 'fil' ? 'Mga mensahe' : 'Messages'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
    },
  );
  testWidgets(
    'not-verified sheet requires an explicit reason and explanation',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      await openSheet(
        tester,
        AdminDismissDialog(
          reportId: 'report',
          asSheet: true,
          loadContext: () async => contextData(),
          perform: (action, data) async {
            sent.add(data);
            return const AdminActionResult(action: 'dismiss');
          },
        ),
      );
      final save = find.widgetWithText(FilledButton, 'Save decision');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(
        find.text('Choose a reason to see its effect on trust points.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unable to verify (no penalty)').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'The photo does not clearly show the affected road.',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(sent.single['reason'], 'unable_to_verify');
      expect(sent.single['confirmedFalseReport'], false);
    },
  );
  testWidgets('report action sheets fit large text with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    for (final dark in [false, true])
      for (final language in ['en', 'fil'])
        for (final scene in ['decision', 'question', 'update']) {
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: scene == 'decision'
                    ? AdminReviewDialog(
                        reportId: 'report',
                        decisionSheet: true,
                        loadContext: () async => contextData(),
                      )
                    : scene == 'question'
                    ? AdminClarificationDialog(
                        reportId: 'report',
                        asSheet: true,
                        loadContext: () async => contextData(),
                      )
                    : AdminReplyDialog(
                        reportId: 'report',
                        report: report(),
                        asSheet: true,
                      ),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
  });
  testWidgets('workspace header respects Android top inset', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: AdminReportWorkspace(report: report(), onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byTooltip('Back to list')).dy,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reporter identity never uses another resident profile left in memory',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: AdminReportWorkspace(
              report: report(),
              onClose: () {},
              reporter: UserProfile(
                id: 'other-resident',
                name: 'Wrong resident',
                photoUrl:
                    'https://example.supabase.co/functions/v1/safepaths-main/media/avatar/other-resident/${'a' * 64}',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(UserAvatar),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).photoUrl,
        isNull,
      );
      expect(find.text('Wrong resident'), findsNothing);
      expect(find.text('Reporter details unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
