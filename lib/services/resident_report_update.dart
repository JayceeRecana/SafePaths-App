import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_report_service.dart';
import 'spark_backend_service.dart';

class ResidentReportUpdate {
  static Future<void> save({
    required String reportId,
    required String severity,
    required String description,
    required DateTime expectedUpdatedAt,
  }) async {
    await ResidentReportEditRepository.platform().save(
      reportId: reportId,
      severity: severity,
      description: description,
      expectedUpdatedAt: expectedUpdatedAt,
    );
  }
}

/// Persist the retry identity before sending; a confirmed write stays successful
/// even if removing the local retry marker fails.
class ResidentReportEditRepository {
  final String environment;
  final String? Function() currentUid;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<void> Function(Map<String, dynamic>) send;
  final DateTime Function() now;
  ResidentReportEditRepository({
    required this.environment,
    required this.currentUid,
    required this.read,
    required this.write,
    required this.remove,
    required this.send,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  factory ResidentReportEditRepository.platform() => ResidentReportEditRepository(
    environment:
        '${SparkBackendService.configuration.firebaseProjectId}:${SparkBackendService.configuration.backend}',
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async {
      if (!await (await SharedPreferences.getInstance()).setString(
        key,
        value,
      )) {
        throw StateError('Retry information could not be saved. Please retry.');
      }
    },
    remove: (key) async => (await SharedPreferences.getInstance()).remove(key),
    send: (data) async {
      final client = AdminReportService.createClient();
      try {
        await client.updateReport(data);
      } finally {
        client.close();
      }
    },
  );

  Future<void> save({
    required String reportId,
    required String severity,
    required String description,
    required DateTime expectedUpdatedAt,
  }) async {
    final uid = currentUid();
    if (uid == null) throw StateError('Please sign in again.');
    final details = {
      'reportId': reportId,
      'severity': severity,
      'description': description.trim(),
      'expectedUpdatedAt': expectedUpdatedAt.millisecondsSinceEpoch,
    };
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode([environment, uid, details])))
        .toString();
    final key = 'resident_edit_$fingerprint';
    Map<String, dynamic>? saved;
    try {
      saved = jsonDecode(await read(key) ?? 'null') as Map<String, dynamic>?;
    } catch (_) {}
    final validSaved =
        saved != null &&
        saved['requestId'] is String &&
        RegExp(
          r'^[A-Za-z0-9_-]{16,128}$',
        ).hasMatch(saved['requestId'] as String) &&
        saved['observedAt'] is String &&
        DateTime.tryParse(saved['observedAt']) != null;
    final pending =
        (validSaved ? saved : null) ??
        {
          'requestId': base64UrlEncode(
            List<int>.generate(24, (_) => Random.secure().nextInt(256)),
          ).replaceAll('=', ''),
          'observedAt': now().toUtc().toIso8601String(),
        };
    await write(key, jsonEncode(pending));
    if (currentUid() != uid) throw StateError('Account changed.');
    await send({...details, ...pending});
    if (currentUid() != uid) throw StateError('Account changed.');
    try {
      await remove(key);
    } catch (_) {
      // Keep the confirmed result. Replays remain idempotent on the server.
    }
  }
}
