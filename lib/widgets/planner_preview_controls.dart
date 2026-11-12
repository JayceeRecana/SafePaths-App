import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../models/planned_route.dart';
import '../theme/app_palette.dart';
import '../utils/navigation_units.dart';

class PreviewRouteOption {
  final PlannedRoute route;
  final String label;
  const PreviewRouteOption(this.route, this.label);
}

String previewRouteDuration(BuildContext context, PlannedRoute route) =>
    route.durationMin < 0
    ? tr(context, 'Unknown time')
    : route.durationMin == 0
    ? tr(context, 'Less than 1 min')
    : '${route.durationMin} ${tr(context, 'min')}';

String previewRouteBadge(PlannedRoute route) {
  if (!route.canStartNavigation) return 'Navigation unavailable';
  if (route.safetyStatus == 'critical') return 'Critical risk';
  if (route.safetyStatus != 'safe' && route.safetyStatus != 'unverified_risk' ||
      route.totalRisk > 0) {
    return 'Caution';
  }
  if (route.hasUnverifiedConditions) return 'Unconfirmed';
  return route.needsCaution ? 'Caution' : 'No known warnings';
}

class RoutePreviewHeader extends StatelessWidget {
  final String title;
  final PlannedRoute route;
  final VoidCallback onBack;
  const RoutePreviewHeader({
    super.key,
    required this.title,
    required this.route,
    required this.onBack,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('route-preview-back'),
              tooltip: tr(context, 'Back'),
              onPressed: onBack,
              color: p.onSurface,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: MediaQuery.sizeOf(context).height < 500 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${previewRouteDuration(context, route)} \u00b7 ${navigationDistance(route.distanceMeters ?? route.distanceMiles * 1609.34)}',
                    maxLines: MediaQuery.sizeOf(context).height < 500 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.primary,
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

class RoutePreviewPanel extends StatefulWidget {
  final List<PreviewRouteOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onNavigate;
  final bool opening;
  final bool liveDataUnavailable;
  const RoutePreviewPanel({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
    required this.onNavigate,
    this.opening = false,
    this.liveDataUnavailable = false,
  });
  @override
  State<RoutePreviewPanel> createState() => _RoutePreviewPanelState();
}

class _RoutePreviewPanelState extends State<RoutePreviewPanel> {
  bool _expanded = false;
  PlannedRoute get route => widget.options[widget.selectedIndex].route;
  @override
  void didUpdateWidget(covariant RoutePreviewPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.options[old.selectedIndex].route.points, route.points)) {
      _expanded = false;
    }
  }

  double _textHeight(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
    int lines,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: lines,
    )..layout(maxWidth: width);
    final result = painter.height;
    painter.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), current = route;
    final critical =
        !current.canStartNavigation || current.safetyStatus == 'critical';
    final caution = current.needsCaution || widget.liveDataUnavailable;
    final foreground = critical
        ? p.onErrorContainer
        : caution
        ? p.onWarningContainer
        : p.onSurface;
    final background = critical
        ? p.errorContainer
        : caution
        ? p.warningContainer
        : p.surfaceContainerLow;
    final explanations =
        (current.routeExplanations.isNotEmpty
                ? current.routeExplanations
                : current.hazardAlerts)
            .toSet()
            .toList();
    final showUnconfirmed = current.unverifiedRoadCount > 0;
    final unconfirmedText =
        '${current.unverifiedRoadCount} ${tr(context, current.unverifiedRoadCount == 1 ? 'road has unconfirmed conditions' : 'roads have unconfirmed conditions')}';
    final title = !current.canStartNavigation
        ? 'Navigation unavailable for this route'
        : current.safetyStatus == 'critical'
        ? 'Critical risk on this route'
        : showUnconfirmed &&
              (current.safetyStatus == 'safe' ||
                  current.safetyStatus == 'unverified_risk') &&
              current.totalRisk == 0
        ? unconfirmedText
        : widget.liveDataUnavailable
        ? 'Live conditions need confirmation'
        : current.needsCaution
        ? 'Review current route conditions'
        : 'No known route warnings';
    final message = !current.canStartNavigation
        ? 'Choose another route or review updated road conditions.'
        : widget.liveDataUnavailable
        ? 'Live road or weather data is unavailable or outdated. Confirm current conditions before travel.'
        : title == unconfirmedText
        ? 'Check local updates before travel.'
        : current.conditionSummary;
    return Material(
      key: const ValueKey('route-options-panel'),
      color: p.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      elevation: 5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final large = MediaQuery.textScalerOf(context).scale(14) > 20;
                final cardWidth = large ? 200.0 : 132.0;
                final labelStyle = GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.onSurface,
                );
                final timeStyle = GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: p.onSurface,
                );
                final metricStyle = GoogleFonts.inter(
                  fontSize: 12,
                  color: p.onSurfaceVariant,
                );
                final badgeStyle = GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                );
                var cardHeight = 0.0;
                for (final option in widget.options) {
                  final height =
                      24 +
                      _textHeight(
                        context,
                        option.label,
                        labelStyle,
                        cardWidth - 24,
                        2,
                      ) +
                      5 +
                      _textHeight(
                        context,
                        previewRouteDuration(context, option.route),
                        timeStyle,
                        cardWidth - 24,
                        2,
                      ) +
                      2 +
                      _textHeight(
                        context,
                        navigationDistance(
                          option.route.distanceMeters ??
                              option.route.distanceMiles * 1609.34,
                        ),
                        metricStyle,
                        cardWidth - 24,
                        2,
                      ) +
                      8 +
                      8 +
                      _textHeight(
                        context,
                        tr(context, previewRouteBadge(option.route)),
                        badgeStyle,
                        cardWidth - 40,
                        2,
                      );
                  if (height > cardHeight) cardHeight = height;
                }
                final more =
                    widget.options.length * (cardWidth + 8) - 8 >
                    bounds.maxWidth - 32;
                return CustomScrollView(
                  key: const ValueKey('route-options-scroll'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${widget.options.length} ${tr(context, widget.options.length == 1 ? 'route option' : 'route options')}',
                                    key: const ValueKey('route-option-count'),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: p.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (more)
                                  Flexible(
                                    child: Text(
                                      '${tr(context, 'Swipe for more')} \u00bb',
                                      textAlign: TextAlign.right,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: p.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: cardHeight,
                              child: ListView.separated(
                                key: const ValueKey('route-choice-carousel'),
                                scrollDirection: Axis.horizontal,
                                itemCount: widget.options.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final option = widget.options[index],
                                      selected = index == widget.selectedIndex;
                                  final badge =
                                      widget.liveDataUnavailable &&
                                          previewRouteBadge(option.route) ==
                                              'No known warnings'
                                      ? 'Unconfirmed'
                                      : previewRouteBadge(option.route);
                                  final severe =
                                      !option.route.canStartNavigation ||
                                      option.route.safetyStatus == 'critical';
                                  final badgeForeground = severe
                                      ? p.onErrorContainer
                                      : (option.route.needsCaution ||
                                            widget.liveDataUnavailable)
                                      ? p.onWarningContainer
                                      : p.onSurfaceVariant;
                                  final badgeBackground = severe
                                      ? p.errorContainer
                                      : (option.route.needsCaution ||
                                            widget.liveDataUnavailable)
                                      ? p.warningContainer
                                      : p.surfaceContainerHigh;
                                  return SizedBox(
                                    width: cardWidth,
                                    child: Semantics(
                                      selected: selected,
                                      button: true,
                                      child: Material(
                                        color: selected
                                            ? Color.alphaBlend(
                                                p.primary.withValues(
                                                  alpha: .07,
                                                ),
                                                p.surfaceContainerLowest,
                                              )
                                            : p.surfaceContainerLowest,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          side: BorderSide(
                                            color: selected
                                                ? p.primary
                                                : p.outlineVariant.withValues(
                                                    alpha: .5,
                                                  ),
                                            width: selected ? 2 : 1,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          key: ValueKey('route-option-$index'),
                                          onTap: widget.opening
                                              ? null
                                              : () => widget.onSelect(index),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  option.label,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: labelStyle.copyWith(
                                                    color: selected
                                                        ? p.primary
                                                        : p.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  previewRouteDuration(
                                                    context,
                                                    option.route,
                                                  ),
                                                  maxLines: 2,
                                                  style: timeStyle,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  navigationDistance(
                                                    option
                                                            .route
                                                            .distanceMeters ??
                                                        option
                                                                .route
                                                                .distanceMiles *
                                                            1609.34,
                                                  ),
                                                  maxLines: 2,
                                                  style: metricStyle,
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: badgeBackground,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    tr(context, badge),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: badgeStyle.copyWith(
                                                      color: badgeForeground,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: const ValueKey('selected-route-conditions'),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: background,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        critical
                                            ? Icons.warning_rounded
                                            : Icons.info_outline,
                                        size: 20,
                                        color: foreground,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title == unconfirmedText
                                                  ? title
                                                  : tr(context, title),
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w700,
                                                color: foreground,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              tr(context, message),
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: foreground,
                                              ),
                                            ),
                                            if (showUnconfirmed &&
                                                title != unconfirmedText) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                unconfirmedText,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  height: 1.4,
                                                  color: foreground,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (explanations.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Divider(
                                      height: 1,
                                      color: foreground.withValues(alpha: .18),
                                    ),
                                    TextButton(
                                      key: const ValueKey(
                                        'route-conditions-toggle',
                                      ),
                                      onPressed: () => setState(
                                        () => _expanded = !_expanded,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: p.primary,
                                        minimumSize: const Size(
                                          double.infinity,
                                          48,
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tr(
                                                context,
                                                _expanded
                                                    ? 'Hide route conditions'
                                                    : 'View route conditions',
                                              ),
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            _expanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverList.builder(
                          itemCount: explanations.length,
                          itemBuilder: (context, index) {
                            final explanation = explanations[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    explanation.startsWith('Avoids')
                                        ? Icons.shield_outlined
                                        : explanation.contains('Unverified')
                                        ? Icons.help_outline
                                        : Icons.warning_amber_rounded,
                                    size: 16,
                                    color: explanation.startsWith('Avoids')
                                        ? p.passable
                                        : p.partial,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      explanation,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: p.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: FilledButton.icon(
              key: const ValueKey('preview-start-navigation'),
              onPressed: !current.canStartNavigation || widget.opening
                  ? null
                  : widget.onNavigate,
              style: FilledButton.styleFrom(
                backgroundColor: caution ? p.onWarningContainer : p.primary,
                foregroundColor: caution ? p.warningContainer : p.onPrimary,
                disabledBackgroundColor: p.surfaceContainerHigh,
                disabledForegroundColor: p.onSurfaceVariant,
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: widget.opening
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: caution ? p.warningContainer : p.onPrimary,
                      ),
                    )
                  : Icon(
                      !current.canStartNavigation
                          ? Icons.block
                          : caution
                          ? Icons.warning_amber_rounded
                          : Icons.navigation_outlined,
                      size: 20,
                    ),
              label: Text(
                tr(
                  context,
                  !current.canStartNavigation
                      ? 'Navigation unavailable'
                      : caution
                      ? 'Navigate with Caution'
                      : 'Start Navigation',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
