import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of a broadcast alert operation with three-way outcome.
class BroadcastResult {
  final bool alertSaved;
  final bool pushSent;
  final String? pushError;
  final String? alertId;
  final int queuedCount;

  BroadcastResult({
    required this.alertSaved,
    this.pushSent = false,
    this.pushError,
    this.alertId,
    this.queuedCount = 0,
  });
}

class BroadcastAlert {
  final String id;
  final String title;
  final String message;
  final String severity; // 'Advisory', 'Warning', 'Critical'
  final String category; // 'EMERGENCY', 'WEATHER UPDATE', 'SYSTEM'
  final DateTime createdAt;
  final String? roadId;
  final String? roadName;
  final String? studyArea;
  final DateTime? expiresAt;
  final bool withdrawn;
  final String? withdrawalReason;
  DateTime get activeUntil =>
      expiresAt ?? createdAt.add(const Duration(hours: 24));
  bool isActiveAt(DateTime now) => !withdrawn && now.isBefore(activeUntil);
  bool get isActive => isActiveAt(DateTime.now());

  BroadcastAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.category,
    required this.createdAt,
    this.roadId,
    this.roadName,
    this.studyArea,
    this.expiresAt,
    this.withdrawn = false,
    this.withdrawalReason,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'severity': severity,
    'category': category,
    'createdAt': Timestamp.fromDate(createdAt),
    if (roadId != null) 'roadId': roadId,
    if (roadName != null) 'roadName': roadName,
    if (studyArea != null) 'studyArea': studyArea,
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    if (withdrawn) 'status': 'withdrawn',
    if (withdrawalReason != null) 'withdrawalReason': withdrawalReason,
  };

  factory BroadcastAlert.fromJson(Map<String, dynamic> json) {
    DateTime? readTime(dynamic value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : value is String
        ? DateTime.tryParse(value)
        : null;
    final date =
        readTime(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return BroadcastAlert(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? '',
      category: json['category'] ?? 'EMERGENCY',
      createdAt: date,
      roadId: json['roadId'] as String?,
      roadName: json['roadName'] as String?,
      studyArea: json['studyArea'] as String?,
      expiresAt: readTime(json['expiresAt']),
      withdrawn: json['status'] == 'withdrawn',
      withdrawalReason: json['withdrawalReason'] as String?,
    );
  }
}
