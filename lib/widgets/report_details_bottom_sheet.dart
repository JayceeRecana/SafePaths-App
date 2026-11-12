import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import 'report_submission_preview.dart';
import 'report_workflow_ui.dart';
import 'safe_image.dart';

/// Community evidence only. Private conversations and admin decisions live in
/// their account-scoped screens, never in this public road entry point.
class ReportDetailsBottomSheet extends StatelessWidget {
  final UserReport report;
  const ReportDetailsBottomSheet({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final name = reportRoadName(report);
    final old = ReportFreshness.isOutdated(report, DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReportActionHeading(
                    title: 'Resident observation',
                    icon: Icons.description_outlined,
                    showClose: true,
                    onClose: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    name == 'Unnamed residential road'
                        ? tr(context, name)
                        : name,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ReportPanel(
                    tint: p.warning.withValues(alpha: p.isDark ? .12 : .08),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 19, color: p.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              old
                                  ? 'This observation is old. Check the latest road condition before travel.'
                                  : 'A resident observation is not a verified road condition. Check the latest barangay update.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: p.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ReportPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, 'What the resident reported'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (report.imageUrl?.trim().isNotEmpty == true) ...[
                          SafeImage(
                            imageUrl: report.imageUrl,
                            width: double.infinity,
                            height: 190,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          if (report.photoSubmittedAt != null &&
                              report.observedAt != null &&
                              report.observedAt!.difference(
                                    report.photoSubmittedAt!,
                                  ) >=
                                  const Duration(minutes: 1)) ...[
                            const SizedBox(height: 8),
                            Text(
                              tr(context, 'Photo from an earlier submission'),
                              style: TextStyle(
                                fontSize: 12,
                                color: p.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                        ],
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
                        const SizedBox(height: 14),
                        Text(
                          '${tr(context, 'Resident-selected flood level')}: ${tr(context, const ['Low', 'Medium', 'High'].contains(report.severity) ? report.severity : 'Not recorded')}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${tr(context, reportTimesShareMinute(report) ? 'Observed and submitted' : 'Observed')}: ${report.observedAt != null ? localizedDateTime(context, report.observedAt!) : tr(context, 'Observation time was not recorded.')}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                        if (!reportTimesShareMinute(report)) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${tr(context, 'Submitted')}: ${localizedDateTime(context, report.createdAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Close')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
