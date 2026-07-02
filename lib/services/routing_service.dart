import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/planned_route.dart';
import 'app_state_service.dart';
import 'weather_service.dart';
import 'location_service.dart';
import '../config/risk_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RoutingService extends ChangeNotifier {
  static final RoutingService instance = RoutingService._internal();
  RoutingService._internal();

  static final String _publicToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  
  bool isRoutePlanning = false;
  bool isRouteLoading = false;
  String? routeErrorMessage;
  String? routeWarningMessage;
  
  Position? originPoint; // Will be set by GPS
  Position? destinationPoint;
  String destinationName = '';
  
  List<PlannedRoute> routes = [];
  int selectedRouteIndex = 0;
  String selectedVehicleType = 'Sedan';

  // Analytics for Dashboard
  int routesProtectedCount = 0;
  double averageRiskReduction = 0.0;
  String? _lastCalculatedRouteSignature;

  // ─── DEV TESTING MODE ────────────────────────────────────────────────────
  // Set to true to pin the origin to Barangay Marulas so you can test routing
  // without physically being there. Set to false for production / real GPS.
  static const bool devMode = kDebugMode && false;
  static final Position _devOrigin = Position(120.9842, 14.6761); // Barangay Marulas, Valenzuela

  void startPlanning({Position? prefillDestination, String? name}) async {
    isRoutePlanning = true;
    routes.clear();
    routeErrorMessage = null;
    routeWarningMessage = null;
    
    if (devMode) {
      // DEV: Use fixed Marulas origin so routing can be tested anywhere
      originPoint = _devOrigin;
    } else {
      // PROD: Use live GPS
      try {
        final pos = await LocationService.getCurrentPosition();
        originPoint = pos ?? _devOrigin; // fallback to Marulas if GPS denied
      } catch (e) {
        debugPrint('[RoutingService] GPS timeout or error: $e');
        originPoint = _devOrigin;
      }
    }

    if (prefillDestination != null) {
      destinationPoint = prefillDestination;
      destinationName = name ?? "Selected Location";
      calculateRoute();
    } else {
      destinationPoint = null;
      destinationName = '';
    }
    notifyListeners();
  }

  void exitPlanning() {
    isRoutePlanning = false;
    destinationPoint = null;
    destinationName = '';
    routes.clear();
    routeErrorMessage = null;
    routeWarningMessage = null;
    notifyListeners();
  }

  void setDestination(Position point, String name) {
    destinationPoint = point;
    destinationName = name;
    calculateRoute();
  }

  void selectRoute(int index) {
    selectedRouteIndex = index;
    notifyListeners();
  }

  void setVehicleType(String type) {
    selectedVehicleType = type;
    if (destinationPoint != null) {
      calculateRoute();
    } else {
      notifyListeners();
    }
  }

  int _calculationId = 0;

  Future<void> calculateRoute() async {
    if (originPoint == null || destinationPoint == null) return;

    final routeStopwatch = Stopwatch()..start();

    _calculationId++;
    final currentCalcId = _calculationId;

    isRouteLoading = true;
    routeErrorMessage = null;
    routeWarningMessage = null;
    routes.clear();
    selectedRouteIndex = 0; // reset to top (safest) route
    notifyListeners();

    try {
      final appState = AppStateService.instance;

      // ── Step 1: Ask Mapbox for ALL alternative routes in one call ──────────
      final allMapboxRoutes = await _fetchDirections(originPoint!, destinationPoint!);

      if (currentCalcId != _calculationId) return; // Prevent race conditions

      if (allMapboxRoutes.isEmpty) {
        routeErrorMessage = 'No routes found. Try a different destination.';
        return;
      }

      // ── Step 2: Evaluate every route's safety against Firestore flood data ─
      List<Map<String, dynamic>> rawEvaluated = [];
      String? highestRiskSegmentToAvoidId;
      double globalMaxRisk = 0.0;

      for (int i = 0; i < allMapboxRoutes.length; i++) {
        final r = allMapboxRoutes[i];
        final pts   = _decodePolyline(r['geometry'] as String);
        final safety = _evaluateRouteSafety(pts, appState.roads, selectedVehicleType);
        final steps  = _parseSteps(r);

        double distMiles = (r['distance'] / 1609.34).roundToDouble();
        double distMeters = (r['distance'] as num).toDouble();
        
        double avgRisk = safety['averageRisk'] as double;
        double maxRisk = safety['maxRisk'] as double;
        double totalRisk = safety['totalRisk'] as double;

        // The Approved Formula
        double routeCost = distMeters + (avgRisk * 10.0) + (maxRisk * 50.0);

        // Safety Score (100 = safe, 0 = catastrophic)
        int safetyScore = (100 - (avgRisk * 0.4) - (maxRisk * 0.6)).round().clamp(0, 100);

        // If Critical, force safety score lower and spike the cost
        if (safety['status'] == 'critical') {
            safetyScore = safetyScore.clamp(0, 20); // Severely limit safety score
            routeCost += 50000.0; // Massive penalty
        }

        if (maxRisk > globalMaxRisk && safety['highestRiskSegmentId'] != null) {
          globalMaxRisk = maxRisk;
          highestRiskSegmentToAvoidId = safety['highestRiskSegmentId'] as String?;
        }

        rawEvaluated.add({
          'pts': pts,
          'durationMin': (r['duration'] / 60).round(),
          'distanceMiles': distMiles,
          'summary': i == 0 ? 'Fastest Route' : 'Alternative ${i + 1}',
          'avoidedRoads': safety['avoided'],
          'crossedRoads': safety['crossedRoads'],
          'safetyStatus': safety['status'],
          'safetyScore': safetyScore,
          'routeCost': routeCost,
          'totalRisk': totalRisk,
          'steps': steps,
        });
      }

      // ── Step 2.5: Dynamic Detour Generator (Safety Firewall Override) ──────
      if (rawEvaluated.isNotEmpty && rawEvaluated.every((r) => r['safetyStatus'] == 'flooded' || r['safetyStatus'] == 'critical')) {
        
        // Find the center of the highest risk segment to avoid it
        double avoidLng = (originPoint!.lng.toDouble() + destinationPoint!.lng.toDouble()) / 2;
        double avoidLat = (originPoint!.lat.toDouble() + destinationPoint!.lat.toDouble()) / 2;
        
        if (highestRiskSegmentToAvoidId != null) {
          final badRoad = appState.roads.cast<dynamic>().firstWhere((r) => r.id == highestRiskSegmentToAvoidId, orElse: () => null);
          if (badRoad != null && badRoad.geometry != null) {
             final coordsDyn = badRoad.geometry!['coordinates'] as List<dynamic>?;
             if (coordsDyn != null && coordsDyn.isNotEmpty) {
                double sumLng = 0;
                double sumLat = 0;
                int count = 0;
                for (final c in coordsDyn) {
                  if (c is List && c.length >= 2) {
                    sumLng += (c[0] as num).toDouble();
                    sumLat += (c[1] as num).toDouble();
                    count++;
                  }
                }
                if (count > 0) {
                  avoidLng = sumLng / count;
                  avoidLat = sumLat / count;
                }
             }
          }
        }
        
        double dLng = destinationPoint!.lng.toDouble() - originPoint!.lng.toDouble();
        double dLat = destinationPoint!.lat.toDouble() - originPoint!.lat.toDouble();
        double dist = math.sqrt(dLng * dLng + dLat * dLat);
        
        // Scale the detour proportionally
        double offsetAmount = (dist * 0.5).clamp(0.001, 0.01);
        
        // Generate waypoints away from the avoided segment
        final offsets = [
          Position(avoidLng + offsetAmount, avoidLat + offsetAmount),
          Position(avoidLng - offsetAmount, avoidLat - offsetAmount),
          Position(avoidLng + offsetAmount, avoidLat - offsetAmount),
          Position(avoidLng - offsetAmount, avoidLat + offsetAmount),
        ];
        
        // Track fingerprints to deduplicate routes
        final Set<String> seenFingerprints = {};
        for (final existing in rawEvaluated) {
          seenFingerprints.add(_routeFingerprint(existing['pts'] as List<Position>));
        }
        
        List<Map<String, dynamic>> allDetours = [];
        final detourFutures = offsets.map((offset) => _fetchDirections(originPoint!, destinationPoint!, waypoint: offset));
        final results = await Future.wait(detourFutures);
        for (final detours in results) {
          allDetours.addAll(detours);
        }
        
        if (currentCalcId != _calculationId) return;
        
        for (int i = 0; i < allDetours.length; i++) {
          final r = allDetours[i];
          final pts = _decodePolyline(r['geometry'] as String);
          
          // Deduplicate: skip routes with same fingerprint
          final fp = _routeFingerprint(pts);
          if (seenFingerprints.contains(fp)) continue;
          seenFingerprints.add(fp);
          
          final safety = _evaluateRouteSafety(pts, appState.roads, selectedVehicleType);
          final steps  = _parseSteps(r);
          
          double distMiles = (r['distance'] / 1609.34).roundToDouble();
          double distMeters = (r['distance'] as num).toDouble();
          double avgRisk = safety['averageRisk'] as double;
          double maxRisk = safety['maxRisk'] as double;
          double totalRisk = safety['totalRisk'] as double;
          double routeCost = distMeters + (avgRisk * 10.0) + (maxRisk * 50.0);
          int safetyScore = (100 - (avgRisk * 0.4) - (maxRisk * 0.6)).round().clamp(0, 100);

          if (safety['status'] == 'critical') {
              safetyScore = safetyScore.clamp(0, 20);
              routeCost += 50000.0;
          }
          
          rawEvaluated.add({
            'pts': pts,
            'durationMin': (r['duration'] / 60).round(),
            'distanceMiles': distMiles,
            'summary': 'Dynamic Safe Detour',
            'avoidedRoads': safety['avoided'],
            'crossedRoads': safety['crossedRoads'],
            'safetyStatus': safety['status'],
            'safetyScore': safetyScore,
            'routeCost': routeCost,
            'totalRisk': totalRisk,
            'steps': steps,
          });
        }
      }

      // ── Step 3: Find Baseline Risk and Sort BY ROUTE COST ASCENDING ──────────────
      final weatherState = SimulatedWeatherService.instance.currentState;
      bool isSevereWeather = weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon;

      if (rawEvaluated.isEmpty) {
        routeErrorMessage = 'No routes found. Try a different destination.';
        isRouteLoading = false;
        notifyListeners();
        return;
      }

      double baselineRisk = 0.0;
      for (var r in rawEvaluated) {
          if ((r['totalRisk'] as double) > baselineRisk) {
              baselineRisk = r['totalRisk'] as double;
          }
      }

      rawEvaluated.sort((a, b) => (a['routeCost'] as double).compareTo(b['routeCost'] as double));

      // ── Step 4: Build Explanations & Convert to PlannedRoute ──────────
      final List<PlannedRoute> evaluated = [];
      
      if (rawEvaluated.isNotEmpty) {
        final top = rawEvaluated[0];
        
        // If ALL routes are flooded or critical, set a blocking error
        if (rawEvaluated.every((r) => r['safetyStatus'] == 'flooded' || r['safetyStatus'] == 'critical')) {
          routeErrorMessage = 'WARNING: All available paths contain flooded or critical predicted risks. If you must proceed, use extreme caution.';
        }
        // If routes exist but aren't fully safe, set a non-blocking warning
        else if (isSevereWeather && top['safetyStatus'] != 'safe') {
          if (weatherState == WeatherState.typhoon) {
            routeWarningMessage = 'Typhoon Active — No completely clear routes available. The safest option is shown first. Proceed with extreme caution.';
          } else {
            routeWarningMessage = 'Heavy Rain Active — Routes may include partially flooded roads. The safest option is shown first. Proceed with caution.';
          }
        }

        var baselineRoute = rawEvaluated.firstWhere((x) => (x['totalRisk'] as double) == baselineRisk, orElse: () => rawEvaluated[0]);

        for (int i = 0; i < rawEvaluated.length; i++) {
          final current = rawEvaluated[i];
          String newSummary = current['summary'] as String;

          if (i == 0) {
            newSummary = (current['safetyScore'] as int) >= 90 ? 'Safest Route'
                : current['safetyStatus'] == 'unverified_risk' ? 'Best Available (Unverified)'
                : (current['safetyScore'] as int) >= 50 ? 'Least Risky Route'
                : 'Best Available Route';
            
            if (current['summary'] == 'Dynamic Safe Detour') {
              newSummary = 'Safe Detour (Auto-Generated)';
            }
          } else {
            if (current['summary'] == 'Dynamic Safe Detour') {
              newSummary = 'Alternative Detour ${i + 1}';
            } else {
              newSummary = 'Alternative ${i + 1}';
            }
          }

          List<Map<String, dynamic>> crossed = current['crossedRoads'] as List<Map<String, dynamic>>;
          List<String> routeExplanations = [];
          
          if (i == 0) {
              if (crossed.isEmpty && baselineRisk > 0) {
                  List<Map<String, dynamic>> baselineCrossed = baselineRoute['crossedRoads'] as List<Map<String, dynamic>>;
                  for (var badRoad in baselineCrossed) {
                      routeExplanations.add('Avoids ${badRoad['name']} (${badRoad['cat']})');
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
          if (timePenalty < 0) timePenalty = 0; // Don't show negative penalty if it's faster

          evaluated.add(PlannedRoute(
            points: current['pts'] as List<Position>,
            durationMin: currentDuration,
            distanceMiles: current['distanceMiles'] as double,
            summary: newSummary,
            avoidedRoads: current['avoidedRoads'] as List<String>,
            routeExplanations: routeExplanations,
            safetyStatus: current['safetyStatus'] as String,
            safetyScore: current['safetyScore'] as int,
            routeCost: current['routeCost'] as double,
            totalRisk: rRisk,
            riskReductionPercentage: riskReduction,
            timePenaltyMin: timePenalty,
            steps: current['steps'] as List<RouteStep>,
          ));
        }
      }

      routes.addAll(evaluated);

      routeStopwatch.stop();
      if (routes.isNotEmpty) {
        final topRoute = routes.first;
        
        // Track analytics
        final signature = '${originPoint?.lat},${originPoint?.lng}|${destinationPoint?.lat},${destinationPoint?.lng}';
        if (signature != _lastCalculatedRouteSignature && topRoute.riskReductionPercentage != null && topRoute.riskReductionPercentage! > 0) {
           _lastCalculatedRouteSignature = signature;
           routesProtectedCount++;
           double oldTotal = averageRiskReduction * (routesProtectedCount - 1);
           averageRiskReduction = (oldTotal + topRoute.riskReductionPercentage!) / routesProtectedCount;
           
           try {
             FirebaseFirestore.instance.collection('analytics').doc('routing').set({
               'routesProtectedCount': FieldValue.increment(1),
               'totalRiskReduction': FieldValue.increment(topRoute.riskReductionPercentage!),
             }, SetOptions(merge: true));
           } catch (e) {
             debugPrint('Failed to sync analytics: $e');
           }
        }

        debugPrint('\n--- ROUTE ANALYSIS ---');
        debugPrint('Routes Evaluated: ${rawEvaluated.length}');
        debugPrint('Road Segments: ${appState.roads.length}');
        debugPrint('Execution: ${routeStopwatch.elapsedMilliseconds} ms');
        debugPrint('Risk Reduction: ${topRoute.riskReductionPercentage ?? 0}%');
        debugPrint('Travel Penalty: +${topRoute.timePenaltyMin} min\n');
      }

    } catch (e) {
      debugPrint('[RoutingService] Route calculation error: $e');
      routeErrorMessage = 'Failed to calculate route. Check your connection.';
    } finally {
      isRouteLoading = false;
      notifyListeners();
    }
  }

  /// Fetches ALL available routes from Mapbox Directions API in a single call.
  /// [alternatives=true] returns up to 3 different paths Mapbox can find.
  Future<List<Map<String, dynamic>>> _fetchDirections(
      Position origin, Position dest, {Position? waypoint}) async {
    // Map vehicle type to the correct Mapbox routing profile
    String profile = 'driving';
    if (selectedVehicleType == 'Walking') {
      profile = 'walking';
    } else if (selectedVehicleType == 'Motorcycle') {
      profile = 'cycling'; // closest Mapbox profile
    }

    String coords = '${origin.lng},${origin.lat};';
    if (waypoint != null) {
      coords += '${waypoint.lng},${waypoint.lat};';
    }
    coords += '${dest.lng},${dest.lat}';

    final url =
        'https://api.mapbox.com/directions/v5/mapbox/$profile/'
        '$coords'
        '?alternatives=true'        // ← request all alternative routes
        '&geometries=polyline'
        '&overview=full'
        '&steps=true'
        '&access_token=$_publicToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          return List<Map<String, dynamic>>.from(data['routes'] as List);
        }
      } else {
        debugPrint('[RoutingService] Mapbox error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[RoutingService] Network error: $e');
    }
    return [];
  }

  List<RouteStep> _parseSteps(Map<String, dynamic> routeData) {
    List<RouteStep> parsedSteps = [];
    if (routeData['legs'] != null && routeData['legs'].isNotEmpty) {
      final leg = routeData['legs'][0];
      if (leg['steps'] != null) {
        for (var step in leg['steps']) {
          final maneuver = step['maneuver'];
          if (maneuver != null && maneuver['location'] != null) {
            final loc = maneuver['location'];
            parsedSteps.add(RouteStep(
              instruction: maneuver['instruction'] ?? '',
              modifier: maneuver['modifier'] ?? '',
              type: maneuver['type'] ?? '',
              distance: (step['distance'] ?? 0).toDouble(),
              location: Position(loc[0], loc[1]),
            ));
          }
        }
      }
    }
    return parsedSteps;
  }

  // ─── GEOMETRY HELPERS ────────────────────────────────────────────────────

  /// Returns the minimum distance in METERS from a point to a line segment.
  /// Uses the Haversine-based perpendicular distance formula.
  static double _pointToSegmentDistanceMeters(
      double pLng, double pLat,
      double aLng, double aLat,
      double bLng, double bLat) {
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
  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180.0;

  /// Fingerprint a route by sampling a few key coordinates for deduplication.
  String _routeFingerprint(List<Position> pts) {
    if (pts.isEmpty) return '';
    final first = pts.first;
    final mid = pts[pts.length ~/ 2];
    final last = pts.last;
    // Round to ~11m precision to catch near-duplicates
    String r(num v) => v.toDouble().toStringAsFixed(4);
    return '${r(first.lng)},${r(first.lat)}|${r(mid.lng)},${r(mid.lat)}|${r(last.lng)},${r(last.lat)}';
  }

  /// Checks if a route crosses a given road within [thresholdMeters].
  /// Uses point-to-segment geometry — NOT point-to-point cloud.
  static bool doesRouteCrossRoad(List<Position> routePts, List<Position> roadPts, {double thresholdMeters = 30.0}) {
    if (routePts.isEmpty || roadPts.length < 2) return false;

    // For each segment of the road polyline
    for (int s = 0; s < roadPts.length - 1; s++) {
      final aLng = roadPts[s].lng.toDouble();
      final aLat = roadPts[s].lat.toDouble();
      final bLng = roadPts[s + 1].lng.toDouble();
      final bLat = roadPts[s + 1].lat.toDouble();

      // Quick bounding-box pre-filter to skip distant segments
      final segMinLng = math.min(aLng, bLng) - 0.0004; // ~40m buffer
      final segMaxLng = math.max(aLng, bLng) + 0.0004;
      final segMinLat = math.min(aLat, bLat) - 0.0004;
      final segMaxLat = math.max(aLat, bLat) + 0.0004;

      for (final pt in routePts) {
        final pLng = pt.lng.toDouble();
        final pLat = pt.lat.toDouble();

        // Fast rejection: skip if point is clearly outside segment bbox
        if (pLng < segMinLng || pLng > segMaxLng || pLat < segMinLat || pLat > segMaxLat) {
          continue;
        }

        final dist = _pointToSegmentDistanceMeters(pLng, pLat, aLng, aLat, bLng, bLat);
        if (dist < thresholdMeters) {
          return true;
        }
      }
    }
    return false;
  }

  // ─── ROUTE SAFETY EVALUATION ────────────────────────────────────────────

  Map<String, dynamic> _evaluateRouteSafety(List<Position> routePts, List<dynamic> allRoads, String vehicleType) {
    List<String> avoided = [];
    List<Map<String, dynamic>> crossedRoads = [];
    String status = 'safe';
    double maxRisk = 0.0;
    double totalRisk = 0.0;
    int crossedCount = 0;
    String? highestRiskSegmentId;

    if (routePts.isEmpty) {
      return {
        'status': status,
        'avoided': avoided,
        'crossedRoads': crossedRoads,
        'maxRisk': 0.0,
        'averageRisk': 0.0,
        'totalRisk': 0.0,
        'highestRiskSegmentId': null,
      };
    }

    final weatherState = SimulatedWeatherService.instance.currentState;
    bool isSevereWeather = weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon;

    for (var road in allRoads) {
      if (road.geometry == null) continue;

      // Parse road score (safeguard dynamic type)
      double currentRisk = (road.riskScore as num).toDouble();

      // We evaluate EVERY road that has a risk score > 0 OR is not passable.
      if (currentRisk > 0 || road.status != 'passable') {
        final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
        if (coordsDyn == null) continue;

        // Parse road coordinates
        List<Position> roadPts = [];
        for (final c in coordsDyn) {
          double? roadLon, roadLat;
          if (c is Map) {
            roadLon = (c['lon'] as num?)?.toDouble();
            roadLat = (c['lat'] as num?)?.toDouble();
          } else if (c is List && c.length >= 2) {
            roadLon = (c[0] as num?)?.toDouble();
            roadLat = (c[1] as num?)?.toDouble();
          }
          if (roadLon != null && roadLat != null) {
            roadPts.add(Position(roadLon, roadLat));
          }
        }

        if (roadPts.length < 2) continue;

        bool crossesRoad = doesRouteCrossRoad(routePts, roadPts, thresholdMeters: 30.0);

        if (crossesRoad) {
          totalRisk += currentRisk;
          crossedCount++;
          
          if (currentRisk > maxRisk) {
            maxRisk = currentRisk;
            highestRiskSegmentId = road.id;
          }

          String roadEffectiveStatus = road.getEffectiveStatus(weatherState);
          double hoursOldForStaleness = DateTime.now().difference(road.updatedAt).inMinutes / 60.0;
          bool isStaleData = hoursOldForStaleness >= RiskConfig.getPassableStaleThresholdHours(road.vulnerability);

          // Critical Barrier Logic
          if (currentRisk >= 80.0 || roadEffectiveStatus == 'not_passable') {
            status = 'critical'; // Replaces 'flooded' to block routing unless no alternative
            if (!avoided.contains(road.name)) avoided.add(road.name);
            crossedRoads.add({'name': road.name, 'risk': currentRisk, 'cat': 'Critical Risk'});
            continue; 
          }

          bool isPassableForVehicle = false;
          if (roadEffectiveStatus == 'partial' && (vehicleType == 'SUV / Pickup' || vehicleType == 'Truck')) {
             isPassableForVehicle = true;
          }

          if (roadEffectiveStatus != 'passable') {
            if (!isPassableForVehicle) {
              String newStatus = roadEffectiveStatus == 'not_passable' ? 'critical' : 'partial';
              if (vehicleType == 'Walking' && roadEffectiveStatus == 'not_passable') newStatus = 'critical';

              const safetyRank = {'safe': 0, 'unverified_risk': 1, 'passable_partial': 2, 'partial': 3, 'critical': 5};
              if ((safetyRank[newStatus] ?? 0) > (safetyRank[status] ?? 0)) status = newStatus;
              
              if (!avoided.contains(road.name)) avoided.add(road.name);
              String cat = currentRisk >= 60 ? 'Warning' : 'Watch';
              crossedRoads.add({'name': road.name, 'risk': currentRisk, 'cat': cat});
            } else {
              const safetyRank = {'safe': 0, 'unverified_risk': 1, 'passable_partial': 2, 'partial': 3, 'critical': 5};
              if ((safetyRank['passable_partial']!) > (safetyRank[status] ?? 0)) status = 'passable_partial';
              if (!avoided.contains('${road.name} (High Clearance)')) avoided.add('${road.name} (High Clearance)');
            }
          } else if (isSevereWeather && isStaleData) {
            const safetyRank = {'safe': 0, 'unverified_risk': 1, 'passable_partial': 2, 'partial': 3, 'critical': 5};
            if ((safetyRank['unverified_risk'] ?? 0) > (safetyRank[status] ?? 0)) status = 'unverified_risk';
            if (!avoided.contains('${road.name} (Unverified Risk)')) avoided.add('${road.name} (Unverified Risk)');
          } else if (currentRisk > 0) {
            if (!avoided.contains('${road.name} (Predicted Risk)')) avoided.add('${road.name} (Predicted Risk)');
            String cat = currentRisk >= 60 ? 'Warning' : (currentRisk >= 30 ? 'Watch' : 'Low Risk');
            crossedRoads.add({'name': road.name, 'risk': currentRisk, 'cat': 'Predicted $cat'});
          }
        }
      }
    }

    double averageRisk = crossedCount > 0 ? totalRisk / crossedCount : 0.0;

    return {
      'status': status,
      'avoided': avoided,
      'crossedRoads': crossedRoads,
      'maxRisk': maxRisk,
      'averageRisk': averageRisk,
      'totalRisk': totalRisk,
      'highestRiskSegmentId': highestRiskSegmentId,
    };
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
           interpolatedPoints.add(Position(
             p1.lng + dLon * (j / steps),
             p1.lat + dLat * (j / steps),
           ));
        }
      } else {
        interpolatedPoints.add(p2);
      }
    }
    return interpolatedPoints;
  }
}