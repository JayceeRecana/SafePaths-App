import '../../widgets/alert_template_library.dart';
import 'dart:async';
import '../../l10n/formatters.dart';
import '../../widgets/communication_admin_dialog.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../config/app_environment.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';

class BroadcastDraft {
  final String title, message, severity;
  final String? roadId, roadName;
  final bool sendPush;
  final int minutes;
  const BroadcastDraft({
    required this.title,
    required this.message,
    required this.severity,
    required this.sendPush,
    required this.minutes,
    this.roadId,
    this.roadName,
  });
}

class BroadcastAlertScreen extends StatefulWidget {
  final bool isStandalone, initiallyActive;
  final DateTime Function()? now;
  final Future<BroadcastResult> Function(BroadcastDraft)? publishAlert;
  const BroadcastAlertScreen({
    super.key,
    this.isStandalone = false,
    this.initiallyActive = false,
    this.now,
    this.publishAlert,
  });

  @override
  State<BroadcastAlertScreen> createState() => _BroadcastAlertScreenState();
}

class _BroadcastAlertScreenState extends State<BroadcastAlertScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _clock;
  int _severity = 1;
  bool _sendPush = false, _sending = false, _reviewing = false;
  bool _showActive = false, _showPast = false;
  int _validityMinutes = 180;
  String? _selectedRoadId, _selectedRoadName;
  String? _publishError;
  DateTime get _now => (widget.now ?? DateTime.now)();
  int get _minutes =>
      AppEnvironment.sparkCommunicationsEnabled ? _validityMinutes : 1440;
  String get _severityName => ['Advisory', 'Warning', 'Critical'][_severity];
  String get _area => AppEnvironment.area.name;

  @override
  void initState() {
    super.initState();
    _showActive = widget.initiallyActive;
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _scrollController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  DateTime _expiry(BroadcastAlert alert) =>
      alert.expiresAt ?? alert.createdAt.add(const Duration(hours: 24));
  bool _active(BroadcastAlert alert) =>
      !alert.withdrawn && _now.isBefore(_expiry(alert));
  Color _severityColor(String value) {
    final p = AppPalette.of(context);
    return value == 'Critical'
        ? p.error
        : value == 'Warning'
        ? p.warning
        : p.primary;
  }

  Color _severitySurface(String value) {
    final p = AppPalette.of(context);
    return value == 'Warning'
        ? p.warningContainer
        : value == 'Critical'
        ? p.scheme.errorContainer
        : p.primary.withValues(alpha: .08);
  }

  IconData _severityIcon(String value) => value == 'Critical'
      ? Icons.report_outlined
      : value == 'Warning'
      ? Icons.warning_amber_rounded
      : Icons.info_outline;
  String _duration(int minutes) => minutes < 60
      ? '$minutes ${tr(context, 'minutes')}'
      : '${minutes ~/ 60} ${tr(context, minutes == 60 ? 'hour' : 'hours')}';
  String _location(String? road) =>
      road ?? '${tr(context, 'Area-wide')} · $_area';
  String _ends(DateTime time) =>
      '${tr(context, 'Ends')}: ${localizedDateTime(context, time)}';

  void _changeTab(bool active) {
    if (_sending) return;
    setState(() => _showActive = active);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return PopScope(
      canPop: !_sending,
      child: AbsorbPointer(
        absorbing: _sending,
        child: Scaffold(
          appBar: AppTopBar(
            title: tr(context, 'Broadcast Alert'),
            showBackButton: widget.isStandalone,
            showProfile: true,
            showSettingsAction: true,
          ),
          backgroundColor: p.surface,
          body: AbsorbPointer(
            absorbing: _sending,
            child: ListenableBuilder(
              listenable: AppStateService.instance,
              builder: (context, _) {
                final history =
                    AppStateService.instance.broadcastHistory
                        .where(
                          (a) =>
                              a.studyArea == null ||
                              a.studyArea == AppEnvironment.area.id,
                        )
                        .toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                final active = history.where(_active).toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final tabs = [
                            _tab(
                              'Write alert',
                              !_showActive,
                              () => _changeTab(false),
                            ),
                            _tab(
                              '${tr(context, 'Active')} (${active.length})',
                              _showActive,
                              () => _changeTab(true),
                              translate: false,
                            ),
                          ];
                          return MediaQuery.textScalerOf(context).scale(12) >
                                      20 ||
                                  box.maxWidth < 260
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    tabs[0],
                                    const SizedBox(height: 6),
                                    tabs[1],
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: tabs[0]),
                                    const SizedBox(width: 8),
                                    Expanded(child: tabs[1]),
                                  ],
                                );
                        },
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: _showActive
                            ? _activeAlerts(history, active)
                            : _compose(),
                      ),
                    ),
                    if (!_showActive)
                      Container(
                        decoration: BoxDecoration(
                          color: p.surfaceContainerLowest,
                          border: Border(
                            top: BorderSide(
                              color: p.outlineVariant.withValues(alpha: .3),
                            ),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _sending || _reviewing
                                    ? null
                                    : _broadcastAlert,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.fact_check_outlined),
                                label: Text(
                                  tr(
                                    context,
                                    _sending ? 'Publishing…' : 'Review alert',
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 50),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  backgroundColor: p.primary,
                                  foregroundColor: p.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
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
      ),
    );
  }

  Widget _tab(
    String text,
    bool selected,
    VoidCallback onTap, {
    bool translate = true,
  }) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.primary : p.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text(
              translate ? tr(context, text) : text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? p.onPrimary : p.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Text(
      tr(context, title),
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppPalette.of(context).onSurface,
      ),
    ),
  );

  Widget _card(Widget child) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.outlineVariant.withValues(alpha: .35)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  InputDecoration _input(String label, String hint) => InputDecoration(
    labelText: tr(context, label),
    hintText: tr(context, hint),
    floatingLabelStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppPalette.of(context).onSurface,
    ),
    alignLabelWithHint: true,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    filled: true,
    fillColor: AppPalette.of(context).surfaceContainerLow,
    contentPadding: const EdgeInsets.all(14),
  );

  Widget _compose() {
    final p = AppPalette.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_publishError != null) ...[
            _notice(Icons.error_outline, _publishError!, p.error),
            const SizedBox(height: 12),
          ],
          _heading('How serious is it?'),
          LayoutBuilder(
            builder: (context, box) {
              final choices = [for (var i = 0; i < 3; i++) _severityChoice(i)];
              return MediaQuery.textScalerOf(context).scale(12) > 18 ||
                      box.maxWidth < 280
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final choice in choices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: choice,
                          ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: choices[i]),
                        ],
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          _heading('What do residents need to know?'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _templateArea(),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('broadcast-title'),
                  controller: _titleController,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _input(
                    'Alert title',
                    'Give the alert a short, clear title',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? tr(context, 'Enter a title with at least 2 characters.')
                      : v!.trim().length > 120
                      ? tr(context, 'Keep the title within 120 characters.')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('broadcast-message'),
                  controller: _messageController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _input(
                    'Instructions for residents',
                    'Say what happened and what residents should do.',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v?.trim().length ?? 0) < 10
                      ? tr(
                          context,
                          'Enter instructions with at least 10 characters.',
                        )
                      : v!.trim().length > 2000
                      ? tr(context, 'Keep the message within 2000 characters.')
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _heading('Where and for how long?'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'Alert location'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: p.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Icon(
                      _selectedRoadId == null ? Icons.public : Icons.add_road,
                      color: p.primary,
                    ),
                    title: Text(
                      _selectedRoadName ?? _area,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      tr(
                        context,
                        _selectedRoadId == null
                            ? 'Area-wide · tap to choose a road'
                            : 'Specific road · tap to change',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: p.primary,
                      ),
                    ),
                    trailing: const Icon(Icons.expand_more),
                    onTap: () => _showRoadPickerSheet(context),
                  ),
                ),
                const SizedBox(height: 12),
                _notice(
                  Icons.info_outline,
                  tr(
                    context,
                    'Publishing an alert does not change the road’s verified condition.',
                  ),
                  p.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'Stays active for'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                if (AppEnvironment.sparkCommunicationsEnabled)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final minutes in [15, 60, 180, 1440])
                        ChoiceChip(
                          label: Text(
                            minutes < 60
                                ? '$minutes min'
                                : '${minutes ~/ 60} ${tr(context, 'h')}',
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _validityMinutes == minutes
                                ? p.onPrimary
                                : p.onSurfaceVariant,
                          ),
                          color: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? p.primary
                                : p.surfaceContainerLow,
                          ),
                          side: BorderSide.none,
                          selected: _validityMinutes == minutes,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _validityMinutes = minutes),
                        ),
                    ],
                  )
                else
                  Text(_duration(1440)),
                const SizedBox(height: 8),
                _detailLine(
                  Icons.schedule_outlined,
                  '${tr(context, 'If published now')} · ${_ends(_now.add(Duration(minutes: _minutes)))}',
                ),
                const Divider(height: 28),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sendPush && AppEnvironment.communicationPushAllowed,
                  onChanged: AppEnvironment.communicationPushAllowed
                      ? (v) => setState(() => _sendPush = v)
                      : null,
                  title: Text(
                    tr(context, 'Also notify eligible residents'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    tr(
                      context,
                      AppEnvironment.communicationPushAllowed
                          ? 'Notifications are queued; phone delivery is not guaranteed.'
                          : 'Push notifications are disabled in this build.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _detailLine(
                  Icons.people_outline,
                  '${tr(context, 'Audience')}: $_area',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _heading('What residents will see'),
          _preview(
            _titleController.text.trim(),
            _messageController.text.trim(),
            _severityName,
            _selectedRoadName,
            _minutes,
            _now.add(Duration(minutes: _minutes)),
          ),
        ],
      ),
    );
  }

  Widget _templateArea() {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 18,
                color: p.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(context, 'Templates (optional)'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(context, 'Choose a starting message, then edit it.'),
            style: TextStyle(fontSize: 12, height: 1.45, color: p.onSurface),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AppStateService.instance.templates.take(3))
                _buildTemplateChip(t),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showTemplateManagerSheet(context),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: Text(tr(context, 'Browse templates')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(IconData icon, String text) {
    final p = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: p.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: p.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _severityChoice(int index) {
    final name = ['Advisory', 'Warning', 'Critical'][index];
    final hints = ['Be aware', 'Act soon', 'Act now'];
    final p = AppPalette.of(context), color = _severityColor(name);
    final selected = _severity == index;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _severitySurface(name) : p.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? color : p.outlineVariant.withValues(alpha: .4),
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _severity = index),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _severityIcon(name),
                  color: selected ? color : p.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, name),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : p.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tr(context, hints[index]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: p.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.4, color: color),
          ),
        ),
      ],
    ),
  );

  Widget _preview(
    String title,
    String message,
    String severity,
    String? road,
    int minutes,
    DateTime ends,
  ) {
    final p = AppPalette.of(context), color = _severityColor(severity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _severitySurface(severity),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_severityIcon(severity), size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(context, severity),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title.isEmpty ? tr(context, 'Your title appears here') : title,
            style: TextStyle(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.isEmpty
                ? tr(context, 'Your instructions appear here.')
                : message,
            style: TextStyle(fontSize: 13, height: 1.45, color: p.onSurface),
          ),
          const SizedBox(height: 12),
          Text(
            _location(road),
            style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '${tr(context, 'Active for')} ${_duration(minutes)} · ${_ends(ends)}',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: p.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeAlerts(
    List<BroadcastAlert> history,
    List<BroadcastAlert> active,
  ) {
    final p = AppPalette.of(context);
    final visible = _showPast ? history : active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Published alerts'),
        Text(
          '$_area · ${tr(context, 'Publishing does not verify road conditions.')}',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: p.onSurfaceVariant,
          ),
        ),
        if (history.length > active.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showPast = !_showPast),
              child: Text(
                tr(
                  context,
                  _showPast ? 'Hide past alerts' : 'Show past alerts',
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _card(
            Text(
              tr(context, 'No active alerts in this area.'),
              style: TextStyle(color: p.onSurfaceVariant),
            ),
          ),
        for (final alert in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      Text(
                        tr(context, alert.severity),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _severityColor(alert.severity),
                        ),
                      ),
                      Text(
                        tr(
                          context,
                          alert.withdrawn
                              ? 'Withdrawn'
                              : _active(alert)
                              ? 'Active'
                              : 'Expired',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alert.title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alert.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _location(alert.roadName),
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tr(context, _active(alert)
                        ? 'Ends'
                        : alert.withdrawn
                        ? 'Original expiry'
                        : 'Expired')}: ${localizedDateTime(context, _expiry(alert))}',
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showPublishedAlert(alert),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(tr(context, 'View alert')),
                      ),
                      if (_active(alert))
                        TextButton(
                          onPressed: () => _showRetractDialog(context, alert),
                          child: Text(
                            tr(context, 'Withdraw alert'),
                            style: TextStyle(color: p.error),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showPublishedAlert(BroadcastAlert alert) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: AppPalette.of(context).surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        title: Text(
          tr(context, 'Published alert'),
          style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _preview(
                  alert.title,
                  alert.message,
                  alert.severity,
                  alert.roadName,
                  _expiry(alert).difference(alert.createdAt).inMinutes,
                  _expiry(alert),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    alert.withdrawn
                        ? 'This alert was withdrawn.'
                        : _active(alert)
                        ? 'This alert is active.'
                        : 'This alert has expired.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(context, 'Close')),
          ),
          if (_active(alert))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showRetractDialog(context, alert);
              },
              child: Text(
                tr(context, 'Withdraw alert'),
                style: TextStyle(color: AppPalette.of(context).error),
              ),
            ),
        ],
      ),
    );
  }

  void _showRetractDialog(BuildContext context, BroadcastAlert alert) {
    if (AppEnvironment.sparkCommunicationsEnabled) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            CommunicationAdminDialog(kind: 'broadcast', id: alert.id),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr(context, 'Retract Broadcast Alert?'),
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Withdraw "${alert.title}" from the active alert feed? Notifications already sent cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              tr(context, 'Cancel'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.of(context).error,
              foregroundColor: AppPalette.of(context).onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await AppStateService.instance.deleteBroadcastAlert(alert.id);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        tr(
                          this.context,
                          'Broadcast alert retracted successfully.',
                        ),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to retract alert: $e')),
                  );
                }
              }
            },
            child: Text(
              tr(context, 'Retract Alert'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _broadcastAlert() async {
    if (_sending || _reviewing) return;
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    // Review an immutable snapshot. Nothing is sent until Publish alert is chosen.
    final draft = BroadcastDraft(
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      severity: _severityName,
      roadId: _selectedRoadId,
      roadName: _selectedRoadName,
      sendPush: _sendPush && AppEnvironment.communicationPushAllowed,
      minutes: _minutes,
    );
    setState(() {
      _reviewing = true;
      _publishError = null;
    });
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: AppPalette.of(context).surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          title: Text(
            tr(context, 'Review alert'),
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _preview(
                    draft.title,
                    draft.message,
                    draft.severity,
                    draft.roadName,
                    draft.minutes,
                    _now.add(Duration(minutes: draft.minutes)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${tr(context, 'Audience')}: $_area',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      context,
                      draft.sendPush
                          ? 'Notifications will be queued for eligible residents.'
                          : 'In-app alert only. No push notification requested.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      context,
                      'Publishing an alert does not change the road’s verified condition.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, 'Expiry starts when the alert is published.'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(context, 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(context, 'Publish alert')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
    if (!mounted || confirmed != true) return;
    setState(() => _sending = true);
    BroadcastResult? result;
    try {
      result =
          await (widget.publishAlert?.call(draft) ??
              AppStateService.instance.broadcastAlert(
                draft.title,
                draft.message,
                draft.severity,
                roadId: draft.roadId,
                roadName: draft.roadName,
                sendPush: draft.sendPush,
                minutes: draft.minutes,
              ));
    } catch (_) {
      // The repository retains the retry identity; the visible draft stays intact.
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (result?.alertSaved != true) {
      setState(
        () => _publishError = tr(
          context,
          'Could not confirm publication. Your draft is still here. Check your connection and retry.',
        ),
      );
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    String message;
    if (result!.queuedCount > 0) {
      message =
          'Alert published. Notifications queued; phone delivery is not confirmed.';
    } else if (result.pushError != null) {
      message = 'Alert published, but notifications could not be sent.';
    } else if (draft.sendPush && result.pushSent) {
      message =
          'Alert published. Notification request accepted; phone delivery is not confirmed.';
    } else if (draft.sendPush) {
      message = 'Alert published. No notifications were queued.';
    } else {
      message = 'Alert published in the area feed.';
    }
    setState(() {
      _showActive = true;
      _showPast = false;
      _publishError = null;
      _titleController.clear();
      _messageController.clear();
      _selectedRoadId = null;
      _selectedRoadName = null;
      _sendPush = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr(context, message))));
  }

  Widget _buildTemplateChip(AlertTemplate t) {
    Color dotColor = AppPalette.of(context).primary;
    if (t.severity == 1) dotColor = AppPalette.of(context).partial;
    if (t.severity == 2) dotColor = AppPalette.of(context).tertiary;

    final isSelected =
        _titleController.text == t.title &&
        _messageController.text == t.message;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _titleController.text = t.title;
            _messageController.text = t.message;
            _severity = t.severity.clamp(0, 2).toInt();
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? dotColor.withValues(alpha: 0.14)
                : AppPalette.of(
                    context,
                  ).surfaceContainerHigh.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? dotColor
                  : AppPalette.of(
                      context,
                    ).outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  t.label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? dotColor
                        : AppPalette.of(context).onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTemplateManagerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return AlertTemplateLibrary(
          onUseTemplate: (template) {
            setState(() {
              _titleController.text = template.title;
              _messageController.text = template.message;
              _severity = template.severity.clamp(0, 2).toInt();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    'Template added to your draft. Review it before publishing.',
                  ),
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: AppPalette.of(context).primary,
              ),
            );
          },
        );
      },
    );
  }

  void _showRoadPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _RoadPickerSheet(
          selectedRoadId: _selectedRoadId,
          onRoadSelected: (road) {
            setState(() {
              if (road == null) {
                _selectedRoadId = null;
                _selectedRoadName = null;
              } else {
                _selectedRoadId = road.id;
                _selectedRoadName = road.name;
                // Conveniently suggest title if empty
                if (_titleController.text.trim().isEmpty) {
                  _titleController.text =
                      '${tr(context, 'Road advisory')}: ${road.name}';
                }
              }
            });
          },
        );
      },
    );
  }
}

class _RoadPickerSheet extends StatefulWidget {
  final String? selectedRoadId;
  final ValueChanged<RoadStatus?> onRoadSelected;

  const _RoadPickerSheet({
    required this.selectedRoadId,
    required this.onRoadSelected,
  });

  @override
  State<_RoadPickerSheet> createState() => _RoadPickerSheetState();
}

class _RoadPickerSheetState extends State<_RoadPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'partial':
        return AppPalette.of(context).partial;
      case 'not_passable':
        return AppPalette.of(context).notPassable;
      default:
        return AppPalette.of(context).secondary;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'not_passable':
        return 'Impassable';
      case 'partial':
        return 'Partial';
      default:
        return 'Passable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final allRoads = AppStateService.instance.roads;
    List<RoadStatus> filteredRoads = allRoads.where((r) {
      if (_searchQuery.isNotEmpty &&
          !r.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_filterStatus == 'passable') return r.status == 'passable';
      if (_filterStatus == 'partial') return r.status == 'partial';
      if (_filterStatus == 'not_passable') return r.status == 'not_passable';
      if (_filterStatus == 'vulnerable') return r.vulnerability == 'high';
      return true;
    }).toList();

    filteredRoads.sort((a, b) => a.name.compareTo(b.name));

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.of(
                    context,
                  ).outlineVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr(context, 'Choose alert location'),
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.of(context).onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: tr(context, 'Search roads in this area...'),
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppPalette.of(context).surfaceContainerLow,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      'All',
                      'all',
                      Icons.list,
                      AppPalette.of(context).primary,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Impassable',
                      'not_passable',
                      Icons.warning,
                      AppPalette.of(context).notPassable,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Partial',
                      'partial',
                      Icons.info,
                      AppPalette.of(context).partial,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Passable',
                      'passable',
                      Icons.check_circle,
                      AppPalette.of(context).secondary,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Vulnerable',
                      'vulnerable',
                      Icons.local_fire_department_outlined,
                      Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
            // Area-wide location option; it does not change recipient eligibility.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: InkWell(
                onTap: () {
                  widget.onRoadSelected(null);
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.selectedRoadId == null
                        ? AppPalette.of(context).primary.withValues(alpha: 0.08)
                        : AppPalette.of(context).surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.selectedRoadId == null
                          ? AppPalette.of(context).primary
                          : AppPalette.of(
                              context,
                            ).outlineVariant.withValues(alpha: 0.2),
                      width: widget.selectedRoadId == null ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.selectedRoadId == null
                              ? AppPalette.of(
                                  context,
                                ).primary.withValues(alpha: 0.12)
                              : AppPalette.of(context).surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          size: 20,
                          color: widget.selectedRoadId == null
                              ? AppPalette.of(context).primary
                              : AppPalette.of(context).onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tr(context, 'Area-wide')} ? ${AppEnvironment.area.name}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: widget.selectedRoadId == null
                                    ? AppPalette.of(context).primary
                                    : AppPalette.of(context).onSurface,
                              ),
                            ),
                            Text(
                              tr(
                                context,
                                'No specific road. The notification audience stays the same.',
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppPalette.of(context).onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.selectedRoadId == null)
                        Icon(
                          Icons.check_circle_rounded,
                          color: AppPalette.of(context).primary,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'ROADS (${filteredRoads.length})',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppPalette.of(context).outline,
                    ),
                  ),
                ],
              ),
            ),
            // Roads List
            Expanded(
              child: filteredRoads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 40,
                            color: AppPalette.of(
                              context,
                            ).outline.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(context, 'No roads found matching criteria'),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filteredRoads.length,
                      itemBuilder: (context, index) {
                        final road = filteredRoads[index];
                        final isSelected = widget.selectedRoadId == road.id;
                        final color = _getStatusColor(road.status);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              widget.onRoadSelected(road);
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppPalette.of(
                                        context,
                                      ).primary.withValues(alpha: 0.08)
                                    : AppPalette.of(
                                        context,
                                      ).surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? AppPalette.of(context).primary
                                      : AppPalette.of(
                                          context,
                                        ).outlineVariant.withValues(alpha: 0.2),
                                  width: isSelected ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  if (!isSelected)
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.02,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Status dot
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Road Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          road.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: isSelected
                                                ? AppPalette.of(context).primary
                                                : AppPalette.of(
                                                    context,
                                                  ).onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                _formatStatus(road.status),
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '•  Vuln: ${road.vulnerability.toUpperCase()}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppPalette.of(
                                                  context,
                                                ).onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: AppPalette.of(context).primary,
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, String value, IconData icon, Color color) {
    final active = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : AppPalette.of(context).surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? color : AppPalette.of(context).onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? color : AppPalette.of(context).onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
