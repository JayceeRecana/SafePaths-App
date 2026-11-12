import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'dart:async';
import '../l10n/formatters.dart';
import 'package:flutter/material.dart';
import '../models/user_report.dart';
import '../utils/report_freshness.dart';

class ReportFreshnessSummary extends StatefulWidget {
  final UserReport report;
  final DateTime Function()? clock;
  const ReportFreshnessSummary({super.key, required this.report, this.clock});
  @override
  State<ReportFreshnessSummary> createState() => _ReportFreshnessSummaryState();
}

class _ReportFreshnessSummaryState extends State<ReportFreshnessSummary> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report, now = widget.clock?.call() ?? DateTime.now();
    final old = ReportFreshness.isOutdated(report, now);
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 13,
              color: palette.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${tr(context, 'Reported')} ${localizedAge(context, report.createdAt, now)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 13,
              color: palette.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${tr(context, report.observedAt == null ? 'Latest report update' : 'Observed (reporter supplied)')} ${localizedAge(context, ReportFreshness.observedAt(report), now)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (old) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(
                alpha: palette.isDark ? 0.15 : 0.6,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 5),
                Text(
                  tr(context, 'Outdated — current condition unknown'),
                  style: GoogleFonts.inter(
                    color: palette.isDark
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
