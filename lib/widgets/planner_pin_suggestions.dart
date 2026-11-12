import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/pin_road_context.dart';
import '../theme/app_palette.dart';
import 'road_condition_overview.dart';

class PlannerPinSuggestions extends StatelessWidget {
  final List<PinPlaceSuggestion> items;
  final ValueChanged<PinPlaceSuggestion> onSelected;
  const PlannerPinSuggestions({
    super.key,
    required this.items,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (items.isEmpty)
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          tr(context, 'No local matches. Use Search to look within this area.'),
          style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
        ),
      );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .25,
      ),
      child: ListView.separated(
        key: const ValueKey('planner-pin-suggestions'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            leading: Icon(
              item.landmark ? Icons.place_outlined : Icons.route_outlined,
              color: p.primary,
            ),
            title: Text(
              item.landmark ? item.title : residentRoadTitle(item.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.onSurface, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              tr(
                context,
                item.landmark
                    ? 'Catalog place · Check the entrance on the map'
                    : 'Monitored road',
              ),
              style: TextStyle(color: p.onSurfaceVariant),
            ),
            onTap: () => onSelected(item),
          );
        },
      ),
    );
  }
}
