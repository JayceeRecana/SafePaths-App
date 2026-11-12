import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/data/marulas_landmarks.dart';
import 'package:safepaths_app/data/marulas_evacuation_sites.dart';
import 'package:safepaths_app/services/pin_road_context.dart';
import 'package:safepaths_app/utils/place_search.dart';
import 'package:safepaths_app/widgets/local_map_search_results.dart';
import 'map_home_controls_test.dart' as fixtures;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'all meaningful query words must match, including partial words and plurals',
    () {
      expect(
        MarulasLandmarksCatalog.search('fatima hospitals').map((p) => p.id),
        ['fumc'],
      );
      expect(MarulasLandmarksCatalog.search('unknownxyz hospital'), isEmpty);
      expect(MarulasLandmarksCatalog.search('Marulas'), isEmpty);
      expect(
        matchesPlaceSearch('Pio Valenzuela street', [
          'Pio Valenzuela Street',
        ], ignoreAreaWords: true),
        isTrue,
      );
      expect(matchesPlaceSearch('road missingxyz', ['Sample Road']), isFalse);
      expect(MarulasLandmarksCatalog.search('FUMC').first.id, 'fumc');
    },
  );
  test(
    'area words are removed only as words and never corrupt place names',
    () {
      expect(placeSearchWords('Citymall Marulas', ignoreAreaWords: true), [
        'citymall',
      ]);
      expect(matchesPlaceSearch('dona', ['Do\u00f1a Ata']), isTrue);
      expect(MarulasLandmarksCatalog.search('evac'), isEmpty);
    },
  );
  test(
    'invalid and withheld catalog pins never appear in routable search results',
    () {
      final invalid = MarulasLandmark(
        id: 'bad',
        name: 'Hospital',
        category: 'Hospital',
        address: '',
        lat: double.nan,
        lng: 120,
        tags: [],
      );
      expect(
        MarulasLandmarksCatalog.search('hospital', landmarks: [invalid]),
        isEmpty,
      );
      expect(
        MarulasLandmarksCatalog.search(
          'fire',
        ).any((p) => p.id == 'fire_station_marulas'),
        isFalse,
      );
      expect(
        MarulasLandmarksCatalog.all.map((p) => p.id).toSet().length,
        MarulasLandmarksCatalog.all.length,
      );
    },
  );
  test(
    'LGU names have a traceable source without invented routing coordinates',
    () {
      expect(MarulasEvacuationSites.names.length, 10);
      expect(MarulasEvacuationSites.names.toSet().length, 10);
      expect(
        MarulasEvacuationSites.names,
        contains('Do\u00f1a Ata Elementary School'),
      );
      expect(MarulasEvacuationSites.sourceUrl, contains('468942608601563'));
      expect(
        MarulasEvacuationSites.names,
        isNot(contains('Do\u00f1a Ata Covered Court')),
      );
    },
  );
  testWidgets('ambiguous local map matches require explicit selection', (
    tester,
  ) async {
    PinPlaceSuggestion? selected;
    final choices = [
      const PinPlaceSuggestion(
        id: 'road',
        title: 'Sample Road',
        landmark: false,
        lat: 14,
        lng: 120,
      ),
      const PinPlaceSuggestion(
        id: 'place',
        title: 'Sample Center',
        landmark: true,
        lat: 14.1,
        lng: 120.1,
      ),
    ];
    await tester.pumpWidget(
      fixtures.shell(
        Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await chooseLocalMapResult(context, choices);
              },
              child: const Text('Search'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Sample Road'), findsOneWidget);
    expect(find.text('Sample Center'), findsOneWidget);
    await tester.tap(find.text('Sample Center'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'place');
    expect(selected?.lat, 14.1);
  });
}
