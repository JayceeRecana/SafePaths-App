import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_state_service.dart';
import '../../services/report_workload.dart';
import '../../services/sync_health.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/report_workflow_ui.dart';
import '../../widgets/user_report_card.dart';
import '../../widgets/road_condition_overview.dart' show residentRoadTitle;
import 'user_reports_screen.dart';

/// The complete active feed for one road, not a claim to show its full history.
class RoadReportQueueScreen extends StatefulWidget {
  final String roadId, roadName;
  const RoadReportQueueScreen({
    super.key,
    required this.roadId,
    required this.roadName,
  });
  @override
  State<RoadReportQueueScreen> createState() => _RoadReportQueueScreenState();
}

class _RoadReportQueueScreenState extends State<RoadReportQueueScreen> {
  String _filter = 'admin';
  @override
  Widget build(BuildContext context) {
    final state = AppStateService.instance, p = AppPalette.of(context);
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Reports for this road'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final work = ReportWorkload(
            state.reports.where((r) => r.roadId == widget.roadId),
          );
          final records = work.open
              .where(
                (r) =>
                    _filter == 'all' ||
                    _filter == 'admin' && r.needsAdminReview ||
                    _filter == 'waiting' && r.awaitsResident,
              )
              .toList();
          final live =
              state.syncHealth.channels['reports'] == SyncCondition.live;
          final name = residentRoadTitle(widget.roadName);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: ReportPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name == 'Unnamed residential road'
                            ? tr(context, name)
                            : name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${tr(context, 'Road reference')}: ${widget.roadId}',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          context,
                          'Active reports for this road. Completed reviews remain in report history.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                      if (!live) ...[
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            context,
                            'Report workload is not confirmed current.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.warning,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: state.retrySync,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(tr(context, 'Retry')),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _filter,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: InputDecoration(
                          labelText: tr(context, 'Show reports'),
                        ),
                        items: [
                          for (final pair in [
                            ('admin', 'Needs admin action'),
                            ('waiting', 'Waiting for resident'),
                            ('all', 'All open reports'),
                          ])
                            DropdownMenuItem(
                              value: pair.$1,
                              child: Text(tr(context, pair.$2)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _filter = v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr(
                      context,
                      live
                          ? 'No reports available in this view.'
                          : 'Reports are not confirmed current. Reconnect and retry.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final report in records)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: UserReportCard(
                    key: ValueKey('road-report-${report.id}'),
                    report: report,
                    road: state.roads
                        .where((r) => r.id == widget.roadId)
                        .firstOrNull,
                    reporterName: state.users
                        .where((r) => r.id == report.userId)
                        .firstOrNull
                        ?.name,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserReportsScreen(
                          isStandalone: true,
                          initialReportId: report.id,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
