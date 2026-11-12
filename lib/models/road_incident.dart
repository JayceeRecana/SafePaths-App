import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/report_freshness.dart';

class RoadIncident {
  final String roadId;
  final String incidentId;
  final String state;
  final int revision;
  final DateTime? lastObservedAt;
  final DateTime? lastConfirmedAt;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final Map<String, int> counts;
  final bool reviewRequired;

  const RoadIncident({
    required this.roadId,
    required this.incidentId,
    required this.state,
    required this.revision,
    this.lastObservedAt,
    this.lastConfirmedAt,
    this.reviewedAt,
    this.reviewNote,
    this.counts = const {},
    this.reviewRequired = true,
  });

  static DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is String
      ? DateTime.tryParse(value)
      : null;

  factory RoadIncident.fromJson(String roadId, Map<String, dynamic> json) =>
      RoadIncident(
        roadId: roadId,
        incidentId: json['incidentId'] as String,
        state: json['state'] as String,
        revision: (json['revision'] as num).toInt(),
        lastObservedAt: _date(json['lastObservedAt']),
        lastConfirmedAt: _date(json['lastConfirmedAt']),
        reviewedAt: _date(json['reviewedAt']),
        reviewNote: json['reviewNote'] as String?,
        reviewRequired: json['reviewRequired'] == true,
        counts: {
          for (final entry in (json['counts'] as Map? ?? {}).entries)
            entry.key.toString(): (entry.value as num).toInt(),
        },
      );

  bool isOutdated(DateTime now) =>
      state != 'resolved' &&
      (state == 'outdated' ||
          lastObservedAt == null ||
          now.difference(lastObservedAt!) >= ReportFreshness.maximumAge ||
          lastObservedAt!.isAfter(now.add(const Duration(minutes: 1))));

  String label(DateTime now) {
    if (state == 'resolved') return 'Admin verified passable';
    if (isOutdated(now)) return 'Outdated — current condition unknown';
    if (state == 'under_verification') return 'Under verification';
    if (state == 'admin_confirmed') return 'Admin confirmed flooding';
    return 'Reported flooding — admin review needed';
  }
}
