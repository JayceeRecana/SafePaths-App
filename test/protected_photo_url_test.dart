import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';

void main() {
  const host = 'bbteuzgfgnrjjrqewidc.supabase.co';
  final digest = 'a' * 64;
  SparkProofClient client(bool main, String signed) => SparkProofClient(
    configuration: SparkProofConfiguration(
      firebaseProjectId: main ? 'safepaths-92c3d' : 'safepaths-test',
      backendUrl:
          'https://$host/functions/v1/${main ? 'safepaths-main' : 'safepaths-report-proof'}',
      mainBackend: main,
    ),
    token: () async => 'test-token',
    client: MockClient(
      (r) async => http.Response(jsonEncode({'url': signed}), 200),
    ),
  );
  String reference(bool main) =>
      'https://$host/functions/v1/${main ? 'safepaths-main' : 'safepaths-report-proof'}/photo/resident/$digest';
  for (final main in [false, true]) {
    final bucket = main ? 'report-photos-marulas' : 'report-photos-proof';
    final signed =
        'https://$host/storage/v1/object/sign/$bucket/reports/resident/$digest.jpg?token=sample';
    test(
      'protected photo uses its own ${main ? 'Marulas' : 'test'} bucket',
      () async {
        final c = client(main, signed);
        addTearDown(c.close);
        expect(await c.photoUrl(reference(main)), signed);
      },
    );
    for (final invalid in [
      signed.replaceFirst(
        bucket,
        main ? 'report-photos-proof' : 'report-photos-marulas',
      ),
      signed.replaceFirst('reports/resident/', 'reports/other/'),
      signed.replaceFirst(digest, 'b' * 64),
      signed.replaceFirst(host, 'example.com'),
      signed.replaceFirst('https:', 'http:'),
      signed.replaceFirst('?token=sample', ''),
      '$signed#unexpected',
    ])
      test(
        'reject mismatched private photo URL ($main ${Uri.parse(invalid).path})',
        () async {
          final c = client(main, invalid);
          addTearDown(c.close);
          await expectLater(
            c.photoUrl(reference(main)),
            throwsA(isA<SparkProofException>()),
          );
        },
      );
  }
}
