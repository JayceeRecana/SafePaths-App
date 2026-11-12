import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/pin_road_context.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/widgets/planner_pin_card.dart';
import 'map_home_controls_test.dart' as fixtures;

RoadStatus road(
  String id,
  List<List<List<double>>> segments, {
  String status = 'passable',
  bool verified = true,
}) => RoadStatus(
  id: id,
  name: 'Road $id',
  status: status,
  notes: '',
  updatedAt: DateTime.now(),
  isVerified: verified,
  source: verified ? 'manual' : 'osm',
  geometry: {
    'type': 'MultiLineString',
    'segments': [
      for (final line in segments)
        {
          'points': [
            for (final p in line) {'lng': p[0], 'lat': p[1]},
          ],
        },
    ],
  },
);
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test('pin context does not bridge disconnected ways or move coordinates', () {
    final disconnected = road('disconnected', [
      [
        [0, 0],
        [.001, 0],
      ],
      [
        [.01, 0],
        [.011, 0],
      ],
    ]);
    final near = road('near', [
      [
        [.004, .0001],
        [.006, .0001],
      ],
    ]);
    final result = nearestPinRoad([disconnected, near], 0, .005)!;
    expect(result.road.id, 'near');
    expect(result.meters, inInclusiveRange(10, 12));
    expect(nearestPinRoad([disconnected], 0, .005)!.meters, greaterThan(400));
    expect(nearestPinRoad([], 0, 0), isNull);
    expect(nearestPinRoad([near], double.nan, 0), isNull);
    expect(nearestPinRoad([near], 91, 0), isNull);
  });
  testWidgets(
    'blocked road warns but a point may still be selected for route evaluation',
    (tester) async {
      var accepted = 0;
      final closed = road('closed', [
        [
          [0, 0],
          [.001, 0],
        ],
      ], status: 'not_passable');
      await tester.pumpWidget(
        fixtures.shell(
          Scaffold(
            body: SingleChildScrollView(
              child: PlannerPinCard(
                forOrigin: false,
                moving: false,
                confirming: false,
                insideArea: true,
                roadsLive: false,
                weather: WeatherState.clear,
                match: PinRoadMatch(closed, 5),
                onConfirm: () => accepted++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not passable'), findsOneWidget);
      expect(
        find.text('Saved road information. Check current conditions.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Choosing a point does not confirm a safe route. The planner checks routes next.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Use this destination'));
      expect(accepted, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'distant pin never inherits a road status and moving or outside pins cannot confirm',
    (tester) async {
      final green = road('green', [
        [
          [0, 0],
          [.001, 0],
        ],
      ]);
      var accepted = 0;
      for (final state in [(false, true), (true, true), (false, false)]) {
        await tester.pumpWidget(
          fixtures.shell(
            Scaffold(
              body: SingleChildScrollView(
                child: PlannerPinCard(
                  forOrigin: true,
                  moving: state.$1,
                  confirming: false,
                  insideArea: state.$2,
                  roadsLive: true,
                  weather: WeatherState.clear,
                  match: PinRoadMatch(green, 100),
                  onConfirm: () => accepted++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Passable'), findsNothing);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed != null, !state.$1 && state.$2);
      }
      expect(accepted, 0);
    },
  );
  testWidgets(
    'unreviewed imports stay unconfirmed and card fits large translated text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: SizedBox(
                  height: 280,
                  child: PlannerPinCard(
                    forOrigin: true,
                    moving: false,
                    confirming: false,
                    insideArea: true,
                    roadsLive: true,
                    weather: WeatherState.clear,
                    match: PinRoadMatch(
                      road('imported', [
                        [
                          [0, 0],
                          [.001, 0],
                        ],
                      ], verified: false),
                      5,
                    ),
                    onConfirm: () {},
                  ),
                ),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          if (language == 'en')
            expect(find.text('Current condition unknown'), findsOneWidget);
          final card = find.byKey(const ValueKey('planner-pin-card'));
          expect(
            tester.getBottomRight(find.byType(FilledButton)).dy,
            lessThanOrEqualTo(tester.getBottomRight(card).dy),
          );
          expect(tester.getSize(card).height, lessThanOrEqualTo(280));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
