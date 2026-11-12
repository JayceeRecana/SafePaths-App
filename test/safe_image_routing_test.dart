import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/widgets/safe_image.dart';

void main() {
  for (final endpoint in ['safepaths-main', 'safepaths-report-proof']) {
    test('$endpoint report and media references use protected readers', () {
      expect(
        protectedImageKind(
          'https://example.supabase.co/functions/v1/$endpoint/photo/resident/hash',
        ),
        ProtectedImageKind.report,
      );
      expect(
        protectedImageKind(
          'https://example.supabase.co/functions/v1/$endpoint/media/avatar/resident/hash',
        ),
        ProtectedImageKind.media,
      );
    });
  }
  test('Public, legacy, insecure and unrelated paths are not misclassified', () {
    for (final url in [
      'https://example.com/flood.jpg',
      'data:image/png;base64,AA==',
      'http://example.com/functions/v1/safepaths-main/photo/resident/hash',
      'https://example.com/functions/v1/safepaths-main/photo-url',
      'https://example.com/functions/v1/safepaths-other/photo/resident/hash',
      'https://example.com/flood.jpg?reference=/functions/v1/safepaths-main/photo/a/b',
    ])
      expect(protectedImageKind(url), isNull);
  });
}
