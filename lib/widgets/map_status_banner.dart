import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../services/map_load_state.dart';

class MapStatusBanner extends StatelessWidget {
  final MapLoadState status;
  final VoidCallback onRetry;
  const MapStatusBanner({
    super.key,
    required this.status,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: status,
    builder: (context, _) {
      if (!status.loading &&
          status.mapError == null &&
          status.overlayError == null) {
        return const SizedBox.shrink();
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.loading) const LinearProgressIndicator(),
              Text(
                tr(
                  context,
                  status.overlayError ?? status.mapError ?? 'Loading map…',
                ),
                textAlign: TextAlign.center,
              ),
              if (!status.loading)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(context, 'Retry map')),
                ),
            ],
          ),
        ),
      );
    },
  );
}
