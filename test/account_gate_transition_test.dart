import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/screens/shared/account_gate_screen.dart';

void main() {
  testWidgets(
    'successful account checks remain loading throughout navigation',
    (tester) async {
      final result = Completer<Widget>();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountGateScreen(resolveDestination: () => result.future),
        ),
      );
      await tester.pump();
      expect(find.text('Checking account...'), findsOneWidget);
      result.complete(const Scaffold(body: Text('Resident home')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Account check incomplete.'), findsNothing);
        expect(find.text('Retry'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('Resident home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed account checks retain an explicit error and retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGateScreen(
          resolveDestination: () async {
            if (++attempts == 1) throw StateError('Unable to verify');
            return const Scaffold(body: Text('Resident home'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Unable to confirm your account. Check your connection and retry.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Resident home'), findsOneWidget);
    expect(find.text('Account check incomplete.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
