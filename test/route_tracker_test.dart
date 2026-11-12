import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/utils/route_tracker.dart';

geo.Position makeGeoPos({
  required double lat,
  required double lng,
  double accuracy = 5.0,
}) {
  return geo.Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime(2026, 1, 1),
    accuracy: accuracy,
    altitude: 0.0,
    altitudeAccuracy: 0.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );
}

PlannedRoute makeTestRoute(List<Position> points, {List<RouteStep>? steps}) {
  return PlannedRoute(
    points: points,
    durationMin: 10,
    distanceMiles: 1.0,
    summary: 'Test Route',
    hazardAlerts: const [],
    safetyStatus: 'safe',
    steps: steps ??
        [
          RouteStep(
            instruction: 'Depart north on Main St',
            modifier: 'straight',
            type: 'depart',
            distance: 0,
            location: points.first,
          ),
          RouteStep(
            instruction: 'Turn right on Oak St',
            modifier: 'right',
            type: 'turn',
            distance: 200,
            location: points.length > 2 ? points[1] : points.last,
          ),
          RouteStep(
            instruction: 'Arrive at destination',
            modifier: 'straight',
            type: 'arrive',
            distance: 200,
            location: points.last,
          ),
        ],
  );
}

void main() {
  group('RouteTracker Step Progression & Geometry Tests', () {
    late DateTime simulatedTime;
    DateTime clock() => simulatedTime;

    setUp(() {
      simulatedTime = DateTime(2026, 1, 1, 12, 0, 0);
    });

    test('Index starts at the first turn (not "depart")', () {
      final pts = [
        Position(120.9700, 14.6700), // depart
        Position(120.9700, 14.6720), // turn right (~222m away)
        Position(120.9730, 14.6720), // arrive
      ];
      final steps = [
        RouteStep(
          instruction: 'Depart on 1st St',
          modifier: 'straight',
          type: 'depart',
          distance: 0,
          location: pts[0],
        ),
        RouteStep(
          instruction: 'Turn right on 2nd St',
          modifier: 'right',
          type: 'turn',
          distance: 222,
          location: pts[1],
        ),
        RouteStep(
          instruction: 'Arrive at destination',
          modifier: 'straight',
          type: 'arrive',
          distance: 333,
          location: pts[2],
        ),
      ];

      final tracker = RouteTracker(
        route: makeTestRoute(pts, steps: steps),
        now: clock,
      );

      // Initial index must be 1 (first maneuver ahead, skipping depart step 0)
      expect(tracker.currentStepIndex, 1);

      final res = tracker.update(makeGeoPos(lat: 14.6700, lng: 120.9700));
      expect(res.stepIndex, 1);
      expect(res.distanceToNextStep > 200.0, true);
    });

    test('Advances after passing a turn and live distance decreases', () {
      final pts = [
        Position(120.9700, 14.6700), // 0m
        Position(120.9700, 14.6720), // ~222m (turn 1)
        Position(120.9730, 14.6720), // ~555m (arrival)
      ];
      final steps = [
        RouteStep(
          instruction: 'Depart',
          modifier: 'straight',
          type: 'depart',
          distance: 0,
          location: pts[0],
        ),
        RouteStep(
          instruction: 'Turn right',
          modifier: 'right',
          type: 'turn',
          distance: 222,
          location: pts[1],
        ),
        RouteStep(
          instruction: 'Arrive',
          modifier: 'straight',
          type: 'arrive',
          distance: 333,
          location: pts[2],
        ),
      ];

      final tracker = RouteTracker(
        route: makeTestRoute(pts, steps: steps),
        now: clock,
      );

      // Start: ~222m to turn 1
      var res = tracker.update(makeGeoPos(lat: 14.6700, lng: 120.9700));
      expect(res.stepIndex, 1);
      final initialDist = res.distanceToNextStep;

      // Move 100m forward along route: distance decreases
      res = tracker.update(makeGeoPos(lat: 14.6709, lng: 120.9700));
      expect(res.stepIndex, 1);
      expect(res.distanceToNextStep < initialDist, true);

      // Advance past turn 1 (to 14.6721, past the 222m point)
      res = tracker.update(makeGeoPos(lat: 14.6720, lng: 120.9710));
      expect(res.stepIndex, 2);
      expect(res.stepChanged, true);
    });

    test('Does not advance while off-route', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6720),
        Position(120.9730, 14.6720),
      ];
      final steps = [
        RouteStep(
          instruction: 'Depart',
          modifier: 'straight',
          type: 'depart',
          distance: 0,
          location: pts[0],
        ),
        RouteStep(
          instruction: 'Turn right',
          modifier: 'right',
          type: 'turn',
          distance: 222,
          location: pts[1],
        ),
        RouteStep(
          instruction: 'Arrive',
          modifier: 'straight',
          type: 'arrive',
          distance: 333,
          location: pts[2],
        ),
      ];

      final tracker = RouteTracker(
        route: makeTestRoute(pts, steps: steps),
        now: clock,
      );

      // User wanders far off-route (>200m away perpendicular)
      final offRouteRes = tracker.update(makeGeoPos(lat: 14.6725, lng: 120.9750));
      expect(offRouteRes.distanceToRoute > 40.0, true);
      expect(offRouteRes.stepIndex, 1); // Remains at step 1
    });

    test('Loop/parallel-street route does not snap to an earlier segment', () {
      // Create a U-shaped / loop route: goes North on A St, East on B St, South on C St (parallel)
      final pts = [
        Position(120.9700, 14.6700), // 0: A St start
        Position(120.9700, 14.6750), // 1: A St end (~550m)
        Position(120.9703, 14.6750), // 2: B St (30m parallel offset)
        Position(120.9703, 14.6700), // 3: C St end
      ];

      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      // Start on segment 0
      tracker.update(makeGeoPos(lat: 14.6700, lng: 120.9700));
      expect(tracker.currentSegmentIndex, 0);

      // Move along to segment 1 then 2
      tracker.update(makeGeoPos(lat: 14.6748, lng: 120.9700));
      tracker.update(makeGeoPos(lat: 14.6750, lng: 120.9702));
      tracker.update(makeGeoPos(lat: 14.6730, lng: 120.9703)); // Travelling South on C St

      expect(tracker.currentSegmentIndex >= 2, true);

      // Now at lat 14.6710 on C St (close to A St at 120.9700 vs C St at 120.9703)
      // Monotonic projection must maintain segment 2 (C St), NOT snap back to segment 0 (A St)
      final res = tracker.update(makeGeoPos(lat: 14.6710, lng: 120.9703));
      expect(tracker.currentSegmentIndex, 2);
      expect(res.shouldReroute, false);
    });

    test('Off-route counter persists until resetOffRoute is called', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6750),
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      final offRouteLat = 14.6710;
      final offRouteLng = 120.9730;

      // Fix 1 (t=0)
      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      // Fix 2 (t=3s)
      simulatedTime = simulatedTime.add(const Duration(seconds: 3));
      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      // Fix 3 (t=6s) -> triggers
      simulatedTime = simulatedTime.add(const Duration(seconds: 3));
      var res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      expect(res.shouldReroute, true);

      // Fix 4 (t=7s) without resetOffRoute -> MUST still return shouldReroute=true
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      expect(res.shouldReroute, true, reason: 'shouldReroute must remain true while deviation continues');

      // Now call resetOffRoute() after gate acquisition
      tracker.resetOffRoute();

      // Next fix at t=8s -> count becomes 1, so shouldReroute is false until debounced again
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      expect(res.shouldReroute, false);
    });
  });

  group('RouteTracker Jitter, Accuracy, and Gate Unit Tests', () {
    late DateTime simulatedTime;
    DateTime clock() => simulatedTime;

    setUp(() {
      simulatedTime = DateTime(2026, 1, 1, 12, 0, 0);
    });

    test('On-route jitter never triggers reroute', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6710),
        Position(120.9700, 14.6720),
        Position(120.9700, 14.6730),
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      for (int i = 0; i < 20; i++) {
        simulatedTime = simulatedTime.add(const Duration(seconds: 1));
        final jitterLng = 120.9700 + (i % 2 == 0 ? 0.00005 : -0.00005);
        final lat = 14.6700 + (i * 0.0001);
        final res = tracker.update(makeGeoPos(lat: lat, lng: jitterLng, accuracy: 5.0));

        expect(res.shouldReroute, false);
        expect(res.arrived, false);
      }
    });

    test('5s deviation does NOT trigger reroute', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6750),
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      final offRouteLng = 120.9720;
      final offRouteLat = 14.6710;

      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      simulatedTime = simulatedTime.add(const Duration(seconds: 3));
      final res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      expect(res.shouldReroute, false);
    });

    test('Accuracy 80m fixes are ignored without resetting counters', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6750),
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      final offRouteLng = 120.9720;
      final offRouteLat = 14.6710;

      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng, accuracy: 10.0));
      simulatedTime = simulatedTime.add(const Duration(seconds: 3));
      final noisyRes = tracker.update(makeGeoPos(lat: 14.6700, lng: 120.9700, accuracy: 80.0));
      expect(noisyRes.ignoredLowAccuracy, true);

      simulatedTime = simulatedTime.add(const Duration(seconds: 3));
      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng, accuracy: 10.0));
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      final res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng, accuracy: 10.0));
      expect(res.shouldReroute, true);
    });

    test('Returning to the route resets counters', () {
      final pts = [
        Position(120.9700, 14.6700),
        Position(120.9700, 14.6750),
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      final offRouteLng = 120.9720;
      final offRouteLat = 14.6710;

      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      simulatedTime = simulatedTime.add(const Duration(seconds: 4));
      tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));

      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      final onRouteRes = tracker.update(makeGeoPos(lat: 14.6710, lng: 120.9700));
      expect(onRouteRes.shouldReroute, false);

      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      final res = tracker.update(makeGeoPos(lat: offRouteLat, lng: offRouteLng));
      expect(res.shouldReroute, false);
    });

    test('Jump ahead of >700m is not flagged off-route', () {
      final pts = <Position>[];
      for (int i = 0; i <= 150; i++) {
        pts.add(Position(120.9700, 14.6700 + (i * 0.0001)));
      }

      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        now: clock,
      );

      tracker.update(makeGeoPos(lat: 14.6700, lng: 120.9700));
      simulatedTime = simulatedTime.add(const Duration(seconds: 10));
      final jumpLat = 14.6700 + (80 * 0.0001);
      final res = tracker.update(makeGeoPos(lat: jumpLat, lng: 120.9700));

      expect(res.shouldReroute, false);
      expect(tracker.currentSegmentIndex >= 79, true);
    });

    test('Arrival at 25m threshold', () {
      final dest = Position(120.9700, 14.6750);
      final pts = [
        Position(120.9700, 14.6700),
        dest,
      ];
      final tracker = RouteTracker(
        route: makeTestRoute(pts),
        arrivalThresholdMeters: 25.0,
        now: clock,
      );

      var res = tracker.update(makeGeoPos(lat: 14.6741, lng: 120.9700));
      expect(res.arrived, false);

      res = tracker.update(makeGeoPos(lat: 14.67487, lng: 120.9700));
      expect(res.arrived, true);
    });

    test('RerouteGate: backoff 8/16/32/60, success resets, force bypasses cooldown, watchdog', () {
      final gate = RerouteGate(
        baseCooldown: const Duration(seconds: 8),
        maxCooldown: const Duration(seconds: 60),
        watchdogTimeout: const Duration(seconds: 20),
        now: clock,
      );

      // Backoff 8 -> 16 -> 32 -> 60
      expect(gate.tryBegin(), true);
      gate.endFailure();
      expect(gate.currentCooldown, const Duration(seconds: 16));

      simulatedTime = simulatedTime.add(const Duration(seconds: 16));
      expect(gate.tryBegin(), true);
      gate.endFailure();
      expect(gate.currentCooldown, const Duration(seconds: 32));

      simulatedTime = simulatedTime.add(const Duration(seconds: 32));
      expect(gate.tryBegin(), true);
      gate.endFailure();
      expect(gate.currentCooldown, const Duration(seconds: 60));

      // Success resets
      simulatedTime = simulatedTime.add(const Duration(seconds: 60));
      expect(gate.tryBegin(), true);
      gate.endSuccess();
      expect(gate.consecutiveFailures, 0);
      expect(gate.currentCooldown, const Duration(seconds: 8));

      // Force bypasses cooldown but not active lock
      simulatedTime = simulatedTime.add(const Duration(seconds: 8));
      expect(gate.tryBegin(), true);
      expect(gate.tryBegin(force: true), false); // Active lock respected
      gate.endFailure();

      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      expect(gate.tryBegin(force: false), false);
      expect(gate.tryBegin(force: true), true); // Bypasses cooldown

      // Watchdog releases stale lock after 20s
      simulatedTime = simulatedTime.add(const Duration(seconds: 21));
      expect(gate.tryBegin(force: true), true);
    });
  });
}
