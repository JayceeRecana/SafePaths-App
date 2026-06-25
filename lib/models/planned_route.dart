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
  final List<String> routeExplanations;
  final String safetyStatus; // 'safe', 'partial', 'not_passable', 'critical'
  final int safetyScore;
  final double routeCost;
  final double totalRisk;
  final int? riskReductionPercentage;
  final int? timePenaltyMin;
  final List<RouteStep> steps;

  PlannedRoute({
    required this.points,
    required this.durationMin,
    required this.distanceMiles,
    required this.summary,
    required this.avoidedRoads,
    this.routeExplanations = const [],
    required this.safetyStatus,
    this.safetyScore = 100,
    this.routeCost = 0.0,
    this.totalRisk = 0.0,
    this.riskReductionPercentage,
    this.timePenaltyMin,
    required this.steps,
  });
}
