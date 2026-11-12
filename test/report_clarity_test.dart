import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/user/report_submission_screen.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/widgets/report_review_summary.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'CLARITY_TEST=true');
    GoogleFonts.config.allowRuntimeFetching = false;
    SimulatedWeatherService.instance;
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  testWidgets(
    'English and Filipino report choices fit a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('fil')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const ReportSubmissionScreen(prefilledRoadId: 'clarity-road'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final choice = language == 'fil' ? 'Mababa' : 'Low';
        await tester.ensureVisible(find.byKey(ValueKey('flood-level-$choice')));
        await tester.tap(find.byKey(ValueKey('flood-level-$choice')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Semantics>(find.byKey(ValueKey('flood-level-$choice')))
              .properties
              .selected,
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'Filipino verification choices and guidance fit a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fil'),
          supportedLocales: const [Locale('en'), Locale('fil')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
                    reportId: 'r',
                    loadContext: () async => {
                      'token': 'a' * 64,
                      'report': {
                        'title': 'Synthetic',
                        'description': 'Test',
                        'severity': 'Low',
                      },
                      'roads': [
                        {'name': 'Road', 'status': 'passable'},
                      ],
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
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'asking for urgent help does not assume or overwrite the observed flood level',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportSubmissionScreen(prefilledRoadId: 'clarity-road'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report road conditions'), findsOneWidget);
      for (final level in ['Low', 'Medium', 'High']) {
        expect(
          tester
              .widget<Semantics>(find.byKey(ValueKey('flood-level-$level')))
              .properties
              .selected,
          false,
        );
      }
      final urgent = find.byType(Switch);
      await tester.ensureVisible(urgent);
      await tester.tap(urgent);
      await tester.pumpAndSettle();
      expect(find.text('Urgent report'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('flood-level-High')))
            .properties
            .selected,
        false,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('flood-level-Low')));
      await tester.tap(find.byKey(const ValueKey('flood-level-Low')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(urgent);
      await tester.tap(urgent);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('flood-level-Low')))
            .properties
            .selected,
        true,
      );
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('flood-level-High')))
            .properties
            .selected,
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resident summary distinguishes a verified observation from an impassable road',
    (tester) async {
      final report = UserReport(
        id: 'r',
        title: 'Synthetic',
        description: 'Test',
        createdAt: DateTime(2026),
        severity: 'Low',
        status: 'verified',
        userId: 'owner',
      );
      final road = RoadStatus(
        id: 'road',
        name: 'Road',
        status: 'not_passable',
        notes: 'Test',
        updatedAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportReviewSummary(report: report, road: road),
          ),
        ),
      );
      expect(find.text('Report review: Observation verified'), findsOneWidget);
      expect(
        find.text('Last recorded road condition: Not passable'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Check the road condition separately'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a private message claiming verification does not replace the recorded review status',
    (tester) async {
      final report = UserReport(
        id: 'r',
        title: 'Synthetic',
        description: 'Test',
        createdAt: DateTime(2026),
        severity: 'Low',
        status: 'under_review',
        userId: 'owner',
        adminReply: 'Your report is verified.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportReviewSummary(report: report)),
        ),
      );
      expect(find.text('Report review: Under review'), findsOneWidget);
      expect(find.text('Report review: Observation verified'), findsNothing);
      expect(
        find.textContaining('Private messages are updates.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a new report requires a deliberate flood level before submission',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportSubmissionScreen(prefilledRoadId: 'clarity-road'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Synthetic observation for form validation.',
      );
      await tester.ensureVisible(find.text('SUBMIT REPORT'));
      await tester.tap(find.text('SUBMIT REPORT'));
      await tester.pump();
      expect(
        find.text('Please choose the flood level you observed.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
