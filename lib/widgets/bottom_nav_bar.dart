import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_state_service.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            key: const ValueKey('resident-navigation-pill'),
            color: palette.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            elevation: palette.isDark ? 0 : 3,
            shadowColor: Colors.black.withValues(alpha: .12),
            shape: StadiumBorder(
              side: BorderSide(
                color: palette.outlineVariant.withValues(alpha: .45),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.map_outlined,
                    activeIcon: Icons.map,
                    label: tr(context, 'MAP'),
                    isActive: currentIndex == 0,
                    onTap: () => onTap(0),
                    hasNotification: false,
                  ),
                  _NavItem(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore,
                    label: tr(context, 'PLANNER'),
                    isActive: currentIndex == 1,
                    onTap: () => onTap(1),
                    hasNotification: false,
                  ),
                  ListenableBuilder(
                    listenable: AppStateService.instance,
                    builder: (context, _) {
                      final unread = AppStateService.instance.unreadAlertCount;
                      return _NavItem(
                        icon: Icons.notifications_outlined,
                        activeIcon: Icons.notifications,
                        label: tr(context, 'ALERTS'),
                        isActive: currentIndex == 2,
                        onTap: () => onTap(2),
                        hasNotification: unread > 0,
                        notificationCount: unread,
                      );
                    },
                  ),
                  _NavItem(
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long,
                    label: tr(context, 'REPORTS'),
                    isActive: currentIndex == 3,
                    onTap: () => onTap(3),
                    hasNotification: false,
                  ),
                ].map((item) => Expanded(child: item)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool hasNotification;
  final int notificationCount;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.hasNotification,
    this.notificationCount = 0,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(_controller);

    if (!widget.hasNotification || widget.isActive) {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasNotification && !widget.isActive) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Semantics(
        button: true,
        selected: widget.isActive,
        label: widget.label,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppPalette.of(context).primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.isActive ? widget.activeIcon : widget.icon,
                    size: 24,
                    color: widget.isActive
                        ? AppPalette.of(context).primary
                        : AppPalette.of(context).onSurfaceVariant,
                  ),
                  if (widget.hasNotification && !widget.isActive)
                    Positioned(
                      top: -4,
                      right: widget.notificationCount > 0 ? -10 : -4,
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) => Transform.scale(
                          scale: _animation.value,
                          child: widget.notificationCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppPalette.of(context).error,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.notificationCount > 99
                                          ? '99+'
                                          : '${widget.notificationCount}',
                                      style: TextStyle(
                                        color: AppPalette.of(context).onError,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppPalette.of(context).error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: widget.isActive
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: widget.isActive
                      ? AppPalette.of(context).primary
                      : AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
