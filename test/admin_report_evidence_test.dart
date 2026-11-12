import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/road_location_preview.dart';
import 'package:safepaths_app/utils/geo_utils.dart';
import 'package:safepaths_app/widgets/admin_report_evidence.dart';
import 'package:safepaths_app/widgets/report_submission_preview.dart';
import 'report_history_layout_test.dart' as fixtures;

UserReport sample({
  Map<String, dynamic>? location,
  Map<String, dynamic>? original,
}) => UserReport(
  id: 'evidence',
  userId: 'resident',
  title: 'Flooding: Sample road',
  description: 'Water near the intersection.',
  severity: 'High',
  status: 'pending',
  createdAt: DateTime(2026, 11, 10, 13, 28),
  observedAt: DateTime(2026, 11, 10, 13, 20),
  location: location,
  originalSubmission: original,
);
const position = {'lat': 14.675512345, 'lng': 120.980598765, 'source': 'gps'};

class Capture implements RoadPreviewCapture {
  final requests = <RoadPreviewRequest>[];
  final result = Completer<Uint8List>();
  @override
  Future<Uint8List> render(RoadPreviewRequest r) {
    requests.add(r);
    return result.future;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test('location validates values and never infers the source', () {
    expect(ReportedLocationEvidence.from(sample()), isNull);
    for (final invalid in [
      {'lat': 91, 'lng': 120},
      {'lat': 14, 'lng': double.nan},
      {'lat': '14', 'lng': 120},
    ]) {
      expect(ReportedLocationEvidence.from(sample(location: invalid)), isNull);
    }
    expect(
      ReportedLocationEvidence.from(sample(location: position))!.sourceLabel,
      'GPS location',
    );
    expect(
      ReportedLocationEvidence.from(
        sample(location: {...position, 'source': 'manual'}),
      )!.sourceLabel,
      'Map pin',
    );
    expect(
      ReportedLocationEvidence.from(
        sample(location: {'lat': 14, 'lng': 120, 'accuracy': 1}),
      )!.sourceLabel,
      'Location source not recorded',
    );
  });
  testWidgets(
    'essential evidence is visible and copying retains stored precision',
    (tester) async {
      String? copied;
      var opens = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: SingleChildScrollView(
              child: AdminReportEvidenceCard(
                report: sample(location: position),
                onViewMap: () => opens++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resident-selected flood level'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Resident observation time'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('14.675512, 120.980599'), findsOneWidget);
      await tester.ensureVisible(find.text('Copy coordinates'));
      await tester.tap(find.text('Copy coordinates'));
      await tester.pumpAndSettle();
      expect(copied, '14.675512345, 120.980598765');
      expect(find.text('Coordinates copied.'), findsOneWidget);
      await tester.tap(find.text('View on map'));
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing coordinates do not offer a map or clipboard action', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: SingleChildScrollView(
            child: AdminReportEvidenceCard(report: sample()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('View on map'), findsNothing);
    expect(find.text('Copy coordinates'), findsNothing);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('No photo attached'), findsOneWidget);
  });
  test(
    'original submission location is not replaced by later edited evidence',
    () {
      final r = sample(
        location: position,
        original: {
          'location': {'lat': 14.1, 'lng': 120.2, 'source': 'manual'},
          'description': 'Original evidence',
          'severity': 'Low',
          'observedAt': '2026-11-09T13:00:00',
          'submittedAt': '2026-11-09T13:05:00',
        },
      );
      final original = submittedReportEvidence(r);
      expect(ReportedLocationEvidence.from(original)!.copyValue, '14.1, 120.2');
      expect(original.description, 'Original evidence');
      expect(original.observedAt, DateTime(2026, 11, 9, 13));
    },
  );
  test('point-only snapshots are available and identity follows the point', () {
    final a = RoadPreviewRequest(
      [],
      width: 280,
      dark: false,
      reportedPoint: GeoCoord(14, 120),
    );
    final b = RoadPreviewRequest(
      [],
      width: 280,
      dark: false,
      reportedPoint: GeoCoord(14.1, 120),
    );
    expect(a.available, isTrue);
    expect(a.identity, isNot(b.identity));
    expect((jsonDecode(a.geoJson) as Map)['features'], isEmpty);
    expect(
      RoadPreviewRequest(
        [],
        width: 280,
        dark: false,
        reportedPoint: GeoCoord(double.nan, 120),
      ).available,
      isFalse,
    );
  });
  testWidgets(
    'map failure preserves the reported coordinates and close action',
    (tester) async {
      final capture = Capture();
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: ReportLocationMapDialog(
              report: sample(location: position),
              capture: () => capture,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(capture.requests.single.reportedPoint!.lat, 14.675512345);
      capture.result.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('14.675512, 120.980599'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Retry map'), findsOneWidget);
      expect(find.text('Confirm and save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'evidence fits narrow screens with large text in both languages and themes',
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
                body: SingleChildScrollView(
                  child: AdminReportEvidenceCard(
                    report: sample(location: position),
                  ),
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
    },
  );
  testWidgets(
    'location comes before flood level and report metadata is not hidden',
    (tester) async {
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: SingleChildScrollView(
              child: AdminReportEvidenceCard(
                report: sample(location: position),
                reporterName: 'Sample resident',
                reporterTrust: 50,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Reported location')).dy,
        lessThan(
          tester.getTopLeft(find.text('Resident-selected flood level')).dy,
        ),
      );
      await tester.ensureVisible(find.text('Report information'));
      await tester.pumpAndSettle();
      expect(find.text('More details'), findsNothing);
      expect(find.text('Reported by'), findsOneWidget);
      expect(find.text('Sample resident'), findsOneWidget);
      expect(find.text('Reporter trust score'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
