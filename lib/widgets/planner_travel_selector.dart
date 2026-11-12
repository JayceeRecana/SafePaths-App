import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

class PlannerTravelSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  const PlannerTravelSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  static const modes = {
    'Walking': Icons.directions_walk,
    'Motorcycle': Icons.motorcycle,
    'Sedan': Icons.directions_car,
    'SUV / Pickup': Icons.airport_shuttle,
  };
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final large = MediaQuery.textScalerOf(context).scale(13) > 18;
    Widget option(String name, IconData icon) {
      final active = name == selected;
      return Semantics(
        selected: active,
        button: true,
        label: tr(context, name),
        child: Tooltip(
          message: tr(context, name),
          child: Material(
            color: active ? p.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(name),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: active ? p.onPrimary : p.onSurfaceVariant,
                      size: 20,
                    ),
                    if (active || large) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tr(context, name),
                          style: TextStyle(
                            color: active ? p.onPrimary : p.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, bounds) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.surfaceContainerLow,
          borderRadius: BorderRadius.circular(large ? 24 : 999),
        ),
        child: large
            ? Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in modes.entries)
                    SizedBox(
                      width: (bounds.maxWidth - 12) / 2,
                      child: option(entry.key, entry.value),
                    ),
                ],
              )
            : Row(
                children: [
                  for (final entry in modes.entries)
                    Expanded(
                      flex: entry.key == selected ? 3 : 1,
                      child: option(entry.key, entry.value),
                    ),
                ],
              ),
      ),
    );
  }
}
