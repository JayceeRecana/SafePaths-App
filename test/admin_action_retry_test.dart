import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/services/communication_service.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';

Map<String, dynamic> ack(Map<String, dynamic> sent) => {
  'saved': true,
  'action': sent['action'],
  'pointsAwarded': 0,
  'replay': false,
  'notification': 'saved_in_app',
  if (sent['action'] == 'road_review') 'roadStatus': 'not_passable',
};
void main() {
  test('admin sends nothing when durable retry storage fails', () async {
    var sends = 0;
    final repo = AdminActionRepository(
      environment: 'main|endpoint',
      currentUid: () => 'admin',
      read: (_) async => null,
      write: (_, _) async => throw StateError('disk full'),
      remove: (_) async {},
      send: (p) async {
        sends++;
        return ack(p);
      },
    );
    await expectLater(
      repo.perform('reply', {'reportId': 'report', 'note': 'Private message'}),
      throwsStateError,
    );
    expect(sends, 0);
  });
  test(
    'lost response survives restart and refreshed context without storing private content',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      AdminActionRepository repository() => AdminActionRepository(
        environment: 'main|endpoint',
        currentUid: () => 'admin',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        send: (p) async {
          sent.add(Map.of(p));
          if (sent.length == 1) throw StateError('response lost');
          return ack(p);
        },
      );
      final details = {
        'roadIds': ['road'],
        'contextToken': 'a' * 64,
        'note': 'PRIVATE FIELD INSPECTION',
        'roadStatus': 'not_passable',
        'verifiedCurrentConditions': true,
      };
      await expectLater(
        repository().perform('road_review', details),
        throwsStateError,
      );
      expect(disk.values.single, isNot(contains('PRIVATE')));
      expect(disk.keys.single, isNot(contains('road_review')));
      await repository().perform('road_review', {
        ...details,
        'contextToken': 'b' * 64,
      });
      expect(sent[1]['requestId'], sent[0]['requestId']);
      expect(sent[1]['contextToken'], 'a' * 64);
      expect(disk, isEmpty);
    },
  );
  test('simultaneous identical replies use one request and one send', () async {
    final disk = <String, String>{}, pending = Completer<void>();
    var sends = 0;
    final repo = AdminActionRepository(
      environment: 'test|endpoint',
      currentUid: () => 'admin',
      read: (k) async => disk[k],
      write: (k, v) async {
        disk[k] = v;
      },
      remove: (k) async {
        disk.remove(k);
      },
      send: (p) async {
        sends++;
        await pending.future;
        return ack(p);
      },
    );
    final first = repo.perform('reply', {'reportId': 'r', 'note': 'Checked'});
    final second = repo.perform('reply', {'reportId': 'r', 'note': 'Checked'});
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);
    pending.complete();
    await Future.wait([first, second]);
    expect(disk, isEmpty);
  });
  test(
    'account switch during persistence prevents an outgoing admin action',
    () async {
      String? uid = 'admin';
      var sends = 0;
      final repo = AdminActionRepository(
        environment: 'main|endpoint',
        currentUid: () => uid,
        read: (_) async => null,
        write: (_, _) async {
          uid = 'other';
        },
        remove: (_) async {},
        send: (p) async {
          sends++;
          return ack(p);
        },
      );
      await expectLater(
        repo.perform('reply', {'reportId': 'r', 'note': 'Checked'}),
        throwsStateError,
      );
      expect(sends, 0);
    },
  );
  test(
    'confirmed save stays successful if retry cleanup fails and a new reply gets a new ID',
    () async {
      final disk = <String, String>{}, ids = <String>[];
      final repo = AdminActionRepository(
        environment: 'main|endpoint',
        currentUid: () => 'admin',
        read: (k) async => disk[k],
        write: (k, v) async {
          if ((jsonDecode(v) as Map)['confirmed'] == true)
            throw StateError('disk full');
          disk[k] = v;
        },
        remove: (_) async => throw StateError('unavailable'),
        send: (p) async {
          ids.add(p['requestId'] as String);
          return ack(p);
        },
      );
      await repo.perform('reply', {'reportId': 'r', 'note': 'Checked'});
      await repo.perform('reply', {'reportId': 'r', 'note': 'Checked'});
      expect(ids.toSet().length, 2);
    },
  );
  test(
    'previous test-build retry IDs are upgraded rather than duplicated',
    () async {
      const environment = 'safepaths-test|https://example.com/test';
      final details = {'reportId': 'r', 'note': 'Original reply'};
      final old = jsonEncode({'action': 'reply', ...details});
      final key =
          'admin_pending_${sha256.convert(utf8.encode('$environment|admin|$old'))}';
      final disk = {key: 'x' * 24};
      String? sent;
      final repo = AdminActionRepository(
        environment: environment,
        currentUid: () => 'admin',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        send: (p) async {
          sent = p['requestId'] as String;
          return ack(p);
        },
      );
      await repo.perform('reply', details);
      expect(sent, 'x' * 24);
      expect(disk, isEmpty);
    },
  );
  test(
    'rejected stale context clears the pending attempt and main/test retries stay separate',
    () async {
      final disk = <String, String>{}, ids = <String>[];
      AdminActionRepository repository(String env, {bool stale = false}) =>
          AdminActionRepository(
            environment: env,
            currentUid: () => 'admin',
            read: (k) async => disk[k],
            write: (k, v) async {
              disk[k] = v;
            },
            remove: (k) async {
              disk.remove(k);
            },
            send: (p) async {
              ids.add(p['requestId'] as String);
              if (stale)
                throw const SparkProofException(
                  'failed-precondition',
                  'Changed',
                );
              throw StateError('offline');
            },
          );
      final details = {
        'roadIds': ['road'],
        'contextToken': 'a' * 64,
        'note': 'Current check',
      };
      await expectLater(
        repository(
          'test|endpoint',
          stale: true,
        ).perform('road_review', details),
        throwsA(isA<SparkProofException>()),
      );
      expect(disk, isEmpty);
      await expectLater(
        repository(
          'test|endpoint',
        ).perform('reply', {'reportId': 'r', 'note': 'Checked'}),
        throwsStateError,
      );
      await expectLater(
        repository(
          'main|endpoint',
        ).perform('reply', {'reportId': 'r', 'note': 'Checked'}),
        throwsStateError,
      );
      expect(disk.length, 2);
      expect(ids.toSet().length, 3);
    },
  );
  test(
    'bounded main broadcasts accept 200 queued recipients, reject 201 and feedback rejects multiple owners',
    () async {
      for (final sample in [
        ('broadcast-publish', 200, true),
        ('broadcast-publish', 201, false),
        ('feedback-action', 2, false),
      ]) {
        final disk = <String, String>{};
        final repo = CommunicationRepository(
          environment: 'main',
          currentUid: () => 'admin',
          read: (k) async => disk[k],
          write: (k, v) async {
            disk[k] = v;
          },
          remove: (k) async {
            disk.remove(k);
          },
          call: (op, p) async => {
            'saved': true,
            'operation': op,
            'resourceId': 'a' * 64,
            'revision': 1,
            'replay': false,
            'notification': 'saved_in_app',
            'queuedCount': sample.$2,
          },
        );
        final attempt = repo.run(sample.$1, {'note': 'Test'});
        if (sample.$3) {
          expect((await attempt)['queuedCount'], 200);
        } else {
          await expectLater(attempt, throwsA(isA<SparkProofException>()));
        }
      }
    },
  );
}
