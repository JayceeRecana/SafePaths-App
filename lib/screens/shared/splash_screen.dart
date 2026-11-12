import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../services/user_service.dart';
import 'login_screen.dart';
import '../../services/account_security.dart';
import 'account_gate_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();

    _startupTimer = Timer(const Duration(milliseconds: 3500), () async {
      if (mounted) {
        if (firebaseInitFailed) {
          // Show error
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text(tr(context, 'Connection Error')),
              content: Text(
                tr(
                  context,
                  'Failed to connect to the server. Please check your internet connection and restart the app.',
                ),
              ),
            ),
          );
          return;
        }

        // 🔐 SESSION PERSISTENCE: Check if user is already logged in
        final currentUser = FirebaseAuth.instance.currentUser;
        Widget destination = const LoginScreen();

        if (currentUser != null) {
          final expired = AccountSecurity.sessionExpired(
            now: DateTime.now(),
            lastActivity: await UserService.lastActivity(),
            isAdmin: await UserService.getUserRole() == UserRole.admin,
          );
          if (currentUser.isAnonymous || expired) {
            await UserService.clearUserData();
          } else {
            destination = const AccountGateScreen();
          }
        }

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                destination,
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final logoSize = (bounds.maxHeight * .25).clamp(128.0, 192.0);
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(36),
                              child: Image.asset(
                                'assets/app_icon.png',
                                width: logoSize,
                                height: logoSize,
                                fit: BoxFit.contain,
                                cacheWidth: 576,
                                excludeFromSemantics: true,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'SafePaths',
                              textAlign: TextAlign.center,
                              style: text.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: p.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                context,
                                'Navigating Safely Through\nFlood-Prone Areas',
                              ),
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(
                                height: 1.5,
                                color: p.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 12, 40, 40),
                  child: Semantics(
                    label: tr(context, 'Loading...'),
                    child: SizedBox(
                      width: 160,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(100),
                        color: p.primary,
                        backgroundColor: p.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
