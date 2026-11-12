import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

/// A shared surface for reporting controls, questions and replies.
class ReportPanel extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  const ReportPanel({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: tint ?? p.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.outlineVariant.withValues(alpha: .4)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Abbreviation is display-only. Copy always preserves the exact document ID.
class ReportReference extends StatelessWidget {
  final String reportId, label;
  const ReportReference({
    super.key,
    required this.reportId,
    this.label = 'Report reference',
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final short = reportId.length > 24
        ? '${reportId.substring(0, 10)}…${reportId.substring(reportId.length - 6)}'
        : reportId;
    return Row(
      children: [
        Icon(Icons.receipt_long_outlined, size: 16, color: p.primary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '${tr(context, label)}: $short',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: p.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: tr(context, 'Copy report reference'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: reportId));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'Report reference copied.'))),
            );
          },
          icon: Icon(Icons.copy_outlined, size: 17, color: p.primary),
        ),
      ],
    );
  }
}

class ReportConversationCard extends StatelessWidget {
  final String title, message;
  final bool resident;
  final String? time;
  final Widget? attachment;
  const ReportConversationCard({
    super.key,
    required this.title,
    required this.message,
    this.resident = false,
    this.time,
    this.attachment,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        color = resident ? p.onSurfaceVariant : p.primary;
    return ReportPanel(
      tint: color.withValues(alpha: p.isDark ? .12 : .055),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  resident ? Icons.person_outline : Icons.shield_outlined,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, title),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 14, height: 1.5, color: p.onSurface),
          ),
          if (attachment != null) ...[const SizedBox(height: 12), attachment!],
          if (time != null) ...[
            const SizedBox(height: 10),
            Text(
              time!,
              style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Consistent heading for report actions on both dialogs and sheets.
class ReportActionHeading extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onClose;
  final bool showClose;
  const ReportActionHeading({
    super.key,
    required this.title,
    required this.icon,
    this.onClose,
    this.showClose = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 22, color: p.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr(context, title),
            style: TextStyle(
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: p.onSurface,
            ),
          ),
        ),
        if (showClose) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: tr(context, 'Close'),
            onPressed: onClose,
            icon: Icon(Icons.close, color: p.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Layout only: each caller retains its own validation and save safeguards.
class ReportActionDialog extends StatelessWidget {
  final String title, reportId;
  final IconData icon;
  final List<Widget> children, actions;
  final bool fixedHeader, asSheet;
  const ReportActionDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.reportId,
    required this.children,
    required this.actions,
    this.fixedHeader = false,
    this.asSheet = false,
  });
  @override
  Widget build(BuildContext context) {
    if (asSheet)
      return ReportActionSheet(
        title: title,
        children: children,
        actions: actions,
      );
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    // At large text sizes or with a tall keyboard, let the heading scroll too
    // rather than squeezing the editor out. Save/cancel stay in dialog actions.
    if (fixedHeader &&
        availableHeight >= 500 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20) {
      final p = AppPalette.of(context);
      return Dialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: const ValueKey('report-action-fixed-heading'),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReportActionHeading(title: title, icon: icon),
                    const SizedBox(height: 6),
                    ReportReference(reportId: reportId),
                  ],
                ),
              ),
              Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('report-action-body-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppPalette.of(context).surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: ReportActionHeading(title: title, icon: icon),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportReference(reportId: reportId),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
      actions: actions,
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    );
  }
}

class ReportActionSheet extends StatelessWidget {
  final String title;
  final List<Widget> children, actions;
  const ReportActionSheet({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .94,
        ),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: p.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, title),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...children,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: actions.reversed.toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
