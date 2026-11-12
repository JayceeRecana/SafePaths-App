import 'admin_report_evidence.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../models/road_status.dart';
import '../models/user_profile.dart';
import '../services/admin_road_overview.dart';
import '../services/weather_service.dart';
import '../theme/app_palette.dart';
import 'report_submission_preview.dart';
import 'report_message_thread.dart';
import 'report_workflow_ui.dart';

/// Selection and actions remain owned by the live, authenticated admin screen.
class AdminReportWorkspace extends StatefulWidget {
  final UserReport report;
  final RoadStatus? road;
  final UserProfile? reporter;
  final UserReport? originalReport;
  final bool busy, initialMessages;
  final VoidCallback onClose;
  final VoidCallback? onDecision, onAsk, onMessage, onRoadUpdate, onStartReview;
  final Widget? followupLink, correctionAction, messagesPane;
  final DateTime Function()? now;
  const AdminReportWorkspace({
    super.key,
    required this.report,
    this.road,
    this.reporter,
    this.originalReport,
    this.busy = false,
    this.initialMessages = false,
    required this.onClose,
    this.onDecision,
    this.onAsk,
    this.onMessage,
    this.onRoadUpdate,
    this.onStartReview,
    this.followupLink,
    this.correctionAction,
    this.messagesPane,
    this.now,
  });
  @override
  State<AdminReportWorkspace> createState() => _AdminReportWorkspaceState();
}

class _AdminReportWorkspaceState extends State<AdminReportWorkspace> {
  late bool _messages;
  bool _noteExpanded = false;
  @override
  void initState() {
    super.initState();
    _messages = widget.initialMessages;
  }

  @override
  void didUpdateWidget(covariant AdminReportWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id)
      _messages = widget.initialMessages;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        report = widget.report,
        road = widget.road;
    final reporter = widget.reporter?.id == report.userId
        ? widget.reporter
        : null;
    final now = (widget.now ?? DateTime.now)();
    final status = report.awaitsResident
        ? 'Waiting for resident'
        : report.needsAdminReview
        ? 'Needs review'
        : reportReviewLabel(report);
    final color = report.reviewOpen
        ? p.onWarningContainer
        : report.status == 'verified'
        ? p.passable
        : p.onSurfaceVariant;
    final assessment = road == null
        ? null
        : AdminRoadAssessment(
            road,
            now,
            SimulatedWeatherService.instance.currentState,
          );
    final roadColor = assessment?.category == 'not_passable'
        ? p.notPassable
        : assessment?.category == 'passable'
        ? p.passable
        : p.onWarningContainer;
    final name = reportRoadName(report, road: road);
    Widget badge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: report.reviewOpen
            ? p.warningContainer
            : color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            report.awaitsResident
                ? Icons.hourglass_empty
                : report.reviewOpen
                ? Icons.pending_actions_outlined
                : report.status == 'verified'
                ? Icons.check_circle_outline
                : Icons.fact_check_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tr(context, status),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    return Material(
      color: p.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: tr(context, 'Back to list'),
                    color: p.onSurface,
                    onPressed: widget.busy ? null : widget.onClose,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == 'Unnamed residential road'
                              ? tr(context, name)
                              : name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            color: p.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: badge(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: p.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    for (final messages in [false, true])
                      Expanded(
                        child: Semantics(
                          selected: _messages == messages,
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _messages = messages),
                            icon: Icon(
                              messages
                                  ? Icons.forum_outlined
                                  : Icons.description_outlined,
                              size: 15,
                            ),
                            label: Text(
                              tr(context, messages ? 'Messages' : 'Report'),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: _messages == messages
                                  ? p.surfaceContainerLowest
                                  : Colors.transparent,
                              foregroundColor: _messages == messages
                                  ? p.primary
                                  : p.onSurfaceVariant,
                              minimumSize: const Size(48, 40),
                              textStyle: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _messages
                  ? (widget.messagesPane ??
                        ReportUpdatesPage(
                          reportId: report.id,
                          report: report,
                          road: road,
                          isAdmin: true,
                          reportIsLive: true,
                          embeddedAdmin: true,
                          hasServerUpdates: true,
                          legacyReplies: report.adminReplies,
                        ))
                  : ListView(
                      key: ValueKey('admin-workspace-report-${report.id}'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        AdminReportEvidenceCard(
                          report: report,
                          road: road,
                          enabled: !widget.busy,
                          reporterName: reporter?.name,
                          reporterPhotoUrl: reporter?.photoUrl,
                          reporterTrust: reporter?.trustScore,
                        ),
                        const SizedBox(height: 12),
                        ReportPanel(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr(context, 'Road condition now'),
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: p.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tr(
                                  context,
                                  'The latest barangay record, separate from the resident report.',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: p.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roadColor.withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      tr(
                                        context,
                                        assessment?.summaryTitle ??
                                            'Road details unavailable',
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: roadColor,
                                      ),
                                    ),
                                  ),
                                  if (road != null)
                                    Text(
                                      assessment?.knownTime == true
                                          ? '${tr(context, assessment!.historyLabel)}: ${localizedDateTime(context, road.updatedAt)}'
                                          : tr(
                                              context,
                                              'Road update time needs confirmation',
                                            ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                              if (assessment?.summaryExplanation != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    tr(
                                      context,
                                      assessment!.summaryExplanation!,
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: p.onSurface,
                                    ),
                                  ),
                                ),
                              if (road?.notes.trim().isNotEmpty == true)
                                Theme(
                                  data: Theme.of(
                                    context,
                                  ).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    onExpansionChanged: (v) =>
                                        setState(() => _noteExpanded = v),
                                    childrenPadding: const EdgeInsets.only(
                                      bottom: 8,
                                    ),
                                    title: Text(
                                      tr(context, 'Barangay note'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: p.onSurface,
                                      ),
                                    ),
                                    subtitle: _noteExpanded
                                        ? null
                                        : Text(
                                            road!.notes,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                              color: p.onSurfaceVariant,
                                            ),
                                          ),
                                    children: [
                                      Text(
                                        road!.notes,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.5,
                                          color: p.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (report.status == 'pending' &&
                            widget.onStartReview != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: widget.busy
                                  ? null
                                  : widget.onStartReview,
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 17,
                              ),
                              label: Text(tr(context, 'Start review')),
                            ),
                          ),
                        if (widget.originalReport != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ReportSubmissionPreview(
                              report: widget.originalReport!,
                            ),
                          ),
                        if (widget.followupLink != null) widget.followupLink!,
                        if (widget.correctionAction != null)
                          widget.correctionAction!,
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(
                  top: BorderSide(
                    color: p.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (report.reviewOpen)
                    FilledButton(
                      onPressed: widget.busy ? null : widget.onDecision,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        textStyle: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(tr(context, 'Make a decision')),
                    )
                  else if (widget.onRoadUpdate != null)
                    FilledButton.icon(
                      onPressed: widget.busy ? null : widget.onRoadUpdate,
                      icon: const Icon(Icons.edit_road_outlined, size: 17),
                      label: Text(tr(context, 'Update road status')),
                    ),
                  if (report.reviewOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              textStyle: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            onPressed: widget.busy || !report.needsAdminReview
                                ? null
                                : widget.onAsk,
                            icon: const Icon(
                              Icons.question_answer_outlined,
                              size: 14,
                            ),
                            label: Text(
                              tr(
                                context,
                                report.clarificationRepliedAt != null
                                    ? 'Ask another question'
                                    : 'Ask the resident',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              textStyle: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            onPressed: widget.busy ? null : widget.onMessage,
                            icon: const Icon(Icons.send_outlined, size: 14),
                            label: Text(
                              tr(context, 'Send update'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
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
      ),
    );
  }
}
