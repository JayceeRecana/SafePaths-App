// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safepaths_app/screens/login_screen.dart';

void main() {
  testWidgets('Login screen renders key actions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 2960);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('SafePaths'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
