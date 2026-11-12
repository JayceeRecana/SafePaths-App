import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/risk_config.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';

/// Presentation only: shortening an OSM label never changes the stored road ID.
String residentRoadTitle(String name) {
  final title = name
      .replaceFirst(RegExp(r'\s*\(OSM\s+\d+\)\s*$', caseSensitive: false), '')
      .trim();
  return title.toLowerCase() == 'unnamed residential'
      ? 'Unnamed residential road'
      : title;
}

/// Inspection age is advisory; an old recorded closure remains a closure.
bool roadNeedsRecheck(RoadStatus road, DateTime now) =>
    const ['partial', 'not_passable'].contains(road.status) &&
    now.difference(road.updatedAt).inMilliseconds >
        RiskConfig.getAdminReCheckThresholdHours(road.vulnerability) * 3600000;

class RoadIdentityHeader extends StatelessWidget {
  final RoadStatus road;
  final bool compact;
  final VoidCallback? onDismiss;
  const RoadIdentityHeader({
    super.key,
    required this.road,
    this.compact = false,
    this.onDismiss,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), title = residentRoadTitle(road.name);
    final largeText = MediaQuery.textScalerOf(context).scale(15) > 21;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.route_outlined, size: 20, color: p.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(context, 'Road status').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: p.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title == 'Unnamed residential road'
                    ? tr(context, title)
                    : title,
                key: ValueKey(
                  compact ? 'preview-road-name' : 'road-resident-title',
                ),
                maxLines: compact ? (largeText ? 1 : 2) : null,
                overflow: compact
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
                style: GoogleFonts.manrope(
                  fontSize: compact ? 15 : 20,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: p.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (onDismiss != null)
          IconButton(
            key: const ValueKey('preview-close'),
            tooltip: tr(context, 'Hide road preview'),
            onPressed: onDismiss,
            color: p.onSurfaceVariant,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

class RoadConditionPanel extends StatelessWidget {
  final RoadStatus road;
  final String statusText;
  final Color foreground, background;
  final IconData statusIcon;
  final DateTime? now;
  final bool compact;
  const RoadConditionPanel({
    super.key,
    required this.road,
    required this.statusText,
    required this.foreground,
    required this.background,
    required this.statusIcon,
    this.now,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), clock = now ?? DateTime.now();
    final recheck = roadNeedsRecheck(road, clock);
    return Container(
      key: const ValueKey('road-condition-banner'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          background.withValues(alpha: p.isDark ? .22 : .4),
          p.surfaceContainerLowest,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final stackBadge =
              box.maxWidth < 250 ||
              MediaQuery.textScalerOf(context).scale(13) > 18;
          final badge = Container(
            key: const ValueKey('road-recheck-notice'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: p.warningContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 12,
                  color: p.onWarningContainer,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tr(context, 'Needs recheck'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.onWarningContainer,
                    ),
                  ),
                ),
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      road.status == 'not_passable'
                          ? Icons.block_rounded
                          : statusIcon,
                      size: 20,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(context, statusText),
                          style: GoogleFonts.inter(
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${tr(context, 'Updated')} ${localizedAge(context, road.updatedAt, clock)}',
                          key: const ValueKey('road-update-age'),
                          style: GoogleFonts.inter(
                            fontSize: compact ? 12 : 13,
                            height: 1.3,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (recheck && !stackBadge) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: badge,
                    ),
                  ],
                ],
              ),
              if (recheck && stackBadge)
                Padding(
                  padding: const EdgeInsets.only(left: 45, top: 6),
                  child: Align(alignment: Alignment.centerLeft, child: badge),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RoadSectionHeading extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool community;
  const RoadSectionHeading({
    super.key,
    required this.label,
    required this.icon,
    this.community = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        accent = community ? p.passable : p.primary;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr(context, label).toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: p.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// One visual card; observation and report feeds retain their independent states.
class RoadCommunityCard extends StatelessWidget {
  final Widget observations, reports;
  const RoadCommunityCard({
    super.key,
    required this.observations,
    required this.reports,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: const ValueKey('road-community-updates'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RoadSectionHeading(
            label: 'Community updates',
            icon: Icons.people_alt_outlined,
            community: true,
          ),
          const SizedBox(height: 18),
          observations,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: p.outlineVariant.withValues(alpha: .5),
            ),
          ),
          reports,
        ],
      ),
    );
  }
}

class RoadConditionOverview extends StatelessWidget {
  final RoadStatus road;
  final String statusText;
  final Color statusBackground, statusColor;
  final IconData statusIcon;
  final bool unconfirmed;
  final DateTime? now;
  const RoadConditionOverview({
    super.key,
    required this.road,
    required this.statusText,
    required this.statusBackground,
    required this.statusColor,
    required this.statusIcon,
    required this.unconfirmed,
    this.now,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoadIdentityHeader(road: road),
        const SizedBox(height: 14),
        RoadConditionPanel(
          road: road,
          statusText: statusText,
          foreground: statusColor,
          background: statusBackground,
          statusIcon: statusIcon,
          now: now,
        ),
        if (unconfirmed) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.warningContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              tr(
                context,
                road.source == 'osm' && !road.isVerified
                    ? 'This road was imported and has not yet received a verified condition update.'
                    : 'The recorded condition needs current confirmation. Check the barangay update and its timestamp.',
              ),
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: p.onWarningContainer,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          key: const ValueKey('road-admin-update'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.outlineVariant.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RoadSectionHeading(
                label: 'Barangay update',
                icon: Icons.admin_panel_settings_outlined,
              ),
              const SizedBox(height: 14),
              Text(
                road.notes.trim().isNotEmpty &&
                        road.notes != 'Imported from OSM'
                    ? road.notes
                    : tr(
                        context,
                        'No barangay note has been added for this road.',
                      ),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: p.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
