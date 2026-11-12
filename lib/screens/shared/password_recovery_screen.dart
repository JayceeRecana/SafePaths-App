import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/account_security.dart';
import '../../widgets/app_top_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Recover Password'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'ACCOUNT ACCESS'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppPalette.of(context).primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'Reset Your Password'),
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppPalette.of(context).onSurface,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      context,
                      'Enter your registered email. We will send reset instructions.',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppPalette.of(context).onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: tr(context, 'name@example.com'),
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              decoration: AppPalette.of(
                context,
              ).primaryActionDecoration(radius: 16, shadow: false),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendRecovery,
                style: ElevatedButton.styleFrom(
                  surfaceTintColor: Colors.transparent,
                  elevation: AppPalette.of(context).isDark ? 0 : null,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        tr(context, 'Send Recovery Link'),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendRecovery() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    if (!AccountSecurity.validEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please enter a valid email address.')),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      _recoverySent();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        _recoverySent();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'too-many-requests'
                  ? tr(
                      context,
                      'Too many requests. Please wait before trying again.',
                    )
                  : tr(
                      context,
                      'Unable to send instructions right now. Check your connection and retry.',
                    ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Unable to connect. Please retry.')),
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recoverySent() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AccountSecurity.recoveryMessage)),
    );
    Navigator.of(context).pop();
  }
}
