import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'spark_backend_service.dart';

class ReportClarificationService {
  static Future<Map<String, dynamic>> load(String reportId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final client = SparkBackendService.createClient();
    try {
      final result = await client.clarificationCall('clarification-context', {
        'reportId': reportId,
      });
      if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed.');
      return result;
    } finally {
      client.close();
    }
  }

  static Future<void> reply(Map<String, dynamic> details) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              SparkBackendService.configuration.backend.toString(),
              uid,
              details,
            ]),
          ),
        )
        .toString();
    final prefs = await SharedPreferences.getInstance(),
        key = 'clarification_$digest';
    final requestId =
        prefs.getString(key) ??
        base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', '');
    if (!await prefs.setString(key, requestId))
      throw StateError('Could not preserve retry information.');
    if (FirebaseAuth.instance.currentUser?.uid != uid)
      throw StateError('Account changed.');
    final client = SparkBackendService.createClient();
    try {
      await client.clarificationCall('clarification-reply', {
        ...details,
        'requestId': requestId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed.');
      try {
        await prefs.remove(key);
      } catch (_) {
        /* The server confirmed this reply. */
      }
    } finally {
      client.close();
    }
  }
}

/// Shared UI/save validation. Server validation remains authoritative.
String? clarificationDraftProblem({
  required String text,
  required DateTime now,
  bool hasPhoto = false,
  bool photoConfirmed = false,
  DateTime? photoObservedAt,
}) {
  if (text.trim().length < 10) return 'Write at least 10 characters.';
  if (text.length > 2000) return 'Keep your reply within 2,000 characters.';
  if (!hasPhoto) return null;
  if (photoObservedAt == null)
    return 'Choose when the attached photo was observed.';
  if (photoObservedAt.millisecondsSinceEpoch <= 0 ||
      photoObservedAt.isAfter(now)) {
    return 'Photo observation time must be in the past or now.';
  }
  if (!photoConfirmed)
    return 'Confirm that the photo supports the observation time selected.';
  return null;
}
