import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_environment.dart';
import 'spark_backend_service.dart';
import 'spark_proof_client.dart';

/// Persists opaque retry/context tokens, never feedback or alert contents.
class CommunicationRepository {
  final String environment;
  final String? Function() currentUid;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  final Map<String, Future<Map<String, dynamic>>> _pending = {};
  final Set<String> _confirmed = {};
  CommunicationRepository({
    required this.environment,
    required this.currentUid,
    required this.read,
    required this.write,
    required this.remove,
    required this.call,
  });

  Future<Map<String, dynamic>> run(
    String operation,
    Map<String, dynamic> data,
  ) {
    final uid = currentUid();
    if (uid == null) throw StateError('Please sign in again.');
    final payload = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(data)) as Map,
    );
    final intent = Map<String, dynamic>.from(payload)..remove('contextToken');
    final key =
        'communication_request_${sha256.convert(utf8.encode(jsonEncode([environment, uid, operation, intent])))}';
    return _pending.putIfAbsent(
      key,
      () => _run(key, uid, operation, payload).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<Map<String, dynamic>> _run(
    String key,
    String uid,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    Map<String, dynamic> saved = {};
    final stored = await read(key);
    try {
      saved = Map<String, dynamic>.from(jsonDecode(stored ?? '{}') as Map);
    } catch (_) {}
    final prior = saved['requestId'];
    if (prior is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(prior) ||
        saved['confirmed'] == true ||
        payload.containsKey('contextToken') &&
            (saved['contextToken'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(saved['contextToken'] as String)) ||
        _confirmed.contains(prior)) {
      saved = {
        'requestId': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
        if (payload['contextToken'] is String)
          'contextToken': payload['contextToken'],
      };
    }
    final serialized = jsonEncode(saved);
    await write(key, serialized);
    if (currentUid() != uid)
      throw StateError('Account changed. Please try again.');
    Map<String, dynamic> result;
    try {
      result = await call(operation, {...payload, ...saved});
    } on SparkProofException catch (e) {
      if (e.code == 'failed-precondition') {
        try {
          if (await read(key) == serialized) await remove(key);
        } catch (_) {}
      }
      rethrow;
    }
    if (currentUid() != uid)
      throw StateError('Account changed. Refresh the latest information.');
    if (result['saved'] != true ||
        result['operation'] != operation ||
        result['resourceId'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(result['resourceId'] as String) ||
        result['revision'] is! int ||
        (result['revision'] as int) < 1 ||
        result['replay'] is! bool ||
        result['notification'] != 'saved_in_app' ||
        result['queuedCount'] is! int ||
        (result['queuedCount'] as int) < 0 ||
        (result['queuedCount'] as int) >
            (operation == 'broadcast-publish' ? 200 : 1))
      throw const SparkProofException(
        'unavailable',
        'The action was not confirmed. Preserve it and retry.',
      );
    _confirmed.add(saved['requestId'] as String);
    if (_confirmed.length > 100) _confirmed.remove(_confirmed.first);
    try {
      if (await read(key) == serialized) {
        await write(key, jsonEncode({...saved, 'confirmed': true}));
        await remove(key);
      }
    } catch (_) {}
    return result;
  }
}

class CommunicationService {
  static final repository = CommunicationRepository(
    environment:
        '${AppEnvironment.name}|${SparkBackendService.configuration.firebaseProjectId}|${SparkBackendService.configuration.backend}',
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async {
      if (!await (await SharedPreferences.getInstance()).setString(key, value))
        throw StateError('Could not preserve this action for retry.');
    },
    remove: (key) async {
      await (await SharedPreferences.getInstance()).remove(key);
    },
    call: (operation, data) async {
      final client = SparkBackendService.createClient();
      try {
        return await client.communicationCall(operation, data);
      } finally {
        client.close();
      }
    },
  );
  static Future<Map<String, dynamic>> command(
    String operation,
    Map<String, dynamic> data,
  ) {
    if (!AppEnvironment.sparkCommunicationsEnabled)
      throw StateError(
        'This option requires the configured SafePaths Test app.',
      );
    return repository.run(operation, data);
  }

  static Future<Map<String, dynamic>> context(String kind, String id) async {
    if (!AppEnvironment.sparkCommunicationsEnabled)
      throw StateError(
        'This option requires the configured SafePaths Test app.',
      );
    final uid = FirebaseAuth.instance.currentUser?.uid,
        client = SparkBackendService.createClient();
    try {
      final result = await client.communicationCall('$kind-context', {
        (kind == 'feedback' ? 'feedbackId' : 'alertId'): id,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['token'] as String) ||
          result['revision'] is! int ||
          result['status'] is! String)
        throw StateError('The current review could not be loaded. Retry.');
      return result;
    } finally {
      client.close();
    }
  }
}
