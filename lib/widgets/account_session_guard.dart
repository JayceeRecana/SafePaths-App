import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/account_security.dart';
import '../services/user_service.dart';
import '../screens/shared/login_screen.dart';

class AccountSessionGuard extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const AccountSessionGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
  });
  @override
  State<AccountSessionGuard> createState() => _AccountSessionGuardState();
}

class _AccountSessionGuardState extends State<AccountSessionGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<User?>? _authSubscription;
  bool _checking = false;
  bool _ending = false;
  String? _uid;
  DateTime? _lastRefresh;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isEmpty) return;
    _uid = FirebaseAuth.instance.currentUser?.uid;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen((user) {
      final signedOut = _uid != null && user == null;
      _uid = user?.uid;
      if (signedOut && !_ending) _returnToLogin();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(refresh: true);
  }

  Future<void> _returnToLogin() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  }

  Future<bool> _check({bool refresh = false, bool touch = false}) async {
    if (_checking ||
        _ending ||
        Firebase.apps.isEmpty ||
        SessionActivity.authenticationInProgress)
      return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    _checking = true;
    try {
      final isAdmin = await UserService.getUserRole() == UserRole.admin;
      final expired = AccountSecurity.sessionExpired(
        now: DateTime.now(),
        lastActivity: await UserService.lastActivity(),
        isAdmin: isAdmin,
        navigating: SessionActivity.navigating,
      );
      if (expired) {
        _ending = true;
        await UserService.clearUserData();
        await _returnToLogin();
        return false;
      }
      if (refresh ||
          _lastRefresh == null ||
          DateTime.now().difference(_lastRefresh!) >=
              const Duration(minutes: 5)) {
        try {
          await user.reload().timeout(const Duration(seconds: 8));
          await FirebaseAuth.instance.currentUser
              ?.getIdToken(true)
              .timeout(const Duration(seconds: 8));
          _lastRefresh = DateTime.now();
        } on FirebaseAuthException catch (e) {
          if ([
            'user-disabled',
            'user-not-found',
            'user-token-expired',
            'invalid-user-token',
          ].contains(e.code)) {
            _ending = true;
            await UserService.clearUserData();
            await _returnToLogin();
            return false;
          }
        } catch (_) {
          /* A network outage alone does not end a valid session. */
        }
      }
      if (touch || !isAdmin && SessionActivity.navigating)
        await UserService.touchSession();
      return true;
    } finally {
      _checking = false;
      _ending = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _check(touch: true),
    onPointerSignal: (_) => _check(touch: true),
    child: widget.child,
  );
}
