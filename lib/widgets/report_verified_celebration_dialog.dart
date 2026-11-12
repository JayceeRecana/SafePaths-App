import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_state_service.dart';
import '../screens/user/profile_screen.dart';

class ReportVerifiedCelebrationDialog extends StatelessWidget {
  final UserReport report;
  final String roadName;

  const ReportVerifiedCelebrationDialog({
    super.key,
    required this.report,
    required this.roadName,
  });

  static void showIfEligible(
    BuildContext context,
    UserReport report,
    String roadName,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          ReportVerifiedCelebrationDialog(report: report, roadName: roadName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final closureNote =
        report.adminReply ??
        'Your observation was verified. Check road details for the latest condition.';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surfaceContainerLowest,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebratory Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppPalette.of(context).secondary,
                    AppPalette.of(context).secondary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.of(
                      context,
                    ).secondary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              tr(context, 'YOUR REPORT HELPED\nTHE COMMUNITY!'),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: AppPalette.of(context).onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),

            // Road Location subtitle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.of(context).secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: AppPalette.of(context).secondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      roadName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).secondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Admin Closure Note Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppPalette.of(
                    context,
                  ).outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.forum_rounded,
                        size: 14,
                        color: AppPalette.of(context).primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tr(context, 'BARANGAY COMMAND NOTE'),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppPalette.of(context).primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '"$closureNote"',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.of(context).onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reward Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppPalette.of(context).secondary.withValues(alpha: 0.15),
                    AppPalette.of(context).secondary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppPalette.of(
                    context,
                  ).secondary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.stars_rounded,
                      color: AppPalette.of(context).onSecondary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.pointsAwarded == null
                              ? 'REPORT REVIEW COMPLETED'
                              : report.pointsAwarded! > 0
                              ? '+${report.pointsAwarded} TRUST POINTS AWARDED'
                              : 'NO ADDITIONAL TRUST POINTS AWARDED',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppPalette.of(context).secondary,
                          ),
                        ),
                        Text(
                          'Your report outcome and current road condition are shown separately.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.of(context).onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(
                        color: AppPalette.of(
                          context,
                        ).outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      tr(context, 'Dismiss'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.of(context).secondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      tr(context, 'View Profile'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.of(context).onSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
