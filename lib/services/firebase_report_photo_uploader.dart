import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PhotoUploadException implements Exception {
  final String message;
  const PhotoUploadException(this.message);
}

/// Owns task/progress subscriptions, and retains completed objects if URL lookup fails.
class FirebaseReportPhotoUploader {
  UploadTask? _task;
  StreamSubscription<TaskSnapshot>? _progress;
  Reference? _completedObject;
  String? _completedKey;
  bool _disposed = false;

  Future<String> upload(
    String photoKey,
    String uid,
    Uint8List bytes,
    void Function(double?) onProgress,
  ) async {
    if (_disposed) {
      throw const PhotoUploadException('Photo upload was canceled.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != uid || user?.emailVerified != true) {
      throw const PhotoUploadException(
        'Please sign in with a verified account and retry.',
      );
    }
    try {
      Reference ref;
      if (_completedKey == photoKey && _completedObject != null) {
        ref = _completedObject!;
        onProgress(1);
      } else {
        ref = FirebaseStorage.instance.ref().child(
          'reports/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        final task = ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        _task = task;
        _progress = task.snapshotEvents.listen(
          (snapshot) {
            if (!_disposed) {
              onProgress(
                snapshot.totalBytes > 0
                    ? snapshot.bytesTransferred / snapshot.totalBytes
                    : null,
              );
            }
          },
          onError: (Object error) {
            /* The task future reports this failure. */
          },
        );
        try {
          await task.timeout(const Duration(seconds: 45));
        } catch (_) {
          try {
            await task.cancel().timeout(const Duration(seconds: 3));
          } catch (_) {}
          rethrow;
        } finally {
          await _progress?.cancel();
          _progress = null;
          _task = null;
        }
        _completedKey = photoKey;
        _completedObject = ref;
        onProgress(1);
      }
      if (_disposed) {
        throw const PhotoUploadException('Photo upload was canceled.');
      }
      return await ref.getDownloadURL().timeout(const Duration(seconds: 10));
    } on PhotoUploadException {
      rethrow;
    } catch (_) {
      throw const PhotoUploadException(
        'Photo upload could not be completed. Check your connection and retry; your form is preserved.',
      );
    }
  }

  void forget() {
    _completedKey = null;
    _completedObject = null;
  }

  void dispose() {
    _disposed = true;
    final task = _task;
    if (task != null) {
      unawaited(task.cancel().then<void>((_) {}, onError: (Object _) {}));
    }
    unawaited(_progress?.cancel() ?? Future<void>.value());
    _progress = null;
  }
}
