import '../../l10n/app_strings.dart';
import 'dart:async';
import '../../services/notification_service.dart';
import '../../services/cached_road_reader.dart';
import 'saved_roads_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_service.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';
import '../user/user_home_screen.dart';
import '../admin/admin_home_screen.dart';

/// Every password sign-in and restored session passes through this gate.
class AccountGateScreen extends StatefulWidget {
  final bool sendVerificationOnOpen;

  /// Exercises loading/navigation transitions without a Firebase session in tests.
  @visibleForTesting
  final Future<Widget> Function()? resolveDestination;
  const AccountGateScreen({
    super.key,
    this.sendVerificationOnOpen = false,
    this.resolveDestination,
  });
  @override
  State<AccountGateScreen> createState() => _AccountGateScreenState();
}

class _AccountGateScreenState extends State<AccountGateScreen> {
  String? _error;
  bool _busy = true;
  bool _opening = false;
  bool _offerSavedRoads = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  void _open(Widget screen) {
    if (!mounted || _opening) return;
    _opening = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  Future<void> _resolve() async {
    if (!mounted || _opening) return;
    setState(() {
      _busy = true;
      _error = null;
      _offerSavedRoads = false;
    });
    try {
      if (widget.resolveDestination != null) {
        _open(await widget.resolveDestination!());
        return;
      }
      var user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        await UserService.clearUserData();
        _open(const LoginScreen());
        return;
      }
      if (!user.emailVerified) {
        _open(
          EmailVerificationScreen(sendOnOpen: widget.sendVerificationOnOpen),
        );
        return;
      }
      await user.reload().timeout(const Duration(seconds: 10));
      user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.emailVerified) {
        _open(const EmailVerificationScreen());
        return;
      }
      await user.getIdToken(true).timeout(const Duration(seconds: 10));
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var doc = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!doc.exists) {
        // Recover from account creation succeeding while profile creation failed.
        await ref
            .set({
              'name': user.displayName ?? 'Resident',
              'email': user.email ?? '',
              'role': 'user',
              'trustScore': 50,
              'verifiedReports': 0,
              'dismissedReports': 0,
              'createdAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));
        doc = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
      }
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != ref.id) {
        return;
      }
      final role = doc.data()?['role'] == 'admin'
          ? UserRole.admin
          : UserRole.user;
      await UserService.saveUserRole(role);
      await UserService.touchSession(force: true);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != ref.id) {
        return;
      }
      // Registration can precede profile creation/recovery. Retry only once
      // the verified profile is ready; push setup must not delay entry.
      unawaited(NotificationService.instance.syncFcmToken());
      _open(
        role == UserRole.admin
            ? const AdminHomeScreen()
            : const UserHomeScreen(),
      );
    } on FirebaseAuthException catch (e) {
      if ([
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      ].contains(e.code)) {
        await UserService.clearUserData();
        _open(const LoginScreen());
      } else {
        await _failed(e);
      }
    } catch (error) {
      await _failed(error);
    } finally {
      if (mounted && !_opening) setState(() => _busy = false);
    }
  }

  Future<void> _failed(Object error) async {
    bool offer = false;
    if (CachedRoadReader.isNetworkFailure(error)) {
      try {
        offer = await CachedRoadReader.sessionAllowed();
      } catch (_) {}
    }
    if (mounted)
      setState(() {
        _error =
            'Unable to confirm your account. Check your connection and retry.';
        _offerSavedRoads = offer;
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(tr(context, 'Checking account...')),
              ] else ...[
                Text(tr(context, _error ?? 'Account check incomplete.')),
                if (_offerSavedRoads)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SavedRoadsScreen(),
                      ),
                    ),
                    child: Text(tr(context, 'View saved roads (read only)')),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _resolve,
                  child: Text(tr(context, 'Retry')),
                ),
                TextButton(
                  onPressed: () async {
                    await UserService.clearUserData();
                    _open(const LoginScreen());
                  },
                  child: Text(tr(context, 'Back to sign in')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
