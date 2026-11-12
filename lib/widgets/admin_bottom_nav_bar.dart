import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_state_service.dart';

class AdminBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdminBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.of(
          context,
        ).surfaceContainerLowest.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: ListenableBuilder(
            listenable: AppStateService.instance,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: tr(context, 'DASHBOARD'),
                    isActive: currentIndex == 0,
                    onTap: () => onTap(0),
                    hasNotification: false,
                  ),
                  _NavItem(
                    icon: Icons.route_outlined,
                    activeIcon: Icons.route,
                    label: tr(context, 'ROADS'),
                    isActive: currentIndex == 1,
                    onTap: () => onTap(1),
                    hasNotification: false,
                  ),
                  _NavItem(
                    icon: Icons.notifications_outlined,
                    activeIcon: Icons.notifications,
                    label: tr(context, 'ALERTS'),
                    isActive: currentIndex == 2,
                    onTap: () {
                      AppStateService.instance.markAlertsSeen();
                      onTap(2);
                    },
                    hasNotification:
                        AppStateService.instance.unreadAlertCount > 0,
                  ),
                  _NavItem(
                    icon: Icons.description_outlined,
                    activeIcon: Icons.description,
                    label: tr(context, 'REPORTS'),
                    isActive: currentIndex == 3,
                    onTap: () => onTap(3),
                    hasNotification: AppStateService.instance.reports.any(
                      (r) => r.status == 'pending',
                    ),
                  ),
                ].map((item) => Expanded(child: item)).toList(),
              );
            },
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

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.hasNotification,
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
          transform: widget.isActive
              ? (Matrix4.identity()..scale(1.05))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppPalette.of(context).primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
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
                      top: -2,
                      right: -4,
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) => Transform.scale(
                          scale: _animation.value,
                          child: Container(
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
