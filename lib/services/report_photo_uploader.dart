import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_environment.dart';
import 'firebase_report_photo_uploader.dart';
import 'spark_backend_service.dart';
import 'spark_proof_client.dart';
export 'firebase_report_photo_uploader.dart' show PhotoUploadException;

class ReportPhotoUploader {
  final bool useSpark;
  final SparkProofClient Function() createClient;
  final String? Function() currentUid;
  final _legacy = FirebaseReportPhotoUploader();
  SparkProofClient? _active;
  bool _disposed = false;
  ReportPhotoUploader({
    bool? useSpark,
    SparkProofClient Function()? createClient,
    String? Function()? currentUid,
  }) : useSpark = useSpark ?? AppEnvironment.sparkReportsRequested,
       createClient = createClient ?? SparkBackendService.createClient,
       currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  Future<String> upload(
    String photoKey,
    String uid,
    Uint8List bytes,
    void Function(double?) progress,
  ) async {
    if (_disposed)
      throw const PhotoUploadException('Photo upload was canceled.');
    if (currentUid() != uid)
      throw const PhotoUploadException(
        'Account changed. Please sign in again.',
      );
    if (!useSpark) return _legacy.upload(photoKey, uid, bytes, progress);
    if (_active != null)
      throw const PhotoUploadException('A photo is already uploading.');
    final client = createClient();
    _active = client;
    try {
      final reference = await client.upload(bytes, progress);
      if (_disposed || currentUid() != uid)
        throw const PhotoUploadException(
          'Account changed or upload was canceled.',
        );
      if (!client.configuration.ownsReference(reference, owner: uid))
        throw const PhotoUploadException(
          'The photo was not confirmed for this account. Retry.',
        );
      return reference;
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  void forget() => _legacy.forget();
  void dispose() {
    _disposed = true;
    _active?.close();
    _active = null;
    _legacy.dispose();
  }
}
