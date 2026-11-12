import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/utils/privacy_diagnostics.dart';
import 'package:safepaths_app/models/feedback_model.dart';

void main() {
  test('follow-up requires an explicit choice, including legacy feedback', () {
    final feedback = FeedbackModel(
      id: 'feedback',
      category: 'General Feedback',
      rating: 4,
      comments: '',
      timestamp: DateTime(2026),
    );
    expect(feedback.allowFollowUp, isFalse);
    expect(FeedbackModel.fromJson({}, 'legacy').allowFollowUp, isFalse);
    expect(
      FeedbackModel.fromJson({'allowFollowUp': false}, 'no').allowFollowUp,
      isFalse,
    );
    expect(
      FeedbackModel.fromJson({'allowFollowUp': true}, 'yes').allowFollowUp,
      isTrue,
    );
  });
  test('feedback diagnostics omit message contents and identifiers', () {
    final error = FirebaseException(
      plugin: 'test',
      code: 'permission-denied',
      message:
          'resident@example.com uid=person GPS=14.67,120.98 https://example.com/photo?token=secret',
    );
    final diagnostic = feedbackFailureDiagnostic(error);
    expect(diagnostic, {
      'type': 'feedback_submission_error',
      'errorCode': 'permission-denied',
    });
    final encoded = jsonEncode(diagnostic);
    for (final value in [
      'resident@example.com',
      'person',
      '14.67',
      '120.98',
      'https://',
      'secret',
    ]) {
      expect(encoded, isNot(contains(value)));
    }
  });

  test(
    'unknown provider codes and ordinary exceptions cannot carry arbitrary content',
    () {
      expect(
        privacySafeErrorCode(
          FirebaseException(plugin: 'test', code: 'person@example.com'),
        ),
        'firebase-error',
      );
      expect(privacySafeErrorCode(StateError('token=secret')), 'unexpected');
      expect(privacySafeErrorCode(TimeoutException('private URL')), 'timeout');
      expect(
        privacySafeErrorCode(const FormatException('private response')),
        'invalid-data',
      );
    },
  );
}
