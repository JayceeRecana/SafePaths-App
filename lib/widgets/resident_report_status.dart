import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';

/// A report decision never describes the current condition of its road.
String residentReportStatus(UserReport report) {
  if (report.rewardCorrection != null) return 'Review corrected';
  return switch (report.status) {
    'waiting_resident' => 'Needs your reply',
    'pending' when report.clarificationRepliedAt != null => 'Reply sent',
    'pending' => 'Sent',
    'under_review' => 'Being checked',
    'verified' => 'Verified',
    'resolved' => 'Reviewed',
    'dismissed' when report.dismissReason == 'needs_correction' =>
      'Needs correction',
    'dismissed' => 'Not verified',
    'expired' => 'Outdated',
    _ => 'Status unavailable',
  };
}

class ResidentReportStatusBadge extends StatelessWidget {
  final UserReport report;
  const ResidentReportStatusBadge({super.key, required this.report});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final waiting = report.awaitsResident;
    final verified =
        report.rewardCorrection == null &&
        (report.status == 'verified' ||
            report.status == 'pending' &&
                report.clarificationRepliedAt != null);
    final color = waiting
        ? p.onWarningContainer
        : verified
        ? p.passable
        : p.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: waiting ? p.warningContainer : color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            waiting
                ? Icons.question_answer_outlined
                : verified
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tr(context, residentReportStatus(report)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
