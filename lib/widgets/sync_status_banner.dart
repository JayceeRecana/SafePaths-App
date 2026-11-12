import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../services/app_state_service.dart';
import 'package:intl/intl.dart';
import '../services/sync_health.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppStateService.instance;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        if (!state.requiresLiveDataWarning) return const SizedBox.shrink();
        final last = state.syncHealth.lastRoadSync;
        final roadState = state.syncHealth.channels['roads'];
        final affected = state.syncHealth.affectedFeeds;
        final riskOnly =
            affected.length == 1 && affected.single == 'Risk estimates';
        final message = state.roads.isEmpty && roadState != SyncCondition.live
            ? 'Road data unavailable. No saved roads are available yet. Connect to load them.'
            : roadState == SyncCondition.cached
            ? 'Showing saved road conditions. They may have changed.'
            : riskOnly && state.syncHealth.roadsLive
            ? 'Road updates are connected. Risk estimates are unavailable or out of date.'
            : 'Some live updates are unavailable. Conditions may have changed.';
        final time = last == null
            ? tr(context, 'Road data has not been confirmed online.')
            : '${tr(context, 'Roads last synced')}: ${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).addPattern('h:mm a').format(last)}';
        return Material(
          color: AppPalette.of(context).warningContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${tr(context, message)} $time',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).onWarningContainer,
                      ),
                    ),
                  ),
                  if (affected.isNotEmpty && !riskOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${tr(context, 'Affected updates')}: ${affected.map((feed) => tr(context, feed)).join(', ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPalette.of(context).onWarningContainer,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: state.retrySync,
                    child: Text(tr(context, 'Retry updates')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
