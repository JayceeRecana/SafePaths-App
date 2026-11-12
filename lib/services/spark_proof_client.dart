import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Explicit test-backend settings shared by the proof and opted-in normal forms.
class SparkProofConfiguration {
  final String firebaseProjectId;
  final Uri backend;
  final bool mainBackend;
  SparkProofConfiguration({
    required this.firebaseProjectId,
    required String backendUrl,
    this.mainBackend = false,
  }) : backend = Uri.parse(backendUrl);

  void validate({
    required String? flavor,
    required String actualProjectId,
    required String mainProjectId,
  }) {
    if (mainBackend) {
      if (flavor != 'production' ||
          mainProjectId != 'safepaths-92c3d' ||
          firebaseProjectId != mainProjectId ||
          actualProjectId != mainProjectId ||
          backend.toString() !=
              'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-main') {
        throw StateError(
          'The Marulas backend configuration does not match the main project.',
        );
      }
      return;
    }
    if (flavor != 'fieldtest' ||
        firebaseProjectId == mainProjectId ||
        actualProjectId == mainProjectId ||
        firebaseProjectId != actualProjectId ||
        !RegExp(r'^[a-z][a-z0-9-]{5,62}$').hasMatch(firebaseProjectId) ||
        !RegExp(r'(^demo-|-(test|staging)(-|$))').hasMatch(firebaseProjectId)) {
      throw StateError(
        'The Spark proof requires the fieldtest flavor and a separate Firebase test project.',
      );
    }
    if (backend.scheme != 'https' ||
        !RegExp(r'^[a-z0-9]{20}\.supabase\.co$').hasMatch(backend.host) ||
        backend.path != '/functions/v1/safepaths-report-proof' ||
        backend.hasPort ||
        backend.userInfo.isNotEmpty ||
        backend.hasQuery ||
        backend.hasFragment) {
      throw StateError(
        'Set the exact HTTPS Supabase report-proof function URL.',
      );
    }
  }

  bool ownsMediaReference(String value, {String? owner, String? purpose}) {
    final prefix = '$backend/media/';
    if (!value.startsWith(prefix)) return false;
    final parts = value.substring(prefix.length).split('/');
    return parts.length == 3 &&
        const ['avatar', 'feedback'].contains(parts[0]) &&
        (purpose == null || purpose == parts[0]) &&
        (owner == null || owner == parts[1]) &&
        RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(parts[1]) &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[2]);
  }

  bool ownsReference(String value, {String? owner}) {
    final prefix = '${backend.toString()}/photo/';
    if (!value.startsWith(prefix)) return false;
    final suffix = value.substring(prefix.length);
    return (owner == null || suffix.startsWith('$owner/')) &&
        RegExp(r'^[A-Za-z0-9_-]{1,128}/[a-f0-9]{64}$').hasMatch(suffix);
  }
}

class SparkProofException implements Exception {
  final String code;
  final String message;
  const SparkProofException(this.code, this.message);
  @override
  String toString() => message;
}

class SparkProofClient {
  final SparkProofConfiguration configuration;
  final Future<String?> Function() token;
  final http.Client _http;
  SparkProofClient({
    required this.configuration,
    required this.token,
    http.Client? client,
  }) : _http = client ?? http.Client();

  Future<Map<String, dynamic>> _post(
    String operation,
    List<int> bytes,
    String contentType, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bearer = await token().timeout(const Duration(seconds: 5));
    if (bearer == null || bearer.isEmpty) {
      throw const SparkProofException(
        'unauthenticated',
        'Please sign in with a verified test account.',
      );
    }
    final request =
        http.Request('POST', Uri.parse('${configuration.backend}/$operation'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $bearer',
            'Content-Type': contentType,
          })
          ..bodyBytes = bytes;
    try {
      final response = await (() async => http.Response.fromStream(
        await _http.send(request),
      ))().timeout(timeout);
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const SparkProofException(
          'unavailable',
          'The test backend returned an invalid response. Preserve the form and retry.',
        );
      }
      if (response.statusCode != 200 || data['error'] != null) {
        final error = data['error'];
        // Only known codes/messages are displayed. No provider body or URL is surfaced.
        final code = error is Map ? error['code'] : null;
        throw SparkProofException(
          code is String ? code : 'unavailable',
          _message(code),
        );
      }
      return data;
    } on SparkProofException {
      rethrow;
    } catch (_) {
      throw const SparkProofException(
        'unavailable',
        'The test service is unavailable. Preserve the form and retry.',
      );
    }
  }

  static String _message(Object? code) => switch (code) {
    'followup-required' =>
      'Open your report history and add a dated follow-up instead of replacing earlier evidence.',
    'unauthenticated' =>
      'Please refresh your sign-in and verify the test account email.',
    'permission-denied' =>
      'This account is not authorized for that test action or photo.',
    'resource-exhausted' =>
      'Please wait five minutes before sending another report.',
    'already-exists' =>
      'This request was already used for different content. Start a new report.',
    'failed-precondition' =>
      'Check the test profile, selected road and report location.',
    'too-large' => 'Choose a smaller JPEG photo.',
    'media-unavailable' =>
      'The uploaded image is unavailable. Attach it again.',
    'photo-unavailable' =>
      'Your uploaded photo is no longer available. Retry to upload it again.',
    'invalid-argument' =>
      'Check the report details and attach your own valid test photo.',
    _ =>
      'The test service could not complete the request. Preserve the form and retry.',
  };

  Future<Map<String, dynamic>> communicationCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const [
      'profile-context',
      'profile-save',
      'feedback-submit',
      'feedback-context',
      'feedback-action',
      'broadcast-publish',
      'broadcast-context',
      'broadcast-action',
    ].contains(operation))
      throw ArgumentError('Unknown communication operation.');
    Map<String, dynamic> response;
    try {
      response = await _post(
        operation,
        utf8.encode(jsonEncode({'data': data})),
        'application/json',
      );
    } on SparkProofException catch (e) {
      throw SparkProofException(e.code, switch (e.code) {
        'failed-precondition' =>
          operation.startsWith('profile-')
              ? 'The profile changed. Refresh the current profile before saving.'
              : 'The record changed. Refresh before saving this action.',
        'media-unavailable' =>
          'The attached image is unavailable. Retry the upload or remove the image before saving.',
        'resource-exhausted' =>
          'Wait one minute before submitting another feedback item or alert.',
        'permission-denied' => 'This account cannot perform that action.',
        'invalid-argument' =>
          operation.startsWith('profile-')
              ? 'Check the profile name, location and selected photo.'
              : 'Check the message, outcome, audience and validity period.',
        _ => 'The action was not confirmed. Keep it and retry.',
      });
    }
    if (response['result'] is! Map)
      throw const SparkProofException(
        'unavailable',
        'The action was not confirmed. Keep it and retry.',
      );
    return Map<String, dynamic>.from(response['result'] as Map);
  }

  Future<Map<String, dynamic>> roadCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const [
      'road-import',
      'road-delete-context',
      'road-delete',
      'road-graph-rebuild',
    ].contains(operation))
      throw ArgumentError('Unknown road maintenance operation.');
    Map<String, dynamic> response;
    try {
      response = await _post(
        operation,
        utf8.encode(jsonEncode({'data': data})),
        'application/json',
        timeout: const Duration(seconds: 60),
      );
    } on SparkProofException catch (e) {
      throw SparkProofException(e.code, switch (e.code) {
        'failed-precondition' =>
          'The road changed, has active conditions, or needs graph review. Refresh it before retrying.',
        'resource-exhausted' =>
          'Use a smaller maintenance batch or resolve active reports before retrying.',
        'permission-denied' =>
          'This account cannot maintain the selected test roads.',
        'invalid-argument' =>
          'Check the selected OSM segments and current road confirmation.',
        _ =>
          'Road maintenance was not confirmed. Preserve the selection and retry.',
      });
    }
    final result = response['result'];
    if (result is! Map)
      throw const SparkProofException(
        'unavailable',
        'The maintenance result was not confirmed. Retry.',
      );
    if (operation != 'road-delete-context') {
      bool count(String key) => result[key] is int && (result[key] as int) >= 0;
      final stats = result['graphStats'];
      if (result['saved'] != true ||
          result['operation'] != operation ||
          result['replay'] is! bool ||
          operation == 'road-import' &&
              (!count('createdCount') ||
                  !count('skippedCount') ||
                  (result['createdCount'] as int) +
                          (result['skippedCount'] as int) !=
                      (data['roads'] as List).length) ||
          operation == 'road-delete' &&
              result['deletedRoadId'] != data['roadId'] ||
          operation != 'road-delete' &&
              (stats is! Map ||
                  stats['totalRoads'] is! int ||
                  stats['avgNeighbors'] is! num ||
                  stats['maximumNeighbors'] is! int ||
                  stats['disconnectedRoads'] is! int))
        throw const SparkProofException(
          'unavailable',
          'The maintenance result was not confirmed. Preserve it and retry.',
        );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> coreCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const ['observe-incident', 'weather-override'].contains(operation))
      throw ArgumentError('Unknown core operation.');
    Map<String, dynamic> response;
    try {
      response = await _post(
        operation,
        utf8.encode(jsonEncode({'data': data})),
        'application/json',
      );
    } on SparkProofException catch (e) {
      throw SparkProofException(e.code, switch (e.code) {
        'self-confirmation' =>
          'Update your own report instead of confirming this incident.',
        'observation-stale' =>
          'This observation is too old. Observe current conditions safely and submit again.',
        'failed-precondition' =>
          'This incident changed or was resolved. Refresh its details.',
        'resource-exhausted' =>
          'Wait one minute before changing your observation.',
        _ => e.message,
      });
    }
    final result = response['result'];
    if (result is! Map || result['saved'] != true || result['replay'] is! bool)
      throw const SparkProofException(
        'unavailable',
        'The action was not confirmed. Keep it and retry.',
      );
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> adminCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const ['admin-context', 'admin-action'].contains(operation)) {
      throw ArgumentError('Unknown administrative operation.');
    }
    Map<String, dynamic> response;
    try {
      response = await _post(
        operation,
        utf8.encode(jsonEncode({'data': data})),
        'application/json',
      );
    } on SparkProofException catch (error) {
      throw SparkProofException(error.code, switch (error.code) {
        'self-review' =>
          'Another administrator must review your own report or follow-up.',
        'failed-precondition' =>
          'New information arrived or this report was already reviewed. Refresh the latest details before saving.',
        'resource-exhausted' => 'Review fewer roads or reports at a time.',
        'already-exists' =>
          'This retry identifier belongs to a different action. Refresh the review.',
        'invalid-argument' =>
          'Check the review details and verification source.',
        'permission-denied' =>
          'This account cannot perform administrator actions.',
        'unauthenticated' =>
          'Please sign in again with your verified administrator account.',
        _ => 'The action was not confirmed. Keep it and retry.',
      });
    }
    final result = response['result'];
    if (result is! Map)
      throw const SparkProofException(
        'unavailable',
        'The action was not confirmed. Preserve it and retry.',
      );
    return Map<String, dynamic>.from(result);
  }

  Future<String> uploadMedia(String purpose, Uint8List bytes) async {
    if (!const ['avatar', 'feedback'].contains(purpose) ||
        bytes.length > (purpose == 'avatar' ? 256 * 1024 : 2 * 1024 * 1024))
      throw const SparkProofException(
        'invalid-argument',
        'Choose a smaller prepared image.',
      );
    Map<String, dynamic> result;
    try {
      result = await _post(
        'media-upload/$purpose',
        bytes,
        'image/jpeg',
        timeout: const Duration(seconds: 45),
      );
    } on SparkProofException catch (e) {
      throw SparkProofException(
        e.code,
        e.code == 'resource-exhausted'
            ? 'The test image allowance is reached. Contact the project team.'
            : 'The image upload was not confirmed. Keep it and retry.',
      );
    }
    final reference = result['reference'];
    if (reference is! String ||
        !configuration.ownsMediaReference(reference, purpose: purpose))
      throw const SparkProofException(
        'unavailable',
        'The image upload was not confirmed. Keep it and retry.',
      );
    return reference;
  }

  Future<Uint8List> mediaBytes(String reference, {String? feedbackId}) async {
    if (!configuration.ownsMediaReference(reference))
      throw const SparkProofException(
        'invalid-argument',
        'This image does not belong to the test backend.',
      );
    final bearer = await token().timeout(const Duration(seconds: 5));
    if (bearer == null || bearer.isEmpty)
      throw const SparkProofException(
        'unauthenticated',
        'Sign in to view this image.',
      );
    final request =
        http.Request('POST', Uri.parse('${configuration.backend}/media-read'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $bearer',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'data': {
              'reference': reference,
              if (feedbackId != null) 'feedbackId': feedbackId,
            },
          });
    try {
      return await (() async {
        final response = await _http.send(request);
        if (response.statusCode != 200 ||
            response.headers['content-type']?.split(';')[0] != 'image/jpeg')
          throw const SparkProofException(
            'unavailable',
            'This image is unavailable. Refresh or retry.',
          );
        if ((response.contentLength ?? 0) > 2 * 1024 * 1024)
          throw const SparkProofException(
            'unavailable',
            'This image exceeds the display limit.',
          );
        final bytes = BytesBuilder(copy: false);
        var length = 0;
        await for (final chunk in response.stream) {
          length += chunk.length;
          if (length > 2 * 1024 * 1024)
            throw const SparkProofException(
              'unavailable',
              'This image exceeds the display limit.',
            );
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      })().timeout(const Duration(seconds: 20));
    } on SparkProofException {
      rethrow;
    } catch (_) {
      throw const SparkProofException(
        'unavailable',
        'Image delivery is unavailable. Retry.',
      );
    }
  }

  Future<String> upload(
    Uint8List bytes,
    void Function(double?) progress,
  ) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const SparkProofException(
        'too-large',
        'The prepared test photo exceeds 2 MB.',
      );
    }
    progress(
      null,
    ); // Honest indeterminate progress; completion requires server confirmation.
    final data = await _post(
      'photo-upload',
      bytes,
      'image/jpeg',
      timeout: const Duration(seconds: 45),
    );
    final reference = data['imageUrl'];
    if (reference is! String || !configuration.ownsReference(reference)) {
      throw const SparkProofException(
        'unavailable',
        'The photo was not confirmed by this test backend. Retry.',
      );
    }
    progress(1);
    return reference;
  }

  Future<Map<String, dynamic>> submit(Map<String, dynamic> data) async {
    final response = await _post(
      'submit-report',
      utf8.encode(jsonEncode({'data': data})),
      'application/json',
    );
    final result = response['result'];
    if (result is! Map ||
        result['reportId'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['reportId'] as String) ||
        result['replay'] is! bool) {
      throw const SparkProofException(
        'unavailable',
        'The report save was not confirmed. Preserve the form and retry.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<String> photoUrl(String reference) async {
    if (!configuration.ownsReference(reference)) {
      throw const SparkProofException(
        'invalid-argument',
        'This photo does not belong to the configured backend.',
      );
    }
    final response = await _post(
      'photo-url',
      utf8.encode(jsonEncode({'imageUrl': reference})),
      'application/json',
    );
    final value = response['url'];
    final signed = value is String ? Uri.tryParse(value) : null;
    final photo = reference.substring('${configuration.backend}/photo/'.length);
    final bucket = configuration.mainBackend
        ? 'report-photos-marulas'
        : 'report-photos-proof';
    if (signed == null ||
        signed.scheme != 'https' ||
        signed.host != configuration.backend.host ||
        signed.userInfo.isNotEmpty ||
        signed.hasPort ||
        signed.path != '/storage/v1/object/sign/$bucket/reports/$photo.jpg' ||
        signed.fragment.isNotEmpty ||
        signed.queryParameters['token']?.isNotEmpty != true) {
      throw const SparkProofException(
        'unavailable',
        'The protected photo is unavailable.',
      );
    }
    return value as String;
  }

  Future<Map<String, dynamic>> clarificationCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const [
      'clarification-context',
      'clarification-reply',
    ].contains(operation))
      throw ArgumentError('Unknown clarification operation.');
    final response = await _post(
      operation,
      utf8.encode(jsonEncode({'data': data})),
      'application/json',
    );
    final result = response['result'];
    if (result is! Map ||
        result['reportId'] != data['reportId'] ||
        operation == 'clarification-reply' && result['replay'] is! bool ||
        operation == 'clarification-context' &&
            (result['requestId'] is! String || result['canReply'] is! bool)) {
      throw StateError(
        'Clarification was not confirmed. Preserve your reply and retry.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> updateReport(Map<String, dynamic> data) async {
    final response = await _post(
      'update-report',
      utf8.encode(jsonEncode({'data': data})),
      'application/json',
    );
    final result = response['result'];
    if (result is! Map ||
        result['reportId'] != data['reportId'] ||
        result['replay'] is! bool)
      throw const SparkProofException(
        'unavailable',
        'The report update was not confirmed. Preserve it and retry.',
      );
  }

  Future<Map<String, dynamic>> followupCall(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!const ['followup-context', 'followup-submit'].contains(operation)) {
      throw ArgumentError('Unknown follow-up operation.');
    }
    Map<String, dynamic> response;
    try {
      response = await _post(
        operation,
        utf8.encode(jsonEncode({'data': data})),
        'application/json',
      );
    } on SparkProofException catch (error) {
      throw SparkProofException(error.code, switch (error.code) {
        'permission-denied' =>
          'Only the original reporter can add this follow-up. Authorized admins can review its history.',
        'failed-precondition' =>
          'The report or incident changed. Refresh the history before continuing.',
        'duplicate-evidence' =>
          'This repeats earlier evidence. Describe the change and use a current photo, or continue without a photo.',
        'observation-stale' =>
          'Choose a time newer than the last submission and within the past 24 hours.',
        'resource-exhausted' =>
          'Wait five minutes between submissions. Eligible worsening updates can be sent after one minute.',
        'already-exists' =>
          'This retry belongs to different details. Keep your draft and refresh the history.',
        'invalid-argument' =>
          'Check the changed condition, description, observation time and photo confirmation.',
        'photo-unavailable' =>
          'This photo is unavailable. Choose it again or submit without it.',
        _ => 'The follow-up was not confirmed. Keep your draft and retry.',
      });
    }
    final result = response['result'];
    if (result is! Map ||
        operation == 'followup-submit' &&
            (result['reportId'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(result['reportId'] as String) ||
                result['rootReportId'] != data['rootReportId'] ||
                result['replay'] is! bool)) {
      throw const SparkProofException(
        'unavailable',
        'The follow-up result was not confirmed. Keep your draft and retry.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> pushDevice(Map<String, dynamic> data) async {
    final response = await _post(
      'push-device',
      utf8.encode(jsonEncode({'data': data})),
      'application/json',
    );
    final result = response['result'];
    if (result is! Map ||
        result['registered'] != (data['mode'] == 'register') ||
        result['sequence'] != data['sequence']) {
      throw const SparkProofException(
        'unavailable',
        'Device registration was not confirmed. Retry notification setup.',
      );
    }
  }

  void close() => _http.close();
}
