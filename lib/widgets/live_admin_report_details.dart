import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/user_report.dart';

/// Watches one selected report independently of the active queue and history
/// pagination, so completion by another admin cannot resurrect an old snapshot.
class LiveAdminReportDetails extends StatefulWidget {
  final UserReport seed;
  final Stream<UserReport?> Function(String)? changes;
  final Widget Function(UserReport report, bool loading) builder;
  final VoidCallback onClose;
  const LiveAdminReportDetails({
    super.key,
    required this.seed,
    this.changes,
    required this.builder,
    required this.onClose,
  });
  @override
  State<LiveAdminReportDetails> createState() => _LiveAdminReportDetailsState();
}

class _LiveAdminReportDetailsState extends State<LiveAdminReportDetails> {
  StreamSubscription<UserReport?>? _subscription;
  UserReport? _report;
  bool _loading = true, _unavailable = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant LiveAdminReportDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed.id != widget.seed.id ||
        oldWidget.seed.userId != widget.seed.userId ||
        oldWidget.changes != widget.changes) {
      _connect();
    }
  }

  void _connect() {
    final generation = ++_generation;
    _subscription?.cancel();
    _report = null;
    _loading = true;
    _unavailable = false;
    try {
      final stream =
          widget.changes?.call(widget.seed.id) ??
          FirebaseFirestore.instance
              .collection('reports')
              .doc(widget.seed.id)
              .snapshots(includeMetadataChanges: true)
              .where(
                (snapshot) => snapshot.exists || !snapshot.metadata.isFromCache,
              )
              .map(
                (snapshot) => snapshot.exists
                    ? UserReport.fromJson({
                        ...snapshot.data()!,
                        'id': snapshot.id,
                      })
                    : null,
              );
      _subscription = stream.listen(
        (report) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _loading = false;
            _unavailable =
                report == null ||
                report.id != widget.seed.id ||
                report.userId != widget.seed.userId;
            _report = _unavailable ? null : report;
          });
        },
        onError: (Object _) {
          if (mounted && generation == _generation)
            setState(() {
              _report = null;
              _loading = false;
              _unavailable = true;
            });
        },
      );
    } catch (_) {
      _loading = false;
      _unavailable = true;
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_unavailable) return widget.builder(_report ?? widget.seed, _loading);
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(height: 12),
            Text(
              tr(
                context,
                'This report could not be refreshed. Check your connection and retry.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: widget.onClose,
                  child: Text(tr(context, 'Back to list')),
                ),
                FilledButton(
                  onPressed: () => setState(_connect),
                  child: Text(tr(context, 'Retry')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
