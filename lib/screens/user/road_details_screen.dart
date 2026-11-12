import '../../widgets/report_followup_prompt.dart';
import '../../widgets/noah_awareness_card.dart';
import '../shared/full_screen_map_screen.dart';
import '../../config/app_environment.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'report_followup_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../../services/user_service.dart';
import '../../widgets/report_details_bottom_sheet.dart';
import '../../widgets/road_reports_section.dart';
import '../../widgets/road_condition_overview.dart';
import '../../widgets/feed_status_notice.dart';
import '../../services/sync_health.dart';
import '../../widgets/road_incident_panel.dart';
import 'report_submission_screen.dart';
import '../../widgets/admin_review_dialog.dart';
import '../../services/admin_report_service.dart';

class RoadDetailsScreen extends StatefulWidget {
  final String roadId;

  const RoadDetailsScreen({super.key, required this.roadId});

  static Route route(String roadId) {
    return PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) =>
          RoadDetailsScreen(roadId: roadId),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(opacity: fadeAnimation, child: child);
      },
    );
  }

  @override
  State<RoadDetailsScreen> createState() => _RoadDetailsScreenState();
}

class _RoadDetailsScreenState extends State<RoadDetailsScreen> {
  late final Future<UserRole?> _role;
  bool _openingRoadReview = false;

  @override
  void initState() {
    super.initState();
    _role = UserService.getUserRole();
  }

  Future<void> _updateRoad(RoadStatus road) async {
    if (_openingRoadReview) return;
    setState(() => _openingRoadReview = true);
    try {
      final result = await showDialog<AdminActionResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AdminReviewDialog(
          roadIds: [road.id],
          previewRoad: road,
          showRoadSettings: true,
          quickConditions: true,
        ),
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.confirmation)));
      }
    } finally {
      if (mounted) setState(() => _openingRoadReview = false);
    }
  }

  double _sheetSize = .6;
  double _availableHeight = 1;
  bool _dragging = false;

  void _animateSheet(double size) => setState(() {
    _dragging = false;
    _sheetSize = size;
  });

  Widget _insetSheet(Widget child) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: child,
      ),
    ),
  );

  Widget _sheetHandle() => Container(
    padding: const EdgeInsets.only(left: 8, top: 8, right: 8),
    color: AppPalette.of(context).surface,
    child: Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('road-details-handle'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                _dragging = true;
                _sheetSize = (_sheetSize - details.delta.dy / _availableHeight)
                    .clamp(.4, .95);
              });
            },
            onVerticalDragEnd: (_) => _animateSheet(
              [.4, .6, .95].reduce(
                (a, b) =>
                    (a - _sheetSize).abs() < (b - _sheetSize).abs() ? a : b,
              ),
            ),
            onVerticalDragCancel: () => _animateSheet(_sheetSize),
            child: Center(
              child: IconButton(
                tooltip: tr(context, 'Expand or collapse road details'),
                onPressed: () {
                  _animateSheet(_sheetSize > .8 ? .6 : .95);
                },
                icon: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).outlineVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('close-road-details'),
          tooltip: tr(context, 'Close road details'),
          onPressed: () => Navigator.of(context).maybePop(),
          color: AppPalette.of(context).onSurfaceVariant,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppPalette.of(context).onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: AppPalette.of(context).onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final roadIndex = appState.roads.indexWhere(
          (r) => r.id == widget.roadId,
        );

        if (roadIndex == -1) {
          return Scaffold(
            appBar: AppTopBar(
              title: tr(context, 'Road Details'),
              showBackButton: true,
            ),
            backgroundColor: AppPalette.of(context).surface,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.not_interested,
                    size: 64,
                    color: AppPalette.of(context).outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr(context, 'Road Not Found'),
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, 'The requested road details are unavailable.'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppPalette.of(context).onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final road = appState.roads[roadIndex];
        final palette = AppPalette.of(context);
        final uid =
            AppEnvironment.sparkFollowupsEnabled && Firebase.apps.isNotEmpty
            ? FirebaseAuth.instance.currentUser?.uid
            : null;
        final ownIncidentReport = uid == null
            ? null
            : appState.reports
                  .where(
                    (report) =>
                        report.userId == uid &&
                        report.roadId == road.id &&
                        report.incidentId == road.activeIncidentId,
                  )
                  .firstOrNull;
        final weatherName =
            switch (SimulatedWeatherService.instance.currentState) {
              WeatherState.clear => 'Clear',
              WeatherState.partlyCloudy => 'Partly cloudy',
              WeatherState.lightRain => 'Light rain',
              WeatherState.moderateRain => 'Moderate rain',
              WeatherState.heavyRain => 'Heavy Rain',
              WeatherState.typhoon =>
                AppEnvironment.sparkCoreEnabled
                    ? 'Severe weather estimate'
                    : 'Typhoon',
            };

        // Filter active broadcast alerts matching this road (strictly match by roadId, or roadName fallback only if roadId is unassigned)
        final roadAlerts = appState.alerts.where((a) {
          if (a.roadId != null && a.roadId!.isNotEmpty) {
            return a.roadId == road.id;
          }
          if (a.roadName != null && a.roadName!.isNotEmpty) {
            return a.roadName!.toLowerCase().trim() ==
                road.name.toLowerCase().trim();
          }
          return false;
        }).toList();

        String statusText = 'PASSABLE';
        Color statusBgColor = AppPalette.of(context).secondaryContainer;
        Color statusColor = AppPalette.of(context).secondary;
        IconData statusIcon = Icons.check_circle;

        final effectiveStatus = road.getEffectiveStatus(
          SimulatedWeatherService.instance.currentState,
        );
        final isUnconfirmed = road.needsStatusConfirmation(
          SimulatedWeatherService.instance.currentState,
        );

        if (effectiveStatus == 'partial') {
          statusText = 'PARTIALLY FLOODED';
          statusBgColor = AppPalette.of(context).surfaceContainerHigh;
          statusColor = AppPalette.of(context).partial;
          statusIcon = Icons.info;
        } else if (effectiveStatus == 'not_passable') {
          statusText = 'NOT PASSABLE';
          statusBgColor = AppPalette.of(context).errorContainer;
          statusColor = AppPalette.of(context).notPassable;
          statusIcon = Icons.warning;
        }
        if (isUnconfirmed) {
          statusText = 'Needs confirmation';
          statusBgColor = AppPalette.of(context).warningContainer;
          statusColor = AppPalette.of(context).onWarningContainer;
          statusIcon = Icons.help_outline;
        }
        if (road.status == 'passable' && road.hasUnresolvedCommunityIncident) {
          statusText = road.communityCondition == 'outdated'
              ? 'CURRENT CONDITION UNKNOWN'
              : 'UNDER VERIFICATION';
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            key: const ValueKey('road-details-viewport'),
            builder: (context, constraints) {
              _availableHeight = constraints.maxHeight;
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.bottomCenter,
                children: [
                  // Tap background to dismiss
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // Only the handle changes height; reading content keeps the map visible.
                  AnimatedFractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor: _sheetSize,
                    widthFactor: 1,
                    duration:
                        _dragging || MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: _insetSheet(
                      Container(
                        key: const ValueKey('road-details-sheet'),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surface,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 20,
                              offset: Offset(0, -4),
                            ),
                          ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SingleChildScrollView(
                              key: const ValueKey('road-details-content'),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                64,
                                20,
                                32,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FeedStatusNotice(
                                    condition:
                                        appState.syncHealth.channels['roads'] ??
                                        SyncCondition.connecting,
                                    isEmpty: false,
                                    emptyMessage: '',
                                    onRetry: appState.retrySync,
                                  ),
                                  RoadConditionOverview(
                                    road: road,
                                    statusText: statusText,
                                    statusBackground: statusBgColor,
                                    statusColor: statusColor,
                                    statusIcon: statusIcon,
                                    unconfirmed: isUnconfirmed,
                                  ),
                                  for (final alert in roadAlerts) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: palette.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: alert.severity == 'Critical'
                                              ? palette.notPassable
                                              : palette.outlineVariant,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tr(context, 'Broadcast advisory'),
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: palette.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            alert.title,
                                            style: GoogleFonts.manrope(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: palette.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            alert.message,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              height: 1.4,
                                              color: palette.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  NoahAwarenessCard(
                                    geometry: road.geometry,
                                    onViewMap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => FullScreenMapScreen(
                                          initialRoadId: road.id,
                                          showNoahInitially: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  RoadCommunityCard(
                                    observations: RoadIncidentRolePanel(
                                      roadId: road.id,
                                      showAdminReview: false,
                                      embedded: true,
                                      reporterAction: ownIncidentReport == null
                                          ? null
                                          : ReportFollowupPrompt(
                                              onOpen: () =>
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ReportFollowupScreen(
                                                            rootReportId:
                                                                ownIncidentReport
                                                                    .historyRootId,
                                                          ),
                                                    ),
                                                  ),
                                            ),
                                    ),
                                    reports: RoadReportsSection(
                                      embedded: true,
                                      roadId: road.id,
                                      reports: appState.reports,
                                      users: appState.users,
                                      syncCondition:
                                          appState
                                              .syncHealth
                                              .channels['reports'] ??
                                          SyncCondition.connecting,
                                      onRetry: () {
                                        appState.retrySync();
                                      },
                                      onOpen: (report) =>
                                          showModalBottomSheet<void>(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (_) =>
                                                ReportDetailsBottomSheet(
                                                  report: report,
                                                ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  // Actions
                                  FutureBuilder<UserRole?>(
                                    future: _role,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const SizedBox.shrink();
                                      }

                                      final admin =
                                          snapshot.data == UserRole.admin;
                                      return FilledButton.icon(
                                        key: const ValueKey(
                                          'road-report-action',
                                        ),
                                        onPressed: admin
                                            ? (_openingRoadReview
                                                  ? null
                                                  : () => _updateRoad(road))
                                            : () => Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ReportSubmissionScreen(
                                                        prefilledRoadId:
                                                            road.id,
                                                      ),
                                                ),
                                              ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: palette.primary,
                                          foregroundColor: palette.onPrimary,
                                          minimumSize: const Size(
                                            double.infinity,
                                            52,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        icon: Icon(
                                          admin
                                              ? Icons
                                                    .admin_panel_settings_outlined
                                              : Icons.campaign_outlined,
                                          size: 20,
                                        ),
                                        label: Text(
                                          tr(
                                            context,
                                            admin
                                                ? 'Admin: Update Status'
                                                : 'Report Update',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  Material(
                                    color: palette.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(20),
                                    child: ExpansionTile(
                                      key: const ValueKey(
                                        'road-prediction-details',
                                      ),
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 4,
                                      ),
                                      childrenPadding: const EdgeInsets.all(20),
                                      expandedCrossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      title: Text(
                                        tr(context, 'Prediction details'),
                                        style: GoogleFonts.manrope(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: palette.onSurface,
                                        ),
                                      ),
                                      children: [
                                        _buildDetailRow(
                                          tr(context, 'Map reference'),
                                          road.name,
                                        ),
                                        Text(
                                          tr(
                                            context,
                                            'Model estimates support road assessment. Scores are not measured accuracy or a guarantee of safe travel.',
                                          ),
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            height: 1.4,
                                            color: palette.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (!appState.syncHealth.riskFresh)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: Text(
                                              tr(
                                                context,
                                                'A current model update is unavailable. Any displayed estimate may be outdated.',
                                              ),
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: palette.partial,
                                              ),
                                            ),
                                          ),
                                        if (road.vulnerability != 'low') ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.partial.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: palette.partial
                                                    .withValues(alpha: 0.2),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.analytics_outlined,
                                                  size: 18,
                                                  color: palette.partial,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Predictive Risk Model: ${road.vulnerability.toUpperCase()} VULNERABILITY',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: palette.partial,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 24),

                                        // PREDICTIVE INTELLIGENCE
                                        if (appState.syncHealth.riskFresh ||
                                            road.riskScore > 0) ...[
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: AppPalette.of(
                                                context,
                                              ).surfaceContainerLowest,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: palette.partial
                                                    .withValues(alpha: 0.3),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: palette.partial
                                                      .withValues(alpha: 0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.hub_outlined,
                                                      size: 16,
                                                      color: palette.partial,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        tr(
                                                          context,
                                                          'PREDICTIVE INTELLIGENCE',
                                                        ),
                                                        style:
                                                            GoogleFonts.inter(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  1.5,
                                                              color: palette
                                                                  .partial,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                _buildDetailRow(
                                                  tr(context, 'Risk Category'),
                                                  tr(
                                                    context,
                                                    road.riskCategory,
                                                  ),
                                                  isBold: true,
                                                ),
                                                _buildDetailRow(
                                                  tr(context, 'Risk Score'),
                                                  '${road.riskScore.toStringAsFixed(1)}/100',
                                                ),
                                                _buildDetailRow(
                                                  tr(context, 'Primary Source'),
                                                  road.propagationSource != null
                                                      ? (appState.roads
                                                                .cast<
                                                                  RoadStatus?
                                                                >()
                                                                .firstWhere(
                                                                  (r) =>
                                                                      r?.id ==
                                                                      road.propagationSource,
                                                                  orElse: () =>
                                                                      null,
                                                                )
                                                                ?.name ??
                                                            road.propagationSource!)
                                                      : 'None (Local Source)',
                                                ),
                                                _buildDetailRow(
                                                  tr(
                                                    context,
                                                    'Weather Condition',
                                                  ),
                                                  tr(context, weatherName),
                                                ),
                                                _buildDetailRow(
                                                  tr(
                                                    context,
                                                    'Warning Duration',
                                                  ),
                                                  road.warningStartTime != null
                                                      ? '${DateTime.now().difference(road.warningStartTime!).inMinutes} minutes'
                                                      : '0 minutes',
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: _sheetHandle(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
