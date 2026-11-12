import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/utils/route_tracker.dart';
import 'package:safepaths_app/utils/navigation_units.dart';

geo.Position fix(double lng, double lat) => geo.Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
PlannedRoute route(List<Position> points, {List<RouteStep> steps = const []}) =>
    PlannedRoute(
      points: points,
      durationMin: 10,
      distanceMiles: 1,
      summary: 'Synthetic route',
      hazardAlerts: [],
      safetyStatus: 'safe',
      steps: steps,
    );
void main() {
  test('consistent metric units and calibrated route labels', () {
    expect(navigationDistance(450), '450 m');
    expect(navigationDistance(1609.34), '1.6 km');
    expect(navigationTime(121), '3 min');
    expect(navigationTime(0), '1 min');
    expect(navigationDistance(double.nan), 'Unknown distance');
    expect(navigationRouteLabel('Dynamic Safe Detour'), 'Detour');
    expect(navigationRouteLabel('Safest Route'), 'Suggested route');
  });
  test('a loop can still arrive after traversing its remaining legs', () {
    final points = [
      Position(120.980, 14.676),
      Position(120.980, 14.680),
      Position(120.984, 14.680),
      Position(120.984, 14.676),
      Position(120.9801, 14.676),
    ];
    final tracker = RouteTracker(route: route(points));
    for (final p in points.take(4)) {
      expect(
        tracker.update(fix(p.lng.toDouble(), p.lat.toDouble())).arrived,
        isFalse,
      );
    }
    expect(tracker.update(fix(120.9801, 14.676)).arrived, isTrue);
    expect(tracker.remainingDistanceMeters, 0);
    expect(tracker.remainingSeconds, 0);
  });
  test(
    'fallback remaining time uses exact route duration and preserves metadata',
    () {
      final r = PlannedRoute(
        points: [Position(120.980, 14.676), Position(120.984, 14.676)],
        durationMin: 4,
        durationSeconds: 210,
        distanceMiles: 1,
        summary: 'Test',
        hazardAlerts: [],
        safetyStatus: 'safe',
        steps: [],
      );
      final copy = r.copyWith(summary: 'Updated');
      final tracker = RouteTracker(route: copy);
      tracker.update(fix(120.982, 14.676));
      expect(tracker.hasStepTiming, isFalse);
      expect(tracker.remainingSeconds, closeTo(105, 0.1));
      expect(copy.safetyScoreLabel, 'Route score 100/100');
    },
  );
  test(
    'initial direction remains available until the first leg is established',
    () {
      final a = Position(120.980, 14.676),
          b = Position(120.978, 14.676),
          c = Position(120.978, 14.678);
      final tracker = RouteTracker(
        route: route(
          [a, b, c],
          steps: [
            RouteStep(
              instruction: 'Head west',
              modifier: 'straight',
              type: 'depart',
              distance: 216,
              location: a,
              durationSeconds: 60,
              bearingAfter: 270,
            ),
            RouteStep(
              instruction: 'Turn right',
              modifier: 'right',
              type: 'turn',
              distance: 222,
              location: b,
              durationSeconds: 180,
            ),
            RouteStep(
              instruction: 'Arrive',
              modifier: '',
              type: 'arrive',
              distance: 0,
              location: c,
              durationSeconds: 0,
            ),
          ],
        ),
      );
      tracker.update(fix(120.980, 14.676));
      expect(tracker.initialDirectionStep!.instruction, 'Head west');
      expect(tracker.remainingSeconds, closeTo(240, 0.5));
      final before = tracker.remainingDistanceMeters;
      tracker.update(fix(120.979, 14.676));
      expect(tracker.initialDirectionStep, isNull);
      expect(tracker.remainingSeconds, closeTo(210, 0.5));
      expect(tracker.remainingDistanceMeters, lessThan(before));
      expect(tracker.travelledPoints.length, greaterThanOrEqualTo(2));
      expect(tracker.remainingPoints().first.lng, closeTo(120.979, 0.00001));
    },
  );
  test('an immediate turn takes precedence over a departure description', () {
    final a = Position(120.980, 14.676),
        b = Position(120.980, 14.67605),
        c = Position(120.982, 14.67605);
    final tracker = RouteTracker(
      route: route(
        [a, b, c],
        steps: [
          RouteStep(
            instruction: 'Head north',
            modifier: '',
            type: 'depart',
            distance: 5,
            location: a,
          ),
          RouteStep(
            instruction: 'Turn right',
            modifier: 'right',
            type: 'turn',
            distance: 220,
            location: b,
          ),
          RouteStep(
            instruction: 'Arrive',
            modifier: '',
            type: 'arrive',
            distance: 0,
            location: c,
          ),
        ],
      ),
    );
    tracker.update(fix(120.980, 14.676));
    expect(tracker.initialDirectionStep, isNull);
    expect(tracker.currentStepIndex, 1);
  });
  test(
    'out-and-back progress follows the return leg and preserves the later turn at the repeated point',
    () {
      final a = Position(120.980, 14.676),
          b = Position(120.980, 14.678),
          c = Position(120.984, 14.676);
      final tracker = RouteTracker(
        route: route(
          [a, b, a, c],
          steps: [
            RouteStep(
              instruction: 'Head north',
              modifier: '',
              type: 'depart',
              distance: 222,
              location: a,
              durationSeconds: 60,
            ),
            RouteStep(
              instruction: 'Turn back',
              modifier: 'uturn',
              type: 'turn',
              distance: 222,
              location: b,
              durationSeconds: 60,
            ),
            RouteStep(
              instruction: 'Turn left',
              modifier: 'left',
              type: 'turn',
              distance: 430,
              location: a,
              durationSeconds: 120,
            ),
            RouteStep(
              instruction: 'Arrive',
              modifier: '',
              type: 'arrive',
              distance: 0,
              location: c,
              durationSeconds: 0,
            ),
          ],
        ),
      );
      tracker.update(fix(120.980, 14.676));
      tracker.update(fix(120.980, 14.678));
      final returning = tracker.update(fix(120.980, 14.677));
      expect(tracker.currentSegmentIndex, 1);
      expect(returning.metersAlongRoute, greaterThan(300));
      expect(returning.stepIndex, 2);
      expect(returning.distanceToNextStep, greaterThan(100));
      expect(returning.shouldReroute, isFalse);
    },
  );
  test('remaining estimates freeze for poor or off-route fixes', () {
    final tracker = RouteTracker(
      route: route([Position(120.980, 14.676), Position(120.980, 14.684)]),
    );
    tracker.update(fix(120.980, 14.677));
    final distance = tracker.remainingDistanceMeters,
        time = tracker.remainingSeconds;
    tracker.update(fix(120.984, 14.679));
    expect(tracker.remainingDistanceMeters, distance);
    expect(tracker.remainingSeconds, time);
  });
  test(
    'a noisy initial fix near a later parallel leg must stay on the initial leg',
    () {
      final tracker = RouteTracker(
        route: route([
          Position(120.980, 14.676),
          Position(120.980, 14.680),
          Position(120.98018, 14.680),
          Position(120.98018, 14.676),
          Position(120.984, 14.676),
        ]),
      );
      final first = tracker.update(fix(120.98015, 14.6761));
      expect(tracker.currentSegmentIndex, 0);
      expect(first.metersAlongRoute, lessThan(40));
      final next = tracker.update(fix(120.980, 14.6764));
      expect(tracker.currentSegmentIndex, 0);
      expect(next.shouldReroute, isFalse);
    },
  );
  test(
    'being close to the endpoint at the beginning of a loop is not arrival',
    () {
      final tracker = RouteTracker(
        route: route([
          Position(120.980, 14.676),
          Position(120.980, 14.680),
          Position(120.984, 14.680),
          Position(120.984, 14.676),
          Position(120.9801, 14.676),
        ]),
      );
      expect(tracker.update(fix(120.980, 14.676)).arrived, isFalse);
    },
  );
}
