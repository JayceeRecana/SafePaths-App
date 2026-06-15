import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/planned_route.dart';
import 'app_state_service.dart';
import 'location_service.dart';

class RoutingService extends ChangeNotifier {
  static final RoutingService instance = RoutingService._internal();
  RoutingService._internal();

  final String _publicToken = 'pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTlldHMweDAyOGYzMnM3a202dWc1encifQ.3bSUr0nz6i29AtlnB2HlHw';
  
  bool isRoutePlanning = false;
  bool isRouteLoading = false;
  String? routeErrorMessage;
  
  Position? originPoint; // Will be set by GPS
  Position? destinationPoint;
  String destinationName = '';
  
  List<PlannedRoute> routes = [];
  int selectedRouteIndex = 0;
  String selectedVehicleType = 'Sedan';

  // ─── DEV TESTING MODE ────────────────────────────────────────────────────
  // Set to true to pin the origin to Barangay Marulas so you can test routing
  // without physically being there. Set to false for production / real GPS.
  static const bool devMode = true;
  static final Position _devOrigin = Position(120.9842, 14.6761); // Barangay Marulas, Valenzuela

  void startPlanning({Position? prefillDestination, String? name}) async {
    isRoutePlanning = true;
    routes.clear();
    routeErrorMessage = null;
    
    if (devMode) {
      // DEV: Use fixed Marulas origin so routing can be tested anywhere
      originPoint = _devOrigin;
    } else {
      // PROD: Use live GPS
      final pos = await LocationService.getCurrentPosition();
      originPoint = pos ?? _devOrigin; // fallback to Marulas if GPS denied
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

  Future<void> calculateRoute() async {
    if (originPoint == null || destinationPoint == null) return;

    isRouteLoading = true;
    routeErrorMessage = null;
    routes.clear();
    selectedRouteIndex = 0; // reset to top (safest) route
    notifyListeners();

    try {
      final appState = AppStateService.instance;

      // ── Step 1: Ask Mapbox for ALL alternative routes in one call ──────────
      final allMapboxRoutes = await _fetchDirections(originPoint!, destinationPoint!);

      if (allMapboxRoutes.isEmpty) {
        routeErrorMessage = 'No routes found. Try a different destination.';
        return;
      }

      // ── Step 2: Evaluate every route's safety against Firestore flood data ─
      final List<PlannedRoute> evaluated = [];
      for (int i = 0; i < allMapboxRoutes.length; i++) {
        final r = allMapboxRoutes[i];
        final pts   = _decodePolyline(r['geometry'] as String);
        final safety = _evaluateRouteSafety(pts, appState.roads);
        final steps  = _parseSteps(r);

        evaluated.add(PlannedRoute(
          points:       pts,
          durationMin:  (r['duration'] / 60).round(),
          distanceMiles: (r['distance'] / 1609.34).roundToDouble(),
          summary:      i == 0 ? 'Fastest Route' : 'Alternative ${i + 1}',
          avoidedRoads: safety['avoided'] as List<String>,
          safetyStatus: safety['status'] as String,
          steps:        steps,
        ));
      }

      // ── Step 3: Sort — safe first, partial next, flooded last ──────────────
      const safetyRank = {'safe': 0, 'partial': 1, 'flooded': 2};
      evaluated.sort((a, b) {
        final aScore = safetyRank[a.safetyStatus] ?? 3;
        final bScore = safetyRank[b.safetyStatus] ?? 3;
        return aScore.compareTo(bScore);
      });

      // ── Step 4: Rename the top route to reflect its actual safety ──────────
      if (evaluated.isNotEmpty) {
        final top = evaluated[0];
        final topLabel = top.safetyStatus == 'safe'
            ? 'Safest Route'
            : top.safetyStatus == 'partial'
                ? 'Least Risky Route'
                : 'Only Available Route';
        evaluated[0] = PlannedRoute(
          points:       top.points,
          durationMin:  top.durationMin,
          distanceMiles: top.distanceMiles,
          summary:      topLabel,
          avoidedRoads: top.avoidedRoads,
          safetyStatus: top.safetyStatus,
          steps:        top.steps,
        );
      }

      routes.addAll(evaluated);

      // Always show routes even if none is fully safe — user needs navigation.
      // The safety badge on each card communicates the risk level.
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
      Position origin, Position dest) async {
    // Map vehicle type to the correct Mapbox routing profile
    String profile = 'driving';
    if (selectedVehicleType == 'Walking') {
      profile = 'walking';
    } else if (selectedVehicleType == 'Motorcycle') {
      profile = 'cycling'; // closest Mapbox profile
    }

    final url =
        'https://api.mapbox.com/directions/v5/mapbox/$profile/'
        '${origin.lng},${origin.lat};${dest.lng},${dest.lat}'
        '?alternatives=true'        // ← request all alternative routes
        '&geometries=polyline'
        '&overview=full'
        '&steps=true'
        '&access_token=$_publicToken';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(data['routes'] as List);
      }
    } else {
      debugPrint('[RoutingService] Mapbox error ${response.statusCode}: ${response.body}');
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
          if (maneuver != null) {
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

  Map<String, dynamic> _evaluateRouteSafety(List<Position> routePts, List<dynamic> allRoads) {
    List<String> avoided = [];
    String status = 'safe';

    if (routePts.isEmpty) return {'status': status, 'avoided': avoided};

    // Check if any route point passes within ~100m of a flooded road coordinate
    for (var road in allRoads) {
      if (road.status != 'passable' && road.geometry != null) {
        final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
        if (coordsDyn == null) continue;

        bool nearFlood = false;
        for (final c in coordsDyn) {
          final roadLon = (c['lon'] as num?)?.toDouble();
          final roadLat = (c['lat'] as num?)?.toDouble();
          if (roadLon == null || roadLat == null) continue;

          for (final pt in routePts) {
            final dLon = (pt.lng.toDouble() - roadLon).abs();
            final dLat = (pt.lat.toDouble() - roadLat).abs();
            // ~0.001 degree ≈ 111 metres
            if (dLon < 0.001 && dLat < 0.001) {
              nearFlood = true;
              break;
            }
          }
          if (nearFlood) break;
        }

        if (nearFlood) {
          status = road.status == 'not_passable' ? 'flooded' : 'partial';
          avoided.add(road.name);
        }
      }
    }

    return {
      'status': status,
      'avoided': avoided,
    };
  }

  List<Position> _decodePolyline(String encoded) {
    List<Position> points = [];
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

      points.add(Position(lng / 1E5, lat / 1E5));
    }
    return points;
  }
}
