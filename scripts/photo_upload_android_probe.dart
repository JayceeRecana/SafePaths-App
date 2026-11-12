// Android-only smoke probe. Run explicitly; never use as a release entrypoint.
// Exercises real native image codecs/files plus simulated upload/save failures.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../lib/utils/report_image.dart';
import '../lib/utils/image_watermark_util.dart';
import '../lib/services/report_submission_coordinator.dart';
import '../lib/widgets/report_upload_progress.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: PhotoUploadProbe()));
}

class PhotoUploadProbe extends StatefulWidget {
  const PhotoUploadProbe({super.key});
  @override
  State<PhotoUploadProbe> createState() => _PhotoUploadProbeState();
}

class _PhotoUploadProbeState extends State<PhotoUploadProbe> {
  final submission = ReportSubmissionCoordinator();
  String result = 'Running native photo checks...';
  final files = <File>[];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => runChecks());
  }

  Future<void> runChecks() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final size in [
        (1, 1),
        (40, 20),
        (2000, 500),
        (500, 2000),
        (2000, 40),
      ]) {
        final source = Uint8List.fromList(
          img.encodePng(img.Image(width: size.$1, height: size.$2)),
        );
        final normalized = await compute(normalizeReportPhoto, source);
        final input = File('${dir.path}/probe_${size.$1}_${size.$2}.jpg');
        files.add(input);
        await input.writeAsBytes(normalized);
        final stamped = await ImageWatermarkUtil.applyWatermark(
          sourceFile: input,
          locationName: 'Android test fixture',
          lat: 14.676,
          lng: 120.984,
          timestamp: DateTime(2026, 10, 23),
        );
        files.add(stamped);
        if (stamped.path == input.path)
          throw StateError('Native watermark returned fallback for $size');
        final bytes = await compute(
          prepareReportImage,
          await stamped.readAsBytes(),
        );
        final image = img.decodeJpg(bytes)!;
        if (image.width > 600 ||
            image.height > 600 ||
            (image.width / image.height - size.$1 / size.$2).abs() > 0.1)
          throw StateError('Bad image dimensions for $size');
        debugPrint('[PHOTO_PROBE] native image $size passed');
      }
      var uploads = 0, saves = 0;
      Future<String> upload(
        Uint8List bytes,
        void Function(double?) progress,
      ) async {
        uploads++;
        for (final value in [0.2, 0.7, 1.0]) {
          progress(value);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return 'https://example.invalid/fixture.jpg';
      }

      Future<void> save(String? url) async {
        if (++saves == 1) throw StateError('Simulated response loss');
        if (url != 'https://example.invalid/fixture.jpg')
          throw StateError('Wrong reused photo');
      }

      try {
        await submission.submit(
          photoKey: 'fixture:photo',
          prepare: () async => Uint8List(1),
          upload: upload,
          save: save,
        );
      } catch (_) {
        /* Retry the intentionally failed save. */
      }
      await submission.submit(
        photoKey: 'fixture:photo',
        prepare: () async => Uint8List(1),
        upload: upload,
        save: save,
      );
      if (uploads != 1 ||
          saves != 2 ||
          submission.phase != ReportSubmissionPhase.complete)
        throw StateError('Unsafe retry');
      debugPrint(
        '[PHOTO_PROBE] PASS: 5 native image cases, progress, and upload reuse',
      );
      if (mounted)
        setState(
          () =>
              result = 'PASS: 5 native image cases, progress and retry reuse.',
        );
    } catch (e, stack) {
      debugPrint('[PHOTO_PROBE] FAIL: $e\n$stack');
      if (mounted) setState(() => result = 'FAIL: $e');
    } finally {
      for (final file in files.toSet()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    submission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo upload smoke probe')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(result),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: submission,
            builder: (_, _) => ReportUploadProgress(
              phase: submission.phase,
              progress: submission.progress,
            ),
          ),
        ],
      ),
    ),
  );
}
