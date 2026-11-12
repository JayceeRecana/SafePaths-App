import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;
import 'package:safepaths_app/models/planned_route.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/screens/user/navigation_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:safepaths_app/services/weather_service.dart';

class Replay {
  final Map<String, dynamic> data;
  final List<RoadStatus> roads;
  final PlannedRoute initial;
  final List<PlannedRoute> alternatives;
  Replay(this.data, this.roads, this.initial, this.alternatives);
  List<Position> get gps =>
      (data['gps'] as List).map((p) => Position(p[0], p[1])).toList();
  String get name => '${data['trip']} / ${data['mode']}';
  String get closureId => data['closure']['id'];
  bool get hasAlternative => data['outcome'] == 'clear_route_found';
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/marulas-moving-closures.json').readAsStringSync(),
  );
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  final replay = <String, Replay>{};
  final app = AppStateService.instance;
  final routing = RoutingService.instance;
  late StreamController<geo.Position> gps;
  late DateTime now;
  late List<Position> displayed;
  late List<Map<String, dynamic>> requests;
  late Future<List<PlannedRoute>> Function() respond;
  late Replay active;

  setUpAll(() async {
    dotenv.loadFromString(envString: 'NAVIGATION_TEST=true');
    SimulatedWeatherService.instance;
    for (final c in cases) {
      final roads = (fixture['roads'] as List)
          .map(
            (r) => RoadStatus(
              id: r['id'],
              name: r['name'],
              status: 'passable',
              notes: 'Virtual only',
              updatedAt: DateTime.now(),
              geometry: Map<String, dynamic>.from(r['geometry']),
              isVerified: true,
            ),
          )
          .toList();
      if (!roads.any((r) => r.id == c['closure']['id']))
        roads.add(
          RoadStatus(
            id: c['closure']['id'],
            name: c['closure']['name'],
            status: 'passable',
            notes: 'Virtual segment only',
            updatedAt: DateTime.now(),
            geometry: Map<String, dynamic>.from(c['closure']['geometry']),
            isVerified: true,
          ),
        );
      final origin = Position(c['origin'][0], c['origin'][1]);
      final dest = Position(c['destination'][0], c['destination'][1]);
      final initial = (await routing.computeRoutes(
        origin: origin,
        destination: dest,
        vehicleType: c['mode'],
        roadsOverride: roads,
        weatherStateOverride: WeatherState.clear,
        allowDetourGeneration: false,
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async => List<Map<String, dynamic>>.from(c['baseline']),
      )).first;
      final point = c['gps'].last;
      final updated = [
        for (final r in roads)
          r.id == c['closure']['id'] ? r.copyWith(status: 'not_passable') : r,
      ];
      final alternatives = await routing.computeRoutes(
        origin: Position(point[0], point[1]),
        destination: dest,
        vehicleType: c['mode'],
        roadsOverride: updated,
        weatherStateOverride: WeatherState.clear,
        avoidRoadIds: {c['closure']['id']},
        directionsFetcher:
            (
              a,
              b, {
              waypoints = const [],
              vehicleType = 'Sedan',
              headingDeg,
            }) async {
              final match = (c['requests'] as List).firstWhere((x) {
                final w = x['waypoints'] as List;
                if (w.length != waypoints.length) return false;
                for (var i = 0; i < w.length; i++) {
                  if ((w[i][0] - waypoints[i].lng).abs() > 1e-6 ||
                      (w[i][1] - waypoints[i].lat).abs() > 1e-6)
                    return false;
                }
                return true;
              });
              return List<Map<String, dynamic>>.from(
                match['response']['routes'],
              );
            },
      );
      replay['${c['trip']} / ${c['mode']}'] = Replay(
        c,
        roads,
        initial,
        alternatives,
      );
    }
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  setUp(() {
    gps = StreamController<geo.Position>();
    now = DateTime.now();
    displayed = [];
    requests = [];
    app.roads.clear();
    routing.destinationPoint = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });
  Future<void> tick(WidgetTester t, int seconds) async {
    now = now.add(Duration(seconds: seconds));
    await t.pump(Duration(seconds: seconds));
    await t.pump();
  }

  Future<void> fix(WidgetTester t, Position p, {double accuracy = 5}) async {
    gps.add(
      geo.Position(
        latitude: p.lat.toDouble(),
        longitude: p.lng.toDouble(),
        timestamp: now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 90,
        headingAccuracy: 5,
        speed: 1,
        speedAccuracy: 0,
      ),
    );
    await t.pump();
    await t.pump();
  }

  Future<void> start(WidgetTester t, Map<String, dynamic> c) async {
    active = replay['${c['trip']} / ${c['mode']}']!;
    app.roads.addAll(active.roads);
    routing.selectedVehicleType = c['mode'];
    respond = () async => active.alternatives;
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: NavigationScreen(
          route: active.initial,
          positionStream: gps.stream,
          now: () => now,
          mapBuilder: (points) {
            displayed = points;
            return const SizedBox.expand();
          },
          stagingSearch: (_) async => null,
          routeComputer:
              ({
                required origin,
                required destination,
                required vehicleType,
                headingDegrees,
                required avoidRoadIds,
                required maxDetourCandidates,
              }) {
                requests.add({
                  'origin': origin,
                  'destination': destination,
                  'mode': vehicleType,
                  'avoid': Set<String>.of(avoidRoadIds),
                  'cap': maxDetourCandidates,
                });
                return respond();
              },
        ),
      ),
    );
    for (final p in active.gps) {
      await fix(t, p);
      await tick(t, 1);
    }
    expect(
      requests,
      isEmpty,
      reason:
          'Following the captured initial route must not trigger off-route reroutes',
    );
  }

  Future<void> close(WidgetTester t) async {
    await app.updateRoadStatus(
      active.closureId,
      'not_passable',
      'Simulated closure',
    );
    await tick(t, 1);
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    unawaited(gps.close());
    await t.pump();
  }

  void endpoints() {
    for (final r in requests) {
      expect(
        (r['destination'] as Position).lng,
        active.initial.requestedDestination!.lng,
      );
      expect(
        (r['destination'] as Position).lat,
        active.initial.requestedDestination!.lat,
      );
      expect(r['mode'], active.data['mode']);
      expect(r['cap'], 6);
    }
  }

  void outcome() {
    if (active.hasAlternative) {
      expect(
        RoutingService.doesRouteCrossGeometry(
          displayed,
          Map<String, dynamic>.from(active.data['closure']['geometry']),
        ),
        isFalse,
      );
      expect(
        displayed,
        same(active.alternatives.firstWhere((r) => !r.isBlocked).points),
      );
      expect(find.text('Guidance paused'), findsNothing);
    } else {
      expect(displayed, same(active.initial.points));
      expect(find.text('Guidance paused'), findsOneWidget);
    }
  }

  for (final c in cases) {
    final label = '${c['trip']} / ${c['mode']}';
    testWidgets('Marulas moving closure: $label', (t) async {
      await start(t, c);
      await close(t);
      expect(requests, hasLength(1));
      expect(requests.single['avoid'], contains(active.closureId));
      expect((requests.single['origin'] as Position).lng, active.gps.last.lng);
      expect((requests.single['origin'] as Position).lat, active.gps.last.lat);
      endpoints();
      outcome();
      expect(t.takeException(), isNull);
      await finish(t);
    });
    if (c['mode'] != 'Sedan' || c['drawn'] == true) continue;
    testWidgets('Marulas unrelated closure leaves route unchanged: $label', (
      t,
    ) async {
      await start(t, c);
      final road = active.roads.firstWhere(
        (r) => !RoutingService.doesRouteCrossGeometry(
          active.initial.points,
          r.geometry,
        ),
      );
      await app.updateRoadStatus(
        road.id,
        'not_passable',
        'Unrelated virtual closure',
      );
      await tick(t, 2);
      expect(requests, isEmpty);
      expect(displayed, same(active.initial.points));
      await finish(t);
    });
    testWidgets(
      'Marulas unreliable GPS queues closure until recovery: $label',
      (t) async {
        await start(t, c);
        await fix(t, active.gps.last, accuracy: 200);
        await close(t);
        expect(requests, isEmpty);
        await fix(t, active.gps.last);
        await tick(t, 1);
        expect(requests, hasLength(1));
        endpoints();
        outcome();
        await finish(t);
      },
    );
    testWidgets('Marulas failed request stays paused and retries: $label', (
      t,
    ) async {
      await start(t, c);
      respond = () async => throw const RoutingUnavailable();
      await close(t);
      expect(requests, hasLength(1));
      expect(displayed, same(active.initial.points));
      expect(find.text('Guidance paused'), findsOneWidget);
      respond = () async => active.alternatives;
      for (var i = 0; i < 3; i++) {
        await tick(t, 5);
        await fix(t, active.gps.last);
      }
      await tick(t, 3);
      expect(requests.length, greaterThanOrEqualTo(2));
      endpoints();
      outcome();
      await finish(t);
    });
    testWidgets('Marulas closure behind progress does not reroute: $label', (
      t,
    ) async {
      await start(t, c);
      final index = (active.initial.points.length * .45).floor();
      final next = active.initial.points[index];
      await fix(t, next);
      await tick(t, 1);
      final old = active.initial.points.first;
      final geometry = <String, dynamic>{
        'type': 'LineString',
        'coordinates': [
          [old.lng, old.lat],
          [old.lng + .00001, old.lat + .00001],
        ],
      };
      await app.updateRoadStatus(
        'virtual-behind',
        'not_passable',
        'Already travelled short test segment',
        name: 'Virtual segment behind',
        geometry: geometry,
      );
      await tick(t, 2);
      expect(requests, isEmpty);
      expect(displayed, same(active.initial.points));
      await finish(t);
    });
    testWidgets(
      'Marulas new closure during calculation cannot adopt a blocked detour: $label',
      (t) async {
        await start(t, c);
        final pending = Completer<List<PlannedRoute>>();
        respond = () => pending.future;
        await close(t);
        expect(requests, hasLength(1));
        final best = active.alternatives.firstWhere((r) => !r.isBlocked);
        final p = best.points[best.points.length ~/ 2];
        final geometry = <String, dynamic>{
          'type': 'LineString',
          'coordinates': [
            [p.lng - .00008, p.lat],
            [p.lng + .00008, p.lat],
          ],
        };
        await app.updateRoadStatus(
          'virtual-second',
          'not_passable',
          'New virtual closure during computation',
          name: 'New detour closure',
          geometry: geometry,
        );
        respond = () async => active.alternatives;
        pending.complete(active.alternatives);
        await t.pump();
        await t.pump();
        await tick(t, 5);
        await fix(t, active.gps.last);
        await tick(t, 4);
        if (identical(displayed, active.initial.points)) {
          expect(find.text('Guidance paused'), findsOneWidget);
        } else {
          expect(
            RoutingService.doesRouteCrossGeometry(displayed, geometry),
            isFalse,
          );
          expect(
            RoutingService.doesRouteCrossGeometry(
              displayed,
              Map<String, dynamic>.from(active.data['closure']['geometry']),
            ),
            isFalse,
          );
        }
        endpoints();
        for (final request in requests.skip(1)) {
          expect(
            request['avoid'],
            containsAll([active.closureId, 'virtual-second']),
          );
        }
        await finish(t);
      },
    );
    testWidgets('Marulas sustained wrong turn triggers recalculation: $label', (
      t,
    ) async {
      await start(t, c);
      respond = () async => throw const RoutingUnavailable();
      final off = Position(
        active.gps.last.lng + .004,
        active.gps.last.lat + .004,
      );
      await fix(t, off);
      await tick(t, 3);
      await fix(t, off);
      await tick(t, 3);
      await fix(t, off);
      await tick(t, 1);
      expect(requests, isNotEmpty);
      expect((requests.first['origin'] as Position).lng, off.lng);
      endpoints();
      await finish(t);
    });
  }
}
