import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackModel {
  final String id;
  final String category;
  final int rating;
  final String comments;
  final bool hasAttachment;
  final bool allowFollowUp;
  final DateTime timestamp;
  final String? userId;
  final String? imageUrl;
  final String status; // 'new', 'reviewed', 'resolved'

  final String? adminReply;
  final DateTime? reviewedAt;
  final String? adminUid;

  FeedbackModel({
    required this.id,
    required this.category,
    required this.rating,
    required this.comments,
    this.hasAttachment = false,
    this.allowFollowUp = false,
    required this.timestamp,
    this.userId,
    this.imageUrl,
    this.status = 'new',
    this.adminReply,
    this.reviewedAt,
    this.adminUid,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'rating': rating,
    'comments': comments,
    'hasAttachment': hasAttachment,
    'allowFollowUp': allowFollowUp,
    'timestamp': Timestamp.fromDate(timestamp),
    'userId': userId,
    'imageUrl': imageUrl,
    'status': status,
    if (adminReply != null) 'adminReply': adminReply,
    if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
    if (adminUid != null) 'adminUid': adminUid,
  };

  factory FeedbackModel.fromJson(Map<String, dynamic> json, String documentId) {
    dynamic rev = json['reviewedAt'];
    DateTime? reviewedDate = rev is Timestamp
        ? rev.toDate()
        : (rev is String ? DateTime.tryParse(rev) : null);
    dynamic ts = json['timestamp'];
    DateTime timestampDate = ts is Timestamp
        ? ts.toDate()
        : (ts is String ? DateTime.parse(ts) : DateTime.now());

    return FeedbackModel(
      id: documentId,
      category: json['category'] as String? ?? 'General Feedback',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comments: json['comments'] as String? ?? '',
      hasAttachment: json['hasAttachment'] as bool? ?? false,
      allowFollowUp: json['allowFollowUp'] as bool? ?? false,
      timestamp: timestampDate,
      userId: json['userId'] as String?,
      imageUrl: json['imageUrl'] as String?,
      status: json['status'] as String? ?? 'new',
      adminReply: json['adminReply'] as String?,
      reviewedAt: reviewedDate,
      adminUid: json['adminUid'] as String?,
    );
  }

  FeedbackModel copyWith({
    String? category,
    int? rating,
    String? comments,
    bool? hasAttachment,
    bool? allowFollowUp,
    DateTime? timestamp,
    String? userId,
    String? imageUrl,
    String? status,
    String? adminReply,
    DateTime? reviewedAt,
    String? adminUid,
  }) {
    return FeedbackModel(
      id: id,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      comments: comments ?? this.comments,
      hasAttachment: hasAttachment ?? this.hasAttachment,
      allowFollowUp: allowFollowUp ?? this.allowFollowUp,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      adminReply: adminReply ?? this.adminReply,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      adminUid: adminUid ?? this.adminUid,
    );
  }
}
