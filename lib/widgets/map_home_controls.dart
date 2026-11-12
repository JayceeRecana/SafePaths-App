import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../models/road_status.dart';
import '../services/weather_service.dart';
import '../theme/app_palette.dart';
import 'user_avatar.dart';
import 'road_condition_overview.dart';

class MapOverlayPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const MapOverlayPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.of(context).surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: AppPalette.of(context).outlineVariant.withValues(alpha: .6),
      ),
    ),
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: .2),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class MapHomeHeader extends StatelessWidget {
  final String? photoUrl;
  final bool searching, busy;
  final TextEditingController controller;
  final String weatherLabel;
  final IconData weatherIcon;
  final bool severeWeather;
  final VoidCallback onProfile,
      onSettings,
      onStartSearch,
      onCloseSearch,
      onSearch,
      onWeather,
      onWeatherInfo;
  const MapHomeHeader({
    super.key,
    this.photoUrl,
    required this.searching,
    required this.busy,
    required this.controller,
    required this.weatherLabel,
    required this.weatherIcon,
    required this.severeWeather,
    required this.onProfile,
    required this.onSettings,
    required this.onStartSearch,
    required this.onCloseSearch,
    required this.onSearch,
    required this.onWeather,
    required this.onWeatherInfo,
  });
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final search = searching
        ? Row(
            children: [
              IconButton(
                tooltip: tr(context, 'Close search'),
                onPressed: onCloseSearch,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: palette.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: tr(context, 'Type road or area name...'),
                    filled: true,
                    fillColor: palette.surfaceContainerLow,
                    suffixIcon: IconButton(
                      tooltip: tr(context, 'Search area'),
                      onPressed: busy ? null : onSearch,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!busy) onSearch();
                  },
                ),
              ),
            ],
          )
        : SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onStartSearch,
              style: TextButton.styleFrom(
                foregroundColor: palette.onSurfaceVariant,
                backgroundColor: palette.surfaceContainerLow,
                minimumSize: const Size(48, 48),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.search, size: 20),
              label: Text(
                tr(context, 'Find a road or place'),
                style: GoogleFonts.inter(fontSize: 14),
              ),
            ),
          );
    final weather = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: onWeather,
          icon: Icon(weatherIcon, size: 20),
          style: TextButton.styleFrom(
            foregroundColor: severeWeather
                ? palette.onWarningContainer
                : palette.primary,
            backgroundColor: severeWeather
                ? palette.warningContainer
                : palette.primary.withValues(alpha: .08),
            minimumSize: const Size(48, 48),
          ),
          label: Text(
            weatherLabel,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (severeWeather)
          IconButton(
            tooltip: tr(context, 'Weather advisory'),
            onPressed: onWeatherInfo,
            color: palette.onSurface,
            icon: const Icon(Icons.info_outline),
          ),
      ],
    );
    return MapOverlayPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
            child: Row(
              children: [
                Semantics(
                  label: tr(context, 'Profile'),
                  button: true,
                  child: InkWell(
                    onTap: onProfile,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: UserAvatar(
                        photoUrl: photoUrl,
                        size: 36,
                        iconSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'SafePaths',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Settings'),
                  onPressed: onSettings,
                  color: palette.onSurfaceVariant,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: palette.outlineVariant.withValues(alpha: .5),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 280 ||
                    weatherLabel.length > 18 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: weather),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    weather,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RoadConditionsButton extends StatelessWidget {
  final VoidCallback onBrowseRoads;
  const RoadConditionsButton({super.key, required this.onBrowseRoads});
  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppPalette.of(context).surface,
      builder: (sheetContext) => RoadConditionsSheet(
        onBrowseRoads: () {
          Navigator.pop(sheetContext);
          onBrowseRoads();
        },
      ),
    ),
    style: FilledButton.styleFrom(
      backgroundColor: AppPalette.of(context).surfaceContainerLowest,
      foregroundColor: AppPalette.of(context).primary,
      minimumSize: const Size(48, 48),
      elevation: 2,
    ),
    icon: const Icon(Icons.layers_outlined),
    label: Text(
      tr(context, 'Road conditions'),
      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class RoadConditionsSheet extends StatelessWidget {
  final VoidCallback onBrowseRoads;
  const RoadConditionsSheet({super.key, required this.onBrowseRoads});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, 'Road conditions'),
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Map colors show recorded conditions. Check road details and update times before travel.',
            ),
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: p.onSurfaceVariant,
            ),
          ),
          _LegendRow(
            color: p.passable,
            title: 'Passable',
            description:
                'The last recorded update marks this road as passable. Conditions can change.',
          ),
          _LegendRow(
            color: p.partial,
            title: 'Partial',
            description:
                'Restrictions or flooding were recorded. Check the road details for your vehicle.',
          ),
          _LegendRow(
            color: p.notPassable,
            title: 'Not passable',
            description:
                'A road closure was recorded. Do not use the closed segment.',
          ),
          _LegendRow(
            color: p.partial,
            title: 'Needs confirmation',
            description:
                'The condition is unreviewed, outdated or awaiting verification. This is an advisory, not a confirmed closure.',
            dashed: true,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onBrowseRoads,
            icon: const Icon(Icons.list_alt),
            label: Text(tr(context, 'Browse roads')),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String title, description;
  final bool dashed;
  const _LegendRow({
    required this.color,
    required this.title,
    required this.description,
    this.dashed = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: SizedBox(
            width: 30,
            height: 6,
            child: Row(
              children: [
                for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, title),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, description),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MapRoadPreview extends StatelessWidget {
  final RoadStatus road;
  final WeatherState weather;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;
  final DateTime? now;
  const MapRoadPreview({
    super.key,
    required this.road,
    required this.weather,
    required this.onOpen,
    this.onDismiss,
    this.now,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), clock = now ?? DateTime.now();
    final uncertain = road.needsStatusConfirmation(weather, currentTime: clock);
    final status = uncertain
        ? 'Needs confirmation'
        : switch (road.status) {
            'passable' => 'Passable',
            'partial' => 'Partial',
            'not_passable' => 'Not passable',
            _ => 'Needs confirmation',
          };
    final color = uncertain
        ? p.partial
        : switch (road.status) {
            'passable' => p.passable,
            'partial' => p.partial,
            'not_passable' => p.notPassable,
            _ => p.partial,
          };
    final hasNote =
        road.notes.trim().isNotEmpty && road.notes != 'Imported from OSM';
    final recheck = roadNeedsRecheck(road, clock);
    final notePreview = road.notes.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: MapOverlayPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
              child: InkWell(
                onTap: onOpen,
                child: RoadIdentityHeader(
                  road: road,
                  compact: true,
                  onDismiss: onDismiss,
                ),
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                key: const ValueKey('preview-summary-scroll'),
                primary: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: onOpen,
                        child: RoadConditionPanel(
                          road: road,
                          statusText: status,
                          foreground: color,
                          background: Color.alphaBlend(
                            color.withValues(alpha: .12),
                            p.surfaceContainerLowest,
                          ),
                          statusIcon: uncertain
                              ? Icons.help_outline
                              : Icons.traffic_outlined,
                          now: clock,
                          compact: true,
                        ),
                      ),
                      if (hasNote) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: onOpen,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: recheck
                                  ? p.warningContainer
                                  : p.surfaceContainerLow,
                              border: Border(
                                left: BorderSide(
                                  width: 2,
                                  color: recheck ? p.partial : p.primary,
                                ),
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final noteStyle = GoogleFonts.inter(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: p.onSurface,
                                );
                                final painter = TextPainter(
                                  text: TextSpan(
                                    text: notePreview,
                                    style: noteStyle,
                                  ),
                                  maxLines: 2,
                                  ellipsis: String.fromCharCode(0x2026),
                                  textDirection: Directionality.of(context),
                                  textScaler: MediaQuery.textScalerOf(context),
                                )..layout(maxWidth: box.maxWidth);
                                final truncated = painter.didExceedMaxLines;
                                painter.dispose();
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      tr(
                                        context,
                                        'Barangay note',
                                      ).toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        letterSpacing: .8,
                                        fontWeight: FontWeight.w600,
                                        color: recheck
                                            ? p.onWarningContainer
                                            : p.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notePreview,
                                      key: const ValueKey('preview-note'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: noteStyle,
                                    ),
                                    if (truncated)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          tr(context, 'Read more'),
                                          key: const ValueKey(
                                            'preview-read-more',
                                          ),
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: p.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: p.outlineVariant.withValues(alpha: .25)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: TextButton(
                key: const ValueKey('preview-view-details'),
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  foregroundColor: p.primary,
                  backgroundColor: p.primary.withValues(alpha: .1),
                  minimumSize: const Size(double.infinity, 48),
                  alignment: Alignment.center,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        tr(context, 'View details'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 18),
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

/// Reserve space for actions and the preview together, keeping its footer visible.
class MapHomeBottomOverlay extends StatelessWidget {
  final Widget actions;
  final Widget? preview;
  const MapHomeBottomOverlay({super.key, required this.actions, this.preview});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(alignment: Alignment.centerRight, child: actions),
      if (preview != null) ...[
        const SizedBox(height: 8),
        Flexible(fit: FlexFit.loose, child: preview!),
      ],
    ],
  );
}

class MapQuickActions extends StatelessWidget {
  final VoidCallback onLocate, onFullscreen, onReport;
  final bool horizontal, locating, canLocate;
  const MapQuickActions({
    super.key,
    required this.onLocate,
    required this.onFullscreen,
    required this.onReport,
    this.horizontal = false,
    this.locating = false,
    this.canLocate = true,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget action(
      String label,
      IconData icon,
      VoidCallback? onTap, {
      bool filled = false,
    }) => Material(
      color: filled ? p.primary : p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      child: SizedBox(
        width: 56,
        height: 56,
        child: IconButton(
          tooltip: tr(context, label),
          onPressed: onTap,
          color: filled ? p.onPrimary : p.primary,
          icon: locating && label == 'Locate me'
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 26),
        ),
      ),
    );
    final children = [
      action(
        'Locate me',
        Icons.my_location,
        locating || !canLocate ? null : onLocate,
      ),
      SizedBox(width: horizontal ? 12 : 0, height: horizontal ? 0 : 12),
      action('Fullscreen map', Icons.fullscreen, onFullscreen),
      SizedBox(width: horizontal ? 12 : 0, height: horizontal ? 0 : 12),
      action(
        'Report road conditions',
        Icons.add_alert_outlined,
        onReport,
        filled: true,
      ),
    ];
    return horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
