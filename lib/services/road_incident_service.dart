import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/road_incident.dart';
import 'backend_service.dart';
import '../config/app_environment.dart';
import 'spark_backend_service.dart';
import 'core_operation_repository.dart';

class RoadIncidentSnapshot {
  final RoadIncident? incident;
  final bool fromCache;
  const RoadIncidentSnapshot(this.incident, {this.fromCache = false});
}

class RoadIncidentService {
  static final coreOperations = CoreOperationRepository(
    environment: AppEnvironment.name,
    account: () =>
        FirebaseAuth.instance.currentUser?.uid ??
        (throw StateError('Please sign in again.')),
    call: (operation, data) async {
      final client = SparkBackendService.createClient();
      try {
        return await client.coreCall(operation, data);
      } finally {
        client.close();
      }
    },
  );
  static Stream<RoadIncidentSnapshot> watch(String roadId) => FirebaseFirestore
      .instance
      .collection('road_incidents')
      .doc(roadId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (doc) => RoadIncidentSnapshot(
          doc.exists ? RoadIncident.fromJson(doc.id, doc.data()!) : null,
          fromCache: doc.metadata.isFromCache,
        ),
      );

  static Future<void> _call(String name, Map<String, dynamic> data) async {
    if (AppEnvironment.sparkCoreEnabled) {
      if (name != 'observeRoadIncident')
        throw StateError('Use the current administrator review screen.');
      return coreOperations.run('observe-incident', data);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    final prefs = await SharedPreferences.getInstance();
    final key =
        'incident_request_${base64UrlEncode(utf8.encode(jsonEncode([uid, name, data])))}';
    Map<String, dynamic>? pending;
    try {
      final saved = prefs.getString(key);
      if (saved != null) pending = jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {}
    final requestId =
        pending?['requestId'] as String? ??
        base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', '');
    final operation = <String, dynamic>{
      'requestId': requestId,
      if (name == 'observeRoadIncident')
        'observedAt':
            pending?['observedAt'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    final serialized = jsonEncode(operation);
    await prefs.setString(key, serialized);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Account changed. Please try again.');
    }
    try {
      await BackendService.call(name, {...data, ...operation});
    } catch (error) {
      if (error.toString().contains('OBSERVATION_STALE') &&
          prefs.getString(key) == serialized) {
        await prefs.remove(key);
        throw StateError(
          'This observation is too old to send as current. Observe conditions safely and submit again.',
        );
      }
      rethrow;
    }
    if (prefs.getString(key) == serialized) await prefs.remove(key);
  }

  static Future<void> observe(RoadIncident incident, String choice) =>
      _call('observeRoadIncident', {
        'roadId': incident.roadId,
        'incidentId': incident.incidentId,
        'choice': choice,
      });

  static Future<void> review(
    RoadIncident incident,
    String roadStatus,
    String note,
  ) => _call('reviewRoadIncident', {
    'roadId': incident.roadId,
    'incidentId': incident.incidentId,
    'revision': incident.revision,
    'roadStatus': roadStatus,
    'note': note,
    'verifiedCurrentConditions': true,
  });
}
