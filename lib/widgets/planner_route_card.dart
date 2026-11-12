import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/planned_route.dart';
import '../models/road_status.dart';
import '../l10n/formatters.dart';
import '../utils/time_utils.dart';
import '../theme/app_palette.dart';
import '../utils/navigation_units.dart';
import 'planner_preview_controls.dart';

class PlannerRouteCard extends StatelessWidget {
  final PlannedRoute route;
  final Widget? map;
  final VoidCallback? onPreview, onNavigate, onSelect;
  final bool compact;
  final List<RoadStatus> roadRecords;
  const PlannerRouteCard({
    super.key,
    required this.route,
    this.map,
    this.onPreview,
    this.onNavigate,
    this.onSelect,
    this.compact = false,
    this.roadRecords = const [],
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final unavailable = !route.canStartNavigation;
    final color = unavailable || route.safetyStatus == 'critical'
        ? p.error
        : route.needsCaution
        ? p.warning
        : p.passable;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr(context, previewRouteBadge(route)),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
    final distance = navigationDistance(
      route.distanceMeters ?? route.distanceMiles * 1609.34,
    );
    final now = DateTime.now();
    bool hasCheck(RoadStatus road) =>
        road.isVerified &&
        TimeUtils.hasRecordedTime(road.updatedAt) &&
        !road.updatedAt.isAfter(now);
    final hasRecordedCheck = roadRecords.any(hasCheck);
    final named =
        route.roadNames.isNotEmpty ||
        route.summary.trim().toLowerCase().startsWith('via ');
    final title = route.roadNames.isNotEmpty
        ? '${tr(context, 'Via')} ${route.roadNames.take(2).join(' · ')}'
        : navigationRouteLabel(route.summary);
    return Material(
      color: p.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(
          color: compact
              ? p.outlineVariant.withValues(alpha: .55)
              : p.primary.withValues(alpha: .45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: compact ? onSelect : null,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    badge,
                    Text(
                      '${previewRouteDuration(context, route)} · $distance',
                      style: TextStyle(color: p.onSurfaceVariant),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: p.primary),
                  ],
                ),
              ] else ...[
                Align(alignment: Alignment.centerLeft, child: badge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      previewRouteDuration(context, route),
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: p.onSurface,
                      ),
                    ),
                    Tooltip(
                      message: tr(context, 'Distance'),
                      child: Semantics(
                        label: '${tr(context, 'Distance')}: $distance',
                        excludeSemantics: true,
                        child: Text(
                          distance,
                          key: const ValueKey('planner-route-distance'),
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: p.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!named)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr(
                        context,
                        'Directions did not supply street names for this route.',
                      ),
                      style: TextStyle(
                        color: p.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .6),
                  ),
                ),
                _RouteInfoRow(
                  icon: unavailable
                      ? Icons.block_outlined
                      : route.needsCaution
                      ? Icons.info_outline
                      : Icons.check_rounded,
                  color: color,
                  text: tr(
                    context,
                    unavailable
                        ? 'Navigation unavailable for this route'
                        : route.conditionSummary,
                  ),
                ),
                const SizedBox(height: 10),
                _RouteInfoRow(
                  icon: Icons.schedule_outlined,
                  color: p.onSurfaceVariant,
                  text: tr(
                    context,
                    hasRecordedCheck
                        ? 'Road checks have individual times'
                        : 'Check time unavailable',
                  ),
                ),
                if (map != null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    key: const ValueKey('planner-route-preview'),
                    onTap: onPreview,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: (MediaQuery.sizeOf(context).width * .52).clamp(
                          180.0,
                          240.0,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            IgnorePointer(child: map!),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tr(context, 'TAP TO EXPAND'),
                                  style: TextStyle(
                                    color: p.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: p.surfaceContainerLowest,
                                child: Icon(
                                  Icons.fullscreen,
                                  color: p.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .6),
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  iconColor: p.primary,
                  collapsedIconColor: p.primary,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    tr(context, 'Route details'),
                    style: TextStyle(
                      color: p.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        tr(
                          context,
                          hasRecordedCheck
                              ? 'See recorded checks for nearby roads in Route details.'
                              : 'A clear warning summary does not mean a recent road inspection.',
                        ),
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (route.roadNames.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${tr(context, 'Street names from directions')}: ${route.roadNames.join(', ')}',
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (roadRecords.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr(context, 'Nearby road records'),
                          style: TextStyle(
                            color: p.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      for (final road in roadRecords.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  road.name,
                                  style: TextStyle(
                                    color: p.onSurface,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  hasCheck(road)
                                      ? '${tr(context, 'Recorded check')}: ${localizedDateTime(context, road.updatedAt)}'
                                      : tr(context, 'No verified check time'),
                                  style: TextStyle(
                                    color: p.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        tr(
                          context,
                          'These are nearby road records, not a single inspection of the entire route.',
                        ),
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (route.realAvoidedCount > 0)
                      Text(
                        '${route.realAvoidedCount} ${tr(context, 'flagged roads avoided compared with the baseline route')}',
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    for (final explanation in route.routeExplanations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: p.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                explanation,
                                style: TextStyle(
                                  color: p.onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('planner-start-navigation'),
                  onPressed: unavailable ? null : onNavigate,
                  icon: Icon(
                    unavailable
                        ? Icons.block
                        : route.needsCaution
                        ? Icons.warning_amber_rounded
                        : Icons.navigation_outlined,
                    size: 20,
                  ),
                  label: Text(
                    tr(
                      context,
                      unavailable
                          ? 'Navigation unavailable'
                          : route.needsCaution
                          ? 'Navigate with Caution'
                          : 'Start Navigation',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: route.needsCaution
                        ? p.warningContainer
                        : p.primary,
                    foregroundColor: route.needsCaution
                        ? p.onWarningContainer
                        : p.onPrimary,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteInfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteInfoRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              text,
              style: TextStyle(
                color: p.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
