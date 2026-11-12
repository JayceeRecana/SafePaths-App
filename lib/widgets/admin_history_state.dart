import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/report_history.dart';
import '../theme/app_palette.dart';

class AdminHistoryState extends StatelessWidget {
  final ReportHistory history;
  final bool hasReports;
  const AdminHistoryState({
    super.key,
    required this.history,
    required this.hasReports,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loading =
        history.loading || (!history.loaded && history.error == null);
    if (hasReports &&
        !loading &&
        history.error == null &&
        !history.page.fromCache)
      return const SizedBox.shrink();
    if (hasReports && loading)
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    final failed = history.error != null;
    final cached = history.page.fromCache;
    final title = loading
        ? 'Loading report history...'
        : failed
        ? (hasReports
              ? 'History could not refresh'
              : 'Report history unavailable')
        : cached
        ? (hasReports ? 'Saved report history' : 'No saved reports')
        : 'No matching reports';
    final detail = loading
        ? 'Checking the selected review outcome and dates.'
        : failed
        ? (hasReports
              ? 'Your last loaded reports remain below. Reconnect to check for changes.'
              : 'Check your connection, then retry to load these reports.')
        : cached
        ? 'Reconnect to confirm the latest reports and load older pages.'
        : 'Try another review outcome or widen the time range.';
    final color = failed
        ? p.error
        : cached
        ? p.warning
        : p.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: p.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          failed
                              ? Icons.cloud_off_outlined
                              : cached
                              ? Icons.history
                              : Icons.inbox_outlined,
                          color: color,
                          size: 21,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, title),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(context, detail),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!loading && (failed || cached))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.primary.withValues(alpha: .10),
                    foregroundColor: p.primary,
                  ),
                  onPressed: history.refresh,
                  icon: const Icon(Icons.refresh, size: 19),
                  label: Text(tr(context, 'Retry')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
