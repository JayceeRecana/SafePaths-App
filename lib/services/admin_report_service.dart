import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'spark_proof_client.dart';
import 'spark_backend_service.dart';

class AdminActionResult {
  final String action;
  final int pointsAwarded;
  final bool replay;
  final String? roadStatus, sourceReportId;
  final bool isFollowup;
  final int pointsReversed, falsePenalty;
  const AdminActionResult({
    required this.action,
    this.pointsAwarded = 0,
    this.replay = false,
    this.roadStatus,
    this.sourceReportId,
    this.isFollowup = false,
    this.pointsReversed = 0,
    this.falsePenalty = 0,
  });
  factory AdminActionResult.fromJson(
    Map<String, dynamic> data,
    String expected,
  ) {
    final points = data['pointsAwarded'];
    final review = expected == 'verify' || expected == 'road_review';
    if (!const [
          'start',
          'reply',
          'verify',
          'dismiss',
          'road_review',
          'correct_followup',
          'request_clarification',
        ].contains(expected) ||
        data['saved'] != true ||
        data['action'] != expected ||
        data['pointsAwarded'] is! int ||
        data['replay'] is! bool ||
        data['notification'] != 'saved_in_app' ||
        (data['sourceReportId'] != null &&
            (expected != 'road_review' ||
                data['sourceReportId'] is! String ||
                !RegExp(
                  r'^[A-Za-z0-9_-]{1,128}$',
                ).hasMatch(data['sourceReportId'] as String))) ||
        points is! int ||
        points < -15 ||
        points > 10 ||
        (data['reportType'] != null &&
            !const ['original', 'followup'].contains(data['reportType'])) ||
        (data['reportType'] == 'followup' &&
            (expected == 'verify' && points > 5 ||
                expected == 'dismiss' && points < -5)) ||
        (expected == 'correct_followup' && data['reportType'] != 'followup') ||
        (expected == 'verify' && points < 0) ||
        (expected == 'dismiss' && points > 0) ||
        (expected == 'correct_followup' &&
            (points > 0 ||
                data['pointsReversed'] is! int ||
                data['falsePenalty'] is! int ||
                (data['pointsReversed'] as int) < 0 ||
                (data['pointsReversed'] as int) > 5 ||
                (data['falsePenalty'] as int) < 0 ||
                (data['falsePenalty'] as int) > 5 ||
                points !=
                    -(data['pointsReversed'] as int) -
                        (data['falsePenalty'] as int))) ||
        (!const ['verify', 'dismiss', 'correct_followup'].contains(expected) &&
            points != 0) ||
        (data['observationOnly'] == true &&
            (expected != 'verify' || data['roadStatus'] != null)) ||
        (review &&
            data['observationOnly'] != true &&
            !const [
              'passable',
              'partial',
              'not_passable',
            ].contains(data['roadStatus']))) {
      throw StateError('The action was not confirmed. Preserve it and retry.');
    }
    return AdminActionResult(
      action: expected,
      pointsAwarded: data['pointsAwarded'] as int,
      replay: data['replay'] as bool,
      roadStatus: data['roadStatus'] as String?,
      sourceReportId: data['sourceReportId'] as String?,
      isFollowup: data['reportType'] == 'followup',
      pointsReversed: data['pointsReversed'] as int? ?? 0,
      falsePenalty: data['falsePenalty'] as int? ?? 0,
    );
  }
  String get confirmation => switch (action) {
    'start' =>
      'Review started. The reporter can see the acknowledgement in the app.',
    'request_clarification' =>
      'Clarification requested. The resident can reply from this report.',
    'reply' =>
      'Message saved in report history. Push delivery has not been confirmed.',
    'verify' =>
      '${isFollowup ? 'Follow-up' : 'Report'} verified. ${roadStatus == null ? 'Current road condition unchanged.' : 'Road condition: ${roadConditionLabel(roadStatus)}.'}${pointsAwarded > 0 ? ' +$pointsAwarded trust points awarded.' : ' No additional trust points awarded.'}',
    'dismiss' =>
      'Dismissal saved.${pointsAwarded < 0 ? ' Trust change: $pointsAwarded.' : ' No trust points deducted.'}',
    'correct_followup' =>
      'Follow-up review corrected. Bonus reversal: -$pointsReversed. False-submission penalty: -$falsePenalty. Original report unchanged.',
    _ =>
      'Road review saved. Current condition: ${roadConditionLabel(roadStatus)}.',
  };
}

String roadConditionLabel(String? status) => switch (status) {
  'passable' => 'Passable',
  'partial' => 'Partially passable',
  'not_passable' => 'Not passable',
  _ => 'Unknown',
};

/// Uses the validated, separate main/test backend configuration.
class AdminReportService {
  static SparkProofClient createClient() => SparkBackendService.createClient();

  static Future<Map<String, dynamic>> context({
    String? reportId,
    List<String>? roadIds,
    String? sourceReportId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final client = createClient();
    try {
      final result = await client.adminCall('admin-context', {
        if (reportId != null) 'reportId': reportId,
        if (roadIds != null) 'roadIds': roadIds,
        if (sourceReportId != null) 'sourceReportId': sourceReportId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed.');
      if (result['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['token'] as String) ||
          result['roads'] is! List)
        throw StateError('The latest review context is unavailable. Retry.');
      return result;
    } finally {
      client.close();
    }
  }

  static Future<AdminActionResult> perform(
    String action,
    Map<String, dynamic> details,
  ) => _actions.perform(action, details);

  static final _actions = AdminActionRepository(
    environment:
        '${SparkBackendService.configuration.firebaseProjectId}|${SparkBackendService.configuration.backend}',
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async {
      if (!await (await SharedPreferences.getInstance()).setString(
        key,
        value,
      )) {
        throw StateError(
          'Could not preserve this action for retry. Nothing was sent.',
        );
      }
    },
    remove: (key) async {
      await (await SharedPreferences.getInstance()).remove(key);
    },
    send: (payload) async {
      final client = createClient();
      try {
        return await client.adminCall('admin-action', payload);
      } finally {
        client.close();
      }
    },
  );
}

/// Stores only opaque request/context tokens. A retry keeps the original context
/// even if the form has refreshed since a response was lost.
class AdminActionRepository {
  final String environment;
  final String? Function() currentUid;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) send;
  final Map<String, Future<AdminActionResult>> _pending = {};
  final Set<String> _confirmed = {};
  AdminActionRepository({
    required this.environment,
    required this.currentUid,
    required this.read,
    required this.write,
    required this.remove,
    required this.send,
  });

  Future<AdminActionResult> perform(
    String action,
    Map<String, dynamic> details,
  ) {
    final uid = currentUid();
    if (uid == null) throw StateError('Please sign in again.');
    if (details.containsKey('action') || details.containsKey('requestId')) {
      throw ArgumentError('Action identity is assigned by the repository.');
    }
    final payload = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(details)) as Map,
    );
    final intent = Map<String, dynamic>.from(payload)..remove('contextToken');
    final key =
        'admin_action_${_digest(jsonEncode([environment, uid, action, intent]))}';
    return _pending.putIfAbsent(
      key,
      () => _run(key, uid, action, payload).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<AdminActionResult> _run(
    String key,
    String uid,
    String action,
    Map<String, dynamic> payload,
  ) async {
    Map<String, dynamic> saved = {};
    final stored = await read(key);
    try {
      saved = Map<String, dynamic>.from(jsonDecode(stored ?? '{}') as Map);
    } catch (_) {}
    final oldPayload = jsonEncode({'action': action, ...payload});
    final legacyKey =
        'admin_pending_${_digest('$environment|$uid|$oldPayload')}';
    // Upgrade a pending ID from the previous test build without reissuing it.
    if (stored == null) {
      final legacy = await read(legacyKey);
      if (legacy != null)
        saved = {
          'requestId': legacy,
          if (payload['contextToken'] is String)
            'contextToken': payload['contextToken'],
        };
    }
    final prior = saved['requestId'];
    if (prior is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(prior) ||
        saved['confirmed'] == true ||
        _confirmed.contains(prior) ||
        payload.containsKey('contextToken') &&
            (saved['contextToken'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(saved['contextToken'] as String))) {
      saved = {
        'requestId': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
        if (payload['contextToken'] is String)
          'contextToken': payload['contextToken'],
      };
    }
    saved = {
      'requestId': saved['requestId'],
      if (payload.containsKey('contextToken'))
        'contextToken': saved['contextToken'],
    };
    final serialized = jsonEncode(saved);
    await write(key, serialized);
    if (currentUid() != uid) throw StateError('Account changed.');
    Map<String, dynamic> response;
    try {
      response = await send({'action': action, ...payload, ...saved});
    } on SparkProofException catch (e) {
      if (e.code == 'failed-precondition') {
        try {
          if (await read(key) == serialized) await remove(key);
        } catch (_) {}
      }
      rethrow;
    }
    final result = AdminActionResult.fromJson(response, action);
    if (result.sourceReportId != payload['sourceReportId']) {
      throw StateError(
        'The report reference was not confirmed. Preserve this update and retry.',
      );
    }
    if (currentUid() != uid) throw StateError('Account changed.');
    _confirmed.add(saved['requestId'] as String);
    if (_confirmed.length > 100) _confirmed.remove(_confirmed.first);
    try {
      if (await read(key) == serialized) {
        await write(key, jsonEncode({...saved, 'confirmed': true}));
        await remove(key);
      }
      if (await read(legacyKey) == saved['requestId']) await remove(legacyKey);
    } catch (_) {
      /* Saved server result remains authoritative. */
    }
    return result;
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
