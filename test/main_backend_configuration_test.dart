import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/services/spark_proof_client.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/test_road_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mainProject = 'safepaths-92c3d';
  const mainUrl =
      'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-main';
  const proofUrl =
      'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
  SparkProofConfiguration main({
    String project = mainProject,
    String url = mainUrl,
  }) => SparkProofConfiguration(
    firebaseProjectId: project,
    backendUrl: url,
    mainBackend: true,
  );
  void validate(
    SparkProofConfiguration config, {
    String flavor = 'production',
    String actual = mainProject,
  }) => config.validate(
    flavor: flavor,
    actualProjectId: actual,
    mainProjectId: mainProject,
  );

  test(
    'main target is explicit and cannot accept proof project, flavor, endpoint or foreign host',
    () {
      expect(() => validate(main()), returnsNormally);
      for (final config in [
        main(project: 'safepaths-test'),
        main(url: proofUrl),
        main(url: '$mainUrl?override=1'),
        main(
          url: mainUrl.replaceFirst(
            'bbteuzgfgnrjjrqewidc',
            'aaaaaaaaaaaaaaaaaaaa',
          ),
        ),
      ]) {
        expect(() => validate(config), throwsStateError);
      }
      expect(() => validate(main(), flavor: 'fieldtest'), throwsStateError);
      expect(
        () => validate(main(), actual: 'safepaths-test'),
        throwsStateError,
      );
      expect(
        () => validate(
          SparkProofConfiguration(
            firebaseProjectId: mainProject,
            backendUrl: proofUrl,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'main and proof photo references remain isolated for reports, avatars and feedback',
    () {
      final production = main();
      final proof = SparkProofConfiguration(
        firebaseProjectId: 'safepaths-test',
        backendUrl: proofUrl,
      );
      final digest = 'a' * 64;
      expect(
        production.ownsReference(
          '$mainUrl/photo/resident/$digest',
          owner: 'resident',
        ),
        isTrue,
      );
      expect(
        production.ownsReference('$proofUrl/photo/resident/$digest'),
        isFalse,
      );
      expect(proof.ownsReference('$mainUrl/photo/resident/$digest'), isFalse);
      expect(
        production.ownsMediaReference(
          '$mainUrl/media/avatar/resident/$digest',
          owner: 'resident',
          purpose: 'avatar',
        ),
        isTrue,
      );
      expect(
        production.ownsMediaReference(
          '$proofUrl/media/avatar/resident/$digest',
        ),
        isFalse,
      );
    },
  );
  test(
    'main opt-in connects the complete service bundle and uses Marulas geography',
    () {
      if (!AppEnvironment.mainBackendRequested) return;
      expect(AppEnvironment.name, 'production');
      expect(AppEnvironment.area.id, 'marulas');
      expect(AppEnvironment.sparkCoreEnabled, isTrue);
      expect(AppEnvironment.sparkReportsRequested, isTrue);
      expect(AppEnvironment.sparkMediaEnabled, isTrue);
      expect(AppEnvironment.sparkCommunicationsEnabled, isTrue);
      expect(AppEnvironment.communicationPushAllowed, isTrue);
      expect(
        AppEnvironment.sparkFollowupsEnabled,
        const bool.fromEnvironment('SAFEPATHS_FOLLOWUPS_ENABLED'),
      );
    },
  );
  test(
    'risk weather accepts only the active study area rather than nearby weather in Marulas',
    () {
      final service = SimulatedWeatherService.forTesting();
      addTearDown(service.dispose);
      final data = <String, dynamic>{
        'studyArea': AppEnvironment.area.id,
        'available': true,
        'source': 'open-meteo',
        'isOverrideMode': false,
        'currentState': 'heavyRain',
        'observedAt': DateTime.now(),
        'precipitationIntensity': 20.0,
        'windSpeed': 3.0,
        'temperature': 29.0,
        'humidity': 75.0,
      };
      service.applyCoreWeather(data);
      expect(service.isDataStale, isFalse);
      service.applyCoreWeather({
        ...data,
        'studyArea': AppEnvironment.isFieldTest ? 'marulas' : 'nearby_test',
      });
      expect(service.isDataStale, isTrue);
    },
  );
  test('legacy map segment matching ignores reversed coordinate order', () {
    final line = [
      <String, double>{'lng': 120.984, 'lat': 14.675},
      <String, double>{'lng': 120.984, 'lat': 14.677},
    ];
    expect(
      TestRoadImport.segmentKey(line),
      TestRoadImport.segmentKey(line.reversed.toList()),
    );
    expect(
      TestRoadImport.segmentKey(line),
      isNot(
        TestRoadImport.segmentKey([
          line.first,
          {'lng': 120.985, 'lat': 14.677},
        ]),
      ),
    );
  });
}
