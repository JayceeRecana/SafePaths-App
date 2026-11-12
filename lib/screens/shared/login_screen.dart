import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/account_security.dart';
import 'account_gate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_service.dart';
import 'registration_screen.dart';
import 'password_recovery_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _rememberDevice = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  void _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('remembered_email');
      if (savedEmail != null && savedEmail.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = savedEmail;
          _rememberDevice = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isLoading = false;

  void _login() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please enter your email and password.')),
        ),
      );
      return;
    }

    if (!AccountSecurity.validEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Please enter a valid email address.')),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    SessionActivity.authenticationInProgress = true;

    try {
      final remaining = await AccountSecurity.remainingLoginSeconds();
      if (!mounted) return;
      if (remaining > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please wait $remaining seconds before trying again.',
            ),
          ),
        );
        return;
      }
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user != null) {
        await AccountSecurity.clearFailures();
        await UserService.setLoggedIn(true);

        try {
          final prefs = await SharedPreferences.getInstance();
          if (_rememberDevice) {
            await prefs.setString('remembered_email', email);
          } else {
            await prefs.remove('remembered_email');
          }
        } catch (_) {}

        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AccountGateScreen()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if ([
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'too-many-requests',
      ].contains(e.code)) {
        await AccountSecurity.failedLogin(
          providerLimited: e.code == 'too-many-requests',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AccountSecurity.loginError(e.code))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'Sign-in could not be completed. Please retry.'),
          ),
        ),
      );
    } finally {
      SessionActivity.authenticationInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      body: Stack(
        children: [
          SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.3),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Login card
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: AppPalette.of(
                              context,
                            ).outlineVariant.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Branding
                            Text(
                              'SafePaths',
                              style: GoogleFonts.manrope(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.0,
                                color: AppPalette.of(context).primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(context, 'Navigating Your Safety'),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Email
                            Text(
                              tr(context, 'EMAIL ADDRESS'),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: AppPalette.of(context).onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: tr(context, 'name@example.com'),
                                prefixIcon: Icon(
                                  Icons.mail_outlined,
                                  size: 18,
                                  color: AppPalette.of(context).outline,
                                ),
                                fillColor: AppPalette.of(
                                  context,
                                ).surfaceContainerLow,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Password
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  tr(context, 'PASSWORD'),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const PasswordRecoveryScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    tr(context, 'Forgot Password?'),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.of(context).primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  size: 18,
                                  color: AppPalette.of(context).outline,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? tr(context, 'Show password')
                                      : tr(context, 'Hide password'),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: AppPalette.of(context).outline,
                                  ),
                                ),
                                fillColor: AppPalette.of(
                                  context,
                                ).surfaceContainerLow,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Remember
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberDevice,
                                    onChanged: (val) {
                                      setState(() {
                                        _rememberDevice = val ?? false;
                                      });
                                    },
                                    activeColor: AppPalette.of(context).primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    side: BorderSide(
                                      color: AppPalette.of(
                                        context,
                                      ).outlineVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  tr(context, 'Remember this device'),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Login button
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: AppPalette.of(
                                  context,
                                ).primaryActionDecoration(radius: 12),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
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
                                      borderRadius: BorderRadius.circular(12),
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
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              tr(context, 'Login'),
                                              style: GoogleFonts.inter(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.arrow_forward,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Register link
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            tr(context, "Don't have an account? "),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegistrationScreen(),
                                ),
                              );
                            },
                            child: Text(
                              tr(context, 'Register'),
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
