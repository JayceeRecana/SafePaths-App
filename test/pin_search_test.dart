import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/config/study_area.dart';
import 'package:safepaths_app/data/marulas_landmarks.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/pin_road_context.dart';
import 'package:safepaths_app/widgets/planner_pin_suggestions.dart';
import 'map_home_controls_test.dart' as fixtures;

const area = StudyArea(
  id: 'sample',
  name: 'Sample',
  searchSuffix: '',
  polygon: '',
  latitude: 0,
  longitude: 0,
  south: -1,
  west: -1,
  north: 1,
  east: 1,
  landmarks: [
    MarulasLandmark(
      id: 'good',
      name: 'Fatima Center',
      category: 'School',
      address: '',
      lat: 0,
      lng: .2,
      tags: ['fatima'],
    ),
    MarulasLandmark(
      id: 'unresolved',
      name: 'Fatima unresolved',
      category: 'Hospital',
      address: '',
      lat: 0,
      lng: .3,
      tags: ['fatima'],
      routingAvailable: false,
    ),
    MarulasLandmark(
      id: 'outside',
      name: 'Fatima outside',
      category: 'School',
      address: '',
      lat: 4,
      lng: 4,
      tags: ['fatima'],
    ),
  ],
);
RoadStatus road(String id, String name, double x) => RoadStatus(
  id: id,
  name: name,
  status: 'passable',
  notes: '',
  updatedAt: DateTime.now(),
  geometry: {
    'type': 'LineString',
    'coordinates': [
      [x, 0],
      [x + .001, 0],
    ],
  },
);
bool inside(double lat, double lng) => lat.abs() <= 1 && lng.abs() <= 1;
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'local suggestions combine roads and eligible landmarks without leaking unresolved/outside pins',
    () {
      final choices = pinPlaceSuggestions(
        'fatima',
        [road('near', 'Fatima Road', 0), road('far', 'Fatima outside road', 3)],
        area,
        isInScope: inside,
      );
      expect(choices.map((p) => p.id), containsAll(['good', 'near']));
      expect(choices.map((p) => p.id), isNot(contains('unresolved')));
      expect(choices.map((p) => p.id), isNot(contains('outside')));
      expect(choices.map((p) => p.id), isNot(contains('far')));
      expect(pinPlaceSuggestions('f', [], area, isInScope: inside), isEmpty);
      expect(
        pinPlaceSuggestions('unmatched', [], area, isInScope: inside),
        isEmpty,
      );
    },
  );
  test('exact road names rank first and choices are bounded', () {
    final choices = pinPlaceSuggestions(
      'fatima',
      [
        for (var i = 0; i < 12; i++)
          road('r$i', i == 5 ? 'Fatima' : 'Fatima Road $i', 0),
      ],
      area,
      isInScope: inside,
    );
    expect(choices.length, 6);
    expect(choices.first.id, 'r5');
  });
  test('Marulas landmark search reuses the existing eligible catalog', () {
    final choices = pinPlaceSuggestions(
      'FUMC',
      [],
      StudyArea.marulas,
      isInScope: (lat, lng) => true,
    );
    expect(choices.map((p) => p.id), contains('fumc'));
    final chosen = choices.firstWhere((p) => p.id == 'fumc');
    final source = StudyArea.marulas.landmarks.firstWhere(
      (p) => p.id == 'fumc',
    );
    expect(chosen.lat, source.lat);
    expect(chosen.lng, source.lng);
  });
  testWidgets(
    'suggestions stay bounded with large translated text and choose the exact result',
    (tester) async {
      PinPlaceSuggestion? selected;
      final items = pinPlaceSuggestions(
        'fatima',
        [road('near', 'Fatima Road', 0)],
        area,
        isInScope: inside,
      );
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          fixtures.shell(
            Scaffold(
              body: PlannerPinSuggestions(
                items: items,
                onSelected: (p) => selected = p,
              ),
            ),
            dark: dark,
            language: 'fil',
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('planner-pin-suggestions')))
              .height,
          lessThanOrEqualTo(150),
        );
        await tester.tap(find.byType(ListTile).first);
        expect(selected!.id, items.first.id);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
