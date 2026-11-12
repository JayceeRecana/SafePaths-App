import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../shared/login_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'report_history_screen.dart';
import '../admin/admin_home_screen.dart';
import '../../services/app_state_service.dart';
import '../../services/user_service.dart';
import '../../widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Account'),
        showBackButton: true,
        showProfile: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: AnimatedBuilder(
        animation: AppStateService.instance,
        builder: (context, child) {
          final appState = AppStateService.instance;
          final currentUserId =
              FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
          final user = appState.users.firstWhere(
            (u) => u.id == currentUserId,
            orElse: () => UserProfile(id: currentUserId, trustScore: 50),
          );

          int trustLevel = UserProfile.getTrustLevel(user.trustScore);

          int nextLevelScore = (trustLevel * 20);
          int currentLevelBase = ((trustLevel - 1) * 20);
          double progress = trustLevel == 5
              ? 1.0
              : (user.trustScore - currentLevelBase) / 20.0;

          Color levelColor = AppPalette.of(context).primary;
          if (trustLevel >= 4) {
            levelColor = AppPalette.of(context).secondary;
          } else if (trustLevel <= 2)
            levelColor = AppPalette.of(context).tertiary;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Avatar & Name
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditProfileScreen(user: user),
                            ),
                          );
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppPalette.of(context).primaryContainer,
                                border: Border.all(
                                  color: AppPalette.of(
                                    context,
                                  ).onPrimaryContainer,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: UserAvatar(
                                photoUrl: user.photoUrl,
                                size: 96,
                                iconSize: 48,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppPalette.of(context).primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppPalette.of(context).onPrimary,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppPalette.of(
                                        context,
                                      ).primary.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 14,
                                  color: AppPalette.of(context).onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.name,
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.of(context).onSurface,
                        ),
                      ),
                      Text(
                        '${user.role.isNotEmpty ? user.role[0].toUpperCase() + user.role.substring(1) : 'User'} • ${user.location}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppPalette.of(context).onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Admin Switcher Card
                if (user.role == 'admin')
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppPalette.of(
                        context,
                      ).primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppPalette.of(
                          context,
                        ).primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            color: AppPalette.of(context).onPrimary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(context, 'System Administrator'),
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.of(context).onSurface,
                                ),
                              ),
                              Text(
                                tr(
                                  context,
                                  'Access administrative controls & tools',
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppPalette.of(
                                    context,
                                  ).onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const AdminHomeScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.of(context).primary,
                            foregroundColor: AppPalette.of(context).onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            tr(context, 'Console'),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Gamification / Reputation Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: levelColor.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: levelColor.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield, color: levelColor, size: 28),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Trust Level $trustLevel',
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppPalette.of(context).onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Reputation Score: ${user.trustScore}',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.of(
                                        context,
                                      ).onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (trustLevel == 5)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppPalette.of(
                                  context,
                                ).secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                tr(context, 'MAX LEVEL'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.of(context).secondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: AppPalette.of(
                            context,
                          ).surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            trustLevel == 5
                                ? tr(context, 'Highest rank achieved!')
                                : '${nextLevelScore - user.trustScore} pts to Level ${trustLevel + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          Text(
                            trustLevel == 5 ? '' : '$nextLevelScore',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                '${user.verifiedReports}',
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.of(context).secondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr(context, 'Verified (+10 pts)'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppPalette.of(
                                    context,
                                  ).onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: AppPalette.of(
                              context,
                            ).outlineVariant.withValues(alpha: 0.3),
                          ),
                          Column(
                            children: [
                              Text(
                                '${user.dismissedReports}',
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: user.dismissedReports > 0
                                      ? AppPalette.of(context).error
                                      : AppPalette.of(context).onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr(context, 'Dismissed / Spam'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppPalette.of(
                                    context,
                                  ).onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Settings List
                _ProfileMenuItem(
                  icon: Icons.edit,
                  title: tr(context, 'Edit Personal Details'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(user: user),
                      ),
                    );
                  },
                ),
                _ProfileMenuItem(
                  icon: Icons.lock_outline,
                  title: tr(context, 'Change Password'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                _ProfileMenuItem(
                  icon: Icons.history,
                  title: tr(context, 'My Report History'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReportHistoryScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await UserService.clearUserData();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: Icon(
                      Icons.logout,
                      color: AppPalette.of(context).error,
                    ),
                    label: Text(
                      tr(context, 'Log Out'),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppPalette.of(context).error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppPalette.of(context).onSurface, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppPalette.of(context).onSurface,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppPalette.of(context).outline,
      ),
      onTap: onTap,
    );
  }
}
