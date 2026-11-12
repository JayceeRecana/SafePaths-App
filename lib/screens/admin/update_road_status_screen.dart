import 'road_report_queue_screen.dart';
import '../../widgets/admin_choice_field.dart';
import '../../config/app_environment.dart';
import '../../services/road_maintenance_service.dart';
import '../../services/spark_proof_client.dart';
import '../../widgets/admin_review_dialog.dart';
import '../../services/admin_report_service.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../../services/sync_health.dart';
import '../../services/admin_road_overview.dart';
import '../../widgets/admin_road_summary.dart';
import '../../widgets/report_workflow_ui.dart';
import '../../widgets/road_condition_overview.dart' show residentRoadTitle;
import '../user/road_details_screen.dart';
import '../shared/full_screen_map_screen.dart';

class UpdateRoadStatusScreen extends StatefulWidget {
  final String? prefilledRoadId, reportIdToVerify, suggestedStatus, closureNote;
  final bool isStandalone, autoFocusSearch, isActive;
  final String initialFilter;
  final Function(bool)? onSelectionChanged;
  final Future<Map<String, dynamic>> Function()? loadReviewContext;
  const UpdateRoadStatusScreen({
    super.key,
    this.prefilledRoadId,
    this.reportIdToVerify,
    this.suggestedStatus,
    this.closureNote,
    this.isStandalone = false,
    this.isActive = true,
    this.autoFocusSearch = false,
    this.initialFilter = 'all',
    this.onSelectionChanged,
    this.loadReviewContext,
  });
  @override
  State<UpdateRoadStatusScreen> createState() => _UpdateRoadStatusScreenState();
}

class _UpdateRoadStatusScreenState extends State<UpdateRoadStatusScreen> {
  final _searchController = TextEditingController();
  String _filter = 'all';
  String? _selectedRoadId;
  Set<String> _selectedRoadIds = {};
  bool _floodProneOnly = false;
  bool _isMultiSelectMode = false,
      _isSubmitting = false,
      _lastHasSelection = false;
  static const filters = {
    'all': 'All roads',
    'needs_check': 'Needs a check',
    'restricted_recheck': 'Restricted roads to recheck',
    'not_passable': 'Not passable',
    'partial': 'Partially passable',
    'passable': 'Passable',
    'unconfirmed': 'Unconfirmed',
  };
  @override
  void initState() {
    super.initState();
    _selectedRoadId = widget.prefilledRoadId;
    _floodProneOnly = widget.initialFilter == 'flood_prone';
    _filter = filters.containsKey(widget.initialFilter)
        ? widget.initialFilter
        : 'all';
    _searchController.addListener(
      () => setState(() {
        _selectedRoadId = null;
        _selectedRoadIds.clear();
      }),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminRoadAssessment> _roads() {
    final weather = SimulatedWeatherService.instance.currentState;
    final query = _searchController.text.trim().toLowerCase();
    return AdminRoadOverview(
        AppStateService.instance.roads,
        DateTime.now(),
        weather,
      ).roads.where((r) {
        if (query.isNotEmpty &&
            !r.road.name.toLowerCase().contains(query) &&
            !r.road.id.toLowerCase().contains(query))
          return false;
        if (_floodProneOnly && r.road.vulnerability != 'high') return false;
        return switch (_filter) {
          'needs_check' => r.needsCheck,
          'restricted_recheck' =>
            const ['partial', 'not_passable'].contains(r.road.status) &&
                r.needsCheck,
          'all' => true,
          _ => r.category == _filter,
        };
      }).toList()
      ..sort(compareAdminRoads);
  }

  List<AdminRoadAssessment> get _selected => _roads()
      .where(
        (r) => _isMultiSelectMode
            ? _selectedRoadIds.contains(r.road.id)
            : r.road.id == _selectedRoadId,
      )
      .toList();
  void _submit() async {
    if (_isSubmitting) return;
    final ids = _selected.map((r) => r.road.id).toList();
    if (ids.isEmpty || ids.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Choose one to twenty roads to review.')),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final result = await showDialog<AdminActionResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AdminReviewDialog(
          reportId: widget.reportIdToVerify,
          roadIds: widget.reportIdToVerify == null ? ids : null,
          initialNote: widget.closureNote,
          showRoadSettings: widget.reportIdToVerify == null,
          quickConditions: widget.reportIdToVerify == null,
          loadContext: widget.loadReviewContext,
        ),
      );
      if (result == null || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.confirmation)));
      setState(() {
        _selectedRoadId = null;
        _selectedRoadIds.clear();
      });
      if (widget.isStandalone && Navigator.canPop(context))
        Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openReports(String id, String name) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RoadReportQueueScreen(roadId: id, roadName: name),
    ),
  );

  void _deleteRoad() async {
    final roadId = _selectedRoadId;
    if (roadId == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      Map<String, dynamic>? review;
      if (AppEnvironment.sparkCoreEnabled) {
        review = await RoadMaintenanceService.deleteContext(roadId);
        if (!mounted) return;
        if (review['canDelete'] != true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(review['reason'] as String)));
          return;
        }
      }
      if (!mounted) return;
      final confirm =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(context, 'Delete Road?')),
              content: Text(
                review == null
                    ? tr(
                        context,
                        'Are you sure you want to permanently delete this road from the database?',
                      )
                    : '${review['name']}\n${review['reason']}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(context, 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    tr(context, 'Delete'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirm || !mounted) return;
      await AppStateService.instance.deleteRoadStatus(
        roadId,
        contextToken: review?['token'] as String?,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                AppEnvironment.sparkCoreEnabled
                    ? 'Deletion saved. Refresh roads to see the current network.'
                    : 'Road deleted.',
              ),
            ),
          ),
        );
        setState(() {
          _selectedRoadId = null;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SparkProofException
                  ? e.message
                  : 'Deletion was not confirmed. Refresh the road and retry.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── SELECTION HANDLERS ──────────────────────────────────────────────

  void _select(String id) {
    if (_isSubmitting) return;
    setState(() {
      if (_isMultiSelectMode) {
        if (_selectedRoadIds.contains(id)) {
          _selectedRoadIds.remove(id);
        } else if (_selectedRoadIds.length < 20) {
          _selectedRoadIds.add(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(context, 'Choose one to twenty roads to review.'),
              ),
            ),
          );
        }
      } else {
        _selectedRoadId = _selectedRoadId == id ? null : id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateService.instance, p = AppPalette.of(context);
    return PopScope(
      canPop: !widget.isActive || (!_lastHasSelection && !widget.isStandalone),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !widget.isActive || _isSubmitting) return;
        if (_lastHasSelection) {
          setState(() {
            _selectedRoadId = null;
            _selectedRoadIds.clear();
            _isMultiSelectMode = false;
            _lastHasSelection = false;
          });
          widget.onSelectionChanged?.call(false);
        } else if (widget.isStandalone && Navigator.canPop(context))
          Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppTopBar(
          title: tr(context, 'Roads'),
          showProfile: true,
          showSettingsAction: true,
          showBackButton: widget.isStandalone || Navigator.canPop(context),
          actions: [
            PopupMenuButton<bool>(
              tooltip: tr(context, 'More filters'),
              icon: const Icon(Icons.tune),
              onSelected: (value) => setState(() {
                _floodProneOnly = value;
                _selectedRoadId = null;
                _selectedRoadIds.clear();
              }),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: !_floodProneOnly,
                  checked: _floodProneOnly,
                  child: Text(tr(context, 'Flood-prone roads only')),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: p.surface,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              state,
              SimulatedWeatherService.instance.listenable,
            ]),
            builder: (context, _) {
              final roads = _roads(), groups = reportsByRoad(state.reports);
              final selected = roads
                  .where(
                    (r) => _isMultiSelectMode
                        ? _selectedRoadIds.contains(r.road.id)
                        : r.road.id == _selectedRoadId,
                  )
                  .toList();
              final hasSelection = selected.isNotEmpty;
              if (hasSelection != _lastHasSelection) {
                _lastHasSelection = hasSelection;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onSelectionChanged?.call(hasSelection);
                });
              }
              final sync =
                  state.syncHealth.channels['roads'] ??
                  SyncCondition.connecting;
              return LayoutBuilder(
                builder: (context, bounds) => Column(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: bounds.maxHeight * .42,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: p.outlineVariant.withValues(
                                      alpha: .75,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: p.isDark ? .12 : .035,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      controller: _searchController,
                                      autofocus: widget.autoFocusSearch,
                                      enabled: !_isSubmitting,
                                      decoration: InputDecoration(
                                        hintText: tr(context, 'Find a road'),
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon:
                                            _searchController.text.isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: tr(context, 'Clear'),
                                                onPressed: () =>
                                                    _searchController.clear(),
                                                icon: const Icon(Icons.close),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _RoadToolbarActions(
                                      filter: AdminChoiceField(
                                        key: ValueKey('road-filter-$_filter'),
                                        value: _filter,
                                        label: 'Show roads',
                                        options: filters,
                                        onChanged: _isSubmitting
                                            ? null
                                            : (v) {
                                                if (v != null)
                                                  setState(() {
                                                    _filter = v;
                                                    _selectedRoadId = null;
                                                    _selectedRoadIds.clear();
                                                  });
                                              },
                                      ),
                                      select: _LabeledRoadTool(
                                        tooltip: _isMultiSelectMode
                                            ? 'Finish selecting'
                                            : 'Select multiple roads',
                                        label: _isMultiSelectMode
                                            ? 'Done'
                                            : 'Select roads',
                                        icon: _isMultiSelectMode
                                            ? Icons.check_box
                                            : Icons.checklist_outlined,
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => setState(() {
                                                _isMultiSelectMode =
                                                    !_isMultiSelectMode;
                                                _selectedRoadIds.clear();
                                                _selectedRoadId = null;
                                              }),
                                      ),
                                      map: _LabeledRoadTool(
                                        tooltip: 'Live Map',
                                        label: 'Map',
                                        icon: Icons.map_outlined,
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FullScreenMapScreen(
                                              initialRoadId: _selectedRoadId,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (sync != SyncCondition.live)
                                AdminDataNotice(
                                  label: 'Road conditions',
                                  condition: sync,
                                  hasRecords: state.roads.isNotEmpty,
                                  onRetry: state.retrySync,
                                ),
                              if (state.reports.isNotEmpty &&
                                  state.syncHealth.channels['reports'] !=
                                      SyncCondition.live)
                                AdminDataNotice(
                                  label: 'Report counts',
                                  condition:
                                      state.syncHealth.channels['reports'] ??
                                      SyncCondition.connecting,
                                  hasRecords: true,
                                  onRetry: state.retrySync,
                                ),
                              if (_floodProneOnly)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: InputChip(
                                    label: Text(
                                      tr(context, 'Flood-prone roads only'),
                                    ),
                                    onDeleted: () => setState(() {
                                      _floodProneOnly = false;
                                      _selectedRoadId = null;
                                      _selectedRoadIds.clear();
                                    }),
                                  ),
                                ),
                              if (_isMultiSelectMode) ...[
                                if (roads.length > 20)
                                  Text(
                                    tr(
                                      context,
                                      'Narrow this view to 20 roads or fewer to select matching roads.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: p.onSurfaceVariant,
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'select-matching-roads',
                                    ),
                                    onPressed:
                                        _isSubmitting ||
                                            roads.isEmpty ||
                                            roads.length > 20
                                        ? null
                                        : () => setState(() {
                                            _selectedRoadIds = roads
                                                .map((r) => r.road.id)
                                                .toSet();
                                          }),
                                    icon: const Icon(Icons.select_all),
                                    label: Text(
                                      '${tr(context, 'Select matching roads')} (${roads.length})',
                                    ),
                                  ),
                                ),
                              ],
                              if (_isMultiSelectMode)
                                Text(
                                  tr(
                                    context,
                                    'Select up to 20 roads. One condition and finding will apply to every selected road.',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: p.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: roads.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  tr(
                                    context,
                                    sync != SyncCondition.live &&
                                            state.roads.isEmpty
                                        ? 'Road data is not available yet.'
                                        : 'No roads match this view.',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              key: const PageStorageKey('admin-roads-list'),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: roads.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = roads[index];
                                final chosen = selected.any(
                                  (r) => r.road.id == item.road.id,
                                );
                                return AdminRoadSummary(
                                  key: ValueKey('admin-road-${item.road.id}'),
                                  assessment: item,
                                  workload: groups[item.road.id],
                                  reportsLive:
                                      state.syncHealth.channels['reports'] ==
                                      SyncCondition.live,
                                  onReports:
                                      groups[item.road.id]?.open.isNotEmpty ==
                                          true
                                      ? () => _openReports(
                                          item.road.id,
                                          item.road.name,
                                        )
                                      : null,
                                  selected: chosen,
                                  riskFresh: state.syncHealth.riskFresh,
                                  onTap: () => _select(item.road.id),
                                  trailing: Icon(
                                    chosen
                                        ? Icons.check_circle
                                        : Icons.chevron_right,
                                    color: chosen
                                        ? p.primary
                                        : p.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                    ),
                    if (hasSelection)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: bounds.maxHeight * .45,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: ReportPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (MediaQuery.textScalerOf(
                                          context,
                                        ).scale(14) <=
                                        20) ...[
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: p.primary.withValues(
                                            alpha: .09,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          _isMultiSelectMode
                                              ? Icons.checklist
                                              : Icons.edit_road_outlined,
                                          color: p.primary,
                                          size: 21,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!_isMultiSelectMode) ...[
                                            Text(
                                              tr(context, 'Selected road'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: p.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                          ],
                                          Text(
                                            _isMultiSelectMode
                                                ? '${selected.length} ${tr(context, 'roads selected')}'
                                                : residentRoadTitle(
                                                    selected.single.road.name,
                                                  ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16,
                                              height: 1.35,
                                              fontWeight: FontWeight.w700,
                                              color: p.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isMultiSelectMode)
                                      PopupMenuButton<String>(
                                        tooltip: tr(
                                          context,
                                          'More road actions',
                                        ),
                                        onSelected: (v) {
                                          if (v == 'delete') _deleteRoad();
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              tr(context, 'Delete Road'),
                                            ),
                                          ),
                                        ],
                                        icon: Icon(
                                          Icons.more_horiz,
                                          color: p.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: tr(context, 'Clear selection'),
                                      onPressed: _isSubmitting
                                          ? null
                                          : () => setState(() {
                                              _selectedRoadId = null;
                                              _selectedRoadIds.clear();
                                            }),
                                      icon: Icon(
                                        Icons.close,
                                        color: p.onSurfaceVariant,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (!_isMultiSelectMode)
                                  LayoutBuilder(
                                    builder: (context, space) {
                                      final stack =
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) >
                                          20;
                                      Widget action(
                                        IconData icon,
                                        String label,
                                        VoidCallback onPressed,
                                      ) => TextButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : onPressed,
                                        icon: Icon(icon, size: 18),
                                        label: Text(
                                          tr(context, label),
                                          textAlign: TextAlign.center,
                                        ),
                                        style: TextButton.styleFrom(
                                          backgroundColor:
                                              p.surfaceContainerLow,
                                          foregroundColor: p.primary,
                                          minimumSize: const Size(48, 48),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                          textStyle: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0,
                                              ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      );
                                      final details = action(
                                        Icons.info_outline,
                                        'Road details',
                                        () => Navigator.push(
                                          context,
                                          RoadDetailsScreen.route(
                                            selected.single.road.id,
                                          ),
                                        ),
                                      );
                                      final reports = action(
                                        Icons.fact_check_outlined,
                                        'Road reports',
                                        () => _openReports(
                                          selected.single.road.id,
                                          selected.single.road.name,
                                        ),
                                      );
                                      return stack
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                details,
                                                const SizedBox(height: 8),
                                                reports,
                                              ],
                                            )
                                          : IntrinsicHeight(
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Expanded(child: details),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: reports),
                                                ],
                                              ),
                                            );
                                    },
                                  )
                                else
                                  Text(
                                    tr(
                                      context,
                                      'Review each selected road before applying one shared update.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: p.warning,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  key: const ValueKey('open-road-review'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 13,
                                    ),
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0,
                                        ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _isSubmitting ? null : _submit,
                                  icon: const Icon(Icons.edit_road_outlined),
                                  label: Text(
                                    tr(
                                      context,
                                      widget.reportIdToVerify == null
                                          ? 'Update road status'
                                          : 'Review report',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LabeledRoadTool extends StatelessWidget {
  final String label, tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _LabeledRoadTool({
    required this.label,
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr(context, tooltip),
    child: SizedBox(
      width: 72,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 64),
          backgroundColor: AppPalette.of(
            context,
          ).primary.withValues(alpha: .07),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: AppPalette.of(context).primary.withValues(alpha: .16),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(
              tr(context, label),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoadToolbarActions extends StatelessWidget {
  final Widget filter, select, map;
  const _RoadToolbarActions({
    required this.filter,
    required this.select,
    required this.map,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 320 || MediaQuery.textScalerOf(context).scale(12) > 17)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filter,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: select),
                const SizedBox(width: 10),
                Expanded(child: map),
              ],
            ),
          ],
        );
      return Row(
        children: [
          Expanded(child: filter),
          const SizedBox(width: 8),
          select,
          const SizedBox(width: 8),
          map,
        ],
      );
    },
  );
}
