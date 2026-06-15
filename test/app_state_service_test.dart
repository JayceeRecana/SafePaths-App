import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/services/app_state_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({}); // Initialize SharedPreferences mock
  });

  test('AppStateService initialization seeds default data', () async {
    final service = AppStateService.instance;
    await service.initialize();

    expect(service.roads.length, 4);
    expect(service.reports.length, 3);
    expect(service.alerts.length, 3);
  });

  test('AppStateService updateRoadStatus updates status and triggers notification', () async {
    final service = AppStateService.instance;
    await service.initialize();

    bool notified = false;
    service.addListener(() {
      notified = true;
    });

    await service.updateRoadStatus('macarthur', 'passable', 'Underpass cleared');

    expect(service.roads.firstWhere((r) => r.id == 'macarthur').status, 'passable');
    expect(service.roads.firstWhere((r) => r.id == 'macarthur').notes, 'Underpass cleared');
    expect(notified, isTrue);
  });

  test('AppStateService submitReport appends a new user report', () async {
    final service = AppStateService.instance;
    await service.initialize();

    final initialCount = service.reports.length;

    await service.submitReport('Flooding: Rizal Ave', 'Heavy water pooling', 'High');

    expect(service.reports.length, initialCount + 1);
    expect(service.reports.first.title, 'Flooding: Rizal Ave');
    expect(service.reports.first.severity, 'High');
    expect(service.reports.first.status, 'pending');
  });

  test('AppStateService broadcastAlert appends a new alert notification', () async {
    final service = AppStateService.instance;
    await service.initialize();

    final initialCount = service.alerts.length;

    await service.broadcastAlert('Storm Warning', 'Heavy storm approaching.', 'Critical');

    expect(service.alerts.length, initialCount + 1);
    expect(service.alerts.first.title, 'Storm Warning');
    expect(service.alerts.first.severity, 'Critical');
  });
}
