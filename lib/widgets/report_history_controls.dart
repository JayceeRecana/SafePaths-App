import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import '../services/report_history.dart';

class ReportHistoryControls extends StatelessWidget {
  final ReportHistory history;
  final double horizontalPadding;
  final bool compact, hideSinglePage, showRefresh, showStatus;
  const ReportHistoryControls({
    super.key,
    required this.history,
    this.horizontalPadding = 16,
    this.compact = false,
    this.hideSinglePage = true,
    this.showRefresh = true,
    this.showStatus = true,
  });
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final showPages =
            !history.loading &&
            history.loaded &&
            (history.pageNumber > 1 ||
                history.page.next != null ||
                !hideSinglePage && history.page.reports.isNotEmpty);
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: compact ? 4 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showStatus && history.loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              if (showStatus && history.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    tr(context, history.error!),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 11 : 12,
                      color: palette.error,
                    ),
                  ),
                ),
              if (showStatus && history.page.fromCache)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    tr(
                      context,
                      'Saved history — reconnect to check for updates or load older pages.',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: compact ? 11 : 12,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              if (showPages)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 12,
                    vertical: compact ? 0 : 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(compact ? 16 : 20),
                    border: Border.all(
                      color: palette.outlineVariant.withValues(alpha: 0.2),
                    ),
                    boxShadow: compact
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: compact ? 4 : 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: history.canGoNewer ? history.newer : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        label: Text(
                          tr(context, 'Newer'),
                          style: GoogleFonts.inter(
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 4 : 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${tr(context, 'Page')} ${history.pageNumber}',
                          style: GoogleFonts.inter(
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w800,
                            color: palette.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: history.canGoOlder ? history.older : null,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 4 : 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                tr(context, 'Older'),
                                style: GoogleFonts.inter(
                                  fontSize: compact ? 11 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                      if (showRefresh)
                        IconButton(
                          onPressed: history.loading ? null : history.refresh,
                          tooltip: tr(context, 'Refresh history'),
                          color: palette.primary,
                          disabledColor: palette.onSurfaceVariant.withValues(
                            alpha: .5,
                          ),
                          iconSize: 18,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                    ],
                  ),
                ),
              if (showStatus && !history.loading && history.error != null)
                TextButton.icon(
                  onPressed: history.refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(tr(context, 'Retry')),
                )
              else if (!history.loading && showRefresh && !showPages)
                IconButton(
                  onPressed: history.refresh,
                  tooltip: tr(context, 'Refresh history'),
                  color: palette.primary,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
            ],
          ),
        );
      },
    );
  }
}
