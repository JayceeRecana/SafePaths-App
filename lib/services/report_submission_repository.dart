import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_environment.dart';
import 'backend_service.dart';
import 'spark_backend_service.dart';
import 'spark_proof_client.dart';

class ReportSaveResult {
  final String reportId;
  final bool replay;
  const ReportSaveResult(this.reportId, this.replay);
  factory ReportSaveResult.fromJson(Map<String, dynamic> value) {
    if (value['reportId'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['reportId'] as String) ||
        value['replay'] is! bool) {
      throw StateError(
        'The report save was not confirmed. Keep your form and retry.',
      );
    }
    return ReportSaveResult(
      value['reportId'] as String,
      value['replay'] as bool,
    );
  }
}

/// Stores only opaque retry IDs and, for follow-ups, context tokens.
/// Notes, photos and coordinates are not copied
/// into preferences or preference keys. Failed/uncertain sends retain the ID.
class ReportSubmissionRepository {
  final String environment;
  final bool preserveContextToken;
  final String? Function() currentUid;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) send;
  final _pending = <String, Future<ReportSaveResult>>{};
  ReportSubmissionRepository({
    required this.environment,
    this.preserveContextToken = false,
    required this.currentUid,
    required this.read,
    required this.write,
    required this.remove,
    required this.send,
  });

  factory ReportSubmissionRepository.platform() {
    final spark = AppEnvironment.sparkReportsRequested;
    if (spark) SparkBackendService.validateConfiguration();
    final project = Firebase.app().options.projectId;
    return ReportSubmissionRepository(
      environment: spark
          ? 'spark:$project:${SparkBackendService.configuration.backend}'
          : 'firebase:$project',
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      read: (key) async =>
          (await SharedPreferences.getInstance()).getString(key),
      write: (key, value) async {
        if (!await (await SharedPreferences.getInstance()).setString(
          key,
          value,
        ))
          throw StateError(
            'Retry information could not be saved. Please retry.',
          );
      },
      remove: (key) async {
        await (await SharedPreferences.getInstance()).remove(key);
      },
      send: (data) async {
        if (!spark) return BackendService.call('submitReport', data);
        final client = SparkBackendService.createClient();
        try {
          return await client.submit(data);
        } finally {
          client.close();
        }
      },
    );
  }
  static dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<ReportSaveResult> save({
    required String uid,
    required Map<String, dynamic> payload,
  }) {
    if (currentUid() != uid)
      return Future.error(StateError('Account changed. Please sign in again.'));
    final snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
    String keyFor(Map<String, dynamic> value) =>
        'report_request_v2_${sha256.convert(utf8.encode(jsonEncode([environment, uid, _canonical(value)])))}';
    final legacyKey = keyFor(snapshot);
    final intent = Map<String, dynamic>.from(snapshot);
    if (preserveContextToken) {
      if (snapshot['contextToken'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(snapshot['contextToken'] as String)) {
        return Future.error(
          StateError('The follow-up context is unavailable. Refresh history.'),
        );
      }
      intent.remove('contextToken');
    }
    final key = keyFor(intent);
    final active = _pending[key];
    if (active != null) return active;
    late Future<ReportSaveResult> operation;
    operation = _save(key, uid, snapshot, legacyKey: legacyKey).whenComplete(
      () {
        if (identical(_pending[key], operation)) _pending.remove(key);
      },
    );
    _pending[key] = operation;
    return operation;
  }

  Future<ReportSaveResult> _save(
    String key,
    String uid,
    Map<String, dynamic> payload, {
    required String legacyKey,
  }) async {
    var stored = await read(key);
    String? migrated;
    if (preserveContextToken && stored == null && legacyKey != key) {
      migrated = await read(legacyKey);
      stored = migrated;
    }
    Map<String, dynamic> saved = {};
    if (preserveContextToken && stored != null) {
      try {
        saved = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      } catch (_) {}
    }
    final prior = preserveContextToken ? saved['requestId'] ?? stored : stored;
    final requestId =
        prior is String && RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(prior)
        ? prior
        : base64UrlEncode(
            List<int>.generate(24, (_) => Random.secure().nextInt(256)),
          ).replaceAll('=', '');
    final contextToken = saved['contextToken'];
    final receipt = preserveContextToken
        ? jsonEncode({
            'requestId': requestId,
            'contextToken':
                contextToken is String &&
                    RegExp(r'^[a-f0-9]{64}$').hasMatch(contextToken)
                ? contextToken
                : payload['contextToken'],
          })
        : requestId;
    await write(key, receipt);
    if (currentUid() != uid)
      throw StateError('Account changed. Please sign in again.');
    Map<String, dynamic> response;
    try {
      response = await send({
        ...payload,
        if (preserveContextToken)
          'contextToken': (jsonDecode(receipt) as Map)['contextToken'],
        'requestId': requestId,
      });
    } on SparkProofException catch (error) {
      // A definite rejection has no saved follow-up; allow refreshed context.
      // Uncertain/network failures retain the original request for replay.
      if (preserveContextToken && error.code == 'failed-precondition') {
        try {
          if (await read(key) == receipt) await remove(key);
          if (migrated != null && await read(legacyKey) == migrated)
            await remove(legacyKey);
        } catch (_) {}
      }
      rethrow;
    }
    final result = ReportSaveResult.fromJson(response);
    if (currentUid() != uid)
      throw StateError('Account changed. Please sign in again.');
    // Cleanup failure must not invalidate an already confirmed server save.
    try {
      if (await read(key) == receipt) await remove(key);
      if (migrated != null && await read(legacyKey) == migrated)
        await remove(legacyKey);
    } catch (_) {}
    return result;
  }
}
