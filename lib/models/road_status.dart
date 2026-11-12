import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/weather_service.dart';
import '../config/risk_config.dart';

class RoadStatus {
  final String id;
  final String name;
  final String
  status; // 'passable', 'partial', 'not_passable', or unknown legacy data.
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
  final String? communityCondition;
  final String? activeIncidentId;

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
    this.communityCondition,
    this.activeIncidentId,
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
    if (warningStartTime != null)
      'warningStartTime': Timestamp.fromDate(warningStartTime!),
    if (propagationSource != null) 'propagationSource': propagationSource,
    'source': source,
    'isVerified': isVerified,
    if (importedAt != null) 'importedAt': Timestamp.fromDate(importedAt!),
    if (communityCondition != null) 'communityCondition': communityCondition,
    if (activeIncidentId != null) 'activeIncidentId': activeIncidentId,
  };

  factory RoadStatus.fromJson(Map<String, dynamic> json) {
    dynamic d = json['updatedAt'];
    DateTime date = d is Timestamp
        ? d.toDate()
        : (d is String ? DateTime.parse(d) : DateTime.now());
    return RoadStatus(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'unknown',
      notes: json['notes'] ?? '',
      updatedAt: date,
      geometry: json['geometry'] as Map<String, dynamic>?,
      confidence: json['confidence'] as int?,
      vulnerability: json['vulnerability'] ?? 'medium',
      neighbors: json['neighbors'] != null
          ? List<String>.from(json['neighbors'])
          : [],
      riskScore: (json['riskScore'] as num?)?.toDouble() ?? 0.0,
      riskCategory: json['riskCategory'] ?? 'Safe',
      warningStartTime: json['warningStartTime'] != null
          ? (json['warningStartTime'] as Timestamp).toDate()
          : null,
      propagationSource: json['propagationSource'],
      source: json['source'] ?? 'manual',
      isVerified: json['isVerified'] ?? false,
      importedAt: json['importedAt'] != null
          ? (json['importedAt'] as Timestamp).toDate()
          : null,
      communityCondition: json['communityCondition'] as String?,
      activeIncidentId: json['activeIncidentId'] as String?,
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
    String? communityCondition,
    String? activeIncidentId,
  }) => RoadStatus(
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
    propagationSource: propagationSource,
    source: source ?? this.source,
    isVerified: isVerified ?? this.isVerified,
    importedAt: importedAt ?? this.importedAt,
    communityCondition: communityCondition ?? this.communityCondition,
    activeIncidentId: activeIncidentId ?? this.activeIncidentId,
  );

  bool get hasUnresolvedCommunityIncident => const [
    'reported_flooding',
    'under_verification',
    'outdated',
    'admin_confirmed',
  ].contains(communityCondition);

  bool needsStatusConfirmation(
    WeatherState weatherState, {
    DateTime? currentTime,
  }) =>
      !const ['passable', 'partial', 'not_passable'].contains(status) ||
      status == 'passable' &&
          getEffectiveStatus(weatherState, currentTime: currentTime) !=
              'passable';

  String getEffectiveStatus(
    WeatherState weatherState, {
    DateTime? currentTime,
  }) {
    String effectiveStatus = status;
    bool isSevereWeather =
        weatherState == WeatherState.heavyRain ||
        weatherState == WeatherState.typhoon;

    if (effectiveStatus == 'passable' && isSevereWeather) {
      final hoursOld =
          (currentTime ?? DateTime.now()).difference(updatedAt).inMinutes /
          60.0;
      final staleThreshold = RiskConfig.getPassableStaleThresholdHours(
        vulnerability,
      );
      if (hoursOld > staleThreshold) {
        if (vulnerability == 'high') {
          // Increase caution for stale data; needsStatusConfirmation keeps
          // weather-derived restrictions separate from recorded closures.
          effectiveStatus = weatherState == WeatherState.typhoon
              ? 'not_passable'
              : 'partial';
        } else if (vulnerability == 'medium') {
          effectiveStatus = 'partial';
        }
      }
    }
    // Preserve known closures and severe-weather restrictions. An old report
    // disappearing from the risk calculation must not turn a road green.
    if (effectiveStatus == 'passable' &&
        (hasUnresolvedCommunityIncident || source == 'osm' && !isVerified)) {
      return 'partial';
    }
    return effectiveStatus;
  }
}
