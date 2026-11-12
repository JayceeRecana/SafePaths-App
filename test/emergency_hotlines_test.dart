import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/screens/shared/emergency_hotlines_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
    'Directory contains all eight supplied numbers with correct dial formats',
    () {
      final numbers = EmergencyHotlinesScreen.contacts
          .expand((c) => c.$4)
          .toList();
      expect(numbers.length, 8);
      expect(numbers.map((n) => n.$2).toSet(), {
        '+63283525000',
        '+63282921405',
        '+639190094045',
        '+639178811639',
        '+63282923519',
        '+63283524000',
        '+63283526000',
        '+63282946711',
      });
    },
  );

  testWidgets(
    'Tapping a number opens tel URI; failure keeps numbers accessible',
    (tester) async {
      Uri? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyHotlinesScreen(
            openLink: (uri) async {
              requested = uri;
              return false;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('(02) 8352 5000'));
      await tester.pumpAndSettle();
      expect(requested.toString(), 'tel:+63283525000');
      expect(
        find.text(
          'Could not open the dialer. Copy the number and dial it on your phone.',
        ),
        findsOneWidget,
      );
      expect(find.text('(02) 8352 5000'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Directory scrolls without overflow at large text in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const EmergencyHotlinesScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('About this directory'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('About this directory'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
