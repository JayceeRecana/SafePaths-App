import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/road_incident.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/risk_engine.dart';
import 'package:safepaths_app/services/road_incident_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/widgets/report_freshness_summary.dart';
import 'package:safepaths_app/widgets/road_incident_panel.dart';
import 'package:safepaths_app/utils/report_freshness.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;

void main() {
  final now = DateTime(2026, 10, 23, 12);
  UserReport report({DateTime? observed, String status = 'pending'}) =>
      UserReport(
        id: 'r',
        userId: 'u',
        roadId: 'road',
        title: 'Flood',
        description: 'Water',
        createdAt: now,
        observedAt: observed,
        severity: 'High',
        status: status,
      );
  RoadStatus road(String condition, {String status = 'passable'}) => RoadStatus(
    id: 'road',
    name: 'Road',
    status: status,
    notes: '',
    updatedAt: now,
    communityCondition: condition,
    geometry: {
      'type': 'LineString',
      'coordinates': [
        [120.984, 14.675],
        [120.984, 14.677],
      ],
    },
  );

  test('freshness uses observation time, not upload or review time', () {
    final old = report(observed: now.subtract(const Duration(hours: 24)));
    expect(ReportFreshness.isOutdated(old, now), isTrue);
    expect(
      ReportFreshness.isOutdated(
        report(observed: now.subtract(const Duration(hours: 23))),
        now,
      ),
      isFalse,
    );
    expect(ReportFreshness.isOutdated(report(status: 'expired'), now), isTrue);
    expect(
      ReportFreshness.isOutdated(
        report(observed: now.add(const Duration(minutes: 2))),
        now,
      ),
      isTrue,
    );
    expect(
      ReportFreshness.isOutdated(UserReport.fromJson({'id': 'missing'}), now),
      isTrue,
    );
  });

  test(
    'unknown/conflicting incidents remain cautionary in clear weather and never reopen closures',
    () {
      for (final state in [
        'reported_flooding',
        'under_verification',
        'outdated',
        'admin_confirmed',
      ]) {
        expect(road(state).getEffectiveStatus(WeatherState.clear), 'partial');
        expect(
          road(
            state,
            status: 'not_passable',
          ).getEffectiveStatus(WeatherState.clear),
          'not_passable',
        );
        final result = RiskEngine.calculateRoadRisk(
          road: road(state),
          allRoads: [road(state)],
          pendingReports: [],
          weatherState: WeatherState.clear,
          currentTime: now,
        );
        expect(result.finalScore, 30);
        expect(result.riskCategory, 'Watch');
      }
      expect(
        road('resolved').getEffectiveStatus(WeatherState.clear),
        'passable',
      );
    },
  );

  test('routing marks unknown road crossings as unverified, not safe', () {
    final result = RoutingService.instance.evaluateRouteSafety(
      [Position(120.983, 14.676), Position(120.985, 14.676)],
      [road('outdated')],
      'Sedan',
      weatherState: WeatherState.clear,
    );
    expect(result['status'], 'unverified_risk');
    expect(result['unconfirmedCount'], 1);
  });

  test(
    'unverified route scores are labelled unconfirmed, including mixed hazards',
    () {
      PlannedRoute route(String status, int count) => PlannedRoute(
        points: [],
        durationMin: 1,
        distanceMiles: 1,
        summary: 'Route',
        hazardAlerts: [],
        steps: [],
        safetyStatus: status,
        unverifiedRoadCount: count,
      );
      expect(route('unverified_risk', 0).safetyScoreLabel, 'Unconfirmed');
      expect(route('partial', 1).safetyScoreLabel, 'Unconfirmed');
      expect(route('safe', 0).safetyScoreLabel, 'Route score 100/100');
    },
  );

  test('an admin opening a report does not remove its risk contribution', () {
    final currentRoad = road('resolved');
    final pending = RiskEngine.calculateRoadRisk(
      road: currentRoad,
      allRoads: [currentRoad],
      pendingReports: [report()],
      weatherState: WeatherState.clear,
      currentTime: now,
    );
    final reviewing = RiskEngine.calculateRoadRisk(
      road: currentRoad,
      allRoads: [currentRoad],
      pendingReports: [report(status: 'under_review')],
      weatherState: WeatherState.clear,
      currentTime: now,
    );
    expect(reviewing.finalScore, pending.finalScore);
    expect(reviewing.finalScore, greaterThan(0));
  });

  testWidgets(
    'report freshness ages on screen and separates observation from submission',
    (tester) async {
      var clock = now;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportFreshnessSummary(
              report: report(
                observed: now.subtract(const Duration(hours: 23, minutes: 59)),
              ),
              clock: () => clock,
            ),
          ),
        ),
      );
      expect(find.text('Reported just now'), findsOneWidget);
      expect(
        find.textContaining('Observed (reporter supplied) 23 hours ago'),
        findsOneWidget,
      );
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Outdated — current condition unknown'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow large-text incident panel blocks duplicate taps and preserves errors for retry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stream = StreamController<RoadIncidentSnapshot>();
      addTearDown(stream.close);
      final operation = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoadIncidentPanel(
                  roadId: 'road',
                  stream: stream.stream,
                  onObserve: (incident, choice) {
                    calls++;
                    return operation.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      stream.add(
        RoadIncidentSnapshot(
          RoadIncident(
            roadId: 'road',
            incidentId: 'incident',
            state: 'reported_flooding',
            revision: 1,
            lastObservedAt: DateTime.now(),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Still flooded'));
      await tester.tap(find.text('Still flooded'));
      await tester.pump();
      await tester.tap(find.text('Still flooded'));
      await tester.pump();
      expect(calls, 1);
      operation.completeError(
        StateError('Connection interrupted. Please retry.'),
      );
      await tester.pump();
      expect(
        find.text('Connection interrupted. Please retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('road review cannot save without current server details', (
    tester,
  ) async {
    final stream = StreamController<RoadIncidentSnapshot>();
    addTearDown(stream.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoadIncidentPanel(
              roadId: 'road',
              isAdmin: true,
              stream: stream.stream,
            ),
          ),
        ),
      ),
    );
    stream.add(
      RoadIncidentSnapshot(
        RoadIncident(
          roadId: 'road',
          incidentId: 'incident',
          state: 'under_verification',
          revision: 2,
          lastObservedAt: DateTime.now(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review current conditions'));
    await tester.pumpAndSettle();
    FilledButton saveButton() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('admin-review-save')),
    );
    expect(saveButton().onPressed, isNull);
    await tester.enterText(
      find.byType(TextField),
      'Barangay field team checked this road.',
    );
    await tester.pump();
    expect(saveButton().onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(saveButton().onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'cached observations cannot be submitted or used to reopen roads',
    (tester) async {
      final stream = StreamController<RoadIncidentSnapshot>();
      addTearDown(stream.close);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoadIncidentPanel(
                roadId: 'road',
                stream: stream.stream,
                onObserve: (_, _) async {
                  calls++;
                },
              ),
            ),
          ),
        ),
      );
      stream.add(
        RoadIncidentSnapshot(
          RoadIncident(
            roadId: 'road',
            incidentId: 'incident',
            state: 'outdated',
            revision: 1,
            lastObservedAt: DateTime.now().subtract(const Duration(hours: 25)),
          ),
          fromCache: true,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('incident-observe-appears_passable')),
      );
      await tester.pump();
      expect(calls, 0);
      expect(find.text('Outdated — current condition unknown'), findsOneWidget);
      expect(find.textContaining('Saved information'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
