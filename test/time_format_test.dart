import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/l10n/formatters.dart';

void main() {
  for (final language in ['en', 'fil']) {
    testWidgets(
      '$language shows AM/PM even when the phone uses a 24-hour clock',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('fil')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
              data: const MediaQueryData(alwaysUse24HourFormat: true),
              child: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      Text(
                        localizedClock(context, DateTime(2026, 10, 26, 0, 5)),
                      ),
                      Text(
                        localizedClock(context, DateTime(2026, 10, 26, 12, 5)),
                      ),
                      Text(
                        localizedDateTime(
                          context,
                          DateTime(2026, 10, 26, 20, 45),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showTimePicker(
                          context: context,
                          initialTime: const TimeOfDay(hour: 20, minute: 45),
                          builder: twelveHourPickerBuilder,
                        ),
                        child: const Text('Choose'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'fil' ? '12:05 am' : '12:05 AM'),
          findsOneWidget,
        );
        expect(
          find.text(language == 'fil' ? '12:05 pm' : '12:05 PM'),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'fil' ? '8:45 pm' : '8:45 PM'),
          findsOneWidget,
        );
        expect(find.textContaining('20:45'), findsNothing);
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        expect(find.text('AM'), findsOneWidget);
        expect(find.text('PM'), findsOneWidget);
        final pickerContext = tester.element(find.byType(TimePickerDialog));
        expect(MediaQuery.of(pickerContext).alwaysUse24HourFormat, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
