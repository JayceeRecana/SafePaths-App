import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/services/report_submission_repository.dart';
import 'package:safepaths_app/services/report_photo_uploader.dart';
import 'package:safepaths_app/services/report_submission_coordinator.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/utils/geo_utils.dart';

const endpoint =
    'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof';
Map<String, dynamic> payload({
  String description = 'Synthetic test observation',
  String? image,
}) => {
  'title': 'Normal form test',
  'description': description,
  'severity': 'High',
  'roadId': 'selected-road',
  'isEmergency': false,
  'observedAt': '2026-10-25T00:00:00Z',
  'location': {
    'lat': 14.676139,
    'lng': 121.009417,
    'source': 'manual',
    if (image != null) 'imageUrl': image,
  },
};
ReportSubmissionRepository repository(
  Map<String, String> store,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) send, {
  String? Function()? uid,
  String env = 'test',
}) => ReportSubmissionRepository(
  environment: env,
  currentUid: uid ?? () => 'resident',
  read: (key) async => store[key],
  write: (key, value) async {
    store[key] = value;
  },
  remove: (key) async {
    store.remove(key);
  },
  send: send,
);
SparkProofClient client(http.Client httpClient) => SparkProofClient(
  configuration: SparkProofConfiguration(
    firebaseProjectId: 'safepaths-test',
    backendUrl: endpoint,
  ),
  token: () async => 'test-bearer',
  client: httpClient,
);
void main() {
  test(
    'normal fieldtest reporting is opt-in without enabling other uploads',
    () {
      expect(
        AppEnvironment.reportsAllowed(isFieldTest: true, sparkRequested: false),
        false,
      );
      expect(
        AppEnvironment.reportsAllowed(isFieldTest: true, sparkRequested: true),
        true,
      );
      expect(
        AppEnvironment.reportsAllowed(
          isFieldTest: false,
          sparkRequested: false,
        ),
        true,
      );
    },
  );
  test(
    'an uncertain save reuses its durable ID after repository recreation without storing report text',
    () async {
      final store = <String, String>{}, ids = <String>[];
      final first = repository(store, (data) async {
        ids.add(data['requestId'] as String);
        throw StateError('lost response');
      });
      await expectLater(
        first.save(uid: 'resident', payload: payload()),
        throwsStateError,
      );
      expect(store.length, 1);
      expect(jsonEncode(store), isNot(contains('Synthetic')));
      expect(jsonEncode(store), isNot(contains('14.676')));
      final second = repository(store, (data) async {
        ids.add(data['requestId'] as String);
        return {'reportId': 'a' * 64, 'replay': true};
      });
      final result = await second.save(uid: 'resident', payload: payload());
      expect(ids[0], ids[1]);
      expect(result.replay, true);
      expect(store, isEmpty);
    },
  );
  test(
    'photo changes, account changes and backend environments cannot reuse an unrelated pending ID',
    () async {
      final store = <String, String>{}, ids = <String>[];
      Future<Map<String, dynamic>> send(Map<String, dynamic> data) async {
        ids.add(data['requestId'] as String);
        throw StateError('offline');
      }

      final repo = repository(store, send);
      for (final data in [
        payload(image: 'photo-one'),
        payload(image: 'photo-two'),
      ])
        await expectLater(
          repo.save(uid: 'resident', payload: data),
          throwsStateError,
        );
      await expectLater(
        repository(store, send, env: 'another-backend').save(
          uid: 'resident',
          payload: payload(image: 'photo-one'),
        ),
        throwsStateError,
      );
      await expectLater(
        repository(store, send, uid: () => 'other').save(
          uid: 'other',
          payload: payload(image: 'photo-one'),
        ),
        throwsStateError,
      );
      expect(ids.toSet().length, 4);
    },
  );
  test(
    'simultaneous identical saves share one request and reject malformed acknowledgements',
    () async {
      final store = <String, String>{},
          wait = Completer<Map<String, dynamic>>();
      var sends = 0;
      final repo = repository(store, (data) {
        sends++;
        return wait.future;
      });
      final a = repo.save(uid: 'resident', payload: payload()),
          b = repo.save(uid: 'resident', payload: payload());
      await Future<void>.delayed(Duration.zero);
      expect(sends, 1);
      wait.complete({'reportId': 'a' * 64, 'replay': false});
      await Future.wait([a, b]);
      final invalid = repository(store, (data) async => {});
      await expectLater(
        invalid.save(uid: 'resident', payload: payload()),
        throwsStateError,
      );
      expect(store.length, 1);
    },
  );
  test(
    'account changes during persistence or response cannot confirm a report for the next account',
    () async {
      String? uid = 'resident';
      var sends = 0;
      final stored = <String, String>{};
      final repo = ReportSubmissionRepository(
        environment: 'test',
        currentUid: () => uid,
        read: (key) async => null,
        write: (key, value) async {
          stored[key] = value;
          uid = 'other';
        },
        remove: (key) async {},
        send: (data) async {
          sends++;
          return {'reportId': 'a' * 64, 'replay': false};
        },
      );
      await expectLater(
        repo.save(uid: 'resident', payload: payload()),
        throwsStateError,
      );
      expect(sends, 0);
      uid = 'resident';
      final after = repository(stored, (data) async {
        uid = 'other';
        return {'reportId': 'a' * 64, 'replay': false};
      }, uid: () => uid);
      await expectLater(
        after.save(uid: 'resident', payload: payload()),
        throwsStateError,
      );
      expect(stored, isNotEmpty);
    },
  );
  test(
    'retry-ID persistence must succeed before sending; cleanup cannot invalidate a saved report',
    () async {
      var sends = 0;
      final broken = ReportSubmissionRepository(
        environment: 'test',
        currentUid: () => 'resident',
        read: (key) async => null,
        write: (key, value) async => throw StateError('storage full'),
        remove: (key) async {},
        send: (data) async {
          sends++;
          return {};
        },
      );
      await expectLater(
        broken.save(uid: 'resident', payload: payload()),
        throwsStateError,
      );
      expect(sends, 0);
      String? saved;
      final cleanup = ReportSubmissionRepository(
        environment: 'test',
        currentUid: () => 'resident',
        read: (key) async => saved,
        write: (key, value) async {
          saved = value;
        },
        remove: (key) async => throw StateError('cleanup unavailable'),
        send: (data) async => {'reportId': 'a' * 64, 'replay': false},
      );
      expect(
        (await cleanup.save(uid: 'resident', payload: payload())).reportId,
        'a' * 64,
      );
    },
  );
  test(
    'normal upload/save pipeline keeps the uploaded photo and request ID after a lost save response',
    () async {
      final store = <String, String>{}, ids = <String>[];
      var uploads = 0, saves = 0;
      final progress = <double?>[];
      final transport = client(
        MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-bearer');
          if (request.url.path.endsWith('/photo-upload')) {
            uploads++;
            return http.Response(
              jsonEncode({'imageUrl': '$endpoint/photo/resident/${'b' * 64}'}),
              200,
            );
          }
          final data = (jsonDecode(request.body) as Map)['data'] as Map;
          ids.add(data['requestId'] as String);
          saves++;
          expect(data['roadId'], 'selected-road');
          expect((data['location'] as Map)['lng'], 121.009417);
          expect(data['observedAt'], '2026-10-25T00:00:00Z');
          if (saves == 1) throw StateError('lost response');
          return http.Response(
            jsonEncode({
              'result': {'reportId': 'a' * 64, 'replay': true},
            }),
            200,
          );
        }),
      );
      final uploader = ReportPhotoUploader(
        useSpark: true,
        currentUid: () => 'resident',
        createClient: () => transport,
      );
      // Each save uses its own transport just as the normal platform repository does.
      final repo = repository(
        store,
        (data) async => client(
          MockClient((request) async {
            final saved = (jsonDecode(request.body) as Map)['data'] as Map;
            ids.add(saved['requestId'] as String);
            saves++;
            expect(saved['roadId'], 'selected-road');
            expect((saved['location'] as Map)['lng'], 121.009417);
            expect(saved['observedAt'], '2026-10-25T00:00:00Z');
            if (saves == 1) throw StateError('lost response');
            return http.Response(
              jsonEncode({
                'result': {'reportId': 'a' * 64, 'replay': true},
              }),
              200,
            );
          }),
        ).submit(data),
      );
      final flow = ReportSubmissionCoordinator();
      addTearDown(flow.dispose);
      addTearDown(uploader.dispose);
      Future<void> submit() => flow.submit(
        photoKey: 'resident:selected-photo',
        prepare: () async => Uint8List.fromList([255, 216, 255, 217]),
        upload: (bytes, p) {
          return uploader.upload('key', 'resident', bytes, (value) {
            progress.add(value);
            p(value);
          });
        },
        save: (reference) async {
          await repo.save(
            uid: 'resident',
            payload: payload(image: reference),
          );
        },
      );
      await expectLater(submit(), throwsA(isA<SparkProofException>()));
      expect(flow.hasUploadedPhoto, true);
      await submit();
      expect(flow.phase, ReportSubmissionPhase.complete);
      expect(uploads, 1);
      expect(saves, 2);
      expect(ids[0], ids[1]);
      expect(progress, [null, 1]);
    },
  );
  test(
    'an upload from another owner or a response after account change cannot be attached',
    () async {
      String? uid = 'resident';
      final wrong = ReportPhotoUploader(
        useSpark: true,
        currentUid: () => uid,
        createClient: () => client(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'imageUrl': '$endpoint/photo/other/${'b' * 64}'}),
              200,
            ),
          ),
        ),
      );
      addTearDown(wrong.dispose);
      await expectLater(
        wrong.upload('key', 'resident', Uint8List(1), (_) {}),
        throwsA(isA<PhotoUploadException>()),
      );
      final moved = ReportPhotoUploader(
        useSpark: true,
        currentUid: () => uid,
        createClient: () => client(
          MockClient((_) async {
            uid = 'other';
            return http.Response(
              jsonEncode({'imageUrl': '$endpoint/photo/resident/${'b' * 64}'}),
              200,
            );
          }),
        ),
      );
      addTearDown(moved.dispose);
      await expectLater(
        moved.upload('key', 'resident', Uint8List(1), (_) {}),
        throwsA(isA<PhotoUploadException>()),
      );
    },
  );
  test(
    'report snapping cannot invent a road segment across disconnected ways',
    () {
      final geometry = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [121.0, 14.67],
            [121.001, 14.67],
          ],
          [
            [121.02, 14.67],
            [121.021, 14.67],
          ],
        ],
      };
      expect(
        GeoUtils.distanceToGeometryMeters(14.67, 121.0105, geometry),
        greaterThan(500),
      );
      expect(
        GeoUtils.distanceToGeometryMeters(14.67, 121.0005, geometry),
        lessThan(1),
      );
      expect(
        GeoUtils.distanceToGeometryMeters(14.67, 121.0, null),
        double.infinity,
      );
    },
  );
}
