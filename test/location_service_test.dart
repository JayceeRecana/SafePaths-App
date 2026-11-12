import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safepaths_app/services/location_service.dart';

class FakePositions extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Future<Position> Function()? locate;
  Position? cached;
  LocationSettings? oneShotSettings;
  final settings = <LocationSettings?>[];
  final events = StreamController<Position>.broadcast();
  int requests = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requests++;
    oneShotSettings = locationSettings;
    return locate!();
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cached;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    return events.stream;
  }
}

void main() {
  late GeolocatorPlatform previous;
  late FakePositions fake;
  Position fix({double accuracy = 5, int ageSeconds = 0}) => Position(
    latitude: 14.676,
    longitude: 120.980,
    timestamp: DateTime.now().subtract(Duration(seconds: ageSeconds)),
    accuracy: accuracy,
    altitude: 3,
    altitudeAccuracy: 2,
    heading: 45,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );
  setUp(() {
    previous = GeolocatorPlatform.instance;
    fake = FakePositions();
    GeolocatorPlatform.instance = fake;
  });
  tearDown(() async {
    GeolocatorPlatform.instance = previous;
    await fake.events.close();
  });
  test(
    'one-shot acquisition preserves GPS metadata and bounds the native request',
    () async {
      final sample = fix();
      fake.locate = () async => sample;
      expect(await LocationService.getCurrentFix(), same(sample));
      expect(fake.oneShotSettings!.timeLimit, const Duration(seconds: 15));
      expect(fake.oneShotSettings!.accuracy, LocationAccuracy.high);
      final point = await LocationService.getCurrentPosition();
      expect(point!.lat, sample.latitude);
      expect(point.lng, sample.longitude);
    },
  );
  test(
    'planner coordinate wrapper rejects inaccurate fixes while raw fix remains inspectable',
    () async {
      final sample = fix(accuracy: 90);
      fake.locate = () async => sample;
      expect(await LocationService.getCurrentFix(), same(sample));
      expect(await LocationService.getCurrentPosition(), isNull);
    },
  );
  test(
    'a timed-out request can expose stale cache metadata but cannot pass planner GPS admission',
    () async {
      fake.locate = () => Future.error(TimeoutException('Synthetic timeout'));
      fake.cached = fix(ageSeconds: 120);
      expect(await LocationService.getCurrentFix(), same(fake.cached));
      expect(await LocationService.getCurrentPosition(), isNull);
    },
  );
  test(
    'disabled services and denied permission never start a location request',
    () async {
      fake.enabled = false;
      expect(await LocationService.getCurrentFix(), isNull);
      fake.enabled = true;
      fake.permission = LocationPermission.deniedForever;
      expect(await LocationService.getCurrentFix(), isNull);
      expect(fake.requests, 0);
    },
  );
  test(
    'shared location subscribers allow fresh fixes without requiring movement',
    () async {
      final first = <Position>[], second = <Position>[];
      final a = LocationService.getPositionStream().listen(first.add);
      final b = LocationService.getPositionStream().listen(second.add);
      final one = fix(), two = fix();
      fake.events.add(one);
      fake.events.add(two);
      await Future<void>.delayed(Duration.zero);
      expect(first, [one, two]);
      expect(second, [one, two]);
      expect(
        fake.settings.every(
          (s) => s!.distanceFilter == 0 && s.accuracy == LocationAccuracy.high,
        ),
        isTrue,
      );
      await a.cancel();
      await b.cancel();
    },
  );
}
