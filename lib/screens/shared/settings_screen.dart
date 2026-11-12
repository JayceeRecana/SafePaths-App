import '../../widgets/settings_preference_card.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_preferences.dart';
import '../../widgets/notification_status_card.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/user_service.dart';
import 'login_screen.dart';
import 'feedback_screen.dart';
import 'emergency_hotlines_screen.dart';
import '../admin/admin_feedback_screen.dart';
import '../admin/admin_home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final role = await UserService.getUserRole();
    if (mounted) {
      setState(() {
        _isAdmin = role == UserRole.admin;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Settings'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'APP PREFERENCES'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppPalette.of(context).primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'Safety & Notification Controls'),
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppPalette.of(context).onSurface,
              ),
            ),
            const SizedBox(height: 20),
            const NotificationStatusCard(settingsStyle: true),
            const SizedBox(height: 12),
            _SettingsActionCard(
              title: tr(context, 'Emergency hotlines'),
              subtitle: tr(
                context,
                'Valenzuela City disaster, fire, police and hospital contacts.',
              ),
              icon: Icons.call_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EmergencyHotlinesScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: AppPalette.of(context).surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  tr(
                    context,
                    'Saved road conditions are available only after they have loaded online and while they remain on this phone. Map tiles may be missing. New routes and report submission require internet. Saved information may be outdated.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SettingsPreferenceCard(
              title: tr(context, 'App language'),
              icon: Icons.language_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: AppPreferences.instance.locale.languageCode,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Language'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(tr(context, 'English')),
                      ),
                      DropdownMenuItem(
                        value: 'fil',
                        child: Text(tr(context, 'Filipino')),
                      ),
                    ],
                    onChanged: (language) async {
                      if (language == null) return;
                      final saved = await AppPreferences.instance.setLanguage(
                        language,
                      );
                      if (!saved && context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                context,
                                'Language changed for now. It could not be saved on this phone.',
                              ),
                            ),
                          ),
                        );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsPreferenceCard(
              title: tr(context, 'Appearance'),
              icon: Icons.palette_outlined,
              child: Semantics(
                label: tr(context, 'Appearance'),
                child: DropdownButtonFormField<ThemeMode>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: AppPreferences.instance.themeMode,
                  decoration: const InputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(tr(context, 'Use phone theme')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(tr(context, 'Light')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(tr(context, 'Dark')),
                    ),
                  ],
                  onChanged: (mode) async {
                    if (mode == null) return;
                    final saved = await AppPreferences.instance.setThemeMode(
                      mode,
                    );
                    if (!saved && context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              context,
                              'Appearance changed for now. It could not be saved on this phone.',
                            ),
                          ),
                        ),
                      );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, 'COMMUNITY'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppPalette.of(context).primary,
              ),
            ),
            const SizedBox(height: 16),
            _SettingsActionCard(
              title: tr(context, 'Feedback & Suggestions'),
              subtitle: tr(context, 'Help us improve SafePaths for Marulas.'),
              icon: Icons.rate_review_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                );
              },
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 24),
              Text(
                tr(context, 'ADMINISTRATION'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppPalette.of(context).primary,
                ),
              ),
              const SizedBox(height: 16),
              _SettingsActionCard(
                title: tr(context, 'Return to Admin Console'),
                subtitle: tr(
                  context,
                  'Manage roads, broadcast alerts, and user reports.',
                ),
                icon: Icons.admin_panel_settings_rounded,
                onTap: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                tr(context, 'CAPSTONE TOOLS'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppPalette.of(context).error,
                ),
              ),
              const SizedBox(height: 16),
              _SettingsActionCard(
                title: tr(context, 'Review Community Feedback'),
                subtitle: tr(
                  context,
                  'Manage feedback for Chapter 4 data collection.',
                ),
                icon: Icons.school_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminFeedbackScreen(),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 24),

            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppPalette.of(context).error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppPalette.of(context).error.withValues(alpha: 0.3),
                ),
              ),
              child: ElevatedButton(
                onPressed: () async {
                  await UserService.clearUserData();
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  tr(context, 'Logout'),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.of(context).error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppPalette.of(context).surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppPalette.of(context).primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AppPalette.of(context).primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppPalette.of(context).onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: AppPalette.of(context).outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
