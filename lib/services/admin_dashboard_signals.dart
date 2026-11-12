import '../models/road_status.dart';
import 'sync_health.dart';

/// Presentation of existing model output only. Never changes road conditions.
class AdminPredictionSummary {
  final List<RoadStatus> roads;
  final DateTime? computedAt;
  final DateTime now;
  final SyncCondition riskSync;
  final bool roadsLive, weatherFresh, drill;
  const AdminPredictionSummary({
    required this.roads,
    required this.computedAt,
    required this.now,
    required this.riskSync,
    required this.roadsLive,
    required this.weatherFresh,
    required this.drill,
  });
  bool get knownTime =>
      computedAt != null &&
      !computedAt!.isAfter(now) &&
      computedAt!.year > 1970;
  bool get current =>
      !drill &&
      roads.isNotEmpty &&
      knownTime &&
      now.difference(computedAt!) < const Duration(minutes: 5) &&
      riskSync == SyncCondition.live &&
      roadsLive &&
      weatherFresh;
  String get label => drill
      ? 'Weather drill active'
      : current
      ? 'Current model output'
      : 'Predictions not confirmed';
  int count(String category) =>
      roads.where((r) => r.riskCategory == category).length;
}
