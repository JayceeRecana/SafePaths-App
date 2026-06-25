import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Consensus Engine Tests', () {
    // Isolated version of the confidence algorithm for mathematical proof
    double calculateConfidence({
      required double baseAuthority,
      required double hoursOld,
      required bool hasPhoto,
      required List<String> otherReportSeverities,
      required String mySeverity,
    }) {
      double authority = baseAuthority;
      if (hasPhoto) {
        authority = (authority + 30.0).clamp(0, 100);
      }

      // Default weather decay window = 12 hours
      double recency = 100.0 - (hoursOld * (100.0 / 12.0));
      if (recency < 0) recency = 0;

      double consensus = 0.0;
      for (var severity in otherReportSeverities) {
        if (severity == mySeverity) {
          consensus += 15.0; // High agreement
        } else {
          consensus -= 10.0; // Conflicting reports
        }
      }

      double total = (authority * 0.4) + (recency * 0.4) + (consensus * 0.2);
      return total.clamp(0.0, 100.0);
    }

    test('High agreement increases confidence', () {
      double soloConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 1.0,
        hasPhoto: false,
        otherReportSeverities: [],
        mySeverity: 'High',
      );

      double agreedConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 1.0,
        hasPhoto: false,
        otherReportSeverities: ['High', 'High'],
        mySeverity: 'High',
      );

      expect(agreedConfidence > soloConfidence, true);
    });

    test('Conflicting reports decrease confidence', () {
      double soloConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 1.0,
        hasPhoto: false,
        otherReportSeverities: [],
        mySeverity: 'High',
      );

      double conflictConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 1.0,
        hasPhoto: false,
        otherReportSeverities: ['Low', 'Low'],
        mySeverity: 'High',
      );

      expect(conflictConfidence < soloConfidence, true);
    });

    test('Aged reports decay to 0 recency', () {
      double freshConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 0.0,
        hasPhoto: false,
        otherReportSeverities: [],
        mySeverity: 'High',
      );

      double agedConfidence = calculateConfidence(
        baseAuthority: 50.0,
        hoursOld: 24.0, // Past the 12 hour window
        hasPhoto: false,
        otherReportSeverities: [],
        mySeverity: 'High',
      );

      expect(agedConfidence < freshConfidence, true);
    });
  });
}
