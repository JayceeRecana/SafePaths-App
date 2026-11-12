import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import 'report_message_thread.dart' show AdminUpdateMessage;
import 'resident_report_details.dart';

/// Presentation only. ReportUpdatesPage owns authentication and pagination.
class AdminReportMessages extends StatefulWidget {
  final UserReport report;
  final List<AdminUpdateMessage> messages;
  final bool fromCache, loading, loadingOlder, hasMore;
  final String? error;
  final VoidCallback? onRetry, onLoadOlder;
  const AdminReportMessages({
    super.key,
    required this.report,
    required this.messages,
    this.fromCache = false,
    this.loading = false,
    this.loadingOlder = false,
    this.hasMore = false,
    this.error,
    this.onRetry,
    this.onLoadOlder,
  });
  @override
  State<AdminReportMessages> createState() => _AdminReportMessagesState();
}

class _AdminReportMessagesState extends State<AdminReportMessages> {
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _latest();
  }

  String? newest(List<AdminUpdateMessage> items) {
    if (items.isEmpty) return null;
    final sorted = [...items]
      ..sort(
        (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.createdAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    return sorted.first.id;
  }

  void _latest() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients)
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });
  @override
  void didUpdateWidget(covariant AdminReportMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (newest(oldWidget.messages) != newest(widget.messages) &&
        (!_scroll.hasClients || _scroll.position.extentAfter < 100))
      _latest();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), report = widget.report;
    final items = [...widget.messages]
      ..sort((a, b) {
        final n = (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          b.createdAt?.millisecondsSinceEpoch ?? 0,
        );
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        if (report.clarificationRepliedAt != null &&
            report.reviewOpen &&
            !report.awaitsResident) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.passable.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.passable.withValues(alpha: .18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.mark_chat_read_outlined,
                  size: 18,
                  color: p.passable,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      context,
                      'The resident replied. Read the answer before making a decision.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: p.passable,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (report.awaitsResident)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr(context, 'Waiting for the resident reply'),
              style: TextStyle(fontSize: 12, color: p.onWarningContainer),
            ),
          ),
        Text(
          tr(context, 'Private messages about this report'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (widget.fromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              tr(
                context,
                'Saved information; reconnect to check the latest update.',
              ),
              style: TextStyle(fontSize: 12, color: p.onWarningContainer),
            ),
          ),
        if (widget.loading) const LinearProgressIndicator(),
        if (widget.error != null) ...[
          Text(
            tr(context, widget.error!),
            style: TextStyle(color: p.error, fontSize: 12),
          ),
          if (widget.onRetry != null)
            TextButton(
              onPressed: widget.onRetry,
              child: Text(tr(context, 'Retry updates')),
            ),
        ],
        if (widget.hasMore)
          TextButton(
            onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
            child: Text(
              tr(
                context,
                widget.loadingOlder ? 'Loading...' : 'Load older updates',
              ),
            ),
          ),
        if (items.isEmpty && !widget.loading && widget.error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              tr(
                context,
                widget.fromCache
                    ? 'No saved admin updates are available on this device.'
                    : 'No admin messages are recorded yet.',
              ),
              style: TextStyle(color: p.onSurfaceVariant),
            ),
          ),
        for (var i = 0; i < items.length; i++) ...[
          if (items[i].createdAt != null &&
              (i == 0 ||
                  items[i - 1].createdAt == null ||
                  DateUtils.dateOnly(items[i].createdAt!.toLocal()) !=
                      DateUtils.dateOnly(items[i - 1].createdAt!.toLocal())))
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Text(
                localizedSubmissionDay(
                  context,
                  items[i].createdAt!,
                  DateTime.now(),
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
              ),
            ),
          ResidentReportMessageBubble(
            key: ValueKey(items[i].id),
            adminView: true,
            report: report,
            sender: items[i].sender,
            message: items[i].message,
            createdAt: items[i].createdAt,
            imageUrl: items[i].imageUrl,
            photoObservedAt: items[i].photoObservedAt,
          ),
        ],
      ],
    );
  }
}
