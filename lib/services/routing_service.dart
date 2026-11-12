import '../utils/route_road_names.dart';
import 'dart:async';

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/planned_route.dart';
import 'app_state_service.dart';
import 'weather_service.dart';
import 'location_service.dart';
import '../config/risk_config.dart';
import '../utils/geo_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RouteComputationCancelled implements Exception {
  const RouteComputationCancelled();
}

class RoutingUnavailable implements Exception {
  const RoutingUnavailable();
}

class NavigationAdmission {
  final PlannedRoute route;
  final bool requiresCaution;
  final String key;
  const NavigationAdmission(this.route, this.requiresCaution, this.key);
}

typedef DirectionsFetcher =
    Future<List<Map<String, dynamic>>> Function(
      Position origin,
      Position destination, {
      List<Position> waypoints,
      String vehicleType,
      double? headingDeg,
    });

class RoutingService extends ChangeNotifier {
  static final RoutingService instance = RoutingService._internal();
  RoutingService._internal();

  static final String _publicToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  static const double unconfirmedRoadCostPenalty = 1500.0;
  // Reject gross endpoint displacement, while allowing ordinary road snapping.
  // This bound does not certify a building entrance or walking access to it.
  static const double maxEndpointSnapMeters = 100.0;
  // Six bounded, concurrent detour requests cover both sides at three scales.
  static const int navigationDetourCandidateLimit = 6;

  bool isRoutePlanning = false;
  bool isRouteLoading = false;
  bool isLocatingGps = false;
  bool isUsingGpsFallback = false;
  String? routeErrorMessage;
  String? routeWarningMessage;

  Position? originPoint; // Will be set by GPS
  Position? destinationPoint;
  String destinationName = '';
  String originName = '';
  int _planningId = 0;

  List<PlannedRoute> routes = [];
  int selectedRouteIndex = 0;
  String selectedVehicleType = 'Sedan';

  // Analytics for Dashboard
  int routesProtectedCount = 0;
  double averageRiskReduction = 0.0;
  String? _lastCalculatedRouteSignature;

  int _sessionId = 0;
  int get planningSessionId => _sessionId;
  bool _safetyAttached = false;

  int startPlanning({
    Position? prefillDestination,
    String? name,
    Future<Position?> Function()? locate,
  }) {
    final planningId = ++_planningId;
    _sessionId++;
    _calculationId++;
    originPoint = null;
    originName = '';
    isRoutePlanning = true;
    isRouteLoading = false;
    isLocatingGps = true;
    isUsingGpsFallback = false;
    routes = [];
    selectedRouteIndex = 0;
    routeErrorMessage = null;
    routeWarningMessage = null;
    destinationPoint = prefillDestination;
    destinationName = prefillDestination == null
        ? ''
        : name ?? 'Selected Location';
    if (!_safetyAttached) {
      AppStateService.instance.mapChanges.addListener(refreshPlannerSafety);
      SimulatedWeatherService.instance.listenable.addListener(
        refreshPlannerSafety,
      );
      _safetyAttached = true;
    }
    notifyListeners();
    unawaited(
      _loadPlanningGps(
        planningId,
        locate ?? LocationService.getCurrentPosition,
      ),
    );
    return _sessionId;
  }

  Future<void> _loadPlanningGps(
    int planningId,
    Future<Position?> Function() locate,
  ) async {
    Position? point;
    try {
      point = await locate().timeout(const Duration(seconds: 18));
    } catch (_) {}
    if (planningId != _planningId || !isRoutePlanning) return;
    isLocatingGps = false;
    if (point == null || !validRoutePoint(point)) {
      routeErrorMessage =
          'GPS is unavailable. Enable precise location or choose a start point on the map.';
      notifyListeners();
      return;
    }
    originPoint = point;
    if (destinationPoint != null) {
      unawaited(calculateRoute());
    } else {
      notifyListeners();
    }
  }

  void exitPlanning({bool notify = true}) {
    _planningId++;
    _sessionId++;
    _calculationId++;
    if (_safetyAttached) {
      AppStateService.instance.mapChanges.removeListener(refreshPlannerSafety);
      SimulatedWeatherService.instance.listenable.removeListener(
        refreshPlannerSafety,
      );
      _safetyAttached = false;
    }
    originPoint = null;
    originName = '';
    isRoutePlanning = false;
    isRouteLoading = false;
    isLocatingGps = false;
    isUsingGpsFallback = false;
    destinationPoint = null;
    destinationName = '';
    routes = [];
    selectedRouteIndex = 0;
    routeErrorMessage = null;
    routeWarningMessage = null;
    if (notify) notifyListeners();
  }

  void setOrigin(Position point, String name) {
    _planningId++; // Ignore GPS results from before the manual selection.
    originPoint = point;
    originName = name;
    isLocatingGps = false;
    isUsingGpsFallback = false;
    routeErrorMessage = null;
    if (destinationPoint != null) {
      calculateRoute();
    } else {
      notifyListeners();
    }
  }

  void clearDestination() {
    _calculationId++;
    destinationPoint = null;
    destinationName = '';
    routes = [];
    selectedRouteIndex = 0;
    isRouteLoading = false;
    routeErrorMessage = null;
    routeWarningMessage = null;
    notifyListeners();
  }

  void setDestination(
    Position point,
    String name, {
    DirectionsFetcher? directionsFetcher,
  }) {
    destinationPoint = point;
    destinationName = name;
    calculateRoute(directionsFetcher: directionsFetcher);
  }

  void selectRoute(int index) {
    if (index < 0 || index >= routes.length) return;
    selectedRouteIndex = index;
    notifyListeners();
  }

  void setVehicleType(String type) {
    selectedVehicleType = (type == 'Truck') ? 'Sedan' : type;
    if (destinationPoint != null) {
      calculateRoute();
    } else {
      notifyListeners();
    }
  }

  int _calculationId = 0;

  /// Pure routing calculation method that returns a [List<PlannedRoute>] without
  /// mutating shared planner state (originPoint, destinationPoint, routes, selectedRouteIndex).
  Future<List<PlannedRoute>> computeRoutes({
    required Position origin,
    required Position destination,
    String vehicleType = 'Sedan',
    double? headingDegrees,
    Set<String> avoidRoadIds = const {},
    bool allowDetourGeneration = true,
    int maxDetourCandidates = 6,
    List<dynamic>? roadsOverride,
    WeatherState? weatherStateOverride,
    DirectionsFetcher? directionsFetcher,
    bool Function()? isCurrent,
    Duration timeBudget = const Duration(seconds: 18),
  }) async {
    if (!validRoutePoint(origin) || !validRoutePoint(destination))
      throw const RoutingUnavailable();
    final roads = List<dynamic>.of(
      roadsOverride ?? AppStateService.instance.roads,
    );
    final weatherState =
        weatherStateOverride ?? SimulatedWeatherService.instance.currentState;
    final provider = directionsFetcher ?? _fetchDirectionsWithWaypoints;
    final watch = Stopwatch()..start();
    void checkCurrent() {
      if (isCurrent != null && !isCurrent())
        throw const RouteComputationCancelled();
      if (watch.elapsed >= timeBudget)
        throw TimeoutException('Route computation budget reached.');
    }

    Future<List<Map<String, dynamic>>> fetcher(
      Position from,
      Position to, {
      List<Position> waypoints = const [],
      String vehicleType = 'Sedan',
      double? headingDeg,
    }) async {
      checkCurrent();
      final raw = await provider(
        from,
        to,
        waypoints: waypoints,
        vehicleType: vehicleType,
        headingDeg: headingDeg,
      ).timeout(timeBudget - watch.elapsed);
      checkCurrent();
      final valid = <Map<String, dynamic>>[];
      for (final row in raw) {
        try {
          final distance = row['distance'],
              duration = row['duration'],
              geometry = row['geometry'];
          if (distance is! num ||
              !distance.isFinite ||
              distance < 0 ||
              duration is! num ||
              !duration.isFinite ||
              duration < 0 ||
              geometry is! String ||
              geometry.isEmpty ||
              geometry.length > 200000)
            continue;
          final points = _decodePolyline(geometry);
          if (points.length < 2 ||
              !points.every(validRoutePoint) ||
              !points.any(
                (p) => p.lat != points.first.lat || p.lng != points.first.lng,
              ))
            continue;
          final originSnap = GeoUtils.haversineMeters(
            from.lat.toDouble(),
            from.lng.toDouble(),
            points.first.lat.toDouble(),
            points.first.lng.toDouble(),
          );
          final destinationSnap = GeoUtils.haversineMeters(
            to.lat.toDouble(),
            to.lng.toDouble(),
            points.last.lat.toDouble(),
            points.last.lng.toDouble(),
          );
          if (originSnap > maxEndpointSnapMeters ||
              destinationSnap > maxEndpointSnapMeters)
            continue;
          valid.add(row);
        } catch (_) {}
      }
      if (raw.isNotEmpty && valid.isEmpty) throw const RoutingUnavailable();
      return valid;
    }

    // ── Step 1: Ask Mapbox for ALL alternative routes in one call ──────────
    var allMapboxRoutes = await fetcher(
      origin,
      destination,
      vehicleType: vehicleType,
      headingDeg: headingDegrees,
    );

    // A valid road network may have no route in the imposed departure
    // direction. Retry once without that constraint, within the same budget.
    if (allMapboxRoutes.isEmpty && headingDegrees != null) {
      allMapboxRoutes = await fetcher(
        origin,
        destination,
        vehicleType: vehicleType,
      );
    }
    if (allMapboxRoutes.isEmpty) {
      return [];
    }

    // ── Step 2: Evaluate every route's safety against Firestore flood data ─
    List<Map<String, dynamic>> rawEvaluated = [];
    String? highestRiskSegmentToAvoidId;
    double globalMaxRisk = 0.0;

    for (int i = 0; i < allMapboxRoutes.length; i++) {
      final r = allMapboxRoutes[i];
      final pts = _decodePolyline(r['geometry'] as String);
      final safety = evaluateRouteSafety(
        pts,
        roads,
        vehicleType,
        weatherState: weatherState,
      );
      final steps = _parseSteps(r);

      double distMeters = (r['distance'] as num).toDouble();
      double distMiles = double.parse(
        (distMeters / 1609.34).toStringAsFixed(1),
      );

      double avgRisk = safety['averageRisk'] as double;
      double maxRisk = safety['maxRisk'] as double;
      double totalRisk = safety['totalRisk'] as double;
      int unconfirmedCount = (safety['unconfirmedCount'] as int?) ?? 0;

      // The Approved Formula
      double routeCost =
          distMeters +
          (avgRisk * 10.0) +
          (maxRisk * 50.0) +
          (unconfirmedCount * unconfirmedRoadCostPenalty);

      // Safety Score (100 = safe, 0 = catastrophic)
      int safetyScore = (100 - (avgRisk * 0.4) - (maxRisk * 0.6)).round().clamp(
        0,
        100,
      );

      // If Critical, force safety score lower and spike the cost
      if (safety['status'] == 'critical') {
        safetyScore = safetyScore.clamp(0, 20); // Severely limit safety score
        routeCost += 50000.0; // Massive penalty
      }

      // Avoid road IDs penalty (+20000 per avoided road crossed)
      if (avoidRoadIds.isNotEmpty) {
        final crossed = safety['crossedRoads'] as List<Map<String, dynamic>>;
        int avoidCount = crossed
            .where((c) => avoidRoadIds.contains(c['id']))
            .length;
        if (avoidCount > 0) {
          routeCost += avoidCount * 20000.0;
        }
      }

      if (maxRisk > globalMaxRisk && safety['highestRiskSegmentId'] != null) {
        globalMaxRisk = maxRisk;
        highestRiskSegmentToAvoidId = safety['highestRiskSegmentId'] as String?;
      }

      rawEvaluated.add({
        'pts': pts,
        'roadNames': roadNamesFromDirections(r),
        'durationMin': (r['duration'] / 60).round(),
        'durationSeconds': (r['duration'] as num).toDouble(),
        'distanceMiles': distMiles,
        'distanceMeters': distMeters,
        'summary': i == 0 ? 'Fastest Route' : 'Alternative ${i + 1}',
        'hazardAlerts': safety['hazardAlerts'],
        'crossedRoads': safety['crossedRoads'],
        'safetyStatus': safety['status'],
        'safetyScore': safetyScore,
        'routeCost': routeCost,
        'totalRisk': totalRisk,
        'steps': steps,
        'isBlocked': safety['isBlocked'],
      });
    }

    // ── Step 2.5: Dynamic Detour Generator (Perpendicular Corridor Diversion) ──
    // Plain routes run first. Detours only happen if NO route from the first Mapbox call is non-critical,
    // OR (avoidRoadIds is non-empty AND every non-critical route still crosses an avoided road).
    final nonCriticalRoutes = rawEvaluated
        .where((r) => r['safetyStatus'] != 'critical')
        .toList();

    bool needsDetour =
        allowDetourGeneration &&
        rawEvaluated.isNotEmpty &&
        (nonCriticalRoutes.isEmpty ||
            (avoidRoadIds.isNotEmpty &&
                nonCriticalRoutes.every(
                  (r) => (r['crossedRoads'] as List<Map<String, dynamic>>).any(
                    (c) => avoidRoadIds.contains(c['id']),
                  ),
                )));

    int cleanDetourCount = 0;
    int partialDetourCount = 0;
    int duplicateDetourCount = 0;

    if (needsDetour) {
      List<Position> criticalCorridorPoints = [];

      for (final road in roads) {
        if (road.geometry == null) continue;
        final currentRisk = (road.riskScore as num).toDouble();
        final effStatus = road.getEffectiveStatus(weatherState);

        if (currentRisk >= 80.0 ||
            effStatus == 'not_passable' ||
            road.status == 'not_passable' ||
            avoidRoadIds.contains(road.id)) {
          final geoPts = GeoUtils.extractPoints(road.geometry);
          if (geoPts.length >= 2) {
            final roadPositions = geoPts
                .map((p) => Position(p.lng, p.lat))
                .toList();
            bool isCrossed = rawEvaluated.any(
              (r) => doesRouteCrossGeometry(
                r['pts'] as List<Position>,
                road.geometry,
                thresholdMeters: RiskConfig.roadCrossingBufferMeters,
              ),
            );
            if (isCrossed) {
              criticalCorridorPoints.addAll(roadPositions);
            }
          }
        }
      }

      if (criticalCorridorPoints.isEmpty &&
          highestRiskSegmentToAvoidId != null) {
        final badRoad = roads.cast<dynamic>().firstWhere(
          (r) => r.id == highestRiskSegmentToAvoidId,
          orElse: () => null,
        );
        if (badRoad != null && badRoad.geometry != null) {
          final pts = GeoUtils.extractPoints(badRoad.geometry);
          if (pts.isNotEmpty) {
            criticalCorridorPoints.addAll(
              pts.map((p) => Position(p.lng, p.lat)),
            );
          }
        }
      }

      if (criticalCorridorPoints.isEmpty) {
        criticalCorridorPoints = [
          Position(
            (origin.lng.toDouble() + destination.lng.toDouble()) / 2,
            (origin.lat.toDouble() + destination.lat.toDouble()) / 2,
          ),
        ];
      }

      double oLng = origin.lng.toDouble();
      double oLat = origin.lat.toDouble();
      double dLng = destination.lng.toDouble();
      double dLat = destination.lat.toDouble();

      double mainDx = dLng - oLng;
      double mainDy = dLat - oLat;
      double mainLen = math.sqrt(mainDx * mainDx + mainDy * mainDy);
      if (mainLen == 0) mainLen = 0.001;

      // Normal unit vectors perpendicular to travel direction (Left & Right)
      double normX = -mainDy / mainLen;
      double normY = mainDx / mainLen;

      final Set<String> seenFingerprints = {};
      for (final existing in rawEvaluated) {
        seenFingerprints.add(
          _routeFingerprint(existing['pts'] as List<Position>),
        );
      }

      Position startFloodPt = criticalCorridorPoints.first;
      Position midFloodPt =
          criticalCorridorPoints[criticalCorridorPoints.length ~/ 2];
      Position endFloodPt = criticalCorridorPoints.last;

      // Progressive perpendicular offsets (~350m, ~700m, ~1100m)
      final offsetDistances = [0.0035, 0.0070, 0.0110];
      List<List<Position>> waypointSets = [];
      final corridorWaypointSets = <List<Position>>[];

      for (final dist in offsetDistances) {
        // A single via-point can return through the closure on its second
        // leg. Reserve the middle scale for two points spanning the trip,
        // while keeping near and wide single-point searches on both sides.
        // This changes candidate shapes, not the request cap or time budget.
        final spansTrip = dist == offsetDistances[1];
        final flankStart = spansTrip ? origin : midFloodPt;
        // Left flank
        waypointSets.add([
          Position(
            flankStart.lng.toDouble() + (normX * dist),
            flankStart.lat.toDouble() + (normY * dist),
          ),
          if (spansTrip) Position(dLng + (normX * dist), dLat + (normY * dist)),
        ]);
        // Right flank
        waypointSets.add([
          Position(
            flankStart.lng.toDouble() - (normX * dist),
            flankStart.lat.toDouble() - (normY * dist),
          ),
          if (spansTrip) Position(dLng - (normX * dist), dLat - (normY * dist)),
        ]);
        // Additional flood-edge shapes remain available to larger caller
        // budgets; the six navigation candidates above cover both sides.
        // Left dual corridor flank
        corridorWaypointSets.add([
          Position(
            startFloodPt.lng.toDouble() + (normX * dist),
            startFloodPt.lat.toDouble() + (normY * dist),
          ),
          Position(
            endFloodPt.lng.toDouble() + (normX * dist),
            endFloodPt.lat.toDouble() + (normY * dist),
          ),
        ]);
        // Right dual corridor flank
        corridorWaypointSets.add([
          Position(
            startFloodPt.lng.toDouble() - (normX * dist),
            startFloodPt.lat.toDouble() - (normY * dist),
          ),
          Position(
            endFloodPt.lng.toDouble() - (normX * dist),
            endFloodPt.lat.toDouble() - (normY * dist),
          ),
        ]);
      }

      waypointSets.addAll(corridorWaypointSets);
      final capped = waypointSets.take(maxDetourCandidates).toList();
      List<Map<String, dynamic>> allDetours = [];
      var detourFailures = 0;
      final results = await Future.wait(
        capped.map(
          (wps) =>
              fetcher(
                origin,
                destination,
                waypoints: wps,
                vehicleType: vehicleType,
                // A closure may require turning back. Keeping the initial
                // forward bearing here can force every detour through the
                // closure before reaching its waypoint. The provider still
                // applies road direction/turn restrictions; every returned
                // route is rechecked against the full closure set below.
                headingDeg: null,
              ).catchError((Object error) {
                if (error is RouteComputationCancelled) throw error;
                detourFailures++;
                return <Map<String, dynamic>>[];
              }),
        ),
      );
      checkCurrent();
      if (capped.isNotEmpty && detourFailures == capped.length)
        throw const RoutingUnavailable();
      for (final detours in results) {
        allDetours.addAll(detours);
      }

      // ── Cross-Hazard Validation: Build list of ALL hazardous road geometries ──
      final List<Map<String, dynamic>> allHazardousRoadGeometries = [];
      for (final road in roads) {
        if (road.geometry == null) continue;
        final currentRisk = (road.riskScore as num).toDouble();
        final effStatus = road.getEffectiveStatus(weatherState);
        if (currentRisk >= 60.0 ||
            effStatus == 'not_passable' ||
            road.status == 'not_passable' ||
            avoidRoadIds.contains(road.id)) {
          final geoPts = GeoUtils.extractPoints(road.geometry);
          if (geoPts.length >= 2) {
            allHazardousRoadGeometries.add({
              'geometry': road.geometry,
              'name': road.name,
              'positions': geoPts.map((p) => Position(p.lng, p.lat)).toList(),
              'risk': currentRisk,
            });
          }
        }
      }
      debugPrint(
        '[CrossHazard] Validating ${allDetours.length} detour candidates against ${allHazardousRoadGeometries.length} hazardous roads',
      );

      for (int i = 0; i < allDetours.length; i++) {
        final r = allDetours[i];
        final pts = _decodePolyline(r['geometry'] as String);

        final fp = _routeFingerprint(pts);
        if (seenFingerprints.contains(fp)) {
          duplicateDetourCount++;
          continue;
        }
        seenFingerprints.add(fp);

        final safety = evaluateRouteSafety(
          pts,
          roads,
          vehicleType,
          weatherState: weatherState,
        );
        final steps = _parseSteps(r);

        double distMeters = (r['distance'] as num).toDouble();
        double distMiles = double.parse(
          (distMeters / 1609.34).toStringAsFixed(1),
        );
        double avgRisk = safety['averageRisk'] as double;
        double maxRisk = safety['maxRisk'] as double;
        double totalRisk = safety['totalRisk'] as double;
        int unconfirmedCount = (safety['unconfirmedCount'] as int?) ?? 0;
        double routeCost =
            distMeters +
            (avgRisk * 10.0) +
            (maxRisk * 50.0) +
            (unconfirmedCount * unconfirmedRoadCostPenalty);
        int safetyScore = (100 - (avgRisk * 0.4) - (maxRisk * 0.6))
            .round()
            .clamp(0, 100);

        if (safety['status'] == 'critical') {
          safetyScore = safetyScore.clamp(0, 20);
          routeCost += 50000.0;
        }

        // Avoid road IDs penalty
        if (avoidRoadIds.isNotEmpty) {
          final crossed = safety['crossedRoads'] as List<Map<String, dynamic>>;
          int avoidCount = crossed
              .where((c) => avoidRoadIds.contains(c['id']))
              .length;
          if (avoidCount > 0) {
            routeCost += avoidCount * 20000.0;
          }
        }

        // ── Cross-Hazard Validation Pass ──
        int crossedHazardCount = 0;
        List<String> crossedHazardNames = [];
        for (final hazard in allHazardousRoadGeometries) {
          if (doesRouteCrossGeometry(
            pts,
            hazard['geometry'] as Map<String, dynamic>?,
            thresholdMeters: RiskConfig.roadCrossingBufferMeters,
          )) {
            crossedHazardCount++;
            crossedHazardNames.add(hazard['name'] as String);
          }
        }

        String detourStatus = safety['status'] as String;
        if (crossedHazardCount > 0 && detourStatus == 'safe') {
          detourStatus = 'partial';
          safetyScore = safetyScore.clamp(0, 70);
          routeCost += crossedHazardCount * 5000.0;
          partialDetourCount++;
          debugPrint(
            '[CrossHazard] Detour $i crosses ${crossedHazardNames.join(", ")} — downgraded to partial',
          );
        } else if (crossedHazardCount == 0 && detourStatus == 'safe') {
          cleanDetourCount++;
          debugPrint(
            '[CrossHazard] ✓ Detour $i is CLEAN — avoids all ${allHazardousRoadGeometries.length} hazard zones',
          );
        }

        rawEvaluated.add({
          'pts': pts,
          'roadNames': roadNamesFromDirections(r),
          'durationMin': (r['duration'] / 60).round(),
          'durationSeconds': (r['duration'] as num).toDouble(),
          'distanceMiles': distMiles,
          'distanceMeters': distMeters,
          'summary': crossedHazardCount == 0
              ? 'Dynamic Safe Detour'
              : 'Dynamic Partial Detour',
          'hazardAlerts': safety['hazardAlerts'],
          'crossedRoads': safety['crossedRoads'],
          'safetyStatus': detourStatus,
          'safetyScore': safetyScore,
          'routeCost': routeCost,
          'totalRisk': totalRisk,
          'steps': steps,
          'isBlocked': safety['isBlocked'],
        });
      }

      debugPrint(
        '[Detour Engine] Detour generation completed: evaluated ${allDetours.length} candidates '
        '($cleanDetourCount clean safe, $partialDetourCount partial hazard, $duplicateDetourCount duplicates skipped)',
      );

      // A failed candidate may have been the only clear alternative. Preserve
      // the navigation failure/backoff path instead of declaring a completed
      // no-clear-route search. A separately checked unblocked result remains
      // usable even if another candidate failed.
      if (detourFailures > 0 &&
          rawEvaluated.every((route) => route['isBlocked'] == true)) {
        throw const RoutingUnavailable();
      }
    }

    if (rawEvaluated.isEmpty) {
      return [];
    }

    // ── Step 3: Find Baseline Risk and Sort BY ROUTE COST ASCENDING ──────────────
    double baselineRisk = 0.0;
    for (var r in rawEvaluated) {
      if ((r['totalRisk'] as double) > baselineRisk) {
        baselineRisk = r['totalRisk'] as double;
      }
    }

    rawEvaluated.sort(
      (a, b) =>
          (a['isBlocked'] == true ? 1 : 0).compareTo(
                b['isBlocked'] == true ? 1 : 0,
              ) !=
              0
          ? (a['isBlocked'] == true ? 1 : 0).compareTo(
              b['isBlocked'] == true ? 1 : 0,
            )
          : (a['routeCost'] as double).compareTo(b['routeCost'] as double),
    );

    // ── Step 4: Build Explanations & Convert to PlannedRoute ──────────
    final List<PlannedRoute> evaluated = [];
    var baselineRoute = rawEvaluated.firstWhere(
      (x) => (x['totalRisk'] as double) == baselineRisk,
      orElse: () => rawEvaluated[0],
    );

    final Set<String> baselineHazardSet = Set<String>.from(
      baselineRoute['hazardAlerts'] as List<String>,
    );

    for (int i = 0; i < rawEvaluated.length; i++) {
      final current = rawEvaluated[i];
      String newSummary = current['summary'] as String;

      if (i == 0) {
        if (current['safetyStatus'] == 'critical') {
          newSummary = 'Caution: Flooded Segment Ahead';
        } else if (current['summary'] == 'Dynamic Safe Detour') {
          newSummary = 'Safe Detour (Auto-Generated)';
        } else if (current['summary'] == 'Dynamic Partial Detour') {
          newSummary = 'Detour (Partial Risk Remains)';
        } else if (current['safetyStatus'] == 'unverified_risk') {
          newSummary = 'Best Available (Unverified)';
        } else {
          newSummary = (current['safetyScore'] as int) >= 90
              ? 'Safest Route'
              : (current['safetyScore'] as int) >= 50
              ? 'Least Risky Route'
              : 'Best Available Route';
        }
      } else {
        if (current['summary'] == 'Dynamic Safe Detour') {
          newSummary = 'Alternative Detour ${i + 1}';
        } else if (current['summary'] == 'Dynamic Partial Detour') {
          newSummary = 'Alt. Detour ${i + 1} (Partial)';
        } else {
          newSummary = 'Alternative ${i + 1}';
        }
      }

      List<Map<String, dynamic>> crossed =
          current['crossedRoads'] as List<Map<String, dynamic>>;
      List<String> routeExplanations = [];

      if (i == 0) {
        if (crossed.isEmpty && baselineRisk > 0) {
          List<Map<String, dynamic>> baselineCrossed =
              baselineRoute['crossedRoads'] as List<Map<String, dynamic>>;
          for (var badRoad in baselineCrossed) {
            routeExplanations.add(
              'Avoids ${badRoad['name']} (${badRoad['cat']})',
            );
          }
        } else {
          for (var road in crossed) {
            routeExplanations.add('Crosses ${road['name']} (${road['cat']})');
          }
        }
      } else {
        for (var road in crossed) {
          routeExplanations.add('Crosses ${road['name']} (${road['cat']})');
        }
      }

      routeExplanations = routeExplanations.toSet().toList();

      int getSeverityWeight(String exp) {
        if (exp.contains('Critical')) return 4;
        if (exp.contains('Warning')) return 3;
        if (exp.contains('Watch')) return 2;
        if (exp.startsWith('Avoids')) return 1;
        return 0;
      }

      routeExplanations.sort(
        (a, b) => getSeverityWeight(b).compareTo(getSeverityWeight(a)),
      );

      double rRisk = current['totalRisk'] as double;
      int? riskReduction;
      if (baselineRisk > 0 && rRisk < baselineRisk) {
        riskReduction = (((baselineRisk - rRisk) / baselineRisk) * 100).round();
      } else if (baselineRisk == 0 && rRisk == 0) {
        riskReduction = 0;
      }

      int baselineDuration = baselineRoute['durationMin'] as int;
      int currentDuration = current['durationMin'] as int;
      int timePenalty = currentDuration - baselineDuration;
      if (timePenalty < 0) timePenalty = 0;

      final List<String> currentHazards =
          current['hazardAlerts'] as List<String>;
      final int realAvoided = baselineHazardSet
          .where((road) => !currentHazards.contains(road))
          .length;

      evaluated.add(
        PlannedRoute(
          points: current['pts'] as List<Position>,
          vehicleType: vehicleType,
          requestedDestination: destination,
          durationMin: currentDuration,
          durationSeconds: current['durationSeconds'] as double?,
          distanceMiles: current['distanceMiles'] as double,
          distanceMeters: current['distanceMeters'] as double,
          requestedAvoidRoadIds: Set<String>.unmodifiable(avoidRoadIds),
          summary: newSummary,
          roadNames: current['roadNames'] as List<String>? ?? const [],
          hazardAlerts: currentHazards,
          routeExplanations: routeExplanations,
          safetyStatus: current['safetyStatus'] as String,
          safetyScore: current['safetyScore'] as int,
          routeCost: current['routeCost'] as double,
          totalRisk: rRisk,
          riskReductionPercentage: riskReduction,
          timePenaltyMin: timePenalty,
          steps: current['steps'] as List<RouteStep>,
          realAvoidedCount: realAvoided,
          isBlocked: current['isBlocked'] as bool? ?? false,
          unverifiedRoadCount: crossed
              .where((road) => road['cat'] == 'Unverified Advisory')
              .length,
        ),
      );
    }

    return evaluated;
  }

  static bool validRoutePoint(Position p) =>
      p.lat.isFinite &&
      p.lng.isFinite &&
      p.lat.abs() <= 90 &&
      p.lng.abs() <= 180;

  static double distanceToRoute(Position point, List<Position> route) {
    if (!validRoutePoint(point) || route.length < 2) return double.infinity;
    var best = double.infinity;
    for (var i = 1; i < route.length; i++) {
      if (!validRoutePoint(route[i - 1]) || !validRoutePoint(route[i]))
        continue;
      final distance = GeoUtils.pointToSegmentDistanceMeters(
        point.lng.toDouble(),
        point.lat.toDouble(),
        route[i - 1].lng.toDouble(),
        route[i - 1].lat.toDouble(),
        route[i].lng.toDouble(),
        route[i].lat.toDouble(),
      );
      if (distance < best) best = distance;
    }
    return best;
  }

  static int compareRoutes(PlannedRoute a, PlannedRoute b) {
    final blocked = (a.isBlocked ? 1 : 0).compareTo(b.isBlocked ? 1 : 0);
    return blocked != 0 ? blocked : a.routeCost.compareTo(b.routeCost);
  }

  PlannedRoute refreshRoute(
    PlannedRoute route, {
    List<dynamic>? roads,
    WeatherState? weather,
    String? vehicleType,
    // Active navigation may evaluate only the path still ahead. This never
    // changes the returned route's geometry, steps or destination.
    List<Position>? evaluationPoints,
  }) {
    final safetyPoints = evaluationPoints ?? route.points;
    if (route.points.length < 2 ||
        !route.points.every(validRoutePoint) ||
        safetyPoints.isEmpty ||
        !safetyPoints.every(validRoutePoint))
      return route.copyWith(
        isBlocked: true,
        safetyStatus: 'critical',
        summary: 'Route unavailable',
        clearComparison: true,
      );
    final safety = evaluateRouteSafety(
      safetyPoints,
      roads ?? AppStateService.instance.roads,
      vehicleType ?? route.vehicleType ?? selectedVehicleType,
      weatherState: weather ?? SimulatedWeatherService.instance.currentState,
    );
    final average = safety['averageRisk'] as double,
        maxRisk = safety['maxRisk'] as double;
    final rawScore = (100 - average * 0.4 - maxRisk * 0.6).round().clamp(
      0,
      100,
    );
    final score = safety['status'] == 'critical'
        ? rawScore.clamp(0, 20)
        : rawScore;
    final outside = safetyPoints.any(
      (p) => !GeoUtils.isInsideStudyArea(
        p.lat.toDouble(),
        p.lng.toDouble(),
        bufferMeters: 50,
      ),
    );
    final unverified = (safety['unconfirmedCount'] as int?) ?? 0,
        status = safety['status'] as String,
        blocked = safety['isBlocked'] as bool;
    final alerts = List<String>.from(safety['hazardAlerts'] as List);
    if (outside == route.outsideStudyArea &&
        status == route.safetyStatus &&
        blocked == route.isBlocked &&
        unverified == route.unverifiedRoadCount &&
        safety['totalRisk'] == route.totalRisk &&
        listEquals(alerts, route.hazardAlerts) &&
        score == route.safetyScore)
      return route;
    final crossed = List<Map<String, dynamic>>.from(
      safety['crossedRoads'] as List,
    );
    return route.copyWith(
      outsideStudyArea: outside,
      safetyStatus: status,
      isBlocked: blocked,
      safetyScore: status == 'critical' ? score.clamp(0, 20) : score,
      totalRisk: safety['totalRisk'] as double,
      unverifiedRoadCount: unverified,
      hazardAlerts: alerts,
      routeCost:
          (route.distanceMeters ?? route.distanceMiles * 1609.34) +
          average * 10 +
          maxRisk * 50 +
          unverified * unconfirmedRoadCostPenalty +
          crossed
                  .where((r) => route.requestedAvoidRoadIds.contains(r['id']))
                  .length *
              20000 +
          (status == 'critical' ? 50000 : 0),
      summary: blocked
          ? 'Route closed'
          : unverified > 0
          ? 'Road conditions unconfirmed'
          : status == 'safe'
          ? 'Clear of known flood reports'
          : 'Route requires caution',
      routeExplanations: crossed
          .map((r) => 'Crosses ${r['name']} (${r['cat']})')
          .toList(),
      clearComparison: true,
    );
  }

  NavigationAdmission navigationAdmission(
    PlannedRoute route, {
    List<dynamic>? roads,
    WeatherState? weather,
    bool? liveDataUnavailable,
  }) {
    final current = refreshRoute(route, roads: roads, weather: weather);
    final effectiveWeather =
        weather ?? SimulatedWeatherService.instance.currentState;
    final unavailable =
        liveDataUnavailable ??
        (AppStateService.instance.requiresLiveDataWarning ||
            SimulatedWeatherService.instance.isDataStale);
    final caution = unavailable || current.needsCaution;
    final key = jsonEncode([
      current.isBlocked,
      current.safetyStatus,
      current.safetyScore,
      current.unverifiedRoadCount,
      current.outsideStudyArea,
      current.hazardAlerts,
      effectiveWeather.name,
      unavailable,
    ]);
    return NavigationAdmission(current, caution, key);
  }

  void refreshPlannerSafety() {
    if (!isRoutePlanning || routes.isEmpty) return;
    final selected =
        selectedRouteIndex >= 0 && selectedRouteIndex < routes.length
        ? routes[selectedRouteIndex].points
        : null;
    routes = routes.map((r) => refreshRoute(r)).toList()..sort(compareRoutes);
    final previous = routes.indexWhere((r) => identical(r.points, selected));
    selectedRouteIndex = previous >= 0 && !routes[previous].isBlocked
        ? previous
        : 0;
    final messages = buildRouteMessages(
      routes,
      SimulatedWeatherService.instance.currentState,
      usingFallback: false,
    );
    routeErrorMessage = messages.error;
    routeWarningMessage = messages.warning;
    if (AppStateService.instance.requiresLiveDataWarning ||
        SimulatedWeatherService.instance.isDataStale)
      routeWarningMessage = [
        if (routeWarningMessage != null) routeWarningMessage!,
        'Live road or weather data is unavailable or outdated. Confirm current conditions before travel.',
      ].join(' ');
    notifyListeners();
  }

  /// Stateful wrapper around [computeRoutes] that updates the Planner UI state.
  Future<void> calculateRoute({
    double? headingDeg,
    DirectionsFetcher? directionsFetcher,
  }) async {
    if (originPoint == null || !validRoutePoint(originPoint!)) {
      _calculationId++;
      routes.clear();
      isRouteLoading = false;
      routeErrorMessage =
          'Waiting for a real GPS location. Enable precise location or choose a start point on the map.';
      notifyListeners();
      return;
    }
    if (destinationPoint == null || !validRoutePoint(destinationPoint!)) {
      _calculationId++;
      routes = [];
      selectedRouteIndex = 0;
      isRouteLoading = false;
      notifyListeners();
      return;
    }

    if (GeoUtils.haversineMeters(
          originPoint!.lat.toDouble(),
          originPoint!.lng.toDouble(),
          destinationPoint!.lat.toDouble(),
          destinationPoint!.lng.toDouble(),
        ) <
        1) {
      _calculationId++;
      routes = [];
      selectedRouteIndex = 0;
      isRouteLoading = false;
      routeErrorMessage = 'Choose different start and destination points.';
      notifyListeners();
      return;
    }
    final requestedName = destinationName;
    final routeStopwatch = Stopwatch()..start();

    _calculationId++;
    final currentCalcId = _calculationId;

    isRouteLoading = true;
    routes = [];
    selectedRouteIndex = 0;
    routeErrorMessage = null;
    routeWarningMessage = null;
    notifyListeners();

    try {
      final computed = await computeRoutes(
        origin: originPoint!,
        destination: destinationPoint!,
        vehicleType: selectedVehicleType,
        headingDegrees: headingDeg,
        allowDetourGeneration: true,
        directionsFetcher: directionsFetcher,
        isCurrent: () => currentCalcId == _calculationId,
      );

      if (currentCalcId != _calculationId) return; // Prevent race conditions

      if (computed.isEmpty) {
        routes.clear();
        routeErrorMessage = 'No routes found. Try a different destination.';
        return;
      }

      routes =
          computed
              .map(
                (r) => refreshRoute(r.copyWith(destinationName: requestedName)),
              )
              .toList()
            ..sort(compareRoutes);
      selectedRouteIndex = 0;

      final weatherState = SimulatedWeatherService.instance.currentState;
      final messages = buildRouteMessages(
        routes,
        weatherState,
        usingFallback: isUsingGpsFallback,
      );
      routeErrorMessage = messages.error;
      routeWarningMessage = messages.warning;
      if (AppStateService.instance.requiresLiveDataWarning ||
          SimulatedWeatherService.instance.isDataStale) {
        routeWarningMessage = [
          if (messages.warning != null) messages.warning!,
          'Live road or weather data is unavailable or outdated. This route cannot be confirmed safe.',
        ].join(' ');
      }

      routeStopwatch.stop();
      if (routes.isNotEmpty) {
        final topRoute = routes.first;

        // Track analytics
        final signature =
            '${originPoint?.lat},${originPoint?.lng}|${destinationPoint?.lat},${destinationPoint?.lng}';
        if (signature != _lastCalculatedRouteSignature &&
            topRoute.riskReductionPercentage != null &&
            topRoute.riskReductionPercentage! > 0) {
          _lastCalculatedRouteSignature = signature;
          routesProtectedCount++;
          double oldTotal = averageRiskReduction * (routesProtectedCount - 1);
          averageRiskReduction =
              (oldTotal + topRoute.riskReductionPercentage!) /
              routesProtectedCount;

          try {
            FirebaseFirestore.instance
                .collection('analytics')
                .doc('routing')
                .set({
                  'routesProtectedCount': FieldValue.increment(1),
                  'totalRiskReduction': FieldValue.increment(
                    topRoute.riskReductionPercentage!,
                  ),
                }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Failed to sync analytics: $e');
          }
        }

        final appState = AppStateService.instance;
        debugPrint('\n--- ROUTE ANALYSIS ---');
        debugPrint('Routes Evaluated: ${routes.length}');
        debugPrint('Road Segments: ${appState.roads.length}');
        debugPrint('Execution: ${routeStopwatch.elapsedMilliseconds} ms');
        debugPrint('Risk Reduction: ${topRoute.riskReductionPercentage ?? 0}%');
        debugPrint('Travel Penalty: +${topRoute.timePenaltyMin} min\n');
      }
    } catch (e) {
      if (e is! RouteComputationCancelled)
        debugPrint(
          '[RoutingService] Route calculation failed (${e.runtimeType}).',
        );
      if (currentCalcId == _calculationId) {
        routeErrorMessage = 'Failed to calculate route. Check your connection.';
      }
    } finally {
      if (currentCalcId == _calculationId) {
        isRouteLoading = false;
        notifyListeners();
      }
    }
  }

  /// Fetches routes with optional intermediate waypoints.
  Future<List<Map<String, dynamic>>> _fetchDirectionsWithWaypoints(
    Position origin,
    Position dest, {
    List<Position> waypoints = const [],
    String vehicleType = 'Sedan',
    double? headingDeg,
  }) async {
    String profile = 'driving';
    if (vehicleType == 'Walking') {
      profile = 'walking';
    } else if (vehicleType == 'Motorcycle') {
      // Motorcycles in the Philippines follow road traffic rules (not bicycle paths)
      profile = 'driving';
    }

    final coordCount = waypoints.length + 2;
    String coords = '${origin.lng},${origin.lat};';
    for (final wp in waypoints) {
      coords += '${wp.lng},${wp.lat};';
    }
    coords += '${dest.lng},${dest.lat}';

    final sb = StringBuffer(
      'https://api.mapbox.com/directions/v5/mapbox/$profile/$coords'
      '?alternatives=true&geometries=polyline&overview=full&steps=true',
    );

    // #2: treat intermediate points as silent via-points -> single leg
    if (waypoints.isNotEmpty) {
      sb.write('&waypoints=0;${coordCount - 1}');
    }

    // #6: bearing only for the origin; empty entries for the rest
    if (headingDeg != null && headingDeg >= 0) {
      final entries = [
        '${headingDeg.round()},45',
        ...List.filled(coordCount - 1, ''),
      ];
      sb.write('&bearings=${entries.join(';')}');
    }
    sb.write('&access_token=$_publicToken');

    try {
      final response = await http
          .get(Uri.parse(sb.toString()))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw const RoutingUnavailable();
      final data = json.decode(response.body);
      if (data is! Map || data['routes'] is! List) {
        if (data is Map && data['code'] == 'NoRoute') return [];
        throw const RoutingUnavailable();
      }
      return (data['routes'] as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (_) {
      throw const RoutingUnavailable();
    }
  }

  List<RouteStep> _parseSteps(Map<String, dynamic> routeData) {
    final result = <RouteStep>[], legs = routeData['legs'];
    if (legs is! List) return result;
    for (var li = 0; li < legs.length; li++) {
      final leg = legs[li];
      if (leg is! Map || leg['steps'] is! List) continue;
      for (final step in leg['steps'] as List) {
        if (step is! Map || step['maneuver'] is! Map) continue;
        final m = step['maneuver'] as Map,
            loc = m['location'],
            distance = step['distance'];
        if (loc is! List ||
            loc.length < 2 ||
            loc[0] is! num ||
            loc[1] is! num ||
            distance is! num ||
            !distance.isFinite ||
            distance < 0)
          continue;
        final point = Position(loc[0], loc[1]);
        if (!validRoutePoint(point)) continue;
        if (m['type'] == 'arrive' && li < legs.length - 1) continue;
        result.add(
          RouteStep(
            instruction: m['instruction'] is String ? m['instruction'] : '',
            modifier: m['modifier'] is String ? m['modifier'] : '',
            type: m['type'] is String ? m['type'] : '',
            distance: distance.toDouble(),
            location: point,
            durationSeconds:
                step['duration'] is num &&
                    (step['duration'] as num).isFinite &&
                    (step['duration'] as num) >= 0
                ? (step['duration'] as num).toDouble()
                : null,
            bearingBefore:
                m['bearing_before'] is num &&
                    (m['bearing_before'] as num).isFinite
                ? (m['bearing_before'] as num).toDouble() % 360
                : null,
            bearingAfter:
                m['bearing_after'] is num &&
                    (m['bearing_after'] as num).isFinite
                ? (m['bearing_after'] as num).toDouble() % 360
                : null,
          ),
        );
      }
    }
    return result;
  }

  // ─── GEOMETRY HELPERS ────────────────────────────────────────────────────

  /// Returns the minimum distance in METERS from a point to a line segment.
  /// Uses the Haversine-based perpendicular distance formula.
  static double _pointToSegmentDistanceMeters(
    double pLng,
    double pLat,
    double aLng,
    double aLat,
    double bLng,
    double bLat,
  ) {
    // Vector AB
    final abLng = bLng - aLng;
    final abLat = bLat - aLat;
    // Vector AP
    final apLng = pLng - aLng;
    final apLat = pLat - aLat;

    final abLenSq = abLng * abLng + abLat * abLat;
    if (abLenSq == 0) {
      // Degenerate segment (A == B), just return point-to-point distance
      return _haversineMeters(pLat, pLng, aLat, aLng);
    }

    // Project P onto line AB, clamped to [0, 1]
    double t = (apLng * abLng + apLat * abLat) / abLenSq;
    t = t.clamp(0.0, 1.0);

    // Closest point on segment
    final closestLng = aLng + t * abLng;
    final closestLat = aLat + t * abLat;

    return _haversineMeters(pLat, pLng, closestLat, closestLng);
  }

  /// Haversine distance between two lat/lng points in meters.
  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180.0;

  /// Deduplicate only identical ordered geometry. Sampling just start, middle
  /// and end can erase a clear detour that differs around the closed segment.
  String _routeFingerprint(List<Position> pts) =>
      pts.map((point) => '${point.lng},${point.lat}').join('|');

  /// Checks if a route crosses a given road within [thresholdMeters].
  /// Tests entire route segments, including crossings between sparse vertices.
  static bool doesRouteCrossRoad(
    List<Position> routePts,
    List<Position> roadPts, {
    double thresholdMeters = RiskConfig.roadCrossingBufferMeters,
  }) {
    if (routePts.isEmpty || roadPts.length < 2) return false;

    // For each segment of the road polyline
    for (int s = 0; s < roadPts.length - 1; s++) {
      final aLng = roadPts[s].lng.toDouble();
      final aLat = roadPts[s].lat.toDouble();
      final bLng = roadPts[s + 1].lng.toDouble();
      final bLat = roadPts[s + 1].lat.toDouble();

      // Quick bounding-box pre-filter to skip distant segments
      final latBuffer = thresholdMeters / 110000.0;
      final lngBuffer =
          latBuffer /
          math.max(
            0.01,
            math.cos(_toRadians(math.max(aLat.abs(), bLat.abs()))),
          );
      final segMinLng = math.min(aLng, bLng) - lngBuffer;
      final segMaxLng = math.max(aLng, bLng) + lngBuffer;
      final segMinLat = math.min(aLat, bLat) - latBuffer;
      final segMaxLat = math.max(aLat, bLat) + latBuffer;

      for (int i = 0; i < routePts.length; i++) {
        final pt = routePts[i];
        final next = routePts[math.min(i + 1, routePts.length - 1)];
        final pLng = pt.lng.toDouble();
        final pLat = pt.lat.toDouble();
        final qLng = next.lng.toDouble();
        final qLat = next.lat.toDouble();

        // Fast rejection: skip if point is clearly outside segment bbox
        if (math.max(pLng, qLng) < segMinLng ||
            math.min(pLng, qLng) > segMaxLng ||
            math.max(pLat, qLat) < segMinLat ||
            math.min(pLat, qLat) > segMaxLat) {
          continue;
        }

        // A true intersection can be far from all four endpoints.
        final rx = qLng - pLng;
        final ry = qLat - pLat;
        final sx = bLng - aLng;
        final sy = bLat - aLat;
        final cross = rx * sy - ry * sx;
        if (cross != 0.0) {
          final dx = aLng - pLng;
          final dy = aLat - pLat;
          final t = (dx * sy - dy * sx) / cross;
          final u = (dx * ry - dy * rx) / cross;
          if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return true;
        }
        final dist = _pointToSegmentDistanceMeters(
          pLng,
          pLat,
          aLng,
          aLat,
          bLng,
          bLat,
        );
        if (dist <= thresholdMeters ||
            _pointToSegmentDistanceMeters(qLng, qLat, aLng, aLat, bLng, bLat) <=
                thresholdMeters ||
            _pointToSegmentDistanceMeters(aLng, aLat, pLng, pLat, qLng, qLat) <=
                thresholdMeters ||
            _pointToSegmentDistanceMeters(bLng, bLat, pLng, pLat, qLng, qLat) <=
                thresholdMeters) {
          return true;
        }
      }
    }
    return false;
  }

  static bool doesRouteCrossGeometry(
    List<Position> route,
    Map<String, dynamic>? geometry, {
    double thresholdMeters = RiskConfig.roadCrossingBufferMeters,
  }) => GeoUtils.extractSegments(geometry).any(
    (segment) => doesRouteCrossRoad(
      route,
      segment.map((p) => Position(p.lng, p.lat)).toList(),
      thresholdMeters: thresholdMeters,
    ),
  );

  // ─── ROUTE SAFETY EVALUATION ────────────────────────────────────────────

  @visibleForTesting
  Map<String, dynamic> evaluateRouteSafety(
    List<Position> routePts,
    List<dynamic> allRoads,
    String vehicleType, {
    WeatherState? weatherState,
  }) {
    // FIX A: renamed from 'avoided' → 'hazardAlerts' to honestly represent
    // roads with risk/hazard that this route crosses (not roads it skips).
    List<String> hazardAlerts = [];
    List<Map<String, dynamic>> crossedRoads = [];
    String status = 'safe';
    bool isBlocked = false;
    double maxRisk = 0.0;
    double totalRisk = 0.0;
    int crossedCount = 0;
    int unconfirmedCount = 0;
    String? highestRiskSegmentId;

    if (routePts.isEmpty) {
      return {
        'status': status,
        'hazardAlerts': hazardAlerts,
        'crossedRoads': crossedRoads,
        'maxRisk': 0.0,
        'averageRisk': 0.0,
        'totalRisk': 0.0,
        'highestRiskSegmentId': null,
        'isBlocked': false,
        'unconfirmedCount': 0,
      };
    }

    final effectiveWeather =
        weatherState ?? SimulatedWeatherService.instance.currentState;

    for (var road in allRoads) {
      if (road.geometry == null) continue;

      // Parse road score (safeguard dynamic type)
      double currentRisk = (road.riskScore as num).toDouble();
      final isUnconfirmed = road.needsStatusConfirmation(effectiveWeather);

      // We evaluate EVERY road that has a risk score > 0 OR is not passable OR is unconfirmed/stale.
      if (currentRisk > 0 || road.status != 'passable' || isUnconfirmed) {
        final geoPts = GeoUtils.extractPoints(road.geometry);
        if (geoPts.length < 2) continue;

        bool crossesRoad = doesRouteCrossGeometry(
          routePts,
          road.geometry,
          thresholdMeters: RiskConfig.roadCrossingBufferMeters,
        );

        if (crossesRoad) {
          const safetyRank = {
            'safe': 0,
            'unverified_risk': 1,
            'passable_partial': 2,
            'partial': 3,
            'critical': 5,
          };

          // 1. Unconfirmed Stale Road Advisory (Tier 1: unverified risk, tracked separately without inflating totalRisk or diluting averageRisk)
          if (isUnconfirmed) {
            unconfirmedCount++;
            // Uncertainty must not downgrade a critical model estimate. Keep
            // its warning and risk totals, without claiming a physical closure.
            if (currentRisk < 80.0) {
              if ((safetyRank['unverified_risk']!) > (safetyRank[status] ?? 0))
                status = 'unverified_risk';
              if (!hazardAlerts.contains('${road.name} (Unverified Risk)'))
                hazardAlerts.add('${road.name} (Unverified Risk)');
              crossedRoads.add({
                'id': road.id,
                'name': road.name,
                'risk': 0.0,
                'cat': 'Unverified Advisory',
              });
              continue;
            }
          }

          totalRisk += currentRisk;
          crossedCount++;

          if (currentRisk > maxRisk) {
            maxRisk = currentRisk;
            highestRiskSegmentId = road.id;
          }

          // 2. Confirmed Impassable Road Barrier (from stored road.status ONLY)
          if (road.status == 'not_passable') {
            status = 'critical';
            isBlocked = true;
            if (!hazardAlerts.contains(road.name)) hazardAlerts.add(road.name);
            crossedRoads.add({
              'id': road.id,
              'name': road.name,
              'risk': currentRisk,
              'cat': 'Critical Risk',
            });
            continue;
          }

          // 3. High Predicted Risk (>= 80.0) -> Critical status, but NOT physically blocked
          if (currentRisk >= 80.0) {
            if ((safetyRank['critical']!) > (safetyRank[status] ?? 0))
              status = 'critical';
            if (!hazardAlerts.contains(road.name)) hazardAlerts.add(road.name);
            crossedRoads.add({
              'id': road.id,
              'name': road.name,
              'risk': currentRisk,
              'cat': 'Critical Predicted Risk',
            });
            continue;
          }

          // 4. Confirmed Partial Flood (road.status == 'partial')
          if (road.status == 'partial') {
            bool isPassableForVehicle = (vehicleType == 'SUV / Pickup');
            if (isPassableForVehicle) {
              if ((safetyRank['passable_partial']!) > (safetyRank[status] ?? 0))
                status = 'passable_partial';
              if (!hazardAlerts.contains('${road.name} (High Clearance)'))
                hazardAlerts.add('${road.name} (High Clearance)');
            } else {
              if ((safetyRank['partial']!) > (safetyRank[status] ?? 0))
                status = 'partial';
              if (!hazardAlerts.contains(road.name))
                hazardAlerts.add(road.name);
            }
            String cat = currentRisk >= 60 ? 'Warning' : 'Watch';
            crossedRoads.add({
              'id': road.id,
              'name': road.name,
              'risk': currentRisk,
              'cat': cat,
            });
            continue;
          }

          // 5. Moderate/Low Predicted Risk
          if (currentRisk > 0) {
            if (!hazardAlerts.contains('${road.name} (Predicted Risk)'))
              hazardAlerts.add('${road.name} (Predicted Risk)');
            String cat = currentRisk >= 60
                ? 'Warning'
                : (currentRisk >= 30 ? 'Watch' : 'Low Risk');
            crossedRoads.add({
              'id': road.id,
              'name': road.name,
              'risk': currentRisk,
              'cat': 'Predicted $cat',
            });
          }
        }
      }
    }

    double averageRisk = crossedCount > 0 ? totalRisk / crossedCount : 0.0;

    return {
      'status': status,
      'hazardAlerts': hazardAlerts,
      'crossedRoads': crossedRoads,
      'maxRisk': maxRisk,
      'averageRisk': averageRisk,
      'totalRisk': totalRisk,
      'highestRiskSegmentId': highestRiskSegmentId,
      'isBlocked': isBlocked,
      'unconfirmedCount': unconfirmedCount,
    };
  }

  /// Prefer a route without known risk, then shorter estimated travel time.
  /// A configured staging location is a suggestion, not a safety certification.
  static Future<Map<String, dynamic>?> findNearestReachableStagingFacility({
    required Position origin,
    required List<Map<String, dynamic>> facilities,
    required RoutingService routingService,
    String vehicleType = 'Sedan',
    List<dynamic>? roadsOverride,
    WeatherState? weatherStateOverride,
    DirectionsFetcher? directionsFetcher,
    bool Function()? isCurrent,
  }) async {
    if (facilities.isEmpty) return null;

    // Helper to evaluate all candidate facilities in parallel for a given pass
    Future<Map<String, dynamic>?> evaluatePass({
      required bool allowDetour,
      required int maxDetours,
      required Duration timeoutDuration,
    }) async {
      final futures = facilities.map((facility) async {
        final fLat = (facility['lat'] as num).toDouble();
        final fLng = (facility['lng'] as num).toDouble();
        final destPos = Position(fLng, fLat);

        try {
          final computed = await routingService
              .computeRoutes(
                origin: origin,
                destination: destPos,
                vehicleType: vehicleType,
                allowDetourGeneration: allowDetour,
                maxDetourCandidates: maxDetours,
                roadsOverride: roadsOverride,
                weatherStateOverride: weatherStateOverride,
                directionsFetcher: directionsFetcher,
                timeBudget: timeoutDuration,
                isCurrent: isCurrent,
              )
              .timeout(timeoutDuration);

          if (isCurrent != null && !isCurrent()) return null;
          final candidates =
              computed
                  .map(
                    (r) => routingService.refreshRoute(
                      r,
                      roads: roadsOverride,
                      weather: weatherStateOverride,
                      vehicleType: vehicleType,
                    ),
                  )
                  .where(isStagingRouteCandidate)
                  .toList()
                ..sort(compareStagingRoutes);
          final reachableRoute = candidates.firstOrNull;

          if (reachableRoute != null) {
            return {...facility, 'reachableRoute': reachableRoute};
          }
        } catch (e) {
          debugPrint(
            '[StagingFacility] Route check unavailable (${e.runtimeType}).',
          );
        }
        return null;
      });

      final results = await Future.wait(futures);
      final reachableCandidates = results
          .whereType<Map<String, dynamic>>()
          .toList();

      if (reachableCandidates.isEmpty) return null;

      reachableCandidates.sort((a, b) {
        final rA = a['reachableRoute'] as PlannedRoute;
        final rB = b['reachableRoute'] as PlannedRoute;
        return compareStagingRoutes(rA, rB);
      });

      return reachableCandidates.first;
    }

    // Pass 1: Direct Reachability (allowDetourGeneration: false, 9s timeout)
    final directResult = await evaluatePass(
      allowDetour: false,
      maxDetours: 0,
      timeoutDuration: const Duration(seconds: 9),
    );
    if (isCurrent != null && !isCurrent()) return null;

    if (directResult != null) {
      return directResult;
    }

    // Pass 2: Detour Fallback (allowDetourGeneration: true, maxDetourCandidates: 3, 12s timeout)
    return await evaluatePass(
      allowDetour: true,
      maxDetours: 3,
      timeoutDuration: const Duration(seconds: 12),
    );
  }

  static bool canAdoptAutomatically(PlannedRoute route) =>
      route.canStartNavigation && route.safetyStatus != 'critical';

  static bool isStagingRouteCandidate(PlannedRoute route) =>
      canAdoptAutomatically(route);

  static int compareStagingRoutes(PlannedRoute a, PlannedRoute b) {
    final caution = (a.needsCaution ? 1 : 0).compareTo(b.needsCaution ? 1 : 0);
    return caution != 0 ? caution : a.durationMin.compareTo(b.durationMin);
  }

  List<Position> _decodePolyline(String encoded) {
    List<Position> rawPoints = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      rawPoints.add(Position(lng / 1E5, lat / 1E5));
    }

    // Step 2: Interpolate points to ensure mathematical density (every ~20m)
    // This prevents the "Polyline Jump" flaw where a straight road misses a flood check
    List<Position> interpolatedPoints = [];
    if (rawPoints.isEmpty) return interpolatedPoints;

    interpolatedPoints.add(rawPoints.first);
    for (int i = 1; i < rawPoints.length; i++) {
      final p1 = rawPoints[i - 1];
      final p2 = rawPoints[i];

      final dLon = p2.lng - p1.lng;
      final dLat = p2.lat - p1.lat;
      final distSq = (dLon * dLon) + (dLat * dLat);

      // If distance > ~20 meters (approx 0.00000004 in degrees squared)
      if (distSq > 0.00000004) {
        int steps = (math.sqrt(distSq) / 0.0002).ceil();
        for (int j = 1; j <= steps; j++) {
          interpolatedPoints.add(
            Position(p1.lng + dLon * (j / steps), p1.lat + dLat * (j / steps)),
          );
        }
      } else {
        interpolatedPoints.add(p2);
      }
    }
    return interpolatedPoints;
  }

  /// Pure static helper to determine if polyline `b` is effectively the same as polyline `a`.
  /// Requires bidirectional coverage: >= 90% (matchRatio) of points in `b` are within 15 m (thresholdMeters) of `a`,
  /// AND >= 90% of points in `a` are within 15 m of `b`.
  static bool routesEffectivelySame(
    List<Position> a,
    List<Position> b, {
    double thresholdMeters = 15.0,
    double matchRatio = 0.90,
  }) {
    if (a.isEmpty && b.isEmpty) return true;
    if (a.isEmpty || b.isEmpty) return false;

    double coverage(List<Position> source, List<Position> target) {
      if (source.isEmpty) return 1.0;
      int matchCount = 0;
      for (final p in source) {
        double minDistance = double.infinity;
        if (target.length == 1) {
          minDistance = GeoUtils.haversineMeters(
            p.lat.toDouble(),
            p.lng.toDouble(),
            target.first.lat.toDouble(),
            target.first.lng.toDouble(),
          );
        } else {
          for (int i = 0; i < target.length - 1; i++) {
            final d = GeoUtils.pointToSegmentDistanceMeters(
              p.lng.toDouble(),
              p.lat.toDouble(),
              target[i].lng.toDouble(),
              target[i].lat.toDouble(),
              target[i + 1].lng.toDouble(),
              target[i + 1].lat.toDouble(),
            );
            if (d < minDistance) {
              minDistance = d;
              if (minDistance <= thresholdMeters) break;
            }
          }
        }
        if (minDistance <= thresholdMeters) {
          matchCount++;
        }
      }
      return matchCount / source.length;
    }

    return coverage(b, a) >= matchRatio && coverage(a, b) >= matchRatio;
  }

  /// Pure helper to find roads whose effective status has changed compared to cached status.
  static List<RoadStatus> findStatusChangedRoads(
    List<RoadStatus> currentRoads,
    Map<String, String> statusCache,
    WeatherState weatherState, {
    Map<String, String>? confirmedStatusCache,
  }) {
    final List<RoadStatus> changed = [];
    for (final road in currentRoads) {
      final effStatus = road.getEffectiveStatus(weatherState);
      final cached = statusCache[road.id];
      if (cached != effStatus ||
          (confirmedStatusCache != null &&
              confirmedStatusCache[road.id] != road.status)) {
        changed.add(road);
      }
    }
    return changed;
  }

  /// Only adopt routes that avoid every currently confirmed closure.
  static List<PlannedRoute> routesAvoidingConfirmedClosures(
    List<PlannedRoute> routes,
    List<RoadStatus> roads,
  ) {
    final closures = roads
        .where((road) => road.status == 'not_passable')
        .toList();
    return routes
        .where(
          (route) =>
              !route.isBlocked &&
              route.points.length >= 2 &&
              !closures.any(
                (road) => doesRouteCrossGeometry(route.points, road.geometry),
              ),
        )
        .toList();
  }

  /// Pure helper to build route error and warning messages according to route safety and weather state.
  static ({String? error, String? warning}) buildRouteMessages(
    List<PlannedRoute> routes,
    WeatherState weather, {
    required bool usingFallback,
  }) {
    if (routes.isEmpty) {
      return (
        error: 'No routes found. Try a different destination.',
        warning: null,
      );
    }

    String? error;
    List<String> warnings = [];

    final allBlocked = routes.every((r) => r.isBlocked);
    final allCritical =
        !allBlocked && routes.every((r) => r.safetyStatus == 'critical');
    final isSevereWeather =
        weather == WeatherState.heavyRain || weather == WeatherState.typhoon;

    if (allBlocked) {
      error = 'All available routes are closed by official flood barriers.';
    } else if (allCritical) {
      warnings.add(
        'All available routes pass through predicted high-risk flood zones.',
      );
    } else if (isSevereWeather && routes.first.safetyStatus != 'safe') {
      if (weather == WeatherState.typhoon) {
        warnings.add(
          'Typhoon Active — No completely clear routes available. The safest option is shown first. Proceed with extreme caution.',
        );
      } else {
        warnings.add(
          'Heavy Rain Active — Routes may include partially flooded roads. The safest option is shown first. Proceed with caution.',
        );
      }
    }

    if (usingFallback) {
      warnings.add(
        'GPS unavailable — route started from default point (Brgy. Marulas).',
      );
    }

    final warning = warnings.isNotEmpty ? warnings.join('\n') : null;
    return (error: error, warning: warning);
  }
}
