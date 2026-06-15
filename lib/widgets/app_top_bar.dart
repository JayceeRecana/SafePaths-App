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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC).withValues(alpha: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Only show the back button when there is actually a route to go back to.
              // Screens used as tabs in an IndexedStack have showBackButton: true but
              // Navigator.canPop() is false — showing the button there would let users
              // pop the root route and land on a black screen.
              if (showBackButton && Navigator.of(context).canPop())
                GestureDetector(
                  onTap: onBackPressed ?? () => Navigator.of(context).pop(),
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
              
              // 2. Wrap the Profile Icon in a GestureDetector for navigation
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
                  title ?? 'SafePaths', // Updated default title to match project
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (actions != null)
                ...actions!
              else if (!showSettingsAction)
                const SizedBox(width: 40, height: 40)
              else
                GestureDetector(
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
            ],
          ),
        ),
      ),
    );
  }
}