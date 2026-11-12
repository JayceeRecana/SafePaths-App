import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/l10n/app_strings.dart';
import 'package:safepaths_app/l10n/formatters.dart';
import 'package:safepaths_app/services/app_preferences.dart';
import 'package:safepaths_app/services/last_road_sync_store.dart';
import 'package:safepaths_app/services/notification_tap_inbox.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/widgets/feed_status_notice.dart';
import 'package:safepaths_app/widgets/bottom_nav_bar.dart';
import 'package:safepaths_app/widgets/admin_bottom_nav_bar.dart';
import 'package:safepaths_app/theme/app_palette.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/screens/user/road_list_screen.dart';
import 'package:safepaths_app/screens/user/road_details_screen.dart';
import 'package:safepaths_app/screens/shared/saved_roads_screen.dart';
import 'package:safepaths_app/services/cached_road_reader.dart';

Widget shell(
  Widget child, {
  String language = 'en',
  double scale = 1,
  ThemeMode themeMode = ThemeMode.light,
}) => MaterialApp(
  theme: AppTheme.theme,
  darkTheme: AppTheme.darkTheme,
  themeMode: themeMode,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test(
    'language choice persists and unsupported/corrupt choices fall back',
    () async {
      final first = AppPreferences();
      await first.load();
      expect(first.locale.languageCode, 'en');
      expect(await first.setLanguage('fil'), isTrue);
      final restarted = AppPreferences();
      await restarted.load();
      expect(restarted.locale.languageCode, 'fil');
      expect(() => restarted.setLanguage('xx'), throwsArgumentError);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app.language', 'invalid');
      await restarted.load();
      expect(restarted.locale.languageCode, 'en');
    },
  );

  test(
    'saved sync survives restart, stays project-scoped and rejects future time',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 10, 24, 10);
      final store = LastRoadSyncStore(prefs, 'test-area');
      await store.save(now);
      expect(LastRoadSyncStore(prefs, 'test-area').read(now: now), now);
      expect(LastRoadSyncStore(prefs, 'other-area').read(now: now), isNull);
      expect(store.read(now: now.subtract(const Duration(minutes: 1))), isNull);
      final health = SyncHealth()..lastRoadSync = store.read(now: now);
      health.update('roads', fromCache: true);
      expect(health.roadsLive, isFalse);
      expect(health.lastRoadSync, now);
      health.reset();
      expect(health.lastRoadSync, now);
      health.reset(clearHistory: true);
      expect(health.lastRoadSync, isNull);
      expect(health.lastRiskCompute, isNull);
    },
  );

  test(
    'appearance choice survives restart and invalid values follow the phone',
    () async {
      final first = AppPreferences();
      await first.load();
      expect(first.themeMode, ThemeMode.system);
      expect(await first.setThemeMode(ThemeMode.dark), isTrue);
      final restarted = AppPreferences();
      await restarted.load();
      expect(restarted.themeMode, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app.theme', 'invalid');
      await restarted.load();
      expect(restarted.themeMode, ThemeMode.system);
    },
  );

  test('core text and safety color pairs meet 4.5:1 in both palettes', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final palette in [AppPalette.light, AppPalette.dark]) {
      final pairs = [
        (palette.onSurface, palette.surface),
        (palette.onSurfaceVariant, palette.surfaceContainerHigh),
        (palette.primary, palette.surface),
        (palette.onPrimary, palette.primary),
        (palette.onPrimaryContainer, palette.primaryContainer),
        (palette.secondary, palette.surface),
        (palette.onSecondary, palette.secondary),
        (palette.onSecondaryContainer, palette.secondaryContainer),
        (palette.tertiary, palette.surface),
        (palette.onTertiary, palette.tertiary),
        (palette.onTertiaryContainer, palette.tertiaryContainer),
        (palette.error, palette.surface),
        (palette.onError, palette.error),
        (palette.onErrorContainer, palette.errorContainer),
        (palette.onWarningContainer, palette.warningContainer),
        (palette.passable, palette.surface),
        (palette.partial, palette.surface),
        (palette.notPassable, palette.surface),
      ];
      for (final pair in pairs) {
        expect(
          contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.isDark} ${pair.$1} / ${pair.$2}',
        );
      }
    }
  });

  testWidgets(
    'theme switches recolor an existing screen without losing its state',
    (tester) async {
      final preferences = AppPreferences();
      await preferences.load();
      final controller = TextEditingController(text: 'Unsent observation');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: preferences,
          builder: (_, _) => shell(
            Builder(
              builder: (context) => Column(
                children: [
                  Container(
                    key: const Key('panel'),
                    color: AppPalette.of(context).surface,
                    child: TextField(controller: controller),
                  ),
                  Text(Theme.of(context).brightness.name),
                ],
              ),
            ),
            themeMode: preferences.themeMode,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await preferences.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('dark'), findsOneWidget);
      expect(controller.text, 'Unsent observation');
      expect(
        (tester.widget<Container>(find.byKey(const Key('panel')))).color,
        AppPalette.dark.surface,
      );
      await preferences.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(find.text('light'), findsOneWidget);
    },
  );

  test(
    'notification tap waits for home and sign-out clears queued contents',
    () {
      final inbox = NotificationTapInbox();
      final received = <Map<String, dynamic>>[];
      final payload = {'type': 'report_reply', 'reportId': 'report-a'};
      inbox.receive(payload);
      payload['type'] = 'changed';
      inbox.attach(received.add);
      expect(received.single['type'], 'report_reply');
      inbox.detach();
      inbox.receive({'type': 'old-account'});
      inbox.clear();
      inbox.attach(received.add);
      expect(received.length, 1);
      inbox.receive({'type': 'broadcast'});
      expect(received.last['type'], 'broadcast');
    },
  );

  test(
    'saved-reader eligibility preserves verification and session expiry',
    () {
      final now = DateTime(2026, 10, 24, 12);
      bool allowed({
        bool signedIn = true,
        bool anonymous = false,
        bool verified = true,
        int age = 5,
        bool admin = false,
      }) => CachedRoadReader.eligible(
        signedIn: signedIn,
        anonymous: anonymous,
        verified: verified,
        now: now,
        lastActivity: now.subtract(Duration(minutes: age)),
        isAdmin: admin,
      );
      expect(allowed(), isTrue);
      expect(allowed(signedIn: false), isFalse);
      expect(allowed(anonymous: true), isFalse);
      expect(allowed(verified: false), isFalse);
      expect(allowed(age: 30), isFalse);
      expect(allowed(age: 15, admin: true), isFalse);
      expect(allowed(age: -3), isFalse);
      expect(
        CachedRoadReader.isNetworkFailure(TimeoutException('offline')),
        isTrue,
      );
      expect(
        CachedRoadReader.isNetworkFailure(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isTrue,
      );
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'user-disabled',
        'invalid-user-token',
      ]) {
        expect(
          CachedRoadReader.isNetworkFailure(
            FirebaseException(plugin: 'test', code: code),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'compiled catalog matches every translation source without empty entries',
    () {
      final source = <String, dynamic>{};
      for (final file in Directory(
        'lib/l10n',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        final entries =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final entry in entries.entries) {
          expect(entry.value, isA<String>());
          expect((entry.value as String).trim(), isNotEmpty, reason: entry.key);
          expect(
            source.containsKey(entry.key),
            isFalse,
            reason: 'Duplicate: ${entry.key}',
          );
        }
        source.addAll(entries);
      }
      expect(filipinoMessages, source);
    },
  );

  testWidgets(
    'language changes rebuild visible UI and preserve supplied report text',
    (tester) async {
      final preferences = AppPreferences();
      await preferences.load();
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: preferences,
          builder: (_, _) => shell(
            Builder(
              builder: (context) => Column(
                children: [
                  Text(tr(context, 'Report History')),
                  const Text('Roads'),
                ],
              ),
            ),
            language: preferences.locale.languageCode,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report History'), findsOneWidget);
      await preferences.setLanguage('fil');
      await tester.pumpAndSettle();
      expect(find.text('Kasaysayan ng mga ulat'), findsOneWidget);
      expect(
        find.text('Roads'),
        findsOneWidget,
      ); // Authored content remains verbatim.
    },
  );

  testWidgets('an empty offline feed never claims there are no alerts', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        FeedStatusNotice(
          condition: SyncCondition.cached,
          isEmpty: true,
          emptyMessage: 'No active alerts right now.',
          onRetry: () {},
        ),
      ),
    );
    expect(find.text('No active alerts right now.'), findsNothing);
    expect(find.textContaining('No saved information'), findsOneWidget);
    await tester.pumpWidget(
      shell(
        FeedStatusNotice(
          condition: SyncCondition.live,
          isEmpty: true,
          emptyMessage: 'No active alerts right now.',
          onRetry: () {},
        ),
      ),
    );
    expect(find.text('No active alerts right now.'), findsOneWidget);
  });

  testWidgets(
    'Filipino failure message wraps at 200% text on a small display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await tester.pumpWidget(
        shell(
          SingleChildScrollView(
            child: FeedStatusNotice(
              condition: SyncCondition.failed,
              isEmpty: true,
              emptyMessage: '',
              onRetry: () => retries++,
            ),
          ),
          language: 'fil',
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kunin muli ang mga update'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resident and admin navigation fit small screens with large Filipino text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final bar in [
        BottomNavBar(currentIndex: 0, onTap: (_) {}),
        AdminBottomNavBar(currentIndex: 0, onTap: (_) {}),
      ]) {
        await tester.pumpWidget(
          shell(
            Align(alignment: Alignment.bottomCenter, child: bar),
            language: 'fil',
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(48),
        );
      }
    },
  );

  testWidgets('relative observation ages and unknown statuses are localized', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 24, 12);
    await tester.pumpWidget(
      shell(
        Builder(
          builder: (context) => Column(
            children: [
              Text(
                localizedAge(
                  context,
                  now.subtract(const Duration(hours: 2)),
                  now,
                ),
              ),
              Text(localizedReportStatus(context, 'unexpected')),
            ],
          ),
        ),
        language: 'fil',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 oras ang nakalipas'), findsOneWidget);
    expect(find.text('Hindi kumpirmado'), findsOneWidget);
  });

  testWidgets(
    'accessible road list supports offline labels, Filipino dates and local search',
    (tester) async {
      final state = AppStateService.instance;
      await state.clearSession();
      await state.initialize();
      state.syncHealth.update('roads', fromCache: true);
      await tester.pumpWidget(
        shell(
          const RoadListScreen(),
          language: 'fil',
          themeMode: ThemeMode.dark,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final firstName =
          (state.roads.map((road) => road.name).toList()..sort()).first;
      expect(find.text(firstName), findsOneWidget);
      expect(find.textContaining('Huling nakatalang update'), findsWidgets);
      expect(
        find.text(
          'Ipinapakita ang naka-save na impormasyon. Kumonekta muli upang kumuha ng mga update.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'no-such-road');
      await tester.pumpAndSettle();
      expect(
        find.text('Walang kalsadang tumugma sa iyong paghahanap.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await state.clearSession();
    },
  );

  testWidgets(
    'road selection returns to the existing map before opening translucent details',
    (tester) async {
      final state = AppStateService.instance;
      await state.clearSession();
      await state.initialize();
      state.syncHealth.update('roads', fromCache: false);
      state.syncHealth.update('reports', fromCache: false);
      state.syncHealth.lastRiskCompute = DateTime.now();
      String? selected;
      final road =
          (state.roads.toList()..sort((a, b) => a.name.compareTo(b.name)))
              .first;
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) => Column(
              children: [
                const Text('Existing map canvas'),
                TextButton(
                  onPressed: () async {
                    final id = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const RoadListScreen()),
                    );
                    if (!context.mounted || id == null) return;
                    selected = id;
                    Navigator.of(context).push(RoadDetailsScreen.route(id));
                  },
                  child: const Text('Browse roads'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browse roads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(road.name));
      await tester.pumpAndSettle();
      expect(selected, road.id);
      expect(find.byType(RoadListScreen), findsNothing);
      expect(find.text('Existing map canvas'), findsOneWidget);
      final details = find.byType(RoadDetailsScreen);
      expect(details, findsOneWidget);
      expect(ModalRoute.of(tester.element(details))!.opaque, isFalse);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('road-details-viewport')),
      );
      final sheet = tester.getRect(
        find.byKey(const ValueKey('road-details-sheet')),
      );
      expect(sheet.bottom, closeTo(viewport.bottom - 12, 1));
      expect(sheet.top, closeTo(viewport.top + viewport.height * .4, 1));
      expect(sheet.height, closeTo(viewport.height * .6 - 12, 1));
      await tester.tap(find.byKey(const ValueKey('close-road-details')));
      await tester.pumpAndSettle();
      expect(find.text('Existing map canvas'), findsOneWidget);
      expect(find.byType(RoadDetailsScreen), findsNothing);
      // Back from the picker returns no selection and leaves the map alone.
      selected = null;
      await tester.tap(find.text('Browse roads'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(RoadListScreen))).pop();
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byType(RoadDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await state.clearSession();
    },
  );

  testWidgets(
    'read-only saved viewer distinguishes old status, empty cache and read failure',
    (tester) async {
      final time = DateTime(2026, 10, 24, 10);
      final road = RoadStatus(
        id: 'cached',
        name: 'Cached Road',
        status: 'not_passable',
        notes: 'Original official note',
        updatedAt: time,
      );
      await tester.pumpWidget(
        shell(
          SavedRoadsScreen(
            loader: () async => CachedRoadSnapshot([road], time),
          ),
          language: 'fil',
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cached Road'), findsOneWidget);
      expect(find.text('Original official note'), findsOneWidget);
      expect(
        find.text('Huling nakatalang kondisyon: Hindi madadaanan'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Hindi kumpirmado ang kasalukuyang kondisyon'),
        findsOneWidget,
      );
      // Only the back button is offered: no route/report/admin entry points.
      expect(find.byType(IconButton), findsOneWidget);
      await tester.pumpWidget(
        shell(
          SavedRoadsScreen(
            key: const ValueKey('empty'),
            loader: () async => const CachedRoadSnapshot([], null),
          ),
          language: 'fil',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Walang naka-save na kalsada sa teleponong ito. Kumonekta upang ma-load ang datos ng kalsada.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        shell(
          SavedRoadsScreen(
            key: const ValueKey('error'),
            loader: () async => throw StateError('cache failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saved roads could not be read'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
