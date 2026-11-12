import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:safepaths_app/utils/report_image.dart';
import 'package:safepaths_app/services/private_media_service.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/widgets/private_media_image.dart';

const endpoint =
    'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/safepaths-report-proof';
SparkProofConfiguration config() => SparkProofConfiguration(
  firebaseProjectId: 'safepaths-test',
  backendUrl: endpoint,
);
Uint8List picture() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 24, height: 24)));
void main() {
  test(
    'private preparation preserves aspect ratio, bounds dimensions and strips EXIF instead of copying source metadata',
    () {
      final image = img.Image(width: 800, height: 400);
      image.exif.imageIfd.make = 'Sensitive camera metadata';
      final source = Uint8List.fromList(img.encodeJpg(image));
      expect(latin1.decode(source), contains('Sensitive camera metadata'));
      final avatar = preparePrivateMedia({
            'purpose': 'avatar',
            'bytes': source,
          }),
          decoded = img.decodeJpg(avatar)!;
      expect(decoded.width, 256);
      expect(decoded.height, 128);
      expect(
        latin1.decode(avatar),
        isNot(contains('Sensitive camera metadata')),
      );
      final report = normalizeReportPhoto(source);
      expect(
        latin1.decode(report),
        isNot(contains('Sensitive camera metadata')),
      );
      expect(
        () => preparePrivateMedia({
          'purpose': 'feedback',
          'bytes': Uint8List.fromList([1, 2, 3]),
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'inline compatibility reading is bounded and never treats arbitrary data as an image',
    () {
      expect(
        boundedLegacyImage('data:image/png;base64,${base64Encode(picture())}'),
        isNotNull,
      );
      expect(boundedLegacyImage('data:image/jpeg;base64,not valid'), isNull);
      expect(
        boundedLegacyImage('data:image/jpeg;base64,${'A' * 700001}'),
        isNull,
      );
    },
  );
  test('media references enforce purpose, backend and owner', () {
    final reference = '$endpoint/media/avatar/resident/${'a' * 64}';
    expect(
      config().ownsMediaReference(
        reference,
        owner: 'resident',
        purpose: 'avatar',
      ),
      true,
    );
    expect(config().ownsMediaReference(reference, owner: 'other'), false);
    expect(config().ownsMediaReference(reference, purpose: 'feedback'), false);
    expect(config().ownsMediaReference('$reference/extra'), false);
    expect(
      config().ownsMediaReference(
        reference.replaceFirst('aaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbb'),
      ),
      false,
    );
  });
  test(
    'missing attachment failures retain an explicit upload recovery message',
    () async {
      final client = SparkProofClient(
        configuration: config(),
        token: () async => 'fixture',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'media-unavailable',
                'message': 'Untrusted provider detail',
              },
            }),
            409,
          ),
        ),
      );
      addTearDown(client.close);
      for (final operation in ['profile-save', 'feedback-submit']) {
        await expectLater(
          client.communicationCall(operation, {}),
          throwsA(
            isA<SparkProofException>()
                .having((e) => e.code, 'code', 'media-unavailable')
                .having(
                  (e) => e.message,
                  'actionable message',
                  contains('Retry the upload'),
                )
                .having(
                  (e) => e.message,
                  'safe message',
                  isNot(contains('provider detail')),
                ),
          ),
        );
      }
    },
  );
  test(
    'confirmed uploads survive save retries without reuploading and account changes cannot adopt an old photo',
    () async {
      String? uid = 'resident';
      var calls = 0;
      SparkProofClient client() => SparkProofClient(
        configuration: config(),
        token: () async => 'fixture',
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'reference': '$endpoint/media/avatar/resident/${'a' * 64}',
            }),
            200,
          );
        }),
      );
      final uploader = PrivateMediaUploader(
        createClient: client,
        currentUid: () => uid,
      );
      addTearDown(uploader.dispose);
      final bytes = picture();
      final first = await uploader.upload('avatar', 'resident', bytes);
      expect(await uploader.upload('avatar', 'resident', bytes), first);
      expect(calls, 1);
      uid = 'other';
      await expectLater(
        uploader.upload('avatar', 'resident', bytes),
        throwsStateError,
      );
    },
  );
  test(
    'upload acknowledgement from a different owner is rejected and a missing asset can be reuploaded explicitly',
    () async {
      var calls = 0;
      final uploader = PrivateMediaUploader(
        currentUid: () => 'resident',
        createClient: () => SparkProofClient(
          configuration: config(),
          token: () async => 'fixture',
          client: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode({
                'reference':
                    '$endpoint/media/avatar/${calls == 1 ? 'other' : 'resident'}/${'a' * 64}',
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(uploader.dispose);
      await expectLater(
        uploader.upload('avatar', 'resident', picture()),
        throwsStateError,
      );
      expect(
        await uploader.upload('avatar', 'resident', picture()),
        contains('/resident/'),
      );
      uploader.forget();
      await uploader.upload('avatar', 'resident', picture());
      expect(calls, 3);
    },
  );
  test(
    'authenticated image reads carry record context and reject failed delivery instead of displaying provider error bytes',
    () async {
      final client = SparkProofClient(
        configuration: config(),
        token: () async => 'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(jsonDecode(request.body)['data']['feedbackId'], 'feedback');
          return http.Response('private provider error', 403);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.mediaBytes(
          '$endpoint/media/feedback/resident/${'b' * 64}',
          feedbackId: 'feedback',
        ),
        throwsA(isA<SparkProofException>()),
      );
    },
  );
  testWidgets(
    'a new account never sees the previous completed image while its request is pending',
    (tester) async {
      var uid = 'resident';
      final accounts = StreamController<String?>.broadcast(sync: true),
          pending = Completer<Uint8List>();
      addTearDown(accounts.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PrivateMediaImage(
            reference: '$endpoint/media/avatar/resident/${'a' * 64}',
            currentUid: () => uid,
            accounts: accounts.stream,
            load: (reference, id) =>
                uid == 'resident' ? Future.value(picture()) : pending.future,
            width: 50,
            height: 50,
            fallback: const Text('No image'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      uid = 'other';
      accounts.add(uid);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      pending.completeError(StateError('Access denied'));
      await tester.pumpAndSettle();
      expect(find.text('No image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a late response from the old account cannot replace the new account placeholder',
    (tester) async {
      var uid = 'resident';
      final accounts = StreamController<String?>.broadcast(sync: true),
          old = Completer<Uint8List>(),
          fresh = Completer<Uint8List>();
      addTearDown(accounts.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PrivateMediaImage(
            reference: '$endpoint/media/avatar/resident/${'a' * 64}',
            currentUid: () => uid,
            accounts: accounts.stream,
            load: (reference, id) =>
                uid == 'resident' ? old.future : fresh.future,
            width: 50,
            height: 50,
            fallback: const Text('No image'),
          ),
        ),
      );
      uid = 'other';
      accounts.add(uid);
      await tester.pump();
      old.complete(picture());
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      fresh.completeError(StateError('Denied'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'hiding home controls and ordinary rebuilds retain the authorized image request',
    (tester) async {
      final accounts = StreamController<String?>.broadcast(sync: true);
      addTearDown(accounts.close);
      var loads = 0;
      var visible = true;
      var reference = '$endpoint/media/avatar/resident/${'a' * 64}';
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Visibility(
                visible: visible,
                maintainState: true,
                child: PrivateMediaImage(
                  reference: reference,
                  currentUid: () => 'resident',
                  accounts: accounts.stream,
                  load: (_, _) async {
                    loads++;
                    return picture();
                  },
                  width: 36,
                  height: 36,
                  fallback: const Text('No image'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 1);
      for (var i = 0; i < 3; i++) {
        update(() => visible = false);
        await tester.pump();
        update(() => visible = true);
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        expect(loads, 1);
      }
      // An actual new profile photo must still load.
      update(() => reference = '$endpoint/media/avatar/resident/${'b' * 64}');
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
