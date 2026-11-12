import 'package:flutter/services.dart' show appFlavor;
import 'study_area.dart';

class AppEnvironment {
  static String resolve(String? flavor, String define) {
    final selected = flavor ?? (define.isEmpty ? 'production' : define);
    if (selected != 'production' && selected != 'fieldtest') {
      throw StateError('Unknown app environment: $selected');
    }
    if (flavor != null && define.isNotEmpty && flavor != define) {
      throw StateError('Build flavor and APP_ENV disagree.');
    }
    return selected;
  }

  static final name = resolve(
    appFlavor,
    const String.fromEnvironment('APP_ENV'),
  );
  static bool get isFieldTest => name == 'fieldtest';
  static bool get mainBackendRequested =>
      const bool.fromEnvironment('SAFEPATHS_BACKEND_ENABLED');
  static bool get managedBackendEnabled => isFieldTest || mainBackendRequested;
  static StudyArea get area =>
      isFieldTest ? StudyArea.fieldtest : StudyArea.marulas;
  static String get envAsset => isFieldTest ? '.env.fieldtest' : '.env';
  static bool get uploadsEnabled => !isFieldTest;
  static bool get sparkMediaRequested =>
      mainBackendRequested ||
      const bool.fromEnvironment('SPARK_PROOF_MEDIA_ENABLED');
  static bool get sparkMediaEnabled =>
      managedBackendEnabled && sparkMediaRequested;
  static bool get profilePhotosEnabled => !isFieldTest || sparkMediaEnabled;
  static bool get feedbackPhotosEnabled =>
      sparkMediaEnabled && sparkCommunicationsEnabled;
  static bool get sparkCommunicationsRequested =>
      mainBackendRequested ||
      const bool.fromEnvironment('SPARK_PROOF_COMMUNICATIONS_ENABLED');
  static bool get sparkCommunicationsEnabled =>
      managedBackendEnabled && sparkCommunicationsRequested;
  static bool get communicationPushAllowed =>
      pushEnabled ||
      sparkCommunicationsEnabled &&
          const bool.fromEnvironment('SPARK_PROOF_PUSH_ENABLED');
  static bool get sparkCoreRequested =>
      mainBackendRequested ||
      const bool.fromEnvironment('SPARK_PROOF_CORE_ENABLED');
  static bool get sparkCoreEnabled =>
      managedBackendEnabled && sparkCoreRequested;
  static bool get sparkReportsRequested =>
      mainBackendRequested ||
      const bool.fromEnvironment('SPARK_PROOF_REPORTS_ENABLED');
  static bool get sparkFollowupsEnabled =>
      managedBackendEnabled &&
      sparkReportsRequested &&
      sparkCoreEnabled &&
      (mainBackendRequested
          ? const bool.fromEnvironment('SAFEPATHS_FOLLOWUPS_ENABLED')
          : const bool.fromEnvironment('SPARK_PROOF_FOLLOWUPS_ENABLED'));
  static bool get reportsEnabled => reportsAllowed(
    isFieldTest: isFieldTest,
    sparkRequested: sparkReportsRequested,
  );
  static bool reportsAllowed({
    required bool isFieldTest,
    required bool sparkRequested,
  }) => !isFieldTest || sparkRequested;
  static bool get pushEnabled => !isFieldTest;

  static void validateTestConfiguration({
    required Map<String, String> env,
    required String actualProjectId,
    required String productionProjectId,
  }) {
    final expected = env['FIELDTEST_FIREBASE_PROJECT_ID']?.trim() ?? '';
    if (expected.isEmpty ||
        expected == 'REQUIRED' ||
        expected == productionProjectId ||
        actualProjectId != expected ||
        actualProjectId == productionProjectId) {
      throw StateError(
        'SafePaths Test requires a separate Firebase test project. Check .env.fieldtest and fieldtest/google-services.json.',
      );
    }
    final token = env['MAPBOX_ACCESS_TOKEN']?.trim() ?? '';
    if (!token.startsWith('pk.')) {
      throw StateError('Set a public Mapbox token in .env.fieldtest.');
    }
    if (env.keys.any(
      (key) =>
          key.startsWith('SUPABASE_') ||
          key.startsWith('FCM_') ||
          key.contains('PRIVATE_KEY'),
    )) {
      throw StateError(
        'The test environment must not contain upload or push credentials.',
      );
    }
  }
}
