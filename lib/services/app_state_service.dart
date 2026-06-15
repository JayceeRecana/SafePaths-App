import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- DATA MODELS ---

class RoadStatus {
  final String id;
  final String name;
  final String status; // 'passable', 'partial', 'not_passable'
  final String notes;
  final DateTime updatedAt;
  final Map<String, dynamic>? geometry;
  final int? confidence;

  RoadStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.notes,
    required this.updatedAt,
    this.geometry,
    this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'notes': notes,
        'updatedAt': Timestamp.fromDate(updatedAt),
        if (geometry != null) 'geometry': geometry,
        if (confidence != null) 'confidence': confidence,
      };

  factory RoadStatus.fromJson(Map<String, dynamic> json) {
    dynamic d = json['updatedAt'];
    DateTime date = d is Timestamp ? d.toDate() : (d is String ? DateTime.parse(d) : DateTime.now());
    return RoadStatus(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'passable',
      notes: json['notes'] ?? '',
      updatedAt: date,
      geometry: json['geometry'] as Map<String, dynamic>?,
      confidence: json['confidence'] as int?,
    );
  }

  RoadStatus copyWith({
    String? status,
    String? notes,
    DateTime? updatedAt,
    Map<String, dynamic>? geometry,
    int? confidence,
  }) =>
      RoadStatus(
        id: id,
        name: name,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        updatedAt: updatedAt ?? this.updatedAt,
        geometry: geometry ?? this.geometry,
        confidence: confidence ?? this.confidence,
      );
}

class UserReport {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final String severity; // 'Low', 'Medium', 'High'
  final String status; // 'pending', 'verified', 'dismissed'
  final String? roadId;

  UserReport({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.severity,
    required this.status,
    this.roadId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': Timestamp.fromDate(createdAt),
        'severity': severity,
        'status': status,
        if (roadId != null) 'roadId': roadId,
      };

  factory UserReport.fromJson(Map<String, dynamic> json) {
    dynamic d = json['createdAt'];
    DateTime date = d is Timestamp ? d.toDate() : (d is String ? DateTime.parse(d) : DateTime.now());
    return UserReport(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      createdAt: date,
      severity: json['severity'] ?? 'Low',
      status: json['status'] ?? 'pending',
      roadId: json['roadId'] as String?,
    );
  }

  UserReport copyWith({
    String? status,
    String? roadId,
  }) =>
      UserReport(
        id: id,
        title: title,
        description: description,
        createdAt: createdAt,
        severity: severity,
        status: status ?? this.status,
        roadId: roadId ?? this.roadId,
      );
}

class BroadcastAlert {
  final String id;
  final String title;
  final String message;
  final String severity; // 'Advisory', 'Warning', 'Critical'
  final String category; // 'EMERGENCY', 'WEATHER UPDATE', 'SYSTEM'
  final DateTime createdAt;

  BroadcastAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.category,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'severity': severity,
        'category': category,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory BroadcastAlert.fromJson(Map<String, dynamic> json) {
    dynamic d = json['createdAt'];
    DateTime date = d is Timestamp ? d.toDate() : (d is String ? DateTime.parse(d) : DateTime.now());
    return BroadcastAlert(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? 'Advisory',
      category: json['category'] ?? 'EMERGENCY',
      createdAt: date,
    );
  }
}

class AppStateService extends ChangeNotifier {

  static final AppStateService _instance = AppStateService._internal();
  static AppStateService get instance => _instance;

  AppStateService._internal();

  bool _initialized = false;
  bool get initialized => _initialized;

  List<RoadStatus> _roads = [];
  List<UserReport> _reports = [];
  List<BroadcastAlert> _alerts = [];

  List<RoadStatus> get roads => _roads;
  List<UserReport> get reports => _reports;
  List<BroadcastAlert> get alerts => _alerts;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> initialize() async {
    if (_initialized) return;

    _db.collection('roads').snapshots().listen((snapshot) {
      _roads = snapshot.docs.map((doc) => RoadStatus.fromJson({...doc.data(), 'id': doc.id})).toList();
      notifyListeners();
    });

    _db.collection('reports').orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
      _reports = snapshot.docs.map((doc) => UserReport.fromJson({...doc.data(), 'id': doc.id})).toList();
      notifyListeners();
    });

    _db.collection('alerts').orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
      _alerts = snapshot.docs.map((doc) => BroadcastAlert.fromJson({...doc.data(), 'id': doc.id})).toList();
      notifyListeners();
    });


    _initialized = true;
    notifyListeners();
  }

  Future<void> updateRoadStatus(
    String roadId,
    String status,
    String notes, {
    Map<String, dynamic>? geometry,
    String? name,
  }) async {
    final Map<String, dynamic> data = {
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (geometry != null) {
      data['geometry'] = geometry;
    }
    if (name != null) {
      data['name'] = name;
    }
    await _db.collection('roads').doc(roadId).set(data, SetOptions(merge: true));
  }

  Future<void> submitReport(String title, String description, String floodLevel, [String? roadId]) async {
    final data = {
      'title': title,
      'description': description,
      'severity': floodLevel,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (roadId != null) {
      data['roadId'] = roadId;
    }
    await _db.collection('reports').add(data);
  }

  Future<void> resolveReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({'status': 'verified'});
  }

  Future<void> dismissReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({'status': 'dismissed'});
  }

  Future<void> broadcastAlert(String title, String message, String severity) async {
    String category = 'EMERGENCY';
    if (severity == 'Advisory') {
      category = 'WEATHER UPDATE';
    } else if (severity == 'Warning') {
      category = 'SYSTEM';
    }

    await _db.collection('alerts').add({
      'title': title,
      'message': message,
      'severity': severity,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearAllAlerts() async {
    final batch = _db.batch();
    final snaps = await _db.collection('alerts').get();
    for (var doc in snaps.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> removeAlert(int index) async {
    if (index >= 0 && index < _alerts.length) {
      await _db.collection('alerts').doc(_alerts[index].id).delete();
    }
  }


}
