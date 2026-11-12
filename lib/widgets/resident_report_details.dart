import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';
import 'report_submission_preview.dart';
import 'report_workflow_ui.dart';
import 'safe_image.dart';

/// Report timestamps, not message wording, identify the recorded workflow event.
enum ResidentMessageTone { routine, question, reply, verified }

ResidentMessageTone residentMessageTone({
  required UserReport report,
  required String sender,
  DateTime? createdAt,
}) {
  bool sameEvent(DateTime? time) =>
      time != null &&
      createdAt != null &&
      time.millisecondsSinceEpoch == createdAt.millisecondsSinceEpoch;
  if (sender == 'Resident clarification') return ResidentMessageTone.reply;
  if (sameEvent(report.clarificationRequestedAt))
    return ResidentMessageTone.question;
  if (report.status == 'verified' &&
      report.rewardCorrection == null &&
      sameEvent(report.reviewedAt))
    return ResidentMessageTone.verified;
  return ResidentMessageTone.routine;
}

/// Compact bubbles follow the resident design; they never infer decisions from
/// authored text or turn a routine message into a road warning.
class ResidentReportMessageBubble extends StatelessWidget {
  final UserReport report;
  final String sender, message;
  final DateTime? createdAt, photoObservedAt;
  final String? imageUrl;
  final bool adminView;
  const ResidentReportMessageBubble({
    super.key,
    required this.report,
    required this.sender,
    required this.message,
    this.createdAt,
    this.imageUrl,
    this.adminView = false,
    this.photoObservedAt,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final tone = residentMessageTone(
      report: report,
      sender: sender,
      createdAt: createdAt,
    );
    final resident = tone == ResidentMessageTone.reply;
    final wasQuestion = tone == ResidentMessageTone.question;
    final question = wasQuestion && report.awaitsResident;
    final positive = resident || tone == ResidentMessageTone.verified;
    final adminOutgoing = adminView && !resident && !question && !positive;
    final outgoing = adminView ? !resident : resident;
    final knownBarangay = const [
      'SafePaths administrator',
      'Barangay Command Center',
    ].contains(sender);
    final displaySender = adminView
        ? tr(context, resident ? 'Resident' : 'You')
        : resident
        ? tr(context, 'You')
        : knownBarangay
        ? tr(context, 'Barangay')
        : sender;
    final color = question
        ? p.onWarningContainer
        : positive
        ? p.passable
        : adminOutgoing
        ? p.primary
        : p.onSurfaceVariant;
    final background = question
        ? p.warningContainer
        : positive
        ? Color.alphaBlend(
            p.passable.withValues(alpha: p.isDark ? .12 : .07),
            p.surfaceContainerLowest,
          )
        : adminOutgoing
        ? Color.alphaBlend(
            p.primary.withValues(alpha: .055),
            p.surfaceContainerLowest,
          )
        : p.surfaceContainerLowest;
    final avatar = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .1),
      ),
      child: Icon(
        resident ? Icons.person_outline : Icons.shield_outlined,
        size: 14,
        color: color,
      ),
    );
    final bubble = Expanded(
      child: Column(
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 5),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  displaySender,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (!question && !positive)
                  Text(
                    tr(context, wasQuestion ? 'Question' : 'Update'),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                if (question || positive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tr(
                        context,
                        question
                            ? (adminView ? 'Question' : 'Question for you')
                            : resident
                            ? (adminView ? 'Reply received' : 'Reply sent')
                            : 'Observation verified',
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: background,
              border: Border.all(
                color: question
                    ? color.withValues(alpha: .3)
                    : positive
                    ? color.withValues(alpha: .22)
                    : p.outlineVariant.withValues(alpha: .55),
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(outgoing ? 18 : 5),
                bottomRight: Radius.circular(outgoing ? 5 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
                if (imageUrl?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SafeImage(imageUrl: imageUrl, height: 160),
                  ),
                  if (photoObservedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${tr(context, 'Photo observation time')}: ${localizedDateTime(context, photoObservedAt!)}',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.4,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 5, 3, 0),
            child: Text(
              createdAt == null
                  ? tr(context, 'Confirming time...')
                  : localizedClock(context, createdAt!),
              style: GoogleFonts.inter(
                fontSize: 10,
                height: 1.4,
                color: p.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: outgoing
            ? [bubble, const SizedBox(width: 7), avatar]
            : [avatar, const SizedBox(width: 7), bubble],
      ),
    );
  }
}

/// All essential submission information is visible without opening another
/// accordion. Original evidence is retained for an edited legacy submission.
class ResidentReportEvidenceCard extends StatelessWidget {
  final UserReport report;
  final RoadStatus? road;
  final bool adminView;
  const ResidentReportEvidenceCard({
    super.key,
    required this.report,
    this.road,
    this.adminView = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        evidence = submittedReportEvidence(report);
    final name = reportRoadName(evidence, road: road);
    final hasPhoto = evidence.imageUrl?.trim().isNotEmpty == true;
    final compact = !report.reviewOpen;
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: p.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: p.onSurfaceVariant),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, label),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: p.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ReportPanel(
      key: ValueKey('submission-preview-${report.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              context,
              adminView
                  ? 'What the resident sent'
                  : report.isFollowup
                  ? 'What you sent in this follow-up'
                  : 'What you sent',
            ),
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          if (hasPhoto && !compact) ...[
            ReportPhotoThumbnail(
              report: evidence,
              width: double.infinity,
              height: adminView ? 150 : 170,
              showExpandBadge: true,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhoto && compact) ...[
                ReportPhotoThumbnail(report: evidence),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  evidence.description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
              ),
            ],
          ),
          ReportRetainedPhotoNotice(report: evidence),
          const SizedBox(height: 8),
          if (!adminView)
            row(
              Icons.location_on_outlined,
              'Where',
              name == 'Unnamed residential road' ? tr(context, name) : name,
            ),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          row(
            Icons.schedule_outlined,
            adminView ? 'When the resident saw it' : 'When you saw it',
            evidence.observedAt == null
                ? tr(context, 'Observation time was not recorded.')
                : localizedDateTime(context, evidence.observedAt!),
          ),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          ReportReference(reportId: report.id),
          if (evidence.id != report.id || report.originalSubmission != null)
            Text(
              tr(context, 'Original submission'),
              style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
