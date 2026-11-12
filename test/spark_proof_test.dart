import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';

const origin = 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co';
const endpoint = '$origin/functions/v1/safepaths-report-proof';
SparkProofConfiguration config([String url = endpoint]) =>
    SparkProofConfiguration(
      firebaseProjectId: 'safepaths-test',
      backendUrl: url,
    );

void main() {
  test(
    'proof configuration refuses main project, default flavor and hostile endpoint variants',
    () {
      void validate(
        SparkProofConfiguration value, {
        String flavor = 'fieldtest',
        String actual = 'safepaths-test',
      }) => value.validate(
        flavor: flavor,
        actualProjectId: actual,
        mainProjectId: 'safepaths-92c3d',
      );
      expect(() => validate(config()), returnsNormally);
      expect(
        () => validate(config(), actual: 'safepaths-92c3d'),
        throwsStateError,
      );
      expect(() => validate(config(), flavor: 'production'), throwsStateError);
      expect(
        () => validate(config(), actual: 'different-test'),
        throwsStateError,
      );
      for (final url in [
        'http://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof',
        '$endpoint?token=secret',
        '$endpoint#fragment',
        '$endpoint/submit-report',
        'https://user:password@aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof',
        'https://aaaaaaaaaaaaaaaaaaaa.supabase.co.attacker.com/functions/v1/safepaths-report-proof',
        'https://aaaaaaaaaaaaaaaaaaaa.supabase.co:8443/functions/v1/safepaths-report-proof',
      ]) {
        expect(() => validate(config(url)), throwsStateError, reason: url);
      }
    },
  );

  test(
    'upload confirms only a reference belonging to the configured proof server',
    () async {
      final progress = <double?>[];
      final client = SparkProofClient(
        configuration: config(),
        token: () async => 'test-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          return http.Response(
            jsonEncode({'imageUrl': '$endpoint/photo/resident/${'a' * 64}'}),
            200,
          );
        }),
      );
      expect(
        await client.upload(Uint8List.fromList([1]), progress.add),
        startsWith('$endpoint/photo/resident/'),
      );
      expect(progress, [null, 1]);
      final invalid = SparkProofClient(
        configuration: config(),
        token: () async => 'token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'imageUrl': 'https://attacker.example/photo'}),
            200,
          ),
        ),
      );
      await expectLater(
        invalid.upload(Uint8List(1), (_) {}),
        throwsA(isA<SparkProofException>()),
      );
      client.close();
      invalid.close();
    },
  );

  test(
    'backend failures, redirects and false success do not become saved reports',
    () async {
      for (final response in [
        http.Response(
          '',
          302,
          headers: {'location': 'https://attacker.example'},
        ),
        http.Response(
          jsonEncode({
            'result': {'reportId': 'missing-confirmation'},
          }),
          200,
        ),
        http.Response(
          jsonEncode({
            'error': {
              'code': 'permission-denied',
              'message': 'PRIVATE person@example.com token=secret',
            },
          }),
          403,
        ),
      ]) {
        final client = SparkProofClient(
          configuration: config(),
          token: () async => 'token',
          client: MockClient((_) async => response),
        );
        try {
          await client.submit({'requestId': 'same-request'});
          fail('An unconfirmed save must fail.');
        } on SparkProofException catch (error) {
          expect(error.message, isNot(contains('PRIVATE')));
          expect(error.message, isNot(contains('secret')));
        } finally {
          client.close();
        }
      }
    },
  );

  test(
    'protected photo responses cannot redirect the app to another host or public bucket',
    () async {
      final reference = '$endpoint/photo/resident/${'b' * 64}';
      for (final signed in [
        'https://attacker.example/photo?token=x',
        '$origin/storage/v1/object/public/report-photos-proof/photo',
        '$origin/storage/v1/object/sign/report-photos-proof/reports/resident/photo.jpg',
        '$origin/storage/v1/object/sign/report-photos-proof/reports/resident/photo.jpg?token=short',
      ]) {
        final client = SparkProofClient(
          configuration: config(),
          token: () async => 'token',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'url': signed, 'expiresIn': 120}),
              200,
            ),
          ),
        );
        if (signed.endsWith('token=short')) {
          expect(await client.photoUrl(reference), signed);
        } else {
          await expectLater(
            client.photoUrl(reference),
            throwsA(isA<SparkProofException>()),
          );
        }
        client.close();
      }
    },
  );

  test('signed-out calls cannot send report data or photo bytes', () async {
    var requests = 0;
    final client = SparkProofClient(
      configuration: config(),
      token: () async => null,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(client.submit({}), throwsA(isA<SparkProofException>()));
    await expectLater(
      client.upload(Uint8List(1), (_) {}),
      throwsA(isA<SparkProofException>()),
    );
    expect(requests, 0);
    client.close();
  });
}
