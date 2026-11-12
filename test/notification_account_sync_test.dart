import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/notification_account_sync.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  @override
  final bool emailVerified;
  @override
  final bool isAnonymous;
  _User(this.uid, {this.emailVerified = false, this.isAnonymous = false});
}

void main() {
  test(
    'private report pushes require the correct account and valid routing IDs',
    () {
      final data = {
        'type': 'report_update',
        'recipientUid': 'resident',
        'reportId': 'report',
        'eventId': 'e' * 64,
      };
      expect(notificationMatchesAccount(data, 'resident'), true);
      expect(notificationMatchesAccount(data, 'other'), false);
      expect(notificationMatchesAccount(data, null), false);
      for (final changed in [
        {'recipientUid': null},
        {'reportId': '../report'},
        {'eventId': 'bad'},
      ]) {
        expect(
          notificationMatchesAccount({...data, ...changed}, 'resident'),
          false,
        );
      }
      expect(
        notificationMatchesAccount({'type': 'broadcast'}, 'resident'),
        true,
      );
    },
  );
  test(
    'admin work notifications require their exact recipient and routing IDs',
    () {
      for (final kind in ['report_new_admin', 'report_reply_admin']) {
        final data = <String, dynamic>{
          'type': kind,
          'recipientUid': 'admin',
          'reportId': 'report',
          'eventId': 'a' * 64,
        };
        expect(notificationMatchesAccount(data, 'admin'), isTrue);
        expect(notificationMatchesAccount(data, 'resident'), isFalse);
        expect(notificationMatchesAccount(data, null), isFalse);
        expect(
          notificationMatchesAccount({...data, 'recipientUid': null}, 'admin'),
          isFalse,
        );
        expect(
          notificationMatchesAccount({...data, 'eventId': 'bad'}, 'admin'),
          isFalse,
        );
        expect(
          notificationMatchesAccount({
            ...data,
            'reportId': '../report',
          }, 'admin'),
          isFalse,
        );
      }
    },
  );
  test('verification refresh registers the same signed-in account', () async {
    final changes = StreamController<User?>();
    var registrations = 0;
    final subscription = watchVerifiedNotificationAccount(
      changes.stream,
      () async {
        registrations++;
      },
    );
    changes.add(null);
    changes.add(_User('resident'));
    changes.add(_User('guest', emailVerified: true, isAnonymous: true));
    await Future<void>.delayed(Duration.zero);
    expect(registrations, 0);
    // No sign-out or new sign-in: the existing user's verification is refreshed.
    changes.add(_User('resident', emailVerified: true));
    await Future<void>.delayed(Duration.zero);
    expect(registrations, 1);
    await subscription.cancel();
    await changes.close();
  });

  test(
    'a transient registration failure does not prevent a later retry',
    () async {
      final changes = StreamController<User?>();
      var attempts = 0;
      final subscription = watchVerifiedNotificationAccount(
        changes.stream,
        () async {
          if (++attempts == 1) throw StateError('network unavailable');
        },
      );
      changes.add(_User('resident', emailVerified: true));
      await Future<void>.delayed(Duration.zero);
      changes.add(_User('resident', emailVerified: true));
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
      await subscription.cancel();
      await changes.close();
    },
  );
}
