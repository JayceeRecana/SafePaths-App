import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:safepaths_app/widgets/admin_dismiss_dialog.dart';

Map<String, dynamic> contextData({bool sos = false}) => {
  'token': 'a' * 64,
  'report': {
    'title': 'Synthetic flood',
    'description': 'Test conditions only',
    'severity': 'High',
    'isEmergency': sos,
  },
  'roads': [
    {'name': 'Road A', 'status': 'not_passable'},
  ],
};
Future<void> open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> chooseCondition(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final proposal in [null, 'passable']) {
    testWidgets(
      'road condition must be chosen explicitly even with proposal $proposal',
      (tester) async {
        Map<String, dynamic>? saved;
        await open(
          tester,
          AdminReviewDialog(
            reportId: 'report',
            initialStatus: proposal,
            loadContext: () async => contextData(),
            perform: (action, data) async {
              saved = Map.of(data);
              return const AdminActionResult(
                action: 'verify',
                roadStatus: 'passable',
              );
            },
          ),
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .initialValue,
          isNull,
        );
        await tester.enterText(
          find.byType(TextField),
          'Synthetic source and current findings.',
        );
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('admin-review-save')),
              )
              .onPressed,
          isNull,
        );
        expect(saved, isNull);
        await chooseCondition(tester, 'Passable');
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('admin-review-save')));
        await tester.pumpAndSettle();
        expect(saved?['roadStatus'], 'passable');
      },
    );
  }

  testWidgets(
    'refreshing a stale review retains findings but requires a fresh condition and confirmation',
    (tester) async {
      var loads = 0, saves = 0;
      final payloads = <Map<String, dynamic>>[];
      await open(
        tester,
        AdminReviewDialog(
          reportId: 'report',
          loadContext: () async => {
            ...contextData(),
            'token': (++loads == 1 ? 'a' : 'b') * 64,
          },
          perform: (action, data) async {
            payloads.add(Map.of(data));
            if (++saves == 1) throw StateError('stale review');
            return const AdminActionResult(
              action: 'verify',
              roadStatus: 'passable',
            );
          },
        ),
      );
      await chooseCondition(tester, 'Not passable');
      await tester.enterText(
        find.byType(TextField),
        'Synthetic findings retained after refresh.',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refresh latest details'));
      await tester.tap(find.text('Refresh latest details'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic findings retained after refresh.',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await chooseCondition(tester, 'Passable');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(payloads.last['contextToken'], 'b' * 64);
      expect(payloads.last['roadStatus'], 'passable');
    },
  );

  testWidgets(
    'editing findings clears the earlier current-condition confirmation',
    (tester) async {
      await open(
        tester,
        AdminReviewDialog(
          reportId: 'report',
          loadContext: () async => contextData(),
        ),
      );
      await chooseCondition(tester, 'Not passable');
      await tester.enterText(
        find.byType(TextField),
        'First synthetic findings.',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'Revised synthetic findings.',
      );
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
    },
  );
  test(
    'save acknowledgements must match the requested action and actual points',
    () {
      final zero = AdminActionResult.fromJson({
        'saved': true,
        'action': 'verify',
        'pointsAwarded': 0,
        'replay': false,
        'roadStatus': 'not_passable',
        'notification': 'saved_in_app',
      }, 'verify');
      expect(zero.confirmation, contains('Not passable'));
      expect(zero.confirmation, isNot(contains('+10')));
      final capped = AdminActionResult.fromJson({
        'saved': true,
        'action': 'verify',
        'pointsAwarded': 3,
        'replay': true,
        'roadStatus': 'partial',
        'notification': 'saved_in_app',
      }, 'verify');
      expect(capped.confirmation, contains('+3'));
      for (final data in [
        <String, dynamic>{},
        {
          'saved': false,
          'action': 'verify',
          'pointsAwarded': 10,
          'replay': false,
          'roadStatus': 'passable',
          'notification': 'saved_in_app',
        },
        {
          'saved': true,
          'action': 'reply',
          'pointsAwarded': 10,
          'replay': false,
          'notification': 'saved_in_app',
        },
        {
          'saved': true,
          'action': 'verify',
          'pointsAwarded': -10,
          'replay': false,
          'roadStatus': 'passable',
          'notification': 'saved_in_app',
        },
      ]) {
        expect(
          () => AdminActionResult.fromJson(data, 'verify'),
          throwsStateError,
        );
      }
    },
  );
  testWidgets(
    'opening a review does not save; verification needs a source and explicit confirmation',
    (tester) async {
      var calls = 0;
      await open(
        tester,
        AdminReviewDialog(
          reportId: 'report',
          loadContext: () async => contextData(),
          perform: (action, data) async {
            calls++;
            return const AdminActionResult(
              action: 'verify',
              roadStatus: 'not_passable',
            );
          },
        ),
      );
      expect(calls, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await chooseCondition(tester, 'Not passable');
      await tester.enterText(
        find.byType(TextField),
        'Current synthetic field inspection.',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(AdminReviewDialog), findsNothing);
    },
  );
  testWidgets('a failed review keeps the draft and retries the same decision', (
    tester,
  ) async {
    var calls = 0;
    final sent = <Map<String, dynamic>>[];
    await open(
      tester,
      AdminReviewDialog(
        reportId: 'report',
        loadContext: () async => contextData(),
        perform: (action, data) async {
          calls++;
          sent.add(Map.of(data));
          if (calls == 1) throw StateError('response lost');
          return const AdminActionResult(
            action: 'verify',
            roadStatus: 'not_passable',
          );
        },
      ),
    );
    await chooseCondition(tester, 'Not passable');
    await tester.enterText(
      find.byType(TextField),
      'Synthetic trusted source and findings.',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-review-save')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminReviewDialog), findsOneWidget);
    expect(find.textContaining('save was not confirmed'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Synthetic trusted source and findings.',
    );
    await tester.tap(find.byKey(const ValueKey('admin-review-save')));
    await tester.pumpAndSettle();
    expect(sent[0], sent[1]);
    expect(find.byType(AdminReviewDialog), findsNothing);
  });
  testWidgets(
    'a failed private reply keeps its text and never defaults to a confirmation',
    (tester) async {
      var calls = 0;
      final sent = <Map<String, dynamic>>[];
      await open(
        tester,
        AdminReplyDialog(
          reportId: 'report',
          perform: (action, data) async {
            calls++;
            sent.add(Map.of(data));
            if (calls == 1) throw StateError('offline');
            return const AdminActionResult(action: 'reply');
          },
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        find.byType(TextField),
        'We received this test report.',
      );
      await tester.pump();
      await tester.tap(find.text('Send update'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminReplyDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'We received this test report.',
      );
      await tester.tap(find.text('Send update'));
      await tester.pumpAndSettle();
      expect(sent[0], sent[1]);
      expect(find.byType(AdminReplyDialog), findsNothing);
    },
  );
  testWidgets('an SOS dismissal stays disabled until explicitly acknowledged', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await open(
      tester,
      AdminDismissDialog(
        reportId: 'report',
        loadContext: () async => contextData(sos: true),
        perform: (action, data) async {
          saved = data;
          return const AdminActionResult(action: 'dismiss');
        },
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save dismissal'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Save dismissal'));
    await tester.pumpAndSettle();
    expect(saved?['confirmEmergency'], true);
    expect(saved?['reason'], 'duplicate_resolved');
  });
  testWidgets(
    'review controls remain usable on a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AdminReviewDialog(
                    reportId: 'report',
                    loadContext: () async => contextData(),
                    perform: (a, d) async => const AdminActionResult(
                      action: 'verify',
                      roadStatus: 'not_passable',
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Partially passable'), findsOneWidget);
    },
  );
  testWidgets(
    'road update uses a fresh explicit condition and current-check confirmation without verifying a report',
    (tester) async {
      String? savedAction;
      Map<String, dynamic>? saved;
      await open(
        tester,
        AdminReviewDialog(
          roadIds: const ['road-a'],
          initialStatus: 'passable',
          loadContext: () async => {
            'workflowVersion': 2,
            'token': 'fresh-token',
            'report': null,
            'roads': [
              {
                'id': 'road-a',
                'name': 'Unnamed residential (OSM 123)',
                'status': 'passable',
              },
            ],
          },
          perform: (action, data) async {
            savedAction = action;
            saved = Map.of(data);
            return const AdminActionResult(
              action: 'road_review',
              roadStatus: 'not_passable',
            );
          },
        ),
      );
      expect(find.text('Update road status'), findsOneWidget);
      expect(find.text('Latest recorded condition'), findsOneWidget);
      expect(find.text('Road reference'), findsOneWidget);
      await tester.ensureVisible(find.text('Road reference'));
      await tester.tap(find.text('Road reference'));
      await tester.pumpAndSettle();
      expect(find.text('road-a'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await chooseCondition(tester, 'Not passable');
      await tester.enterText(
        find.byType(TextField),
        'Checked by the barangay team this afternoon. Water covers the crossing.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-review-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(savedAction, 'road_review');
      expect(saved?['roadIds'], ['road-a']);
      expect(saved?['roadStatus'], 'not_passable');
      expect(saved?['verifiedCurrentConditions'], true);
      expect(saved?.containsKey('reportId'), false);
      expect(saved?.containsKey('observationOnly'), false);
    },
  );
  testWidgets(
    'a report-originated road update carries its reference without verifying that report',
    (tester) async {
      Map<String, dynamic>? saved;
      String? action;
      await open(
        tester,
        AdminReviewDialog(
          roadIds: const ['road-a'],
          sourceReportId: 'original-report',
          loadContext: () async => {
            'workflowVersion': 2,
            'reportRoadLinkSupported': true,
            'token': 'fresh',
            'report': null,
            'sourceReport': {
              'id': 'original-report',
              'roadId': 'road-a',
              'status': 'verified',
            },
            'roads': [
              {'id': 'road-a', 'name': 'Road A', 'status': 'not_passable'},
            ],
          },
          perform: (a, d) async {
            action = a;
            saved = Map.of(d);
            return const AdminActionResult(
              action: 'road_review',
              roadStatus: 'passable',
              sourceReportId: 'original-report',
            );
          },
        ),
      );
      expect(
        find.textContaining('Opened from report: original-report'),
        findsOneWidget,
      );
      await chooseCondition(tester, 'Passable');
      await tester.enterText(
        find.byType(TextField),
        'Field staff checked the crossing this afternoon. The road is clear.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-review-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(action, 'road_review');
      expect(saved?['sourceReportId'], 'original-report');
      expect(saved?['roadIds'], ['road-a']);
      expect(saved?.containsKey('reportId'), false);
      expect(saved?.containsKey('observationOnly'), false);
      expect(find.byType(AdminReviewDialog), findsNothing);
    },
  );
  testWidgets(
    'an older backend cannot silently drop the report link; refresh preserves the findings',
    (tester) async {
      var supported = false, saves = 0;
      await open(
        tester,
        AdminReviewDialog(
          roadIds: const ['road-a'],
          sourceReportId: 'original-report',
          loadContext: () async => {
            'workflowVersion': 2,
            'token': 'fresh',
            'report': null,
            'reportRoadLinkSupported': supported,
            'sourceReport': {'id': 'original-report', 'roadId': 'road-a'},
            'roads': [
              {'id': 'road-a', 'name': 'Road A', 'status': 'passable'},
            ],
          },
          perform: (a, d) async {
            saves++;
            return const AdminActionResult(action: 'road_review');
          },
        ),
      );
      expect(
        find.text(
          'This backend cannot retain the report reference yet. No update was saved.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Current conditions checked by the barangay team.',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      expect(saves, 0);
      supported = true;
      await tester.ensureVisible(find.text('Refresh latest details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh latest details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Current conditions checked by the barangay team.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Opened from report: original-report'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('admin-review-confirmation')),
            )
            .value,
        false,
      );
    },
  );
  testWidgets(
    'a mismatched source road blocks saving and a mismatched save receipt preserves the draft',
    (tester) async {
      await open(
        tester,
        AdminReviewDialog(
          roadIds: const ['road-a'],
          sourceReportId: 'original-report',
          loadContext: () async => {
            'workflowVersion': 2,
            'token': 'fresh',
            'reportRoadLinkSupported': true,
            'report': null,
            'sourceReport': {
              'id': 'original-report',
              'roadId': 'different-road',
            },
            'roads': [
              {'id': 'road-a', 'name': 'Road A', 'status': 'passable'},
            ],
          },
        ),
      );
      expect(
        find.text(
          'The linked report could not be confirmed for this road. Reopen it from Report details.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('admin-review-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open(
        tester,
        AdminReviewDialog(
          roadIds: const ['road-a'],
          sourceReportId: 'original-report',
          loadContext: () async => {
            'workflowVersion': 2,
            'token': 'fresh',
            'reportRoadLinkSupported': true,
            'report': null,
            'sourceReport': {'id': 'original-report', 'roadId': 'road-a'},
            'roads': [
              {'id': 'road-a', 'name': 'Road A', 'status': 'not_passable'},
            ],
          },
          perform: (a, d) async => const AdminActionResult(
            action: 'road_review',
            roadStatus: 'passable',
            sourceReportId: 'wrong-receipt',
          ),
        ),
      );
      await chooseCondition(tester, 'Passable');
      await tester.enterText(
        find.byType(TextField),
        'CCTV checked by the barangay team at the recorded time.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-review-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AdminReviewDialog), findsOneWidget);
      expect(
        find.textContaining('The save was not confirmed.'),
        findsOneWidget,
      );
      expect(
        find.text('CCTV checked by the barangay team at the recorded time.'),
        findsOneWidget,
      );
    },
  );
  test('save receipt accepts only a valid road-update reference', () {
    final data = <String, dynamic>{
      'saved': true,
      'action': 'road_review',
      'pointsAwarded': 0,
      'replay': false,
      'notification': 'saved_in_app',
      'roadStatus': 'passable',
      'sourceReportId': 'original-report',
    };
    expect(
      AdminActionResult.fromJson(data, 'road_review').sourceReportId,
      'original-report',
    );
    expect(
      () => AdminActionResult.fromJson({
        ...data,
        'sourceReportId': '../invalid',
      }, 'road_review'),
      throwsStateError,
    );
    expect(
      () => AdminActionResult.fromJson({...data, 'action': 'verify'}, 'verify'),
      throwsStateError,
    );
    expect(
      AdminActionResult.fromJson({
        ...data,
        'sourceReportId': null,
      }, 'road_review').sourceReportId,
      isNull,
    );
  });
}
