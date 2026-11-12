import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

class ReportFollowupPrompt extends StatelessWidget {
  final VoidCallback onOpen;
  const ReportFollowupPrompt({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: p.isDark ? .10 : .045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.primary.withValues(alpha: .18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.history_rounded, size: 19, color: p.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'You reported this incident'),
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: p.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr(
                        context,
                        'Use a follow-up to update your own report. Your earlier evidence stays in the history.',
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.5,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onOpen,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              backgroundColor: p.primary.withValues(alpha: .1),
              foregroundColor: p.primary,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'View condition history'),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
