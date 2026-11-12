import 'package:flutter/foundation.dart';

enum ReportSubmissionPhase {
  idle,
  processing,
  uploading,
  saving,
  failed,
  complete,
}

typedef PhotoUploader =
    Future<String> Function(Uint8List bytes, void Function(double?) onProgress);

/// Keeps the successful upload across ambiguous/failed report-save attempts.
/// The screen owns one coordinator per form; photo identity includes account ID.
class ReportSubmissionCoordinator extends ChangeNotifier {
  ReportSubmissionPhase phase = ReportSubmissionPhase.idle;
  double? progress;
  String? _cachedKey;
  String? _cachedUrl;
  bool _disposed = false;
  bool get isBusy => [
    ReportSubmissionPhase.processing,
    ReportSubmissionPhase.uploading,
    ReportSubmissionPhase.saving,
  ].contains(phase);
  bool get hasUploadedPhoto => _cachedUrl != null;
  void invalidatePhoto() {
    _cachedKey = null;
    _cachedUrl = null;
  }

  void _setPhase(ReportSubmissionPhase value) {
    if (_disposed) return;
    phase = value;
    notifyListeners();
  }

  Future<void> submit({
    required String? photoKey,
    required Future<Uint8List> Function() prepare,
    required PhotoUploader upload,
    required Future<void> Function(String?) save,
  }) async {
    if (_disposed || isBusy || phase == ReportSubmissionPhase.complete) return;
    if (photoKey != _cachedKey) invalidatePhoto();
    progress = null;
    try {
      String? url;
      if (photoKey != null) {
        if (_cachedKey == photoKey && _cachedUrl != null) {
          url = _cachedUrl;
        } else {
          _setPhase(ReportSubmissionPhase.processing);
          final bytes = await prepare();
          if (_disposed) return;
          _setPhase(ReportSubmissionPhase.uploading);
          url = await upload(bytes, (value) {
            if (_disposed || phase != ReportSubmissionPhase.uploading) return;
            progress = value != null && value.isFinite
                ? value.clamp(0.0, 1.0)
                : null;
            notifyListeners();
          });
          if (_disposed) return;
          _cachedKey = photoKey;
          _cachedUrl = url;
        }
      }
      if (_disposed) return;
      _setPhase(ReportSubmissionPhase.saving);
      await save(url);
      if (!_disposed) _setPhase(ReportSubmissionPhase.complete);
    } catch (_) {
      if (!_disposed) _setPhase(ReportSubmissionPhase.failed);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
