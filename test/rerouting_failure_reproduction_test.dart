import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';

String encode(List<Position> points) {
  final b = StringBuffer();
  var lat = 0, lng = 0;
  void value(int delta) {
    var v = delta < 0 ? ~(delta << 1) : delta << 1;
    while (v >= 32) {
      b.writeCharCode((32 | (v & 31)) + 63);
      v >>= 5;
    }
    b.writeCharCode(v + 63);
  }

  for (final p in points) {
    final y = (p.lat * 1e5).round(), x = (p.lng * 1e5).round();
    value(y - lat);
    value(x - lng);
    lat = y;
    lng = x;
  }
  return b.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/marulas-serrano-detour.json').readAsStringSync(),
  );
  final data = fixture['closure'];
  final closure = RoadStatus(
    id: data['id'],
    name: data['name'],
    status: 'not_passable',
    notes: 'Controlled replay',
    updatedAt: DateTime(2026, 11, 9),
    geometry: Map<String, dynamic>.from(data['geometry']),
    riskScore: 80,
    isVerified: true,
  );
  final origin = Position(fixture['origin'][0], fixture['origin'][1]),
      destination = Position(
        fixture['destination'][0],
        fixture['destination'][1],
      );
  List<Map<String, dynamic>> response(String key) => [
    Map<String, dynamic>.from(fixture[key]),
  ];
  final routing = RoutingService.instance;
  test(
    'A direction-constrained NoRoute retries once without bearing before reporting no route',
    () async {
      final headings = <double?>[];
      final result = await routing.computeRoutes(
        origin: origin,
        destination: destination,
        headingDegrees: 90,
        roadsOverride: [closure],
        weatherStateOverride: WeatherState.clear,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              headings.add(headingDeg);
              return headingDeg == null ? response('turnbackDetour') : [];
            },
      );
      expect(result.any((r) => !r.isBlocked), isTrue);
      expect(headings, [90, null]);
    },
  );
  test('NoRoute without a bearing does not repeat the same request', () async {
    var calls = 0;
    final result = await routing.computeRoutes(
      origin: origin,
      destination: destination,
      roadsOverride: [closure],
      directionsFetcher:
          (
            a,
            b, {
            waypoints = const [],
            vehicleType = 'Sedan',
            headingDeg,
          }) async {
            calls++;
            return [];
          },
    );
    expect(result, isEmpty);
    expect(calls, 1);
  });
  test(
    'A failed detour request plus blocked results is unavailable, not a completed no-clear-route search',
    () async {
      var candidates = 0;
      final result = routing.computeRoutes(
        origin: origin,
        destination: destination,
        roadsOverride: [closure],
        weatherStateOverride: WeatherState.clear,
        maxDetourCandidates: 3,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              if (waypoints.isEmpty) return response('direct');
              if (++candidates == 1) throw const RoutingUnavailable();
              return response('constrainedDetour');
            },
      );
      await expectLater(result, throwsA(isA<RoutingUnavailable>()));
      expect(candidates, 3);
    },
  );
  test(
    'One failed detour request does not discard a separately checked clear MacArthur result',
    () async {
      var candidates = 0;
      final result = await routing.computeRoutes(
        origin: origin,
        destination: destination,
        roadsOverride: [closure],
        weatherStateOverride: WeatherState.clear,
        maxDetourCandidates: 3,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              if (waypoints.isEmpty) return response('direct');
              if (++candidates == 1) throw const RoutingUnavailable();
              return response('turnbackDetour');
            },
      );
      expect(
        RoutingService.routesAvoidingConfirmedClosures(result, [closure]),
        isNotEmpty,
      );
    },
  );
  test('A completed search returning only closures stays blocked', () async {
    final result = await routing.computeRoutes(
      origin: origin,
      destination: destination,
      roadsOverride: [closure],
      weatherStateOverride: WeatherState.clear,
      maxDetourCandidates: 3,
      directionsFetcher:
          (
            a,
            b, {
            waypoints = const [],
            vehicleType = 'Sedan',
            headingDeg,
          }) async => response('direct'),
    );
    expect(result, isNotEmpty);
    expect(
      RoutingService.routesAvoidingConfirmedClosures(result, [closure]),
      isEmpty,
    );
  });
  test(
    'A clean detour sharing start middle and end with a blocked route is not discarded as a duplicate',
    () async {
      final start = Position(120.980, 14.676),
          mid = Position(120.985, 14.680),
          end = Position(120.990, 14.676);
      final bad = [
        start,
        Position(120.985, 14.676),
        mid,
        Position(120.990, 14.680),
        end,
      ];
      final good = [
        start,
        Position(120.980, 14.680),
        mid,
        Position(120.990, 14.680),
        end,
      ];
      final road = RoadStatus(
        id: 'synthetic-closure',
        name: 'Simulated closed segment',
        status: 'not_passable',
        notes: 'Test only',
        updatedAt: DateTime.now(),
        riskScore: 80,
        isVerified: true,
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.984, 14.676],
            [120.986, 14.676],
          ],
        },
      );
      Map<String, dynamic> route(List<Position> p) => {
        'geometry': encode(p),
        'distance': 1500.0,
        'duration': 180.0,
        'legs': [],
      };
      final result = await routing.computeRoutes(
        origin: start,
        destination: end,
        roadsOverride: [road],
        weatherStateOverride: WeatherState.clear,
        maxDetourCandidates: 3,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [route(waypoints.isEmpty ? bad : good)],
      );
      final clear = RoutingService.routesAvoidingConfirmedClosures(result, [
        road,
      ]);
      expect(
        clear,
        hasLength(1),
        reason:
            'Different geometry must survive deduplication; identical returned detours should still collapse.',
      );
    },
  );
  for (final wrongStart in [false, true]) {
    test(
      'Rejects provider geometry with a distant ${wrongStart ? 'origin' : 'destination'}',
      () async {
        final a = Position(120.980, 14.676), b = Position(120.990, 14.676);
        final raw = {
          'geometry': encode([
            wrongStart ? Position(120.970, 14.676) : a,
            wrongStart ? b : Position(121.000, 14.676),
          ]),
          'distance': 1000.0,
          'duration': 180.0,
          'legs': [],
        };
        await expectLater(
          routing.computeRoutes(
            origin: a,
            destination: b,
            roadsOverride: [],
            directionsFetcher:
                (
                  a,
                  b, {
                  waypoints = const [],
                  vehicleType = 'Sedan',
                  headingDeg,
                }) async => [raw],
          ),
          throwsA(isA<RoutingUnavailable>()),
        );
      },
    );
  }
  test(
    'Nearby road snapping is allowed and a distant malformed alternative is filtered',
    () async {
      final a = Position(120.980, 14.676), b = Position(120.990, 14.676);
      final near = {
        'geometry': encode([a, Position(120.990, 14.6764)]),
        'distance': 1000.0,
        'duration': 180.0,
        'legs': [],
      };
      final far = {
        'geometry': encode([a, Position(121.000, 14.676)]),
        'distance': 1000.0,
        'duration': 180.0,
        'legs': [],
      };
      final result = await routing.computeRoutes(
        origin: a,
        destination: b,
        roadsOverride: [],
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => [far, near],
      );
      expect(result, hasLength(1));
      expect(result.single.requestedDestination!.lng, b.lng);
    },
  );
  test(
    'A bounded wider search samples both sides at the largest diversion distance',
    () async {
      final a = Position(120.980, 14.676), b = Position(120.990, 14.676);
      final closed = RoadStatus(
        id: 'synthetic-closure',
        name: 'Simulated closed segment',
        status: 'not_passable',
        notes: 'Test only',
        updatedAt: DateTime.now(),
        riskScore: 80,
        isVerified: true,
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [120.984, 14.676],
            [120.986, 14.676],
          ],
        },
      );
      final bad = {
        'geometry': encode([a, b]),
        'distance': 1000.0,
        'duration': 180.0,
        'legs': [],
      };
      final good = {
        'geometry': encode([
          a,
          Position(120.980, 14.690),
          Position(120.990, 14.690),
          b,
        ]),
        'distance': 3000.0,
        'duration': 600.0,
        'legs': [],
      };
      final offsets = <double>[];
      final result = await routing.computeRoutes(
        origin: a,
        destination: b,
        roadsOverride: [closed],
        weatherStateOverride: WeatherState.clear,
        maxDetourCandidates: 6,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              if (waypoints.isEmpty) return [bad];
              final offset = (waypoints.first.lat - 14.676).toDouble();
              offsets.add(offset);
              return [offset < -.010 ? good : bad];
            },
      );
      expect(offsets, hasLength(6));
      expect(offsets.any((d) => d > .010), isTrue);
      expect(offsets.any((d) => d < -.010), isTrue);
      expect(
        RoutingService.routesAvoidingConfirmedClosures(result, [closed]),
        isNotEmpty,
      );
    },
  );
}
