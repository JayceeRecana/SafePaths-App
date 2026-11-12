import 'package:google_fonts/google_fonts.dart';
import '../l10n/formatters.dart';
import 'admin_dismiss_dialog.dart';
import '../services/road_location_preview.dart' show RoadPreviewCapture;
import 'road_location_preview.dart';
import '../services/admin_road_overview.dart';
import '../services/app_state_service.dart';
import '../services/weather_service.dart';
import 'admin_road_summary.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';
import 'road_condition_overview.dart' show residentRoadTitle;
import 'report_submission_preview.dart';
import 'report_workflow_ui.dart';
import '../models/user_report.dart';
import '../screens/user/report_clarification_screen.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../services/admin_report_service.dart';
import 'safe_image.dart';

Future<AdminActionResult?> showAdminReview(
  BuildContext context, {
  String? reportId,
  String? sourceReportId,
  List<String>? roadIds,
  String? initialStatus,
  String? initialNote,
  String? vulnerability,
}) => reportId != null
    ? showModalBottomSheet<AdminActionResult>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => AdminReviewDialog(
          reportId: reportId,
          initialNote: initialNote,
          decisionSheet: true,
        ),
      )
    : showDialog<AdminActionResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AdminReviewDialog(
          reportId: reportId,
          sourceReportId: sourceReportId,
          roadIds: roadIds,
          initialStatus: initialStatus,
          initialNote: initialNote,
          vulnerability: vulnerability,
        ),
      );

class AdminReviewDialog extends StatefulWidget {
  final String? reportId,
      sourceReportId,
      initialStatus,
      initialNote,
      vulnerability;
  final bool showRoadSettings, mapSheet, quickConditions, decisionSheet;
  final RoadStatus? previewRoad;
  final RoadPreviewCapture Function()? previewCapture;
  final ScrollController? scrollController;
  final List<String>? roadIds;
  final Future<Map<String, dynamic>> Function()? loadContext;
  final Future<AdminActionResult> Function(String, Map<String, dynamic>)?
  perform;
  const AdminReviewDialog({
    super.key,
    this.reportId,
    this.sourceReportId,
    this.roadIds,
    this.showRoadSettings = false,
    this.decisionSheet = false,
    this.mapSheet = false,
    this.quickConditions = false,
    this.previewRoad,
    this.previewCapture,
    this.scrollController,
    this.initialStatus,
    this.initialNote,
    this.vulnerability,
    this.loadContext,
    this.perform,
  });
  @override
  State<AdminReviewDialog> createState() => _AdminReviewDialogState();
}

class _AdminReviewDialogState extends State<AdminReviewDialog> {
  late final TextEditingController _note;
  Map<String, dynamic>? _context;
  String? _status, _vulnerability;
  int _conditionEpoch = 0;
  bool? _decisionVerified;
  bool _observationOnly = false;
  bool _verified = false,
      _loading = true,
      _saving = false,
      _meaningfulFollowup = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.initialNote ?? '');
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _verified = false;
      _meaningfulFollowup = false;
      _context = null;
      _status = null;
      _vulnerability = widget.vulnerability;
      _conditionEpoch++;
    });
    try {
      final data =
          await (widget.loadContext?.call() ??
              AdminReportService.context(
                reportId: widget.reportId,
                sourceReportId: widget.sourceReportId,
                roadIds: widget.roadIds,
              ));
      if (widget.sourceReportId != null) {
        if (data['reportRoadLinkSupported'] != true) {
          if (mounted)
            setState(
              () => _error =
                  'This backend cannot retain the report reference yet. No update was saved.',
            );
          return;
        }
        final source = data['sourceReport'];
        if (widget.reportId != null ||
            source is! Map ||
            source['id'] != widget.sourceReportId ||
            widget.roadIds?.length != 1 ||
            source['roadId'] != widget.roadIds!.single) {
          if (mounted)
            setState(
              () => _error =
                  'The linked report could not be confirmed for this road. Reopen it from Report details.',
            );
          return;
        }
      }
      if (mounted)
        setState(() {
          _context = data;
          _observationOnly =
              widget.reportId != null && data['workflowVersion'] == 2;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The latest report and road details could not be loaded. Retry before reviewing.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _loading ||
        _context == null ||
        (!_observationOnly && _status == null) ||
        (!_quickCheck && !_verified) ||
        _note.text.trim().length < 10)
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final action = widget.reportId == null ? 'road_review' : 'verify';
      final details = <String, dynamic>{
        if (widget.reportId != null) 'reportId': widget.reportId,
        if (widget.roadIds != null) 'roadIds': widget.roadIds,
        if (widget.sourceReportId != null)
          'sourceReportId': widget.sourceReportId,
        'contextToken': _context!['token'],
        if (!_observationOnly) 'roadStatus': _status,
        if (_observationOnly) 'observationOnly': true,
        'note': _note.text.trim(),
        if (!_observationOnly) 'verifiedCurrentConditions': true,
        if ((_context!['report'] as Map?)?['reportType'] == 'followup')
          'meaningfulFollowup': _meaningfulFollowup,
        if (_vulnerability != null) 'vulnerability': _vulnerability,
      };
      final result = await (widget.perform ?? AdminReportService.perform)(
        action,
        details,
      );
      if (result.sourceReportId != widget.sourceReportId)
        throw StateError('The report reference was not confirmed.');
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The save was not confirmed. Keep this review and retry. If new information arrived, refresh the latest details and verify them again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Direct road edits attest through the explicit final button. Report reviews
  // keep their separate evidence confirmation and reward safeguards.
  bool get _quickCheck => widget.quickConditions && widget.reportId == null;

  Widget _quickChoices() {
    final p = AppPalette.of(context);
    {
      final stacked =
          (MediaQuery.sizeOf(context).width - 72) < 220 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      Widget choice(String value) {
        final selected = _status == value, color = _conditionColor(value);
        final label = Text(
          tr(
            context,
            value == 'partial' ? 'Partial' : roadConditionLabel(value),
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        );
        final icon = Icon(
          selected
              ? Icons.check_circle
              : switch (value) {
                  'not_passable' => Icons.block,
                  'partial' => Icons.warning_amber_rounded,
                  _ => Icons.route_outlined,
                },
          size: 21,
        );
        return Semantics(
          selected: selected,
          child: Tooltip(
            message: tr(context, roadConditionLabel(value)),
            child: OutlinedButton(
              key: ValueKey('quick-condition-$value'),
              onPressed: _saving || _loading || _context == null
                  ? null
                  : () => setState(() {
                      _status = value;
                      _verified = false;
                    }),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                foregroundColor: color,
                backgroundColor: selected
                    ? color.withValues(alpha: .12)
                    : p.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(
                  color: selected ? color : p.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: stacked
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: 10),
                        Expanded(child: label),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(height: 7), label],
                    ),
            ),
          ),
        );
      }

      const values = ['not_passable', 'partial', 'passable'];
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  choice(values[i]),
                ],
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: choice(values[i])),
                  ],
                ],
              ),
            );
    }
  }

  Widget _locationPreview(List<dynamic> roads) => RoadLocationPreview(
    capture: widget.previewCapture,
    roads: [
      for (final value in roads.whereType<Map>())
        if (value['id'] is String)
          RoadStatus(
            id: value['id'] as String,
            name: '${value['name'] ?? 'Road'}',
            status: 'unknown',
            notes: '',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            geometry: value['geometry'] is Map
                ? Map<String, dynamic>.from(value['geometry'] as Map)
                : AppStateService.instance.roads
                      .where((r) => r.id == value['id'])
                      .firstOrNull
                      ?.geometry,
          ),
    ],
  );

  Widget _surface({
    required bool scrollable,
    required Color backgroundColor,
    required EdgeInsets insetPadding,
    required ShapeBorder shape,
    required EdgeInsets titlePadding,
    required EdgeInsets contentPadding,
    required EdgeInsets actionsPadding,
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) {
    if (!widget.mapSheet)
      return AlertDialog(
        scrollable: scrollable,
        backgroundColor: backgroundColor,
        insetPadding: insetPadding,
        shape: shape,
        titlePadding: titlePadding,
        contentPadding: contentPadding,
        actionsPadding: actionsPadding,
        title: title,
        content: content,
        actions: actions,
      );
    final p = AppPalette.of(context);
    final roads = (_context?['roads'] as List?) ?? const [];
    final latest = roads
        .whereType<Map>()
        .where((r) => r['id'] == widget.previewRoad?.id)
        .firstOrNull;
    final name = residentRoadTitle(
      '${latest?['name'] ?? widget.previewRoad?.name ?? 'Road'}',
    );
    final roadName = Text(
      name == 'Unnamed residential road' ? tr(context, name) : name,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: p.onSurface,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final record = latest != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'Latest recorded condition'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.primary,
                ),
              ),
              _roadRecord(latest, showName: false),
            ],
          )
        : widget.previewRoad != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _conditionLabel(widget.previewRoad!.status),
              _explanation(
                'Saved condition. Loading the latest road details...',
              ),
            ],
          )
        : const SizedBox();
    return Material(
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: LayoutBuilder(
        builder: (context, bounds) {
          // Large accessibility text and the keyboard must never squeeze the form
          // between an oversized fixed header and footer. Let the whole form scroll.
          final compact = MediaQuery.textScalerOf(context).scale(14) > 20;
          if (compact)
            return SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 12),
                  roadName,
                  const SizedBox(height: 12),
                  record,
                  content,
                  const SizedBox(height: 16),
                  actions.last,
                  const SizedBox(height: 8),
                  actions.first,
                ],
              ),
            );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: title,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: roadName,
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: widget.scrollController,
                  padding: contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [record, content],
                  ),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(child: actions.first),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: actions.last),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, {bool emphasis = false}) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      tr(context, title),
      style: TextStyle(
        fontSize: emphasis ? 14 : 13,
        fontWeight: FontWeight.w800,
        color: emphasis
            ? AppPalette.of(context).primary
            : AppPalette.of(context).onSurface,
      ),
    ),
  );
  Widget _explanation(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      tr(context, text),
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: AppPalette.of(context).onSurfaceVariant,
      ),
    ),
  );
  Color _conditionColor(String? status) {
    final p = AppPalette.of(context);
    return switch (status) {
      'not_passable' => p.error,
      'partial' => p.warning,
      'passable' => p.passable,
      _ => p.onSurfaceVariant,
    };
  }

  Widget _conditionLabel(String? status, {bool prominent = false}) => Row(
    children: [
      Icon(
        switch (status) {
          'not_passable' => Icons.block,
          'partial' => Icons.warning_amber_rounded,
          'passable' => Icons.route_outlined,
          _ => Icons.help_outline,
        },
        size: prominent ? 24 : 16,
        color: _conditionColor(status),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          tr(context, roadConditionLabel(status)),
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: prominent ? 18 : 12,
            fontWeight: prominent ? FontWeight.w800 : FontWeight.w600,
            color: _conditionColor(status),
          ),
        ),
      ),
    ],
  );
  Widget _roadRecord(Map value, {bool showName = true}) {
    final p = AppPalette.of(context);
    final name = residentRoadTitle('${value['name'] ?? 'Road'}');
    final updated = value['updatedAt'] is String
        ? DateTime.tryParse(value['updatedAt'])
        : null;
    final local = AppStateService.instance.roads
        .where((r) => r.id == value['id'])
        .firstOrNull;
    final record = RoadStatus(
      id: '${value['id'] ?? ''}',
      name: '${value['name'] ?? 'Road'}',
      status: value['status'] is String ? value['status'] as String : 'unknown',
      notes: '',
      updatedAt: updated ?? DateTime.fromMillisecondsSinceEpoch(0),
      isVerified: value['isVerified'] == true,
      source: value['source'] is String ? value['source'] as String : 'manual',
      vulnerability: value['vulnerability'] is String
          ? value['vulnerability'] as String
          : 'high',
      communityCondition: value['communityCondition'] is String
          ? value['communityCondition'] as String
          : local?.communityCondition,
    );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showName)
            Text(
              name == 'Unnamed residential road' ? tr(context, name) : name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          AdminRoadConditionDetails(
            assessment: AdminRoadAssessment(
              record,
              DateTime.now(),
              SimulatedWeatherService.instance.currentState,
              verificationKnown: value['isVerified'] is bool,
            ),
          ),
          if (value['id'] is String)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  tr(context, 'Road reference'),
                  style: TextStyle(fontSize: 11, color: p.primary),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      '${value['id']}',
                      style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roadRecords(List<dynamic> roads) {
    final p = AppPalette.of(context);
    return ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history_outlined, size: 18, color: p.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(context, 'Latest recorded condition'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
              ),
            ],
          ),
          if (roads.length == 1)
            _roadRecord(roads.single as Map)
          else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '${roads.length} ${tr(context, 'roads selected')}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                tr(context, 'View selected roads'),
                style: TextStyle(fontSize: 12, color: p.primary),
              ),
              children: [for (final road in roads) _roadRecord(road as Map)],
            ),
          if (widget.sourceReportId != null)
            ReportReference(
              reportId: widget.sourceReportId!,
              label: 'Opened from report',
            ),
          if (roads.length > 1)
            _explanation(
              'The condition you choose will apply to all selected roads.',
            ),
        ],
      ),
    );
  }

  Widget _decisionRoadPanel(Map road, bool available) {
    final p = AppPalette.of(context);
    final status = road['status'] is String
        ? road['status'] as String
        : 'unknown';
    final unknown =
        road['isVerified'] != true ||
        !const ['passable', 'partial', 'not_passable'].contains(status);
    final color = unknown ? p.onWarningContainer : _conditionColor(status);
    final icon = unknown
        ? Icons.help_outline
        : status == 'not_passable'
        ? Icons.block
        : status == 'partial'
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    final updated = road['updatedAt'] is String
        ? DateTime.tryParse(road['updatedAt'] as String)
        : null;
    final knownTime =
        updated != null &&
        updated.millisecondsSinceEpoch > 0 &&
        !updated.isAfter(DateTime.now().add(const Duration(minutes: 1)));
    Widget badge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? .16 : .08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              tr(
                context,
                unknown
                    ? 'Current condition unknown'
                    : roadConditionLabel(status),
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    final change = OutlinedButton.icon(
      onPressed: available && road['id'] is String
          ? () async {
              setState(() => _saving = true);
              try {
                await showAdminReview(
                  context,
                  roadIds: [road['id'] as String],
                  sourceReportId: widget.reportId,
                );
              } finally {
                if (mounted) setState(() => _saving = false);
              }
              if (mounted) await _load();
            }
          : null,
      icon: const Icon(Icons.edit_road_outlined, size: 16),
      label: Text(tr(context, 'Change')),
      style: OutlinedButton.styleFrom(
        textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history_outlined, size: 16, color: p.onSurfaceVariant),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tr(context, 'Latest recorded road condition'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (MediaQuery.textScalerOf(context).scale(12) > 17)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [badge(), const SizedBox(height: 8), change],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: badge()),
                ),
                const SizedBox(width: 8),
                change,
              ],
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 14,
                color: p.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  knownTime
                      ? '${tr(context, 'Updated')}: ${localizedDateTime(context, updated)}'
                      : tr(context, 'Road update time needs confirmation'),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: p.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tr(
                    context,
                    'Report verification leaves this road status unchanged.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _decisionSurface() {
    final p = AppPalette.of(context), report = _context?['report'] as Map?;
    final roads = (_context?['roads'] as List?) ?? const [];
    final root = _context?['rootReport'] as Map?;
    final originalPending = const [
      'pending',
      'under_review',
      'waiting_resident',
    ].contains(root?['status']);
    final road = roads.length == 1 ? roads.single as Map : null;
    final available =
        !_loading &&
        !_saving &&
        _context != null &&
        _context?['workflowVersion'] == 2 &&
        _context?['selfReview'] != true &&
        const [
          'pending',
          'under_review',
          'waiting_resident',
        ].contains(report?['status']);
    Widget choice(
      bool verify,
      String label,
      String detail,
      IconData icon,
      Color color,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: _decisionVerified == verify,
        child: InkWell(
          onTap: available
              ? () => setState(() {
                  _decisionVerified = verify;
                  _verified = false;
                })
              : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _decisionVerified == verify
                  ? color.withValues(alpha: p.isDark ? .08 : .045)
                  : p.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _decisionVerified == verify
                    ? color
                    : p.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, label),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: p.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tr(context, detail),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _decisionVerified == verify
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: _decisionVerified == verify ? color : p.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !_saving,
      child: ReportActionSheet(
        title: 'Your decision',
        children: [
          Text(
            tr(
              context,
              'About the resident observation. The resident will be told.',
            ),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: p.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(),
          choice(
            true,
            'Verified',
            'The observation is supported by the evidence.',
            Icons.check_circle_outline,
            p.passable,
          ),
          choice(
            false,
            'Not verified',
            'Choose a reason in the next step.',
            Icons.help_outline,
            p.onWarningContainer,
          ),
          if (_decisionVerified == true) ...[
            const SizedBox(height: 8),
            ReportPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 18, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, 'Explain your decision'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    enabled: available,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 1000,
                    onChanged: (_) => setState(() {
                      _verified = false;
                      _meaningfulFollowup = false;
                    }),
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: p.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: tr(
                        context,
                        'Describe the evidence you checked...',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: p.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: p.surfaceContainerLow,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: p.outlineVariant.withValues(alpha: .45),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: p.outlineVariant.withValues(alpha: .45),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, 'Minimum 10 characters'),
                          style: TextStyle(
                            fontSize: 10,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${_note.text.length}/1000',
                        style: TextStyle(
                          fontSize: 10,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    color: p.outlineVariant.withValues(alpha: .35),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    activeColor: p.passable,
                    value: _verified,
                    onChanged: available
                        ? (v) => setState(() => _verified = v == true)
                        : null,
                    title: Text(
                      tr(
                        context,
                        'I checked the submitted evidence and observation time.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (report?['reportType'] == 'followup')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _meaningfulFollowup,
                onChanged:
                    available && report?['conditionChange'] != 'unchanged'
                    ? (v) => setState(() => _meaningfulFollowup = v == true)
                    : null,
                title: Text(
                  tr(
                    context,
                    'I verified a meaningful change beyond the earlier submissions. Eligible for up to +5 trust points.',
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
          ],
          if (road != null) _decisionRoadPanel(road, available),
          if (report?['clarificationRequestId'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: available
                    ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReportClarificationScreen(
                              reportId: widget.reportId!,
                              isAdmin: true,
                              report: UserReport.fromJson({
                                ...Map<String, dynamic>.from(report!),
                                'id': widget.reportId,
                              }),
                            ),
                          ),
                        );
                        if (mounted) await _load();
                      }
                    : null,
                style: TextButton.styleFrom(
                  backgroundColor: p.primary.withValues(alpha: .05),
                  minimumSize: const Size(48, 44),
                  textStyle: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.question_answer_outlined, size: 16),
                label: Text(tr(context, 'Read the question and reply')),
              ),
            ),
          if (originalPending) ...[
            Text(
              tr(
                context,
                'Review the original observation first so that its outcome and reward remain separate.',
              ),
            ),
            TextButton(
              onPressed: available && root?['id'] is String
                  ? () async {
                      await showAdminReview(
                        context,
                        reportId: root!['id'] as String,
                      );
                      if (mounted) await _load();
                    }
                  : null,
              child: Text(tr(context, 'Review original report')),
            ),
          ],
          if (!_loading &&
              report != null &&
              !const [
                'pending',
                'under_review',
                'waiting_resident',
              ].contains(report['status']))
            Text(
              tr(
                context,
                'This report has already been reviewed. Close this decision and check the latest details.',
              ),
            ),
          if (_context?['selfReview'] == true)
            Text(
              tr(
                context,
                'Another administrator must review your own report or follow-up.',
              ),
            ),
          if (_error != null) ...[
            Text(
              tr(context, _error!),
              style: TextStyle(color: p.error, fontSize: 12),
            ),
            TextButton(
              onPressed: _saving ? null : _load,
              child: Text(tr(context, 'Refresh latest details')),
            ),
          ],
        ],
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('admin-review-save'),
            onPressed:
                !available ||
                    _decisionVerified == null ||
                    (_decisionVerified == true &&
                        (originalPending ||
                            !_observationOnly ||
                            !_verified ||
                            _note.text.trim().length < 10))
                ? null
                : () async {
                    if (_decisionVerified == true) {
                      await _save();
                    } else {
                      setState(() => _saving = true);
                      try {
                        final result = await showAdminDismiss(
                          context,
                          widget.reportId!,
                          asSheet: true,
                        );
                        if (result != null && mounted)
                          Navigator.pop(context, result);
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    }
                  },
            child: Text(
              tr(
                context,
                _saving
                    ? 'Confirming save...'
                    : _decisionVerified == false
                    ? 'Continue to reason'
                    : 'Save decision',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decisionSheet) return _decisionSurface();
    final p = AppPalette.of(context);
    final roadOnly = widget.reportId == null;
    final saveLabel = roadOnly
        ? (_quickCheck ? 'Confirm and save' : 'Save road status')
        : _observationOnly
        ? 'Verify observation'
        : 'Verify and update road';
    final report = _context?['report'] as Map?;
    final roads = (_context?['roads'] as List?) ?? const [];
    final root = _context?['rootReport'] as Map?;
    final originalNeedsReview = const [
      'pending',
      'under_review',
      'waiting_resident',
    ].contains(root?['status']);
    return PopScope(
      canPop: !_saving,
      child: _surface(
        scrollable: true,
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                roadOnly ? Icons.edit_road_outlined : Icons.fact_check_outlined,
                size: 22,
                color: p.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(
                  context,
                  roadOnly ? 'Update road status' : 'Verify observation',
                ),
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_context?['selfReview'] == true)
              Text(
                tr(
                  context,
                  'Another administrator must review your own report or follow-up.',
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            if (report != null) ...[
              if (report['reportType'] == 'followup')
                Text(
                  tr(
                    context,
                    'Follow-up: review the new observation separately from the original report.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              _section('1. Check the resident observation'),
              Text(
                '${report['title']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${report['description']}'),
              const SizedBox(height: 12),
              ReportPanel(
                child: ReportEvidenceContext(
                  report: UserReport.fromJson(
                    Map<String, dynamic>.from(report),
                  ),
                ),
              ),
              if (widget.reportId != null &&
                  report['clarificationRequestId'] is String)
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReportClarificationScreen(
                                reportId: widget.reportId!,
                                report: UserReport.fromJson({
                                  ...Map<String, dynamic>.from(report),
                                  'id': widget.reportId!,
                                }),
                                isAdmin: true,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                  icon: const Icon(Icons.question_answer_outlined),
                  label: Text(
                    tr(context, 'Read question and reply before deciding'),
                  ),
                ),
              if (report['imageUrl'] is String)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SafeImage(
                      imageUrl: report['imageUrl'] as String,
                      height: 130,
                    ),
                  ),
                ),
            ],
            if (root != null) ...[
              if (originalNeedsReview) ...[
                Text(
                  tr(
                    context,
                    'Review the original observation first so that its outcome and reward remain separate.',
                  ),
                ),
                TextButton(
                  onPressed: _saving || root['id'] is! String
                      ? null
                      : () async {
                          final result = await showAdminReview(
                            context,
                            reportId: root['id'] as String,
                          );
                          if (result != null && mounted) await _load();
                        },
                  child: Text(tr(context, 'Review original report')),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                tr(context, 'Earlier report for comparison'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${(root['originalSubmission'] as Map?)?['description'] ?? root['description']}',
              ),
              Text(
                tr(
                  context,
                  'Earlier photos are not evidence of the latest conditions.',
                ),
              ),
              if ((root['originalSubmission'] as Map?)?['imageUrl'] is String ||
                  root['imageUrl'] is String)
                SafeImage(
                  imageUrl:
                      ((root['originalSubmission'] as Map?)?['imageUrl'] ??
                              root['imageUrl'])
                          as String,
                  height: 100,
                ),
            ],
            if (roads.isNotEmpty && !widget.mapSheet) ...[
              const SizedBox(height: 14),
              _locationPreview(roads),
              const SizedBox(height: 14),
              _roadRecords(roads),
            ],
            if (!roadOnly)
              _explanation(
                'Verify the resident observation. Update the road only if you have checked its current condition.',
              ),
            if (widget.initialStatus != null)
              Text(
                '${tr(context, 'Previously selected condition')}: ${tr(context, roadConditionLabel(widget.initialStatus))}',
              ),
            if (widget.reportId != null && _context?['workflowVersion'] == 2)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr(context, 'Also update the current road condition'),
                ),
                subtitle: Text(
                  tr(
                    context,
                    'Leave off if you can only verify the earlier observation.',
                  ),
                ),
                value: !_observationOnly,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _observationOnly = !value;
                        _verified = false;
                      }),
              ),
            if (!_observationOnly) ...[
              _section(
                roadOnly
                    ? '1. Set the new road status'
                    : '2. Set the new road status',
                emphasis: true,
              ),
              if (_quickCheck)
                _quickChoices()
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('review-condition:$_conditionEpoch'),
                  isExpanded: true,
                  isDense: MediaQuery.textScalerOf(context).scale(13) <= 18,
                  itemHeight: null,
                  initialValue: _status,
                  menuMaxHeight: 360,
                  selectedItemBuilder: (_) => [
                    for (final value in ['not_passable', 'partial', 'passable'])
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _conditionLabel(value, prominent: true),
                      ),
                  ],
                  dropdownColor: p.surfaceContainerLow,
                  iconEnabledColor: p.onSurfaceVariant,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: 14,
                    color: p.onSurface,
                  ),
                  hint: Text(
                    tr(context, 'Select road status'),
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _status == null
                        ? p.surfaceContainerLow
                        : _conditionColor(_status).withValues(alpha: .08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color:
                            (_status == null
                                    ? p.primary
                                    : _conditionColor(_status))
                                .withValues(alpha: .65),
                        width: 1.3,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color:
                            (_status == null
                                    ? p.primary
                                    : _conditionColor(_status))
                                .withValues(alpha: .65),
                        width: 1.3,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _status == null
                            ? p.primary
                            : _conditionColor(_status),
                        width: 1.8,
                      ),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'not_passable',
                      child: Text(tr(context, 'Not passable')),
                    ),
                    DropdownMenuItem(
                      value: 'partial',
                      child: Text(tr(context, 'Partially passable')),
                    ),
                    DropdownMenuItem(
                      value: 'passable',
                      child: Text(tr(context, 'Passable')),
                    ),
                  ],
                  onChanged: _saving || _loading || _context == null
                      ? null
                      : (value) {
                          if (value != null)
                            setState(() {
                              _status = value;
                              _verified = false;
                              _meaningfulFollowup = false;
                            });
                        },
                ),
            ],
            _section(
              roadOnly
                  ? '2. Describe the check'
                  : _observationOnly
                  ? '2. Explain your decision'
                  : '3. Describe the check',
            ),
            Text(
              tr(
                context,
                _observationOnly
                    ? 'What supports the resident observation?'
                    : 'Who checked, when, and what did they find?',
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: p.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLength: 1000,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => Text(
                    '$currentLength/$maxLength',
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
              minLines: 3,
              maxLines: 6,
              enabled: !_saving,
              decoration: InputDecoration(
                hintText: tr(
                  context,
                  _observationOnly
                      ? 'Write your explanation here...'
                      : 'Example: CCTV checked at 3 PM. Water covers the crossing.',
                ),
                helperText: tr(context, 'Minimum 10 characters'),
                helperStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.4,
                  color: p.onSurfaceVariant,
                ),
                helperMaxLines: 2,
                alignLabelWithHint: true,
                filled: true,
                fillColor: p.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {
                _verified = false;
                _meaningfulFollowup = false;
              }),
            ),
            if (_quickCheck)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 14),
                child: ReportPanel(
                  padding: const EdgeInsets.all(12),
                  tint: p.primary.withValues(alpha: .05),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: p.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(
                            context,
                            (widget.roadIds?.length ?? 1) > 1
                                ? 'Saving confirms you checked every selected road. Findings are visible to residents.'
                                : 'Saving confirms your current road check. Findings are visible to residents.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _explanation(
                _observationOnly
                    ? 'This explanation is sent privately to the reporter.'
                    : 'This note will appear with the road update.',
              ),
              _section(
                roadOnly
                    ? '3. Confirm the check'
                    : _observationOnly
                    ? '3. Confirm the evidence'
                    : '4. Confirm the check',
              ),
              ReportPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: CheckboxListTile(
                  key: const ValueKey('admin-review-confirmation'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _verified,
                  onChanged: _saving || _loading || _context == null
                      ? null
                      : (value) => setState(() => _verified = value == true),
                  title: Text(
                    tr(
                      context,
                      _observationOnly
                          ? 'I checked the evidence supporting this observation.'
                          : 'I checked the current road condition.',
                    ),
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ),
            ],
            if (roadOnly && widget.showRoadSettings)
              ReportPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: ExpansionTile(
                  key: ValueKey('road-settings-$_conditionEpoch'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    tr(context, 'More road settings'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    tr(context, 'Optional road information'),
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
                  childrenPadding: const EdgeInsets.only(top: 10, bottom: 10),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('road-vulnerability-$_conditionEpoch'),
                      initialValue: _vulnerability,
                      isExpanded: true,
                      itemHeight: null,
                      hint: Text(tr(context, 'Keep current setting')),
                      decoration: InputDecoration(
                        labelText: tr(context, 'Flood vulnerability'),
                      ),
                      items: [
                        for (final pair in [
                          ('low', 'Low'),
                          ('medium', 'Medium'),
                          ('high', 'High'),
                        ])
                          DropdownMenuItem(
                            value: pair.$1,
                            child: Text(tr(context, pair.$2)),
                          ),
                      ],
                      onChanged: _saving || _loading || _context == null
                          ? null
                          : (v) => setState(() {
                              _vulnerability = v;
                              _verified = false;
                            }),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        tr(
                          context,
                          'How easily this road tends to flood, rather than today’s water level.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: p.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (report?['reportType'] == 'followup') ...[
              Text(
                tr(
                  context,
                  'Verification alone does not award another original-report reward. Only one meaningful follow-up bonus is available per resident and incident.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _meaningfulFollowup,
                onChanged:
                    _saving ||
                        _loading ||
                        _context == null ||
                        report?['conditionChange'] == 'unchanged'
                    ? null
                    : (value) =>
                          setState(() => _meaningfulFollowup = value == true),
                title: Text(
                  tr(
                    context,
                    'I verified a meaningful change beyond the earlier submissions. Eligible for up to +5 trust points.',
                  ),
                ),
              ),
            ],
            if (_error != null)
              Text(
                tr(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_error != null)
              TextButton(
                onPressed: _saving ? null : _load,
                child: Text(tr(context, 'Refresh latest details')),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('admin-review-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed:
                !_loading &&
                    !_saving &&
                    _context != null &&
                    _context?['selfReview'] != true &&
                    !originalNeedsReview &&
                    (_observationOnly || _status != null) &&
                    (_quickCheck || _verified) &&
                    _note.text.trim().length >= 10
                ? _save
                : null,
            child: Text(
              tr(context, _saving ? 'Confirming save...' : saveLabel),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
