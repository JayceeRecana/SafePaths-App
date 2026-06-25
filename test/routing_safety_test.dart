import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Routing Safety Cost Engine', () {
    double calculateRouteCost({
      required double distanceMeters,
      required double avgRisk,
      required double maxRisk,
      required String status,
    }) {
      double routeCost = distanceMeters + (avgRisk * 10.0) + (maxRisk * 50.0);
      
      if (status == 'critical') {
        routeCost += 50000.0;
      }
      return routeCost;
    }

    test('Safer routes receive lower costs (equal distance)', () {
      double safeRouteCost = calculateRouteCost(
        distanceMeters: 1000.0,
        avgRisk: 0.0,
        maxRisk: 0.0,
        status: 'safe',
      );

      double riskyRouteCost = calculateRouteCost(
        distanceMeters: 1000.0,
        avgRisk: 20.0,
        maxRisk: 50.0,
        status: 'caution',
      );

      expect(safeRouteCost < riskyRouteCost, true);
    });

    test('Critical status applies massive penalty', () {
      double safeRouteCost = calculateRouteCost(
        distanceMeters: 1000.0,
        avgRisk: 0.0,
        maxRisk: 0.0,
        status: 'safe',
      );

      double criticalRouteCost = calculateRouteCost(
        distanceMeters: 1000.0,
        avgRisk: 80.0,
        maxRisk: 95.0,
        status: 'critical',
      );

      expect(criticalRouteCost > safeRouteCost + 50000.0, true);
    });

    test('Routing prefers slightly longer safe route over shorter risky route', () {
      double longerSafeRouteCost = calculateRouteCost(
        distanceMeters: 1500.0,
        avgRisk: 0.0,
        maxRisk: 0.0,
        status: 'safe',
      );

      double shorterRiskyRouteCost = calculateRouteCost(
        distanceMeters: 1000.0,
        avgRisk: 40.0, // Cost = +400
        maxRisk: 60.0, // Cost = +3000
        status: 'warning',
      );
      
      // longerSafeRouteCost = 1500
      // shorterRiskyRouteCost = 1000 + 400 + 3000 = 4400

      expect(longerSafeRouteCost < shorterRiskyRouteCost, true);
    });
  });
}
