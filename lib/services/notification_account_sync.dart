import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

bool notificationMatchesAccount(Map<String, dynamic> data, String? uid) {
  if (const [
    'report_update',
    'report_new_admin',
    'report_reply_admin',
    'feedback_update',
    'broadcast_update',
  ].contains(data['type'])) {
    final field =
        const [
          'report_update',
          'report_new_admin',
          'report_reply_admin',
        ].contains(data['type'])
        ? 'reportId'
        : data['type'] == 'feedback_update'
        ? 'feedbackId'
        : 'alertId';
    return uid != null &&
        data['recipientUid'] == uid &&
        data[field] is String &&
        RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(data[field] as String) &&
        data['eventId'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(data['eventId'] as String);
  }
  return data['recipientUid'] == null ||
      (uid != null && data['recipientUid'] == uid);
}

/// Verification can change without a sign-out/sign-in transition. Feed this
/// listener userChanges(), which includes refreshes of the current account.
StreamSubscription<User?> watchVerifiedNotificationAccount(
  Stream<User?> changes,
  Future<void> Function() synchronize,
) => changes.listen((user) {
  if (user == null || user.isAnonymous || !user.emailVerified) {
    return;
  }
  // Notification registration must not block the account flow. A later account
  // refresh can retry a transient failure.
  unawaited(synchronize().catchError((Object _) {}));
});
