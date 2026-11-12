import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_environment.dart';
import 'communication_service.dart';
import 'spark_backend_service.dart';
import 'spark_proof_client.dart';

class PrivateMediaUploader {
  final SparkProofClient Function() createClient;
  final String? Function() currentUid;
  SparkProofClient? _active;
  bool _disposed = false;
  String? _key, _reference;
  PrivateMediaUploader({
    SparkProofClient Function()? createClient,
    String? Function()? currentUid,
  }) : createClient = createClient ?? SparkBackendService.createClient,
       currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);
  Future<String> upload(String purpose, String uid, Uint8List bytes) async {
    if (_disposed || currentUid() != uid)
      throw StateError('Account changed or upload was cancelled.');
    if (_active != null) throw StateError('An image is already uploading.');
    final key = '$purpose|$uid|${sha256.convert(bytes)}';
    if (_key == key && _reference != null) return _reference!;
    final client = createClient();
    _active = client;
    try {
      final reference = await client.uploadMedia(purpose, bytes);
      if (_disposed || currentUid() != uid)
        throw StateError('Account changed or upload was cancelled.');
      if (!client.configuration.ownsMediaReference(
        reference,
        owner: uid,
        purpose: purpose,
      ))
        throw StateError('The image was not confirmed for this account.');
      _key = key;
      _reference = reference;
      return reference;
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  void forget() {
    _key = null;
    _reference = null;
  }

  void dispose() {
    _disposed = true;
    _active?.close();
    _active = null;
    forget();
  }
}

class PrivateMediaService {
  static Future<Map<String, dynamic>> profileContext() async {
    if (!AppEnvironment.sparkMediaEnabled)
      throw StateError('Use the configured SafePaths Test app.');
    final user = FirebaseAuth.instance.currentUser,
        client = SparkBackendService.createClient();
    try {
      final value = await client.communicationCall('profile-context', {});
      if (user == null ||
          FirebaseAuth.instance.currentUser?.uid != user.uid ||
          value['ownerUid'] != user.uid ||
          value['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['token'] as String) ||
          value['name'] is! String ||
          value['location'] is! String)
        throw StateError('The profile could not be refreshed. Retry.');
      return value;
    } finally {
      client.close();
    }
  }

  static Future<void> saveProfile(Map<String, dynamic> data) async {
    if (!AppEnvironment.sparkMediaEnabled)
      throw StateError('Use the configured SafePaths Test app.');
    await CommunicationService.repository.run('profile-save', data);
  }

  static Future<Uint8List> read(String reference, {String? feedbackId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid,
        client = SparkBackendService.createClient();
    try {
      final bytes = await client.mediaBytes(reference, feedbackId: feedbackId);
      if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed.');
      return bytes;
    } finally {
      client.close();
    }
  }
}
