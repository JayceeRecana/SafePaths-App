import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/screens/user/report_followup_screen.dart';
import 'package:safepaths_app/services/report_followup_service.dart';
import 'package:safepaths_app/services/report_submission_repository.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/widgets/admin_dismiss_dialog.dart';
import 'package:safepaths_app/widgets/followup_correction_button.dart';
import 'package:safepaths_app/theme/app_theme.dart';

final rootId = 'a' * 64;
final childId = 'b' * 64;
final token = 'c' * 64;
UserReport original() => UserReport(
  id: rootId,
  userId: 'resident',
  title: 'Earlier flood report',
  description: 'Original flooding',
  createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  observedAt: DateTime.now().subtract(const Duration(hours: 1)),
  severity: 'High',
  status: 'verified',
  roadId: 'road',
  incidentId: 'incident',
  pointsAwarded: 10,
);
ReportFollowupContext data({bool canSubmit = true}) => ReportFollowupContext(
  root: original(),
  updates: const [],
  token: token,
  canSubmit: canSubmit,
  closedReason: canSubmit
      ? null
      : 'This incident is closed or has changed. Submit a new report for a new event.',
);
Widget shell(
  Widget child, {
  String language = 'en',
  bool dark = false,
  double scale = 1,
}) => MaterialApp(
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
Future<void> revealFollowupControl(WidgetTester tester, Finder finder) async {
  // The redesigned form has separate cards; settle layout and scroll until
  // the requested control is actually tappable, including lazy-list extents.
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    final dy = tester.getCenter(finder).dy;
    await tester.scrollUntilVisible(
      finder.hitTestable(),
      dy < 0 ? -180 : 180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> chooseCleared(WidgetTester tester) async {
  final choice = find.byKey(const ValueKey('followup-change:null'));
  await revealFollowupControl(tester, choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text('No floodwater visible').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('followup-description')),
    'The road surface is visible now.',
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'follow-up fields and the preserved snapshot survive model copy and decoding',
    () {
      final report = UserReport.fromJson({
        ...original().toJson(),
        'reportType': 'followup',
        'rootReportId': rootId,
        'conditionChange': 'cleared',
        'photoSubmittedAt': '2026-10-26T12:00:00Z',
        'originalSubmission': {
          'description': 'Earlier evidence',
          'photoSubmittedAt': null,
        },
        'rewardCorrection': {'reversed': 5, 'penalty': 0},
      });
      final changed = report.copyWith(status: 'dismissed');
      expect(changed.isFollowup, true);
      expect(changed.historyRootId, rootId);
      expect(changed.originalSubmission?['description'], 'Earlier evidence');
      expect(changed.photoSubmittedAt, DateTime.utc(2026, 10, 26, 12));
      expect(changed.rewardCorrection?['penalty'], 0);
    },
  );
  test('history rejects cross-owner records and fabricated root links', () {
    final valid = {
      'token': token,
      'canSubmit': true,
      'rootReport': original().toJson(),
      'updates': <dynamic>[],
    };
    expect(ReportFollowupContext.fromJson(valid, rootId).root.id, rootId);
    expect(
      () => ReportFollowupContext.fromJson({
        ...valid,
        'updates': [
          {
            ...original().toJson(),
            'id': childId,
            'reportType': 'followup',
            'rootReportId': rootId,
            'userId': 'other',
          },
        ],
      }, rootId),
      throwsStateError,
    );
  });
  test(
    'lost-response retry uses the same opaque ID and accepts a single saved follow-up',
    () async {
      final preferences = <String, String>{};
      final ids = <String>[];
      var calls = 0;
      final client = SparkProofClient(
        configuration: SparkProofConfiguration(
          firebaseProjectId: 'safepaths-test',
          backendUrl:
              'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof',
        ),
        token: () async => 'test-token',
        client: MockClient((request) async {
          expect(request.url.path.endsWith('/followup-submit'), true);
          final payload = jsonDecode(request.body)['data'] as Map;
          ids.add(payload['requestId'] as String);
          if (calls++ == 0) throw http.ClientException('Response lost');
          return http.Response(
            jsonEncode({
              'result': {
                'reportId': childId,
                'rootReportId': rootId,
                'replay': true,
              },
            }),
            200,
          );
        }),
      );
      final repository = ReportSubmissionRepository(
        environment: 'followup-test',
        currentUid: () => 'resident',
        read: (key) async => preferences[key],
        write: (key, value) async {
          preferences[key] = value;
        },
        remove: (key) async {
          preferences.remove(key);
        },
        send: (payload) => client.followupCall('followup-submit', payload),
      );
      final payload = {
        'rootReportId': rootId,
        'description': 'Private current observation',
        'observedAt': '2026-10-26T12:00:00Z',
      };
      await expectLater(
        repository.save(uid: 'resident', payload: payload),
        throwsA(isA<SparkProofException>()),
      );
      expect(preferences.keys.single.contains('Private'), false);
      final result = await repository.save(uid: 'resident', payload: payload);
      expect(result.replay, true);
      expect(ids[0], ids[1]);
      expect(preferences, isEmpty);
      client.close();
    },
  );
  testWidgets(
    'a follow-up needs deliberate choices and a description before saving',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        shell(
          ReportFollowupScreen(
            rootReportId: rootId,
            loadContext: () async => data(),
            submitFollowup: (_) async {
              calls++;
              return ReportSaveResult(childId, false);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await revealFollowupControl(tester, find.text('Submit follow-up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit follow-up'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        find.textContaining('Choose what changed, describe'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'no-water follow-up is explicit, carries no old photo and preserves the original',
    (tester) async {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        shell(
          ReportFollowupScreen(
            rootReportId: rootId,
            loadContext: () async => data(),
            submitFollowup: (payload) async {
              sent = payload;
              return ReportSaveResult(childId, false);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCleared(tester);
      await revealFollowupControl(tester, find.text('Submit follow-up'));
      await tester.tap(find.text('Submit follow-up'));
      await tester.pumpAndSettle();
      expect(sent?['conditionChange'], 'cleared');
      expect(sent?['severity'], 'Low');
      expect(sent?.containsKey('imageUrl'), false);
      expect(sent?['contextToken'], token);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Original flooding'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed sends preserve the draft and timestamp and block duplicate taps',
    (tester) async {
      final pending = Completer<ReportSaveResult>();
      final times = <String>[];
      var calls = 0;
      await tester.pumpWidget(
        shell(
          ReportFollowupScreen(
            rootReportId: rootId,
            loadContext: () async => data(),
            submitFollowup: (payload) {
              calls++;
              times.add(payload['observedAt'] as String);
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCleared(tester);
      await revealFollowupControl(tester, find.text('Submit follow-up'));
      await tester.tap(find.text('Submit follow-up'));
      await tester.pump();
      await tester.tap(find.text('Submit follow-up'));
      await tester.pump();
      expect(calls, 1);
      pending.completeError(StateError('Uncertain response'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('followup-description')),
            )
            .controller
            ?.text,
        'The road surface is visible now.',
      );
      await revealFollowupControl(tester, find.text('Submit follow-up'));
      await tester.tap(find.text('Submit follow-up'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(times[0], times[1]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'closed incidents retain history but do not offer a follow-up form',
    (tester) async {
      await tester.pumpWidget(
        shell(
          ReportFollowupScreen(
            rootReportId: rootId,
            loadContext: () async => data(canSubmit: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original flooding'), findsOneWidget);
      expect(find.text('Submit follow-up'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'condition history and follow-up form fit enlarged English and Filipino text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              ReportFollowupScreen(
                rootReportId: rootId,
                loadContext: () async => data(),
              ),
              language: language,
              dark: dark,
              scale: 1.8,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$language/$dark follow-up form',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'meaningful bonus needs explicit acknowledgement and refresh clears it',
    (tester) async {
      final response = <String, dynamic>{
        'token': token,
        'report': {
          'reportType': 'followup',
          'title': 'New condition',
          'description': 'Water decreased',
          'severity': 'Low',
          'conditionChange': 'improved',
        },
        'rootReport': {'description': 'Original flooding'},
        'roads': <dynamic>[],
      };
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => AdminReviewDialog(
                    reportId: childId,
                    loadContext: () async => response,
                    perform: (action, payload) async {
                      sent = payload;
                      throw StateError('Uncertain save');
                    },
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
      final bonus = find.widgetWithText(
        CheckboxListTile,
        'I verified a meaningful change beyond the earlier submissions. Eligible for up to +5 trust points.',
      );
      expect(tester.widget<CheckboxListTile>(bonus).value, false);
      await revealFollowupControl(
        tester,
        find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not passable').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Field team checked that the water decreased.',
      );
      await revealFollowupControl(
        tester,
        find.byKey(const ValueKey('admin-review-confirmation')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-review-confirmation')));
      await revealFollowupControl(tester, bonus);
      await tester.tap(bonus);
      await tester.pump();
      await revealFollowupControl(
        tester,
        find.byKey(const ValueKey('admin-review-save')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-review-save')));
      await tester.pumpAndSettle();
      expect(sent?['meaningfulFollowup'], true);
      expect(sent?.containsKey('pointsAwarded'), false);
      await revealFollowupControl(tester, find.text('Refresh latest details'));
      await tester.tap(find.text('Refresh latest details'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(bonus).value, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('wrong attachment is a distinct no-penalty follow-up outcome', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => AdminDismissDialog(
                  reportId: childId,
                  loadContext: () async => {
                    'token': token,
                    'report': {
                      'reportType': 'followup',
                      'title': 'Follow-up',
                      'description': 'Unclear image',
                    },
                  },
                  perform: (action, payload) async {
                    sent = payload;
                    return const AdminActionResult(
                      action: 'dismiss',
                      isFollowup: true,
                    );
                  },
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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Wrong attachment / needs clarification (no penalty)').last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save dismissal'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField),
      'Please provide the photo for this road and observation.',
    );
    await tester.pump();
    await tester.tap(find.text('Save dismissal'));
    await tester.pumpAndSettle();
    expect(sent?['reason'], 'needs_correction');
    expect(sent?['confirmedFalseReport'], false);
    expect(sent?.containsKey('pointsAwarded'), false);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'bonus reversal and a misconduct penalty are separate explicit decisions',
    (tester) async {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => FollowupCorrectionDialog(
                    reportId: childId,
                    loadContext: () async => {'token': token},
                    perform: (action, payload) async {
                      sent = payload;
                      return const AdminActionResult(
                        action: 'correct_followup',
                        isFollowup: true,
                        pointsAwarded: -5,
                        pointsReversed: 5,
                      );
                    },
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
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save correction'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Mistaken approval: reverse the bonus only').last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'The wrong attachment was approved by mistake.',
      );
      await tester.pump();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(sent?['reason'], 'mistaken_approval');
      expect(sent?['confirmedFalseReport'], false);
      expect(sent?.containsKey('pointsAwarded'), false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'temporary refresh failure preserves the draft but loss of authorization clears history',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        shell(
          ReportFollowupScreen(
            rootReportId: rootId,
            loadContext: () async {
              if (loads++ == 0) return data();
              if (loads == 2) throw StateError('Network unavailable');
              throw const SparkProofException(
                'permission-denied',
                'Access removed',
              );
            },
            submitFollowup: (_) async => ReportSaveResult(childId, false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCleared(tester);
      await revealFollowupControl(tester, find.text('Refresh history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      final draft = tester.widget<TextField>(
        find.byKey(const ValueKey('followup-description')),
      );
      expect(draft.controller!.text, 'The road surface is visible now.');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit follow-up'),
            )
            .onPressed,
        isNull,
      );
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final retry = find.text('Refresh history').first;
      await revealFollowupControl(tester, retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(find.byKey(const ValueKey('followup-description')), findsNothing);
      expect(find.text('Original flooding'), findsNothing);
      expect(
        find.textContaining('This account can no longer open'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
