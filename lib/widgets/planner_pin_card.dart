import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../services/admin_road_overview.dart';
import '../services/pin_road_context.dart';
import '../services/weather_service.dart';
import '../theme/app_palette.dart';
import 'road_condition_overview.dart';

class PlannerPinCard extends StatelessWidget {
  final bool forOrigin, moving, confirming, insideArea, roadsLive;
  final PinRoadMatch? match;
  final WeatherState weather;
  final VoidCallback? onConfirm;
  final String? placeName;
  final bool pinUnavailable;
  final VoidCallback? onRetry;
  const PlannerPinCard({
    super.key,
    required this.forOrigin,
    required this.moving,
    required this.confirming,
    required this.insideArea,
    required this.roadsLive,
    required this.weather,
    this.match,
    this.onConfirm,
    this.placeName,
    this.pinUnavailable = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Forty metres is a display proximity threshold, not route acceptance.
    final road = match != null && match!.meters <= 40 ? match!.road : null;
    final assessment = road == null
        ? null
        : AdminRoadAssessment(road, DateTime.now(), weather);
    final restricted = road?.status == 'not_passable';
    final color = restricted
        ? p.notPassable
        : assessment?.category == 'passable'
        ? p.passable
        : p.warning;
    return Container(
      key: const ValueKey('planner-pin-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(context, forOrigin ? 'Starting point' : 'Destination'),
                    style: TextStyle(
                      color: p.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    placeName ?? tr(context, 'Pinned Location'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (pinUnavailable) ...[
                    Text(
                      tr(
                        context,
                        'The selected point could not be read. Retry or move the map.',
                      ),
                      style: TextStyle(color: p.warning),
                    ),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, 'Retry selected point')),
                    ),
                  ] else if (moving)
                    Text(
                      tr(context, 'Move the map to position the pin.'),
                      style: TextStyle(color: p.onSurfaceVariant),
                    )
                  else if (!insideArea)
                    Text(
                      tr(context, 'Choose a point within the study area.'),
                      style: TextStyle(color: p.warning),
                    )
                  else if (road == null)
                    Text(
                      tr(
                        context,
                        'No monitored road identified near this pin.',
                      ),
                      style: TextStyle(color: p.onSurfaceVariant),
                    )
                  else ...[
                    Text(
                      '${tr(context, 'Nearby road')}: ${residentRoadTitle(road.name)}',
                      style: TextStyle(
                        color: p.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            restricted
                                ? Icons.block_outlined
                                : Icons.info_outline,
                            color: color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context, assessment!.summaryTitle),
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${tr(context, 'Updated')}: ${localizedAge(context, road.updatedAt, DateTime.now())}',
                                  style: TextStyle(
                                    color: p.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!roadsLive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr(
                            context,
                            'Saved road information. Check current conditions.',
                          ),
                          style: TextStyle(color: p.warning, fontSize: 12),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      context,
                      'Choosing a point does not confirm a safe route. The planner checks routes next.',
                    ),
                    style: TextStyle(
                      color: p.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: moving || confirming || !insideArea || pinUnavailable
                ? null
                : onConfirm,
            icon: confirming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 20),
            label: Text(
              tr(
                context,
                confirming
                    ? 'Confirming location...'
                    : forOrigin
                    ? 'Use this starting point'
                    : 'Use this destination',
              ),
              textAlign: TextAlign.center,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
