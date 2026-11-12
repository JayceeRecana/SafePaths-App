import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

/// The same accessible selection control with a styled menu and selected row.
class AdminChoiceField extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String?>? onChanged;
  final String? label;
  const AdminChoiceField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
  });
  IconData _icon(String key) => switch (key) {
    'not_passable' => Icons.block,
    'partial' => Icons.warning_amber_rounded,
    'passable' || 'verified' => Icons.check_circle_outline,
    'unconfirmed' => Icons.help_outline,
    'restricted_recheck' || 'needs_check' => Icons.update,
    'urgent' => Icons.sos,
    'waiting_resident' => Icons.question_answer_outlined,
    'pending' || 'admin' => Icons.pending_actions,
    'under_review' => Icons.fact_check_outlined,
    'dismissed' || 'spam_false' || 'unable_to_verify' => Icons.cancel_outlined,
    _ => Icons.filter_list_rounded,
  };
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return DropdownButtonFormField<String>(
      key: ValueKey('admin-choice-$value'),
      initialValue: value,
      isExpanded: true,
      itemHeight: null,
      menuMaxHeight: MediaQuery.sizeOf(context).height * .65,
      dropdownColor: p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      elevation: 8,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.primary),
      decoration: InputDecoration(
        labelText: label == null ? null : tr(context, label!),
        filled: true,
        fillColor: p.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      selectedItemBuilder: (context) => options.entries
          .map(
            (entry) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                tr(context, entry.value),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: p.onSurface,
                ),
              ),
            ),
          )
          .toList(),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: entry.key == value
                      ? p.primary.withValues(alpha: .10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _icon(entry.key),
                      size: 20,
                      color: entry.key == value
                          ? p.primary
                          : p.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(context, entry.value),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: entry.key == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: p.onSurface,
                        ),
                      ),
                    ),
                    if (entry.key == value) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_rounded, size: 18, color: p.primary),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
