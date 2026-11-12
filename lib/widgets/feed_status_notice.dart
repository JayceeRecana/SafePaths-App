import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../services/sync_health.dart';

/// An empty cached query is not proof that there are no alerts or hazards.
class FeedStatusNotice extends StatelessWidget {
  final SyncCondition condition;
  final bool isEmpty;
  final String emptyMessage;
  final VoidCallback onRetry;
  const FeedStatusNotice({
    super.key,
    required this.condition,
    required this.isEmpty,
    required this.emptyMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!isEmpty && condition == SyncCondition.live) {
      return const SizedBox.shrink();
    }
    final message = switch (condition) {
      SyncCondition.connecting => 'Checking for updates…',
      SyncCondition.cached =>
        isEmpty
            ? 'No saved information is available. Connect to check for updates.'
            : 'Showing saved information. Reconnect to check for updates.',
      SyncCondition.failed =>
        'Updates could not load. Check your connection and retry.',
      SyncCondition.live => emptyMessage,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (condition == SyncCondition.connecting)
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(tr(context, message), textAlign: TextAlign.center),
            ),
            if (condition != SyncCondition.live)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'Retry updates')),
              ),
          ],
        ),
      ),
    );
  }
}
