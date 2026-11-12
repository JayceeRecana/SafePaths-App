import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/models/planned_route.dart';

void main() {
  test('small server clock differences do not flap a connected risk feed', () {
    final now = DateTime(2026, 11, 8, 17, 28);
    final health = SyncHealth(now: () => now);
    for (final channel in health.channels.keys.toList()) {
      health.update(channel, fromCache: false);
    }
    health.lastRiskCompute = now.add(const Duration(seconds: 2));
    expect(health.riskFresh, isTrue);
    expect(health.healthy, isTrue);
    expect(health.affectedFeeds, isEmpty);
    health.lastRiskCompute = now.add(SyncHealth.allowedClockSkew);
    expect(health.riskFresh, isTrue);
    health.lastRiskCompute = now.add(const Duration(seconds: 31));
    expect(health.healthy, isFalse);
    expect(health.affectedFeeds, ['Risk estimates']);
  });
  test(
    'clock tolerance never extends old risk data or hides a failed feed',
    () {
      final now = DateTime(2026, 11, 8, 17, 28);
      final health = SyncHealth(now: () => now);
      for (final channel in health.channels.keys.toList()) {
        health.update(channel, fromCache: false);
      }
      health.lastRiskCompute = now.subtract(
        const Duration(minutes: 4, seconds: 59),
      );
      expect(health.healthy, isTrue);
      health.lastRiskCompute = now.subtract(SyncHealth.riskMaxAge);
      expect(health.riskFresh, isFalse);
      expect(health.affectedFeeds, ['Risk estimates']);
      health.lastRiskCompute = now;
      health.update('risk', fromCache: true);
      expect(health.healthy, isFalse);
      expect(health.affectedFeeds, ['Risk estimates']);
      health.update('risk', fromCache: false);
      health.fail('alerts');
      expect(health.affectedFeeds, ['Area alerts']);
      expect(health.healthy, isFalse);
    },
  );
  test(
    'cache, errors, and stale scheduler heartbeat never count as live health',
    () {
      final health = SyncHealth();
      expect(health.healthy, isFalse);
      for (final channel in health.channels.keys.toList()) {
        health.update(channel, fromCache: false);
      }
      expect(health.healthy, isFalse);
      health.lastRiskCompute = DateTime.now();
      expect(health.healthy, isTrue);
      final confirmed = health.lastRoadSync;
      health.update('roads', fromCache: true);
      expect(health.healthy, isFalse);
      expect(health.lastRoadSync, confirmed);
      health.update('roads', fromCache: false);
      health.fail('alerts');
      expect(health.failed, isTrue);
      expect(health.healthy, isFalse);
      health.update('alerts', fromCache: false);
      health.lastRiskCompute = DateTime.now().subtract(
        const Duration(minutes: 6),
      );
      expect(health.healthy, isFalse);
      health.reset();
      expect(
        health.channels.values.every((s) => s == SyncCondition.connecting),
        isTrue,
      );
    },
  );

  test(
    'failed recalculation cannot leave a previous route available to start',
    () async {
      final service = RoutingService.instance;
      service.routes = [
        PlannedRoute(
          points: [Position(120.984, 14.676), Position(120.985, 14.676)],
          durationMin: 1,
          distanceMiles: 0.1,
          summary: 'Previous destination',
          hazardAlerts: [],
          safetyStatus: 'safe',
          steps: [],
        ),
      ];
      service.originPoint = Position(120.984, 14.676);
      service.destinationPoint = Position(120.99, 14.676);
      // No provider configuration in this test: the new request fails.
      await service.calculateRoute();
      expect(service.routes, isEmpty);
      expect(service.routeErrorMessage, isNotNull);
      expect(service.isRouteLoading, isFalse);
      service.exitPlanning();
    },
  );
}
