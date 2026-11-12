import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/pin_road_context.dart';
import '../theme/app_palette.dart';

/// Ambiguous local map searches require an explicit result selection.
Future<PinPlaceSuggestion?> chooseLocalMapResult(
  BuildContext context,
  List<PinPlaceSuggestion> choices,
) {
  if (choices.length == 1) return Future.value(choices.single);
  return showModalBottomSheet<PinPlaceSuggestion>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .6,
    ),
    builder: (context) {
      final p = AppPalette.of(context);
      return SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Text(
              tr(context, 'Choose a search result'),
              style: TextStyle(
                color: p.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in choices)
              ListTile(
                leading: Icon(
                  item.landmark
                      ? Icons.place_outlined
                      : Icons.add_road_outlined,
                  color: p.primary,
                ),
                title: Text(item.title),
                subtitle: Text(
                  item.subtitle?.isNotEmpty == true
                      ? item.subtitle!
                      : tr(
                          context,
                          item.landmark ? 'Landmark' : 'Monitored Street',
                        ),
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      );
    },
  );
}
