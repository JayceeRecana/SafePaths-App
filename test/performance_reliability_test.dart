import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/map_road_data.dart';
import 'package:safepaths_app/services/map_load_state.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/widgets/map_status_banner.dart';
import 'package:safepaths_app/widgets/report_history_controls.dart';

void main() {
  final now = DateTime(2026, 10, 23, 12);
  RoadStatus road({
    String id = 'r',
    String status = 'passable',
    String? condition,
    Map<String, dynamic>? geometry,
    String category = 'Safe',
  }) => RoadStatus(
    id: id,
    name: id,
    status: status,
    notes: '',
    updatedAt: now,
    vulnerability: 'high',
    communityCondition: condition,
    riskCategory: category,
    geometry:
        geometry ??
        {
          'type': 'LineString',
          'coordinates': [
            [120.984, 14.675],
            [120.984, 14.677],
          ],
        },
  );
  UserReport report(String id) => UserReport(
    id: id,
    title: id,
    description: 'Test',
    createdAt: now,
    severity: 'High',
    status: 'pending',
    userId: 'u',
  );

  test(
    'paging recent history never truncates the complete active hazard feed',
    () {
      final active = List.generate(45, (i) => report('active$i'));
      final own = List.generate(
        30,
        (i) => report('history$i').copyWith(status: 'resolved'),
      );
      final merged = mergeReportFeeds(active, own);
      expect(merged.length, 75);
      expect(merged.where((report) => report.status == 'pending').length, 45);
      final duplicate = mergeReportFeeds(active, [
        report('active0').copyWith(status: 'resolved'),
      ]);
      expect(duplicate.length, 45);
      expect(
        duplicate.singleWhere((report) => report.id == 'active0').status,
        'pending',
      );
    },
  );

  test(
    'map geometry and GeoJSON stay cached across repeated unchanged snapshots',
    () {
      final cache = MapRoadData(), roads = [road()];
      final original = cache.project(roads, WeatherState.clear, now: now);
      for (var i = 0; i < 1000; i++) {
        expect(
          identical(
            cache.project(roads, WeatherState.clear, now: now),
            original,
          ),
          isTrue,
        );
      }
      cache.project(
        [road()],
        WeatherState.clear,
        now: now,
      ); // Fresh Firestore map objects, same data.
      expect(cache.geometryBuilds, 1);
      expect(cache.dataBuilds, 1);
      cache.project([road(category: 'Watch')], WeatherState.clear, now: now);
      expect(cache.geometryBuilds, 1);
      expect(cache.dataBuilds, 2);
    },
  );

  test(
    'cache invalidates for closure, time-based staleness and unresolved incidents',
    () {
      final cache = MapRoadData(), roads = [road()];
      Map props(String json) =>
          (jsonDecode(json)['features'] as List).first['properties'] as Map;
      expect(
        props(cache.project(roads, WeatherState.heavyRain, now: now))['status'],
        'passable',
      );
      expect(
        props(
          cache.project(
            roads,
            WeatherState.heavyRain,
            now: now.add(const Duration(minutes: 31)),
          ),
        )['isUnconfirmed'],
        true,
      );
      expect(
        props(
          cache.project(
            [road(condition: 'outdated')],
            WeatherState.clear,
            now: now,
          ),
        )['status'],
        'partial',
      );
      expect(
        props(
          cache.project(
            [road(status: 'not_passable')],
            WeatherState.clear,
            now: now,
          ),
        )['status'],
        'not_passable',
      );
      expect(cache.geometryBuilds, 1);
    },
  );

  test(
    'disconnected segments stay disconnected and removed roads leave the cache',
    () {
      final cache = MapRoadData();
      final data = jsonDecode(
        cache.project(
          [
            road(
              geometry: {
                'type': 'MultiLineString',
                'coordinates': [
                  [
                    [120.98, 14.67],
                    [120.981, 14.671],
                  ],
                  [
                    [120.99, 14.68],
                    [120.991, 14.681],
                  ],
                ],
              },
            ),
          ],
          WeatherState.clear,
          now: now,
        ),
      );
      expect(data['features'], hasLength(2));
      cache.project([], WeatherState.clear, now: now);
      expect(cache.retainedRoads, 0);
      final missing = RoadStatus(
        id: 'empty',
        name: 'Empty',
        status: 'passable',
        notes: '',
        updatedAt: now,
      );
      expect(
        jsonDecode(
          cache.project([missing], WeatherState.clear, now: now),
        )['features'],
        isEmpty,
      );
    },
  );

  test(
    'paging retains one page, ignores duplicate taps and preserves data on failure',
    () async {
      final pending = Completer<ReportPage>();
      var calls = 0;
      final history = ReportHistory((cursor) async {
        calls++;
        if (calls == 1) {
          return ReportPage([
            report('first'),
          ], next: ReportCursor(now, 'first'));
        }
        if (calls == 2) return pending.future;
        throw StateError('offline');
      });
      await history.refresh();
      final load = history.older();
      await history.older();
      expect(calls, 2);
      pending.complete(
        ReportPage([report('second')], next: ReportCursor(now, 'second')),
      );
      await load;
      expect(history.pageNumber, 2);
      expect(history.page.reports.single.id, 'second');
      await history.older();
      expect(history.page.reports.single.id, 'second');
      expect(history.pageNumber, 2);
      expect(history.error, isNotNull);
      expect(history.loading, isFalse);
      history.dispose();
    },
  );

  test(
    'older empty pages and cached partial pages do not falsely erase history',
    () async {
      var count = 0;
      final history = ReportHistory(
        (_) async => ++count == 1
            ? ReportPage([report('first')], next: ReportCursor(now, 'first'))
            : const ReportPage([]),
      );
      await history.refresh();
      await history.older();
      expect(history.page.reports.single.id, 'first');
      expect(history.canGoOlder, isFalse);
      history.dispose();
      final cached = ReportHistory(
        (_) async => ReportPage(
          [report('cached')],
          next: ReportCursor(now, 'cached'),
          fromCache: true,
        ),
      );
      await cached.refresh();
      expect(cached.canGoOlder, isFalse);
      expect(cached.page.fromCache, isTrue);
      cached.dispose();
    },
  );

  test('late history results cannot notify a disposed screen', () async {
    final pending = Completer<ReportPage>();
    final history = ReportHistory((_) => pending.future);
    final load = history.refresh();
    history.dispose();
    pending.complete(ReportPage([report('late')]));
    await load;
  });

  testWidgets(
    'map timeout exposes retry, loading success does not hide an overlay failure',
    (tester) async {
      final status = MapLoadState(timeout: const Duration(seconds: 2));
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapStatusBanner(
              status: status,
              onRetry: () {
                retries++;
                status.begin();
              },
            ),
          ),
        ),
      );
      status.begin();
      await tester.pump();
      expect(find.text('Loading map…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('taking too long'), findsOneWidget);
      await tester.tap(find.text('Retry map'));
      await tester.pump();
      expect(retries, 1);
      status.overlaysFailed();
      status.loaded();
      await tester.pump();
      expect(find.textContaining('overlays could not refresh'), findsOneWidget);
      status.overlaysLoaded();
      await tester.pump();
      expect(find.byType(Card), findsNothing);
      await tester.pumpWidget(const SizedBox());
      status.dispose();
    },
  );

  testWidgets('history controls fit large fonts and show recoverable errors', (
    tester,
  ) async {
    final history = ReportHistory((_) async => throw StateError('offline'));
    await history.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 280,
              child: ReportHistoryControls(history: history),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    history.dispose();
  });
}
