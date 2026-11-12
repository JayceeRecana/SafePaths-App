import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:safepaths_app/utils/report_image.dart';
import 'package:safepaths_app/services/report_submission_coordinator.dart';
import 'package:safepaths_app/widgets/report_upload_progress.dart';

void main() {
  test('only valid JPEG/PNG content is accepted before processing', () {
    final photo = img.Image(width: 12, height: 8);
    for (final encoded in [img.encodeJpg(photo), img.encodePng(photo)]) {
      final normalized = normalizeReportPhoto(Uint8List.fromList(encoded));
      expect(img.decodeJpg(normalized)!.width, 12);
    }
    for (final encoded in [
      img.encodeGif(photo),
      [0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99],
    ]) {
      expect(
        () => normalizeReportPhoto(Uint8List.fromList(encoded)),
        throwsFormatException,
      );
    }
    for (final bytes in [
      [255, 216, 255, 0],
      [137, 80, 78, 71, 13, 10, 26, 10],
    ]) {
      expect(
        () => normalizeReportPhoto(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
    }
    expect(
      () => normalizeReportPhoto(Uint8List(maxReportPhotoBytes + 1)),
      throwsFormatException,
    );
  });
  test(
    'large pixel dimensions are rejected before allocating decoded pixels',
    () {
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 12, height: 8)),
      );
      final sof = List.generate(
        bytes.length - 8,
        (i) => i,
      ).firstWhere((i) => bytes[i] == 255 && bytes[i + 1] == 192);
      final view = ByteData.sublistView(bytes);
      view.setUint16(sof + 5, 10000, Endian.big);
      view.setUint16(sof + 7, 5000, Endian.big);
      expect(
        () => normalizeReportPhoto(bytes),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dimensions'),
          ),
        ),
      );
    },
  );
  test('normalization bounds large portrait images without distortion', () {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 500, height: 2000)),
    );
    final decoded = img.decodeJpg(normalizeReportPhoto(bytes))!;
    expect((decoded.width, decoded.height), (400, 1600));
  });
  test('extreme one-pixel aspect ratios never produce a zero-sized image', () {
    for (final size in [(1, 20000), (20000, 1)]) {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: size.$1, height: size.$2)),
      );
      final result = img.decodeJpg(
        prepareReportImage(normalizeReportPhoto(bytes)),
      )!;
      expect(result.width, inInclusiveRange(1, 600));
      expect(result.height, inInclusiveRange(1, 600));
    }
  });

  test(
    'saving failure retains the uploaded photo and retry skips processing/upload',
    () async {
      final c = ReportSubmissionCoordinator();
      addTearDown(c.dispose);
      var prepares = 0, uploads = 0, saves = 0;
      Future<Uint8List> prepare() async {
        prepares++;
        return Uint8List(1);
      }

      Future<String> upload(
        Uint8List bytes,
        void Function(double?) progress,
      ) async {
        uploads++;
        progress(0.42);
        return 'https://photo';
      }

      Future<void> save(String? url) async {
        expect(url, 'https://photo');
        if (++saves == 1) throw StateError('response lost');
      }

      await expectLater(
        c.submit(photoKey: 'u:a', prepare: prepare, upload: upload, save: save),
        throwsStateError,
      );
      expect(c.phase, ReportSubmissionPhase.failed);
      expect(c.hasUploadedPhoto, isTrue);
      await c.submit(
        photoKey: 'u:a',
        prepare: prepare,
        upload: upload,
        save: save,
      );
      expect((prepares, uploads, saves), (1, 1, 2));
      expect(c.phase, ReportSubmissionPhase.complete);
    },
  );
  test(
    'changing photo/account identity invalidates a previous upload',
    () async {
      final c = ReportSubmissionCoordinator();
      addTearDown(c.dispose);
      var uploads = 0;
      Future<String> upload(Uint8List bytes, void Function(double?) p) async =>
          'https://photo/${++uploads}';
      Future<void> fail(String? _) async => throw StateError('offline');
      for (final key in ['u:a', 'u:b', 'other:b']) {
        await expectLater(
          c.submit(
            photoKey: key,
            prepare: () async => Uint8List(1),
            upload: upload,
            save: fail,
          ),
          throwsStateError,
        );
      }
      expect(uploads, 3);
      c.invalidatePhoto();
      expect(c.hasUploadedPhoto, isFalse);
    },
  );
  test('upload failures recover and cannot advance to report saving', () async {
    final c = ReportSubmissionCoordinator();
    addTearDown(c.dispose);
    var saves = 0;
    await expectLater(
      c.submit(
        photoKey: 'a',
        prepare: () async => Uint8List(1),
        upload: (_, _) async => throw StateError('network'),
        save: (_) async {
          saves++;
        },
      ),
      throwsStateError,
    );
    expect(c.isBusy, isFalse);
    expect(c.hasUploadedPhoto, isFalse);
    expect(saves, 0);
  });
  test(
    'duplicate taps do not start another upload and disposal prevents later saving',
    () async {
      final c = ReportSubmissionCoordinator();
      final uploaded = Completer<String>();
      var uploads = 0, saves = 0;
      Future<String> upload(Uint8List b, void Function(double?) p) {
        uploads++;
        return uploaded.future;
      }

      final first = c.submit(
        photoKey: 'a',
        prepare: () async => Uint8List(1),
        upload: upload,
        save: (_) async {
          saves++;
        },
      );
      await Future<void>.delayed(Duration.zero);
      await c.submit(
        photoKey: 'a',
        prepare: () async => Uint8List(1),
        upload: upload,
        save: (_) async {
          saves++;
        },
      );
      expect(uploads, 1);
      c.dispose();
      uploaded.complete('https://photo');
      await first;
      expect(saves, 0);
    },
  );
  test('reports without a photo skip processing and uploading', () async {
    final c = ReportSubmissionCoordinator();
    addTearDown(c.dispose);
    var saves = 0;
    await c.submit(
      photoKey: null,
      prepare: () async => throw StateError('unexpected'),
      upload: (_, _) async => throw StateError('unexpected'),
      save: (url) async {
        expect(url, isNull);
        saves++;
      },
    );
    expect(saves, 1);
    expect(c.phase, ReportSubmissionPhase.complete);
  });
  testWidgets(
    'progress distinguishes upload from save on a narrow, large-text display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget screen(ReportSubmissionPhase phase, double? value) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: ReportUploadProgress(phase: phase, progress: value),
          ),
        ),
      );
      await tester.pumpWidget(screen(ReportSubmissionPhase.uploading, 0.42));
      expect(find.text('Uploading photo: 42%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.42,
      );
      await tester.pumpWidget(screen(ReportSubmissionPhase.saving, 1));
      expect(find.text('Saving report...'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
