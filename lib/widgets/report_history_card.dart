import 'resident_report_status.dart';
import 'report_workflow_ui.dart';
import '../screens/user/report_clarification_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_environment.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/road_status.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import 'report_followup_link.dart';
import 'report_message_thread.dart';
import 'report_review_summary.dart';
import 'report_submission_preview.dart';

/// Actual submission, review outcome and private updates remain distinct.
class ReportHistoryCard extends StatefulWidget {
  final UserReport report;
  final RoadStatus? road;
  final bool ownHistory;
  final VoidCallback? onEdit;
  final DateTime Function()? now;
  const ReportHistoryCard({
    super.key,
    required this.report,
    this.road,
    this.ownHistory = true,
    this.onEdit,
    this.now,
  });

  @override
  State<ReportHistoryCard> createState() => _ReportHistoryCardState();
}

class _ReportHistoryCardState extends State<ReportHistoryCard> {
  Timer? _ageTimer;
  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report, road = widget.road;
    final ownHistory = widget.ownHistory, onEdit = widget.onEdit;
    final p = AppPalette.of(context);
    // Current notes, observation time and photo must describe the same revision.
    final evidence = report;
    final name = reportRoadName(report, road: road);
    final legacy = report.adminReplies.isNotEmpty
        ? report.adminReplies
        : [
            if (report.adminReply?.trim().isNotEmpty == true)
              ReportReply(
                message: report.adminReply!,
                timestamp: report.reviewedAt ?? report.createdAt,
              ),
          ];
    if (ownHistory) {
      void open({bool messages = false}) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportUpdatesPage(
            reportId: report.id,
            report: report,
            road: road,
            initialMessages: messages,
            legacyReplies: legacy,
            hasServerUpdates: report.hasAdminUpdates,
          ),
        ),
      );
      final action = report.awaitsResident
          ? 'The barangay asked you a question.'
          : report.clarificationRepliedAt != null && report.reviewOpen
          ? 'Reply sent. Waiting for barangay review.'
          : report.status == 'under_review'
          ? 'The barangay is checking your report.'
          : report.status == 'pending'
          ? 'Waiting for barangay review'
          : report.status == 'verified'
          ? 'Your observation was verified.'
          : report.dismissReason == 'needs_correction'
          ? 'Clearer or corrected evidence is needed.'
          : 'See the review outcome and messages.';
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: p.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: report.awaitsResident
                ? p.warning.withValues(alpha: .6)
                : p.outlineVariant.withValues(alpha: .4),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => open(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name == 'Unnamed residential road'
                              ? tr(context, name)
                              : name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: ResidentReportStatusBadge(report: report),
                        ),
                      ),
                    ],
                  ),
                  if (report.isFollowup || report.isEmergency)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        tr(context, report.isEmergency ? 'SOS' : 'Follow-up'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: p.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    report.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${tr(context, 'Reported')}: ${localizedDateTime(context, report.createdAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                  if (ReportFreshness.isOutdated(
                    report,
                    (widget.now ?? DateTime.now)(),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.history_toggle_off,
                            size: 16,
                            color: p.warning,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              tr(
                                context,
                                'This observation is old. Check the latest road condition before travel.',
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: p.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      height: 1,
                      color: p.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        report.awaitsResident
                            ? Icons.question_answer_outlined
                            : report.status == 'verified'
                            ? Icons.check_circle_outline
                            : Icons.schedule_outlined,
                        color: report.awaitsResident
                            ? p.onWarningContainer
                            : report.status == 'verified' ||
                                  report.clarificationRepliedAt != null
                            ? p.passable
                            : p.onSurfaceVariant,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, action),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                      if (!report.awaitsResident)
                        Icon(Icons.chevron_right, size: 20, color: p.primary),
                    ],
                  ),
                  if (report.awaitsResident) ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => open(messages: true),
                      child: Text(tr(context, 'Reply to barangay')),
                    ),
                  ],
                  if (ownHistory &&
                      !AppEnvironment.sparkFollowupsEnabled &&
                      report.clarificationRequestId == null &&
                      ['pending', 'under_review'].contains(report.status) &&
                      onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(tr(context, 'Update Flood Level / Notes')),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .4)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            report.isEmergency
                                ? Icons.sos
                                : Icons.water_drop_outlined,
                            size: 13,
                            color: report.isEmergency ? p.error : p.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              tr(
                                context,
                                report.isEmergency
                                    ? 'SOS'
                                    : report.isFollowup
                                    ? 'Follow-up'
                                    : ownHistory
                                    ? 'Your report'
                                    : 'Report',
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: p.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name == 'Unnamed residential road' ? tr(context, name) : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: p.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.primary.withValues(alpha: .14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 16,
                                  color: p.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    tr(context, 'Your observation'),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: p.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (report.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                report.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                  color: p.onSurface,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (evidence.imageUrl?.trim().isNotEmpty == true) ...[
                        const SizedBox(width: 10),
                        ReportPhotoThumbnail(report: evidence),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 14,
                        color: p.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${tr(context, 'Observed')}: ${localizedDateTime(context, ReportFreshness.observedAt(report))}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report.imageUrl?.trim().isNotEmpty == true &&
                report.photoSubmittedAt != null &&
                ReportFreshness.observedAt(
                      report,
                    ).difference(report.photoSubmittedAt!) >=
                    const Duration(minutes: 1))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(context, 'Photo from an earlier submission'),
                  style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                ),
              ),
            ReportReference(reportId: report.id),
            ReportStatusProgress(report: report),
            ReportReviewSummary(report: report, road: road, compact: true),
            if (ReportFreshness.isOutdated(
              report,
              (widget.now ?? DateTime.now)(),
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.history_toggle_off, size: 16, color: p.warning),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          'This observation is old. Check the latest road condition before travel.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: p.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (report.hasAdminUpdates || legacy.isNotEmpty)
              ReportMessageThread(
                reportId: report.id,
                report: report,
                isAdmin: !ownHistory,
                legacyReplies: legacy,
                hasServerUpdates: report.hasAdminUpdates,
              ),
            if (report.clarificationRequestId != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportClarificationScreen(
                      reportId: report.id,
                      report: report,
                      isAdmin: !ownHistory,
                    ),
                  ),
                ),
                icon: const Icon(Icons.question_answer_outlined),
                label: Text(
                  tr(
                    context,
                    ownHistory && report.awaitsResident
                        ? 'Reply to clarification request'
                        : 'View clarification',
                  ),
                ),
              ),
            ReportFollowupLink(report: report, readOnly: !ownHistory),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey('report-evidence-${report.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  tr(context, 'View report details'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.primary,
                  ),
                ),
                children: [ReportEvidenceDetails(report: evidence)],
              ),
            ),
            if (ownHistory &&
                !AppEnvironment.sparkFollowupsEnabled &&
                report.clarificationRequestId == null &&
                ['pending', 'under_review'].contains(report.status) &&
                onEdit != null)
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(tr(context, 'Update Flood Level / Notes')),
              ),
          ],
        ),
      ),
    );
  }
}
