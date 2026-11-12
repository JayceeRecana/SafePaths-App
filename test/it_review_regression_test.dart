import 'dart:typed_data';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/screens/shared/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:safepaths_app/screens/shared/registration_screen.dart';
import 'package:safepaths_app/services/routing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:safepaths_app/utils/password_policy.dart';
import 'package:safepaths_app/utils/report_image.dart';

void main() {
  testWidgets('login visibility matches password state and hides unavailable providers', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    final password = find.byType(TextField).at(1);
    await tester.enterText(password, 'Example1!');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(tester.widget<TextField>(password).controller!.text, 'Example1!');
    expect(find.text('Google'), findsNothing);
    expect(find.text('Apple'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('manual start point updates planner and clears GPS loading', () {
    final routing = RoutingService.instance;
    routing.exitPlanning();
    routing.isLocatingGps = true;
    routing.setOrigin(Position(120.984, 14.676), 'Selected start');
    expect(routing.originPoint!.lng, 120.984);
    expect(routing.originName, 'Selected start');
    expect(routing.isLocatingGps, isFalse);
    routing.exitPlanning();
    expect(routing.originName, isEmpty);
  });

  testWidgets(
    'registration stays readable on small screen and toggles both passwords',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: RegistrationScreen()));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Abcdef1!');
      await tester.pump();
      expect(find.text('Requirements met: 5/5'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(2)).obscureText, isFalse);
      await tester.ensureVisible(fields.at(3));
      await tester.enterText(fields.at(3), 'different');
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      await tester.tap(find.byTooltip('Show confirmation password'));
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(3)).obscureText, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('registration rejects passwords missing any required category', () {
    for (final value in [
      '',
      'Aa1!',
      'abcdef1!',
      'ABCDEF1!',
      'Abcdefg!',
      'Abcdef12',
      'Abcdef1 ',
    ]) {
      expect(PasswordPolicy.isValid(value), isFalse, reason: value);
    }
    expect(PasswordPolicy.isValid('Abcdef1!'), isTrue);
    expect(PasswordPolicy.isValid('A longer passphrase 1!'), isTrue);
  });

  for (final size in [(1200, 300), (300, 1200), (40, 20), (1, 1)]) {
    test('upload preserves aspect ratio for $size', () {
      final source = img.Image(width: size.$1, height: size.$2);
      final result = img.decodeJpg(
        prepareReportImage(Uint8List.fromList(img.encodePng(source))),
      )!;
      expect(result.width, lessThanOrEqualTo(600));
      expect(result.height, lessThanOrEqualTo(600));
      expect(result.width / result.height, closeTo(size.$1 / size.$2, 0.01));
      if (size.$1 < 600 && size.$2 < 600) {
        expect(result.width, size.$1);
        expect(result.height, size.$2);
      }
    });
  }
  test('bad and oversized uploads fail clearly', () {
    expect(
      () => prepareReportImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => prepareReportImage(Uint8List(10 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
