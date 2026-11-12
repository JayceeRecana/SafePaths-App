import '../../widgets/admin_road_check_section.dart';
import '../../widgets/admin_report_workspace.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/live_admin_report_details.dart';
import '../../widgets/report_workflow_ui.dart';
import '../../widgets/admin_choice_field.dart';
import '../../widgets/admin_history_state.dart';
import '../../widgets/report_activity_summary.dart';
import '../../services/report_workload.dart';
import '../../services/sync_health.dart';
import '../../widgets/admin_clarification_dialog.dart';
import 'dart:async';
import '../../utils/time_utils.dart';
import '../../l10n/formatters.dart';
import '../../widgets/admin_reply_dialog.dart';
import '../../widgets/report_followup_link.dart';
import '../../widgets/followup_correction_button.dart';
import '../../widgets/admin_dismiss_dialog.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../widgets/admin_review_dialog.dart';
import '../../services/admin_report_service.dart';
import '../../widgets/user_report_card.dart';
import '../../services/report_history.dart';
import '../../widgets/report_history_controls.dart';
import '../user/road_details_screen.dart';

enum ReportFilterTab { actionable, recent48h, all }

class UserReportsScreen extends StatefulWidget {
  final bool isStandalone, isActive;
  final ReportPageLoader? historyLoader;
  final Future<Map<String, dynamic>> Function(String)? loadReport;
  final Stream<UserReport?> Function(String)? selectedReportChanges;
  final bool initiallyWaitingResident, initiallyHistory, initiallyUrgent;
  final String? initialReportId;
  final int openRequestRevision;
  final DateTime Function()? now;
  final Function(bool)? onSelectionChanged;
  const UserReportsScreen({
    super.key,
    this.isStandalone = false,
    this.isActive = true,
    this.historyLoader,
    this.loadReport,
    this.selectedReportChanges,
    this.initiallyWaitingResident = false,
    this.initiallyHistory = false,
    this.initiallyUrgent = false,
    this.initialReportId,
    this.openRequestRevision = 0,
    this.now,
    this.onSelectionChanged,
  });

  @override
  State<UserReportsScreen> createState() => _UserReportsScreenState();
}

class _UserReportsScreenState extends State<UserReportsScreen>
    with WidgetsBindingObserver {
  Timer? _dayTimer;
  final _listScroll = ScrollController();
  late DateTime _calendarDay;
  DateTime _now() => (widget.now ?? DateTime.now)();
  String? _selectedReportId;
  final Map<String, String> _replyDrafts = {};
  final TextEditingController _privateUpdateController =
      TextEditingController();
  ReportFilterTab _currentFilter = ReportFilterTab.actionable;
  bool _isSendingReply = false;
  String _queueStatus = 'admin', _historyStatus = 'completed';
  UserReport? _directReport;
  int _openGeneration = 0;
  String? _directError;
  bool _openingReport = false, _showReportSearch = false;
  final _search = TextEditingController();
  StreamSubscription<User?>? _accountWatch;
  String? _openingUid, _pendingReportId;
  bool _accountChanged = false;
  bool get _interactionBusy => _adminActionBusy || _isSendingReply;
  void _resumePendingOpen() {
    if (!mounted ||
        _interactionBusy ||
        _pendingReportId == null ||
        _accountChanged)
      return;
    final id = _pendingReportId!;
    _pendingReportId = null;
    _openReport(id);
  }

  Future<void> _openReport(String id) async {
    if (_accountChanged) return;
    if (_interactionBusy) {
      _pendingReportId = id;
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      setState(
        () => _directError =
            'Paste the full report reference using its Copy button.',
      );
      return;
    }
    setState(() {
      _openingReport = true;
      _directError = null;
    });
    final generation = ++_openGeneration;
    try {
      final data =
          await (widget.loadReport?.call(id) ??
              AdminReportService.context(reportId: id));
      if (!mounted || generation != _openGeneration) return;
      if (_interactionBusy) {
        _pendingReportId = id;
        return;
      }
      final report = UserReport.fromJson(
        Map<String, dynamic>.from(data['report'] as Map),
      );
      if (report.id != id) throw StateError('Report reference changed.');
      _selectReport(id, seed: report);
    } catch (_) {
      if (mounted && generation == _openGeneration)
        setState(
          () => _directError =
              'This report could not be opened. Check its ID and your connection, then retry.',
        );
    } finally {
      if (mounted && generation == _openGeneration)
        setState(() => _openingReport = false);
    }
  }

  @override
  void didUpdateWidget(covariant UserReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReportId != null &&
        (widget.initialReportId != oldWidget.initialReportId ||
            widget.openRequestRevision != oldWidget.openRequestRevision))
      _openReport(widget.initialReportId!);
  }

  ReportHistory? _history;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyWaitingResident) _queueStatus = 'waiting_resident';
    if (widget.initiallyUrgent) _queueStatus = 'urgent';
    if (widget.initiallyHistory) {
      _currentFilter = ReportFilterTab.all;
      _historyStatus = 'all';
    }
    if (Firebase.apps.isNotEmpty) {
      _openingUid = FirebaseAuth.instance.currentUser?.uid;
      _accountWatch = FirebaseAuth.instance.userChanges().listen((user) {
        if (user?.uid != _openingUid && mounted) {
          _openGeneration++;
          setState(() {
            _accountChanged = true;
            _pendingReportId = null;
            _replyDrafts.clear();
            _privateUpdateController.clear();
            _selectedReportId = null;
            _directReport = null;
            _openingReport = false;
          });
          widget.onSelectionChanged?.call(false);
        }
      });
    }
    if (widget.initiallyHistory)
      _changeFilter(ReportFilterTab.all, force: true);
    if (widget.initialReportId != null) _openReport(widget.initialReportId!);
    _calendarDay = TimeUtils.localDay(_now());
    WidgetsBinding.instance.addObserver(this);
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          (TimeUtils.localDay(_now()) != _calendarDay ||
              _currentFilter == ReportFilterTab.recent48h)) {
        setState(() => _calendarDay = TimeUtils.localDay(_now()));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _calendarDay = TimeUtils.localDay(_now()));
    }
  }

  List<UserReport> get _visibleReports {
    final live = {
      for (final report in AppStateService.instance.reports) report.id: report,
    };
    return _currentFilter == ReportFilterTab.actionable
        ? live.values.toList()
        : _history?.page.reports
                  .map(
                    (report) => live[report.id] == null
                        ? report
                        : fresherReport(report, live[report.id]!),
                  )
                  .toList() ??
              [];
  }

  void _changeFilter(ReportFilterTab tab, {bool force = false}) {
    if (tab == _currentFilter && !force) return;
    if (_interactionBusy) return;
    _selectReport(null);
    _history?.dispose();
    final history = tab == ReportFilterTab.actionable
        ? null
        : widget.historyLoader != null
        ? ReportHistory(widget.historyLoader!)
        : AppStateService.instance.createReportHistory(
            dismissReason:
                const [
                  'unable_to_verify',
                  'spam_false',
                  'duplicate_resolved',
                ].contains(_historyStatus)
                ? _historyStatus
                : null,
            statuses: _historyStatus == 'completed'
                ? ['verified', 'resolved', 'dismissed']
                : _historyStatus == 'all'
                ? null
                : const [
                    'unable_to_verify',
                    'spam_false',
                    'duplicate_resolved',
                  ].contains(_historyStatus)
                ? ['dismissed']
                : [_historyStatus],
            since: tab == ReportFilterTab.recent48h
                ? _now().subtract(const Duration(hours: 48))
                : null,
          );
    setState(() {
      _currentFilter = tab;
      _history = history;
      _selectedReportId = null;
    });
    widget.onSelectionChanged?.call(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _listScroll.hasClients) _listScroll.jumpTo(0);
    });
    history?.refresh();
  }

  @override
  void dispose() {
    _openGeneration++;
    _accountWatch?.cancel();
    _search.dispose();
    _dayTimer?.cancel();
    _listScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _history?.dispose();
    _privateUpdateController.dispose();
    super.dispose();
  }

  void _selectReport(
    String? reportId, {
    UserReport? seed,
    bool completedAction = false,
  }) {
    if (_accountChanged) return;
    if (_interactionBusy && !completedAction) {
      if (reportId != null) _pendingReportId = reportId;
      return;
    }
    final changed = _selectedReportId != reportId;
    _openGeneration++;
    final record =
        seed ?? _visibleReports.where((r) => r.id == reportId).firstOrNull;
    setState(() {
      if (changed) {
        if (_selectedReportId != null)
          _replyDrafts[_selectedReportId!] = _privateUpdateController.text;
        _privateUpdateController.text = reportId == null
            ? ''
            : _replyDrafts[reportId] ?? '';
      }
      _selectedReportId = reportId;
      if (reportId == null) {
        _directReport = null;
      } else if (record != null) {
        _directReport = record;
      }
      _openingReport = false;
      _directError = null;
    });
    widget.onSelectionChanged?.call(reportId != null);
  }

  List<Widget> _buildReportControls(
    ReportWorkload workload,
    bool liveQueue,
    bool history,
    DateTime now,
  ) {
    final p = AppPalette.of(context);
    Widget filter(
      String label,
      String value,
      Map<String, String> options,
      ValueChanged<String?> changed,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              tr(context, label),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.onSurface,
              ),
            ),
            if (label == 'Review outcome')
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showReportSearch = !_showReportSearch),
                icon: Icon(
                  _showReportSearch ? Icons.close : Icons.search,
                  size: 17,
                ),
                label: Text(
                  tr(context, 'Find report'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AdminChoiceField(
          key: ValueKey('$label-$value'),
          value: value,
          options: options,
          onChanged: changed,
        ),
      ],
    );
    Widget metric(String title, int count, IconData icon, VoidCallback tap) =>
        Material(
          color: p.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: tap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: p.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(context, title),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    liveQueue ? '$count' : '--',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: p.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 17,
                    color: p.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
    return [
      ReportPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!history) ...[
              filter(
                'Show reports',
                _queueStatus,
                {
                  'urgent': 'Urgent open reports',
                  'admin': 'Needs admin action',
                  'pending': 'Needs review',
                  'under_review': 'Under review',
                  'waiting_resident': 'Waiting for resident',
                  'all': 'All open reports',
                },
                (v) {
                  if (v != null) setState(() => _queueStatus = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    liveQueue
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 16,
                    color: liveQueue ? p.primary : p.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      tr(
                        context,
                        liveQueue
                            ? 'Live review queue'
                            : 'Queue may be incomplete. Reconnect to confirm the latest reports.',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (_directError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(context, _directError!),
                    style: TextStyle(color: p.error, fontSize: 12),
                  ),
                ),
            ] else ...[
              filter(
                'Review outcome',
                _historyStatus,
                {
                  'completed': 'Completed reviews',
                  'verified': 'Verified',
                  'resolved': 'Reviewed',
                  'unable_to_verify': 'Unable to verify',
                  'duplicate_resolved': 'Duplicate submission',
                  'spam_false': 'False / abusive report',
                  'dismissed': 'All dismissed reports',
                  'expired': 'Legacy outdated reports',
                  'all': 'All reports',
                },
                (v) {
                  if (v != null) {
                    _historyStatus = v;
                    _changeFilter(_currentFilter, force: true);
                  }
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr(context, 'Last 48 hours'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  tr(context, 'Based on submission time'),
                  style: const TextStyle(fontSize: 11),
                ),
                value: _currentFilter == ReportFilterTab.recent48h,
                onChanged: (v) => _changeFilter(
                  v ? ReportFilterTab.recent48h : ReportFilterTab.all,
                ),
              ),
              if (_showReportSearch) ...[
                Divider(
                  height: 24,
                  color: p.outlineVariant.withValues(alpha: .4),
                ),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _openingReport
                      ? null
                      : (value) => _openReport(value.trim()),
                  decoration: InputDecoration(
                    hintText: tr(context, 'Paste report reference'),
                    prefixIcon: const Icon(
                      Icons.receipt_long_outlined,
                      size: 20,
                    ),
                    suffixIcon: _openingReport
                        ? const Padding(
                            padding: EdgeInsets.all(15),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: tr(context, 'Open report'),
                            onPressed: () => _openReport(_search.text.trim()),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'Use the Copy button beside a report reference.'),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ],
              if (_directError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(context, _directError!),
                    style: TextStyle(color: p.error, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (!history) ...[
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ReportPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              leading: Icon(Icons.space_dashboard_outlined, color: p.primary),
              title: Text(
                tr(context, 'Workload summary'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                metric(
                  'Needs admin action',
                  workload.needsAdmin,
                  Icons.pending_actions_outlined,
                  () => setState(() => _queueStatus = 'admin'),
                ),
                const SizedBox(height: 8),
                metric(
                  'Waiting for resident',
                  workload.waiting,
                  Icons.question_answer_outlined,
                  () => setState(() => _queueStatus = 'waiting_resident'),
                ),
                if (workload.urgent > 0) ...[
                  const SizedBox(height: 8),
                  metric(
                    'Urgent requests',
                    workload.urgent,
                    Icons.warning_amber_rounded,
                    () => setState(() => _queueStatus = 'all'),
                  ),
                ],
                if (workload.oldest != null)
                  TextButton.icon(
                    onPressed: () => _selectReport(workload.oldest!.id),
                    icon: const Icon(Icons.schedule, size: 17),
                    label: Text(
                      '${tr(context, 'Oldest waiting report')}: ${localizedAge(context, workload.oldest!.createdAt, now)}',
                    ),
                  ),
                const SizedBox(height: 10),
                const ReportActivitySummary(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  bool _adminActionBusy = false;

  Future<void> _showDismissReasonSheet(
    BuildContext context,
    UserReport report, {
    VoidCallback? onDismissed,
  }) async {
    if (_adminActionBusy) return;
    setState(() => _adminActionBusy = true);
    try {
      final result = await showAdminDismiss(context, report.id);
      if (result != null && mounted) {
        _history?.refresh();
        onDismissed?.call();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.confirmation)));
      }
    } finally {
      if (mounted) setState(() => _adminActionBusy = false);
      _resumePendingOpen();
    }
  }

  Future<void> _startReview(UserReport report) async {
    if (_adminActionBusy) return;
    setState(() => _adminActionBusy = true);
    try {
      final latest = await AdminReportService.context(reportId: report.id);
      final result = await AdminReportService.perform('start', {
        'reportId': report.id,
        'contextToken': latest['token'],
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.confirmation)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Starting the review was not confirmed. Retry or refresh the report.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _adminActionBusy = false);
      _resumePendingOpen();
    }
  }

  Future<void> _verifyReport(UserReport report) async {
    if (_adminActionBusy) return;
    setState(() => _adminActionBusy = true);
    try {
      final result = await showAdminReview(context, reportId: report.id);
      if (result == null || !mounted) return;
      _history?.refresh();
      _selectReport(null, completedAction: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.confirmation)));
    } finally {
      if (mounted) setState(() => _adminActionBusy = false);
      _resumePendingOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;
    final headerHistory = _history;

    return PopScope(
      canPop:
          !widget.isActive ||
          (_selectedReportId == null && !widget.isStandalone),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !widget.isActive) return;
        if (_selectedReportId != null) {
          _selectReport(null);
        } else if (widget.isStandalone && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: _selectedReportId != null
            ? null
            : AppTopBar(
                title: tr(context, 'User Reports'),
                showBackButton:
                    _selectedReportId != null ||
                    widget.isStandalone ||
                    Navigator.canPop(context),
                showProfile: true,
                showSettingsAction: true,
                actions: [
                  if (headerHistory != null)
                    ListenableBuilder(
                      listenable: headerHistory,
                      builder: (context, _) => IconButton(
                        tooltip: tr(context, 'Refresh reports'),
                        onPressed: headerHistory.loading
                            ? null
                            : headerHistory.refresh,
                        icon: const Icon(Icons.refresh),
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                ],
                onBackPressed: () {
                  if (_selectedReportId != null) {
                    _selectReport(null);
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              ),
        backgroundColor: AppPalette.of(context).surface,
        body: ListenableBuilder(
          listenable: Listenable.merge([
            appState,
            if (_history != null) _history!,
          ]),
          builder: (context, _) {
            final allReports = _visibleReports;
            final incidents = appState.roads
                .where(
                  (road) => [
                    'reported_flooding',
                    'under_verification',
                    'outdated',
                  ].contains(road.communityCondition),
                )
                .toList();
            final now = _now();
            bool needsReview(UserReport report) => report.reviewOpen;
            final workload = ReportWorkload(appState.reports);
            final liveQueue =
                appState.syncHealth.channels['reports'] == SyncCondition.live;
            final showRoadReminders =
                _currentFilter == ReportFilterTab.actionable &&
                _queueStatus != 'urgent' &&
                incidents.isNotEmpty;

            List<UserReport> filteredReports;
            switch (_currentFilter) {
              case ReportFilterTab.actionable:
                filteredReports = allReports
                    .where(
                      (r) =>
                          needsReview(r) &&
                          (_queueStatus == 'all' ||
                              _queueStatus == 'urgent' && r.isEmergency ||
                              _queueStatus == 'admin' && r.needsAdminReview ||
                              r.status == _queueStatus),
                    )
                    .toList();
                break;
              case ReportFilterTab.recent48h:
                filteredReports = allReports
                    .where(
                      (r) =>
                          !r.createdAt.isAfter(now) &&
                          now.difference(r.createdAt) <=
                              const Duration(hours: 48),
                    )
                    .toList();
                break;
              case ReportFilterTab.all:
                filteredReports = List.from(allReports);
                break;
            }

            final groupedByDate = _currentFilter != ReportFilterTab.actionable;
            if (!groupedByDate) {
              filteredReports.sort(compareReportWorkload);
            } else {
              filteredReports.sort(compareReportSubmissions);
            }

            UserReport? selectedReport = _directReport?.id == _selectedReportId
                ? _directReport
                : null;
            if (_selectedReportId != null) {
              try {
                final live = allReports.firstWhere(
                  (r) => r.id == _selectedReportId,
                );
                selectedReport = selectedReport == null
                    ? live
                    : fresherReport(selectedReport, live);
              } catch (_) {}
            }

            return Stack(
              children: [
                // 1. The List & Filter Layer
                Positioned.fill(
                  child: ExcludeSemantics(
                    excluding: selectedReport != null,
                    child: Column(
                      children: [
                        // Plain tabs keep the filters readable without nested pills.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Material(
                            color: Colors.transparent,
                            child: Padding(
                              padding: EdgeInsets.zero,
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final filters = [
                                    _buildFilterTab(
                                      label: tr(context, 'Review queue'),
                                      isSelected:
                                          _currentFilter ==
                                          ReportFilterTab.actionable,
                                      onTap: () => _changeFilter(
                                        ReportFilterTab.actionable,
                                      ),
                                    ),
                                    _buildFilterTab(
                                      label: tr(context, 'History'),
                                      isSelected:
                                          _currentFilter !=
                                          ReportFilterTab.actionable,
                                      onTap: () =>
                                          _changeFilter(ReportFilterTab.all),
                                    ),
                                  ];
                                  if (MediaQuery.textScalerOf(
                                            context,
                                          ).scale(11) >
                                          16 ||
                                      box.maxWidth < 250) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: filters,
                                    );
                                  }
                                  return Row(
                                    children: [
                                      for (final filter in filters)
                                        Expanded(child: filter),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                        // Reports List
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_selectedReportId != null) {
                                _selectReport(null);
                              }
                            },
                            child: ListView.builder(
                              key: const ValueKey('report-list-scroll'),
                              controller: _listScroll,
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                _selectedReportId != null ? 400 : 120,
                              ),
                              itemCount:
                                  filteredReports.length +
                                  1 +
                                  (showRoadReminders ? 1 : 0),
                              itemBuilder: (context, position) {
                                if (showRoadReminders &&
                                    position == filteredReports.length + 1) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: AdminRoadCheckSection(
                                      roads: incidents,
                                      onOpen: (road) => Navigator.push(
                                        context,
                                        RoadDetailsScreen.route(road.id),
                                      ),
                                    ),
                                  );
                                }
                                if (position == 0)
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ..._buildReportControls(
                                        workload,
                                        liveQueue,
                                        groupedByDate,
                                        now,
                                      ),
                                      if (_history != null &&
                                          (_history!.pageNumber > 1 ||
                                              _history!.page.next != null))
                                        ReportHistoryControls(
                                          history: _history!,
                                          horizontalPadding: 0,
                                          compact: true,
                                          hideSinglePage: true,
                                          showRefresh: false,
                                          showStatus: false,
                                        ),
                                      if (groupedByDate && _history != null)
                                        AdminHistoryState(
                                          history: _history!,
                                          hasReports:
                                              filteredReports.isNotEmpty,
                                        ),
                                      if (groupedByDate &&
                                          filteredReports.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            12,
                                            4,
                                            4,
                                          ),
                                          child: Text(
                                            tr(
                                              context,
                                              'Grouped by submission date, newest first.',
                                            ),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppPalette.of(
                                                context,
                                              ).onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      if (!groupedByDate &&
                                          filteredReports.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Text(
                                            tr(
                                              context,
                                              liveQueue
                                                  ? 'No reports available in this view.'
                                                  : 'Reports are not confirmed current. Reconnect and retry.',
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                final index = position - 1;
                                final item = filteredReports[index];
                                final isActionable = [
                                  'pending',
                                  'under_review',
                                ].contains(item.status);
                                final road = appState.roads
                                    .where((r) => r.id == item.roadId)
                                    .firstOrNull;
                                final reporter = appState.users
                                    .where((u) => u.id == item.userId)
                                    .firstOrNull;
                                final showDay =
                                    groupedByDate &&
                                    (index == 0 ||
                                        TimeUtils.submissionDayKey(
                                              filteredReports[index - 1]
                                                  .createdAt,
                                              now,
                                            ) !=
                                            TimeUtils.submissionDayKey(
                                              item.createdAt,
                                              now,
                                            ));
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showDay)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          2,
                                          8,
                                          2,
                                          8,
                                        ),
                                        child: Text(
                                          localizedSubmissionDay(
                                            context,
                                            item.createdAt,
                                            now,
                                          ),
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppPalette.of(
                                              context,
                                            ).onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Dismissible(
                                        key: ValueKey(item.id),
                                        direction: isActionable
                                            ? DismissDirection.horizontal
                                            : DismissDirection.none,
                                        background: Container(
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppPalette.of(
                                              context,
                                            ).primary,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.fact_check_outlined,
                                            color: AppPalette.of(
                                              context,
                                            ).onPrimary,
                                          ),
                                        ),
                                        secondaryBackground: Container(
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppPalette.of(context).error,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.cancel_outlined,
                                            color: AppPalette.of(
                                              context,
                                            ).onError,
                                          ),
                                        ),
                                        confirmDismiss: (direction) async {
                                          if (_adminActionBusy ||
                                              _isSendingReply)
                                            return false;
                                          if (direction ==
                                              DismissDirection.endToStart) {
                                            await _showDismissReasonSheet(
                                              context,
                                              item,
                                              onDismissed: () {
                                                if (_selectedReportId ==
                                                    item.id)
                                                  _selectReport(
                                                    null,
                                                    completedAction: true,
                                                  );
                                              },
                                            );
                                          } else if (direction ==
                                              DismissDirection.startToEnd) {
                                            await _verifyReport(item);
                                          }
                                          return false;
                                        },
                                        child: UserReportCard(
                                          report: item,
                                          now: widget.now,
                                          showSubmissionClock: groupedByDate,
                                          road: road,
                                          reporterName: reporter?.name,
                                          selected:
                                              item.id == _selectedReportId,
                                          busy:
                                              _adminActionBusy ||
                                              _isSendingReply,
                                          roadNeedsAttention:
                                              !isActionable &&
                                              needsReview(item),
                                          onTap: () => _selectReport(
                                            item.id == _selectedReportId
                                                ? null
                                                : item.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. The Dynamic Floating Inspector Card
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  top: selectedReport != null ? 0 : null,
                  bottom: selectedReport != null ? 0 : -700,
                  left: 0,
                  right: 0,
                  child: selectedReport != null
                      ? LiveAdminReportDetails(
                          key: ValueKey(
                            'live-admin-report-${selectedReport.id}',
                          ),
                          seed: selectedReport,
                          changes: widget.selectedReportChanges,
                          onClose: () => _selectReport(null),
                          builder: (report, loading) =>
                              _buildFloatingCard(report, loading: loading),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? p.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.3,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? p.primary : p.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendPrivateUpdate(UserReport report) async {
    if (_adminActionBusy || _isSendingReply) return;
    setState(() => _isSendingReply = true);
    try {
      final result = await showModalBottomSheet<AdminActionResult>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => AdminReplyDialog(
          asSheet: true,
          reportId: report.id,
          report: report,
          controller: _privateUpdateController,
        ),
      );
      if (result == null || !mounted) return;
      _replyDrafts.remove(report.id);
      if (_selectedReportId == report.id) _privateUpdateController.clear();
      _history?.refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.confirmation)));
    } finally {
      if (mounted) setState(() => _isSendingReply = false);
      _resumePendingOpen();
    }
  }

  Future<void> _updateRoadStatus(
    RoadStatus road, {
    String? sourceReportId,
  }) async {
    if (_adminActionBusy || _isSendingReply) return;
    setState(() => _adminActionBusy = true);
    try {
      final result = await showAdminReview(
        context,
        roadIds: [road.id],
        sourceReportId: sourceReportId,
      );
      if (result == null || !mounted) return;
      _history?.refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.confirmation)));
    } finally {
      if (mounted) setState(() => _adminActionBusy = false);
      _resumePendingOpen();
    }
  }

  Future<void> _askForClarification(UserReport report) async {
    if (_adminActionBusy || _isSendingReply || !report.needsAdminReview) return;
    setState(() => _adminActionBusy = true);
    try {
      final result = await showAdminClarification(context, report.id);
      if (result != null && mounted) {
        _history?.refresh();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.confirmation)));
      }
    } finally {
      if (mounted) setState(() => _adminActionBusy = false);
      _resumePendingOpen();
    }
  }

  Widget _buildFloatingCard(UserReport report, {bool loading = false}) {
    final state = AppStateService.instance;
    final road = state.roads.where((r) => r.id == report.roadId).firstOrNull;
    final reporter = state.users
        .where((u) => u.id == report.userId)
        .firstOrNull;
    final original = report.isFollowup
        ? state.reports.where((r) => r.id == report.rootReportId).firstOrNull
        : null;
    return AdminReportWorkspace(
      key: ValueKey('admin-workspace-${report.id}'),
      now: widget.now,
      report: report,
      road: road,
      reporter: reporter,
      originalReport: original,
      busy: loading || _adminActionBusy || _isSendingReply,
      onClose: () => _selectReport(null),
      onDecision: () => _verifyReport(report),
      onAsk: report.needsAdminReview
          ? () => _askForClarification(report)
          : null,
      onMessage: report.reviewOpen ? () => _sendPrivateUpdate(report) : null,
      onStartReview: () => _startReview(report),
      onRoadUpdate: road == null
          ? null
          : () => _updateRoadStatus(road, sourceReportId: report.id),
      followupLink: ReportFollowupLink(
        report: report,
        readOnly: true,
        label: report.isFollowup
            ? 'View original report and follow-ups'
            : 'View follow-ups',
      ),
      correctionAction: FollowupCorrectionButton(
        report: report,
        onSaved: () {
          _history?.refresh();
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
