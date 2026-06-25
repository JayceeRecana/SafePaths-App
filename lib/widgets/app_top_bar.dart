import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../screens/shared/settings_screen.dart';
import '../screens/user/profile_screen.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton;
  final bool showProfile;
  final bool showSettingsAction;
  final VoidCallback? onBackPressed;
  final VoidCallback? onSettingsPressed;
  final List<Widget>? actions;

  const AppTopBar({
    super.key,
    this.title,
    this.showBackButton = false,
    this.showProfile = true,
    this.showSettingsAction = true,
    this.onBackPressed,
    this.onSettingsPressed,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AppBar(
          backgroundColor: const Color(0xFFF8FAFC).withValues(alpha: 0.7),
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Row(
            children: [
              if (showBackButton)
                GestureDetector(
                  onTap: onBackPressed ?? () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                ),
              
              if (showProfile && !showBackButton)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      color: AppColors.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppColors.onPrimaryContainer,
                      size: 18,
                    ),
                  ),
                ),
                
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title ?? 'SafePaths',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            ...?actions,
            if (!showSettingsAction)
              const SizedBox(width: 16)
            else
              Semantics(
                label: 'Settings',
                button: true,
                child: GestureDetector(
                  onTap: () {
                  if (onSettingsPressed != null) {
                    onSettingsPressed!();
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.settings_outlined,
                    color: Colors.grey.shade500,
                    size: 24,
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