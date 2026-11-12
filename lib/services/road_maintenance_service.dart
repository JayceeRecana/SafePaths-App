import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_environment.dart';
import 'communication_service.dart';
import 'spark_backend_service.dart';

/// The migrated test path only; no private credential or main-project fallback.
class RoadMaintenanceService {
  static final repository = CommunicationRepository(
    environment:
        '${AppEnvironment.name}|${SparkBackendService.configuration.firebaseProjectId}|${SparkBackendService.configuration.backend}',
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async {
      if (!await (await SharedPreferences.getInstance()).setString(key, value))
        throw StateError('Could not preserve this maintenance request.');
    },
    remove: (key) async {
      await (await SharedPreferences.getInstance()).remove(key);
    },
    call: (operation, data) async {
      final client = SparkBackendService.createClient();
      try {
        return await client.roadCall(operation, data);
      } finally {
        client.close();
      }
    },
  );
  static void enabled() {
    if (!AppEnvironment.sparkCoreEnabled)
      throw StateError('Use the configured SafePaths Test app.');
  }

  static Future<Map<String, dynamic>> deleteContext(String id) async {
    enabled();
    final uid = FirebaseAuth.instance.currentUser?.uid,
        client = SparkBackendService.createClient();
    try {
      final result = await client.roadCall('road-delete-context', {
        'roadId': id,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result['roadId'] != id ||
          result['ownerUid'] != uid ||
          result['canDelete'] is! bool ||
          result['name'] is! String ||
          result['reason'] is! String ||
          result['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['token'] as String))
        throw StateError('Refresh the current road before deletion.');
      return result;
    } finally {
      client.close();
    }
  }

  static Future<void> delete(String id, String token) async {
    enabled();
    await repository.run('road-delete', {
      'roadId': id,
      'contextToken': token,
      'confirmed': true,
    });
  }

  static Future<Map<String, dynamic>> rebuild() async {
    enabled();
    final result = await repository.run('road-graph-rebuild', {});
    return Map<String, dynamic>.from(result['graphStats'] as Map);
  }

  static Future<Map<String, dynamic>> importRoads(
    List<Map<String, dynamic>> roads,
  ) async {
    enabled();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var created = 0, skipped = 0;
    Map<String, dynamic> stats = {};
    for (var at = 0; at < roads.length; at += 10) {
      if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed. Reopen road import.');
      final result = await repository.run('road-import', {
        'roads': roads.sublist(at, (at + 10).clamp(0, roads.length)),
      });
      created += result['createdCount'] as int;
      skipped += result['skippedCount'] as int;
      stats = Map<String, dynamic>.from(result['graphStats'] as Map);
    }
    return {
      'createdCount': created,
      'skippedCount': skipped,
      'graphStats': stats,
    };
  }
}
