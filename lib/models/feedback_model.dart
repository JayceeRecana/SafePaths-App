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

  FeedbackModel({
    required this.id,
    required this.category,
    required this.rating,
    required this.comments,
    this.hasAttachment = false,
    this.allowFollowUp = true,
    required this.timestamp,
    this.userId,
    this.imageUrl,
    this.status = 'new',
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
      };

  factory FeedbackModel.fromJson(Map<String, dynamic> json, String documentId) => FeedbackModel(
        id: documentId,
        category: json['category'] as String,
        rating: json['rating'] as int,
        comments: json['comments'] as String,
        hasAttachment: json['hasAttachment'] as bool? ?? false,
        allowFollowUp: json['allowFollowUp'] as bool? ?? true,
        timestamp: (json['timestamp'] as Timestamp).toDate(),
        userId: json['userId'] as String?,
        imageUrl: json['imageUrl'] as String?,
        status: json['status'] as String? ?? 'new',
      );
}
