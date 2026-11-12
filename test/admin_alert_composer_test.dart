import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/screens/admin/broadcast_alert_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/services/weather_service.dart';
import 'package:safepaths_app/theme/app_theme.dart';

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
  home: child,
);

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('broadcast-title')),
    'Flood advisory',
  );
  await tester.enterText(
    find.byKey(const ValueKey('broadcast-message')),
    'Avoid the flooded crossing. Use the marked detour.',
  );
}

Future<void> review(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Review alert'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'ALERT_PREVIEW=true');
  });
  tearDownAll(() => SimulatedWeatherService.instance.dispose());

  testWidgets(
    'review requires valid content, shows the full draft and never publishes on cancel',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        shell(
          BroadcastAlertScreen(
            now: () => DateTime(2026, 10, 30, 13, 30),
            publishAlert: (draft) async {
              calls++;
              return BroadcastResult(alertSaved: true);
            },
          ),
        ),
      );
      await review(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, 0);
      await fill(tester);
      await review(tester);
      expect(find.text('Keep editing'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Flood advisory')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Avoid the flooded crossing. Use the marked detour.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(AppEnvironment.area.name),
        ),
        findsWidgets,
      );
      expect(
        find.text('In-app alert only. No push notification requested.'),
        findsOneWidget,
      );
      expect(find.textContaining('all active users'), findsNothing);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('broadcast-title')),
            )
            .controller!
            .text,
        'Flood advisory',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'publication failure preserves the draft and an in-flight retry cannot be sent twice',
    (tester) async {
      final sent = <BroadcastDraft>[];
      final completion = Completer<BroadcastResult>();
      await tester.pumpWidget(
        shell(
          BroadcastAlertScreen(
            publishAlert: (draft) async {
              sent.add(draft);
              if (sent.length == 1) {
                throw StateError('Synthetic connection interruption');
              }
              return completion.future;
            },
          ),
        ),
      );
      await fill(tester);
      await review(tester);
      await tester.tap(find.text('Publish alert'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not confirm publication.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('broadcast-message')),
            )
            .controller!
            .text,
        'Avoid the flooded crossing. Use the marked detour.',
      );
      await review(tester);
      await tester.tap(find.text('Publish alert'));
      await tester.pump();
      expect(sent.length, 2);
      expect(sent[1].title, sent[0].title);
      expect(sent[1].message, sent[0].message);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Publishing…'),
            )
            .onPressed,
        isNull,
      );
      completion.complete(BroadcastResult(alertSaved: true, queuedCount: 1));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Alert published. Notifications queued; phone delivery is not confirmed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Published alerts'), findsOneWidget);
      await tester.tap(find.text('Write alert'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('broadcast-title')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'road location preserves the audience and reviewed publication settings',
    (tester) async {
      final state = AppStateService.instance,
          previous = [...AppStateService.instance.roads];
      final road = RoadStatus(
        id: 'synthetic-alert-road',
        name: 'Sample Road',
        status: 'not_passable',
        notes: '',
        updatedAt: DateTime.now(),
      );
      state.roads
        ..clear()
        ..add(road);
      addTearDown(() {
        state.roads
          ..clear()
          ..addAll(previous);
      });
      BroadcastDraft? sent;
      await tester.pumpWidget(
        shell(
          BroadcastAlertScreen(
            publishAlert: (draft) async {
              sent = draft;
              return BroadcastResult(alertSaved: false);
            },
          ),
        ),
      );
      await fill(tester);
      final location = find.widgetWithText(ListTile, AppEnvironment.area.name);
      await tester.ensureVisible(location);
      await tester.pumpAndSettle();
      await tester.tap(location);
      await tester.pumpAndSettle();
      expect(find.text('Choose alert location'), findsOneWidget);
      await tester.tap(find.text('Sample Road'));
      await tester.pumpAndSettle();
      if (AppEnvironment.sparkCommunicationsEnabled) {
        await tester.ensureVisible(find.text('15 min'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15 min'));
        await tester.pumpAndSettle();
      }
      if (AppEnvironment.communicationPushAllowed) {
        final notification = find.text('Also notify eligible residents');
        await tester.ensureVisible(notification);
        await tester.pumpAndSettle();
        await tester.tap(notification);
        await tester.pumpAndSettle();
      }
      await review(tester);
      expect(find.text('Audience: ${AppEnvironment.area.name}'), findsWidgets);
      await tester.tap(find.text('Publish alert'));
      await tester.pumpAndSettle();
      expect(sent!.roadId, road.id);
      expect(
        sent!.minutes,
        AppEnvironment.sparkCommunicationsEnabled ? 15 : 1440,
      );
      expect(sent!.sendPush, AppEnvironment.communicationPushAllowed);
      expect(state.roads.single.status, 'not_passable');
      expect(find.textContaining('nearby residents'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('using a saved template fills the composer without publishing', (
    tester,
  ) async {
    var publications = 0;
    final template = AppStateService.instance.templates.first;
    await tester.pumpWidget(
      shell(
        BroadcastAlertScreen(
          publishAlert: (_) async {
            publications++;
            return BroadcastResult(alertSaved: true);
          },
        ),
      ),
    );
    final browse = find.text('Browse templates');
    await tester.ensureVisible(browse);
    await tester.pumpAndSettle();
    await tester.tap(browse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use template').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('broadcast-title')))
          .controller!
          .text,
      template.title,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('broadcast-message')),
          )
          .controller!
          .text,
      template.message,
    );
    expect(publications, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late publication failure cannot write to a disposed screen', (
    tester,
  ) async {
    final completion = Completer<BroadcastResult>();
    await tester.pumpWidget(
      shell(BroadcastAlertScreen(publishAlert: (_) => completion.future)),
    );
    await fill(tester);
    await review(tester);
    await tester.tap(find.text('Publish alert'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    completion.completeError(StateError('Synthetic late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'active alerts expire without a backend update and remain available in past alerts',
    (tester) async {
      var clock = DateTime.now();
      await AppStateService.instance.broadcastAlert(
        'Synthetic expiry check',
        'Synthetic alert for expiry testing only.',
        'Advisory',
      );
      await tester.pumpWidget(shell(BroadcastAlertScreen(now: () => clock)));
      final activeTab = find.textContaining('Active (');
      await tester.tap(activeTab);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic expiry check'), findsOneWidget);
      clock = clock.add(const Duration(hours: 25));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Active (0)'), findsOneWidget);
      expect(find.text('No active alerts in this area.'), findsOneWidget);
      await tester.tap(find.text('Show past alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic expiry check'), findsOneWidget);
      expect(find.text('Expired'), findsWidgets);
      await tester.tap(find.text('View alert'));
      await tester.pumpAndSettle();
      expect(find.text('This alert has expired.'), findsOneWidget);
      expect(find.text('Withdraw alert'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'composer and review fit narrow screens in both themes and languages at enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final language in ['en', 'fil']) {
          await tester.pumpWidget(
            shell(
              const BroadcastAlertScreen(),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await fill(tester);
          final button = find.byWidgetPredicate(
            (w) => w is FilledButton && w.onPressed != null,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
