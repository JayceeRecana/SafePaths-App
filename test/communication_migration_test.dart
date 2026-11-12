import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safepaths_app/services/communication_service.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/services/notification_account_sync.dart';
import 'package:safepaths_app/models/broadcast_alert.dart';

Map<String, dynamic> saved(String operation) => {
  'saved': true,
  'operation': operation,
  'resourceId': 'a' * 64,
  'revision': 1,
  'replay': false,
  'notification': 'saved_in_app',
  'queuedCount': 0,
};
void main() {
  test(
    'lost response survives repository recreation and retains its original review context without storing contents',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      var calls = 0;
      CommunicationRepository repository() => CommunicationRepository(
        environment: 'test',
        currentUid: () => 'resident',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        call: (op, data) async {
          sent.add(data);
          if (++calls == 1)
            throw const SparkProofException('unavailable', 'retry');
          return saved(op);
        },
      );
      final payload = {
        'feedbackId': 'private-feedback',
        'contextToken': 'b' * 64,
        'action': 'reply',
        'note': 'private response',
        'notify': false,
      };
      await expectLater(
        repository().run('feedback-action', payload),
        throwsA(isA<SparkProofException>()),
      );
      expect(disk.values.single, isNot(contains('private response')));
      expect(disk.keys.single, isNot(contains('private-feedback')));
      await repository().run('feedback-action', {
        ...payload,
        'contextToken': 'c' * 64,
      });
      expect(sent[0], sent[1]);
      expect(disk, isEmpty);
    },
  );
  test(
    'persistence failure stops sending and account changes cannot confirm another account action',
    () async {
      var calls = 0;
      String? uid = 'resident';
      final blocked = CommunicationRepository(
        environment: 'test',
        currentUid: () => uid,
        read: (k) async => null,
        write: (k, v) async => throw StateError('disk unavailable'),
        remove: (k) async {},
        call: (op, data) async {
          calls++;
          return saved(op);
        },
      );
      await expectLater(blocked.run('feedback-submit', {}), throwsStateError);
      expect(calls, 0);
      final unreadable = CommunicationRepository(
        environment: 'test',
        currentUid: () => uid,
        read: (k) async => throw StateError('disk read unavailable'),
        write: (k, v) async {},
        remove: (k) async {},
        call: (op, data) async {
          calls++;
          return saved(op);
        },
      );
      await expectLater(
        unreadable.run('feedback-submit', {}),
        throwsStateError,
      );
      expect(calls, 0);
      final switched = CommunicationRepository(
        environment: 'test',
        currentUid: () => uid,
        read: (k) async => null,
        write: (k, v) async {},
        remove: (k) async {},
        call: (op, data) async {
          uid = 'other';
          return saved(op);
        },
      );
      await expectLater(switched.run('feedback-submit', {}), throwsStateError);
    },
  );
  test(
    'concurrent retries share a save and malformed acknowledgements stay pending',
    () async {
      final disk = <String, String>{};
      var calls = 0;
      final repo = CommunicationRepository(
        environment: 'test',
        currentUid: () => 'resident',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        call: (op, data) async {
          calls++;
          return {...saved(op), 'notification': 'delivered'};
        },
      );
      final first = repo.run('feedback-submit', {'rating': 4}),
          second = repo.run('feedback-submit', {'rating': 4});
      await expectLater(
        Future.wait([first, second]),
        throwsA(isA<SparkProofException>()),
      );
      expect(calls, 1);
      expect(disk, isNotEmpty);
    },
  );
  test(
    'a stale rejection clears its original context so a refreshed review can proceed',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      final repo = CommunicationRepository(
        environment: 'test',
        currentUid: () => 'admin',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        call: (op, data) async {
          sent.add(data);
          if (sent.length == 1)
            throw const SparkProofException('failed-precondition', 'refresh');
          return saved(op);
        },
      );
      final payload = {
        'feedbackId': 'feedback',
        'action': 'reply',
        'note': 'reviewed note',
        'contextToken': 'b' * 64,
      };
      await expectLater(
        repo.run('feedback-action', payload),
        throwsA(isA<SparkProofException>()),
      );
      await repo.run('feedback-action', {...payload, 'contextToken': 'c' * 64});
      expect(sent.last['contextToken'], 'c' * 64);
      expect(sent.last['requestId'], isNot(sent.first['requestId']));
    },
  );
  test(
    'private feedback and scoped broadcast notification taps require their intended signed-in account',
    () {
      for (final kind in ['feedback_update', 'broadcast_update']) {
        final data = {
          'type': kind,
          'recipientUid': 'resident',
          'eventId': 'e' * 64,
          kind == 'feedback_update' ? 'feedbackId' : 'alertId': 'resource',
        };
        expect(notificationMatchesAccount(data, 'resident'), true);
        expect(notificationMatchesAccount(data, 'other'), false);
        expect(notificationMatchesAccount(data, null), false);
        expect(
          notificationMatchesAccount({
            ...data,
            'recipientUid': null,
          }, 'resident'),
          false,
        );
        expect(
          notificationMatchesAccount({...data, 'eventId': 'bad'}, 'resident'),
          false,
        );
      }
    },
  );
  test(
    'withdrawn and expired broadcasts are inactive while legacy validity is preserved',
    () {
      final data = {
        'id': 'test',
        'title': 'Test',
        'message': 'test',
        'createdAt': Timestamp.now(),
        'severity': 'Warning',
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 15)),
        ),
        'status': 'active',
        'studyArea': 'nearby_test',
      };
      expect(BroadcastAlert.fromJson(data).isActive, true);
      expect(
        BroadcastAlert.fromJson({...data, 'status': 'withdrawn'}).isActive,
        false,
      );
      expect(
        BroadcastAlert.fromJson({
          ...data,
          'expiresAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        }).isActive,
        false,
      );
      final legacy = Map<String, dynamic>.from(data)
        ..remove('expiresAt')
        ..remove('status');
      expect(BroadcastAlert.fromJson(legacy).isActive, true);
    },
  );
}
