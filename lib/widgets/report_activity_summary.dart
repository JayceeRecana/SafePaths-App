import 'dart:async';
import 'report_workflow_ui.dart';
import '../theme/app_palette.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';

/// On-demand server aggregates, never totals inferred from a history page.
class ReportActivitySummary extends StatefulWidget {
  final Future<(int, int)> Function(DateTime start, DateTime end)? load;
  final DateTime Function()? now;
  const ReportActivitySummary({super.key, this.load, this.now});
  @override
  State<ReportActivitySummary> createState() => _ReportActivitySummaryState();
}

class _ReportActivitySummaryState extends State<ReportActivitySummary>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _expanded = false;
  int _generation = 0;
  Timer? _dayTimer;
  late DateTime _calendarDay;
  DateTime _now() => (widget.now ?? DateTime.now)();
  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
  (int, int)? _counts;
  DateTime? _checked;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calendarDay = _day(_now());
    _scheduleDayCheck();
  }

  void _scheduleDayCheck() {
    _dayTimer?.cancel();
    final now = _now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      _checkDay();
      _scheduleDayCheck();
    });
  }

  void _invalidate(DateTime day) {
    _generation++;
    setState(() {
      _calendarDay = day;
      _loading = false;
      _counts = null;
      _checked = null;
      _error = null;
    });
    if (_expanded) unawaited(_load());
  }

  void _checkDay() {
    if (_day(_now()) != _calendarDay) _invalidate(_day(_now()));
  }

  @override
  void didUpdateWidget(covariant ReportActivitySummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkDay();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _invalidate(_day(_now()));
      _scheduleDayCheck();
    }
  }

  @override
  void dispose() {
    _generation++;
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _counts = null;
    });
    final now = _now(),
        uid = widget.load == null
            ? FirebaseAuth.instance.currentUser?.uid
            : null;
    final start = DateTime(now.year, now.month, now.day),
        end = DateTime(now.year, now.month, now.day + 1);
    try {
      final result = await (widget.load?.call(start, end) ?? _fetch(start, end))
          .timeout(const Duration(seconds: 12));
      if (!mounted ||
          generation != _generation ||
          widget.load == null && FirebaseAuth.instance.currentUser?.uid != uid)
        return;
      if (_day(_now()) != start) {
        _invalidate(_day(_now()));
        return;
      }
      setState(() {
        _counts = result;
        _checked = now;
      });
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          (widget.load != null ||
              FirebaseAuth.instance.currentUser?.uid == uid))
        setState(
          () => _error = 'Summary unavailable. Reconnect and try again.',
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<(int, int)> _fetch(DateTime start, DateTime end) async {
    final reports = FirebaseFirestore.instance.collection('reports');
    final results = await Future.wait([
      reports
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .count()
          .get(),
      reports
          .where('status', whereIn: ['verified', 'resolved', 'dismissed'])
          .where(
            'reviewedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          )
          .where('reviewedAt', isLessThan: Timestamp.fromDate(end))
          .count()
          .get(),
    ]);
    if (results.any((r) => r.count == null))
      throw StateError('Counts not confirmed.');
    return (results[0].count!, results[1].count!);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ReportPanel(
        padding: EdgeInsets.zero,
        tint: p.surfaceContainerLow,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            tr(context, 'Today’s report activity'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          onExpansionChanged: (open) {
            _expanded = open;
            if (open) _load();
          },
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_counts != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr(context, 'Received today')),
                trailing: Text(
                  '${_counts!.$1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr(context, 'Reviews completed today')),
                trailing: Text(
                  '${_counts!.$2}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                tr(
                  context,
                  'Counts as of the last check. Replies are not new reports.',
                ),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: p.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${tr(context, 'Checked')}: ${localizedDateTime(context, _checked!)}',
                style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
              ),
            ],
            if (_error != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18, color: p.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, _error!),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 17),
                label: Text(tr(context, 'Refresh summary')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
