import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class RouteStep {
  final String instruction;
  final String modifier;
  final String type;
  final double distance;
  final Position location;

  RouteStep({
    required this.instruction,
    required this.modifier,
    required this.type,
    required this.distance,
    required this.location,
  });
}

class PlannedRoute {
  final List<Position> points;
  final int durationMin;
  final double distanceMiles;
  final String summary;
  final List<String> avoidedRoads;
  final String safetyStatus; // 'safe', 'partial', 'not_passable'
  final List<RouteStep> steps;

  PlannedRoute({
    required this.points,
    required this.durationMin,
    required this.distanceMiles,
    required this.summary,
    required this.avoidedRoads,
    required this.safetyStatus,
    required this.steps,
  });
}
