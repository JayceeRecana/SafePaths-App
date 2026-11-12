import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class RouteStep {
  final String instruction;
  final String modifier;
  final String type;
  final double distance;
  final Position location;
  final double? durationSeconds;
  final double? bearingBefore, bearingAfter;

  RouteStep({
    required this.instruction,
    required this.modifier,
    required this.type,
    required this.distance,
    required this.location,
    this.durationSeconds,
    this.bearingBefore,
    this.bearingAfter,
  });
}

class PlannedRoute {
  final List<Position> points;
  final int durationMin;
  final double? durationSeconds;
  final double distanceMiles;
  final double? distanceMeters;
  final String summary;

  /// Street names supplied by directions, kept apart from safety summaries.
  final List<String> roadNames;

  /// Roads with risk/hazard that this route actually CROSSES (previously misnamed avoidedRoads)
  final List<String> hazardAlerts;
  final List<String> routeExplanations;
  final String safetyStatus; // 'safe', 'partial', 'not_passable', 'critical'
  final int safetyScore;
  final double routeCost;
  final double totalRisk;
  final int? riskReductionPercentage;
  final int? timePenaltyMin;
  final List<RouteStep> steps;

  /// For the top/best route: how many hazardous roads it avoids vs. the worst baseline route
  final int realAvoidedCount;

  /// True if route crosses an impassable / not_passable road segment
  final bool isBlocked;
  final int unverifiedRoadCount;
  final String? vehicleType;
  final Position? requestedDestination;
  final String? destinationName;
  final bool outsideStudyArea;
  final Set<String> requestedAvoidRoadIds;

  PlannedRoute({
    required this.points,
    required this.durationMin,
    this.durationSeconds,
    required this.distanceMiles,
    this.distanceMeters,
    required this.summary,
    this.roadNames = const [],
    required this.hazardAlerts,
    this.routeExplanations = const [],
    required this.safetyStatus,
    this.safetyScore = 100,
    this.routeCost = 0.0,
    this.totalRisk = 0.0,
    this.riskReductionPercentage,
    this.timePenaltyMin,
    required this.steps,
    this.realAvoidedCount = 0,
    this.isBlocked = false,
    this.unverifiedRoadCount = 0,
    this.vehicleType,
    this.requestedDestination,
    this.destinationName,
    this.outsideStudyArea = false,
    this.requestedAvoidRoadIds = const {},
  });

  PlannedRoute copyWith({
    String? summary,
    List<String>? hazardAlerts,
    List<String>? routeExplanations,
    String? safetyStatus,
    int? safetyScore,
    double? routeCost,
    double? totalRisk,
    bool? isBlocked,
    int? unverifiedRoadCount,
    String? destinationName,
    bool? outsideStudyArea,
    bool clearComparison = false,
  }) => PlannedRoute(
    points: points,
    durationMin: durationMin,
    durationSeconds: durationSeconds,
    distanceMiles: distanceMiles,
    distanceMeters: distanceMeters,
    summary: summary ?? this.summary,
    roadNames: roadNames,
    hazardAlerts: hazardAlerts ?? this.hazardAlerts,
    routeExplanations: routeExplanations ?? this.routeExplanations,
    safetyStatus: safetyStatus ?? this.safetyStatus,
    safetyScore: safetyScore ?? this.safetyScore,
    routeCost: routeCost ?? this.routeCost,
    totalRisk: totalRisk ?? this.totalRisk,
    steps: steps,
    isBlocked: isBlocked ?? this.isBlocked,
    unverifiedRoadCount: unverifiedRoadCount ?? this.unverifiedRoadCount,
    riskReductionPercentage: clearComparison ? null : riskReductionPercentage,
    timePenaltyMin: clearComparison ? null : timePenaltyMin,
    realAvoidedCount: clearComparison ? 0 : realAvoidedCount,
    vehicleType: vehicleType,
    requestedDestination: requestedDestination,
    destinationName: destinationName ?? this.destinationName,
    outsideStudyArea: outsideStudyArea ?? this.outsideStudyArea,
    requestedAvoidRoadIds: requestedAvoidRoadIds,
  );

  /// Navigation cannot be started on physically blocked/closed routes.
  bool get canStartNavigation =>
      !isBlocked &&
      points.length >= 2 &&
      points.every(
        (p) =>
            p.lat.isFinite &&
            p.lng.isFinite &&
            p.lat.abs() <= 90 &&
            p.lng.abs() <= 180,
      ) &&
      points.any((p) => p.lat != points.first.lat || p.lng != points.first.lng);

  bool get hasUnverifiedConditions =>
      outsideStudyArea ||
      unverifiedRoadCount > 0 ||
      safetyStatus == 'unverified_risk';

  bool get needsCaution =>
      hasUnverifiedConditions ||
      totalRisk > 0 ||
      hazardAlerts.isNotEmpty ||
      safetyStatus != 'safe';

  String get safetyScoreLabel =>
      hasUnverifiedConditions ? 'Unconfirmed' : 'Route score $safetyScore/100';

  String get conditionSummary {
    if (outsideStudyArea)
      return 'Parts of this route are outside the monitored study area. Flood conditions there are unconfirmed.';
    if (hasUnverifiedConditions) {
      return 'Current road conditions are unconfirmed. Check local updates before travel.';
    }
    if (!needsCaution) {
      return 'Clear of known flood reports; conditions may change.';
    }
    if (['partial', 'passable_partial'].contains(safetyStatus)) {
      return 'Flooding is reported along this route. Confirm local passability before travel.';
    }
    return 'This route crosses reported or predicted flood hazards.';
  }
}
