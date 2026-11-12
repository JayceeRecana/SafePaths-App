import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/widgets/navigation_location_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Each supported travel mode has its matching icon', () {
    expect(NavigationLocationIcon.iconFor('Walking'), Icons.directions_walk);
    expect(NavigationLocationIcon.iconFor('Motorcycle'), Icons.motorcycle);
    expect(NavigationLocationIcon.iconFor('Sedan'), Icons.directions_car);
    expect(
      NavigationLocationIcon.iconFor('SUV / Pickup'),
      Icons.airport_shuttle,
    );
    expect(NavigationLocationIcon.iconFor(null), Icons.directions_car);
  });

  test(
    'All markers encode as native PNG images and reuse the cached result',
    () async {
      for (final mode in ['Walking', 'Motorcycle', 'Sedan', 'SUV / Pickup']) {
        final bytes = await NavigationLocationIcon.image(mode);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 80);
        expect(frame.image.height, 80);
        expect(
          identical(bytes, await NavigationLocationIcon.image(mode)),
          isTrue,
        );
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
