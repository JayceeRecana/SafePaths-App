import '../theme/app_palette.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_strings.dart';
import '../screens/shared/settings_screen.dart';
import '../screens/user/profile_screen.dart';
import '../services/app_state_service.dart';
import 'user_avatar.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton, showProfile, showSettingsAction;
  final bool inset;
  final VoidCallback? onBackPressed, onSettingsPressed;
  final List<Widget>? actions;
  const AppTopBar({
    super.key,
    this.title,
    this.inset = false,
    this.showBackButton = false,
    this.showProfile = true,
    this.showSettingsAction = true,
    this.onBackPressed,
    this.onSettingsPressed,
    this.actions,
  });
  @override
  Size get preferredSize => Size.fromHeight(inset ? 80 : 64);
  @override
  Widget build(BuildContext context) {
    if (!inset) return _toolbar(context);
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.outlineVariant.withValues(alpha: .35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: _toolbar(context),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) => ClipRRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: AppBar(
        toolbarHeight: inset ? 60 : 64,
        backgroundColor: inset
            ? AppPalette.of(context).surfaceContainerLowest
            : AppPalette.of(context).surface.withValues(alpha: 0.94),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: inset
            ? 2
            : showBackButton || showProfile
            ? 8
            : 20,
        leadingWidth: showProfile && !showBackButton ? (inset ? 60 : 68) : null,
        actionsPadding: EdgeInsetsDirectional.only(end: inset ? 6 : 12),
        leading: showBackButton
            ? IconButton(
                tooltip: tr(context, 'Back'),
                icon: const Icon(Icons.arrow_back),
                onPressed:
                    onBackPressed ??
                    () {
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    },
              )
            : showProfile
            ? Padding(
                padding: EdgeInsetsDirectional.only(start: inset ? 4 : 12),
                child: ListenableBuilder(
                  listenable: AppStateService.instance,
                  builder: (context, _) {
                    final uid = Firebase.apps.isEmpty
                        ? null
                        : FirebaseAuth.instance.currentUser?.uid;
                    final users = AppStateService.instance.users.where(
                      (user) => user.id == uid,
                    );
                    final user = users.isEmpty ? null : users.first;
                    return IconButton(
                      tooltip: tr(context, 'Profile'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      icon: UserAvatar(
                        photoUrl: user?.photoUrl,
                        size: inset ? 32 : 36,
                        iconSize: 18,
                      ),
                    );
                  },
                ),
              )
            : null,
        title: Text(
          title == null ? 'SafePaths' : tr(context, title!),
          style: GoogleFonts.manrope(
            fontSize: inset ? 18 : 20,
            fontWeight: FontWeight.w800,
            color: AppPalette.of(context).primary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ...?actions,
          if (showSettingsAction)
            IconButton(
              tooltip: tr(context, 'Settings'),
              icon: Icon(Icons.settings_outlined, size: inset ? 21 : 24),
              style: inset
                  ? IconButton.styleFrom(
                      foregroundColor: AppPalette.of(context).onSurfaceVariant,
                      backgroundColor: AppPalette.of(
                        context,
                      ).surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size(48, 48),
                    )
                  : null,
              onPressed:
                  onSettingsPressed ??
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
            ),
        ],
      ),
    ),
  );
}
