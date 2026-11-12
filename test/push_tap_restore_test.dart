import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/notification_tap_inbox.dart';

void main() {
  test(
    'a cold-start tap survives matching account restoration and is discarded for another account',
    () {
      final inbox = NotificationTapInbox();
      final received = <Map<String, dynamic>>[];
      inbox.receive({
        'type': 'report_update',
        'recipientUid': 'resident',
        'reportId': 'report',
      });
      inbox.retainForAccount('resident');
      inbox.attach(received.add);
      expect(received.single['reportId'], 'report');
      inbox.detach();
      inbox.receive({'recipientUid': 'resident', 'reportId': 'private'});
      inbox.retainForAccount('other');
      inbox.attach(received.add);
      expect(received.length, 1);
      inbox.detach();
      inbox.receive({'recipientUid': 'resident'});
      inbox.retainForAccount(null);
      inbox.attach(received.add);
      expect(received.length, 1);
    },
  );
}
