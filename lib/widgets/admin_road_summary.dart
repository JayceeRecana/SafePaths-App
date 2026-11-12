import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../services/admin_road_overview.dart';
import '../services/report_workload.dart';
import '../services/sync_health.dart';
import '../theme/app_palette.dart';
import 'road_condition_overview.dart' show residentRoadTitle;

Color adminRoadColor(BuildContext context, String category) {
  final p = AppPalette.of(context);
  return switch (category) {
    'not_passable' => p.error,
    'partial' => p.warning,
    'passable' => p.passable,
    _ => p.onSurfaceVariant,
  };
}

class AdminDataNotice extends StatelessWidget {
  final String label;
  final SyncCondition condition;
  final bool hasRecords;
  final VoidCallback? onRetry;
  const AdminDataNotice({
    super.key,
    required this.label,
    required this.condition,
    required this.hasRecords,
    this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), live = condition == SyncCondition.live;
    final message = live
        ? 'Live updates'
        : hasRecords
        ? 'Saved data; current information is not confirmed.'
        : condition == SyncCondition.connecting
        ? 'Connecting; counts are not available yet.'
        : 'Data unavailable. Refresh to retry.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${tr(context, label)} \u00b7 ${tr(context, message)}',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: p.onSurfaceVariant,
              ),
            ),
          ),
          if (!live && condition != SyncCondition.connecting && onRetry != null)
            IconButton(
              tooltip: tr(context, 'Refresh'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 19),
            ),
        ],
      ),
    );
  }
}

class AdminRoadSummary extends StatelessWidget {
  final AdminRoadAssessment assessment;
  final ReportWorkload? workload;
  final bool selected, riskFresh;
  final VoidCallback? onTap, onReports;
  final bool reportsLive;
  final Widget? trailing;
  const AdminRoadSummary({
    super.key,
    required this.assessment,
    this.workload,
    this.selected = false,
    this.riskFresh = false,
    this.onTap,
    this.onReports,
    this.reportsLive = false,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        road = assessment.road,
        name = residentRoadTitle(assessment.road.name),
        color = assessment.currentConditionUnknown
            ? p.warning
            : adminRoadColor(context, assessment.category);
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Material(
        color: selected
            ? p.primary.withValues(alpha: p.isDark ? .16 : .06)
            : p.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected
                ? p.primary
                : p.outlineVariant.withValues(alpha: .4),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
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
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: p.onSurface,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AdminRoadConditionDetails(assessment: assessment),
                ),
                if (road.riskCategory != 'Safe' && road.riskScore > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${tr(context, 'Predicted risk')}: ${tr(context, road.riskCategory)}${riskFresh ? '' : ' \u00b7 ${tr(context, 'Saved prediction')}'}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (onReports != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onReports,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(tr(context, 'Reports for this road')),
                  ),
                  Text(
                    workload != null && workload!.open.isNotEmpty
                        ? '${tr(context, 'Needs admin action')}: ${workload!.needsAdmin} \u00b7 ${tr(context, 'Waiting for resident')}: ${workload!.waiting}'
                        : tr(
                            context,
                            reportsLive
                                ? 'No active reports for this road.'
                                : 'Report workload is not confirmed current.',
                          ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared by list cards and the update form. A saved map default is never
/// presented as a previously verified condition.
class AdminRoadConditionDetails extends StatelessWidget {
  final AdminRoadAssessment assessment;
  const AdminRoadConditionDetails({super.key, required this.assessment});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = assessment.currentConditionUnknown
        ? p.warning
        : adminRoadColor(context, assessment.category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, 'Road condition'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: p.primary,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                assessment.currentConditionUnknown
                    ? Icons.help_outline
                    : switch (assessment.road.status) {
                        'not_passable' => Icons.block,
                        'partial' => Icons.warning_amber_rounded,
                        _ => Icons.check_circle_outline,
                      },
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(context, assessment.summaryTitle),
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (assessment.knownTime)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: p.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${tr(context, assessment.historyLabel)}: ${localizedAge(context, assessment.road.updatedAt, assessment.now)}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: p.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (assessment.summaryExplanation != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(context, assessment.summaryExplanation!),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: p.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
