import 'admin_review_dialog.dart';
import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/road_incident.dart';
import '../services/road_incident_service.dart';
import '../services/user_service.dart';

/// One incident per road, shared by every report of that incident.
class RoadIncidentPanel extends StatefulWidget {
  final String roadId;
  final bool isAdmin;
  final bool showAdminReview;
  final bool embedded;
  final Widget? reporterAction;
  final Stream<RoadIncidentSnapshot>? stream;
  final Future<void> Function(RoadIncident, String)? onObserve;
  const RoadIncidentPanel({
    super.key,
    required this.roadId,
    this.isAdmin = false,
    this.showAdminReview = true,
    this.embedded = false,
    this.reporterAction,
    this.stream,
    this.onObserve,
  });
  @override
  State<RoadIncidentPanel> createState() => _RoadIncidentPanelState();
}

class _RoadIncidentPanelState extends State<RoadIncidentPanel> {
  late Stream<RoadIncidentSnapshot> _stream;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  String? _success;
  String? _savedChoice, _savedIncidentId, _successIncidentId;
  int _responseContext = 0;
  @override
  void initState() {
    super.initState();
    _stream = widget.stream ?? RoadIncidentService.watch(widget.roadId);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant RoadIncidentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roadId != widget.roadId ||
        oldWidget.stream != widget.stream) {
      _stream = widget.stream ?? RoadIncidentService.watch(widget.roadId);
      _error = null;
      _success = null;
      _savedChoice = _savedIncidentId = null;
      _busy = false;
      _responseContext++;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action,
    String success, {
    String? choice,
    String? incidentId,
  }) async {
    if (_busy) return;
    final responseContext = _responseContext;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await action();
      if (mounted && responseContext == _responseContext) {
        setState(() {
          _success = success;
          _successIncidentId = incidentId;
          _savedChoice = choice;
          _savedIncidentId = incidentId;
        });
      }
    } catch (error) {
      final message = error.toString().replaceFirst('Bad state: ', '');
      if (mounted && responseContext == _responseContext) {
        setState(
          () => _error =
              message.contains('TimeoutException') ||
                  message.contains('ClientException')
              ? 'We could not confirm this was saved. Check your connection and retry.'
              : message,
        );
      }
    } finally {
      if (mounted && responseContext == _responseContext) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review(RoadIncident incident) async {
    final result = await showAdminReview(context, roadIds: [incident.roadId]);
    if (result != null && mounted) {
      setState(() {
        _success = result.confirmation;
        _successIncidentId = incident.incidentId;
      });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<RoadIncidentSnapshot>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            tr(
              context,
              'Community observations are unavailable. Road condition could not be confirmed. Reopen this screen to retry.',
            ),
            style: GoogleFonts.inter(),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            tr(context, 'Checking community observations…'),
            style: GoogleFonts.inter(),
          ),
        );
      }
      final incident = snapshot.data!.incident;
      if (incident == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tr(
              context,
              'No community incident is recorded. This does not confirm the road is safe.',
            ),
            style: GoogleFonts.inter(),
          ),
        );
      }
      final now = DateTime.now(), cached = snapshot.data!.fromCache;
      final enabled = !_busy && !cached && incident.state != 'resolved';
      final palette = AppPalette.of(context);
      final responseCount = incident.counts.values.fold<int>(
        0,
        (a, b) => a + b,
      );

      final isResolved = incident.state == 'resolved';
      final statusColor = isResolved
          ? palette.secondary
          : (incident.reviewedAt != null
                ? (palette.isDark
                      ? Colors.orangeAccent
                      : const Color(0xFFC2410C))
                : palette.partial);

      return Container(
        width: double.infinity,
        padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(20),
        decoration: widget.embedded
            ? null
            : BoxDecoration(
                color: palette.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: palette.outlineVariant.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showAdminReview) ...[
              // Section Category Label
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: palette.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, 'COMMUNITY & ADMIN UPDATES'),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: palette.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'Road updates'),
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              // Incident Status / Admin Review Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isResolved
                                ? Icons.check_circle_rounded
                                : (incident.reviewedAt != null
                                      ? Icons.verified_user_rounded
                                      : Icons.fact_check_outlined),
                            size: 14,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              incident.reviewedAt == null
                                  ? 'Incident status'
                                  : 'Admin review',
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, incident.label(now)),
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    if (incident.reviewedAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: palette.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${tr(context, 'Reviewed')} ${localizedAge(context, incident.reviewedAt!, now)}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: palette.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (incident.reviewNote?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: palette.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 13,
                                  color: palette.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    tr(context, 'Admin note'),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: palette.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              incident.reviewNote!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: palette.onSurface,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            // Resident Observations Section Header
            Row(
              children: [
                if (!widget.embedded) ...[
                  Icon(
                    Icons.people_alt_outlined,
                    size: 16,
                    color: palette.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    tr(context, 'Quick observations'),
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.onSurface,
                    ),
                  ),
                ),
                if (responseCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$responseCount ${tr(context, responseCount == 1 ? "response" : "responses")}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (responseCount == 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      size: 16,
                      color: palette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          'No quick observations yet. If you can safely see this road, share what you observe.',
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final choice in _choices.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              switch (choice.key) {
                                'still_flooded' => Icons.water_drop_outlined,
                                'appears_passable' => Icons.visibility_outlined,
                                _ => Icons.help_outline_rounded,
                              },
                              size: 16,
                              color: switch (choice.key) {
                                'still_flooded' => palette.notPassable,
                                'appears_passable' => palette.passable,
                                _ => palette.onSurfaceVariant,
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr(context, choice.value),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: palette.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${incident.counts[choice.key] ?? 0}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (cached)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: palette.partial,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          'Saved information — reconnect to send an observation or review.',
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: palette.partial,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Actions Section
            if (incident.state != 'resolved') ...[
              const SizedBox(height: 20),
              if (widget.isAdmin)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: enabled ? () => _review(incident) : null,
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: Text(
                      tr(context, 'Review current conditions'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                )
              else if (widget.reporterAction != null)
                widget.reporterAction!
              else ...[
                Text(
                  tr(context, 'What can you see right now?'),
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: 8),

                // Friendly Safety Tip Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFFEF3C7,
                    ).withValues(alpha: palette.isDark ? 0.15 : 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Color(0xFFD97706),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(
                            context,
                            'Respond only from a safe place. Do not enter floodwater.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: palette.isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Modern Choice Buttons
                for (final choice in _choices.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Semantics(
                        selected:
                            _savedIncidentId == incident.incidentId &&
                            _savedChoice == choice.key,
                        child: OutlinedButton.icon(
                          key: ValueKey('incident-observe-${choice.key}'),
                          onPressed: enabled
                              ? () => _run(
                                  () =>
                                      (widget.onObserve ??
                                      RoadIncidentService.observe)(
                                        incident,
                                        choice.key,
                                      ),
                                  'Salamat! Your observation was saved. Road reopening requires admin verification.',
                                  choice: choice.key,
                                  incidentId: incident.incidentId,
                                )
                              : null,
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            backgroundColor:
                                _savedIncidentId == incident.incidentId &&
                                    _savedChoice == choice.key
                                ? palette.primary.withValues(alpha: .08)
                                : widget.embedded
                                ? palette.surfaceContainerLow
                                : palette.surfaceContainerLowest,
                            foregroundColor: palette.onSurface,
                            side: BorderSide(
                              color:
                                  _savedIncidentId == incident.incidentId &&
                                      _savedChoice == choice.key
                                  ? palette.primary
                                  : widget.embedded
                                  ? Colors.transparent
                                  : palette.outlineVariant.withValues(
                                      alpha: .45,
                                    ),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: switch (choice.key) {
                                'still_flooded' => const Color(
                                  0xFFDC2626,
                                ).withValues(alpha: 0.1),
                                'appears_passable' => const Color(
                                  0xFF16A34A,
                                ).withValues(alpha: 0.1),
                                _ => palette.primary.withValues(alpha: 0.1),
                              },
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              switch (choice.key) {
                                'still_flooded' => Icons.water_drop_rounded,
                                'appears_passable' => Icons.visibility_outlined,
                                _ => Icons.help_outline_rounded,
                              },
                              size: 16,
                              color: switch (choice.key) {
                                'still_flooded' => palette.notPassable,
                                'appears_passable' => palette.passable,
                                _ => palette.primary,
                              },
                            ),
                          ),
                          label: Text(
                            tr(context, choice.value),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],

            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(),
                ),
              ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: palette.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: palette.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_success != null && _successIncidentId == incident.incidentId)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: palette.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(context, _success!),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(context, 'Road reopening requires admin verification.'),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // More Details ExpansionTile
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                  iconColor: palette.primary,
                  collapsedIconColor: palette.onSurfaceVariant,
                  title: Text(
                    tr(context, 'More details'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (incident.lastObservedAt != null) ...[
                            _infoBullet(
                              context,
                              Icons.history_rounded,
                              '${tr(context, 'Latest observation')}: ${localizedAge(context, incident.lastObservedAt!, now)}',
                            ),
                            const SizedBox(height: 8),
                          ],
                          _infoBullet(
                            context,
                            Icons.verified_outlined,
                            incident.lastConfirmedAt == null
                                ? tr(
                                    context,
                                    'No independent resident flood confirmation yet.',
                                  )
                                : '${tr(context, 'Last resident flood confirmation')}: ${localizedAge(context, incident.lastConfirmedAt!, now)}',
                          ),
                          const SizedBox(height: 8),
                          _infoBullet(
                            context,
                            Icons.shield_outlined,
                            tr(
                              context,
                              'Responses may be old. They do not establish that a road is safe.',
                            ),
                          ),
                          if (!widget.isAdmin) ...[
                            const SizedBox(height: 8),
                            _infoBullet(
                              context,
                              Icons.update_rounded,
                              tr(
                                context,
                                'Your new response replaces your previous response for this incident.',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  static const _choices = {
    'still_flooded': 'Still flooded',
    'appears_passable': 'Looks passable',
    'cannot_confirm': 'I cannot confirm',
  };

  Widget _infoBullet(BuildContext context, IconData icon, String text) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: palette.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: palette.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Resolves the role once; the backend always checks it independently.
class RoadIncidentRolePanel extends StatefulWidget {
  final String roadId;
  final bool showAdminReview;
  final bool embedded;
  final Widget? reporterAction;
  const RoadIncidentRolePanel({
    super.key,
    required this.roadId,
    this.showAdminReview = true,
    this.embedded = false,
    this.reporterAction,
  });
  @override
  State<RoadIncidentRolePanel> createState() => _RoadIncidentRolePanelState();
}

class _RoadIncidentRolePanelState extends State<RoadIncidentRolePanel> {
  late final Future<UserRole?> _role = UserService.getUserRole();
  @override
  Widget build(BuildContext context) => FutureBuilder<UserRole?>(
    future: _role,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasData) {
        return Text(
          tr(
            context,
            'Account access could not be checked. Reopen this screen to retry.',
          ),
        );
      }
      if (!snapshot.hasData) {
        return Text(tr(context, 'Checking account access…'));
      }
      return RoadIncidentPanel(
        roadId: widget.roadId,
        isAdmin: snapshot.data == UserRole.admin,
        showAdminReview: widget.showAdminReview,
        embedded: widget.embedded,
        reporterAction: widget.reporterAction,
      );
    },
  );
}
