import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/l10n/app_strings.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'package:safepaths_app/widgets/navigation_trip_details_sheet.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final size in [const Size(320, 568), const Size(740, 360)]) {
    for (final dark in [false, true]) {
      for (final language in ['en', 'fil']) {
        testWidgets(
          'Bounded details retains close and detour at $size, $language, dark=$dark',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var closed = 0, detours = 0;
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
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: size.height * .72,
                      child: NavigationTripDetailsSheet(
                        destination: 'Sample destination',
                        vehicle: 'Sedan',
                        conditionSummary: 'Check current local updates.',
                        scoreLabel: 'Unconfirmed',
                        stepTiming: true,
                        paused: false,
                        unconfirmedRoads: List.generate(
                          20,
                          (i) => 'Road segment ${i + 1}',
                        ),
                        showDetour: true,
                        onDetour: () => detours++,
                        onClose: () => closed++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(
              find.byType(NavigationTripDetailsSheet),
            );
            expect(find.text('Road segment 20'), findsNothing);
            final sheet = tester.getRect(
              find.byKey(const ValueKey('navigation-trip-details-sheet')),
            );
            expect(sheet.top, greaterThanOrEqualTo(size.height * .27));
            final roadSection = find.text(
              '${tr(context, 'Unconfirmed road segments')} (20)',
            );
            await tester.scrollUntilVisible(
              roadSection,
              150,
              scrollable: find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('navigation-trip-details-body'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            final roadIcon = find.descendant(
              of: find.ancestor(
                of: roadSection,
                matching: find.byType(ExpansionTile),
              ),
              matching: find.byIcon(Icons.warning_amber_rounded),
            );
            await tester.ensureVisible(roadIcon);
            await tester.pumpAndSettle();
            await tester.tap(roadIcon);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('Road segment 20'),
              300,
              scrollable: find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('navigation-trip-details-body'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(OutlinedButton, tr(context, 'Close')),
            );
            await tester.tap(
              find.widgetWithText(FilledButton, tr(context, 'Find detour')),
            );
            expect(closed, 1);
            expect(detours, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
