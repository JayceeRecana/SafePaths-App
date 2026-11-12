import 'report_workflow_ui.dart';
import '../screens/user/report_clarification_screen.dart';
import '../utils/time_utils.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/road_status.dart';
import '../models/user_profile.dart';
import '../models/user_report.dart';
import '../services/report_followup_service.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import 'report_message_thread.dart';
import '../services/admin_report_service.dart' show roadConditionLabel;
import 'report_submission_preview.dart';
import 'road_condition_overview.dart' show roadNeedsRecheck;
import 'safe_image.dart';

enum InspectorTone { information, caution, success, danger, neutral }

class InspectorEvent {
  final String id, title;
  final DateTime time;
  final InspectorTone tone;
  final String? text, condition;
  final int? points;
  final Map<String, dynamic>? correction;
  const InspectorEvent(
    this.id,
    this.title,
    this.time,
    this.tone, {
    this.text,
    this.condition,
    this.points,
    this.correction,
  });
}

/// A summary of known records, not a reconstructed complete road-event log.
List<InspectorEvent> inspectorEvents(UserReport report, RoadStatus? road) {
  final events = <InspectorEvent>[];
  bool known(DateTime? time) => time != null && time.millisecondsSinceEpoch > 0;
  final original = submittedReportEvidence(report);
  if (known(report.createdAt)) {
    events.add(
      InspectorEvent(
        'submitted',
        report.isFollowup ? 'Follow-up submitted' : 'Report submitted',
        report.createdAt,
        InspectorTone.information,
        text: original.description != report.description
            ? original.description
            : null,
      ),
    );
  }
  if (!report.isFollowup &&
      known(report.lastUpdatedByUser) &&
      report.lastUpdatedByUser!.isAfter(report.createdAt)) {
    events.add(
      InspectorEvent(
        'resident-edit',
        'Resident updated the report',
        report.lastUpdatedByUser!,
        InspectorTone.information,
        text: report.description,
      ),
    );
  }
  if (known(report.clarificationRequestedAt)) {
    events.add(
      InspectorEvent(
        'clarification-request',
        'Clarification requested',
        report.clarificationRequestedAt!,
        InspectorTone.caution,
      ),
    );
  }
  if (known(report.clarificationRepliedAt)) {
    events.add(
      InspectorEvent(
        'clarification-reply',
        'Resident replied',
        report.clarificationRepliedAt!,
        InspectorTone.information,
      ),
    );
  }
  if (known(report.reviewStartedAt)) {
    events.add(
      InspectorEvent(
        'review-start',
        'Review started',
        report.reviewStartedAt!,
        InspectorTone.caution,
      ),
    );
  }
  if (known(report.reviewedAt) &&
      const ['verified', 'resolved', 'dismissed'].contains(report.status)) {
    final corrected = report.rewardCorrection != null;
    final needsCorrection = report.dismissReason == 'needs_correction';
    events.add(
      InspectorEvent(
        'review',
        corrected
            ? 'Follow-up review corrected'
            : report.status == 'verified'
            ? 'Observation verified'
            : report.status == 'resolved'
            ? 'Incident reviewed'
            : needsCorrection
            ? 'Needs correction'
            : 'Report dismissed',
        report.reviewedAt!,
        corrected || needsCorrection
            ? InspectorTone.caution
            : report.status == 'verified'
            ? InspectorTone.success
            : report.dismissReason == 'spam_false'
            ? InspectorTone.danger
            : InspectorTone.neutral,
        condition: report.incidentReviewStatus,
        points: corrected ? null : report.pointsAwarded,
        correction: report.rewardCorrection,
      ),
    );
  }
  // Suppress a repeated snapshot from the very same review; keep later updates.
  if (road != null &&
      known(road.updatedAt) &&
      !(road.updatedAt == report.reviewedAt &&
          road.status == report.incidentReviewStatus)) {
    events.add(
      InspectorEvent(
        'road-latest',
        'Latest recorded road update',
        road.updatedAt,
        road.isVerified
            ? road.status == 'not_passable'
                  ? InspectorTone.danger
                  : road.status == 'passable'
                  ? InspectorTone.success
                  : InspectorTone.caution
            : InspectorTone.caution,
        condition: road.status,
      ),
    );
  }
  // Stable ordering for simultaneous server writes.
  final ordered = events.asMap().entries.toList()
    ..sort((a, b) {
      final time = a.value.time.compareTo(b.value.time);
      return time == 0 ? a.key.compareTo(b.key) : time;
    });
  return ordered.map((entry) => entry.value).toList();
}

class AdminReportInspector extends StatefulWidget {
  final Widget? clarificationAction;
  final UserReport report;
  final RoadStatus? road;
  final UserProfile? reporter;
  final UserReport? originalReport;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback? onReview,
      onDismiss,
      onRoadUpdate,
      onStartReview,
      onMessage,
      onViewRoad;
  final Widget? followupLink, correctionAction;
  final DateTime Function()? now;
  const AdminReportInspector({
    super.key,
    this.clarificationAction,
    required this.report,
    this.road,
    this.reporter,
    this.originalReport,
    this.busy = false,
    required this.onClose,
    this.onReview,
    this.onDismiss,
    this.onRoadUpdate,
    this.onStartReview,
    this.onMessage,
    this.onViewRoad,
    this.followupLink,
    this.correctionAction,
    this.now,
  });
  @override
  State<AdminReportInspector> createState() => _AdminReportInspectorState();
}

class _AdminReportInspectorState extends State<AdminReportInspector> {
  Timer? _timer;
  bool _noteExpanded = false;
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

  Color _color(InspectorTone tone) {
    final p = AppPalette.of(context);
    return switch (tone) {
      InspectorTone.information => p.primary,
      InspectorTone.caution => p.warning,
      InspectorTone.success => p.passable,
      InspectorTone.danger => p.error,
      InspectorTone.neutral => p.onSurfaceVariant,
    };
  }

  IconData _icon(InspectorTone tone) => switch (tone) {
    InspectorTone.information => Icons.description_outlined,
    InspectorTone.caution => Icons.pending_actions_outlined,
    InspectorTone.success => Icons.check_circle_outline,
    InspectorTone.danger => Icons.block,
    InspectorTone.neutral => Icons.history,
  };
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      tr(context, text),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: AppPalette.of(context).onSurfaceVariant,
      ),
    ),
  );
  Widget _card(Widget child, {Color? color, Key? key}) {
    final p = AppPalette.of(context);
    return Material(
      key: key,
      color: color ?? p.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.outlineVariant.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  Widget _notice(String text, InspectorTone tone) {
    final color = _color(tone);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == InspectorTone.danger ? Icons.sos : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, text),
              style: TextStyle(fontSize: 12, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(
    String heading,
    String status,
    String subtitle,
    InspectorTone tone, {
    double? headingHeight,
  }) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: headingHeight,
          child: Text(
            tr(context, heading),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: 10,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: AppPalette.of(context).onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(tone), size: 18, color: _color(tone)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(context, status),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _color(tone),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppPalette.of(context).onSurfaceVariant,
          ),
        ),
      ],
    ),
    key: ValueKey('inspector-summary-$heading'),
  );

  @override
  Widget build(BuildContext context) {
    final report = widget.report,
        road = widget.road,
        p = AppPalette.of(context);
    final now = (widget.now ?? DateTime.now)();
    final pending = report.reviewOpen;
    final corrected = report.rewardCorrection != null;
    final correction =
        report.status == 'dismissed' &&
        report.dismissReason == 'needs_correction';
    final status = reportReviewLabel(report);
    final tone =
        corrected || correction || pending || report.status == 'expired'
        ? InspectorTone.caution
        : report.status == 'verified'
        ? InspectorTone.success
        : report.dismissReason == 'spam_false'
        ? InspectorTone.danger
        : InspectorTone.neutral;
    final reviewed = TimeUtils.hasRecordedTime(report.reviewedAt)
        ? report.reviewedAt
        : null;
    final reportTime = reviewed != null && !pending
        ? '${tr(context, 'Reviewed')}: ${localizedDateTime(context, reviewed)}'
        : pending
        ? tr(
            context,
            report.awaitsResident
                ? 'Waiting for the resident reply'
                : 'Review the submitted evidence',
          )
        : TimeUtils.hasRecordedTime(report.createdAt)
        ? '${tr(context, 'Submitted')}: ${localizedDateTime(context, report.createdAt)}'
        : tr(context, 'Submission time not recorded');
    final roadTimeConfirmed =
        road != null &&
        TimeUtils.hasRecordedTime(road.updatedAt) &&
        !road.updatedAt.isAfter(now.add(const Duration(minutes: 1)));
    final roadTime = road == null
        ? tr(context, 'Road details unavailable')
        : !roadTimeConfirmed
        ? tr(context, 'Road update time needs confirmation')
        : '${tr(context, 'Updated')}: ${localizedAge(context, road.updatedAt, now)}';
    final roadTone = road == null || !road.isVerified || !roadTimeConfirmed
        ? InspectorTone.caution
        : road.status == 'not_passable'
        ? InspectorTone.danger
        : road.status == 'passable'
        ? InspectorTone.success
        : InspectorTone.caution;
    final events = inspectorEvents(report, road);
    final roadName = reportRoadName(report, road: road);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    List<Widget> summaries({double? headingHeight}) => [
      _summary(
        report.isFollowup ? 'This follow-up' : 'This report',
        status,
        reportTime,
        tone,
        headingHeight: headingHeight,
      ),
      _summary(
        'Latest recorded road update',
        road != null && !road.isVerified
            ? 'Unconfirmed'
            : roadConditionLabel(road?.status),
        roadTime,
        roadTone,
        headingHeight: headingHeight,
      ),
    ];
    final original = widget.originalReport;
    final validOriginal =
        original != null &&
        report.isFollowup &&
        !original.isFollowup &&
        original.id == report.rootReportId &&
        original.userId == report.userId &&
        original.incidentId == report.incidentId;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.assignment_outlined,
                    size: 19,
                    color: p.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, pending ? 'Review report' : 'Report details'),
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: p.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Close'),
                  color: p.onSurfaceVariant,
                  onPressed: widget.busy ? null : widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: ValueKey('inspector-scroll-${report.id}'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (report.isFollowup) ...[
                    Text(
                      tr(context, 'Follow-up to an earlier report'),
                      style: TextStyle(
                        color: p.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    roadName == 'Unnamed residential road'
                        ? tr(context, roadName)
                        : roadName,
                    style: GoogleFonts.manrope(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: p.onSurface,
                    ),
                  ),
                  if (roadName == 'Unnamed residential road' &&
                      report.roadId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${tr(context, 'Road reference')}: ${report.roadId}',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ReportReference(reportId: report.id),
                  if (large) ...[
                    summaries().first,
                    const SizedBox(height: 8),
                    summaries().last,
                  ] else
                    LayoutBuilder(
                      builder: (context, box) {
                        final width = (box.maxWidth - 8) / 2 - 28;
                        double headingHeight = 0;
                        for (final title in [
                          report.isFollowup ? 'This follow-up' : 'This report',
                          'Latest recorded road update',
                        ]) {
                          final painter = TextPainter(
                            text: TextSpan(
                              text: tr(context, title),
                              style: Theme.of(context).textTheme.bodyMedium!
                                  .copyWith(
                                    fontSize: 10,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(maxWidth: width > 1 ? width : 1);
                          if (painter.height > headingHeight)
                            headingHeight = painter.height;
                          painter.dispose();
                        }
                        final cards = summaries(headingHeight: headingHeight);
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cards.first),
                              const SizedBox(width: 8),
                              Expanded(child: cards.last),
                            ],
                          ),
                        );
                      },
                    ),
                  if (widget.onStartReview != null &&
                      report.status == 'pending')
                    TextButton.icon(
                      onPressed: widget.busy ? null : widget.onStartReview,
                      icon: const Icon(Icons.manage_search),
                      label: Text(tr(context, 'Start review')),
                    ),
                  if (widget.clarificationAction != null)
                    widget.clarificationAction!,
                  if (report.clarificationRequestId != null)
                    OutlinedButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReportClarificationScreen(
                                  reportId: report.id,
                                  report: report,
                                  isAdmin: true,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.question_answer_outlined),
                      label: Text(
                        tr(
                          context,
                          report.awaitsResident
                              ? 'View clarification request'
                              : 'Review resident clarification',
                        ),
                      ),
                    ),
                  if (report.isEmergency)
                    _notice(
                      'Resident requested urgent assistance. A report review does not confirm rescue dispatch.',
                      InspectorTone.danger,
                    ),
                  if (road != null &&
                      reviewed != null &&
                      report.incidentReviewStatus != null &&
                      road.updatedAt.isAfter(reviewed) &&
                      report.incidentReviewStatus != road.status)
                    _notice(
                      'The latest road update differs from the condition recorded at this review. See the recorded updates below.',
                      InspectorTone.information,
                    )
                  else if (pending)
                    _notice(
                      'Review what the resident observed and when. Check current road conditions separately.',
                      InspectorTone.information,
                    ),
                  if (road != null &&
                      (!road.isVerified ||
                          !roadTimeConfirmed ||
                          roadNeedsRecheck(road, now)))
                    _notice(
                      !roadTimeConfirmed
                          ? 'The road update time is unconfirmed. Check current conditions before changing its status.'
                          : !road.isVerified
                          ? 'The recorded road condition needs confirmation.'
                          : 'The road update needs a recheck. Its recorded restriction still applies.',
                      InspectorTone.caution,
                    ),
                  if (road != null && road.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _card(
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        onExpansionChanged: (value) =>
                            setState(() => _noteExpanded = value),
                        title: Text(
                          tr(
                            context,
                            road.isVerified ? 'Barangay note' : 'Road note',
                          ),
                          style: TextStyle(
                            color: p.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: _noteExpanded
                            ? null
                            : Text(
                                road.notes,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.onSurface,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              road.notes,
                              style: TextStyle(
                                color: p.onSurface,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.onViewRoad != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.busy ? null : widget.onViewRoad,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(
                          tr(context, 'View road and community updates'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .5),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 19,
                          color: p.primary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              report.isFollowup
                                  ? 'What the resident updated'
                                  : 'What the resident reported',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: p.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (report.imageUrl?.trim().isNotEmpty == true)
                          InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (dialog) => ReportPhotoViewer(
                                child: Dialog(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          tooltip: tr(context, 'Close'),
                                          color: p.onSurfaceVariant,
                                          onPressed: () =>
                                              Navigator.pop(dialog),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ),
                                      Flexible(
                                        child: InteractiveViewer(
                                          child: SafeImage(
                                            imageUrl: report.imageUrl,
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                            height:
                                                MediaQuery.sizeOf(
                                                  context,
                                                ).height *
                                                .6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            child: Semantics(
                              button: true,
                              label: tr(context, 'View submitted photo'),
                              child: SafeImage(
                                imageUrl: report.imageUrl,
                                height: 170,
                                width: double.infinity,
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          )
                        else
                          Text(
                            tr(context, 'No photo attached with this report'),
                            style: TextStyle(color: p.onSurfaceVariant),
                          ),
                        const SizedBox(height: 12),
                        if (report.isFollowup)
                          Text(
                            tr(
                              context,
                              followupChangeLabel(report.conditionChange),
                            ),
                          ),
                        Text(
                          report.description.isEmpty
                              ? tr(context, 'No description provided.')
                              : report.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Divider(
                          height: 16,
                          color: p.outlineVariant.withValues(alpha: .35),
                        ),
                        ReportEvidenceContext(
                          report: report,
                          showReporterContext: true,
                          reporterName: widget.reporter?.name,
                          reporterTrust: widget.reporter?.trustScore,
                        ),
                        if (report.imageUrl?.trim().isNotEmpty == true &&
                            TimeUtils.hasRecordedTime(
                              report.photoSubmittedAt,
                            ) &&
                            ReportFreshness.observedAt(
                                  report,
                                ).difference(report.photoSubmittedAt!) >=
                                const Duration(minutes: 1))
                          _notice(
                            'Photo from an earlier submission',
                            InspectorTone.caution,
                          ),
                        if (TimeUtils.hasRecordedTime(report.observedAt) &&
                            report.observedAt!.isAfter(
                              now.add(const Duration(minutes: 1)),
                            ))
                          _notice(
                            'The observation time is in the future. Confirm it with the resident.',
                            InspectorTone.caution,
                          )
                        else if (TimeUtils.hasRecordedTime(report.observedAt) &&
                            now.difference(report.observedAt!) >=
                                ReportFreshness.maximumAge)
                          _notice(
                            'This observation is old. It does not establish the current road condition.',
                            InspectorTone.caution,
                          )
                        else if (report.status == 'expired')
                          _notice(
                            'This report is marked outdated. Check current conditions separately.',
                            InspectorTone.caution,
                          ),
                      ],
                    ),
                  ),
                  if (validOriginal)
                    ExpansionTile(
                      key: ValueKey('inspector-original-${report.id}'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(tr(context, 'View original report')),
                      children: [ReportSubmissionPreview(report: original)],
                    ),
                  if (widget.followupLink != null) widget.followupLink!,
                  _label('Recorded updates'),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            'Report events and the latest road update. Earlier road changes may not be listed.',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final event in events) _event(event),
                        if (events.isEmpty)
                          Text(tr(context, 'No dated updates are available.')),
                      ],
                    ),
                  ),
                  if (widget.onMessage != null ||
                      report.hasAdminUpdates ||
                      report.adminReplies.isNotEmpty ||
                      report.adminReply?.trim().isNotEmpty == true) ...[
                    _label('Private updates to the resident'),
                    if (widget.onMessage != null)
                      OutlinedButton.icon(
                        onPressed: widget.busy ? null : widget.onMessage,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(tr(context, 'Send private update')),
                      ),
                    if (report.hasAdminUpdates ||
                        report.adminReplies.isNotEmpty ||
                        report.adminReply?.trim().isNotEmpty == true)
                      ReportMessageThread(
                        reportId: report.id,
                        report: report,
                        isAdmin: true,
                        hasServerUpdates: report.hasAdminUpdates,
                        legacyReplies: report.adminReplies.isNotEmpty
                            ? report.adminReplies
                            : [
                                if (report.adminReply?.trim().isNotEmpty ==
                                    true)
                                  ReportReply(
                                    message: report.adminReply!,
                                    timestamp:
                                        report.reviewedAt ?? report.createdAt,
                                  ),
                              ],
                      ),
                  ],
                  const SizedBox(height: 8),
                  ExpansionTile(
                    key: ValueKey('inspector-details-${report.id}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Technical details')),
                    children: [
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SelectableText(
                              '${tr(context, 'Report ID')}: ${report.id}',
                            ),
                            if (report.roadId != null)
                              Text(
                                '${tr(context, 'Road ID')}: ${report.roadId}',
                              ),
                            if (report.rewardCorrection != null &&
                                report.pointsAwarded != null)
                              Text(
                                '${tr(context, 'Original review award')}: ${report.pointsAwarded}',
                              ),
                            if (widget.correctionAction != null)
                              widget.correctionAction!,
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: p.outlineVariant.withValues(alpha: .4)),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final buttons = [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      textStyle: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: widget.busy
                        ? null
                        : pending
                        ? widget.onDismiss
                        : widget.onClose,
                    child: Text(
                      tr(context, pending ? 'Other decision' : 'Back to list'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      textStyle: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: widget.busy
                        ? null
                        : pending
                        ? widget.onReview
                        : widget.onRoadUpdate,
                    child: Text(
                      tr(
                        context,
                        pending ? 'Review report' : 'Update road status',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ];
                return large || box.maxWidth < 285
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buttons.first,
                          const SizedBox(height: 6),
                          buttons.last,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: buttons.first),
                          const SizedBox(width: 8),
                          Expanded(child: buttons.last),
                        ],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _event(InspectorEvent event) {
    final p = AppPalette.of(context), color = _color(event.tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Semantics(
                  label: tr(context, event.title),
                  child: Container(
                    key: ValueKey('event-dot-${event.id}'),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon(event.tone), size: 14, color: color),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: p.outlineVariant.withValues(alpha: .5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedDateTime(context, event.time),
                    style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tr(context, event.title),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  if (event.condition != null)
                    Text(
                      '${tr(context, event.id == 'road-latest' ? 'Recorded condition' : 'Condition recorded at review')}: ${tr(context, roadConditionLabel(event.condition))}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurface,
                      ),
                    ),
                  if (event.text?.trim().isNotEmpty == true)
                    Text(
                      event.text!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurface,
                      ),
                    ),
                  if (event.points != null)
                    Text(
                      event.points == 0
                          ? tr(
                              context,
                              'No trust points awarded for this review.',
                            )
                          : '${tr(context, 'Trust change for this review')}: ${event.points! > 0 ? '+' : ''}${event.points}',
                      style: TextStyle(fontSize: 12, color: p.onSurface),
                    ),
                  if (event.correction != null)
                    Text(
                      '${tr(context, 'Bonus reversal')}: -${event.correction!['reversed'] ?? 0}. ${tr(context, 'False-submission penalty')}: -${event.correction!['penalty'] ?? 0}.',
                      style: TextStyle(fontSize: 12, color: p.onSurface),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
