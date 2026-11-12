import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../models/user_profile.dart';
import '../services/sync_health.dart';
import '../services/report_followup_service.dart';
import '../theme/app_palette.dart';
import '../utils/report_freshness.dart';
import 'user_avatar.dart';

/// The report feed's connection state is independent of the road's condition.
class RoadReportsSection extends StatelessWidget {
  final String roadId;
  final List<UserReport> reports;
  final List<UserProfile> users;
  final SyncCondition syncCondition;
  final VoidCallback onRetry;
  final ValueChanged<UserReport> onOpen;
  final DateTime? now;
  final bool embedded;

  const RoadReportsSection({
    super.key,
    required this.roadId,
    required this.reports,
    required this.syncCondition,
    required this.onRetry,
    required this.onOpen,
    this.users = const [],
    this.now,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final clock = now ?? DateTime.now();
    final items = ReportFreshness.awaitingReviewForRoad(reports, roadId, clock);
    final live = syncCondition == SyncCondition.live;
    final checking = syncCondition == SyncCondition.connecting;
    final message = switch (syncCondition) {
      SyncCondition.connecting => 'Checking reports for this road...',
      SyncCondition.cached =>
        'Showing saved reports. Reconnect to check the latest reports.',
      SyncCondition.failed =>
        'Reports could not be refreshed. The latest report count is unknown.',
      SyncCondition.live => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                tr(context, 'Reports awaiting review'),
                style: GoogleFonts.manrope(
                  fontSize: embedded ? 16 : 18,
                  fontWeight: FontWeight.w700,
                  color: palette.onSurface,
                ),
              ),
            ),
            if (live && items.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(
                key: const ValueKey('road-report-count'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'Observations from the last 24 hours awaiting admin review.',
          ),
          style: GoogleFonts.inter(
            fontSize: 13,
            color: palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (message != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (checking) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                Text(tr(context, message)),
                if (!checking)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr(context, 'Retry reports')),
                  ),
              ],
            ),
          ),
        if (live && items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: embedded
                  ? palette.surfaceContainerLow
                  : palette.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: embedded
                  ? null
                  : Border.all(color: palette.outlineVariant),
            ),
            child: Text(
              tr(
                context,
                'No recent reports are awaiting review for this road.',
              ),
              style: GoogleFonts.inter(color: palette.onSurfaceVariant),
            ),
          ),
        for (final report in items)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Builder(
              builder: (context) {
                final profile = users
                    .where((user) => user.id == report.userId)
                    .firstOrNull;
                return _ReportItem(
                  key: ValueKey('road-report-${report.id}'),
                  name: profile?.name.isNotEmpty == true
                      ? profile!.name
                      : tr(context, 'Resident report'),
                  photoUrl: profile?.photoUrl,
                  time:
                      '${tr(context, 'Observed')} ${localizedAge(context, ReportFreshness.observedAt(report), clock)}',
                  comment: report.description,
                  severity: report.severity,
                  conditionLabel: report.isFollowup
                      ? tr(context, followupChangeLabel(report.conditionChange))
                      : null,
                  historical: report.isHistoricalFollowup,
                  onTap: () => onOpen(report),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        Text(
          tr(context, 'Resident reports do not confirm that a road is safe.'),
          style: GoogleFonts.inter(
            fontSize: 12,
            color: palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReportItem extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String time;
  final String comment;
  final String severity;
  final String? conditionLabel;
  final bool historical;
  final VoidCallback? onTap;

  const _ReportItem({
    super.key,
    required this.name,
    this.photoUrl,
    required this.time,
    required this.comment,
    required this.severity,
    this.conditionLabel,
    this.historical = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color severityColor = AppPalette.of(context).secondary;
    IconData severityIcon = Icons.water_drop_outlined;

    if (severity == 'Medium') {
      severityColor = AppPalette.of(context).partial;
      severityIcon = Icons.warning_amber_rounded;
    } else if (severity == 'High') {
      severityColor = AppPalette.of(context).notPassable;
      severityIcon = Icons.water_damage;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.of(
          context,
        ).surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.of(context).outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: UserAvatar(
                        photoUrl: photoUrl,
                        size: 40,
                        iconSize: 20,
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: severityColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(severityIcon, size: 9, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            time,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (conditionLabel != null) ...[
                        Text(
                          '${tr(context, 'Follow-up')}: $conditionLabel',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.of(context).primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (historical)
                        Text(
                          tr(
                            context,
                            'The road was reviewed separately. This observation still awaits its own review.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppPalette.of(context).onSurfaceVariant,
                          ),
                        ),
                      Text(
                        comment,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppPalette.of(context).onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
