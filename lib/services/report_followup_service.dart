import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_environment.dart';
import '../models/user_report.dart';
import 'report_submission_repository.dart';
import 'spark_backend_service.dart';

class ReportFollowupContext {
  final UserReport root;
  final List<UserReport> updates;
  final String token;
  final bool canSubmit;
  final bool viewerIsAdmin;
  final String? closedReason;
  const ReportFollowupContext({
    required this.root,
    required this.updates,
    required this.token,
    required this.canSubmit,
    this.viewerIsAdmin = false,
    this.closedReason,
  });

  factory ReportFollowupContext.fromJson(
    Map<String, dynamic> data,
    String rootId,
  ) {
    if (data['token'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['token'] as String) ||
        data['rootReport'] is! Map ||
        data['updates'] is! List ||
        data['canSubmit'] is! bool) {
      throw StateError('The condition history is unavailable. Retry.');
    }
    final root = UserReport.fromJson(
      Map<String, dynamic>.from(data['rootReport'] as Map),
    );
    final updates = (data['updates'] as List)
        .map(
          (item) => UserReport.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    if (root.id != rootId ||
        root.isFollowup ||
        updates.length > 100 ||
        updates.any(
          (item) =>
              !item.isFollowup ||
              item.rootReportId != rootId ||
              item.userId != root.userId ||
              item.incidentId != root.incidentId,
        )) {
      throw StateError('The condition history could not be confirmed. Retry.');
    }
    return ReportFollowupContext(
      root: root,
      updates: updates,
      token: data['token'] as String,
      canSubmit: data['canSubmit'] as bool,
      viewerIsAdmin: data['viewerIsAdmin'] == true,
      closedReason: data['closedReason'] as String?,
    );
  }

  UserReport get original => root.originalSubmission == null
      ? root
      : UserReport.fromJson({
          ...root.toJson(),
          ...root.originalSubmission!,
          'id': root.id,
          'createdAt':
              root.originalSubmission!['submittedAt'] ??
              root.createdAt.toIso8601String(),
        });
}

class ReportFollowupService {
  static void _checkEnabled() {
    if (!AppEnvironment.sparkFollowupsEnabled)
      throw StateError('Follow-up reporting is not enabled in this build.');
  }

  static Future<ReportFollowupContext> load(String rootId) async {
    _checkEnabled();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final client = SparkBackendService.createClient();
    try {
      final data = await client.followupCall('followup-context', {
        'rootReportId': rootId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed. Reopen the history.');
      return ReportFollowupContext.fromJson(data, rootId);
    } finally {
      client.close();
    }
  }

  static final _repository = ReportSubmissionRepository(
    preserveContextToken: true,
    environment:
        'followups:${SparkBackendService.configuration.firebaseProjectId}:${SparkBackendService.configuration.backend}',
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async {
      if (!await (await SharedPreferences.getInstance()).setString(key, value))
        throw StateError('Could not preserve the follow-up retry.');
    },
    remove: (key) async {
      await (await SharedPreferences.getInstance()).remove(key);
    },
    send: (payload) async {
      final client = SparkBackendService.createClient();
      try {
        return await client.followupCall('followup-submit', payload);
      } finally {
        client.close();
      }
    },
  );

  static Future<ReportSaveResult> save(Map<String, dynamic> payload) {
    _checkEnabled();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    return _repository.save(uid: uid, payload: payload);
  }
}

String followupChangeLabel(String? value) => switch (value) {
  'worsened' => 'Flooding increased',
  'improved' => 'Floodwater decreased',
  'cleared' => 'No floodwater visible',
  'unchanged' => 'Conditions appear unchanged',
  _ => 'Choose what changed',
};
