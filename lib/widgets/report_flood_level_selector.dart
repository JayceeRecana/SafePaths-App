import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

/// Display-only selection; reporting still maps 0/1/2 to Low/Medium/High.
class ReportFloodLevelSelector extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onChanged;
  const ReportFloodLevelSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final options = [
      (Icons.water_drop, 'Low', p.secondary),
      (Icons.flood, 'Medium', p.primary),
      (Icons.warning_rounded, 'High', p.tertiary),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final stacked =
            box.maxWidth < 250 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final tiles = [
          for (var i = 0; i < options.length; i++)
            _LevelTile(
              icon: options[i].$1,
              label: tr(context, options[i].$2),
              color: options[i].$3,
              selected: selected == i,
              stacked: stacked,
              onTap: () => onChanged(i),
            ),
        ];
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    tiles[i],
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
              );
      },
    );
  }
}

class _LevelTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected, stacked;
  final VoidCallback onTap;
  const _LevelTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.stacked,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final background = selected
        ? Color.alphaBlend(
            color.withValues(alpha: p.isDark ? 0.13 : 0.075),
            p.surfaceContainerLowest,
          )
        : p.surfaceContainerLow;
    final symbol = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 24, color: color),
    );
    final text = Text(
      label,
      textAlign: stacked ? TextAlign.start : TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: selected ? color : p.onSurface,
      ),
    );
    final check = selected
        ? Icon(Icons.check_circle_rounded, size: 16, color: color)
        : const SizedBox(width: 16, height: 16);
    return Semantics(
      key: ValueKey('flood-level-$label'),
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: stacked ? 12 : 6,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? color
                    : p.outlineVariant.withValues(alpha: .25),
                width: 1.5,
              ),
            ),
            child: stacked
                ? Row(
                    children: [
                      symbol,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                      const SizedBox(width: 8),
                      check,
                    ],
                  )
                : Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: symbol),
                          const SizedBox(height: 8),
                          text,
                        ],
                      ),
                      Positioned(top: 0, right: 0, child: check),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
