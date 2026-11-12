import '../config/risk_config.dart';
import '../models/road_status.dart';
import '../models/user_report.dart';
import '../utils/time_utils.dart';
import 'report_workload.dart';
import 'weather_service.dart';

/// Admin presentation only. Never writes road data or changes routing policy.
class AdminRoadAssessment {
  final RoadStatus road;
  final DateTime now;
  final WeatherState weather;
  final bool verificationKnown;
  AdminRoadAssessment(
    this.road,
    this.now,
    this.weather, {
    this.verificationKnown = true,
  });
  bool get knownStatus =>
      const ['passable', 'partial', 'not_passable'].contains(road.status);
  bool get knownTime =>
      TimeUtils.hasRecordedTime(road.updatedAt) && !road.updatedAt.isAfter(now);
  bool get stale {
    if (!knownTime) return true;
    final storm = const [
      WeatherState.moderateRain,
      WeatherState.heavyRain,
      WeatherState.typhoon,
    ].contains(weather);
    final hours = road.status == 'passable' && storm
        ? RiskConfig.getPassableStaleThresholdHours(road.vulnerability)
        : RiskConfig.getAdminReCheckThresholdHours(road.vulnerability);
    return now.difference(road.updatedAt).inMilliseconds >= hours * 3600000;
  }

  bool get needsCheck =>
      !knownStatus ||
      !verificationKnown ||
      !road.isVerified ||
      stale ||
      road.needsStatusConfirmation(weather, currentTime: now) ||
      const [
        'reported_flooding',
        'under_verification',
        'outdated',
      ].contains(road.communityCondition);
  // A recorded restriction remains visible, even when it needs another check.
  // A passable label requires current, verified information.
  String get category => const ['partial', 'not_passable'].contains(road.status)
      ? road.status
      : road.status == 'passable' && !needsCheck
      ? 'passable'
      : 'unconfirmed';
  String get label => switch (category) {
    'not_passable' => 'Not passable',
    'partial' => 'Partially passable',
    'passable' => 'Passable',
    _ => 'Unconfirmed',
  };
  // Explain current uncertainty before exposing a historical status. Imported
  // defaults are not a past barangay check; restrictions never expire into green.
  bool get currentConditionUnknown => category == 'unconfirmed';
  String get summaryTitle => currentConditionUnknown
      ? 'Current condition unknown'
      : needsCheck
      ? (road.status == 'not_passable'
            ? 'Last recorded: Not passable'
            : 'Last recorded: Partially passable')
      : label;
  String? get summaryExplanation {
    if (!knownStatus) return 'No usable road condition is recorded.';
    if (!verificationKnown)
      return 'Barangay verification details are unavailable for this record.';
    if (!road.isVerified)
      return road.source == 'osm'
          ? 'No barangay verification is recorded for this map data.'
          : 'No verified barangay check is recorded.';
    if (!knownTime)
      return 'The check time is missing or invalid. Check this road again.';
    if (const [
      'reported_flooding',
      'under_verification',
    ].contains(road.communityCondition))
      return 'Resident observations need a new barangay check.';
    if (stale) return 'A new barangay check is needed.';
    if (needsCheck)
      return 'Check this road again before confirming its condition.';
    return null;
  }

  String get historyLabel =>
      !verificationKnown || !road.isVerified || !knownStatus
      ? (road.source == 'osm' ? 'Map record saved' : 'Road record saved')
      : currentConditionUnknown && road.status == 'passable'
      ? 'Last confirmed passable'
      : 'Last barangay check';
}

class AdminRoadOverview {
  final List<AdminRoadAssessment> roads;
  AdminRoadOverview(
    Iterable<RoadStatus> records,
    DateTime now,
    WeatherState weather,
  ) : roads = records
          .map((road) => AdminRoadAssessment(road, now, weather))
          .toList();
  int count(String category) =>
      roads.where((r) => r.category == category).length;
  List<AdminRoadAssessment> get checks =>
      roads.where((r) => r.needsCheck).toList()..sort(compareAdminRoads);
}

/// Describes graph connectivity only, never backend or push availability.
String adminGraphHealth({
  required bool roadsLive,
  required int roads,
  required int disconnected,
}) {
  if (!roadsLive || roads <= 0) return 'Not confirmed';
  if (disconnected == 0) return 'No isolated roads';
  return disconnected > roads * .2 ? 'Needs review' : 'Some gaps';
}

int compareAdminRoads(AdminRoadAssessment a, AdminRoadAssessment b) {
  if (a.needsCheck != b.needsCheck) return a.needsCheck ? -1 : 1;
  int rank(String category) => switch (category) {
    'not_passable' => 0,
    'partial' => 1,
    'unconfirmed' => 2,
    _ => 3,
  };
  final status = rank(a.category).compareTo(rank(b.category));
  if (status != 0) return status;
  if (a.needsCheck && b.needsCheck) {
    if (a.knownTime != b.knownTime) return a.knownTime ? 1 : -1;
    final age = a.road.updatedAt.compareTo(b.road.updatedAt);
    if (age != 0) return age;
  }
  final name = a.road.name.compareTo(b.road.name);
  return name == 0 ? a.road.id.compareTo(b.road.id) : name;
}

Map<String, ReportWorkload> reportsByRoad(Iterable<UserReport> reports) {
  final groups = <String, List<UserReport>>{};
  for (final report in reports) {
    if (report.roadId != null && report.reviewOpen) {
      groups.putIfAbsent(report.roadId!, () => []).add(report);
    }
  }
  return groups.map((key, value) => MapEntry(key, ReportWorkload(value)));
}
