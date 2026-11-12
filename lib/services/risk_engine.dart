import 'dart:math' show min, max;
import 'package:geolocator/geolocator.dart';
import '../config/risk_config.dart';
import '../utils/report_freshness.dart';
import '../models/road_status.dart';
import '../models/user_report.dart';
import '../utils/geo_utils.dart';
import 'weather_service.dart';

class RoadRiskResult {
  final double finalScore;
  final String riskCategory;
  final DateTime? warningStartTime;
  final String? propagationSource;
  final double baseRisk;
  final double consensusRisk;
  final double propagationRisk;
  final double timeBonus;

  RoadRiskResult({
    required this.finalScore,
    required this.riskCategory,
    this.warningStartTime,
    this.propagationSource,
    required this.baseRisk,
    required this.consensusRisk,
    required this.propagationRisk,
    required this.timeBonus,
  });
}

class RiskEngine {
  /// Pure predictive risk calculation function for a single road.
  /// Supports Dependency Injection of [currentTime] for deterministic unit testing.
  static RoadRiskResult calculateRoadRisk({
    required RoadStatus road,
    required List<RoadStatus> allRoads,
    required List<UserReport> pendingReports,
    required WeatherState weatherState,
    Map<String, double>? previousRisks,
    DateTime? currentTime,
    double Function(UserReport)? confidenceCalculator,
  }) {
    final now = currentTime ?? DateTime.now();
    final weatherMultiplier = RiskConfig.getWeatherMultiplier(weatherState);

    // 1. Base Status Risk
    double baseRisk = 0.0;
    if (road.status == 'not_passable') {
      baseRisk = 100.0;
    } else if (road.status == 'partial') {
      baseRisk = 50.0;
    } else if (road.status == 'passable') {
      baseRisk = 0.0;
    }

    // 2. Consensus Risk (Pending Reports on this road)
    double consensusRisk = 0.0;
    final latestByUser = <String, UserReport>{};
    for (final report in pendingReports) {
      if (report.roadId != road.id ||
          report.isHistoricalFollowup ||
          ![
            'pending',
            'under_review',
            'waiting_resident',
          ].contains(report.status) ||
          ReportFreshness.isOutdated(report, now))
        continue;
      final previous = latestByUser[report.userId];
      if (previous == null ||
          ReportFreshness.observedAt(
            report,
          ).isAfter(ReportFreshness.observedAt(previous)) ||
          (ReportFreshness.observedAt(report) ==
                  ReportFreshness.observedAt(previous) &&
              report.id.compareTo(previous.id) > 0)) {
        latestByUser[report.userId] = report;
      }
    }
    final roadReports = latestByUser.values;
    for (var report in roadReports) {
      double conf = confidenceCalculator != null
          ? confidenceCalculator(report)
          : calculateLiveConfidence(
              report: report,
              allRoads: allRoads,
              pendingReports: pendingReports,
              weatherState: weatherState,
              currentTime: now,
            );
      if (report.severity == 'High') {
        consensusRisk += (conf * 0.8);
      } else if (report.severity == 'Medium') {
        consensusRisk += (conf * 0.5);
      } else if (report.severity == 'Low') {
        consensusRisk += (conf * 0.2);
      }
    }
    if (consensusRisk > 100) consensusRisk = 100;

    // 3. Propagation Risk (from neighbors)
    double maxNeighborRisk = 0.0;
    String? maxNeighborId;
    final riskMap =
        previousRisks ?? {for (var r in allRoads) r.id: r.riskScore};

    for (var nId in road.neighbors) {
      double nRisk = riskMap[nId] ?? 0.0;
      if (nRisk > maxNeighborRisk) {
        maxNeighborRisk = nRisk;
        maxNeighborId = nId;
      }
    }

    double vulnerabilityMult = RiskConfig.lowVulnerability;
    if (road.vulnerability == 'high') {
      vulnerabilityMult = RiskConfig.highVulnerability;
    } else if (road.vulnerability == 'medium') {
      vulnerabilityMult = RiskConfig.mediumVulnerability;
    }

    double propagationRisk =
        maxNeighborRisk * weatherMultiplier * vulnerabilityMult;
    propagationRisk = min(propagationRisk, maxNeighborRisk * 0.95);

    // 4. Calculate Total Initial Risk (capped at 100.0 before applying temporal modifiers)
    double totalRisk = (baseRisk + consensusRisk + propagationRisk).clamp(
      0.0,
      100.0,
    );

    // 5. Time Escalation
    DateTime? newWarningStartTime = road.warningStartTime;
    double timeBonus = 0.0;

    // Start the timer if it enters WATCH/WARNING category
    if (totalRisk >= RiskConfig.watchThreshold) {
      newWarningStartTime ??= road.updatedAt;

      int minutesInWarning = now.difference(newWarningStartTime).inMinutes;
      if (minutesInWarning > RiskConfig.predictionWindowMinutes) {
        // Expired Prediction decay
        timeBonus = -20.0;
      } else if (minutesInWarning >= 60) {
        timeBonus = RiskConfig.warning60MinuteBonus;
      } else if (minutesInWarning >= 30) {
        timeBonus = RiskConfig.warning30MinuteBonus;
      }
    } else {
      newWarningStartTime = null; // Clear timer if it drops below Watch
    }

    // Final Score & Category
    double finalScore = (totalRisk + timeBonus).clamp(0.0, 100.0);
    if (road.hasUnresolvedCommunityIncident &&
        finalScore < RiskConfig.safeThreshold) {
      finalScore = RiskConfig.safeThreshold;
    }

    String category = 'Safe';
    if (finalScore >= RiskConfig.warningThreshold) {
      category = 'Critical';
    } else if (finalScore >= RiskConfig.watchThreshold) {
      category = 'Warning';
    } else if (finalScore >= RiskConfig.safeThreshold) {
      category = 'Watch';
    }

    String? actualSourceId;
    if (maxNeighborRisk > baseRisk &&
        maxNeighborRisk > consensusRisk &&
        maxNeighborId != null) {
      actualSourceId = maxNeighborId;
    }

    return RoadRiskResult(
      finalScore: finalScore,
      riskCategory: category,
      warningStartTime: newWarningStartTime,
      propagationSource: actualSourceId,
      baseRisk: baseRisk,
      consensusRisk: consensusRisk,
      propagationRisk: propagationRisk,
      timeBonus: timeBonus,
    );
  }

  /// Calculates dynamic live confidence score (0-100) for a report.
  static double calculateLiveConfidence({
    required UserReport report,
    required List<RoadStatus> allRoads,
    required List<UserReport> pendingReports,
    required WeatherState weatherState,
    DateTime? currentTime,
  }) {
    final breakdown = calculateLiveConfidenceBreakdown(
      report: report,
      allRoads: allRoads,
      pendingReports: pendingReports,
      weatherState: weatherState,
      currentTime: currentTime,
    );
    return breakdown['total'] as double;
  }

  /// Calculates the mathematical confidence breakdown for a given report.
  static Map<String, dynamic> calculateLiveConfidenceBreakdown({
    required UserReport report,
    required List<RoadStatus> allRoads,
    required List<UserReport> pendingReports,
    required WeatherState weatherState,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();

    // 1. Authority Base Score
    double authority = report.authorityScore.clamp(0.0, 100.0);

    // 2. Time Recency Decay
    final hoursOld = max(
      0,
      now.difference(ReportFreshness.observedAt(report)).inMinutes / 60.0,
    );

    double decayWindowHours = 12.0; // default clear weather
    switch (weatherState) {
      case WeatherState.lightRain:
        decayWindowHours = 16.0;
        break;
      case WeatherState.moderateRain:
        decayWindowHours = 20.0;
        break;
      case WeatherState.heavyRain:
        decayWindowHours = 28.0;
        break;
      case WeatherState.typhoon:
        decayWindowHours = 36.0;
        break;
      default:
        break;
    }

    double recency = 100.0 - (hoursOld * (100.0 / decayWindowHours));
    if (recency < 0) recency = 0;

    double weatherMultiplier = 1.0;

    final officialRoad = allRoads.firstWhere(
      (r) => r.id == report.roadId,
      orElse: () =>
          RoadStatus(id: '', name: '', status: '', notes: '', updatedAt: now),
    );

    // Residual Flood check: only apply Clear Weather penalty if the official road status is currently passable.
    if (officialRoad.status == 'passable' || officialRoad.status.isEmpty) {
      if (weatherState == WeatherState.clear) weatherMultiplier = 0.85;
    }

    if (weatherState == WeatherState.lightRain) {
      weatherMultiplier = 1.05;
    } else if (weatherState == WeatherState.moderateRain) {
      weatherMultiplier = 1.10;
    } else if (weatherState == WeatherState.heavyRain) {
      weatherMultiplier = 1.15;
    } else if (weatherState == WeatherState.typhoon) {
      weatherMultiplier = 1.25;
    }

    // 3. Consensus (Base 0. Look for other reports on the same road)
    double consensus = 0.0;
    if (report.roadId != null) {
      final otherReports = pendingReports
          .where(
            (r) =>
                r.id != report.id &&
                !r.isHistoricalFollowup &&
                r.userId != report.userId &&
                r.roadId == report.roadId &&
                [
                  'pending',
                  'under_review',
                  'waiting_resident',
                ].contains(r.status) &&
                !ReportFreshness.isOutdated(r, now),
          )
          .toList();

      // Robust Troll Filter: Only count the most recent report per user within a 30-min window
      Map<String, UserReport> uniqueUserReports = {};
      for (var other in otherReports) {
        final minDiff = ReportFreshness.observedAt(
          report,
        ).difference(ReportFreshness.observedAt(other)).inMinutes.abs();
        if (minDiff > 30) continue; // Outside the consensus window

        if (!uniqueUserReports.containsKey(other.userId) ||
            ReportFreshness.observedAt(other).isAfter(
              ReportFreshness.observedAt(uniqueUserReports[other.userId]!),
            )) {
          uniqueUserReports[other.userId] = other;
        }
      }

      if (uniqueUserReports.isNotEmpty) {
        consensus = 50.0;
        for (var other in uniqueUserReports.values) {
          // Weight consensus impact by reporter authority score to prevent Sybil consensus fabrication
          final authWeight = (other.authorityScore / 100.0).clamp(0.2, 1.0);
          if (other.severity == report.severity) {
            consensus +=
                25.0 * authWeight; // Boost for agreement weighted by trust
          } else {
            consensus -=
                15.0 * authWeight; // Penalty for disagreement weighted by trust
          }
        }
      }
    }
    if (consensus > 100) consensus = 100;
    if (consensus < 0) consensus = 0;

    // 4. Proximity Bonus (Check GPS distance to the road)
    double proximity = 0.0;
    if (report.location != null && report.roadId != null) {
      final road = allRoads.firstWhere(
        (r) => r.id == report.roadId,
        orElse: () =>
            RoadStatus(id: '', name: '', status: '', notes: '', updatedAt: now),
      );
      if (road.id.isNotEmpty && road.geometry != null) {
        final geoPts = GeoUtils.extractPoints(road.geometry);
        double minDistance = double.infinity;
        double uLat = (report.location!['lat'] as num).toDouble();
        double uLng = (report.location!['lng'] as num).toDouble();

        for (var pt in geoPts) {
          double dist = Geolocator.distanceBetween(uLat, uLng, pt.lat, pt.lng);
          if (dist < minDistance) minDistance = dist;
        }

        if (minDistance < double.infinity) {
          if (minDistance <= 50) {
            proximity = 20.0;
          } else if (minDistance <= 500) {
            proximity = 10.0;
          } else if (minDistance >= 2000) {
            proximity = -20.0;
          }
        }
      }
    }

    // The Math: Confidence = (Authority × 0.5) + (Consensus × 0.3) + (Recency × 0.2) + Proximity
    double baseConfidence =
        (authority * 0.5) +
        (consensus *
            weatherMultiplier *
            0.3) + // only consensus is weather-sensitive
        (recency * 0.2);

    double confidence = baseConfidence + proximity;

    if (confidence > 100) confidence = 100;
    if (confidence < 0) confidence = 0;

    return {
      'authority': authority,
      'authorityContribution': authority * 0.5,
      'recency': recency,
      'recencyContribution': recency * 0.2,
      'consensus': consensus,
      'consensusContribution': consensus * weatherMultiplier * 0.3,
      'weatherMultiplier': weatherMultiplier,
      'proximity': proximity,
      'total': confidence,
    };
  }
}
