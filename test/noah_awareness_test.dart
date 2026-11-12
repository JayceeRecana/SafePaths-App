import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/services/noah_awareness.dart';
import 'package:safepaths_app/widgets/noah_awareness_card.dart';
import 'package:safepaths_app/theme/app_theme.dart';

class _NoahTestBundle extends CachingAssetBundle {
  final String? contents;
  _NoahTestBundle(this.contents);
  @override
  Future<ByteData> load(String key) async {
    if (contents == null) throw FlutterError('Missing test asset');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents!)));
  }
}

Map<String, dynamic> line(List<List<double>> points) => {
  'type': 'LineString',
  'coordinates': points,
};
List<List<double>> ring(double w, double s, double e, double n) => [
  [w, s],
  [e, s],
  [e, n],
  [w, n],
  [w, s],
];
NoahDataset fixture() => NoahDataset.parse(
  jsonEncode({
    'type': 'FeatureCollection',
    'metadata': {
      'scenarioYears': 5,
      'hasCoverageMask': false,
      'preparedBounds': [0, 0, 10, 10],
    },
    'features': [
      {
        'type': 'Feature',
        'properties': {'Var': 1},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring(1, 1, 4, 4), ring(2, 2, 3, 3)],
        },
      },
      {
        'type': 'Feature',
        'properties': {'Var': 3},
        'geometry': {
          'type': 'MultiPolygon',
          'coordinates': [
            [ring(6, 6, 8, 8)],
          ],
        },
      },
    ],
  }),
);
Widget shell(
  Widget child, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'missing bundle and malformed data have distinct failure stages',
    () async {
      await expectLater(
        NoahRepository.loadAsset(_NoahTestBundle(null)),
        throwsA(
          isA<NoahLoadException>().having(
            (e) => e.stage,
            'stage',
            NoahFailureStage.asset,
          ),
        ),
      );
      await expectLater(
        NoahRepository.loadAsset(_NoahTestBundle('not geojson')),
        throwsA(
          isA<NoahLoadException>().having(
            (e) => e.stage,
            'stage',
            NoahFailureStage.data,
          ),
        ),
      );
      final c = NoahMapController(
        loader: () => NoahRepository.loadAsset(_NoahTestBundle(null)),
      );
      await c.setEnabled(true);
      expect(c.failureStage, NoahFailureStage.asset);
      expect(c.safePaths, isTrue);
      c.dispose();
      final rendered = NoahMapController(loader: () async => fixture());
      await rendered.setEnabled(true);
      rendered.renderFailed();
      expect(rendered.failureStage, NoahFailureStage.render);
      await rendered.retry();
      expect(rendered.failureStage, isNull);
      expect(rendered.failed, isFalse);
      rendered.dispose();
    },
  );
  testWidgets(
    'missing-asset sheet gives a restart explanation and a blue coverage action',
    (tester) async {
      final c = NoahMapController(
        loader: () async =>
            throw const NoahLoadException(NoahFailureStage.asset),
      );
      await c.setEnabled(true);
      await tester.pumpWidget(
        shell(
          NoahLayerControls(
            controller: c,
            onViewCoverage: () {},
            onRoadLegend: () {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('Legend and coverage'));
      await tester.pumpAndSettle();
      expect(
        find.text('NOAH data is missing from this app build.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Stop Flutter completely and run the app again to include the map data.',
        ),
        findsOneWidget,
      );
      final action = find.widgetWithText(FilledButton, 'View Marulas coverage');
      expect(action, findsOneWidget);
      final button = tester.widget<FilledButton>(action);
      final context = tester.element(action);
      expect(
        button.style!.backgroundColor!.resolve({}),
        Theme.of(context).colorScheme.primary,
      );
      expect(
        find.textContaining('https://noah.up.edu.ph/'),
        findsNothing,
      ); // sources stay collapsed
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test(
    'segments crossing hazards are found even when endpoints are outside; holes are excluded',
    () {
      final d = fixture();
      expect(
        d
            .assess(
              line([
                [0, 1.5],
                [5, 1.5],
              ]),
            )
            .levels,
        {1},
      );
      expect(
        d
            .assess(
              line([
                [2.2, 2.2],
                [2.8, 2.8],
              ]),
            )
            .levels,
        isEmpty,
      );
      expect(
        d
            .assess(
              line([
                [5, 7],
                [9, 7],
              ]),
            )
            .levels,
        {3},
      );
      expect(
        d
            .assess(
              line([
                [0, 0],
                [1, 1],
              ]),
            )
            .levels,
        {1},
      ); // boundary touch is awareness, not closure
    },
  );
  test(
    'all disjoint road segments are assessed; no connecting line is invented',
    () {
      final d = fixture();
      final g = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [0.0, 0.0],
            [0.5, 0.5],
          ],
          [
            [9.0, 9.0],
            [9.5, 9.5],
          ],
        ],
      };
      expect(d.assess(g).levels, isEmpty);
      g['coordinates'] = [
        [
          [1.5, 1.5],
          [1.8, 1.8],
        ],
        [
          [6.2, 6.2],
          [6.5, 6.5],
        ],
      ];
      expect(d.assess(g).levels, {1, 3});
    },
  );
  test('outside, partial, malformed and unshaded roads do not become safe', () {
    final d = fixture();
    expect(
      d
          .assess(
            line([
              [-2, -2],
              [-1, -1],
            ]),
          )
          .available,
      isFalse,
    );
    final partial = d.assess(
      line([
        [-1, 1.5],
        [3.5, 1.5],
      ]),
    );
    expect(partial.available, isTrue);
    expect(partial.partial, isTrue);
    expect(partial.levels, {1});
    final clear = d.assess(
      line([
        [4.5, 4.5],
        [5, 5],
      ]),
    );
    expect(clear.available, isTrue);
    expect(clear.levels, isEmpty);
    for (final g in [
      null,
      <String, dynamic>{
        'type': 'Point',
        'coordinates': [2, 2],
      },
      line([
        [double.nan, 0],
        [2, 2],
      ]),
      line([
        [2, 2],
      ]),
    ]) {
      expect(d.assess(g).available, isFalse);
    }
  });
  test('awareness assessment leaves input road geometry unchanged', () {
    final g = line([
      [0, 1.5],
      [5, 1.5],
    ]);
    final before = jsonEncode(g);
    fixture().assess(g);
    expect(jsonEncode(g), before);
  });
  test(
    'unexpected scenario and malformed dataset fail instead of implying no hazard',
    () {
      expect(
        () => NoahDataset.parse(
          '{"type":"FeatureCollection","metadata":{"scenarioYears":100}}',
        ),
        throwsFormatException,
      );
      expect(() => NoahDataset.parse('not json'), throwsFormatException);
    },
  );
  test(
    'bundled source identifies five-year scenario and Marulas while nearby test roads remain outside',
    () async {
      final data = await NoahRepository.load();
      expect(data.bounds.contains(const NoahPoint(120.9842, 14.6761)), isTrue);
      expect(
        data
            .assess(
              line([
                [121.009, 14.676],
                [121.010, 14.676],
              ]),
            )
            .available,
        isFalse,
      );
      final raw = jsonDecode(data.geoJson) as Map;
      expect(
        raw['metadata']['revision'],
        '3820095a7e40b6bc852390d43a8c6d368d6fe081',
      );
      expect(raw['metadata']['hasCoverageMask'], isFalse);
      expect(raw['metadata']['modelDate'], isNull);
      expect(
        (raw['features'] as List).map((f) => f['properties']['Var']).toSet(),
        {1, 2, 3},
      );
      expect(utf8.encode(data.geoJson).length, lessThan(2500000));
    },
  );
  test(
    'layer toggles are independent; late load does not re-enable a disabled layer',
    () async {
      final pending = Completer<NoahDataset>();
      final c = NoahMapController(loader: () => pending.future);
      expect(c.enabled, isFalse);
      expect(c.safePaths, isTrue);
      final task = c.setEnabled(true);
      expect(c.loading, isTrue);
      await c.setEnabled(false);
      c.setSafePaths(false);
      pending.complete(fixture());
      await task;
      expect(c.enabled, isFalse);
      expect(c.safePaths, isFalse);
      expect(c.data, isNotNull);
      c.observeCenter(50, 50);
      expect(c.centerInside, isFalse);
      c.observeCenter(2, 2);
      expect(c.centerInside, isTrue);
      c.dispose();
    },
  );
  test(
    'load failure is retryable and disposal during load does not notify',
    () async {
      var attempts = 0;
      final c = NoahMapController(
        loader: () async {
          if (attempts++ == 0) throw StateError('synthetic');
          return fixture();
        },
      );
      await c.setEnabled(true);
      expect(c.failed, isTrue);
      expect(c.safePaths, isTrue);
      await c.retry();
      expect(c.failed, isFalse);
      expect(c.data, isNotNull);
      c.dispose();
      final p = Completer<NoahDataset>();
      final gone = NoahMapController(loader: () => p.future);
      final f = gone.setEnabled(true);
      gone.dispose();
      p.complete(fixture());
      await f;
    },
  );
  test('routing and report services have no NOAH dependency', () {
    for (final path in [
      'lib/services/routing_service.dart',
      'lib/services/risk_engine.dart',
      'lib/services/app_state_service.dart',
      'lib/models/road_status.dart',
      'lib/services/admin_report_service.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('noah_awareness')),
        reason: path,
      );
    }
  });
  testWidgets(
    'controls keep both choices and road legend; failure is explicit',
    (tester) async {
      final c = NoahMapController(
        loader: () async => throw StateError('synthetic'),
      );
      var legend = 0;
      await tester.pumpWidget(
        shell(
          NoahLayerControls(
            controller: c,
            onViewCoverage: () {},
            onRoadLegend: () => legend++,
          ),
        ),
      );
      await tester.tap(find.text('NOAH'));
      await tester.pumpAndSettle();
      expect(find.text('NOAH unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Road conditions'));
      expect(legend, 1);
      expect(c.safePaths, isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'road awareness remains distinct from live status, fits both themes and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          shell(
            NoahAwarenessCard(
              key: UniqueKey(),
              geometry: line([
                [5, 7],
                [9, 7],
              ]),
              loader: () async => fixture(),
            ),
            dark: dark,
            scale: 2,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.tap(find.text('NOAH flood awareness'));
        await tester.pumpAndSettle();
        expect(find.text('High hazard'), findsOneWidget);
        expect(
          find.text('5-year scenario · Not live flooding'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'layer controls and information sheet fit Filipino and enlarged text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        var viewed = 0;
        final c = NoahMapController(loader: () async => fixture());
        await c.setEnabled(true);
        await tester.pumpWidget(
          shell(
            NoahLayerControls(
              controller: c,
              onViewCoverage: () => viewed++,
              onRoadLegend: () {},
            ),
            dark: dark,
            language: 'fil',
            scale: 2,
          ),
        );
        await tester.tap(find.byTooltip('Mga kulay at saklaw'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = find.text('Tingnan ang saklaw sa Marulas');
        await tester.scrollUntilVisible(
          action,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(viewed, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
  testWidgets(
    'road-card load failure retries without inventing a road hazard',
    (tester) async {
      var calls = 0;
      Future<NoahDataset> load() async {
        if (calls++ == 0) throw StateError('synthetic');
        return fixture();
      }

      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            geometry: line([
              [20, 20],
              [21, 21],
            ]),
            loader: load,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.pumpAndSettle();
      expect(find.text('NOAH information could not load.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('NOAH information unavailable for this road.'),
        findsOneWidget,
      );
      expect(find.text('High hazard'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'road card shows intersected NOAH classes with calculated road-length shares',
    (tester) async {
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            geometry: {
              'type': 'MultiLineString',
              'segments': [
                {
                  'points': [
                    {'lon': 1.5, 'lat': 1.5},
                    {'lon': 1.8, 'lat': 1.8},
                  ],
                },
                {
                  'points': [
                    {'lon': 6.2, 'lat': 6.2},
                    {'lon': 6.5, 'lat': 6.5},
                  ],
                },
              ],
            },
            loader: () async => fixture(),
          ),
        ),
      );
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('noah-mapped-level-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('noah-mapped-level-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('noah-mapped-level-2')), findsNothing);
      expect(
        find.byKey(const ValueKey('noah-road-length-breakdown')),
        findsOneWidget,
      );
      expect(find.text('Share of the whole mapped road'), findsOneWidget);
      expect(find.textContaining('1.5 m'), findsNothing);
      expect(
        find.text(
          'This is modeled hazard, not current flooding. Check the latest barangay road update before travel.',
        ),
        findsOneWidget,
      );
      expect(find.text('Source and limitations'), findsOneWidget);
      expect(
        find.text(
          'Source: Project NOAH, via the BetterGov.PH mirror. Original model date unavailable.',
        ),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Source and limitations'));
      await tester.tap(find.text('Source and limitations'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Source: Project NOAH, via the BetterGov.PH mirror. Original model date unavailable.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'changing roads hides the previous hazard while the next assessment is pending',
    (tester) async {
      const key = ValueKey('selected-noah-road');
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            key: key,
            geometry: line([
              [5, 7],
              [9, 7],
            ]),
            loader: () async => fixture(),
          ),
        ),
      );
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('noah-mapped-level-3')), findsOneWidget);
      final next = Completer<NoahDataset>();
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            key: key,
            geometry: line([
              [20, 20],
              [21, 21],
            ]),
            loader: () => next.future,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('noah-mapped-level-3')), findsNothing);
      expect(find.text('Checking mapped hazard...'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('noah-road-length-breakdown')),
        findsNothing,
      );
      next.complete(fixture());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('NOAH information unavailable for this road.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('noah-mapped-level-3')), findsNothing);
    },
  );
  testWidgets(
    'unshaded and outside roads do not get hazard rows or safe labels',
    (tester) async {
      for (final points in [
        <List<double>>[
          [4.5, 4.5],
          [5, 5],
        ],
        <List<double>>[
          [20, 20],
          [21, 21],
        ],
      ]) {
        await tester.pumpWidget(
          shell(
            NoahAwarenessCard(
              key: UniqueKey(),
              geometry: line(points),
              loader: () async => fixture(),
            ),
          ),
        );
        await tester.tap(find.text('NOAH flood awareness'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        for (final level in [1, 2, 3]) {
          expect(
            find.byKey(ValueKey('noah-mapped-level-$level')),
            findsNothing,
          );
        }
        expect(find.text('Safe'), findsNothing);
        expect(
          find.text(
            'Unshaded areas are not proven safe. NOAH does not change report reviews or navigation decisions.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'refined NOAH card fits enlarged English and Filipino in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true])
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            shell(
              NoahAwarenessCard(
                key: UniqueKey(),
                geometry: line([
                  [5, 7],
                  [9, 7],
                ]),
                loader: () async => fixture(),
                onViewMap: () {},
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.tap(
            find.text(
              language == 'fil'
                  ? 'Kaalaman sa baha mula sa NOAH'
                  : 'NOAH flood awareness',
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('noah-mapped-level-3')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
    },
  );
  testWidgets(
    'length breakdown labels its denominator and explains derived percentages',
    (tester) async {
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            geometry: line([
              [5, 7],
              [9, 7],
            ]),
            loader: () async => fixture(),
          ),
        ),
      );
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('50.0%'), findsNWidgets(2));
      expect(
        find.text('Road-length shares, not a chance of flooding.'),
        findsOneWidget,
      );
      final explanation = find.text('How these percentages are calculated');
      await tester.ensureVisible(explanation);
      await tester.tap(explanation);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'SafePaths calculates these percentages from the whole unique mapped road length and NOAH polygons, using the 5-year rainfall scenario. They are not percentages published directly by NOAH.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Shares are rounded to 0.1% and total 100.0%. Very small intersections may round to 0.0%.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'outside road shows 100 percent outside; zero geometry has no percentage chart',
    (tester) async {
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            geometry: line([
              [20, 20],
              [21, 21],
            ]),
            loader: () async => fixture(),
          ),
        ),
      );
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Outside prepared data'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        shell(
          NoahAwarenessCard(
            geometry: line([
              [1, 1],
              [1, 1],
            ]),
            loader: () async => fixture(),
          ),
        ),
      );
      await tester.tap(find.text('NOAH flood awareness'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('noah-road-length-breakdown')),
        findsNothing,
      );
      expect(
        find.text(
          'Unable to calculate road-length percentages from the available geometry.',
        ),
        findsOneWidget,
      );
      expect(find.text('100.0%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
