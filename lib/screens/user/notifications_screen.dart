import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_state_service.dart';
import '../../services/sync_health.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/feed_status_notice.dart';
import '../../widgets/resident_alert_card.dart';

class NotificationsScreen extends StatefulWidget {
  /// Optional snapshots keep design previews and tests out of the database.
  final List<BroadcastAlert>? alerts;
  final SyncCondition? syncCondition;
  final DateTime Function()? now;
  const NotificationsScreen({
    super.key,
    this.alerts,
    this.syncCondition,
    this.now,
  });
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Timer? _expiry;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  void _scheduleExpiry(List<BroadcastAlert> alerts) {
    _expiry?.cancel();
    final remaining =
        alerts
            .where((a) => a.isActiveAt(_now))
            .map((a) => a.activeUntil.difference(_now))
            .where((d) => d > Duration.zero)
            .toList()
          ..sort();
    if (remaining.isNotEmpty) {
      _expiry = Timer(remaining.first, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppStateService.instance, p = AppPalette.of(context);
    return Scaffold(
      appBar: const AppTopBar(inset: true),
      backgroundColor: p.surface,
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final all = widget.alerts ?? app.alerts;
          _scheduleExpiry(all);
          final alerts = all.where((a) => a.isActiveAt(_now)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Alerts'),
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (alerts.isNotEmpty && widget.alerts == null)
                    TextButton(
                      onPressed: () async {
                        await app.clearAllAlerts();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(context, 'Alerts hidden from your list.'),
                            ),
                          ),
                        );
                      },
                      child: Text(tr(context, 'Hide all')),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, 'Updates for your area'),
                style: TextStyle(
                  color: p.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const AlertRoadReminder(),
              const SizedBox(height: 16),
              FeedStatusNotice(
                condition:
                    widget.syncCondition ??
                    app.syncHealth.channels['alerts'] ??
                    SyncCondition.connecting,
                isEmpty: alerts.isEmpty,
                emptyMessage: tr(context, 'No active alerts right now.'),
                onRetry: app.retrySync,
              ),
              for (final alert in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ResidentAlertCard(
                    key: ValueKey(alert.id),
                    alert: alert,
                    now: widget.now,
                    onDismiss: widget.alerts != null
                        ? null
                        : () => app.removeAlert(alert.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
