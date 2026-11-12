import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/services/core_operation_repository.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'core action preserves opaque retry identity after response loss and clears on confirmation',
    () async {
      final sent = <Map<String, dynamic>>[];
      final repo = CoreOperationRepository(
        environment: 'fieldtest',
        account: () => 'resident',
        call: (operation, data) async {
          sent.add(data);
          if (sent.length == 1)
            throw const SparkProofException('unavailable', 'Retry');
          return {'saved': true, 'replay': true};
        },
      );
      const payload = {
        'roadId': 'private-road',
        'incidentId': 'private-incident',
        'choice': 'appears_passable',
      };
      await expectLater(
        repo.run('observe-incident', payload),
        throwsA(isA<SparkProofException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().single, isNot(contains('private-road')));
      expect(
        prefs.getString(prefs.getKeys().single),
        isNot(contains('private-incident')),
      );
      await repo.run('observe-incident', payload);
      expect(sent[1], sent[0]);
      expect(prefs.getKeys(), isEmpty);
    },
  );
  test(
    'stale observations get a new receipt and invalid acknowledgement remains retryable',
    () async {
      final sent = <Map<String, dynamic>>[];
      final repo = CoreOperationRepository(
        environment: 'fieldtest',
        account: () => 'resident',
        call: (operation, data) async {
          sent.add(data);
          if (sent.length == 1)
            throw const SparkProofException(
              'observation-stale',
              'Observe again',
            );
          return {'saved': false, 'replay': false};
        },
      );
      await expectLater(
        repo.run('observe-incident', {'choice': 'still_flooded'}),
        throwsA(isA<SparkProofException>()),
      );
      await expectLater(
        repo.run('observe-incident', {'choice': 'still_flooded'}),
        throwsA(isA<SparkProofException>()),
      );
      expect(sent[1]['requestId'], isNot(sent[0]['requestId']));
      expect((await SharedPreferences.getInstance()).getKeys(), isNotEmpty);
    },
  );
  test('concurrent identical actions share a single server save', () async {
    var calls = 0;
    final repo = CoreOperationRepository(
      environment: 'fieldtest',
      account: () => 'resident',
      call: (operation, data) async {
        calls++;
        return {'saved': true, 'replay': false};
      },
    );
    await Future.wait([
      repo.run('observe-incident', {'choice': 'still_flooded'}),
      repo.run('observe-incident', {'choice': 'still_flooded'}),
    ]);
    expect(calls, 1);
  });
  Map<String, dynamic> snapshot() => {
    'studyArea': AppEnvironment.area.id,
    'available': true,
    'source': 'open-meteo',
    'isOverrideMode': false,
    'currentState': 'heavyRain',
    'observedAt': DateTime.now(),
    'precipitationIntensity': 20,
    'windSpeed': 10,
    'temperature': 28,
    'humidity': 80,
    'forecast': [
      {
        'time': DateTime.now().add(const Duration(hours: 1)),
        'temperature': 27,
        'rainChance': 60,
        'state': 'moderateRain',
      },
    ],
  };
  test(
    'weather requires fresh area-matched server data and does not fabricate hourly forecasts',
    () {
      final service = SimulatedWeatherService.forTesting();
      addTearDown(service.dispose);
      expect(service.isDataStale, true);
      expect(service.getHourlyForecast(), isEmpty);
      service.applyCoreWeather(snapshot());
      expect(service.isDataStale, false);
      expect(service.getHourlyForecast().length, 1);
      service.applyCoreWeather(snapshot(), fromCache: true);
      expect(service.isDataStale, true);
      expect(service.getHourlyForecast(), isEmpty);
      service.applyCoreWeather({
        ...snapshot(),
        'observedAt': DateTime.now().subtract(const Duration(minutes: 31)),
      });
      expect(service.isDataStale, true);
      expect(
        service.getWeatherDescription(service.currentState),
        'Weather unavailable',
      );
      service.applyCoreWeather({
        ...snapshot(),
        'observedAt': DateTime.now().add(const Duration(minutes: 2)),
      });
      expect(service.isDataStale, true);
      service.applyCoreWeather({
        ...snapshot(),
        'studyArea': AppEnvironment.isFieldTest ? 'marulas' : 'nearby_test',
      });
      expect(service.isDataStale, true);
    },
  );
  test(
    'expired drill is unavailable rather than a fresh live weather reading',
    () {
      final service = SimulatedWeatherService.forTesting();
      addTearDown(service.dispose);
      service.applyCoreWeather({
        ...snapshot(),
        'source': 'admin-drill',
        'isOverrideMode': true,
        'overrideExpiresAt': DateTime.now().subtract(
          const Duration(seconds: 1),
        ),
      });
      expect(service.isDataStale, true);
      expect(service.getHourlyForecast(), isEmpty);
      service.currentState;
      expect(service.isDataStale, true);
    },
  );
}
