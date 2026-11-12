import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safepaths_app/services/communication_service.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';

Map<String, dynamic> result(String operation) => {
  'saved': true,
  'operation': operation,
  'resourceId': 'a' * 64,
  'revision': 1,
  'replay': false,
  'notification': 'saved_in_app',
  'queuedCount': 0,
  'createdCount': 1,
  'skippedCount': 0,
  'deletedRoadId': 'osm_way_1',
  'graphStats': {
    'totalRoads': 1,
    'avgNeighbors': 0.0,
    'maximumNeighbors': 0,
    'disconnectedRoads': 1,
  },
};
SparkProofClient client(
  Future<http.Response> Function(http.Request) handler,
) => SparkProofClient(
  configuration: SparkProofConfiguration(
    firebaseProjectId: 'safepaths-test',
    backendUrl:
        'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof',
  ),
  token: () async => 'synthetic-session',
  client: MockClient(handler),
);
void main() {
  test(
    'road maintenance transport requires the confirmed operation and actual imported/skipped count',
    () async {
      final c = client((request) async {
        expect(request.headers['Authorization'], 'Bearer synthetic-session');
        expect(jsonDecode(request.body)['data']['roads'], hasLength(1));
        return http.Response(
          jsonEncode({'result': result('road-import')}),
          200,
        );
      });
      addTearDown(c.close);
      expect(
        (await c.roadCall('road-import', {
          'roads': [
            {'id': 'osm_way_1'},
          ],
        }))['createdCount'],
        1,
      );
    },
  );
  test(
    'false maintenance success, wrong deleted road and malformed graph statistics are rejected',
    () async {
      for (final entry in [
        (
          'road-import',
          {
            'roads': [{}],
          },
          {...result('road-import'), 'createdCount': 2},
        ),
        (
          'road-delete',
          {'roadId': 'osm_way_1'},
          {...result('road-delete'), 'deletedRoadId': 'different'},
        ),
        (
          'road-graph-rebuild',
          <String, dynamic>{},
          {...result('road-graph-rebuild'), 'graphStats': {}},
        ),
      ]) {
        final c = client(
          (_) async => http.Response(jsonEncode({'result': entry.$3}), 200),
        );
        addTearDown(c.close);
        await expectLater(
          c.roadCall(entry.$1, entry.$2),
          throwsA(isA<SparkProofException>()),
        );
      }
    },
  );
  test(
    'stale deletion message instructs refresh without disclosing provider response details',
    () async {
      final c = client(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'failed-precondition',
              'message': 'PRIVATE PROVIDER DETAIL',
            },
          }),
          409,
        ),
      );
      addTearDown(c.close);
      await expectLater(
        c.roadCall('road-delete', {'roadId': 'osm_way_1'}),
        throwsA(
          isA<SparkProofException>()
              .having((e) => e.code, 'code', 'failed-precondition')
              .having((e) => e.message, 'safe recovery', contains('Refresh'))
              .having((e) => e.message, 'privacy', isNot(contains('PRIVATE'))),
        ),
      );
    },
  );
  test(
    'lost maintenance save survives repository recreation with the original confirmation and no stored geometry',
    () async {
      final disk = <String, String>{}, attempts = <Map<String, dynamic>>[];
      var first = true;
      CommunicationRepository repository() => CommunicationRepository(
        environment: 'test-project|test-endpoint',
        currentUid: () => 'admin',
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
        remove: (key) async {
          disk.remove(key);
        },
        call: (operation, data) async {
          attempts.add(data);
          if (first) {
            first = false;
            throw const SparkProofException('unavailable', 'lost response');
          }
          return {...result(operation), 'replay': true};
        },
      );
      final data = {
        'roadId': 'osm_way_1',
        'contextToken': 'a' * 64,
        'confirmed': true,
      };
      await expectLater(
        repository().run('road-delete', data),
        throwsA(isA<SparkProofException>()),
      );
      expect(jsonEncode(disk), isNot(contains('osm_way_1')));
      expect(
        (await repository().run('road-delete', {
          ...data,
          'contextToken': 'b' * 64,
        }))['replay'],
        true,
      );
      expect(attempts[1]['requestId'], attempts[0]['requestId']);
      expect(attempts[1]['contextToken'], 'a' * 64);
      expect(disk, isEmpty);
    },
  );
  test(
    'account change cannot accept another administrator maintenance acknowledgement',
    () async {
      var uid = 'admin';
      final disk = <String, String>{};
      final repository = CommunicationRepository(
        environment: 'test',
        currentUid: () => uid,
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
        remove: (key) async {
          disk.remove(key);
        },
        call: (operation, data) async {
          uid = 'other';
          return result(operation);
        },
      );
      await expectLater(
        repository.run('road-graph-rebuild', {}),
        throwsStateError,
      );
      expect(disk, isNotEmpty);
    },
  );
}
