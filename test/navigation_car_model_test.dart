import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:safepaths_app/widgets/navigation_car_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Native 3D marker stays disabled in all normal travel modes', () {
    expect(NavigationCarModel.enabled, isFalse);
    for (final mode in ['Sedan', 'Walking', 'Motorcycle', 'SUV / Pickup', null]) {
      expect(NavigationCarModel.supports(mode), isFalse);
    }
  });

  test('Inactive model configuration remains available for isolated diagnosis', () {
    final puck = NavigationCarModel.puck(90).locationPuck3D!;
    expect(puck.modelUri, startsWith('asset://assets/navigation/'));
    expect(puck.modelScaleMode, ModelScaleMode.VIEWPORT);
    expect(puck.modelRotation, [0, 0, -90]);
    expect(puck.modelCastShadows, isFalse);
  });

  test(
    'Bundled GLB is self-contained, bounded and has valid mesh buffers',
    () async {
      await NavigationCarModel.ensureBundled();
      final bytes = await rootBundle.load(NavigationCarModel.asset);
      expect(bytes.lengthInBytes, lessThan(50000));
      final jsonLength = bytes.getUint32(12, Endian.little);
      expect(bytes.getUint32(16, Endian.little), 0x4e4f534a);
      final json =
          jsonDecode(
                utf8.decode(
                  bytes.buffer.asUint8List(
                    bytes.offsetInBytes + 20,
                    jsonLength,
                  ),
                ),
              )
              as Map;
      expect(json['asset']['version'], '2.0');
      expect(json.containsKey('images'), isFalse);
      expect(json.containsKey('extensionsRequired'), isFalse);
      final binaryStart = 20 + jsonLength;
      expect(bytes.getUint32(binaryStart + 4, Endian.little), 0x004e4942);
      final binaryLength = bytes.getUint32(binaryStart, Endian.little);
      expect(json['buffers'].single.containsKey('uri'), isFalse);
      expect(json['buffers'].single['byteLength'], binaryLength);
      var triangles = 0;
      for (final primitive in json['meshes'].single['primitives']) {
        final position = json['accessors'][primitive['attributes']['POSITION']];
        final normal = json['accessors'][primitive['attributes']['NORMAL']];
        expect(position['count'], normal['count']);
        expect(position['count'] % 3, 0);
        triangles += (position['count'] as int) ~/ 3;
        for (final accessor in [position, normal]) {
          expect(accessor['type'], 'VEC3');
          expect(accessor['componentType'], 5126);
          final view = json['bufferViews'][accessor['bufferView']];
          expect(view['byteLength'], accessor['count'] * 12);
          expect(
            view['byteOffset'] + view['byteLength'],
            lessThanOrEqualTo(binaryLength),
          );
        }
      }
      expect(triangles, 506);
    },
  );

  void fix(
    NavigationMarkerHeading h, {
    double heading = 90,
    double speed = 3,
    double accuracy = 5,
    double headingAccuracy = 10,
    Duration age = Duration.zero,
  }) => h.update(
    heading: heading,
    speed: speed,
    accuracy: accuracy,
    headingAccuracy: headingAccuracy,
    age: age,
  );

  test('Direction holds while stopped, inaccurate, stale or invalid', () {
    final h = NavigationMarkerHeading();
    fix(h);
    expect(h.bearing, 90);
    fix(h, heading: 180, speed: 0);
    fix(h, heading: 180, accuracy: 50);
    fix(h, heading: 180, headingAccuracy: 50);
    fix(h, heading: 180, age: const Duration(seconds: 10));
    fix(h, heading: double.nan);
    fix(h, speed: double.nan);
    expect(h.bearing, 90);
    fix(h, heading: 180);
    expect(h.bearing, 180);
  });

  test('Direction handles north wraparound and ignores small jitter', () {
    final h = NavigationMarkerHeading();
    fix(h, heading: 350);
    expect(h.bearing, 350);
    fix(h, heading: 1);
    expect(h.bearing, 1);
    fix(h, heading: 359);
    expect(h.bearing, 1);
    fix(h, heading: 360);
    expect(h.bearing, 1);
    fix(h, heading: 20);
    expect(h.bearing, 20);
  });
}
