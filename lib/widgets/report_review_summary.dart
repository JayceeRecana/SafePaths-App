import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import 'package:flutter/material.dart';
import '../models/user_report.dart';
import '../models/road_status.dart';
import '../services/admin_report_service.dart';

class ReportReviewSummary extends StatelessWidget {
  final UserReport report;
  final RoadStatus? road;
  final bool compact;
  const ReportReviewSummary({
    super.key,
    required this.report,
    this.road,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isVerified = report.status == 'verified';
    final isResolved = report.status == 'resolved';
    final isDismissed = report.status == 'dismissed';
    final needsCorrection =
        isDismissed && report.dismissReason == 'needs_correction';
    final reviewCorrected = report.rewardCorrection != null;

    final reviewColor = isVerified
        ? palette.secondary
        : (isResolved
              ? palette.primary
              : (isDismissed && !needsCorrection && !reviewCorrected
                    ? palette.error
                    : palette.primary));

    if (compact) return _compact(context, reviewColor);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: reviewColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: reviewColor.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: reviewColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVerified
                      ? Icons.check_circle_rounded
                      : (isResolved
                            ? Icons.task_alt_rounded
                            : (isDismissed
                                  ? Icons.cancel_outlined
                                  : Icons.pending_actions_rounded)),
                  size: 14,
                  color: reviewColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${compact ? '' : '${tr(context, 'Report review')}: '}${tr(context, reviewCorrected
                      ? 'Follow-up review corrected'
                      : needsCorrection
                      ? 'Needs correction'
                      : switch (report.status) {
                          'waiting_resident' => 'Waiting for your clarification',
                          'pending' => compact ? 'Awaiting admin review' : 'Received',
                          'under_review' => 'Under review',
                          'verified' => 'Observation verified',
                          'resolved' => 'Incident reviewed',
                          'dismissed' when report.dismissReason == 'unable_to_verify' => 'Unable to verify',
                          'dismissed' => 'Dismissed',
                          'expired' => 'Outdated',
                          _ => 'Unknown',
                        })}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: reviewColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (compact && report.reviewedAt != null) ...[
            Text(
              '${tr(context, 'Reviewed')}: ${localizedDateTime(context, report.reviewedAt!)}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (!compact ||
              needsCorrection ||
              reviewCorrected ||
              isDismissed ||
              report.isHistoricalFollowup)
            Text(
              tr(
                context,
                reviewCorrected
                    ? 'The follow-up review was corrected. Earlier report outcomes remain separate. See condition history for the original award and adjustment.'
                    : needsCorrection
                    ? 'The admin requested clearer or corrected evidence. Add a new dated follow-up; earlier submissions remain in the history. No trust points were deducted.'
                    : report.isHistoricalFollowup && report.reviewOpen
                    ? 'The road was reviewed separately. This observation still awaits its own review.'
                    : report.status == 'verified'
                    ? 'The observation was verified. Check the road condition separately before travel.'
                    : 'Private messages are updates. The report review and road condition are recorded separately.',
              ),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: palette.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(compact ? 0 : 10),
            decoration: BoxDecoration(
              color: compact
                  ? Colors.transparent
                  : palette.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: compact
                  ? null
                  : Border.all(
                      color: palette.outlineVariant.withValues(alpha: 0.25),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.traffic_rounded,
                      size: 14,
                      color: palette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${tr(context, 'Last recorded road condition')}: ${tr(context, roadConditionLabel(road?.status))}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: compact && road?.status == 'not_passable'
                              ? palette.error
                              : palette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (road != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.update_rounded,
                        size: 14,
                        color: palette.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${tr(context, 'Road updated')}: ${localizedAge(context, road!.updatedAt, DateTime.now())}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (report.incidentReviewStatus != null &&
                    (!compact ||
                        report.incidentReviewStatus != road?.status)) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.fact_check_outlined,
                        size: 14,
                        color: palette.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${tr(context, 'Road condition at this review')}: ${tr(context, roadConditionLabel(report.incidentReviewStatus))}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (reviewCorrected) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${tr(context, 'Bonus reversal')}: -${report.rewardCorrection!['reversed'] ?? 0}. ${tr(context, 'False-submission penalty')}: -${report.rewardCorrection!['penalty'] ?? 0}.',
                  ),
                ],
                if (report.pointsAwarded != null && !reviewCorrected) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.stars_rounded,
                        size: 14,
                        color: (report.pointsAwarded ?? 0) > 0
                            ? palette.secondary
                            : palette.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          report.pointsAwarded == 0
                              ? tr(
                                  context,
                                  'No trust points awarded for this review.',
                                )
                              : '${tr(context, 'Trust change for this review')}: ${report.pointsAwarded! > 0 ? '+' : ''}${report.pointsAwarded}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: (report.pointsAwarded ?? 0) > 0
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: (report.pointsAwarded ?? 0) > 0
                                ? palette.secondary
                                : palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compact(BuildContext context, Color color) {
    final p = AppPalette.of(context);
    final corrected = report.rewardCorrection != null;
    final correction =
        report.status == 'dismissed' &&
        report.dismissReason == 'needs_correction';
    final title = tr(
      context,
      corrected
          ? 'Follow-up review corrected'
          : correction
          ? 'Needs correction'
          : switch (report.status) {
              'waiting_resident' => 'Waiting for your clarification',
              'pending' => 'Awaiting admin review',
              'under_review' => 'Under review',
              'verified' => 'Observation verified',
              'resolved' => 'Incident reviewed',
              'dismissed' when report.dismissReason == 'unable_to_verify' =>
                'Unable to verify',
              'dismissed' => 'Dismissed',
              'expired' => 'Outdated',
              _ => 'Unknown',
            },
    );
    final explanation = corrected
        ? 'The follow-up review was corrected. Earlier report outcomes remain separate. See condition history for the original award and adjustment.'
        : correction
        ? 'The admin requested clearer or corrected evidence. Add a new dated follow-up; earlier submissions remain in the history. No trust points were deducted.'
        : report.isHistoricalFollowup && report.reviewOpen
        ? 'The road was reviewed separately. This observation still awaits its own review.'
        : report.status == 'dismissed'
        ? 'Private messages are updates. The report review and road condition are recorded separately.'
        : null;
    Widget pill(String text, {Color? foreground, String? tooltip}) {
      final item = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: p.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: foreground ?? p.onSurface,
          ),
        ),
      );
      return tooltip == null ? item : Tooltip(message: tooltip, child: item);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: .08),
          p.surfaceContainerLowest,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                report.status == 'verified'
                    ? Icons.check_circle_outline
                    : correction
                    ? Icons.edit_note_outlined
                    : report.status == 'dismissed'
                    ? Icons.cancel_outlined
                    : Icons.fact_check_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (report.reviewedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${tr(context, 'Reviewed')}: ${localizedDateTime(context, report.reviewedAt!)}',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.4,
                  color: p.onSurfaceVariant,
                ),
              ),
            ),
          if (explanation != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(context, explanation),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: p.onSurfaceVariant,
                ),
              ),
            ),
          if (report.pointsAwarded != null && !corrected || road != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (report.pointsAwarded != null && !corrected)
                  pill(
                    report.pointsAwarded == 0
                        ? tr(
                            context,
                            'No trust points awarded for this review.',
                          )
                        : '${report.pointsAwarded! > 0 ? '+' : ''}${report.pointsAwarded} ${tr(context, 'trust')}',
                    foreground: report.pointsAwarded! > 0
                        ? p.passable
                        : p.onSurfaceVariant,
                    tooltip:
                        '${tr(context, 'Trust change for this review')}: ${report.pointsAwarded! > 0 ? '+' : ''}${report.pointsAwarded}',
                  ),
                if (road != null)
                  pill(
                    '${tr(context, 'Recorded condition')}: ${tr(context, roadConditionLabel(road!.status))}',
                    tooltip:
                        '${tr(context, 'Last recorded road condition')}: ${tr(context, roadConditionLabel(road!.status))}',
                    foreground: road!.status == 'not_passable'
                        ? p.notPassable
                        : p.onSurface,
                  ),
              ],
            ),
          ],
          if (road != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${tr(context, 'Road updated')}: ${localizedAge(context, road!.updatedAt, DateTime.now())}',
                style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
              ),
            ),
          if (report.incidentReviewStatus != null &&
              report.incidentReviewStatus != road?.status)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${tr(context, 'Road condition at this review')}: ${tr(context, roadConditionLabel(report.incidentReviewStatus))}',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: p.onSurfaceVariant,
                ),
              ),
            ),
          if (corrected)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                '${tr(context, 'Bonus reversal')}: -${report.rewardCorrection!['reversed'] ?? 0}. ${tr(context, 'False-submission penalty')}: -${report.rewardCorrection!['penalty'] ?? 0}.',
                style: TextStyle(fontSize: 11, height: 1.4, color: p.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
