import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_environment.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/broadcast_alert.dart';
import '../screens/shared/full_screen_map_screen.dart';
import '../theme/app_palette.dart';
import '../utils/time_utils.dart';

/// One presentation for published alerts in the list and notification deep link.
class ResidentAlertCard extends StatefulWidget {
  final BroadcastAlert alert;
  final VoidCallback? onDismiss, onViewRoad;
  final DateTime Function()? now;
  const ResidentAlertCard({
    super.key,
    required this.alert,
    this.onDismiss,
    this.onViewRoad,
    this.now,
  });
  @override
  State<ResidentAlertCard> createState() => _ResidentAlertCardState();
}

class _ResidentAlertCardState extends State<ResidentAlertCard> {
  Timer? _expiry;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  void _schedule() {
    _expiry?.cancel();
    final delay = widget.alert.activeUntil.difference(_now);
    if (!widget.alert.withdrawn && delay > Duration.zero) {
      _expiry = Timer(delay, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ResidentAlertCard old) {
    super.didUpdateWidget(old);
    if (old.alert != widget.alert || old.now != widget.now) _schedule();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert, p = AppPalette.of(context);
    final active = a.isActiveAt(_now);
    final known = ['Advisory', 'Warning', 'Critical'].contains(a.severity);
    final color = !active
        ? p.onSurfaceVariant
        : switch (a.severity) {
            'Critical' => p.error,
            'Warning' => p.warning,
            'Advisory' => p.primary,
            _ => p.onSurfaceVariant,
          };
    final icon = switch (a.severity) {
      'Critical' => Icons.report_outlined,
      'Warning' => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };
    final status = a.withdrawn
        ? 'Withdrawn'
        : !active
        ? 'Expired'
        : null;
    final road = a.roadName?.trim();
    final scope = road?.isNotEmpty == true
        ? road!
        : a.roadId?.isNotEmpty == true
        ? tr(context, 'Selected road')
        : a.studyArea == AppEnvironment.area.id
        ? '${tr(context, 'Area-wide')} · ${AppEnvironment.area.name}'
        : tr(context, 'Alert area not recorded');
    Widget info(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: p.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: p.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tr(
                                context,
                                known ? a.severity : 'Severity not recorded',
                              ),
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (status != null)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(tr(context, status)),
                        side: BorderSide.none,
                        backgroundColor: p.surfaceContainerLow,
                      ),
                  ],
                ),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  tooltip: tr(context, 'Hide alert'),
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            a.title,
            style: TextStyle(
              color: p.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            a.message,
            style: TextStyle(color: p.onSurface, fontSize: 14, height: 1.5),
          ),
          if (!active) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                a.withdrawn && a.withdrawalReason?.trim().isNotEmpty == true
                    ? '${tr(context, 'Withdrawal reason')}: ${a.withdrawalReason}'
                    : tr(
                        context,
                        'This alert is no longer active. Check current alerts before acting.',
                      ),
                style: TextStyle(color: p.onSurface, fontSize: 13, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .6)),
          info(Icons.location_on_outlined, scope),
          info(
            Icons.schedule_outlined,
            TimeUtils.hasRecordedTime(a.createdAt)
                ? '${tr(context, 'Issued')}: ${localizedDateTime(context, a.createdAt)}'
                : tr(context, 'Issue time not recorded'),
          ),
          info(
            Icons.timelapse_outlined,
            a.expiresAt != null
                ? '${tr(context, active ? 'Active until' : 'End time')}: ${localizedDateTime(context, a.expiresAt!)}'
                : tr(context, 'End time not recorded'),
          ),
          if (a.roadId?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  widget.onViewRoad ??
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          FullScreenMapScreen(initialRoadId: a.roadId),
                    ),
                  ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(tr(context, 'View road')),
            ),
          ],
        ],
      ),
    );
  }
}

class AlertRoadReminder extends StatelessWidget {
  const AlertRoadReminder({super.key});
  @override
  Widget build(BuildContext context) => Text(
    tr(
      context,
      'An announcement does not change the verified road condition. Check the latest road update before travel.',
    ),
    style: TextStyle(
      color: AppPalette.of(context).onSurfaceVariant,
      fontSize: 12,
      height: 1.5,
    ),
  );
}
