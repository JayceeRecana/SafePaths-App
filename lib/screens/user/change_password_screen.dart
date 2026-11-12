import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final oldPass = _oldPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please fill all fields.'))),
      );
      return;
    }

    if (newPass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'New passwords do not match.'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        final cred = EmailAuthProvider.credential(
          email: user.email!,
          password: oldPass,
        );
        await user.reauthenticateWithCredential(cred);
        await user.updatePassword(newPass);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Password updated successfully.')),
          ),
        );
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? tr(context, 'Failed to update password')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Change Password'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel(tr(context, 'CURRENT PASSWORD')),
            const SizedBox(height: 8),
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppPalette.of(context).outline,
                ),
                fillColor: AppPalette.of(context).surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 20),

            _buildFieldLabel(tr(context, 'NEW PASSWORD')),
            const SizedBox(height: 8),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.lock_reset,
                  size: 18,
                  color: AppPalette.of(context).outline,
                ),
                fillColor: AppPalette.of(context).surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 20),

            _buildFieldLabel(tr(context, 'CONFIRM NEW PASSWORD')),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: AppPalette.of(context).outline,
                ),
                fillColor: AppPalette.of(context).surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: AppPalette.of(
                  context,
                ).primaryActionDecoration(radius: 16),
                child: ElevatedButton(
                  onPressed: _updatePassword,
                  style: ElevatedButton.styleFrom(
                    surfaceTintColor: Colors.transparent,
                    elevation: AppPalette.of(context).isDark ? 0 : null,
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
                          tr(context, 'Update Password'),
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
    );
  }

  Widget _buildFieldLabel(String label) {
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
