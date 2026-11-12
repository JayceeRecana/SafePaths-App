import 'user_avatar.dart';
import 'report_workflow_ui.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/road_status.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import '../utils/time_utils.dart';
import 'road_condition_overview.dart' show residentRoadTitle;
import 'safe_image.dart';

/// Decision context belongs beside the evidence, not inside technical metadata.
class ReportEvidenceContext extends StatelessWidget {
  final UserReport report;
  final String? reporterName, reporterPhotoUrl;
  final int? reporterTrust;
  final bool showReporterContext, showReporterAvatar;
  final bool showObservationDetails;
  const ReportEvidenceContext({
    super.key,
    required this.report,
    this.reporterName,
    this.reporterPhotoUrl,
    this.reporterTrust,
    this.showReporterAvatar = false,
    this.showReporterContext = false,
    this.showObservationDetails = true,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget row(IconData icon, String label, String value, {Widget? leading}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ?? Icon(icon, size: 17, color: p.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(context, label),
                      style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: p.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    final observed = report.observedAt;
    final observedKnown = TimeUtils.hasRecordedTime(observed);
    final submittedKnown = TimeUtils.hasRecordedTime(report.createdAt);
    final sameMinute =
        observedKnown &&
        submittedKnown &&
        observed!.millisecondsSinceEpoch ~/ 60000 ==
            report.createdAt.millisecondsSinceEpoch ~/ 60000;
    final photoTime = report.photoSubmittedAt;
    final showPhotoTime =
        report.imageUrl?.trim().isNotEmpty == true &&
        TimeUtils.hasRecordedTime(photoTime) &&
        (!submittedKnown ||
            photoTime!.millisecondsSinceEpoch ~/ 60000 !=
                report.createdAt.millisecondsSinceEpoch ~/ 60000);
    final lat = report.location?['lat'], lng = report.location?['lng'];
    final locationKnown =
        lat is num &&
        lng is num &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showObservationDetails) ...[
          row(
            Icons.water_drop_outlined,
            'Resident-selected flood level',
            const ['Low', 'Medium', 'High'].contains(report.severity)
                ? tr(context, report.severity)
                : tr(context, 'Not recorded'),
          ),
          if (sameMinute)
            row(
              Icons.schedule,
              'Observed and submitted',
              localizedDateTime(context, observed),
            )
          else ...[
            row(
              Icons.visibility_outlined,
              'Observed',
              observedKnown
                  ? localizedDateTime(context, observed!)
                  : tr(context, 'Observation time was not recorded.'),
            ),
            row(
              Icons.send_outlined,
              'Submitted',
              submittedKnown
                  ? localizedDateTime(context, report.createdAt)
                  : tr(context, 'Submission time not recorded'),
            ),
          ],
        ],
        if (showPhotoTime)
          row(
            Icons.photo_outlined,
            'Photo submitted',
            localizedDateTime(context, photoTime!),
          ),
        if (TimeUtils.hasRecordedTime(report.lastUpdatedByUser) &&
            report.lastUpdatedByUser!.difference(report.createdAt).inMinutes >=
                1)
          row(
            Icons.edit_note,
            'Last resident edit',
            localizedDateTime(context, report.lastUpdatedByUser!),
          ),
        if (showObservationDetails)
          row(
            Icons.location_on_outlined,
            'Reported location',
            locationKnown
                ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                : tr(context, 'Location not recorded or unavailable'),
          ),
        if (reporterName?.trim().isNotEmpty == true || showReporterContext)
          row(
            Icons.person_outline,
            'Reported by',
            reporterName?.trim().isNotEmpty == true
                ? reporterName!
                : tr(context, 'Reporter details unavailable'),
            leading: showReporterAvatar
                ? UserAvatar(
                    photoUrl: reporterPhotoUrl,
                    size: 36,
                    iconSize: 20,
                    backgroundColor: p.primaryContainer,
                    iconColor: p.onPrimaryContainer,
                  )
                : null,
          ),
        if (reporterTrust != null) ...[
          row(
            Icons.history_outlined,
            'Reporter trust score',
            '${reporterTrust!}/100',
          ),
          Text(
            tr(
              context,
              'Reporting history only. Check the evidence for this report.',
            ),
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: p.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// This is a display snapshot, never a replacement for the report/review record.
UserReport submittedReportEvidence(UserReport report) {
  if (report.isFollowup || report.originalSubmission == null) return report;
  try {
    return UserReport.fromJson({
      ...report.toJson(),
      ...report.originalSubmission!,
      'id': report.id,
      'createdAt':
          report.originalSubmission!['submittedAt'] ??
          report.createdAt.toIso8601String(),
    });
  } catch (_) {
    return report;
  }
}

/// Shared short outcome labels for the admin list and inspector.
String reportReviewLabel(UserReport report) {
  if (report.rewardCorrection != null) return 'Follow-up review corrected';
  if (report.status == 'dismissed' &&
      report.dismissReason == 'needs_correction')
    return 'Needs correction';
  if (report.status == 'dismissed' &&
      report.dismissReason == 'unable_to_verify')
    return 'Unable to verify';
  if (report.status == 'dismissed' &&
      report.dismissReason == 'duplicate_resolved')
    return 'Duplicate submission';
  return switch (report.status) {
    'waiting_resident' => 'Waiting for resident',
    'pending' =>
      report.clarificationRepliedAt != null
          ? 'Resident replied'
          : 'Needs review',
    'under_review' => 'Under review',
    'verified' => 'Verified',
    'resolved' => 'Reviewed',
    'expired' => 'Outdated',
    'dismissed' => 'Dismissed',
    _ => 'Unknown',
  };
}

String reportRoadName(UserReport report, {RoadStatus? road}) {
  final title =
      road?.name ??
      (report.title.contains(':')
          ? report.title.substring(report.title.indexOf(':') + 1).trim()
          : report.title);
  return residentRoadTitle(title);
}

class ReportPhotoThumbnail extends StatelessWidget {
  final UserReport report;
  final double width, height;
  final bool showExpandBadge;
  const ReportPhotoThumbnail({
    super.key,
    required this.report,
    this.width = 64,
    this.height = 64,
    this.showExpandBadge = false,
  });
  @override
  Widget build(BuildContext context) {
    if (report.imageUrl?.trim().isNotEmpty != true)
      return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: tr(context, 'View submitted photo'),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialog) => ReportPhotoViewer(
            child: Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialog).height * .8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(
                                context,
                                report.isFollowup
                                    ? 'Follow-up photo'
                                    : 'Submitted photo',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr(context, 'Close'),
                            onPressed: () => Navigator.pop(dialog),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        child: SafeImage(
                          imageUrl: report.imageUrl,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: MediaQuery.sizeOf(dialog).height * .55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeImage(
                imageUrl: report.imageUrl,
                width: width,
                height: height,
                borderRadius: BorderRadius.circular(16),
              ),
              if (showExpandBadge)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: AppPalette.of(context).primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compare the displayed minute only when an observation time was supplied.
/// Missing observation times must not be presented as a recorded observation.
bool reportTimesShareMinute(UserReport report) =>
    report.observedAt != null &&
    report.observedAt!.millisecondsSinceEpoch ~/ 60000 ==
        report.createdAt.millisecondsSinceEpoch ~/ 60000;

class ReportSubmissionPreview extends StatelessWidget {
  final UserReport report;
  final RoadStatus? road;
  final bool showReference;
  const ReportSubmissionPreview({
    super.key,
    required this.report,
    this.road,
    this.showReference = true,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        evidence = submittedReportEvidence(report);
    final name = reportRoadName(evidence, road: road);
    return Material(
      color: p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        key: ValueKey('submission-preview-${report.id}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.outlineVariant.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: p.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(
                      context,
                      report.isFollowup
                          ? 'Submitted follow-up'
                          : report.originalSubmission != null &&
                                report.lastUpdatedByUser != null &&
                                report.lastUpdatedByUser!.isAfter(
                                  report.createdAt,
                                )
                          ? 'Original submission'
                          : 'Submitted report',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == 'Unnamed residential road'
                            ? tr(context, name)
                            : name,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.onSurface,
                        ),
                      ),
                      if (evidence.description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          evidence.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.4,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (evidence.imageUrl?.trim().isNotEmpty == true) ...[
                  const SizedBox(width: 12),
                  ReportPhotoThumbnail(report: evidence),
                ],
              ],
            ),
            if (showReference) ReportReference(reportId: report.id),
            const SizedBox(height: 8),
            Text(
              '${tr(context, reportTimesShareMinute(evidence) ? 'Observed and submitted' : 'Observed')}: ${localizedDateTime(context, ReportFreshness.observedAt(evidence))}',
              style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey('submitted-details-${report.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  tr(context, 'View submitted report'),
                  style: TextStyle(
                    fontSize: 12,
                    color: p.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  ReportEvidenceDetails(
                    report: evidence,
                    submissionTimeAlreadyShown: reportTimesShareMinute(
                      evidence,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportEvidenceDetails extends StatelessWidget {
  final UserReport report;
  final bool submissionTimeAlreadyShown;
  const ReportEvidenceDetails({
    super.key,
    required this.report,
    this.submissionTimeAlreadyShown = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          report.title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          report.description,
          style: TextStyle(fontSize: 13, height: 1.4, color: p.onSurface),
        ),
        if (!submissionTimeAlreadyShown) ...[
          const SizedBox(height: 8),
          Text(
            '${tr(context, 'Submitted')}: ${localizedDateTime(context, report.createdAt)}',
            style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
          ),
        ],

        if (report.photoSubmittedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            '${tr(context, 'Photo submitted')}: ${localizedDateTime(context, report.photoSubmittedAt!)}',
            style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
          ),
        ],
        // The thumbnail above opens the full, account-guarded photo viewer.
      ],
    );
  }
}

class ReportStatusProgress extends StatelessWidget {
  final UserReport report;
  final bool resident;
  const ReportStatusProgress({
    super.key,
    required this.report,
    this.resident = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final finalReview = const [
      'verified',
      'resolved',
      'dismissed',
    ].contains(report.status);
    final reviewed = finalReview || report.reviewedAt != null;
    final reviewing =
        report.status == 'under_review' ||
        report.awaitsResident ||
        report.clarificationRepliedAt != null;
    final terminal = finalReview || report.status == 'expired';
    final terminalColor = report.status == 'resolved'
        ? p.primary
        : report.status == 'verified'
        ? p.passable
        : report.status == 'dismissed'
        ? (report.dismissReason == 'needs_correction' ? p.primary : p.error)
        : p.warning;
    final labels = [
      'Sent',
      'Review',
      switch (report.status) {
        'verified' => 'Verified',
        'resolved' => 'Reviewed',
        'dismissed' =>
          report.dismissReason == 'needs_correction'
              ? 'Correction'
              : 'Dismissed',
        'expired' => 'Outdated',
        _ => resident ? 'Decision' : 'Outcome',
      },
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(3, (i) {
          final active =
              i == 0 ||
              (i == 1 && (reviewed || reviewing)) ||
              (i == 2 && terminal);
          final color = resident && i == 0
              ? p.passable
              : resident && i == 1 && report.awaitsResident
              ? p.warning
              : i == 2 && terminal
              ? terminalColor
              : active
              ? (report.status == 'verified' ? p.passable : p.primary)
              : p.outlineVariant;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1.5,
                        color: i == 0
                            ? Colors.transparent
                            : (i == 1
                                  ? (reviewed || reviewing)
                                  : terminal && reviewed)
                            ? color
                            : p.outlineVariant,
                      ),
                    ),
                    Icon(
                      active
                          ? (i == 1 && report.awaitsResident
                                ? Icons.question_answer_rounded
                                : i == 1 && reviewing
                                ? Icons.pending
                                : i == 2 && report.status == 'expired'
                                ? Icons.history
                                : i == 2 && report.status == 'dismissed'
                                ? Icons.cancel
                                : Icons.check_circle)
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: color,
                    ),
                    Expanded(
                      child: Container(
                        height: 1.5,
                        color: i == 2
                            ? Colors.transparent
                            : (i == 0
                                  ? (reviewed || reviewing)
                                  : terminal && reviewed)
                            ? color
                            : p.outlineVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  tr(context, labels[i]),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: active ? p.onSurface : p.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// A photo modal must not retain an earlier account's image after sign-out or
/// a direct account switch, including legacy inline evidence.
class ReportPhotoViewer extends StatefulWidget {
  final Widget child;
  final String? Function()? currentViewer;
  final Stream<String?>? viewerChanges;
  const ReportPhotoViewer({
    super.key,
    required this.child,
    this.currentViewer,
    this.viewerChanges,
  });
  @override
  State<ReportPhotoViewer> createState() => _ReportPhotoViewerState();
}

class _ReportPhotoViewerState extends State<ReportPhotoViewer> {
  StreamSubscription<String?>? _accounts;
  String? _initial;
  bool _changed = false;
  String? _viewer() {
    if (widget.currentViewer != null) return widget.currentViewer!();
    if (Firebase.apps.isEmpty) return 'local-preview';
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.emailVerified && !user.isAnonymous
        ? user.uid
        : null;
  }

  @override
  void initState() {
    super.initState();
    _initial = _viewer();
    final stream =
        widget.viewerChanges ??
        (Firebase.apps.isEmpty
            ? const Stream<String?>.empty()
            : FirebaseAuth.instance.userChanges().map(
                (user) =>
                    user != null && user.emailVerified && !user.isAnonymous
                    ? user.uid
                    : null,
              ));
    _accounts = stream.listen((uid) {
      if (mounted && uid != _initial) setState(() => _changed = true);
    });
  }

  @override
  void dispose() {
    unawaited(_accounts?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _changed || _initial == null || _viewer() != _initial
      ? AlertDialog(
          content: Text(
            tr(
              context,
              'Account changed. Reopen updates from your own reports.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Close')),
            ),
          ],
        )
      : widget.child;
}

/// Submission time identifies a retained attachment, never its capture time.
class ReportRetainedPhotoNotice extends StatelessWidget {
  final UserReport report;
  const ReportRetainedPhotoNotice({super.key, required this.report});
  @override
  Widget build(BuildContext context) {
    final submitted = report.photoSubmittedAt, observed = report.observedAt;
    if (report.imageUrl?.trim().isNotEmpty != true ||
        !TimeUtils.hasRecordedTime(submitted) ||
        !TimeUtils.hasRecordedTime(observed) ||
        observed!.difference(submitted!) < const Duration(minutes: 1)) {
      return const SizedBox.shrink();
    }
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_outlined, size: 16, color: p.warning),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              tr(context, 'Photo from an earlier submission'),
              style: TextStyle(fontSize: 11, height: 1.5, color: p.warning),
            ),
          ),
        ],
      ),
    );
  }
}
