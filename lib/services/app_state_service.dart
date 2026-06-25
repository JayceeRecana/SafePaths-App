import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin, sin, min;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';
import 'weather_service.dart';
import '../config/risk_config.dart';
import '../utils/coalescing_lock.dart';
import '../utils/geo_utils.dart';

// --- DATA MODELS ---

class RoadStatus {
  final String id;
  final String name;
  final String status; // 'passable', 'partial', 'not_passable'
  final String notes;
  final DateTime updatedAt;
  final Map<String, dynamic>? geometry;
  final int? confidence;
  final String vulnerability; // 'low', 'medium', 'high'
  
  // Predictive Risk Engine Properties
  final List<String> neighbors;
  final double riskScore;
  final String riskCategory; // 'Safe', 'Watch', 'Warning', 'Critical'
  final DateTime? warningStartTime;
  final String? propagationSource;
  
  final String source; // 'manual', 'osm'
  final bool isVerified;
  final DateTime? importedAt;

  RoadStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.notes,
    required this.updatedAt,
    this.geometry,
    this.confidence,
    this.vulnerability = 'medium', // Default is medium
    this.neighbors = const [],
    this.riskScore = 0.0,
    this.riskCategory = 'Safe',
    this.warningStartTime,
    this.propagationSource,
    this.source = 'manual',
    this.isVerified = false,
    this.importedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'notes': notes,
        'updatedAt': Timestamp.fromDate(updatedAt),
        if (geometry != null) 'geometry': geometry,
        if (confidence != null) 'confidence': confidence,
        'vulnerability': vulnerability,
        'neighbors': neighbors,
        'riskScore': riskScore,
        'riskCategory': riskCategory,
        if (warningStartTime != null) 'warningStartTime': Timestamp.fromDate(warningStartTime!),
        if (propagationSource != null) 'propagationSource': propagationSource,
        'source': source,
        'isVerified': isVerified,
        if (importedAt != null) 'importedAt': Timestamp.fromDate(importedAt!),
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
      vulnerability: json['vulnerability'] ?? 'medium',
      neighbors: json['neighbors'] != null ? List<String>.from(json['neighbors']) : [],
      riskScore: (json['riskScore'] as num?)?.toDouble() ?? 0.0,
      riskCategory: json['riskCategory'] ?? 'Safe',
      warningStartTime: json['warningStartTime'] != null ? (json['warningStartTime'] as Timestamp).toDate() : null,
      propagationSource: json['propagationSource'],
      source: json['source'] ?? 'manual',
      isVerified: json['isVerified'] ?? false,
      importedAt: json['importedAt'] != null ? (json['importedAt'] as Timestamp).toDate() : null,
    );
  }

  RoadStatus copyWith({
    String? status,
    String? notes,
    DateTime? updatedAt,
    Map<String, dynamic>? geometry,
    int? confidence,
    String? vulnerability,
    List<String>? neighbors,
    double? riskScore,
    String? riskCategory,
    DateTime? warningStartTime,
    String? source,
    bool? isVerified,
    DateTime? importedAt,
  }) =>
      RoadStatus(
        id: id,
        name: name,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        updatedAt: updatedAt ?? this.updatedAt,
        geometry: geometry ?? this.geometry,
        confidence: confidence ?? this.confidence,
        vulnerability: vulnerability ?? this.vulnerability,
        neighbors: neighbors ?? this.neighbors,
        riskScore: riskScore ?? this.riskScore,
        riskCategory: riskCategory ?? this.riskCategory,
        warningStartTime: warningStartTime ?? this.warningStartTime,
        propagationSource: propagationSource ?? this.propagationSource,
        source: source ?? this.source,
        isVerified: isVerified ?? this.isVerified,
        importedAt: importedAt ?? this.importedAt,
      );

  String getEffectiveStatus(WeatherState weatherState) {
    String effectiveStatus = status;
    bool isSevereWeather = weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon;
    
    if (effectiveStatus == 'passable' && isSevereWeather) {
      final hoursOld = DateTime.now().difference(updatedAt).inMinutes / 60.0;
      if (hoursOld > RiskConfig.passableStaleThresholdHours) {
        if (vulnerability == 'high') {
          effectiveStatus = 'not_passable';
        } else if (vulnerability == 'medium') {
          effectiveStatus = 'partial';
        }
      }
    }
    return effectiveStatus;
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String location;
  final String role;
  final int trustScore;
  final int verifiedReports;
  final int dismissedReports;

  UserProfile({
    required this.id,
    this.name = 'Resident',
    this.email = 'No Email',
    this.location = 'Brgy. Marulas',
    this.role = 'user',
    this.trustScore = 50,
    this.verifiedReports = 0,
    this.dismissedReports = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'location': location,
        'role': role,
        'trustScore': trustScore,
        'verifiedReports': verifiedReports,
        'dismissedReports': dismissedReports,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Resident',
      email: json['email'] ?? 'No Email',
      location: json['location'] ?? 'Brgy. Marulas',
      role: json['role'] ?? 'user',
      trustScore: json['trustScore'] ?? 50,
      verifiedReports: json['verifiedReports'] ?? 0,
      dismissedReports: json['dismissedReports'] ?? 0,
    );
  }
}

class UserReport {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final String severity; // 'Low', 'Medium', 'High'
  final String status; // 'pending', 'verified', 'dismissed'
  final String? roadId;
  final Map<String, dynamic>? location;
  final String userId;
  final double authorityScore;
  final double confidenceScore;
  final String? imageUrl;

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
        if (roadId != null) 'roadId': roadId,
        if (location != null) 'location': location,
        if (imageUrl != null) 'imageUrl': imageUrl,
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
      location: json['location'] as Map<String, dynamic>?,
      userId: json['userId'] ?? 'anonymous',
      authorityScore: (json['authorityScore'] as num?)?.toDouble() ?? 50.0,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  UserReport copyWith({
    String? status,
    String? roadId,
    Map<String, dynamic>? location,
  }) =>
      UserReport(
        id: id,
        title: title,
        description: description,
        createdAt: createdAt,
        severity: severity,
        status: status ?? this.status,
        roadId: roadId ?? this.roadId,
        location: location ?? this.location,
        userId: userId,
        authorityScore: authorityScore,
        confidenceScore: confidenceScore,
      );
}

class BroadcastAlert {
  final String id;
  final String title;
  final String message;
  final String severity; // 'Advisory', 'Warning', 'Critical'
  final String category; // 'EMERGENCY', 'WEATHER UPDATE', 'SYSTEM'
  final DateTime createdAt;
  bool get isActive => DateTime.now().difference(createdAt).inHours < 24;

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

class SystemActionLog {
  final DateTime timestamp;
  final String action;
  final String details;

  SystemActionLog({
    required this.timestamp,
    required this.action,
    required this.details,
  });
}

class AlertTemplate {
  final String id;
  final String label;
  final String title;
  final String message;
  final int severity;

  AlertTemplate({
    required this.id,
    required this.label,
    required this.title,
    required this.message,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'title': title,
        'message': message,
        'severity': severity,
      };

  factory AlertTemplate.fromJson(Map<String, dynamic> json) {
    return AlertTemplate(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? 0,
    );
  }
}

class AppStateService extends ChangeNotifier {

  static final AppStateService _instance = AppStateService._internal();
  static AppStateService get instance => _instance;

  AppStateService._internal();

  bool _initialized = false;
  bool get initialized => _initialized;
  final CoalescingLock _checksLock = CoalescingLock(delay: const Duration(seconds: 1));
  final List<StreamSubscription> _subscriptions = [];

  List<RoadStatus> _roads = [];
  List<UserReport> _reports = [];
  List<BroadcastAlert> _alerts = [];
  
  // Default custom templates
  List<AlertTemplate> _templates = [
    AlertTemplate(id: '1', label: 'Severe Flood', title: 'Severe Flood Warning', message: 'Please avoid low-lying areas immediately. Severe flooding is expected.', severity: 2),
    AlertTemplate(id: '2', label: 'Road Clearing', title: 'Road Clearing Operations', message: 'Clearing operations are ongoing. Expect heavy traffic and temporary blockages.', severity: 1),
    AlertTemplate(id: '3', label: 'Evacuation', title: 'Evacuation Notice', message: 'Immediate evacuation is strongly advised for residents in vulnerable areas.', severity: 2),
  ];
  List<AlertTemplate> get templates => _templates;

  Timer? _riskTimer;
  
  // Predictive Routing Engine
  Future<Map<String, dynamic>> buildAndVerifyRoadGraph() async {
    try {
      debugPrint('[AppStateService] Building Road Graph...');
      final snapshot = await FirebaseFirestore.instance.collection('roads').get();
      List<RoadStatus> tempRoads = snapshot.docs.map((d) => RoadStatus.fromJson({...d.data(), 'id': d.id})).toList();

      int orphanCount = 0;
      final validIds = tempRoads.map((r) => r.id).toSet();
      for (var road in tempRoads) {
        for (var nId in road.neighbors) {
          if (!validIds.contains(nId)) {
            orphanCount++;
          }
        }
      }

      int totalRoads = tempRoads.length;
      int totalConnections = 0;
      int disconnectedRoads = 0;

      // Reset neighbors
      for (int i = 0; i < tempRoads.length; i++) {
        tempRoads[i] = tempRoads[i].copyWith(neighbors: []);
      }

      // Check intersections
      for (int i = 0; i < tempRoads.length; i++) {
        final roadA = tempRoads[i];
        final ptsA = GeoUtils.extractPoints(roadA.geometry);
        if (ptsA.isEmpty) continue;

        Set<String> newNeighbors = {};

        for (int j = 0; j < tempRoads.length; j++) {
          if (i == j) continue;
          final roadB = tempRoads[j];
          final ptsB = GeoUtils.extractPoints(roadB.geometry);
          if (ptsB.isEmpty) continue;

          // Check if any point in B is very close to any SEGMENT of A (fixes T-junctions)
          bool intersects = false;
          for (final pB in ptsB) {
            for (int k = 0; k < ptsA.length - 1; k++) {
              final pA1 = ptsA[k];
              final pA2 = ptsA[k + 1];
              double dist = GeoUtils.pointToSegmentDistanceMeters(
                  pB.lng, pB.lat, pA1.lng, pA1.lat, pA2.lng, pA2.lat);
              if (dist < 25.0) { // 25 meters tolerance for T-junctions
                intersects = true;
                break;
              }
            }
            if (intersects) break;
          }

          if (!intersects) {
            // Check reverse: any point in A close to any segment in B
            for (final pA in ptsA) {
              for (int k = 0; k < ptsB.length - 1; k++) {
                final pB1 = ptsB[k];
                final pB2 = ptsB[k + 1];
                double dist = GeoUtils.pointToSegmentDistanceMeters(
                    pA.lng, pA.lat, pB1.lng, pB1.lat, pB2.lng, pB2.lat);
                if (dist < 25.0) {
                  intersects = true;
                  break;
                }
              }
              if (intersects) break;
            }
          }

          if (intersects) {
            newNeighbors.add(roadB.id);
          }
        }

        tempRoads[i] = roadA.copyWith(neighbors: newNeighbors.toList());
      }

      // Batch update Firestore and calculate metrics
      WriteBatch batch = FirebaseFirestore.instance.batch();
      
      int maxNeighbors = 0;
      List<String> disconnectedRoadNames = [];
      List<String> suspiciousRoads = [];
      int symmetryViolations = 0;

      // 1. Calculate symmetry violations
      for (var road in tempRoads) {
        for (var nId in road.neighbors) {
          final neighbor = tempRoads.firstWhere((r) => r.id == nId, orElse: () => road);
          if (neighbor.id != road.id && !neighbor.neighbors.contains(road.id)) {
            symmetryViolations++;
          }
        }
      }

      // 2. Calculate Connected Components
      Set<String> visited = {};
      int connectedComponents = 0;
      List<int> componentSizes = [];

      void dfs(String roadId) {
        visited.add(roadId);
        final road = tempRoads.firstWhere((r) => r.id == roadId);
        for (var nId in road.neighbors) {
          if (!visited.contains(nId)) {
            dfs(nId);
          }
        }
      }

      for (var road in tempRoads) {
        if (!visited.contains(road.id)) {
          int startSize = visited.length;
          dfs(road.id);
          componentSizes.add(visited.length - startSize);
          connectedComponents++;
        }
      }

      for (var road in tempRoads) {
        if (road.neighbors.isEmpty) {
          disconnectedRoads++;
          disconnectedRoadNames.add(road.name.isNotEmpty ? road.name : road.id);
        }
        if (road.neighbors.length > maxNeighbors) {
          maxNeighbors = road.neighbors.length;
        }
        if (road.neighbors.length > 8) {
          suspiciousRoads.add('${road.name.isNotEmpty ? road.name : road.id} (${road.neighbors.length})');
        }
        totalConnections += road.neighbors.length;
        
        final docRef = FirebaseFirestore.instance.collection('roads').doc(road.id);
        batch.update(docRef, {'neighbors': road.neighbors});
      }

      await batch.commit();

      double avgNeighbors = totalRoads > 0 ? (totalConnections / totalRoads) : 0;
      
      debugPrint('--- ADVANCED GRAPH INTEGRITY REPORT ---');
      debugPrint('Total Roads: $totalRoads');
      debugPrint('Total Connections: $totalConnections');
      debugPrint('Average Neighbors per Road: ${avgNeighbors.toStringAsFixed(2)}');
      debugPrint('Maximum Neighbors: $maxNeighbors');
      debugPrint('Disconnected Roads: $disconnectedRoads');
      debugPrint('Orphan References (cleaned): $orphanCount');
      if (disconnectedRoadNames.isNotEmpty) debugPrint('   -> ${disconnectedRoadNames.join(', ')}');
      debugPrint('Symmetry Violations: $symmetryViolations');
      debugPrint('Connected Components: $connectedComponents');
      debugPrint('   -> Component Sizes: ${componentSizes.join(', ')}');
      debugPrint('Suspicious Roads (>8 neighbors): ${suspiciousRoads.length}');
      if (suspiciousRoads.isNotEmpty) debugPrint('   -> ${suspiciousRoads.join(', ')}');
      debugPrint('---------------------------------------');

      return {
        'totalRoads': totalRoads,
        'avgNeighbors': avgNeighbors,
        'disconnectedRoads': disconnectedRoads,
        'maximumNeighbors': maxNeighbors,
        'connectedComponents': connectedComponents,
      };

    } catch (e) {
      debugPrint('[AppStateService] Error building road graph: $e');
      return {};
    }
  }

  bool _isUpdatingFloodRisk = false;

  Future<void> _updateFloodRisk() async {
    if (_isUpdatingFloodRisk) return;
    if (_roads.isEmpty) return;
    
    _isUpdatingFloodRisk = true;
    try {
      final stopwatch = Stopwatch()..start();
    
    final now = DateTime.now();
    final weatherState = SimulatedWeatherService.instance.currentState;
    
    double weatherMultiplier = 0.0;
    switch (weatherState) {
      case WeatherState.clear: weatherMultiplier = 0.0; break;
      case WeatherState.lightRain: weatherMultiplier = 0.2; break;
      case WeatherState.moderateRain: weatherMultiplier = 0.4; break;
      case WeatherState.heavyRain: weatherMultiplier = 0.7; break;
      case WeatherState.typhoon: weatherMultiplier = 1.0; break;
    }

    Map<String, double> previousRisks = { for (var r in _roads) r.id: r.riskScore };
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (var road in _roads) {
      // 1. Base Status Risk
      double baseRisk = 0.0;
      if (road.status == 'not_passable') baseRisk = 100.0;
      else if (road.status == 'partial') baseRisk = 50.0;
      else if (road.status == 'passable') baseRisk = 0.0;

      // 2. Consensus Risk (Pending Reports on this road)
      double consensusRisk = 0.0;
      final pendingReports = _reports.where((r) => r.roadId == road.id && r.status == 'pending');
      for (var report in pendingReports) {
        double conf = calculateLiveConfidence(report);
        if (report.severity == 'High') consensusRisk += (conf * 0.8);
        else if (report.severity == 'Medium') consensusRisk += (conf * 0.5);
        else if (report.severity == 'Low') consensusRisk += (conf * 0.2);
      }
      if (consensusRisk > 100) consensusRisk = 100;

      // 3. Propagation Risk (from neighbors)
      double maxNeighborRisk = 0.0;
      String? maxNeighborId;
      for (var nId in road.neighbors) {
        double nRisk = previousRisks[nId] ?? 0.0;
        if (nRisk > maxNeighborRisk) {
          maxNeighborRisk = nRisk;
          maxNeighborId = nId;
        }
      }

      double vulnerabilityMult = RiskConfig.lowVulnerability;
      if (road.vulnerability == 'high') vulnerabilityMult = RiskConfig.highVulnerability;
      else if (road.vulnerability == 'medium') vulnerabilityMult = RiskConfig.mediumVulnerability;

      double propagationRisk = maxNeighborRisk * weatherMultiplier * vulnerabilityMult;
      propagationRisk = min(propagationRisk, maxNeighborRisk * 0.95);

      // 4. Calculate Total Initial Risk
      double totalRisk = baseRisk + consensusRisk + propagationRisk;

      // 5. Time Escalation
      DateTime? newWarningStartTime = road.warningStartTime;
      double timeBonus = 0.0;

      // Start the timer if it enters WARNING category (>= 60.0)
      if (totalRisk >= RiskConfig.watchThreshold) {
        if (newWarningStartTime == null) {
          newWarningStartTime = now;
        } else {
          int minutesInWarning = now.difference(newWarningStartTime).inMinutes;
          if (minutesInWarning >= 60) timeBonus = RiskConfig.warning60MinuteBonus;
          else if (minutesInWarning >= 30) timeBonus = RiskConfig.warning30MinuteBonus;
          
          if (minutesInWarning > RiskConfig.predictionWindowMinutes) {
             // Expired Prediction decay
             timeBonus = -20.0;
          }
        }
      } else {
        newWarningStartTime = null; // Clear timer if it drops below Warning
      }

      // Final Score & Category
      double finalScore = (totalRisk + timeBonus).clamp(0.0, 100.0);
      
      String category = 'Safe';
      if (finalScore >= RiskConfig.warningThreshold) category = 'Critical';
      else if (finalScore >= RiskConfig.watchThreshold) category = 'Warning';
      else if (finalScore >= RiskConfig.safeThreshold) category = 'Watch';

      String? actualSourceId;
      if (maxNeighborRisk > baseRisk && maxNeighborRisk > consensusRisk && maxNeighborId != null) {
        actualSourceId = maxNeighborId;
      }

      // Update if changed
      if (finalScore != road.riskScore || category != road.riskCategory || newWarningStartTime != road.warningStartTime || actualSourceId != road.propagationSource) {
        batch.update(_db.collection('roads').doc(road.id), {
          'riskScore': finalScore,
          'riskCategory': category,
          'warningStartTime': newWarningStartTime != null ? Timestamp.fromDate(newWarningStartTime) : null,
          'propagationSource': actualSourceId,
        });

        // ONLY print if the road actually has risk, to avoid spamming the console
        if (finalScore > 0) {
          String propSource = "None";
          if (maxNeighborId != null) {
            final nRoad = _roads.firstWhere((r) => r.id == maxNeighborId, orElse: () => road);
            propSource = nRoad.name.isNotEmpty ? nRoad.name : maxNeighborId;
          }

          debugPrint('''
--- RISK REPORT ---
Road: ${road.name.isNotEmpty ? road.name : road.id}
Admin Status: ${road.status}
Risk Score: ${finalScore.toStringAsFixed(1)}
Risk Category: $category
Warning Start: ${newWarningStartTime?.toIso8601String() ?? 'N/A'}

Math Breakdown:
Base Risk: ${baseRisk.toStringAsFixed(1)}
Consensus Risk: ${consensusRisk.toStringAsFixed(1)}
Neighbor Risk: ${maxNeighborRisk.toStringAsFixed(1)} (Source: $propSource)
Weather Multiplier: $weatherMultiplier
Vulnerability Multiplier: $vulnerabilityMult
Time Bonus: $timeBonus
Final Risk: ${finalScore.toStringAsFixed(1)}

Propagation Applied: ${propagationRisk > 0 ? 'YES' : 'NO'}
-------------------''');
        }
      }
    }

      await batch.commit();
      stopwatch.stop();
      
      lastRiskEngineExecutionMs = stopwatch.elapsedMilliseconds;
      lastRiskEngineRun = DateTime.now();
      notifyListeners();

      debugPrint('\n--- RISK ENGINE ---');
      debugPrint('Roads: ${_roads.length}');
      debugPrint('Execution: ${lastRiskEngineExecutionMs} ms\n');
    } finally {
      _isUpdatingFloodRisk = false;
    }
  }



  // State maps
  int lastRiskEngineExecutionMs = 0;
  DateTime? lastRiskEngineRun;
  List<UserProfile> _users = [];
  final List<SystemActionLog> _systemLogs = [];
  final Map<String, DateTime> _lastAutoEscalation = {};
  final Map<String, Map<String, DateTime>> _lastReputationGain = {};

  List<RoadStatus> get roads => _roads;
  List<UserReport> get reports => _reports;
  List<BroadcastAlert> get alerts => _alerts;
  List<UserProfile> get users => _users;
  List<SystemActionLog> get systemLogs => List.unmodifiable(_systemLogs);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  Future<void> _loadEscalationTimestamps() async {
    try {
      final doc = await _db.collection('system').doc('escalation_log').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        data.forEach((roadId, value) {
          if (value is Timestamp) {
            _lastAutoEscalation[roadId] = value.toDate();
          }
        });
      }
    } catch (e) {
      debugPrint('[AppState] Failed to load escalation log: $e');
    }
  }

  Future<void> _saveEscalationTimestamp(String roadId, DateTime time) async {
    try {
      await _db.collection('system').doc('escalation_log').set(
        {roadId: Timestamp.fromDate(time)},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[AppState] Failed to save escalation log: $e');
    }
  }

  void _onWeatherChanged() {
    notifyListeners();
    _updateFloodRisk();
    _runAutomatedSystemChecks();
  }

  @override
  void dispose() {
    SimulatedWeatherService.instance.listenable.removeListener(_onWeatherChanged);
    _riskTimer?.cancel();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _riskTimer?.cancel();
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    try {
      await _loadEscalationTimestamps();

      _subscriptions.add(_db.collection('roads').snapshots().listen((snapshot) {
        _roads = snapshot.docs.map((doc) => RoadStatus.fromJson({...doc.data(), 'id': doc.id})).toList();
        notifyListeners();
      }));

      _subscriptions.add(_db.collection('reports').orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
        _reports = snapshot.docs.map((doc) => UserReport.fromJson({...doc.data(), 'id': doc.id})).toList();
        notifyListeners();
        _runAutomatedSystemChecks();
      }));

      _riskTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateFloodRisk());

      _subscriptions.add(_db.collection('alerts').orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
        _alerts = snapshot.docs.map((doc) => BroadcastAlert.fromJson({...doc.data(), 'id': doc.id})).toList();
        notifyListeners();
      }));

      _subscriptions.add(_db.collection('users').snapshots().listen((snapshot) {
        _users = snapshot.docs.map((doc) => UserProfile.fromJson({...doc.data(), 'id': doc.id})).toList();
        notifyListeners();
      }));

      SimulatedWeatherService.instance.listenable.addListener(_onWeatherChanged);

      notifyListeners();
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  void _runAutomatedSystemChecks() {
    _checksLock.run(() async {
      try {
      final now = DateTime.now();

      // 1. AUTO-EXPIRY: Archive pending reports older than 24 hours
      final expiredReports = _reports.where((r) => 
        r.status == 'pending' && now.difference(r.createdAt).inHours >= 24
      ).toList();
      
      if (expiredReports.isNotEmpty) {
        WriteBatch batch = _db.batch();
        for (var report in expiredReports) {
          batch.update(_db.collection('reports').doc(report.id), {'status': 'expired'});
        }
        await batch.commit();
      }

    // 2. AUTO-ESCALATION: High-confidence crowd consensus generates Admin Alerts
    for (var road in _roads) {
      final pendingReports = _reports.where((r) => r.roadId == road.id && r.status == 'pending').toList();
      final totalReports = pendingReports.length;
      if (totalReports < 3) continue;

      Map<String, int> severityCounts = {};
      for (var r in pendingReports) {
        severityCounts[r.severity] = (severityCounts[r.severity] ?? 0) + 1;
      }

      String dominantSeverity = '';
      int maxCount = 0;
      severityCounts.forEach((sev, count) {
        if (count > maxCount) {
          maxCount = count;
          dominantSeverity = sev;
        }
      });

      double maxAgreement = maxCount / totalReports;
      final consensusGroup = pendingReports.where((r) => r.severity == dominantSeverity).toList();

      // Check anti-spam cooldown for this road and alert type
      String alertActionType = maxAgreement >= 0.70 ? 'Consensus Alert' : 'Verification Alert';
      String logKey = '${road.id}_$alertActionType';
      
      bool recentAlertExists = false;
      if (_lastAutoEscalation.containsKey(logKey)) {
        if (now.difference(_lastAutoEscalation[logKey]!).inHours < 3) {
          recentAlertExists = true;
        }
      }

      if (recentAlertExists) continue;

      if (maxAgreement >= 0.70) {
        // Calculate average confidence of the consensus group
        double totalConfidence = 0.0;
        for (var report in consensusGroup) {
          totalConfidence += calculateLiveConfidence(report);
        }
        double avgConfidence = totalConfidence / consensusGroup.length;

        bool triggerVolume = consensusGroup.length >= 5;
        bool triggerConfidence = consensusGroup.length >= 3 && avgConfidence >= 85.0;

        // Threshold: 5+ reports OR 3+ reports with >=85 avg confidence
        if (triggerVolume || triggerConfidence) {
           String triggerReason = triggerVolume 
               ? 'Agreement >= 70% AND Reports >= 5' 
               : 'Agreement >= 70% AND AvgConfidence >= 85';

            _systemLogs.insert(0, SystemActionLog(
              timestamp: now,
              action: alertActionType,
              details: 'Crowd Consensus Alert: ${consensusGroup.length} residents report ${road.name} as $dominantSeverity. (Agreement: ${(maxAgreement*100).toStringAsFixed(0)}%). Admin verification requested.',
            ));
            notifyListeners();

            // Persist cooldown
            _lastAutoEscalation[logKey] = now;
            _saveEscalationTimestamp(logKey, now);

            // 💾 Save Audit Trail
            _db.collection('consensus_audits').add({
                'roadId': road.id,
                'roadName': road.name,
                'roadStatusAtTime': road.status,
                'timestamp': FieldValue.serverTimestamp(),
                'algorithmVersion': 'v2.0',
                'confidenceCalculationVersion': 'v1.0',
                'alertType': 'Consensus Alert',
                'triggerReason': triggerReason,
                'dominantSeverity': dominantSeverity,
                'agreementRate': maxAgreement,
                'averageConfidence': avgConfidence,
                'totalReports': totalReports,
                'consensusGroupSize': consensusGroup.length,
                'severityDistribution': severityCounts,
            });
        }
      } else if (maxAgreement >= 0.50) {
         // Split vote, Under Verification
         var sortedSeverities = severityCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
         String splitDetails = sortedSeverities.map((e) => '${e.value} ${e.key}').join(', ');
         
         _systemLogs.insert(0, SystemActionLog(
            timestamp: now,
            action: alertActionType,
            details: 'Road Under Verification: ${road.name} has conflicting reports ($splitDetails). Consensus not reached. Admin verification requested.',
          ));
          notifyListeners();

          // Persist cooldown
          _lastAutoEscalation[logKey] = now;
          _saveEscalationTimestamp(logKey, now);

          // 💾 Save Audit Trail
          _db.collection('consensus_audits').add({
              'roadId': road.id,
              'roadName': road.name,
              'roadStatusAtTime': road.status,
              'timestamp': FieldValue.serverTimestamp(),
              'algorithmVersion': 'v2.0',
              'alertType': 'Under Verification',
              'triggerReason': '50% <= Agreement < 70%',
              'dominantSeverity': dominantSeverity,
              'agreementRate': maxAgreement,
              'totalReports': totalReports,
              'severityDistribution': severityCounts,
          });
      }
    }

    // 3. WEATHER RISK ALERTS: Admin warnings
    final weatherState = SimulatedWeatherService.instance.currentState;
    if (weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon) {
      bool alerted = false;
      for (var road in _roads) {
        if (alerted) break;
        if (road.status != 'passable') continue;
        
        final hoursSinceUpdate = now.difference(road.updatedAt).inMinutes / 60.0;
        if (hoursSinceUpdate < 1.0) continue; // Match getEffectiveStatus() 1-hour TTL

        final roadReports = _reports.where((r) => r.roadId == road.id && r.status == 'pending');
        for (var report in roadReports) {
          if (calculateLiveConfidence(report) > 70.0) {
            // Trigger alert! Check if we already sent one recently to avoid spam
            final recentAlerts = _alerts.where((a) => a.category == 'SYSTEM' && a.title.contains('Heavy Rain'));
            if (recentAlerts.isNotEmpty && now.difference(recentAlerts.first.createdAt).inMinutes < 60) {
              alerted = true;
              break; // Already alerted recently
            }

            broadcastAlert(
              'Heavy Rain / Flood Risk',
              'Heavy rain detected. ${road.name} has pending flood reports with high confidence. Please verify immediately.',
              'Critical',
            );
            alerted = true;
            break;
          }
        }
      }
    }
    } catch (e) {
      debugPrint('[AppState] Error during automated checks: $e');
    }
  });
}

  Future<void> updateRoadStatus(
    String roadId,
    String status,
    String notes, {
    Map<String, dynamic>? geometry,
    String? name,
    String? vulnerability,
  }) async {
    final uid = await UserService.getUserId();
    String userName = 'Unknown';
    if (uid != 'anonymous') {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'Unknown Admin';
        }
      } catch (_) {}
    }

    final Map<String, dynamic> data = {
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'updatedByName': userName,
    };
    if (geometry != null) {
      data['geometry'] = geometry;
    }
    if (name != null) {
      data['name'] = name;
    }
    if (vulnerability != null) {
      data['vulnerability'] = vulnerability;
    }
    await _db.collection('roads').doc(roadId).set(data, SetOptions(merge: true))
        .timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('Unable to connect. Please check your internet connection.'));
  }

  Future<void> updateMultipleRoadStatus(
    Set<String> roadIds,
    String status,
    String notes, {
    String? vulnerability,
  }) async {
    final uid = await UserService.getUserId();
    String userName = 'Unknown';
    if (uid != 'anonymous') {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'Unknown Admin';
        }
      } catch (_) {}
    }

    final Map<String, dynamic> data = {
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'updatedByName': userName,
    };
    if (vulnerability != null) {
      data['vulnerability'] = vulnerability;
    }

    WriteBatch batch = _db.batch();
    for (String roadId in roadIds) {
      batch.set(_db.collection('roads').doc(roadId), data, SetOptions(merge: true));
    }

    await batch.commit().timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('Unable to connect. Please check your internet connection.'));
  }

  Future<void> deleteRoadStatus(String roadId) async {
    await _db.collection('roads').doc(roadId).delete();
  }

  Future<void> submitReport(String title, String description, String floodLevel, [String? roadId, Map<String, dynamic>? location]) async {
    final uid = await UserService.getUserId();
    
    if (uid == 'anonymous') {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = 'lastReportTime_anonymous_device';
      final lastTimeStr = prefs.getString(prefKey);
      if (lastTimeStr != null) {
        final lastTime = DateTime.parse(lastTimeStr);
        if (DateTime.now().difference(lastTime).inMinutes < 5) {
          throw Exception('SPAM_COOLDOWN');
        }
      }
      await prefs.setString(prefKey, DateTime.now().toIso8601String());
    } else {
      final userRef = _db.collection('users').doc(uid);
      final userDoc = await userRef.get();
      if (userDoc.exists) {
        final lastReportAt = userDoc.data()?['lastReportAt'];
        if (lastReportAt != null) {
          final lastTime = (lastReportAt as Timestamp).toDate();
          if (DateTime.now().difference(lastTime).inMinutes < 5) {
            throw Exception('SPAM_COOLDOWN');
          }
        }
      }
      await userRef.update({'lastReportAt': FieldValue.serverTimestamp()});
    }
    
    // Fetch actual trust score (authority)
    double authority = 50.0;
    try {
      if (uid != 'anonymous') {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists) {
          authority = (doc.data()?['trustScore'] as num?)?.toDouble() ?? 50.0;
        }
      }
    } catch (_) {}

    // 📸 Photo Verification Bonus (Proximity-Equivalent Bonus)
    // Providing photo evidence significantly boosts the report's authority.
    String? imageUrl;
    if (location != null && location.containsKey('imageUrl')) {
      imageUrl = location['imageUrl'];
      location.remove('imageUrl'); // keep geometry clean
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      authority = (authority + 30.0).clamp(0, 100);
    }

    // Single Active Report Per Road logic: update if exists
    if (roadId != null) {
      try {
        final existing = _reports.firstWhere(
            (r) => r.userId == uid && r.roadId == roadId && r.status == 'pending');
        await _db.collection('reports').doc(existing.id).update({
          'severity': floodLevel,
          'description': description,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByUser': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('Unable to connect. Please check your internet connection.'));
        return; // Exit, we don't want to create a duplicate
      } catch (e) {
        // No existing pending report found, continue to create a new one
      }
    }

    if (roadId != null && location != null && location.containsKey('lat') && location.containsKey('lng')) {
      try {
        final road = _roads.firstWhere((r) => r.id == roadId);
        double minDistance = double.infinity;
        double uLat = (location['lat'] as num).toDouble();
        double uLng = (location['lng'] as num).toDouble();
        
        if (road.geometry != null && road.geometry!['coordinates'] != null) {
          final coords = road.geometry!['coordinates'] as List<dynamic>;
          for (var coord in coords) {
            double? rLng, rLat;
            if (coord is Map) {
              rLng = (coord['lon'] as num?)?.toDouble() ?? (coord['lng'] as num?)?.toDouble();
              rLat = (coord['lat'] as num?)?.toDouble();
            } else if (coord is List && coord.length >= 2) {
              rLng = (coord[0] as num?)?.toDouble();
              rLat = (coord[1] as num?)?.toDouble();
            }
            if (rLng != null && rLat != null) {
              double dist = _calculateDistance(uLat, uLng, rLat, rLng);
              if (dist < minDistance) minDistance = dist;
            }
          }
        }
        
        if (minDistance != double.infinity && minDistance > 500) {
          throw Exception('OUT_OF_RANGE');
        }
      } catch (e) {
        if (e.toString() == 'Exception: OUT_OF_RANGE') rethrow;
      }
    }

    final data = {
      'title': title,
      'description': description,
      'severity': floodLevel,
      'status': 'pending',
      'userId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'authorityScore': authority,
      'confidenceScore': 0.0,
    };
    if (roadId != null) {
      data['roadId'] = roadId;
    }
    if (location != null) {
      data['location'] = location;
    }
    await _db.collection('reports').add(data)
        .timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('Unable to connect. Please check your internet connection.'));
  }

  Future<void> _updateUserReputation(String uid, int pointChange, bool isVerified) async {
    if (uid == 'anonymous') return;
    
    final docRef = _db.collection('users').doc(uid);
    final doc = await docRef.get();
    
    if (doc.exists) {
      final currentScore = doc.data()?['trustScore'] ?? 50;
      final currentVerified = doc.data()?['verifiedReports'] ?? 0;
      final currentDismissed = doc.data()?['dismissedReports'] ?? 0;
      
      int newScore = currentScore + pointChange;
      if (newScore > 100) newScore = 100;
      if (newScore < 0) newScore = 0;
      
      await docRef.update({
        'trustScore': newScore,
        'verifiedReports': isVerified ? currentVerified + 1 : currentVerified,
        'dismissedReports': !isVerified ? currentDismissed + 1 : currentDismissed,
      });
    } else {
      int newScore = 50 + pointChange;
      if (newScore > 100) newScore = 100;
      if (newScore < 0) newScore = 0;
      await docRef.set({
        'trustScore': newScore,
        'verifiedReports': isVerified ? 1 : 0,
        'dismissedReports': !isVerified ? 1 : 0,
      });
    }
  }

  Future<void> resolveReport(String reportId) async {
    final reportsFound = _reports.where((r) => r.id == reportId);
    if (reportsFound.isEmpty) return;
    final report = reportsFound.first;
    await _db.collection('reports').doc(reportId).update({'status': 'verified'});
    
    bool shouldGivePoints = true;
    if (report.roadId != null) {
      final userGains = _lastReputationGain[report.userId] ?? {};
      final lastGain = userGains[report.roadId!];
      if (lastGain != null && DateTime.now().difference(lastGain).inHours < 12) {
        shouldGivePoints = false;
      } else {
        userGains[report.roadId!] = DateTime.now();
        _lastReputationGain[report.userId] = userGains;
      }
    }
    
    await _updateUserReputation(report.userId, shouldGivePoints ? 5 : 0, true);
  }

  Future<void> dismissReport(String reportId) async {
    final reportsFound = _reports.where((r) => r.id == reportId);
    if (reportsFound.isEmpty) return;
    final report = reportsFound.first;
    await _db.collection('reports').doc(reportId).update({'status': 'dismissed'});
    await _updateUserReputation(report.userId, -15, false);
  }

  Future<void> addAlertTemplate(AlertTemplate template) async {
    _templates.add(template);
    notifyListeners();
  }

  Future<void> broadcastAlert(String title, String message, String severity) async {
    String category = 'EMERGENCY';
    if (severity == 'Advisory') {
      category = 'WEATHER UPDATE';
    } else if (severity == 'Warning') {
      category = 'SYSTEM';
    }

    final uid = await UserService.getUserId();
    String userName = 'System';
    if (uid != 'anonymous') {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'System';
        }
      } catch (_) {}
    }

    await _db.collection('alerts').add({
      'title': title,
      'message': message,
      'severity': severity,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': uid,
      'createdByName': userName,
    });
  }

  Future<void> clearAllAlerts() async {
    final snaps = await _db.collection('alerts').get();
    final docs = snaps.docs;
    
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _db.batch();
      final end = (i + 500 < docs.length) ? i + 500 : docs.length;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }

  Future<void> removeAlert(String alertId) async {
    if (_alerts.any((a) => a.id == alertId)) {
      await _db.collection('alerts').doc(alertId).delete();
    }
  }

  double calculateLiveConfidence(UserReport report) {
    return getLiveConfidenceBreakdown(report)['total'] as double;
  }

  Map<String, dynamic> getLiveConfidenceBreakdown(UserReport report) {
    // 1. Authority (Fetch dynamically from user's trust score)
    double authority = report.authorityScore;
    try {
      final userProfile = _users.firstWhere((u) => u.id == report.userId);
      authority = userProfile.trustScore.toDouble();
    } catch (e) {
      // Ignore if user profile isn't loaded
    }
    
    // Re-apply photo bonus live
    if (report.imageUrl != null && report.imageUrl!.isNotEmpty) {
      authority = (authority + 30.0).clamp(0, 100);
    }

    // Weather Multiplier (Contextual Advisor)
    final weatherState = SimulatedWeatherService.instance.currentState;

    // 2. Recency (Decay stretches during severe weather)
    final hoursOld = DateTime.now().difference(report.createdAt).inMinutes / 60.0;
    
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
    
    final officialRoad = _roads.firstWhere(
      (r) => r.id == report.roadId, 
      orElse: () => RoadStatus(id: '', name: '', status: '', notes: '', updatedAt: DateTime.now())
    );
    
    // Residual Flood check: only apply Clear Weather penalty if the official road status is currently passable.
    if (officialRoad.status == 'passable' || officialRoad.status.isEmpty) {
      if (weatherState == WeatherState.clear) weatherMultiplier = 0.85;
    }
    
    if (weatherState == WeatherState.lightRain) {
      weatherMultiplier = 1.05;
    } else if (weatherState == WeatherState.moderateRain) weatherMultiplier = 1.10;
    else if (weatherState == WeatherState.heavyRain) weatherMultiplier = 1.15;
    else if (weatherState == WeatherState.typhoon) weatherMultiplier = 1.25;

    // 3. Consensus (Base 0. Look for other reports on the same road)
    double consensus = 0.0;
    if (report.roadId != null) {
      final otherReports = _reports.where((r) => r.id != report.id && r.roadId == report.roadId && r.status == 'pending').toList();
      
      // Robust Troll Filter: Only count the most recent report per user within a 30-min window
      Map<String, UserReport> uniqueUserReports = {};
      for (var other in otherReports) {
        if (other.userId == 'anonymous') continue; // Skip anonymous for consensus to prevent spam
        
        final minDiff = report.createdAt.difference(other.createdAt).inMinutes.abs();
        if (minDiff > 30) continue; // Outside the consensus window

        if (!uniqueUserReports.containsKey(other.userId) || 
            other.createdAt.isAfter(uniqueUserReports[other.userId]!.createdAt)) {
          uniqueUserReports[other.userId] = other;
        }
      }

      if (uniqueUserReports.isNotEmpty) {
        consensus = 50.0;
        for (var other in uniqueUserReports.values) {
          if (other.severity == report.severity) {
            consensus += 25.0; // Boost for agreement
          } else {
            consensus -= 15.0; // Penalty for disagreement
          }
        }
      }
    }
    if (consensus > 100) consensus = 100;
    if (consensus < 0) consensus = 0;

    // 4. Proximity Bonus (Check GPS distance to the road)
    double proximity = 0.0;
    if (report.location != null && report.roadId != null) {
      final road = _roads.firstWhere(
        (r) => r.id == report.roadId, 
        orElse: () => RoadStatus(id: '', name: '', status: '', notes: '', updatedAt: DateTime.now())
      );
      if (road.id.isNotEmpty && road.geometry != null && road.geometry!['coordinates'] != null) {
        final coords = road.geometry!['coordinates'] as List<dynamic>;
        double minDistance = double.infinity;
        
        for (var coord in coords) {
          double? rLng, rLat;
          if (coord is Map) {
            rLng = (coord['lon'] as num?)?.toDouble();
            rLat = (coord['lat'] as num?)?.toDouble();
          } else if (coord is List && coord.length >= 2) {
            rLng = (coord[0] as num?)?.toDouble();
            rLat = (coord[1] as num?)?.toDouble();
          }
          if (rLng == null || rLat == null) continue;
            
          double dist = Geolocator.distanceBetween(
            (report.location!['lat'] as num).toDouble(),
            (report.location!['lng'] as num).toDouble(),
            rLat,
            rLng,
          );
            
            if (dist < minDistance) {
              minDistance = dist;
            }
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
        (consensus * weatherMultiplier * 0.3) + // only consensus is weather-sensitive
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
