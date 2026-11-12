import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/services/resident_report_update.dart';
import 'package:safepaths_app/screens/user/report_history_screen.dart';
import 'package:safepaths_app/widgets/report_history_card.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/widgets/resident_report_details.dart';

final base = DateTime(2026, 10, 28, 10);
UserReport item([Map<String, dynamic> extra = const {}]) =>
    UserReport.fromJson({
      'id': 'report',
      'userId': 'resident',
      'title': 'Flood: Test Road',
      'description': 'Original observation',
      'createdAt': base.toIso8601String(),
      'observedAt': base.toIso8601String(),
      'status': 'pending',
      ...extra,
    });
Widget shell(Widget child) => MaterialApp(theme: AppTheme.theme, home: child);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'late cached active feed cannot undo a newer review or reward correction',
    () {
      final pending = item();
      final verified = item({
        'status': 'verified',
        'pointsAwarded': 10,
        'reviewedAt': base.add(const Duration(minutes: 5)).toIso8601String(),
      });
      final corrected = item({
        'status': 'dismissed',
        'pointsAwarded': -5,
        'reviewedAt': base.add(const Duration(minutes: 8)).toIso8601String(),
      });
      expect(fresherReport(verified, pending).status, 'verified');
      expect(mergeReportFeeds([pending], [verified]).single.pointsAwarded, 10);
      expect(fresherReport(verified, corrected).pointsAwarded, -5);
      expect(fresherReport(corrected, verified).pointsAwarded, -5);
    },
  );
  test(
    'review start and reply revisions survive serialization and reject stale snapshots',
    () {
      for (final field in ['reviewStartedAt', 'adminRepliedAt', 'updatedAt']) {
        final fresh = item({
          field: base.add(const Duration(minutes: 2)).toIso8601String(),
          'status': 'under_review',
          'hasAdminUpdates': true,
        });
        final roundTrip = UserReport.fromJson(fresh.toJson());
        expect(fresherReport(roundTrip, item()).status, 'under_review');
        expect(fresherReport(item(), fresh).hasAdminUpdates, isTrue);
        expect(
          fresherReport(
            fresh.copyWith(description: 'Edit'),
            item(),
          ).description,
          'Edit',
        );
      }
      final wrongOwner = item({
        'userId': 'someone-else',
        'updatedAt': '2099-01-01',
      });
      expect(fresherReport(item(), wrongOwner).userId, 'resident');
    },
  );
  test(
    'new head arriving during first older-message request does not lose the displaced message',
    () {
      final previous = List.generate(20, (i) => 100 - i);
      final latest = [101, ...previous.take(19)];
      final older = <String, int>{};
      retainDisplacedHead(
        older: older,
        previous: previous,
        latest: latest,
        loadingOlder: true,
        id: (i) => '$i',
      );
      for (var i = 80; i > 60; i--) {
        older['$i'] = i;
      }
      final all = {...older, for (final i in latest) '$i': i};
      expect(all.values.toSet(), {for (var i = 61; i <= 101; i++) i});
      expect(all.length, 41);
      final bounded = <String, int>{};
      retainDisplacedHead(
        older: bounded,
        previous: previous,
        latest: latest,
        loadingOlder: false,
        id: (i) => '$i',
      );
      expect(bounded, isEmpty);
    },
  );

  group('resident edit retries', () {
    late Map<String, String> storage;
    late List<Map<String, dynamic>> sent;
    String? uid;
    late DateTime now;
    ResidentReportEditRepository repo({
      bool failWrite = false,
      bool failRemove = false,
      Future<void> Function(Map<String, dynamic>)? send,
      String env = 'test:backend',
    }) => ResidentReportEditRepository(
      environment: env,
      currentUid: () => uid,
      now: () => now,
      read: (k) async => storage[k],
      write: (k, v) async {
        if (failWrite) throw StateError('disk');
        storage[k] = v;
      },
      remove: (k) async {
        if (failRemove) throw StateError('disk');
        storage.remove(k);
      },
      send:
          send ??
          (data) async {
            sent.add(data);
          },
    );
    Future<void> save(ResidentReportEditRepository repository) =>
        repository.save(
          reportId: 'report',
          severity: 'High',
          description: 'Updated water level',
          expectedUpdatedAt: base,
        );
    setUp(() {
      storage = {};
      sent = [];
      uid = 'resident';
      now = base;
    });
    test(
      'response-loss retry reuses request ID and observation time across repository restarts',
      () async {
        await expectLater(
          save(
            repo(
              send: (data) async {
                sent.add(data);
                throw StateError('response lost');
              },
            ),
          ),
          throwsStateError,
        );
        now = base.add(const Duration(minutes: 2));
        await save(repo());
        expect(sent.length, 2);
        expect(sent[1], sent[0]);
        expect(storage, isEmpty);
      },
    );
    test(
      'failed persistence sends nothing; cleanup failure keeps a confirmed save successful',
      () async {
        await expectLater(save(repo(failWrite: true)), throwsStateError);
        expect(sent, isEmpty);
        await save(repo(failRemove: true));
        expect(sent.length, 1);
        expect(storage.length, 1);
      },
    );
    test('retry receipts are scoped by backend and account', () async {
      await save(repo(failRemove: true));
      await save(repo(failRemove: true, env: 'other-backend'));
      uid = 'another';
      await save(repo(failRemove: true));
      expect(storage.length, 3);
      expect(sent.map((s) => s['requestId']).toSet().length, 3);
    });
    test(
      'account changed during send cannot receive success or remove the retry receipt',
      () async {
        await expectLater(
          save(
            repo(
              send: (_) async {
                uid = 'another';
              },
            ),
          ),
          throwsStateError,
        );
        expect(storage.length, 1);
      },
    );
  });

  testWidgets(
    'archived card presents matching notes and photo, preserving original preview separately',
    (tester) async {
      final updated = item({
        'description': 'Updated observation',
        'imageUrl': 'new-photo',
        'lastUpdatedByUser': base
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'originalSubmission': {
          'description': 'Original observation',
          'imageUrl': 'original-photo',
          'submittedAt': base.toIso8601String(),
          'observedAt': base.toIso8601String(),
        },
      });
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportHistoryCard(report: updated, ownHistory: false),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<ReportPhotoThumbnail>(find.byType(ReportPhotoThumbnail))
            .report
            .imageUrl,
        'new-photo',
      );
      await tester.ensureVisible(find.text('View report details'));
      await tester.tap(find.text('View report details'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReportEvidenceDetails>(find.byType(ReportEvidenceDetails))
            .report
            .description,
        'Updated observation',
      );
      await tester.pumpWidget(
        shell(Scaffold(body: ReportSubmissionPreview(report: updated))),
      );
      expect(
        tester
            .widget<ReportPhotoThumbnail>(find.byType(ReportPhotoThumbnail))
            .report
            .imageUrl,
        'original-photo',
      );
      expect(find.text('Original submission'), findsOneWidget);
    },
  );
  testWidgets(
    'stale warning appears while history stays open without a server update',
    (tester) async {
      var now = base.add(const Duration(hours: 23, minutes: 59));
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportHistoryCard(report: item(), now: () => now),
            ),
          ),
        ),
      );
      expect(find.textContaining('This observation is old.'), findsNothing);
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.textContaining('This observation is old.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'direct account switch hides loaded history and ignores a pending page',
    (tester) async {
      String? uid = 'resident';
      final auth = StreamController<String?>();
      final pending = Completer<ReportPage>();
      var calls = 0;
      await tester.pumpWidget(
        shell(
          ReportHistoryScreen(
            currentAccount: () => uid,
            accountChanges: auth.stream,
            createHistory: (_) => ReportHistory((_) async {
              calls++;
              return calls == 1 ? ReportPage([item()]) : pending.future;
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original observation'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh history'));
      await tester.pump();
      uid = 'another';
      auth.add(uid);
      await tester.pump();
      expect(find.text('Original observation'), findsNothing);
      pending.complete(ReportPage([item()]));
      await tester.pumpAndSettle();
      expect(find.text('Original observation'), findsNothing);
      expect(find.textContaining('Account changed.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(auth.close());
      await tester.pump();
    },
  );
  testWidgets('dismissed edit sheet ignores late save failures', (
    tester,
  ) async {
    final auth = StreamController<String?>();
    final save = Completer<void>();
    await tester.pumpWidget(
      shell(
        ReportHistoryScreen(
          currentAccount: () => 'resident',
          accountChanges: auth.stream,
          createHistory: (_) =>
              ReportHistory((_) async => ReportPage([item()])),
          saveEdit: (_, _, _) => save.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Update Flood Level / Notes'));
    await tester.tap(find.text('Update Flood Level / Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save update'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    save.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Update failed:'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(auth.close());
    await tester.pump();
  }, skip: AppEnvironment.sparkFollowupsEnabled);
  testWidgets(
    'earlier retained photo is identified instead of appearing to be new evidence',
    (tester) async {
      final updated = item({
        'imageUrl': 'earlier-photo',
        'photoSubmittedAt': base.toIso8601String(),
        'observedAt': base.add(const Duration(minutes: 10)).toIso8601String(),
      });
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ResidentReportEvidenceCard(report: updated),
            ),
          ),
        ),
      );
      expect(find.text('Photo from an earlier submission'), findsOneWidget);
    },
  );
  testWidgets(
    'account switch while saving closes edit once and ignores the late success',
    (tester) async {
      String? uid = 'resident';
      final auth = StreamController<String?>();
      final save = Completer<void>();
      var started = 0;
      await tester.pumpWidget(
        shell(
          ReportHistoryScreen(
            currentAccount: () => uid,
            accountChanges: auth.stream,
            createHistory: (_) =>
                ReportHistory((_) async => ReportPage([item()])),
            saveEdit: (_, _, _) {
              started++;
              return save.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Update Flood Level / Notes'));
      await tester.tap(find.text('Update Flood Level / Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save update'));
      await tester.pump();
      expect(started, 1);
      uid = 'another';
      auth.add(uid);
      await tester.pump();
      auth.add(
        uid,
      ); // Repeated token/auth events must not pop the history route.
      await tester.pumpAndSettle();
      save.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Account changed.'), findsOneWidget);
      expect(find.text('Report updated successfully.'), findsNothing);
      expect(find.text('Original observation'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(auth.close());
      await tester.pump();
    },
    skip: AppEnvironment.sparkFollowupsEnabled,
  );
}
