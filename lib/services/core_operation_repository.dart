import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'spark_proof_client.dart';

/// Keeps only opaque retry identifiers and an observation timestamp on disk.
class CoreOperationRepository {
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  final String Function() account;
  final String environment;
  final Map<String, Future<void>> _pending = {};
  CoreOperationRepository({
    required this.call,
    required this.account,
    required this.environment,
  });

  Future<void> run(String operation, Map<String, dynamic> payload) {
    final uid = account();
    final key =
        'core_request_${sha256.convert(utf8.encode(jsonEncode([environment, uid, operation, payload])))}';
    return _pending.putIfAbsent(
      key,
      () => _run(
        key,
        uid,
        operation,
        payload,
      ).whenComplete(() { _pending.remove(key); }),
    );
  }

  Future<void> _run(
    String key,
    String uid,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> pending = {};
    try {
      pending = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}') as Map,
      );
    } catch (_) {}
    if (pending['requestId'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{16,128}$',
        ).hasMatch(pending['requestId'] as String)) {
      pending = {
        'requestId': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
        if (operation == 'observe-incident')
          'observedAt': DateTime.now().toUtc().toIso8601String(),
      };
    }
    final serialized = jsonEncode(pending);
    if (!await prefs.setString(key, serialized))
      throw StateError('Could not preserve this action for retry.');
    if (account() != uid)
      throw StateError('Account changed. Please try again.');
    try {
      final result = await call(operation, {...payload, ...pending});
      if (account() != uid)
        throw StateError('Account changed. Refresh the latest details.');
      if (result['saved'] != true || result['replay'] is! bool)
        throw const SparkProofException(
          'unavailable',
          'The action was not confirmed. Keep it and retry.',
        );
    } on SparkProofException catch (error) {
      if (error.code == 'observation-stale' &&
          prefs.getString(key) == serialized)
        await prefs.remove(key);
      rethrow;
    }
    // A confirmed server save remains successful if local cleanup fails.
    try {
      if (prefs.getString(key) == serialized) await prefs.remove(key);
    } catch (_) {}
  }
}
