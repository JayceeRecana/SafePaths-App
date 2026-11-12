import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

/// Classifies failures without retaining provider messages, URLs, tokens,
/// coordinates, account IDs, or user-entered content.
String privacySafeErrorCode(Object error) {
  if (error is TimeoutException) {
    return 'timeout';
  }
  if (error is FormatException) {
    return 'invalid-data';
  }
  if (error is FirebaseException) {
    const allowed = {
      'permission-denied',
      'unauthenticated',
      'unavailable',
      'deadline-exceeded',
      'resource-exhausted',
      'network-request-failed',
      'canceled',
      'unknown',
      'object-not-found',
      'unauthorized',
      'quota-exceeded',
      'retry-limit-exceeded',
    };
    return allowed.contains(error.code) ? error.code : 'firebase-error';
  }
  return 'unexpected';
}

Map<String, String> feedbackFailureDiagnostic(Object error) => {
  'type': 'feedback_submission_error',
  'errorCode': privacySafeErrorCode(error),
};
