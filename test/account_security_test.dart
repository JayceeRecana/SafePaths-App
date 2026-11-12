import 'dart:async';
import 'package:safepaths_app/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safepaths_app/services/account_security.dart';
import 'package:safepaths_app/services/email_verification.dart';
import 'package:safepaths_app/screens/shared/email_verification_screen.dart';

class FakeVerification implements VerificationActions {
  bool verified = false;
  int sends = 0;
  DateTime? next;
  Completer<void>? sendCompleter;
  @override
  String get email => 'resident@example.com';
  @override
  Future<bool> refresh() async => verified;
  @override
  Future<DateTime?> nextResendAt() async => next;
  @override
  Future<void> send() async {
    sends++;
    next = DateTime.now().add(const Duration(minutes: 1));
    if (sendCompleter != null) await sendCompleter!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('email validation rejects incomplete and whitespace addresses', () {
    for (final email in [
      '',
      'resident',
      'resident@',
      'a b@example.com',
      'a@example',
    ]) {
      expect(AccountSecurity.validEmail(email), isFalse);
    }
    expect(AccountSecurity.validEmail(' resident@example.com '), isTrue);
  });
  test(
    'five failed attempts persist a device cooldown and success clears it',
    () async {
      for (var i = 0; i < 4; i++) await AccountSecurity.failedLogin();
      expect(await AccountSecurity.remainingLoginSeconds(), 0);
      await AccountSecurity.failedLogin();
      expect(
        await AccountSecurity.remainingLoginSeconds(),
        inInclusiveRange(1, 60),
      );
      await AccountSecurity.clearFailures();
      expect(await AccountSecurity.remainingLoginSeconds(), 0);
      await AccountSecurity.failedLogin(providerLimited: true);
      expect(await AccountSecurity.remainingLoginSeconds(), greaterThan(0));
    },
  );
  test('credential errors do not reveal whether an email exists', () {
    expect(
      AccountSecurity.loginError('user-not-found'),
      AccountSecurity.loginError('wrong-password'),
    );
    expect(
      AccountSecurity.loginError('invalid-credential'),
      AccountSecurity.loginError('wrong-password'),
    );
  });
  test(
    'session expiry enforces role limits while preserving resident navigation',
    () {
      final now = DateTime(2026, 10, 23, 20);
      bool expired(
        int minutes, {
        bool admin = false,
        bool navigating = false,
      }) => AccountSecurity.sessionExpired(
        now: now,
        lastActivity: now.subtract(Duration(minutes: minutes)),
        isAdmin: admin,
        navigating: navigating,
      );
      expect(expired(14, admin: true), isFalse);
      expect(expired(15, admin: true), isTrue);
      expect(expired(15, admin: true, navigating: true), isTrue);
      expect(expired(29), isFalse);
      expect(expired(30), isTrue);
      expect(expired(60, navigating: true), isFalse);
      expect(
        AccountSecurity.sessionExpired(
          now: now,
          lastActivity: null,
          isAdmin: false,
        ),
        isTrue,
      );
      expect(
        AccountSecurity.sessionExpired(
          now: now,
          lastActivity: now.add(const Duration(minutes: 2)),
          isAdmin: false,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'plaintext remote image URLs are rejected without a network request',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeImage(imageUrl: 'http://example.com/photo.jpg'),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_not_supported_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'verification screen does not pass an unverified account and supports refreshed verification',
    (tester) async {
      final actions = FakeVerification();
      var allowed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: EmailVerificationScreen(
            actions: actions,
            onVerified: () => allowed = true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text("I've verified my email"));
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
      expect(find.textContaining('not verified yet'), findsOneWidget);
      actions.verified = true;
      await tester.tap(find.text("I've verified my email"));
      await tester.pumpAndSettle();
      expect(allowed, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'resend prevents duplicate requests and starts a visible cooldown',
    (tester) async {
      final actions = FakeVerification()..sendCompleter = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(home: EmailVerificationScreen(actions: actions)),
      );
      await tester.pump();
      await tester.tap(find.text('Send verification email'));
      await tester.pump();
      expect(actions.sends, 1);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Send verification email'),
      );
      expect(button.onPressed, isNull);
      actions.sendCompleter!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Resend in'), findsOneWidget);
      expect(actions.sends, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
