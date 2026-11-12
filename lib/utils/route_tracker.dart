import 'dart:math' as math;
import 'location_fix.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/planned_route.dart';
import 'geo_utils.dart';

/// Result returned by [RouteTracker.update] on every GPS location update.
class TrackResult {
  final bool shouldReroute;
  final bool arrived;
  final int stepIndex;
  final bool stepChanged;
  final double distanceToRoute;
  final double metersAlongRoute;
  final double distanceToNextStep;
  final bool ignoredLowAccuracy;

  const TrackResult({
    required this.shouldReroute,
    required this.arrived,
    required this.stepIndex,
    required this.stepChanged,
    required this.distanceToRoute,
    required this.metersAlongRoute,
    required this.distanceToNextStep,
    this.ignoredLowAccuracy = false,
  });
}

/// Tracks the device's progress along a planned route with telemetry filtering,
/// accuracy-scaled off-route thresholding, along-route step projection, and debouncing.
class RouteTracker {
  final PlannedRoute route;
  final DateTime Function() _now;

  int currentStepIndex;
  int currentSegmentIndex;

  int _consecutiveOffRouteCount = 0;
  DateTime? _firstOffRouteTime;
  double? _lastKnownDistanceToRoute;
  double _lastKnownMetersAlong = 0.0;
  double _matchedMetersAlong = 0.0;
  Position? _lastMatchedPosition;

  double get totalDistanceMeters =>
      _cumulativePointDistances.isEmpty ? 0 : _cumulativePointDistances.last;
  double get metersAlongRoute => _lastKnownMetersAlong;
  double get remainingDistanceMeters =>
      math.max(0, totalDistanceMeters - _lastKnownMetersAlong);
  bool get hasStepTiming =>
      route.steps.length > 1 &&
      route.steps
          .take(route.steps.length - 1)
          .every(
            (s) =>
                s.durationSeconds != null &&
                s.durationSeconds!.isFinite &&
                s.durationSeconds! >= 0,
          ) &&
      route.steps.fold<double>(0, (sum, s) => sum + (s.durationSeconds ?? 0)) >
          0;
  double get remainingSeconds {
    if (hasStepTiming) {
      double seconds = 0;
      for (var i = 0; i + 1 < route.steps.length; i++) {
        final start = _stepDistancesAlongRoute[i],
            end = _stepDistancesAlongRoute[i + 1];
        if (end <= start) {
          if (_lastKnownMetersAlong <= start)
            seconds += route.steps[i].durationSeconds!;
          continue;
        }
        if (_lastKnownMetersAlong >= end) continue;
        seconds +=
            route.steps[i].durationSeconds! *
            ((end - math.max(start, _lastKnownMetersAlong)) / (end - start))
                .clamp(0, 1);
      }
      return seconds;
    }
    final seconds = route.durationSeconds ?? route.durationMin * 60.0;
    return totalDistanceMeters <= 0
        ? 0
        : seconds * (remainingDistanceMeters / totalDistanceMeters).clamp(0, 1);
  }

  // Keep the first direction visible until the first leg is established, except
  // when an immediate turn needs precedence. Never invent a U-turn instruction.
  RouteStep? get initialDirectionStep {
    if (route.steps.length < 2 ||
        route.steps.first.type != 'depart' ||
        route.steps.first.instruction.trim().isEmpty ||
        _lastKnownMetersAlong >= 12)
      return null;
    if (_stepDistancesAlongRoute[1] - _lastKnownMetersAlong <= 15) return null;
    return route.steps.first;
  }

  Position _pointAt(double distance) {
    if (route.points.length < 2) return route.points.first;
    final i = _findSegmentForDistance(distance);
    final start = _cumulativePointDistances[i],
        end = _cumulativePointDistances[i + 1];
    final t = end <= start
        ? 0.0
        : ((distance - start) / (end - start)).clamp(0.0, 1.0);
    final a = route.points[i], b = route.points[i + 1];
    return Position(a.lng + (b.lng - a.lng) * t, a.lat + (b.lat - a.lat) * t);
  }

  List<Position> get travelledPoints {
    if (route.points.length < 2 || _lastKnownMetersAlong <= 0) return [];
    final i = _findSegmentForDistance(_lastKnownMetersAlong);
    return [...route.points.take(i + 1), _pointAt(_lastKnownMetersAlong)];
  }

  final double arrivalThresholdMeters;
  final double maxAcceptableAccuracyMeters;

  // Cumulative distance in meters from route start to each route point
  final List<double> _cumulativePointDistances = [];
  // Precomputed along-route distance in meters for each maneuver step
  final List<double> _stepDistancesAlongRoute = [];

  RouteTracker({
    required this.route,
    this.currentStepIndex = 0,
    this.currentSegmentIndex = 0,
    this.arrivalThresholdMeters = 25.0,
    this.maxAcceptableAccuracyMeters = 60.0,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _precomputeDistances();
    _initCurrentStepIndex();
  }

  void _precomputeDistances() {
    final pts = route.points;
    if (pts.isEmpty) return;

    _cumulativePointDistances.add(0.0);
    double total = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      final d = GeoUtils.haversineMeters(
        pts[i].lat.toDouble(),
        pts[i].lng.toDouble(),
        pts[i + 1].lat.toDouble(),
        pts[i + 1].lng.toDouble(),
      );
      total += d;
      _cumulativePointDistances.add(total);
    }

    final measured = route.steps.fold<double>(
      0,
      (sum, s) =>
          sum + (s.distance.isFinite && s.distance > 0 ? s.distance : 0),
    );
    double previous = 0, reported = 0;
    for (var i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      final anchor = i == 0 && step.type == 'depart'
          ? 0.0
          : i == route.steps.length - 1 && step.type == 'arrive'
          ? totalDistanceMeters
          : _projectStepAnchor(
              step.location,
              previous,
              measured > 0
                  ? reported / measured * totalDistanceMeters
                  : previous,
            );
      _stepDistancesAlongRoute.add(anchor);
      previous = anchor;
      if (step.distance.isFinite && step.distance > 0)
        reported += step.distance;
    }
  }

  int _findSegmentForDistance(double dist) {
    if (_cumulativePointDistances.isEmpty) return 0;
    for (int i = 0; i < _cumulativePointDistances.length - 1; i++) {
      if (_cumulativePointDistances[i + 1] >= dist) {
        return i;
      }
    }
    return math.max(0, _cumulativePointDistances.length - 2);
  }

  void _initCurrentStepIndex() {
    if (route.steps.isEmpty) {
      currentStepIndex = 0;
      return;
    }
    // Next maneuver ahead: first step i >= 1 with stepMeters[i] > metersAlong - 5
    int nextIdx = 0;
    if (_stepDistancesAlongRoute.length > 1) {
      nextIdx = _stepDistancesAlongRoute.length - 1;
      for (int i = 1; i < _stepDistancesAlongRoute.length; i++) {
        if (_stepDistancesAlongRoute[i] > _lastKnownMetersAlong - 5.0) {
          nextIdx = i;
          break;
        }
      }
    }
    currentStepIndex = nextIdx;
  }

  // Match maneuver anchors in route order. Repeated coordinates on an
  // out-and-back route must not project an upcoming turn onto an earlier pass.
  double _projectStepAnchor(Position p, double minimum, double expected) {
    var bestDistance = double.infinity, bestAlong = minimum;
    for (
      var i = _findSegmentForDistance(minimum);
      i + 1 < route.points.length;
      i++
    ) {
      final a = route.points[i], b = route.points[i + 1];
      final start = _cumulativePointDistances[i],
          length = _cumulativePointDistances[i + 1] - start;
      if (length <= 0) continue;
      final dx = b.lng.toDouble() - a.lng.toDouble(),
          dy = b.lat.toDouble() - a.lat.toDouble();
      final lo = ((minimum - start) / length).clamp(0.0, 1.0);
      final t =
          (((p.lng - a.lng) * dx + (p.lat - a.lat) * dy) / (dx * dx + dy * dy))
              .clamp(lo, 1.0);
      final distance = GeoUtils.haversineMeters(
        p.lat.toDouble(),
        p.lng.toDouble(),
        (a.lat + dy * t).toDouble(),
        (a.lng + dx * t).toDouble(),
      );
      final along = start + t * length;
      if (distance < bestDistance - 0.5 ||
          ((distance - bestDistance).abs() <= 0.5 &&
              (along - expected).abs() < (bestAlong - expected).abs())) {
        bestDistance = distance;
        bestAlong = along;
      }
    }
    return math.max(minimum, bestAlong);
  }

  /// Resets off-route counter and timer after reroute gate acquisition or on-route recovery.
  void resetOffRoute() {
    _consecutiveOffRouteCount = 0;
    _firstOffRouteTime = null;
  }

  /// Updates navigation progress and evaluates off-route using raw GPS telemetry.
  TrackResult update(geo.Position position) {
    if (route.points.isEmpty) {
      return TrackResult(
        shouldReroute: false,
        arrived: false,
        stepIndex: currentStepIndex,
        stepChanged: false,
        distanceToRoute: 0.0,
        metersAlongRoute: 0.0,
        distanceToNextStep: 0.0,
      );
    }

    // 1. Accuracy Filter: Ignore fixes worse than 60 meters (do NOT reset off-route counters)
    if (!usableLocationFix(position)) {
      final nextStepDist =
          _stepDistancesAlongRoute.isNotEmpty &&
              currentStepIndex < _stepDistancesAlongRoute.length
          ? math.max(
              0.0,
              _stepDistancesAlongRoute[currentStepIndex] -
                  _lastKnownMetersAlong,
            )
          : 0.0;
      return TrackResult(
        shouldReroute: false,
        arrived: false,
        stepIndex: currentStepIndex,
        stepChanged: false,
        distanceToRoute: _lastKnownDistanceToRoute ?? 0.0,
        metersAlongRoute: _lastKnownMetersAlong,
        distanceToNextStep: nextStepDist,
        ignoredLowAccuracy: true,
      );
    }

    final double userLat = position.latitude;
    final double userLng = position.longitude;

    // 3. Accuracy-scaled dynamic off-route threshold (clamp between 35m and 90m)
    final double dynamicThreshold = (35.0 + position.accuracy * 1.2).clamp(
      35.0,
      90.0,
    );

    // 4. Match route distance and progress together within a plausible corridor.
    final distToRoute = _computeDistanceToRoute(
      userLat,
      userLng,
      dynamicThreshold,
      position.accuracy,
    );
    _lastKnownDistanceToRoute = distToRoute;

    final bool isOffRouteNow = distToRoute > dynamicThreshold;

    // 5. Compute Meters Along Route & Step Progression (Only advance when ON-ROUTE)
    bool stepChanged = false;
    double metersAlong = _lastKnownMetersAlong;

    if (!isOffRouteNow) {
      metersAlong = math.max(_lastKnownMetersAlong, _matchedMetersAlong);
      _lastMatchedPosition = Position(userLng, userLat);
      _lastKnownMetersAlong = metersAlong;

      if (_stepDistancesAlongRoute.isNotEmpty) {
        // Step progression: currentStepIndex is the first step i >= 1 with stepMeters[i] > metersAlong - 5
        int targetStepIndex = currentStepIndex;
        if (_stepDistancesAlongRoute.length > 1) {
          targetStepIndex = _stepDistancesAlongRoute.length - 1;
          for (int i = 1; i < _stepDistancesAlongRoute.length; i++) {
            if (_stepDistancesAlongRoute[i] > metersAlong - 5.0) {
              targetStepIndex = i;
              break;
            }
          }
        }

        if (targetStepIndex != currentStepIndex) {
          currentStepIndex = targetStepIndex;
          stepChanged = true;
        }
      }
    }

    final double distanceToNextStep =
        _stepDistancesAlongRoute.isNotEmpty &&
            currentStepIndex < _stepDistancesAlongRoute.length
        ? math.max(
            0.0,
            _stepDistancesAlongRoute[currentStepIndex] - metersAlong,
          )
        : 0.0;

    final dest = route.points.last;
    final distToDest = GeoUtils.haversineMeters(
      userLat,
      userLng,
      dest.lat.toDouble(),
      dest.lng.toDouble(),
    );
    if (!isOffRouteNow &&
        distToDest <= arrivalThresholdMeters &&
        remainingDistanceMeters <= arrivalThresholdMeters) {
      _lastKnownMetersAlong = totalDistanceMeters;
      return TrackResult(
        shouldReroute: false,
        arrived: true,
        stepIndex: route.steps.isEmpty ? 0 : route.steps.length - 1,
        stepChanged: false,
        distanceToRoute: distToRoute,
        metersAlongRoute: totalDistanceMeters,
        distanceToNextStep: 0,
      );
    }

    // 6. Dual Debounced Off-Route Check (>=3 consecutive fixes AND >=6 seconds sustained deviation)
    // Note: Do NOT clear counters when shouldReroute is returned; keep returning true while off-route.
    bool shouldReroute = false;
    if (isOffRouteNow) {
      _consecutiveOffRouteCount++;
      _firstOffRouteTime ??= _now();

      final elapsedMs = _now().difference(_firstOffRouteTime!).inMilliseconds;
      if (_consecutiveOffRouteCount >= 3 && elapsedMs >= 6000) {
        shouldReroute = true;
      }
    } else {
      _consecutiveOffRouteCount = 0;
      _firstOffRouteTime = null;
    }

    return TrackResult(
      shouldReroute: shouldReroute,
      arrived: false,
      stepIndex: currentStepIndex,
      stepChanged: stepChanged,
      distanceToRoute: distToRoute,
      metersAlongRoute: metersAlong,
      distanceToNextStep: distanceToNextStep,
    );
  }

  /// Calculates perpendicular distance to the forward route polyline.
  /// Restricts matching to plausible progress to disambiguate overlapping legs.
  double _computeDistanceToRoute(
    double userLat,
    double userLng,
    double dynamicThreshold,
    double accuracy,
  ) {
    final points = route.points;
    if (points.length < 2)
      return points.isEmpty
          ? double.infinity
          : GeoUtils.haversineMeters(
              userLat,
              userLng,
              points.first.lat.toDouble(),
              points.first.lng.toDouble(),
            );
    final anchor = _lastMatchedPosition ?? points.first;
    final movement = GeoUtils.haversineMeters(
      userLat,
      userLng,
      anchor.lat.toDouble(),
      anchor.lng.toDouble(),
    );
    final floor = math.max(
      0.0,
      _lastKnownMetersAlong - math.max(20.0, accuracy),
    );
    final ceiling = math.min(
      totalDistanceMeters,
      _lastKnownMetersAlong + math.max(80.0, movement * 1.8 + accuracy * 2),
    );
    final expected = _lastMatchedPosition == null
        ? 0.0
        : _lastKnownMetersAlong + movement;
    final matches = <({int segment, double along, double distance})>[];
    for (
      var i = _findSegmentForDistance(floor);
      i + 1 < points.length && _cumulativePointDistances[i] <= ceiling;
      i++
    ) {
      final start = _cumulativePointDistances[i],
          end = _cumulativePointDistances[i + 1],
          length = end - start;
      if (length <= 0 || end < floor) continue;
      final a = points[i], b = points[i + 1];
      final dx = b.lng.toDouble() - a.lng.toDouble(),
          dy = b.lat.toDouble() - a.lat.toDouble();
      final square = dx * dx + dy * dy;
      final lo = ((floor - start) / length).clamp(0.0, 1.0),
          hi = ((ceiling - start) / length).clamp(0.0, 1.0);
      final t = square <= 0
          ? lo
          : (((userLng - a.lng) * dx + (userLat - a.lat) * dy) / square).clamp(
              lo,
              hi,
            );
      final distance = GeoUtils.haversineMeters(
        userLat,
        userLng,
        a.lat + dy * t,
        a.lng + dx * t,
      );
      matches.add((segment: i, along: start + t * length, distance: distance));
    }
    if (matches.isEmpty) return double.infinity;
    final nearest = matches.map((m) => m.distance).reduce(math.min);
    final nearby = matches
        .where((m) => m.distance <= nearest + math.min(accuracy, 8.0))
        .toList();
    nearby.sort((a, b) {
      final progress = (a.along - expected).abs().compareTo(
        (b.along - expected).abs(),
      );
      return progress != 0 ? progress : a.segment.compareTo(b.segment);
    });
    final best = nearby.first;
    _matchedMetersAlong = best.along;
    if (best.distance <= dynamicThreshold)
      currentSegmentIndex = math.max(currentSegmentIndex, best.segment);
    return best.distance;
  }

  /// Returns the remaining points of the route ahead of the user.
  List<Position> remainingPoints() {
    if (route.points.isEmpty) return [];
    if (remainingDistanceMeters <= 0) return [route.points.last];
    final i = _findSegmentForDistance(_lastKnownMetersAlong);
    return [_pointAt(_lastKnownMetersAlong), ...route.points.skip(i + 1)];
  }
}

/// Controls rerouting concurrency, exponential backoff, cooldown, and watchdog recovery.
class RerouteGate {
  final Duration baseCooldown;
  final Duration maxCooldown;
  final Duration watchdogTimeout;
  final DateTime Function() _now;

  bool _isLocked = false;
  DateTime? _lockStartTime;
  DateTime? _lastRerouteTime;
  int _consecutiveFailures = 0;

  RerouteGate({
    this.baseCooldown = const Duration(seconds: 8),
    this.maxCooldown = const Duration(seconds: 60),
    this.watchdogTimeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool get isLocked => _isLocked;
  int get consecutiveFailures => _consecutiveFailures;

  /// Returns current cooldown based on exponential backoff:
  /// baseCooldown * 2^failures, clamped to maxCooldown.
  Duration get currentCooldown {
    final factor = math.pow(2, _consecutiveFailures).toInt();
    final totalSeconds = (baseCooldown.inSeconds * factor).clamp(
      baseCooldown.inSeconds,
      maxCooldown.inSeconds,
    );
    return Duration(seconds: totalSeconds);
  }

  /// Returns the remaining cooldown duration, or Duration.zero if ready.
  Duration get remainingCooldown {
    if (_lastRerouteTime == null) return Duration.zero;
    final elapsed = _now().difference(_lastRerouteTime!);
    final total = currentCooldown;
    if (elapsed >= total) return Duration.zero;
    return total - elapsed;
  }

  /// Attempts to acquire the gate to start a reroute.
  /// If [force] is true, bypasses the time cooldown while respecting the in-flight lock.
  /// Watchdog: If locked for >= 20s, recovers automatically from stale lock.
  bool tryBegin({bool force = false}) {
    final now = _now();

    // 20s Watchdog recovery
    if (_isLocked &&
        _lockStartTime != null &&
        now.difference(_lockStartTime!) >= watchdogTimeout) {
      _isLocked = false;
      _lockStartTime = null;
    }

    if (_isLocked) return false;

    if (!force) {
      if (_lastRerouteTime != null &&
          now.difference(_lastRerouteTime!) < currentCooldown) {
        return false;
      }
    }

    _isLocked = true;
    _lockStartTime = now;
    _lastRerouteTime = now;
    return true;
  }

  /// Concludes a successful reroute: resets failures and releases lock.
  void endSuccess() {
    _isLocked = false;
    _lockStartTime = null;
    _lastRerouteTime = _now();
    _consecutiveFailures = 0;
  }

  /// Concludes a failed reroute: increments failure backoff and releases lock.
  void endFailure() {
    _isLocked = false;
    _lockStartTime = null;
    _lastRerouteTime = _now();
    _consecutiveFailures++;
  }

  /// Neutral release (e.g. for a halt): releases lock without increasing backoff.
  void releaseNeutral() {
    _isLocked = false;
    _lockStartTime = null;
    _lastRerouteTime = _now();
  }

  /// Resets the gate completely.
  void reset() {
    _isLocked = false;
    _lockStartTime = null;
    _lastRerouteTime = null;
    _consecutiveFailures = 0;
  }
}
