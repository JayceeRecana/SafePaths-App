import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/l10n/app_strings.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/navigation_hud.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in [const Size(320, 568), const Size(740, 360)]) {
    for (final dark in [false, true]) {
      for (final language in ['en', 'fil']) {
        testWidgets(
          'HUD preserves controls at $size, 200% text, $language, dark=$dark',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var details = 0, ended = 0, retries = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.theme,
                darkTheme: AppTheme.darkTheme,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                supportedLocales: const [Locale('en'), Locale('fil')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                locale: Locale(language),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => NavigationHud(
                      guidance: NavigationGuidanceCard(
                        title: tr(context, 'Guidance paused'),
                        detail:
                            'Waiting for GPS. A long road name remains available without covering trip controls.',
                        icon: Icons.location_disabled_outlined,
                        action: TextButton(
                          onPressed: () => retries++,
                          child: const Text('Retry GPS'),
                        ),
                      ),
                      notice: const NavigationNotice(
                        title: 'Road ahead not passable',
                        detail:
                            'A long barangay road name and a confirmed closure remain visible while waiting for a fresh GPS fix.',
                        tone: NavigationTone.danger,
                      ),
                      controls: const Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: null,
                          icon: Icon(Icons.my_location),
                        ),
                      ),
                      footer: NavigationTripPanel(
                        time: '13 min',
                        distance: '1.8 km remaining',
                        estimateLabel: tr(context, 'Previous route estimate'),
                        arrived: false,
                        paused: true,
                        onDetails: () => details++,
                        onEnd: () => ended++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            final footer = tester.getRect(
              find.byKey(const ValueKey('navigation-trip-panel')),
            );
            final top = tester.getRect(
              find.byKey(const ValueKey('navigation-top-scroll')),
            );
            expect(top.bottom, lessThanOrEqualTo(footer.top));
            expect(footer.bottom, lessThanOrEqualTo(size.height));
            final detailsButton = find.byTooltip(
              tr(
                tester.element(find.byType(NavigationTripPanel)),
                'Trip details',
              ),
            );
            await tester.tap(detailsButton);
            final endButton = find.widgetWithText(
              FilledButton,
              tr(tester.element(find.byType(NavigationTripPanel)), 'End Route'),
            );
            await tester.tap(endButton);
            expect(details, 1);
            expect(ended, 1);
            await tester.ensureVisible(find.text('Retry GPS'));
            await tester.tap(find.text('Retry GPS'));
            expect(retries, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'normal HUD leaves open map gestures and positions controls above footer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var mapTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => mapTaps++,
                  child: const SizedBox.expand(),
                ),
                NavigationHud(
                  guidance: const NavigationGuidanceCard(
                    title: '80 m',
                    detail: 'Turn left onto the next road',
                    icon: Icons.turn_left,
                  ),
                  controls: const Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: null,
                      icon: Icon(Icons.my_location),
                    ),
                  ),
                  footer: NavigationTripPanel(
                    time: '3 min',
                    distance: '557 m remaining',
                    estimateLabel: 'Estimated time remaining',
                    arrival: 'Arrival: 8:01 PM',
                    arrived: false,
                    paused: false,
                    onDetails: () {},
                    onEnd: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(150, 350));
      expect(mapTaps, 1);
      expect(find.byType(NavigationStatusCard), findsNothing);
      expect(
        tester.getRect(find.byIcon(Icons.my_location)).bottom,
        lessThan(tester.getRect(find.byType(NavigationTripPanel)).top),
      );
      expect(find.text('Arrival: 8:01 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
