import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/password_policy.dart';
import '../../services/account_security.dart';
import '../../services/user_service.dart';
import 'login_screen.dart';
import 'account_gate_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  bool _agreedToTerms = false;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;

  void _register() async {
    if (_isLoading) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please complete all required fields.')),
        ),
      );
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please enter a valid email address.')),
        ),
      );
      return;
    }

    if (!PasswordPolicy.isValid(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PasswordPolicy.requirements)),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Passwords do not match.'))),
      );
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please agree to the terms to continue.')),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    SessionActivity.authenticationInProgress = true;

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'name': name,
                'email': email,
                'role': 'user',
                'trustScore': 50,
                'verifiedReports': 0,
                'dismissedReports': 0,
                'createdAt': FieldValue.serverTimestamp(),
              })
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          /* Profile setup is retried after email verification. */
        }

        await UserService.saveUserRole(UserRole.user);
        await UserService.setLoggedIn(true);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Account created. Please verify your email to continue.',
              ),
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                const AccountGateScreen(sendVerificationOnOpen: true),
          ),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? tr(context, 'Registration failed.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Account setup could not be completed. If your account was created, sign in to finish setup.',
            ),
          ),
        ),
      );
    } finally {
      SessionActivity.authenticationInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Registration card
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 480),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mobile branding
                        Text(
                          'SafePaths',
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppPalette.of(context).primary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        Text(
                          tr(context, 'Create Account'),
                          style: GoogleFonts.manrope(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: AppPalette.of(context).onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            context,
                            'Complete the details below to register.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: AppPalette.of(context).onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Full Name
                        _FieldLabel(label: tr(context, 'FULL NAME')),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: tr(context, 'Johnathan Doe'),
                            prefixIcon: Icon(
                              Icons.person_outlined,
                              size: 18,
                              color: AppPalette.of(context).outline,
                            ),
                            fillColor: AppPalette.of(
                              context,
                            ).surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Email
                        _FieldLabel(label: tr(context, 'EMAIL ADDRESS')),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: tr(context, 'john@example.com'),
                            prefixIcon: Icon(
                              Icons.mail_outlined,
                              size: 18,
                              color: AppPalette.of(context).outline,
                            ),
                            fillColor: AppPalette.of(
                              context,
                            ).surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 20),

                        _FieldLabel(label: tr(context, 'PASSWORD')),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: tr(context, 'Enter a password'),
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? tr(context, 'Show password')
                                  : tr(context, 'Hide password'),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                            ),
                            fillColor: AppPalette.of(
                              context,
                            ).surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value:
                              PasswordPolicy.score(_passwordController.text) /
                              5,
                          color:
                              PasswordPolicy.isValid(_passwordController.text)
                              ? AppPalette.of(context).secondary
                              : AppPalette.of(context).primary,
                          backgroundColor: AppPalette.of(
                            context,
                          ).surfaceContainerHigh,
                          semanticsLabel: 'Password requirements met',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          PasswordPolicy.requirements,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppPalette.of(context).onSurfaceVariant,
                          ),
                        ),
                        if (_passwordController.text.isNotEmpty)
                          Text(
                            'Requirements met: ${PasswordPolicy.score(_passwordController.text)}/5',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 20),
                        _FieldLabel(label: tr(context, 'CONFIRM PASSWORD')),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _hideConfirmation,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: tr(context, 'Re-enter your password'),
                            errorText:
                                _confirmPasswordController.text.isNotEmpty &&
                                    _confirmPasswordController.text !=
                                        _passwordController.text
                                ? tr(context, 'Passwords do not match.')
                                : null,
                            prefixIcon: const Icon(Icons.verified_outlined),
                            suffixIcon: IconButton(
                              tooltip: _hideConfirmation
                                  ? tr(context, 'Show confirmation password')
                                  : tr(context, 'Hide confirmation password'),
                              icon: Icon(
                                _hideConfirmation
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _hideConfirmation = !_hideConfirmation,
                              ),
                            ),
                            fillColor: AppPalette.of(
                              context,
                            ).surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Terms
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _agreedToTerms,
                                onChanged: (val) {
                                  setState(() {
                                    _agreedToTerms = val ?? false;
                                  });
                                },
                                activeColor: AppPalette.of(context).primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                side: BorderSide(
                                  color: AppPalette.of(context).outlineVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: tr(context, 'I agree to the '),
                                    ),
                                    TextSpan(
                                      text: tr(context, 'Terms of Service'),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppPalette.of(context).primary,
                                      ),
                                    ),
                                    TextSpan(text: tr(context, ' and ')),
                                    TextSpan(
                                      text: tr(context, 'Privacy Policy'),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppPalette.of(context).primary,
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Register button
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            decoration: AppPalette.of(
                              context,
                            ).primaryActionDecoration(radius: 16),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                surfaceTintColor: Colors.transparent,
                                elevation: AppPalette.of(context).isDark
                                    ? 0
                                    : null,
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
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
                                      tr(context, 'Register'),
                                      style: GoogleFonts.manrope(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Login link
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    Text(
                      tr(context, 'Already have an account? '),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: Text(
                        tr(context, 'Login'),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.of(context).primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          color: AppPalette.of(context).onSurfaceVariant,
        ),
      ),
    );
  }
}
