import '../../l10n/app_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/email_verification.dart';
import '../../services/user_service.dart';
import 'account_gate_screen.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final bool sendOnOpen;
  final VerificationActions? actions;
  final VoidCallback? onVerified;
  const EmailVerificationScreen({
    super.key,
    this.sendOnOpen = false,
    this.actions,
    this.onVerified,
  });
  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  late final VerificationActions _actions =
      widget.actions ?? FirebaseVerificationActions();
  bool _busy = false;
  String? _message;
  DateTime? _nextResend;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _nextResend != null) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _nextResend = await _actions.nextResendAt();
      if (!mounted) return;
      setState(() {});
      if (widget.sendOnOpen) _send();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _actions.send();
      if (mounted)
        setState(
          () => _message =
              'Verification email sent. Check your inbox and spam folder.',
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _message =
              e is FirebaseAuthException && e.code == 'too-many-requests'
              ? 'Too many requests. Please wait before trying again.'
              : 'Unable to send a verification email right now. Check your connection or try again later.',
        );
    } finally {
      final next = await _actions.nextResendAt();
      if (mounted)
        setState(() {
          _nextResend = next;
          _busy = false;
        });
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final verified = await _actions.refresh();
      if (!mounted) return;
      if (verified) {
        if (widget.onVerified != null) {
          widget.onVerified!();
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AccountGateScreen()),
            (_) => false,
          );
        }
      } else {
        setState(
          () => _message =
              'Your email is not verified yet. Open the link in your email, then check again.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _message =
              'Unable to check verification. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _nextResend == null
        ? 0
        : (_nextResend!.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil()
              .clamp(0, 60);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.mark_email_unread_outlined, size: 56),
                    const SizedBox(height: 20),
                    Text(
                      tr(context, 'Verify your email'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Open the verification link sent to ${_actions.email}. You need to verify this address before using your account.',
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_message!, semanticsLabel: _message),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _check,
                      child: Text(
                        _busy
                            ? tr(context, 'Please wait...')
                            : tr(context, "I've verified my email"),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || seconds > 0 ? null : _send,
                      child: Text(
                        seconds > 0
                            ? 'Resend in $seconds seconds'
                            : tr(context, 'Send verification email'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await UserService.clearUserData();
                              if (context.mounted)
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                  (_) => false,
                                );
                            },
                      child: Text(tr(context, 'Use another account')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
