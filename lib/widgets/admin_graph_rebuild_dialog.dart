import 'package:flutter/material.dart';
import '../config/app_environment.dart';
import '../l10n/app_strings.dart';
import '../services/app_state_service.dart';
import '../theme/app_palette.dart';

class AdminGraphRebuildDialog extends StatefulWidget {
  final Future<Map<String, dynamic>> Function()? rebuild;
  const AdminGraphRebuildDialog({super.key, this.rebuild});
  @override
  State<AdminGraphRebuildDialog> createState() =>
      _AdminGraphRebuildDialogState();
}

class _AdminGraphRebuildDialogState extends State<AdminGraphRebuildDialog> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;
  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data =
          await (widget.rebuild ??
              AppStateService.instance.buildAndVerifyRoadGraph)();
      final total = data['totalRoads'],
          isolated = data['disconnectedRoads'],
          maximum = data['maximumNeighbors'],
          components = data['connectedComponents'],
          average = data['avgNeighbors'];
      if (total is! int ||
          total < 0 ||
          isolated is! int ||
          isolated < 0 ||
          isolated > total ||
          maximum is! int ||
          maximum < 0 ||
          components is! int ||
          components < 0 ||
          components > total ||
          average is! num ||
          !average.isFinite ||
          average < 0)
        throw StateError('Graph result not confirmed.');
      if (mounted) setState(() => _result = data);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The rebuild was not confirmed. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: p.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.hub_outlined, color: p.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(
                  context,
                  _result == null
                      ? 'Rebuild road connections'
                      : 'Road connections rebuilt',
                ),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  context,
                  'Area: {area}',
                ).replaceAll('{area}', AppEnvironment.area.name),
                style: TextStyle(fontWeight: FontWeight.w600, color: p.primary),
              ),
              const SizedBox(height: 12),
              if (_result == null)
                Text(
                  tr(
                    context,
                    'This updates neighbour links used for routing. It does not change verified road conditions.',
                  ),
                ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(tr(context, 'Rebuilding connections. Please wait...')),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    tr(context, _error!),
                    style: TextStyle(color: p.error),
                  ),
                ),
              if (_result != null) ...[
                Text(
                  tr(
                    context,
                    'Roads processed: {count}',
                  ).replaceAll('{count}', '${_result!['totalRoads']}'),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    'Roads with no neighbour links: {count}',
                  ).replaceAll('{count}', '${_result!['disconnectedRoads']}'),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    'This result does not confirm that every road is passable.',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_busy)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, _result == null ? 'Cancel' : 'Done')),
            ),
          if (_result == null)
            FilledButton(
              onPressed: _busy ? null : _run,
              child: Text(
                tr(
                  context,
                  _busy
                      ? 'Working...'
                      : _error == null
                      ? 'Rebuild connections'
                      : 'Retry',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
