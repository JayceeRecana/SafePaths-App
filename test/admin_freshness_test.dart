// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:safepaths_app/services/admin_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safepaths_app/services/admin_road_overview.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/screens/admin/admin_panel_screen.dart';
import 'package:safepaths_app/screens/admin/admin_feedback_screen.dart';
import 'package:safepaths_app/widgets/report_activity_summary.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

Widget shell(
  Widget home, {
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
  home: home,
);

class Meta implements SnapshotMetadata {
  @override
  final bool isFromCache;
  Meta(this.isFromCache);
  @override
  bool get hasPendingWrites => false;
}

// Test-only platform snapshot; production always receives the SDK implementation.
// ignore: subtype_of_sealed_class
class FeedbackDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'feedback';
  @override
  Map<String, dynamic> data() => {
    'category': 'Map Accuracy',
    'rating': 4,
    'comments': 'Saved feedback content',
    'status': 'new',
    'timestamp': Timestamp.now(),
    'hasAttachment': false,
    'allowFollowUp': false,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FeedbackSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final SnapshotMetadata metadata;
  FeedbackSnapshot(bool cached) : metadata = Meta(cached);
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [FeedbackDoc()];
  @override
  int get size => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    auth.FirebaseAuthPlatform.instance = fixtures.TestAuth()..signIn('admin');
    platform.FirebaseFirestorePlatform.instance = fixtures.TestStore();
    dotenv.loadFromString(envString: 'ADMIN_RELIABILITY_TESTS=true');
  });
  test('dashboard counts share road freshness and retain old restrictions', () {
    final now = DateTime.now();
    RoadStatus road(
      String id,
      String status, {
      bool verified = true,
      bool old = false,
      String source = 'manual',
    }) => RoadStatus(
      id: id,
      name: id,
      status: status,
      notes: '',
      isVerified: verified,
      source: source,
      updatedAt: old ? now.subtract(const Duration(days: 11)) : now,
    );
    final data = [
      road('fresh', 'passable'),
      road('old', 'passable', old: true),
      road('import', 'passable', verified: false, source: 'osm'),
      road('closed', 'not_passable', old: true),
      road('partial', 'partial', old: true),
    ];
    final summary = AdminRoadOverview(data, now, WeatherState.clear);
    expect(summary.count('passable'), 1);
    expect(summary.count('unconfirmed'), 2);
    expect(summary.count('not_passable'), 1);
    expect(summary.count('partial'), 1);
    expect(summary.checks.length, 4);
    expect(data[3].status, 'not_passable');
    expect(
      adminGraphHealth(roadsLive: false, roads: 5, disconnected: 0),
      'Not confirmed',
    );
    expect(
      adminGraphHealth(roadsLive: true, roads: 0, disconnected: 0),
      'Not confirmed',
    );
    expect(
      adminGraphHealth(roadsLive: true, roads: 5, disconnected: 0),
      'No isolated roads',
    );
    expect(
      adminGraphHealth(roadsLive: true, roads: 100, disconnected: 6),
      'Some gaps',
    );
    expect(
      adminGraphHealth(roadsLive: true, roads: 5, disconnected: 3),
      'Needs review',
    );
  });
  testWidgets(
    'midnight clears yesterday totals and ignores a late old-day response',
    (tester) async {
      var now = DateTime(2026, 11, 1, 23, 59, 50), calls = 0;
      final previous = Completer<(int, int)>();
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportActivitySummary(
                now: () => now,
                load: (start, end) async {
                  calls++;
                  if (calls == 1) return previous.future;
                  expect(start, DateTime(2026, 11, 2));
                  return (2, 1);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pump();
      expect(calls, 1);
      now = DateTime(2026, 11, 2, 0, 0, 10);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('2'), findsOneWidget);
      previous.complete((99, 88));
      await tester.pumpAndSettle();
      expect(find.text('99'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'resume refreshes an open snapshot and a failed refresh never shows old counts or zero',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: SingleChildScrollView(
              child: ReportActivitySummary(
                load: (start, end) async {
                  calls++;
                  if (calls > 1) throw StateError('offline');
                  return (7, 3);
                },
              ),
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('7'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.textContaining('Summary unavailable.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'populated cached feedback stays visible with a notice until a server snapshot arrives',
    (tester) async {
      final source = StreamController<QuerySnapshot>.broadcast();
      await tester.pumpWidget(
        shell(AdminFeedbackScreen(feedbackStream: source.stream)),
      );
      await tester.pump();
      source.add(FeedbackSnapshot(true));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved feedback content'), findsOneWidget);
      expect(
        find.text('Showing saved information. Reconnect to check for updates.'),
        findsOneWidget,
      );
      source.add(FeedbackSnapshot(false));
      await tester.pumpAndSettle();
      expect(
        find.text('Showing saved information. Reconnect to check for updates.'),
        findsNothing,
      );
      expect(find.textContaining('Saved feedback content'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await source.close();
    },
  );
  testWidgets(
    'dashboard keeps its cards usable with unconfirmed roads in both themes and languages at large text',
    (tester) async {
      final previousHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        previousHandler?.call(details);
        if (details.exception.toString().contains('overflowed'))
          debugPrint(details.toString());
      };
      addTearDown(() => FlutterError.onError = previousHandler);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppStateService.instance,
          old = List<RoadStatus>.of(AppStateService.instance.roads),
          now = DateTime.now();
      state.roads
        ..clear()
        ..addAll([
          RoadStatus(
            id: 'fresh',
            name: 'Fresh road',
            status: 'passable',
            notes: '',
            isVerified: true,
            source: 'manual',
            neighbors: ['old'],
            updatedAt: now,
          ),
          RoadStatus(
            id: 'old',
            name: 'Older road',
            status: 'passable',
            notes: '',
            isVerified: true,
            source: 'manual',
            neighbors: ['fresh'],
            updatedAt: now.subtract(const Duration(days: 11)),
          ),
          RoadStatus(
            id: 'import',
            name: 'Imported road',
            status: 'passable',
            notes: '',
            isVerified: false,
            source: 'osm',
            neighbors: ['old'],
            updatedAt: now,
          ),
        ]);
      state.syncHealth.channels['roads'] = SyncCondition.live;
      for (final language in ['en', 'fil'])
        for (final dark in [false, true])
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(
              shell(
                AdminPanelScreen(
                  loadInsights: (days) async => AdminInsightsData(
                    start: now.subtract(const Duration(days: 6)),
                    end: now.add(const Duration(days: 1)),
                    checkedAt: now,
                    reports: [],
                  ),
                ),
                dark: dark,
                language: language,
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('OPERATIONAL'), findsNothing);
            expect(tester.takeException(), isNull);
            expect(
              find.textContaining(
                language == 'en'
                    ? 'Confirmed passable'
                    : 'Kumpirmadong madaraanan',
              ),
              findsOneWidget,
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
      state.roads
        ..clear()
        ..addAll(old);
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
