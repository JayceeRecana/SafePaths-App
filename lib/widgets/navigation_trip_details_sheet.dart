import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import 'navigation_hud.dart';

/// A bounded, live trip summary. Only its body scrolls; dismissal stays visible.
class NavigationTripDetailsSheet extends StatelessWidget {
  const NavigationTripDetailsSheet({
    super.key,
    required this.destination,
    required this.vehicle,
    required this.conditionSummary,
    required this.scoreLabel,
    required this.stepTiming,
    required this.paused,
    required this.onClose,
    this.notice,
    this.gpsMessage,
    this.unconfirmedRoads = const [],
    this.hazardAlerts = const [],
    this.routeUpdate,
    this.updatedAt,
    this.showDetour = false,
    this.onDetour,
  });

  final String destination, vehicle, conditionSummary, scoreLabel;
  final bool stepTiming, paused, showDetour;
  final NavigationNotice? notice;
  final String? gpsMessage, routeUpdate, updatedAt;
  final List<String> unconfirmedRoads, hazardAlerts;
  final VoidCallback onClose;
  final VoidCallback? onDetour;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget section(Widget child) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .4)),
      ),
      child: child,
    );
    Widget disclosure(String title, IconData icon, List<Widget> children) =>
        Material(
          color: p.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: p.outlineVariant.withValues(alpha: .4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey(title),
            leading: Icon(icon, color: p.primary, size: 20),
            title: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: p.onSurface,
              ),
            ),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 3,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            shape: const Border(),
            collapsedShape: const Border(),
            children: children,
          ),
        );
    return Material(
      key: const ValueKey('navigation-trip-details-sheet'),
      color: p.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.45,
          color: p.onSurface,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.route_outlined,
                      color: p.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(context, 'Trip details'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Close trip details'),
                    onPressed: onClose,
                    color: p.onSurface,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('navigation-trip-details-body'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  section(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${tr(context, 'Destination')}: $destination',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${tr(context, 'Travel mode')}: $vehicle',
                          style: TextStyle(color: p.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(context, 'Review details when safely stopped.'),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (notice != null) ...[
                    const SizedBox(height: 12),
                    NavigationStatusCard(notice: notice!),
                  ],
                  if (gpsMessage != null) ...[
                    const SizedBox(height: 12),
                    section(Text(gpsMessage!)),
                  ],
                  const SizedBox(height: 12),
                  section(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, 'Route conditions'),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(conditionSummary),
                        for (final alert in hazardAlerts) ...[
                          const SizedBox(height: 8),
                          Text(alert),
                        ],
                      ],
                    ),
                  ),
                  if (unconfirmedRoads.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    disclosure(
                      '${tr(context, 'Unconfirmed road segments')} (${unconfirmedRoads.length})',
                      Icons.warning_amber_rounded,
                      [
                        for (var i = 0; i < unconfirmedRoads.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i + 1}.',
                                  style: TextStyle(color: p.onSurfaceVariant),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(unconfirmedRoads[i])),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (routeUpdate != null) ...[
                    const SizedBox(height: 12),
                    section(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr(context, 'Latest route update'),
                            style: TextStyle(
                              color: p.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(routeUpdate!),
                          if (updatedAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              updatedAt!,
                              style: TextStyle(color: p.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  disclosure(tr(context, 'About estimates'), Icons.schedule_outlined, [
                    Text(
                      tr(
                        context,
                        stepTiming
                            ? 'Time remaining is estimated from route step durations and GPS progress.'
                            : 'Time remaining is estimated from the original route time and distance remaining.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'This estimate does not include live traffic or waiting time.',
                      ),
                    ),
                    if (paused) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          context,
                          'These estimates describe the previous route or last matched position until navigation resumes.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(scoreLabel),
                    Text(
                      tr(
                        context,
                        'The route score is a model rating, not a guarantee of road safety.',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  disclosure(tr(context, 'Map guide'), Icons.layers_outlined, [
                    Text(
                      tr(
                        context,
                        'Map: blue shows the remaining route; grey shows the travelled part. Red roads are not passable; dashed roads have unconfirmed conditions.',
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: p.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: onClose,
                        child: Text(tr(context, 'Close')),
                      ),
                    ),
                    if (showDetour) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: onDetour,
                          child: Text(
                            tr(context, 'Find detour'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
