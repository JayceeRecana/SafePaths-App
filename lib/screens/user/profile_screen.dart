import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../shared/login_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'report_history_screen.dart';
import '../../services/app_state_service.dart';
import '../../services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Account',
        showBackButton: true,
        showProfile: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppColors.surface,
      body: AnimatedBuilder(
        animation: AppStateService.instance,
        builder: (context, child) {
          final appState = AppStateService.instance;
          final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
          final user = appState.users.firstWhere(
            (u) => u.id == currentUserId,
            orElse: () => UserProfile(
              id: currentUserId,
              trustScore: 50,
            ),
          );

          int trustLevel = 1;
          if (user.trustScore >= 80) {
            trustLevel = 5;
          } else if (user.trustScore >= 60) trustLevel = 4;
          else if (user.trustScore >= 40) trustLevel = 3;
          else if (user.trustScore >= 20) trustLevel = 2;

          int nextLevelScore = (trustLevel * 20);
          int currentLevelBase = ((trustLevel - 1) * 20);
          double progress = trustLevel == 5 
              ? 1.0 
              : (user.trustScore - currentLevelBase) / 20.0;
          
          Color levelColor = AppColors.primary;
          if (trustLevel >= 4) {
            levelColor = AppColors.secondary;
          } else if (trustLevel <= 2) levelColor = AppColors.tertiary;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Avatar & Name
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryContainer,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, size: 48, color: AppColors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.name,
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        '${user.role.isNotEmpty ? user.role[0].toUpperCase() + user.role.substring(1) : 'User'} • ${user.location}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Gamification / Reputation Card
                if (user.role != 'admin')
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: levelColor.withValues(alpha: 0.3)),
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
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Reputation Score: ${user.trustScore}',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (trustLevel == 5)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                'MAX LEVEL',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.secondary,
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
                          backgroundColor: AppColors.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            trustLevel == 5 ? 'Highest rank achieved!' : '${nextLevelScore - user.trustScore} pts to Level ${trustLevel + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            trustLevel == 5 ? '' : '$nextLevelScore',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (user.role != 'admin')
                  const SizedBox(height: 32),

            // Settings List
            _ProfileMenuItem(
              icon: Icons.edit, 
              title: 'Edit Personal Details', 
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)),
                );
              }
            ),
            _ProfileMenuItem(
              icon: Icons.lock_outline, 
              title: 'Change Password', 
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                );
              }
            ),
            if (user.role != 'admin')
              _ProfileMenuItem(
                icon: Icons.history, 
                title: 'My Report History', 
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportHistoryScreen()),
                  );
                }
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
                icon: const Icon(Icons.logout, color: AppColors.error),
                label: Text(
                  'Log Out',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  const _ProfileMenuItem({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.onSurface, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
      onTap: onTap,
    );
  }
}