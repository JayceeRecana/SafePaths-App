import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/noah_awareness.dart';

const categories = NoahLengthCategory.values;
List<List<double>> ring(double w, double s, double e, double n) => [
  [w, s],
  [e, s],
  [e, n],
  [w, n],
  [w, s],
];
Map<String, dynamic> polygon(
  int level,
  double west,
  double east, {
  List<List<List<double>>> holes = const [],
}) => {
  'type': 'Feature',
  'properties': {'Var': level},
  'geometry': {
    'type': 'Polygon',
    'coordinates': [ring(west, -.5, east, .5), ...holes],
  },
};
NoahDataset dataset(List<Map<String, dynamic>> features) => NoahDataset.parse(
  jsonEncode({
    'type': 'FeatureCollection',
    'metadata': {
      'scenarioYears': 5,
      'hasCoverageMask': false,
      'preparedBounds': [0, -1, 10, 1],
    },
    'features': features,
  }),
);
Map<String, dynamic> road(double a, double b, {double latitude = 0}) => {
  'type': 'LineString',
  'coordinates': [
    [a, latitude],
    [b, latitude],
  ],
};
void shares(NoahLengthBreakdown d, Map<NoahLengthCategory, double> expected) {
  for (final c in categories) {
    expect(d.fraction(c), closeTo(expected[c] ?? 0, 1e-8), reason: c.name);
  }
  expect(d.tenthsPercent.values.reduce((a, b) => a + b), 1000);
  expect(d.meters.values.every((v) => v >= 0 && v.isFinite), isTrue);
  expect(d.meters.values.reduce((a, b) => a + b), closeTo(d.totalMeters, 1e-8));
}

void main() {
  Map<String, dynamic> storedRoad(
    List<List<List<double>>> lines, {
    String longitudeKey = 'lon',
  }) => {
    'type': 'MultiLineString',
    'segments': [
      for (final line in lines)
        {
          'points': [
            for (final point in line) {longitudeKey: point[0], 'lat': point[1]},
          ],
        },
    ],
  };

  test(
    'Firestore road segments match GeoJSON without joining disconnected ways',
    () {
      final d = dataset([polygon(3, 4, 6)]);
      final lines = <List<List<double>>>[
        [
          [1, 0],
          [3, 0],
        ],
        [
          [7, 0],
          [9, 0],
        ],
      ];
      final reference = d.assess({
        'type': 'MultiLineString',
        'coordinates': lines,
      });
      for (final key in ['lon', 'lng']) {
        final actual = d.assess(storedRoad(lines, longitudeKey: key));
        expect(actual.available, isTrue);
        expect(actual.levels, isEmpty); // No invented bridge through hazard.
        for (final category in categories) {
          expect(
            actual.lengthBreakdown!.fraction(category),
            closeTo(reference.lengthBreakdown!.fraction(category), 1e-10),
          );
        }
      }
      final withIsolatedPoint = d.assess(
        storedRoad([
          ...lines,
          [
            [5, 0],
          ], // A stored singleton has no length and must not bridge ways.
        ]),
      );
      expect(withIsolatedPoint.levels, isEmpty);
      expect(
        withIsolatedPoint.lengthBreakdown!.totalMeters,
        closeTo(reference.lengthBreakdown!.totalMeters, 1e-8),
      );
      final crossing = d.assess(
        storedRoad([
          [
            [1, 0],
            [9, 0],
          ],
        ]),
      );
      expect(crossing.levels, contains(3));
      expect(
        crossing.lengthBreakdown!.fraction(NoahLengthCategory.high),
        closeTo(.25, 1e-8),
      );
    },
  );

  test(
    'malformed stored road points do not produce partial or invented percentages',
    () {
      final d = dataset([polygon(3, 4, 6)]);
      for (final geometry in [
        {'type': 'MultiLineString', 'segments': []},
        {
          'type': 'MultiLineString',
          'segments': [
            {
              'points': [
                {'lat': 0},
                {'lat': 0, 'lon': 5},
              ],
            },
          ],
        },
        storedRoad([
          [
            [1, 0],
            [double.nan, 0],
          ],
        ]),
        storedRoad([
          [
            [1, 0],
          ],
        ]),
      ]) {
        final actual = d.assess(geometry);
        expect(actual.available, isFalse);
        expect(actual.lengthBreakdown, isNull);
      }
    },
  );

  test(
    'known equatorial metres and known shares use the full road denominator',
    () {
      final d = dataset([polygon(1, 1, 4), polygon(2, 4, 7), polygon(3, 7, 9)]);
      shares(d.assess(road(0, 10)).lengthBreakdown!, {
        NoahLengthCategory.low: .3,
        NoahLengthCategory.medium: .3,
        NoahLengthCategory.high: .2,
        NoahLengthCategory.noMappedHazard: .2,
      });
      final metres = d.assess(road(0, .001)).lengthBreakdown!;
      expect(metres.totalMeters, closeTo(111.19508, .001));
      shares(metres, {NoahLengthCategory.noMappedHazard: 1});
    },
  );
  test(
    'overlap is assigned once to the highest mapped class, independent of feature order',
    () {
      final features = [
        polygon(1, 1, 9),
        polygon(2, 3, 8),
        polygon(3, 5, 7),
        polygon(3, 6, 9),
      ];
      final expected = {
        NoahLengthCategory.low: .2,
        NoahLengthCategory.medium: .2,
        NoahLengthCategory.high: .4,
        NoahLengthCategory.noMappedHazard: .2,
      };
      shares(dataset(features).assess(road(0, 10)).lengthBreakdown!, expected);
      shares(
        dataset(
          features.reversed.toList(),
        ).assess(road(0, 10)).lengthBreakdown!,
        expected,
      );
    },
  );
  test(
    'same-class overlapping polygons are unioned without double counting',
    () {
      shares(
        dataset([
          polygon(3, 1, 6),
          polygon(3, 3, 8),
        ]).assess(road(0, 10)).lengthBreakdown!,
        {NoahLengthCategory.high: .7, NoahLengthCategory.noMappedHazard: .3},
      );
    },
  );
  test(
    'polygon holes are no mapped intersection, closed boundaries have length, isolated touches do not',
    () {
      final d = dataset([
        polygon(1, 1, 9, holes: [ring(3, -.25, 7, .25)]),
      ]);
      shares(d.assess(road(0, 10)).lengthBreakdown!, {
        NoahLengthCategory.low: .4,
        NoahLengthCategory.noMappedHazard: .6,
      });
      shares(d.assess(road(1, 9, latitude: -.5)).lengthBreakdown!, {
        NoahLengthCategory.low: 1,
      });
      shares(d.assess(road(3, 7, latitude: -.25)).lengthBreakdown!, {
        NoahLengthCategory.low: 1,
      });
      final touching = d.assess({
        'type': 'LineString',
        'coordinates': [
          [0, -1],
          [1, -.5],
        ],
      });
      expect(touching.levels, {1});
      shares(touching.lengthBreakdown!, {NoahLengthCategory.noMappedHazard: 1});
    },
  );
  test(
    'partial and wholly outside roads preserve an explicit outside share',
    () {
      final d = dataset([polygon(3, 2, 4)]);
      final partial = d.assess(road(-5, 15));
      expect(partial.partial, isTrue);
      shares(partial.lengthBreakdown!, {
        NoahLengthCategory.high: .1,
        NoahLengthCategory.noMappedHazard: .4,
        NoahLengthCategory.outsidePrepared: .5,
      });
      final outside = d.assess(road(-5, -1));
      expect(outside.available, isFalse);
      shares(outside.lengthBreakdown!, {NoahLengthCategory.outsidePrepared: 1});
    },
  );
  test(
    'disjoint components are not joined and repeated/reversed pieces are counted once',
    () {
      final d = dataset([polygon(1, 1, 2), polygon(3, 6, 7)]);
      final disjoint = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [1, 0],
            [2, 0],
          ],
          [
            [6, 0],
            [7, 0],
          ],
          [
            [9, 0],
            [10, 0],
          ],
        ],
      };
      final measured = d.assess(disjoint).lengthBreakdown!;
      shares(measured, {
        NoahLengthCategory.low: 1 / 3,
        NoahLengthCategory.high: 1 / 3,
        NoahLengthCategory.noMappedHazard: 1 / 3,
      });
      expect(measured.tenthsPercent.values.reduce((a, b) => a + b), 1000);
      final repeated = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [0, 0],
            [10, 0],
          ],
          [
            [10, 0],
            [0, 0],
          ],
          [
            [2, 0],
            [8, 0],
          ],
        ],
      };
      final original = d.assess(road(0, 10)).lengthBreakdown!,
          dedup = d.assess(repeated).lengthBreakdown!;
      expect(dedup.totalMeters, closeTo(original.totalMeters, 1e-6));
      for (final c in categories) {
        expect(dedup.fraction(c), closeTo(original.fraction(c), 1e-10));
      }
      final overlapping = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [0, 0],
            [6, 0],
          ],
          [
            [4, 0],
            [10, 0],
          ],
        ],
      };
      expect(
        d.assess(overlapping).lengthBreakdown!.totalMeters,
        closeTo(original.totalMeters, 1e-6),
      );
    },
  );
  test(
    'densification and reversal preserve shares; tiny intersections round honestly',
    () {
      final d = dataset([polygon(1, 1, 3), polygon(3, 4, 4.00001)]);
      final simple = d.assess(road(0, 10)).lengthBreakdown!;
      final dense = d.assess({
        'type': 'LineString',
        'coordinates': [
          [10, 0],
          [8, 0],
          [3, 0],
          [0, 0],
        ],
      }).lengthBreakdown!;
      for (final c in categories) {
        expect(dense.fraction(c), closeTo(simple.fraction(c), 1e-8));
      }
      expect(simple.meters[NoahLengthCategory.high], greaterThan(0));
      expect(simple.tenthsPercent[NoahLengthCategory.high], 0);
      expect(simple.tenthsPercent.values.reduce((a, b) => a + b), 1000);
    },
  );
  test(
    'missing, zero-length, malformed and unsupported dateline geometry have no fabricated percentages',
    () {
      final d = dataset([polygon(1, 1, 3)]);
      for (final g in [
        null,
        road(1, 1),
        {
          'type': 'Point',
          'coordinates': [1, 0],
        },
        road(double.nan, 2),
        road(-179, 179),
      ]) {
        expect(d.assess(g).lengthBreakdown, isNull);
      }
    },
  );
  test('real bundled polygons match independent GIS reference shares', () {
    final d = NoahDataset.parse(
      File('assets/noah/marulas-5year.geojson').readAsStringSync(),
    );
    final reference =
        jsonDecode(
              File(
                'test/fixtures/noah_length_reference.json',
              ).readAsStringSync(),
            )
            as Map;
    for (final entry in reference['cases'] as List) {
      final g = Map<String, dynamic>.from(entry['geometry'] as Map);
      final measured = d.assess(g).lengthBreakdown!;
      for (final c in categories) {
        expect(
          measured.fraction(c),
          closeTo((entry['fractions'][c.name] as num).toDouble(), .000001),
          reason: '${entry['name']} / ${c.name}',
        );
      }
      final stored = d.assess(
        storedRoad(
          g['type'] == 'LineString'
              ? [
                  List<List<double>>.from(
                    (g['coordinates'] as List).map(
                      (p) => List<double>.from(
                        (p as List).map((v) => (v as num).toDouble()),
                      ),
                    ),
                  ),
                ]
              : List<List<List<double>>>.from(
                  (g['coordinates'] as List).map(
                    (line) => List<List<double>>.from(
                      (line as List).map(
                        (p) => List<double>.from(
                          (p as List).map((v) => (v as num).toDouble()),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
      for (final c in categories) {
        expect(
          stored.lengthBreakdown!.fraction(c),
          closeTo(measured.fraction(c), .000001),
        );
      }
      expect(measured.tenthsPercent.values.reduce((a, b) => a + b), 1000);
    }
  });
}
