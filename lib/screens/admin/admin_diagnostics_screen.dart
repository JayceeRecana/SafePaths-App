import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/formatters.dart';
import '../../services/app_state_service.dart';
import '../../services/sync_health.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_top_bar.dart';

/// Read-only local/feed diagnostics, deliberately separate from report history.
class AdminDiagnosticsScreen extends StatelessWidget {
  const AdminDiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: tr(context, 'Technical diagnostics'),
      showBackButton: true,
    ),
    backgroundColor: AppPalette.of(context).surface,
    body: ListenableBuilder(
      listenable: AppStateService.instance,
      builder: (context, _) {
        final state = AppStateService.instance, p = AppPalette.of(context);
        final now = DateTime.now();
        final logs = state.systemLogs.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Text(tr(context, label))),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
        Widget panel(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, title),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        );
        String time(DateTime? at) =>
            at == null || at.isAfter(now) || at.year <= 1970
            ? tr(context, 'Not recorded')
            : localizedDateTime(context, at);
        String sync(String channel) =>
            tr(context, switch (state.syncHealth.channels[channel]) {
              SyncCondition.live => 'Server snapshot received',
              SyncCondition.cached => 'Saved information',
              SyncCondition.failed => 'Could not update',
              _ => 'Checking for updates',
            });
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr(
                context,
                'Feed information does not confirm push delivery or the health of every service.',
              ),
              style: TextStyle(color: p.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            panel('Latest feed states', [
              for (final entry in [
                ('roads', 'Road updates'),
                ('reports', 'Live report queue'),
                ('alerts', 'Alerts'),
                ('risk', 'Risk calculation feed'),
              ])
                line(entry.$2, sync(entry.$1)),
              line('Last road sync', time(state.syncHealth.lastRoadSync)),
              line(
                'Last server risk calculation',
                time(state.syncHealth.lastRiskCompute),
              ),
            ]),
            panel('Road connections', [
              Text(
                tr(
                  context,
                  'Neighbour links describe map connectivity, not whether a road is passable.',
                ),
              ),
              line('Roads loaded', '${state.roads.length}'),
              line(
                'Roads with no neighbour links',
                '${state.roads.where((r) => r.neighbors.isEmpty).length}',
              ),
              line(
                'Recorded neighbour links',
                '${state.roads.fold<int>(0, (total, r) => total + r.neighbors.length)}',
              ),
            ]),
            panel('Local calculation timing', [
              Text(
                tr(
                  context,
                  'Local measurements are separate from the backend worker.',
                ),
              ),
              line('Last local run', time(state.lastRiskEngineRun)),
              line(
                'Recorded execution time',
                state.lastRiskEngineExecutionMs > 0 &&
                        state.lastRiskEngineRun != null &&
                        !state.lastRiskEngineRun!.isAfter(now)
                    ? '${state.lastRiskEngineExecutionMs} ms'
                    : tr(context, 'Not measured'),
              ),
            ]),
            panel('System activity on this device', [
              Text(
                tr(
                  context,
                  'Local diagnostic entries, not the report review history.',
                ),
              ),
              if (logs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    tr(context, 'No local system activity recorded.'),
                  ),
                ),
              for (final log in logs.take(20))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    log.action,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(time(log.timestamp)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(log.details),
                      ),
                    ),
                  ],
                ),
              if (logs.length > 20)
                Text(tr(context, 'Showing the 20 most recent local entries.')),
            ]),
          ],
        );
      },
    ),
  );
}
