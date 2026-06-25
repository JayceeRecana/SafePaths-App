import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/config/risk_config.dart';

void main() {
  group('Risk Engine Threshold Tests', () {
    String getCategory(double finalScore) {
      if (finalScore >= RiskConfig.warningThreshold) return 'Critical';
      if (finalScore >= RiskConfig.watchThreshold) return 'Warning';
      if (finalScore >= RiskConfig.safeThreshold) return 'Watch';
      return 'Safe';
    }

    test('Score 29 should be Safe', () {
      expect(getCategory(29.0), 'Safe');
    });

    test('Score 30 should be Watch', () {
      expect(getCategory(30.0), 'Watch');
    });

    test('Score 59.9 should be Watch', () {
      expect(getCategory(59.9), 'Watch');
    });

    test('Score 60 should be Warning', () {
      expect(getCategory(60.0), 'Warning');
    });

    test('Score 79.9 should be Warning', () {
      expect(getCategory(79.9), 'Warning');
    });

    test('Score 80 should be Critical', () {
      expect(getCategory(80.0), 'Critical');
    });

    test('Score 100 should be Critical', () {
      expect(getCategory(100.0), 'Critical');
    });
  });
}
