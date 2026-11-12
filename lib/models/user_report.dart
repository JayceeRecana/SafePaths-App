import 'package:cloud_firestore/cloud_firestore.dart';

class ReportReply {
  final String message;
  final DateTime timestamp;
  final String sender;

  const ReportReply({
    required this.message,
    required this.timestamp,
    this.sender = 'Barangay Command Center',
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    'timestamp': Timestamp.fromDate(timestamp),
    'sender': sender,
  };

  factory ReportReply.fromJson(Map<String, dynamic> json) {
    dynamic t = json['timestamp'];
    DateTime date = t is Timestamp
        ? t.toDate()
        : (t is String
              ? DateTime.tryParse(t) ?? DateTime.now()
              : DateTime.now());
    return ReportReply(
      message: json['message'] ?? '',
      timestamp: date,
      sender: json['sender'] ?? 'Barangay Command Center',
    );
  }
}

class UserReport {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final String severity; // 'Low', 'Medium', 'High'
  final String
  status; // pending, under_review, verified, resolved, expired, dismissed
  final String? roadId;
  final Map<String, dynamic>? location;
  final String userId;
  final double authorityScore;
  final double confidenceScore;
  final String? imageUrl;
  final String? dismissReason; // 'spam_false', 'duplicate_resolved'
  final String? adminReply;
  final List<ReportReply> adminReplies;
  final DateTime? reviewedAt;
  final DateTime? reviewStartedAt;
  final bool isEmergency;
  final DateTime? lastUpdatedByUser;

  /// Latest server mutation known to this snapshot, including replies/reviews.
  final DateTime? recordUpdatedAt;
  final DateTime? observedAt;
  final String? incidentId;
  final int? pointsAwarded;
  final String? incidentReviewStatus;
  final bool hasAdminUpdates;
  final String? rootReportId, conditionChange;
  final String reportType;
  final DateTime? photoSubmittedAt;
  final Map<String, dynamic>? originalSubmission, rewardCorrection;
  final int followupCount;
  final String? clarificationRequestId;
  final DateTime? clarificationRequestedAt, clarificationRepliedAt;
  bool get awaitsResident => status == 'waiting_resident';
  bool get needsAdminReview => status == 'pending' || status == 'under_review';
  bool get reviewOpen => needsAdminReview || awaitsResident;
  bool get isFollowup => reportType == 'followup';
  bool get isHistoricalFollowup =>
      isFollowup && incidentReviewStatus == 'passable';
  String get historyRootId => isFollowup ? rootReportId ?? id : id;

  UserReport({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.severity,
    required this.status,
    this.roadId,
    this.location,
    required this.userId,
    this.authorityScore = 50.0,
    this.confidenceScore = 0.0,
    this.imageUrl,
    this.dismissReason,
    this.adminReply,
    this.adminReplies = const [],
    this.reviewedAt,
    this.reviewStartedAt,
    this.isEmergency = false,
    this.lastUpdatedByUser,
    this.recordUpdatedAt,
    this.observedAt,
    this.incidentId,
    this.pointsAwarded,
    this.incidentReviewStatus,
    this.hasAdminUpdates = false,
    this.rootReportId,
    this.conditionChange,
    this.reportType = 'original',
    this.photoSubmittedAt,
    this.originalSubmission,
    this.rewardCorrection,
    this.followupCount = 0,
    this.clarificationRequestId,
    this.clarificationRequestedAt,
    this.clarificationRepliedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'createdAt': Timestamp.fromDate(createdAt),
    'severity': severity,
    'status': status,
    'userId': userId,
    'authorityScore': authorityScore,
    'confidenceScore': confidenceScore,
    'isEmergency': isEmergency,
    if (observedAt != null) 'observedAt': Timestamp.fromDate(observedAt!),
    if (incidentId != null) 'incidentId': incidentId,
    if (pointsAwarded != null) 'pointsAwarded': pointsAwarded,
    if (incidentReviewStatus != null)
      'incidentReviewStatus': incidentReviewStatus,
    'hasAdminUpdates': hasAdminUpdates,
    'reportType': reportType,
    if (rootReportId != null) 'rootReportId': rootReportId,
    if (conditionChange != null) 'conditionChange': conditionChange,
    if (photoSubmittedAt != null)
      'photoSubmittedAt': Timestamp.fromDate(photoSubmittedAt!),
    if (originalSubmission != null) 'originalSubmission': originalSubmission,
    if (rewardCorrection != null) 'rewardCorrection': rewardCorrection,
    'followupCount': followupCount,
    if (clarificationRequestId != null)
      'clarificationRequestId': clarificationRequestId,
    if (clarificationRequestedAt != null)
      'clarificationRequestedAt': Timestamp.fromDate(clarificationRequestedAt!),
    if (clarificationRepliedAt != null)
      'clarificationRepliedAt': Timestamp.fromDate(clarificationRepliedAt!),
    if (roadId != null) 'roadId': roadId,
    if (location != null) 'location': location,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (dismissReason != null) 'dismissReason': dismissReason,
    if (adminReply != null) 'adminReply': adminReply,
    if (adminReplies.isNotEmpty)
      'adminReplies': adminReplies.map((r) => r.toJson()).toList(),
    if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
    if (reviewStartedAt != null)
      'reviewStartedAt': Timestamp.fromDate(reviewStartedAt!),
    if (recordUpdatedAt != null)
      'recordUpdatedAt': Timestamp.fromDate(recordUpdatedAt!),
    if (lastUpdatedByUser != null)
      'lastUpdatedByUser': Timestamp.fromDate(lastUpdatedByUser!),
  };

  factory UserReport.fromJson(Map<String, dynamic> json) {
    dynamic d = json['createdAt'];
    DateTime date = d is Timestamp
        ? d.toDate()
        : (d is String
              ? DateTime.tryParse(d) ?? DateTime.fromMillisecondsSinceEpoch(0)
              : DateTime.fromMillisecondsSinceEpoch(0));
    dynamic r = json['reviewedAt'];
    DateTime? revDate = r is Timestamp
        ? r.toDate()
        : (r is String ? DateTime.tryParse(r) : null);
    dynamic u = json['lastUpdatedByUser'];
    DateTime? updDate = u is Timestamp
        ? u.toDate()
        : (u is String ? DateTime.tryParse(u) : null);

    final legacyReply = json['adminReply'] as String?;
    List<ReportReply> replies = [];
    if (json['adminReplies'] is List) {
      replies = (json['adminReplies'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => ReportReply.fromJson(m))
          .toList();
    } else if (legacyReply != null && legacyReply.trim().isNotEmpty) {
      replies = [
        ReportReply(
          message: legacyReply,
          timestamp: revDate ?? date,
          sender: 'Barangay Command Center',
        ),
      ];
    }

    return UserReport(
      clarificationRequestId: json['clarificationRequestId'] as String?,
      clarificationRequestedAt: optionalDate(json['clarificationRequestedAt']),
      clarificationRepliedAt: optionalDate(json['clarificationRepliedAt']),
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      createdAt: date,
      severity: json['severity'] ?? 'Low',
      status: json['status'] ?? 'pending',
      roadId: json['roadId'] as String?,
      location: json['location'] as Map<String, dynamic>?,
      userId: json['userId'] ?? 'anonymous',
      authorityScore: (json['authorityScore'] as num?)?.toDouble() ?? 50.0,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl'] as String?,
      dismissReason: json['dismissReason'] as String?,
      adminReply: legacyReply,
      adminReplies: replies,
      reviewedAt: revDate,
      reviewStartedAt: optionalDate(json['reviewStartedAt']),
      isEmergency: json['isEmergency'] == true,
      lastUpdatedByUser: updDate,
      recordUpdatedAt: [
        date,
        if (revDate != null) revDate,
        if (updDate != null) updDate,
        for (final field in [
          'recordUpdatedAt',
          'updatedAt',
          'reviewStartedAt',
          'adminRepliedAt',
        ])
          if (optionalDate(json[field]) case final DateTime time) time,
      ].reduce((a, b) => a.isAfter(b) ? a : b),
      observedAt: json['observedAt'] is Timestamp
          ? (json['observedAt'] as Timestamp).toDate()
          : json['observedAt'] is String
          ? DateTime.tryParse(json['observedAt'])
          : null,
      incidentId: json['incidentId'] as String?,
      pointsAwarded: (json['pointsAwarded'] as num?)?.toInt(),
      incidentReviewStatus: json['incidentReviewStatus'] as String?,
      hasAdminUpdates: json['hasAdminUpdates'] == true,
      reportType: json['reportType'] == 'followup' ? 'followup' : 'original',
      rootReportId: json['rootReportId'] as String?,
      conditionChange: json['conditionChange'] as String?,
      photoSubmittedAt: optionalDate(json['photoSubmittedAt']),
      originalSubmission: json['originalSubmission'] is Map
          ? Map<String, dynamic>.from(json['originalSubmission'] as Map)
          : null,
      rewardCorrection: json['rewardCorrection'] is Map
          ? Map<String, dynamic>.from(json['rewardCorrection'] as Map)
          : null,
      followupCount: (json['followupCount'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? optionalDate(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is String
      ? DateTime.tryParse(value)
      : value is DateTime
      ? value
      : null;

  UserReport copyWith({
    String? title,
    String? description,
    String? severity,
    String? status,
    String? roadId,
    Map<String, dynamic>? location,
    String? imageUrl,
    String? dismissReason,
    String? adminReply,
    List<ReportReply>? adminReplies,
    DateTime? reviewedAt,
    bool? isEmergency,
    DateTime? lastUpdatedByUser,
    DateTime? observedAt,
    String? incidentId,
    int? pointsAwarded,
    String? incidentReviewStatus,
    bool? hasAdminUpdates,
  }) => UserReport(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    createdAt: createdAt,
    severity: severity ?? this.severity,
    status: status ?? this.status,
    roadId: roadId ?? this.roadId,
    location: location ?? this.location,
    userId: userId,
    authorityScore: authorityScore,
    confidenceScore: confidenceScore,
    imageUrl: imageUrl ?? this.imageUrl,
    dismissReason: dismissReason ?? this.dismissReason,
    adminReply: adminReply ?? this.adminReply,
    adminReplies: adminReplies ?? this.adminReplies,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewStartedAt: reviewStartedAt,
    isEmergency: isEmergency ?? this.isEmergency,
    lastUpdatedByUser: lastUpdatedByUser ?? this.lastUpdatedByUser,
    recordUpdatedAt: recordUpdatedAt,
    observedAt: observedAt ?? this.observedAt,
    incidentId: incidentId ?? this.incidentId,
    pointsAwarded: pointsAwarded ?? this.pointsAwarded,
    incidentReviewStatus: incidentReviewStatus ?? this.incidentReviewStatus,
    hasAdminUpdates: hasAdminUpdates ?? this.hasAdminUpdates,
    reportType: reportType,
    rootReportId: rootReportId,
    conditionChange: conditionChange,
    originalSubmission: originalSubmission,
    photoSubmittedAt: photoSubmittedAt,
    rewardCorrection: rewardCorrection,
    followupCount: followupCount,
  );
}

enum DismissReason { spam, duplicate }
