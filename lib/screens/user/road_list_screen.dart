import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_state_service.dart';
import '../../services/sync_health.dart';
import '../../services/weather_service.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/feed_status_notice.dart';

/// A keyboard/TalkBack-accessible road picker. Returns the selected road ID.
class RoadListScreen extends StatefulWidget {
  const RoadListScreen({super.key});
  @override
  State<RoadListScreen> createState() => _RoadListScreenState();
}

class _RoadListScreenState extends State<RoadListScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final state = AppStateService.instance;
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Road list'),
        showBackButton: true,
        showProfile: false,
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final condition =
              state.syncHealth.channels['roads'] ?? SyncCondition.connecting;
          final roads =
              state.roads
                  .where((road) => road.name.toLowerCase().contains(_query))
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: tr(context, 'Search roads...'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
              FeedStatusNotice(
                condition: condition,
                isEmpty: state.roads.isEmpty,
                emptyMessage: tr(context, 'No monitored roads are available.'),
                onRetry: state.retrySync,
              ),
              Expanded(
                child: roads.isEmpty && state.roads.isNotEmpty
                    ? Center(
                        child: Text(tr(context, 'No roads match your search.')),
                      )
                    : ListView.separated(
                        itemCount: roads.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final road = roads[index];
                          final status =
                              road.needsStatusConfirmation(
                                SimulatedWeatherService.instance.currentState,
                              )
                              ? 'Needs confirmation'
                              : switch (road.getEffectiveStatus(
                                  SimulatedWeatherService.instance.currentState,
                                )) {
                                  'passable' => 'Passable',
                                  'partial' => 'Partially passable',
                                  'not_passable' => 'Not passable',
                                  _ => 'Current conditions need verification',
                                };
                          final time = DateFormat.yMMMd(
                            Localizations.localeOf(context).toLanguageTag(),
                          ).addPattern('h:mm a').format(road.updatedAt);
                          return ListTile(
                            title: Text(road.name),
                            subtitle: Text(
                              '${tr(context, status)}\n${tr(context, 'Last recorded update')}: $time',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(road.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
