import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/screens/admin/user_reports_screen.dart';
import 'package:safepaths_app/widgets/user_report_card.dart';
import 'package:safepaths_app/widgets/admin_report_workspace.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';
import 'package:safepaths_app/widgets/safe_image.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/theme/app_palette.dart';

final now = DateTime(2026, 10, 30, 15);
UserReport item([Map<String, dynamic> extra = const {}]) =>
    UserReport.fromJson({
      'id': 'report',
      'userId': 'resident',
      'roadId': 'road',
      'title': 'Deep Water: Unnamed residential (OSM 552835258)',
      'description': 'Ankle-deep water across the road.',
      'severity': 'High',
      'status': 'pending',
      'createdAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
      'observedAt': now.subtract(const Duration(minutes: 20)).toIso8601String(),
      ...extra,
    });
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
  home: Scaffold(body: child),
);
Widget card(UserReport report, {VoidCallback? onTap, bool busy = false}) =>
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: UserReportCard(
        report: report,
        now: () => now,
        onTap: onTap,
        busy: busy,
      ),
    );
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'LIST_TEST=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  test('list and inspector use the same precise outcome labels', () {
    for (final pair in {
      'pending': 'Needs review',
      'under_review': 'Under review',
      'verified': 'Verified',
      'resolved': 'Reviewed',
      'dismissed': 'Dismissed',
      'expired': 'Outdated',
      'unknown': 'Unknown',
    }.entries) {
      expect(reportReviewLabel(item({'status': pair.key})), pair.value);
    }
    expect(
      reportReviewLabel(
        item({'status': 'dismissed', 'dismissReason': 'needs_correction'}),
      ),
      'Needs correction',
    );
    expect(
      reportReviewLabel(
        item({
          'status': 'verified',
          'rewardCorrection': {'reversed': 5, 'penalty': 0},
        }),
      ),
      'Follow-up review corrected',
    );
  });
  testWidgets(
    'card shows one outcome, honest observation and submission ages, and current evidence',
    (tester) async {
      final report = item({
        'imageUrl': 'current-photo',
        'photoSubmittedAt': now
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'originalSubmission': {
          'description': 'Original notes',
          'imageUrl': 'original-photo',
        },
      });
      await tester.pumpWidget(shell(card(report)));
      expect(find.text('Needs review'), findsOneWidget);
      expect(find.text('Unnamed residential road'), findsOneWidget);
      expect(find.text('Observed: 20 minutes ago'), findsOneWidget);
      expect(find.text('Submitted: 10 minutes ago'), findsOneWidget);
      expect(find.text('Photo from an earlier submission'), findsOneWidget);
      expect(
        tester.widget<SafeImage>(find.byType(SafeImage)).imageUrl,
        'current-photo',
      );
      expect(find.text('Original notes'), findsNothing);
      expect(find.textContaining('OSM'), findsNothing);
      expect(find.textContaining('TRUST'), findsNothing);
      expect(find.text('DEEP WATER'), findsNothing);
      expect(find.text('Urgent assistance requested'), findsNothing);
    },
  );
  testWidgets(
    'missing observation time is labelled submitted and same-minute times are not repeated',
    (tester) async {
      final missing = UserReport(
        id: 'missing',
        userId: 'resident',
        title: 'Road',
        description: 'Notes',
        severity: 'Low',
        status: 'pending',
        createdAt: now,
      );
      await tester.pumpWidget(shell(card(missing)));
      expect(find.textContaining('Observed:'), findsNothing);
      expect(find.textContaining('Submitted:'), findsOneWidget);
      await tester.pumpWidget(
        shell(
          card(
            item({
              'createdAt': now.toIso8601String(),
              'observedAt': now.toIso8601String(),
            }),
          ),
        ),
      );
      expect(find.textContaining('Observed:'), findsOneWidget);
      expect(find.textContaining('Submitted:'), findsNothing);
    },
  );
  testWidgets(
    'private updates and road attention do not imply a manual reply or reopen the report',
    (tester) async {
      await tester.pumpWidget(
        shell(
          SingleChildScrollView(
            child: UserReportCard(
              report: item({'status': 'verified', 'hasAdminUpdates': true}),
              now: () => now,
              roadNeedsAttention: true,
              reporterName: 'Actual reporter',
            ),
          ),
        ),
      );
      expect(find.text('Verified'), findsOneWidget);
      expect(find.byTooltip('Private updates'), findsOneWidget);
      expect(find.text('Road condition needs review'), findsOneWidget);
      expect(find.text('View details'), findsOneWidget);
      expect(find.text('Needs review'), findsNothing);
      expect(find.text('REPLY SENT'), findsNothing);
      expect(find.text('Reported by: Actual reporter'), findsOneWidget);
    },
  );
  testWidgets(
    'one card tap opens its report; busy cards do not trigger an action',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(shell(card(item(), onTap: () => opened++)));
      await tester.tap(find.text('Review report'));
      expect(opened, 1);
      await tester.pumpWidget(
        shell(card(item(), onTap: () => opened++, busy: true)),
      );
      await tester.tap(find.text('Review report'));
      expect(opened, 1);
    },
  );
  testWidgets(
    'follow-up outcome is independent and urgent assistance only follows its stored flag',
    (tester) async {
      await tester.pumpWidget(
        shell(
          card(
            item({
              'reportType': 'followup',
              'rootReportId': 'root',
              'isEmergency': true,
              'status': 'under_review',
            }),
          ),
        ),
      );
      expect(find.text('Follow-up'), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('Urgent assistance requested'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    },
  );
  testWidgets(
    'cards wrap in both themes and languages on narrow displays at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          for (final status in [
            'pending',
            'verified',
            'dismissed',
            'expired',
          ]) {
            await tester.pumpWidget(
              shell(
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: UserReportCard(
                    report: item({
                      'status': status,
                      'reportType': 'followup',
                      'rootReportId': 'root',
                      'imageUrl': 'test-photo',
                      'isEmergency': true,
                      'hasAdminUpdates': true,
                      'description': List.filled(
                        8,
                        'Long resident observation.',
                      ).join(' '),
                    }),
                    reporterName: List.filled(
                      5,
                      'Long reporter name',
                    ).join(' '),
                    now: () => now,
                    onTap: () {},
                  ),
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
              reason: '$language dark=$dark status=$status',
            );
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
  testWidgets(
    'real reports list opens the selected inspector and keeps completed and dismissed records in All reports',
    (tester) async {
      final state = AppStateService.instance;
      final previous = [...state.reports];
      final current = DateTime.now();
      state.reports
        ..clear()
        ..addAll([
          item({
            'id': 'pending',
            'createdAt': current.toIso8601String(),
            'observedAt': current.toIso8601String(),
          }),
          item({
            'id': 'completed',
            'status': 'verified',
            'description': 'Verified report sample',
            'createdAt': current.toIso8601String(),
          }),
          item({
            'id': 'dismissed',
            'status': 'dismissed',
            'description': 'Dismissed report sample',
            'createdAt': current.toIso8601String(),
          }),
        ]);
      addTearDown(() {
        state.reports
          ..clear()
          ..addAll(previous);
      });
      await tester.pumpWidget(
        shell(
          UserReportsScreen(
            initialReportId: 'completed',
            loadReport: (id) async => {
              'report': state.reports.firstWhere((r) => r.id == id).toJson(),
            },
            selectedReportChanges: (id) =>
                Stream.value(state.reports.firstWhere((r) => r.id == id)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AdminReportWorkspace>(find.byType(AdminReportWorkspace))
            .report
            .id,
        'completed',
      );
      await tester.tap(find.byTooltip('Back to list'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminReportWorkspace), findsNothing);
      expect(find.text('Review queue'), findsOneWidget);
      expect(find.text('Actionable (1)'), findsNothing);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsNothing);
      expect(find.byTooltip('Refresh reports'), findsOneWidget);
      final dismissedCard = find.byWidgetPredicate(
        (w) => w is UserReportCard && w.report.id == 'dismissed',
      );
      await tester.scrollUntilVisible(
        dismissedCard,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(dismissedCard, findsOneWidget);
      final completeCard = find.byWidgetPredicate(
        (w) => w is UserReportCard && w.report.id == 'completed',
      );
      await tester.scrollUntilVisible(
        completeCard,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('report-list-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final detailsAction = find.descendant(
        of: completeCard,
        matching: find.text('View details'),
      );
      await tester.ensureVisible(detailsAction);
      await tester.pumpAndSettle();
      await tester.tap(detailsAction);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AdminReportWorkspace>(find.byType(AdminReportWorkspace))
            .report
            .id,
        'completed',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'all filters stay reachable on narrow screens and selected dark text has sufficient contrast',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              const UserReportsScreen(),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          final label = language == 'fil' ? 'Kasaysayan' : 'History';
          expect(find.text(label).hitTestable(), findsOneWidget);
          final selectedTab = tester
              .widgetList<Semantics>(find.byType(Semantics))
              .singleWhere(
                (s) =>
                    s.properties.button == true &&
                    s.properties.selected == true,
              );
          final selectedText = tester.widget<Text>(
            find.descendant(
              of: find.byWidget(selectedTab),
              matching: find.byType(Text),
            ),
          );
          final palette = AppPalette.of(
            tester.element(find.byWidget(selectedTab)),
          );
          final fg = selectedText.style!.color!.computeLuminance(),
              bg = palette.surface.computeLuminance();
          final ratio =
              ((fg > bg ? fg : bg) + .05) / ((fg < bg ? fg : bg) + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets(
    'attention count does not shrink when browsing a paginated history page',
    (tester) async {
      final state = AppStateService.instance,
          previous = [...AppStateService.instance.reports];
      final current = DateTime.now();
      state.reports
        ..clear()
        ..addAll(
          List.generate(
            45,
            (i) => item({
              'id': 'pending-$i',
              'createdAt': current
                  .subtract(Duration(minutes: i))
                  .toIso8601String(),
            }),
          ),
        );
      addTearDown(() {
        state.reports
          ..clear()
          ..addAll(previous);
      });
      await tester.pumpWidget(shell(const UserReportsScreen()));
      await tester.pumpAndSettle();
      expect(state.reports.where((r) => r.needsAdminReview).length, 45);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(state.reports.where((r) => r.needsAdminReview).length, 45);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('All reports'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('All reports').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Page 1'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Page 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
