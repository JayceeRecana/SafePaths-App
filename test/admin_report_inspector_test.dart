import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/user_profile.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/theme/app_palette.dart';
import 'package:safepaths_app/widgets/admin_report_inspector.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';

final submitted = DateTime(2026, 10, 26, 13, 28);
final reviewed = submitted.add(const Duration(minutes: 2));
final latest = submitted.add(const Duration(days: 2));
UserReport report([Map<String, dynamic> extra = const {}]) =>
    UserReport.fromJson({
      'id': 'report',
      'userId': 'resident',
      'roadId': 'road',
      'incidentId': 'incident',
      'title': 'Flood: Unnamed residential (OSM 552835258)',
      'description': 'Ankle-deep water reported by the resident.',
      'severity': 'High',
      'createdAt': submitted.toIso8601String(),
      'observedAt': submitted.toIso8601String(),
      'status': 'pending',
      ...extra,
    });
RoadStatus road([String status = 'passable', DateTime? time]) => RoadStatus(
  id: 'road',
  name: 'Unnamed residential (OSM 552835258)',
  status: status,
  notes: 'No water accumulation during the current check.',
  updatedAt: time ?? latest,
  isVerified: true,
);
Widget shell(
  Widget child, {
  bool dark = false,
  String language = 'en',
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
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(12), child: child),
  ),
);
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'timeline shows stored review and latest road snapshot without inventing road changes',
    () {
      final item = report({
        'status': 'verified',
        'reviewedAt': reviewed.toIso8601String(),
        'incidentReviewStatus': 'not_passable',
        'pointsAwarded': 10,
      });
      final events = inspectorEvents(item, road());
      expect(events.map((e) => e.id), ['submitted', 'review', 'road-latest']);
      expect(events[1].condition, 'not_passable');
      expect(events[1].points, 10);
      expect(events[2].condition, 'passable');
      expect(events[2].title, 'Latest recorded road update');
      expect(events.any((e) => e.title.contains('reopened')), isFalse);
      expect(
        inspectorEvents(item, road('not_passable', reviewed)).map((e) => e.id),
        ['submitted', 'review'],
      );
    },
  );
  test(
    'review-start timestamp survives decoding and copying; waiting state gets no invented event',
    () {
      final pending = report();
      expect(inspectorEvents(pending, null).map((e) => e.id), ['submitted']);
      final started = report({
        'status': 'under_review',
        'reviewStartedAt': reviewed.toIso8601String(),
      });
      final decoded = UserReport.fromJson(
        started.copyWith(description: 'Updated').toJson(),
      );
      expect(decoded.reviewStartedAt, reviewed);
      expect(inspectorEvents(decoded, null).last.time, reviewed);
      expect(inspectorEvents(decoded, null).last.tone, InspectorTone.caution);
      expect(
        inspectorEvents(UserReport.fromJson({'id': 'unknown'}), null),
        isEmpty,
      );
    },
  );
  test(
    'correction displays its actual adjustment without re-awarding original points',
    () {
      final corrected = report({
        'reportType': 'followup',
        'rootReportId': 'root',
        'status': 'verified',
        'reviewedAt': reviewed.toIso8601String(),
        'pointsAwarded': 5,
        'rewardCorrection': {'reversed': 5, 'penalty': 0},
      });
      final event = inspectorEvents(corrected, null).last;
      expect(event.title, 'Follow-up review corrected');
      expect(event.points, isNull);
      expect(event.correction?['reversed'], 5);
      expect(event.tone, InspectorTone.caution);
    },
  );
  testWidgets(
    'pending inspector shows evidence context while keeping technical IDs secondary',
    (tester) async {
      var reviews = 0, dismissals = 0;
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: report(),
            road: road('not_passable'),
            reporter: UserProfile(
              id: 'resident',
              name: 'Resident',
              trustScore: 70,
            ),
            now: () => latest,
            onClose: () {},
            onReview: () => reviews++,
            onDismiss: () => dismissals++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Needs review'), findsOneWidget);
      expect(find.text('Unnamed residential road'), findsOneWidget);
      expect(find.text('Reporter trust score'), findsOneWidget);
      expect(find.text('70/100'), findsOneWidget);
      expect(find.text('Resident-selected flood level'), findsOneWidget);
      expect(find.text('Observed and submitted'), findsOneWidget);
      expect(find.textContaining('Report ID:'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Review report'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Other decision'));
      expect(reviews, 1);
      expect(dismissals, 1);
      await tester.scrollUntilVisible(
        find.text('Technical details'),
        350,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(find.text('70/100'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Review report').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'verified report and later passable update remain distinct and use semantic dot colours',
    (tester) async {
      final item = report({
        'status': 'verified',
        'reviewedAt': reviewed.toIso8601String(),
        'incidentReviewStatus': 'not_passable',
        'pointsAwarded': 10,
      });
      var updates = 0;
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: item,
            road: road('not_passable'),
            now: () => latest,
            onClose: () {},
            onRoadUpdate: () => updates++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verified'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review report'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Update road status'));
      expect(updates, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('event-dot-submitted')),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      Color dot(String id) =>
          ((tester
                      .widget<Container>(find.byKey(ValueKey('event-dot-$id')))
                      .decoration!)
                  as BoxDecoration)
              .color!;
      expect(dot('submitted'), AppPalette.light.primary.withValues(alpha: .12));
      expect(dot('review'), AppPalette.light.passable.withValues(alpha: .12));
      expect(dot('road-latest'), AppPalette.light.error.withValues(alpha: .12));
      expect(dot('submitted'), isNot(dot('review')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'follow-up shows its own evidence and opens only the matching original separately',
    (tester) async {
      final root = report({
        'id': 'root',
        'status': 'verified',
        'pointsAwarded': 10,
      });
      final update = report({
        'id': 'followup',
        'rootReportId': 'root',
        'reportType': 'followup',
        'description': 'Water has decreased in the new observation.',
        'conditionChange': 'improved',
      });
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: update,
            road: road(),
            originalReport: root,
            now: () => latest,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This follow-up'), findsOneWidget);
      expect(find.text(root.description), findsNothing);
      await tester.scrollUntilVisible(
        find.text('View original report'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.tap(find.text('View original report'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReportSubmissionPreview>(
              find.byType(ReportSubmissionPreview),
            )
            .report
            .id,
        'root',
      );
      expect(find.text(root.description), findsOneWidget);
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: update,
            originalReport: report({'id': 'wrong-root'}),
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View original report'), findsNothing);
    },
  );
  testWidgets(
    'inspector fits narrow screens in both languages and themes at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          for (final state in ['pending', 'verified', 'dismissed', 'expired']) {
            await tester.pumpWidget(
              shell(
                AdminReportInspector(
                  report: report({'status': state, 'isEmergency': true}),
                  road: road(),
                  now: () => latest,
                  onClose: () {},
                  onReview: () {},
                  onDismiss: () {},
                ),
                language: language,
                dark: dark,
                scale: 2,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$language dark=$dark status=$state',
            );
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -450),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
  testWidgets('busy inspector disables consequential actions', (tester) async {
    await tester.pumpWidget(
      shell(
        AdminReportInspector(
          report: report(),
          onClose: () {},
          onReview: () {},
          onDismiss: () {},
          busy: true,
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review report'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Other decision'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'private-message draft survives cancelling and reopening its dialog',
    (tester) async {
      final draft = TextEditingController();
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    AdminReplyDialog(reportId: 'report', controller: draft),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'A factual private update',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft.text, 'A factual private update');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('A factual private update'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      draft.dispose();
    },
  );
  testWidgets(
    'status comparison cards have equal heights with different timestamp lengths',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: report({
              'status': 'verified',
              'reviewedAt': reviewed.toIso8601String(),
            }),
            road: road(),
            now: () => latest,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final left = tester.getSize(
        find.byKey(const ValueKey('inspector-summary-This report')),
      );
      final right = tester.getSize(
        find.byKey(
          const ValueKey('inspector-summary-Latest recorded road update'),
        ),
      );
      expect(left.height, closeTo(right.height, .1));
      expect(left.width, closeTo(right.width, .1));
      expect(
        tester.getTopLeft(find.text('Verified')).dy,
        closeTo(tester.getTopLeft(find.text('Passable')).dy, .1),
      );
    },
  );
  testWidgets(
    'evidence context exposes separate observation and submission times plus location before technical details',
    (tester) async {
      final item = report({
        'observedAt': submitted
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
        'location': {'lat': 14.67, 'lng': 121.01},
      });
      var opened = 0;
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: item,
            road: road(),
            reporter: UserProfile(
              id: 'resident',
              name: 'Sample resident',
              trustScore: 70,
            ),
            now: () => latest,
            onClose: () {},
            onViewRoad: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observed'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.textContaining('11:28 AM'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReportEvidenceContext),
          matching: find.textContaining('1:28 PM'),
        ),
        findsOneWidget,
      );
      expect(find.text('14.670000, 121.010000'), findsOneWidget);
      expect(find.text('70/100'), findsOneWidget);
      expect(find.textContaining('Report ID:'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('View road and community updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View road and community updates'));
      expect(opened, 1);
      expect(find.text('Road updates'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown evidence is explicit and future observation time is not described as old',
    (tester) async {
      final item = report({
        'observedAt': latest.add(const Duration(hours: 1)).toIso8601String(),
        'location': {'lat': 999, 'lng': 121.01},
      });
      await tester.pumpWidget(
        shell(
          AdminReportInspector(
            report: item,
            road: road().copyWith(isVerified: false),
            now: () => latest,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unconfirmed'), findsOneWidget);
      expect(find.text('Location not recorded or unavailable'), findsOneWidget);
      expect(find.text('Reporter details unavailable'), findsOneWidget);
      expect(
        find.text(
          'The observation time is in the future. Confirm it with the resident.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'This observation is old. It does not establish the current road condition.',
        ),
        findsNothing,
      );
      expect(find.textContaining('999.000000'), findsNothing);
    },
  );
}
