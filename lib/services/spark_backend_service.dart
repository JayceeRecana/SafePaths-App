import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart' show appFlavor;
import '../firebase_options.dart';
import 'spark_proof_client.dart';
import '../config/app_environment.dart';

/// Authenticated transport with separate, explicitly pinned main/test targets.
class SparkBackendService {
  static SparkProofConfiguration get configuration => SparkProofConfiguration(
    mainBackend: AppEnvironment.mainBackendRequested,
    firebaseProjectId: AppEnvironment.mainBackendRequested
        ? const String.fromEnvironment('SAFEPATHS_FIREBASE_PROJECT_ID')
        : const String.fromEnvironment('SPARK_PROOF_FIREBASE_PROJECT_ID'),
    backendUrl: AppEnvironment.mainBackendRequested
        ? const String.fromEnvironment('SAFEPATHS_BACKEND_URL')
        : const String.fromEnvironment('SPARK_PROOF_BACKEND_URL'),
  );
  static void validateConfiguration() => configuration.validate(
    flavor: appFlavor,
    actualProjectId: Firebase.app().options.projectId,
    mainProjectId: DefaultFirebaseOptions.android.projectId,
  );
  static SparkProofClient createClient() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified || user.isAnonymous)
      throw StateError('Please sign in with a verified account.');
    validateConfiguration();
    return SparkProofClient(
      configuration: configuration,
      token: () async {
        if (FirebaseAuth.instance.currentUser?.uid != user.uid)
          throw StateError('Account changed.');
        final token = await user.getIdToken();
        if (FirebaseAuth.instance.currentUser?.uid != user.uid)
          throw StateError('Account changed.');
        return token;
      },
    );
  }
}
