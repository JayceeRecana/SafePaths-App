import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/services/road_location_preview.dart';
import 'package:safepaths_app/widgets/road_location_preview.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgiN79HwADiwIW0wB7tQAAAABJRU5ErkJggg==',
);
RoadStatus road(String id, {Map<String, dynamic>? geometry}) => RoadStatus(
  id: id,
  name: 'Road $id',
  status: 'passable',
  notes: '',
  updatedAt: DateTime(2026),
  geometry: geometry,
);
Map<String, dynamic> lines(double lon) => {
  'type': 'MultiLineString',
  'coordinates': [
    [
      [lon, 14.67],
      [lon + .001, 14.67],
    ],
    [
      [lon + .002, 14.67],
      [lon + .003, 14.67],
    ],
  ],
};

class Capture implements RoadPreviewCapture {
  final result = Completer<Uint8List>();
  final requests = <RoadPreviewRequest>[];
  int cancels = 0;
  @override
  Future<Uint8List> render(RoadPreviewRequest r) {
    requests.add(r);
    return result.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

Widget shell(List<RoadStatus> roads, List<Capture> captures) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RoadLocationPreview(
        roads: roads,
        capture: () => captures.removeAt(0),
      ),
    ),
  ),
);
void main() {
  tearDownAll(() => SimulatedWeatherService.instance.dispose());
  test(
    'road preview preserves disjoint ways, excludes invalid coordinates and reports unmapped roads',
    () {
      final request = RoadPreviewRequest(
        [
          road('a', geometry: lines(121)),
          road('missing'),
          road(
            'invalid',
            geometry: {
              'type': 'LineString',
              'coordinates': [
                [999, 14.6],
                [121, 14.7],
              ],
            },
          ),
        ],
        width: 320,
        dark: false,
      );
      final features = (jsonDecode(request.geoJson) as Map)['features'] as List;
      expect(request.mappedRoadIds, ['a']);
      expect(request.requestedCount, 3);
      expect(features.length, 2);
      expect(features[0]['geometry']['coordinates'], [
        [121.0, 14.67],
        [121.001, 14.67],
      ]);
      expect(features[1]['geometry']['coordinates'], [
        [121.002, 14.67],
        [121.003, 14.67],
      ]);
    },
  );
  test(
    'preview identity follows geometry and theme, not road condition or notes',
    () {
      final a = road('a', geometry: lines(121));
      String key(RoadStatus r, {bool dark = false}) =>
          RoadPreviewRequest([r], width: 320, dark: dark).identity;
      expect(
        key(a),
        key(a.copyWith(status: 'not_passable', notes: 'New findings')),
      );
      expect(key(a), isNot(key(a, dark: true)));
      expect(key(a), isNot(key(a.copyWith(geometry: lines(121.1)))));
    },
  );
  testWidgets(
    'missing geometry provides a nonblocking explanation without requesting a map',
    (tester) async {
      final capture = Capture();
      await tester.pumpWidget(shell([road('a')], [capture]));
      await tester.pumpAndSettle();
      expect(capture.requests, isEmpty);
      expect(
        find.text('Map location is unavailable for the selected road.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'map failure can retry and a successful preview opens a read-only enlarged image',
    (tester) async {
      final a = Capture(), b = Capture();
      await tester.pumpWidget(shell([road('a', geometry: lines(121))], [a, b]));
      await tester.pump();
      a.result.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Map preview could not be loaded. You can still complete the check.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry map'));
      await tester.pump();
      expect(b.requests.length, 1);
      b.result.complete(png);
      await tester.pumpAndSettle();
      expect(find.text('Enlarge map'), findsOneWidget);
      await tester.tap(find.text('Enlarge map'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(a.cancels, greaterThanOrEqualTo(1));
      expect(b.cancels, greaterThanOrEqualTo(1));
    },
  );
  testWidgets(
    'changing roads clears old output and ignores a late capture after cancellation',
    (tester) async {
      final a = Capture(), b = Capture(), captures = [a, b];
      await tester.pumpWidget(
        shell([road('a', geometry: lines(121))], captures),
      );
      await tester.pump();
      await tester.pumpWidget(
        shell([road('b', geometry: lines(121.1))], captures),
      );
      await tester.pump();
      expect(a.cancels, 1);
      expect(b.requests.single.mappedRoadIds, ['b']);
      a.result.complete(png);
      await tester.pump();
      expect(find.text('Enlarge map'), findsNothing);
      b.result.complete(png);
      await tester.pumpAndSettle();
      expect(find.text('Enlarge map'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'map heading and incomplete-geometry notice fit narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = Capture();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoadLocationPreview(
                roads: [
                  road('a', geometry: lines(121)),
                  road('missing'),
                ],
                capture: () => c,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      c.result.complete(png);
      await tester.pumpAndSettle();
      expect(find.text('Roads shown on map: 1/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'loaded preview has finite dimensions inside the actual scrollable AlertDialog',
    (tester) async {
      final c = Capture();
      tester.view.physicalSize = const Size(411, 865);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    scrollable: true,
                    title: const Text('Update road status'),
                    content: RoadLocationPreview(
                      roads: [road('a', geometry: lines(121))],
                      capture: () => c,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Confirm and save'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      c.result.complete(png);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final image = find.byType(Image);
      expect(tester.getSize(image).width.isFinite, true);
      expect(find.text('Confirm and save'), findsOneWidget);
      expect(find.text('Enlarge map'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final success in [true, false])
    testWidgets(
      'complete road-update dialog can save with preview success=$success',
      (tester) async {
        final c = Capture();
        Map<String, dynamic>? saved;
        tester.view.physicalSize = const Size(411, 865);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AdminReviewDialog(
                      roadIds: const ['a'],
                      quickConditions: true,
                      showRoadSettings: true,
                      previewCapture: () => c,
                      loadContext: () async => {
                        'token': 'test',
                        'roads': [
                          {
                            'id': 'a',
                            'name': '11th Drive',
                            'status': 'passable',
                            'isVerified': true,
                            'updatedAt': DateTime.now().toIso8601String(),
                            'geometry': lines(121),
                          },
                        ],
                      },
                      perform: (action, data) async {
                        expect(action, 'road_review');
                        saved = data;
                        return const AdminActionResult(
                          action: 'road_review',
                          roadStatus: 'not_passable',
                        );
                      },
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (success)
          c.result.complete(png);
        else
          c.result.completeError(StateError('preview offline'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Update road status'), findsOneWidget);
        final choice = find.byKey(
          const ValueKey('quick-condition-not_passable'),
        );
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pump();
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'CCTV operator checked current flooding at the crossing.',
        );
        await tester.pump();
        final save = find.byKey(const ValueKey('admin-review-save'));
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved?['roadStatus'], 'not_passable');
        expect(saved?['roadIds'], ['a']);
        expect(saved?['verifiedCurrentConditions'], true);
        expect(find.byType(AdminReviewDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
}
