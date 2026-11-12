import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/report_submission_repository.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';

void main() {
  final original = {
    'rootReportId': 'a' * 64,
    'contextToken': 'b' * 64,
    'description': 'Water has receded near the intersection.',
    'observedAt': '2026-11-10T05:00:00Z',
    'conditionChange': 'improved',
    'severity': 'Low',
  };
  test(
    'response loss followed by refresh must replay the same follow-up and original context',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      ReportSubmissionRepository repo() => ReportSubmissionRepository(
        environment: 'followups:main',
        preserveContextToken: true,
        currentUid: () => 'resident',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        send: (p) async {
          sent.add(p);
          if (sent.length == 1) throw StateError('Response lost after save');
          return {'reportId': 'd' * 64, 'replay': true};
        },
      );
      await expectLater(
        repo().save(uid: 'resident', payload: original),
        throwsStateError,
      );
      await repo().save(
        uid: 'resident',
        payload: {...original, 'contextToken': 'c' * 64},
      );
      expect(
        sent[1],
        sent[0],
        reason:
            'Refreshing context must not create a new submission after an uncertain save.',
      );
      expect(disk, isEmpty);
    },
  );
  test(
    'definitively stale context can be replaced after refresh without persisting private evidence',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      final repo = ReportSubmissionRepository(
        environment: 'followups:main',
        preserveContextToken: true,
        currentUid: () => 'resident',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        send: (p) async {
          sent.add(p);
          if (sent.length == 1)
            throw SparkProofException('failed-precondition', 'Context changed');
          return {'reportId': 'd' * 64, 'replay': false};
        },
      );
      await expectLater(
        repo.save(uid: 'resident', payload: original),
        throwsA(isA<SparkProofException>()),
      );
      await repo.save(
        uid: 'resident',
        payload: {...original, 'contextToken': 'c' * 64},
      );
      expect(sent[1]['contextToken'], 'c' * 64);
      expect(sent[1]['requestId'], isNot(sent[0]['requestId']));
      expect(disk, isEmpty);
    },
  );
  test(
    'pending follow-up receipt keeps only opaque identity and context, and account remains scoped',
    () async {
      final disk = <String, String>{};
      var uid = 'resident';
      final repo = ReportSubmissionRepository(
        environment: 'followups:main',
        preserveContextToken: true,
        currentUid: () => uid,
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {},
        send: (p) async => throw StateError('Offline'),
      );
      await expectLater(
        repo.save(uid: uid, payload: original),
        throwsStateError,
      );
      final receipt = jsonDecode(disk.values.single) as Map;
      expect(receipt.keys.toSet(), {'requestId', 'contextToken'});
      expect(jsonEncode(disk), isNot(contains(original['description'])));
      uid = 'other';
      await expectLater(
        repo.save(uid: uid, payload: original),
        throwsStateError,
      );
      expect(disk.length, 2);
    },
  );
  test(
    'concurrent retries with refreshed tokens share one in-flight save',
    () async {
      final disk = <String, String>{};
      final pending = Completer<Map<String, dynamic>>();
      var sends = 0;
      final repo = ReportSubmissionRepository(
        environment: 'followups:main',
        preserveContextToken: true,
        currentUid: () => 'resident',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
        remove: (k) async {
          disk.remove(k);
        },
        send: (p) {
          sends++;
          return pending.future;
        },
      );
      final a = repo.save(uid: 'resident', payload: original);
      final b = repo.save(
        uid: 'resident',
        payload: {...original, 'contextToken': 'c' * 64},
      );
      expect(identical(a, b), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sends, 1);
      pending.complete({'reportId': 'd' * 64, 'replay': false});
      expect((await a).reportId, (await b).reportId);
    },
  );
  test(
    'upgrading an existing same-context retry preserves its old request ID',
    () async {
      final disk = <String, String>{}, sent = <Map<String, dynamic>>[];
      ReportSubmissionRepository repo(bool preserve) =>
          ReportSubmissionRepository(
            environment: 'followups:main',
            preserveContextToken: preserve,
            currentUid: () => 'resident',
            read: (k) async => disk[k],
            write: (k, v) async {
              disk[k] = v;
            },
            remove: (k) async {
              disk.remove(k);
            },
            send: (p) async {
              sent.add(p);
              if (sent.length == 1) throw StateError('Lost response');
              return {'reportId': 'd' * 64, 'replay': true};
            },
          );
      await expectLater(
        repo(false).save(uid: 'resident', payload: original),
        throwsStateError,
      );
      await repo(true).save(uid: 'resident', payload: original);
      expect(sent[1], sent[0]);
      expect(disk, isEmpty);
    },
  );
  test(
    'follow-up retry persistence failure prevents sending and confirmed cleanup failure remains success',
    () async {
      final disk = <String, String>{};
      var sends = 0;
      ReportSubmissionRepository repo(bool failWrite) =>
          ReportSubmissionRepository(
            environment: 'followups:main',
            preserveContextToken: true,
            currentUid: () => 'resident',
            read: (k) async => disk[k],
            write: (k, v) async {
              if (failWrite) throw StateError('Storage full');
              disk[k] = v;
            },
            remove: (k) async => throw StateError('Cleanup failed'),
            send: (p) async {
              sends++;
              return {'reportId': 'd' * 64, 'replay': false};
            },
          );
      await expectLater(
        repo(true).save(uid: 'resident', payload: original),
        throwsStateError,
      );
      expect(sends, 0);
      expect(
        (await repo(false).save(uid: 'resident', payload: original)).reportId,
        'd' * 64,
      );
      expect(sends, 1);
    },
  );
}
