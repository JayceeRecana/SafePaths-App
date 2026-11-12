import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';

/// The same rounded surface, heading and icon treatment as Settings actions.
class SettingsPreferenceCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const SettingsPreferenceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: p.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DefaultTextStyle.merge(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: p.onSurfaceVariant,
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
