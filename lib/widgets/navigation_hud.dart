import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

enum NavigationTone { information, caution, danger, success }

/// One primary notice. Secondary conditions belong in its explanation/details,
/// rather than a stack of independently positioned banners.
class NavigationNotice {
  final String title, detail;
  final NavigationTone tone;
  final IconData icon;
  final bool busy;
  final List<Widget> actions;
  const NavigationNotice({
    required this.title,
    required this.detail,
    this.tone = NavigationTone.information,
    this.icon = Icons.info_outline,
    this.busy = false,
    this.actions = const [],
  });
}

class NavigationGuidanceCard extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  final bool busy;
  final NavigationTone tone;
  final Widget? action;
  const NavigationGuidanceCard({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    this.busy = false,
    this.tone = NavigationTone.information,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = switch (tone) {
      NavigationTone.danger => p.notPassable,
      NavigationTone.caution => p.warning,
      NavigationTone.success => p.passable,
      _ => p.primary,
    };
    return Material(
      key: const ValueKey('navigation-guidance'),
      color: p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: color,
                          ),
                        )
                      : Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: p.onSurface,
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.35,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (action != null)
              Align(alignment: Alignment.centerRight, child: action!),
          ],
        ),
      ),
    );
  }
}

class NavigationStatusCard extends StatelessWidget {
  final NavigationNotice notice;
  const NavigationStatusCard({super.key, required this.notice});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (color, background) = switch (notice.tone) {
      NavigationTone.danger => (
        p.notPassable,
        Color.alphaBlend(
          p.errorContainer.withValues(alpha: p.isDark ? .55 : .5),
          p.surfaceContainerLowest,
        ),
      ),
      NavigationTone.caution => (p.onWarningContainer, p.warningContainer),
      NavigationTone.success => (
        p.passable,
        Color.alphaBlend(
          p.passable.withValues(alpha: .1),
          p.surfaceContainerLowest,
        ),
      ),
      _ => (
        p.primary,
        Color.alphaBlend(
          p.primary.withValues(alpha: .08),
          p.surfaceContainerLowest,
        ),
      ),
    };
    return Semantics(
      // Progress/GPS ticks must not repeatedly interrupt spoken maneuvers.
      container: true,
      child: Material(
        key: const ValueKey('navigation-status'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.withValues(alpha: .24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: notice.busy
                        ? SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          )
                        : Icon(notice.icon, color: color, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        if (notice.detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            notice.detail,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              height: 1.4,
                              color: p.onSurface,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (notice.actions.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: notice.actions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Footer and map controls occupy normal layout space. Only the top information
/// scrolls on short/large-text screens; it cannot cover the footer or its actions.
class NavigationHud extends StatelessWidget {
  final Widget guidance, footer, controls;
  final NavigationNotice? notice;
  const NavigationHud({
    super.key,
    required this.guidance,
    required this.footer,
    required this.controls,
    this.notice,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    key: const ValueKey('navigation-top-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        guidance,
                        if (notice != null) ...[
                          const SizedBox(height: 8),
                          NavigationStatusCard(notice: notice!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: controls,
              ),
            ],
          ),
        ),
        footer,
      ],
    ),
  );
}

class NavigationTripPanel extends StatelessWidget {
  final String time, distance, estimateLabel;
  final String? arrival;
  final bool arrived, paused;
  final VoidCallback onDetails, onEnd;
  const NavigationTripPanel({
    super.key,
    required this.time,
    required this.distance,
    required this.estimateLabel,
    this.arrival,
    required this.arrived,
    required this.paused,
    required this.onDetails,
    required this.onEnd,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final stacked = size.width < 500 && large;
    final metrics = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: size.height * (stacked ? .22 : .3),
      ),
      child: SingleChildScrollView(
        key: const ValueKey('navigation-trip-metrics'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              time,
              style: GoogleFonts.manrope(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
                color: arrived
                    ? p.passable
                    : paused
                    ? p.onSurfaceVariant
                    : p.primary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (paused) ...[
                  Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 16,
                    color: p.warning,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    estimateLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: paused ? FontWeight.w700 : FontWeight.w500,
                      color: paused ? p.warning : p.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                Widget metric(IconData icon, String label) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: p.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                return Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    metric(
                      arrived ? Icons.flag_outlined : Icons.route_outlined,
                      distance,
                    ),
                    if (arrival != null)
                      metric(Icons.schedule_rounded, arrival!),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
    final details = Tooltip(
      message: tr(context, 'Trip details'),
      child: OutlinedButton.icon(
        onPressed: onDetails,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          foregroundColor: p.primary,
          backgroundColor: p.primary.withValues(alpha: .05),
          side: BorderSide(color: p.primary.withValues(alpha: .22)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
        label: Text(tr(context, 'Trip details'), textAlign: TextAlign.center),
      ),
    );
    final end = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        backgroundColor: arrived ? p.primary : p.errorContainer,
        foregroundColor: arrived ? p.onPrimary : p.onErrorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      onPressed: onEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            arrived ? Icons.check_rounded : Icons.stop_circle_outlined,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              tr(context, arrived ? 'Done' : 'End Route'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Material(
          key: const ValueKey('navigation-trip-panel'),
          color: p.surfaceContainerLowest,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: .14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: p.outlineVariant.withValues(alpha: .45)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                metrics,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .5),
                  ),
                ),
                if (stacked) ...[
                  details,
                  const SizedBox(height: 8),
                  end,
                ] else
                  Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 10),
                      Expanded(child: end),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
