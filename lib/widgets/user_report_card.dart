import 'report_workflow_ui.dart';
import '../utils/time_utils.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import 'report_submission_preview.dart';
import 'safe_image.dart';

/// A report inbox summary. Evidence, road decisions and trust details live in
/// the inspector. Colours describe the report outcome, not road passability.
class UserReportCard extends StatefulWidget {
  final UserReport report;
  final RoadStatus? road;
  final String? reporterName;
  final bool selected, busy, roadNeedsAttention, showSubmissionClock;
  final VoidCallback? onTap;
  final DateTime Function()? now;
  const UserReportCard({
    super.key,
    required this.report,
    this.road,
    this.reporterName,
    this.selected = false,
    this.busy = false,
    this.roadNeedsAttention = false,
    this.showSubmissionClock = false,
    this.onTap,
    this.now,
  });
  @override
  State<UserReportCard> createState() => _UserReportCardState();
}

class _UserReportCardState extends State<UserReportCard> {
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
    final p = AppPalette.of(context), report = widget.report;
    final now = (widget.now ?? DateTime.now)();
    final pending = report.reviewOpen;
    final corrected = report.rewardCorrection != null;
    final correction =
        report.status == 'dismissed' &&
        report.dismissReason == 'needs_correction';
    final colour =
        pending || corrected || correction || report.status == 'expired'
        ? p.warning
        : report.status == 'verified'
        ? p.passable
        : report.dismissReason == 'spam_false'
        ? p.error
        : p.onSurfaceVariant;
    final statusIcon = pending
        ? Icons.pending_actions_outlined
        : corrected || correction
        ? Icons.edit_note
        : report.status == 'verified'
        ? Icons.check_circle_outline
        : report.status == 'dismissed'
        ? Icons.cancel_outlined
        : Icons.history;
    final name = reportRoadName(report, road: widget.road);
    final hasPhoto = report.imageUrl?.trim().isNotEmpty == true;
    final hasMessages =
        report.hasAdminUpdates ||
        report.adminReplies.isNotEmpty ||
        report.adminReply?.trim().isNotEmpty == true;
    final hasSubmission = TimeUtils.hasRecordedTime(report.createdAt);
    final observed = TimeUtils.hasRecordedTime(report.observedAt)
        ? report.observedAt
        : null;
    final submittedLater =
        observed != null &&
        hasSubmission &&
        report.createdAt.difference(observed).inMilliseconds.abs() >= 60000;
    final sameMinute = hasSubmission && reportTimesShareMinute(report);
    final oldPhoto =
        hasPhoto &&
        TimeUtils.hasRecordedTime(report.photoSubmittedAt) &&
        ReportFreshness.observedAt(
              report,
            ).difference(report.photoSubmittedAt!) >=
            const Duration(minutes: 1);
    final canOpen = !widget.busy && widget.onTap != null;
    final largeText = MediaQuery.textScalerOf(context).scale(11) > 15.5;
    final showObservationDetail =
        observed != null &&
        (widget.showSubmissionClock
            ? !sameMinute
            : submittedLater || !hasSubmission);
    final timeText = !hasSubmission
        ? tr(context, 'Submission time not recorded')
        : widget.showSubmissionClock
        ? '${tr(context, sameMinute ? 'Observed and submitted' : 'Submitted')}: ${localizedClock(context, report.createdAt)}'
        : '${tr(context, observed != null && !submittedLater ? 'Observed' : 'Submitted')}: ${localizedAge(context, observed != null && !submittedLater ? observed : report.createdAt, now)}';
    final badge = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 14, color: colour),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  tr(context, reportReviewLabel(report)),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (report.isFollowup)
          Text(
            tr(context, 'Follow-up'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: p.primary,
            ),
          ),
      ],
    );
    Widget notice(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color ?? p.onSurfaceVariant),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: color ?? p.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
    return Material(
      color: p.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: widget.selected
              ? p.primary
              : p.outlineVariant.withValues(alpha: .4),
          width: widget.selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen ? widget.onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              badge,
              if (report.isEmergency)
                notice(
                  Icons.sos,
                  tr(context, 'Urgent assistance requested'),
                  color: p.error,
                ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Tooltip(
                          message: name == 'Unnamed residential road'
                              ? tr(context, name)
                              : name,
                          child: Text(
                            name == 'Unnamed residential road'
                                ? tr(context, name)
                                : name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                              color: p.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.description.trim().isEmpty
                              ? tr(context, 'No description provided.')
                              : report.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(width: 10),
                    Semantics(
                      label: tr(context, 'Photo attached'),
                      child: SafeImage(
                        imageUrl: report.imageUrl,
                        width: 60,
                        height: 60,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Tooltip(
                message: hasSubmission
                    ? '${tr(context, 'Submitted')}: ${localizedDateTime(context, report.createdAt)}'
                    : tr(context, 'Submission time not recorded'),
                child: notice(Icons.schedule_outlined, timeText),
              ),
              if (showObservationDetail)
                notice(
                  Icons.visibility_outlined,
                  '${tr(context, 'Observed')}: ${localizedAge(context, observed, now)}',
                ),
              if (oldPhoto)
                notice(
                  Icons.photo_outlined,
                  tr(context, 'Photo from an earlier submission'),
                  color: p.warning,
                ),
              if (widget.roadNeedsAttention && !pending)
                notice(
                  Icons.fact_check_outlined,
                  tr(context, 'Road condition needs review'),
                  color: p.warning,
                ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: p.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ReportReference(reportId: report.id),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: p.outlineVariant.withValues(alpha: .3)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final reporter =
                      widget.reporterName?.trim().isNotEmpty == true
                      ? Text(
                          '${tr(context, 'Reported by')}: ${widget.reporterName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: p.onSurfaceVariant,
                          ),
                        )
                      : null;
                  final updates = Tooltip(
                    message: tr(context, 'Private updates'),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 15,
                        color: p.primary,
                      ),
                    ),
                  );
                  final action = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          tr(
                            context,
                            pending ? 'Review report' : 'View details',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: p.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 16, color: p.primary),
                    ],
                  );
                  if (largeText || box.maxWidth < 245) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (reporter != null) ...[
                          reporter,
                          const SizedBox(height: 5),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (hasMessages) ...[
                              updates,
                              const SizedBox(width: 8),
                            ],
                            Flexible(child: action),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      if (reporter != null)
                        Expanded(child: reporter)
                      else
                        const Spacer(),
                      if (hasMessages) ...[const SizedBox(width: 8), updates],
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: box.maxWidth * .45,
                        ),
                        child: action,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
