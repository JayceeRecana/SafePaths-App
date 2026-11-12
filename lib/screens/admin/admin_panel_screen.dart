import 'dart:async';
import 'dart:math';
import '../../services/admin_insights.dart';
import '../../services/admin_dashboard_signals.dart';
import 'admin_diagnostics_screen.dart';
import '../../services/sync_health.dart';
import '../../l10n/formatters.dart';
import '../../widgets/road_condition_overview.dart' show residentRoadTitle;
import '../../services/admin_road_overview.dart';
import '../../services/report_workload.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import 'broadcast_alert_screen.dart';
import 'update_road_status_screen.dart';
import 'user_reports_screen.dart';
import 'weather_simulator_screen.dart';
import 'consensus_audit_screen.dart';
import 'import_roads_screen.dart';
import 'admin_insights_screen.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/admin_graph_rebuild_dialog.dart';

class AdminPanelScreen extends StatefulWidget {
  final AdminInsightsLoader? loadInsights;
  const AdminPanelScreen({super.key, this.loadInsights});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with WidgetsBindingObserver {
  Timer? _freshnessTimer;
  late Future<AdminInsightsData> _weekData;
  DateTime? _insightsDay;
  void _reloadInsights() {
    final now = DateTime.now();
    _insightsDay = DateTime(now.year, now.month, now.day);
    _weekData = Future.sync(
      () => (widget.loadInsights ?? AdminInsightsService.load)(7),
    );
    _weekData.ignore();
  }

  void _refreshInsights() => setState(_reloadInsights);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloadInsights();
    // Reassess age locally; this does not poll Firestore.
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted)
        setState(() {
          final now = DateTime.now();
          if (_insightsDay != DateTime(now.year, now.month, now.day))
            _reloadInsights();
        });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refreshInsights();
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppStateService.instance,
      SimulatedWeatherService.instance.listenable,
    ]),
    builder: (context, _) => _buildDashboard(context),
  );

  Widget _buildDashboard(BuildContext context) {
    final appState = AppStateService.instance;

    final palette = AppPalette.of(context);
    final isDark = palette.isDark;

    return Scaffold(
      backgroundColor: isDark ? palette.surface : const Color(0xFFF6F8FB),
      appBar: AppTopBar(
        title: tr(context, 'SafePaths Admin'),
        showBackButton: false,
        showProfile: true,
        showSettingsAction: true,
      ),
      body: Builder(
        builder: (context) {
          final weatherService = SimulatedWeatherService.instance;
          final weatherState = weatherService.currentState;
          final weatherText = weatherService.isDataStale
              ? tr(context, 'Weather unavailable')
              : weatherService.isOverrideMode
              ? tr(context, 'Weather drill active')
              : _getWeatherDescription(
                  weatherState,
                  weatherService.temperature,
                );

          final roadOverview = AdminRoadOverview(
            appState.roads,
            DateTime.now(),
            weatherState,
          );
          final staleCount = roadOverview.checks.length;
          final restrictedRecheckCount = roadOverview.roads
              .where(
                (r) =>
                    const ['partial', 'not_passable'].contains(r.road.status) &&
                    r.needsCheck,
              )
              .length;

          final liveAlerts = appState.alerts.where((a) => a.isActive).toList();
          final liveAlertsCount = liveAlerts.length;

          final workload = ReportWorkload(appState.reports);
          final oldest = workload.oldest;
          final oldestSubmissionAge = oldest == null
              ? null
              : localizedAge(context, oldest.createdAt, DateTime.now());
          final pendingReportsCount = ReportWorkload(
            appState.reports,
          ).needsAdmin;
          final staleRoadsDisplay = staleCount;

          // Total things needing attention
          final totalThingsNeedYou =
              (workload.open.isNotEmpty ? 1 : 0) +
              (liveAlerts.isNotEmpty ? 1 : 0) +
              (staleCount > 0 ? 1 : 0);
          final displayNeedsYouCount = totalThingsNeedYou;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Hero Banner Card
                _buildHeroBanner(
                  context: context,
                  displayNeedsYouCount: displayNeedsYouCount,
                  workloadLive:
                      appState.syncHealth.roadsLive &&
                      appState.syncHealth.channels['reports'] ==
                          SyncCondition.live &&
                      appState.syncHealth.channels['alerts'] ==
                          SyncCondition.live,
                  alertsLive:
                      appState.syncHealth.channels['alerts'] ==
                      SyncCondition.live,
                  weatherText: weatherText,
                  liveAlertsCount: liveAlertsCount,
                ),
                const SizedBox(height: 20),

                // 2. Quick Actions 4-in-a-row
                _buildQuickActionsRow(context, appState, isDark),
                const SizedBox(height: 24),

                // 3. Needs You Section
                _buildNeedsYouSection(
                  context: context,
                  appState: appState,
                  isDark: isDark,
                  pendingReportsCount: pendingReportsCount,
                  oldestSubmissionAge: oldestSubmissionAge,
                  liveAlertsCount: liveAlertsCount,
                  staleRoadsDisplay: staleRoadsDisplay,
                  workload: workload,
                  restrictedRecheckCount: restrictedRecheckCount,
                ),
                const SizedBox(height: 24),

                // 4. This Week / Insights Teaser
                _buildThisWeekSection(context, isDark, appState),
                const SizedBox(height: 24),

                // 5. Your Roads Section
                _buildYourRoadsSection(context, isDark, appState),
                const SizedBox(height: 24),

                // 6. Recent Activity Section
                _buildRecentActivitySection(context, isDark, appState),
                const SizedBox(height: 36),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getWeatherDescription(WeatherState state, double temp) {
    final tempStr = '${temp.round()}°';
    return switch (state) {
      WeatherState.clear => 'Clear • $tempStr',
      WeatherState.partlyCloudy => 'Partly cloudy • $tempStr',
      WeatherState.lightRain => 'Light rain • $tempStr',
      WeatherState.moderateRain => 'Moderate rain • $tempStr',
      WeatherState.heavyRain => 'Heavy rain • $tempStr',
      WeatherState.typhoon => 'Typhoon alert • $tempStr',
    };
  }

  Widget _buildHeroBanner({
    required BuildContext context,
    required int displayNeedsYouCount,
    required bool workloadLive,
    required bool alertsLive,
    required String weatherText,
    required int liveAlertsCount,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0056C6), Color(0xFF1972E6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0056C6).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -40,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat(
                      'EEEE, MMM d',
                    ).format(DateTime.now()).toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !workloadLive
                        ? tr(context, 'Workload needs a connection check')
                        : displayNeedsYouCount == 0
                        ? tr(context, 'No outstanding checks in the live feeds')
                        : displayNeedsYouCount == 1
                        ? tr(context, '1 area needs attention')
                        : tr(
                            context,
                            '{count} areas need attention',
                          ).replaceAll('{count}', '$displayNeedsYouCount'),
                    style: GoogleFonts.manrope(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tooltip(
                        key: const ValueKey('dashboard-weather-status'),
                        message: tr(
                          context,
                          'Weather status. Drills are managed separately in admin tools.',
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  weatherText,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (c, a, s) =>
                                const BroadcastAlertScreen(
                                  isStandalone: true,
                                  initiallyActive: true,
                                ),
                            transitionsBuilder: (c, a, s, child) =>
                                FadeTransition(opacity: a, child: child),
                            transitionDuration: const Duration(
                              milliseconds: 200,
                            ),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.campaign_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  !alertsLive
                                      ? tr(context, 'Alerts not confirmed')
                                      : liveAlertsCount == 1
                                      ? tr(context, '1 live alert')
                                      : tr(
                                          context,
                                          '{count} live alerts',
                                        ).replaceAll(
                                          '{count}',
                                          '$liveAlertsCount',
                                        ),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (c, a, s) =>
                              const UserReportsScreen(isStandalone: true),
                          transitionsBuilder: (c, a, s, child) =>
                              FadeTransition(opacity: a, child: child),
                          transitionDuration: const Duration(milliseconds: 200),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                tr(context, 'Start with reports'),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0056C6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Color(0xFF0056C6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow(
    BuildContext context,
    AppStateService appState,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildQuickActionItem(
          context: context,
          icon: Icons.campaign_rounded,
          iconColor: Colors.white,
          bgColor: const Color(0xFF0056C6),
          label: tr(context, 'Send alert'),
          isDark: isDark,
          onTap: () => Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (c, a, s) =>
                  const BroadcastAlertScreen(isStandalone: true),
              transitionsBuilder: (c, a, s, child) =>
                  FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 200),
            ),
          ),
        ),
        _buildQuickActionItem(
          context: context,
          icon: Icons.description_outlined,
          iconColor: const Color(0xFF975A16),
          bgColor: const Color(0xFFFEF3D6),
          label: tr(context, 'Reports'),
          isDark: isDark,
          onTap: () => Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (c, a, s) =>
                  const UserReportsScreen(isStandalone: true),
              transitionsBuilder: (c, a, s, child) =>
                  FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 200),
            ),
          ),
        ),
        _buildQuickActionItem(
          context: context,
          icon: Icons.edit_note_rounded,
          iconColor: const Color(0xFF1E7E34),
          bgColor: const Color(0xFFD7F5DD),
          label: tr(context, 'Update road'),
          isDark: isDark,
          onTap: () => Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (c, a, s) =>
                  const UpdateRoadStatusScreen(isStandalone: true),
              transitionsBuilder: (c, a, s, child) =>
                  FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 200),
            ),
          ),
        ),
        _buildQuickActionItem(
          context: context,
          icon: Icons.grid_view_rounded,
          iconColor: const Color(0xFF1A73E8),
          bgColor: const Color(0xFFE3EFFC),
          label: tr(context, 'Tools'),
          isDark: isDark,
          onTap: () => _showTemplatesAndToolsSheet(context, appState),
        ),
      ],
    );
  }

  Widget _buildQuickActionItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1B2430),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeedsYouSection({
    required BuildContext context,
    required AppStateService appState,
    required bool isDark,
    required int pendingReportsCount,
    required String? oldestSubmissionAge,
    required int liveAlertsCount,
    required int staleRoadsDisplay,
    required ReportWorkload workload,
    required int restrictedRecheckCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Needs you'),
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1B2430),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E232A) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF2D3540) : const Color(0xFFE2E7ED),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (workload.urgent > 0)
                _buildNeedsYouRow(
                  icon: Icons.sos,
                  iconColor: AppPalette.of(context).error,
                  iconBgColor: AppPalette.of(
                    context,
                  ).error.withValues(alpha: .10),
                  title:
                      appState.syncHealth.channels['reports'] ==
                          SyncCondition.live
                      ? tr(
                          context,
                          'Urgent open reports: {count}',
                        ).replaceAll('{count}', '${workload.urgent}')
                      : tr(context, 'Saved urgent reports need checking'),
                  subtitle: tr(
                    context,
                    'Includes those waiting for a resident reply.',
                  ),
                  isDark: isDark,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UserReportsScreen(
                        isStandalone: true,
                        initiallyUrgent: true,
                      ),
                    ),
                  ),
                ),
              _buildNeedsYouRow(
                icon: Icons.description_outlined,
                iconColor: const Color(0xFF975A16),
                iconBgColor: const Color(0xFFFEF3D6),
                title:
                    appState.syncHealth.channels['reports'] !=
                        SyncCondition.live
                    ? tr(context, 'Report queue not confirmed')
                    : pendingReportsCount == 1
                    ? tr(context, '1 report to review')
                    : tr(
                        context,
                        '{count} reports to review',
                      ).replaceAll('{count}', '$pendingReportsCount'),
                subtitle:
                    appState.syncHealth.channels['reports'] !=
                        SyncCondition.live
                    ? tr(context, 'Connect to confirm the current workload.')
                    : pendingReportsCount == 0
                    ? tr(context, 'No reports need admin review.')
                    : oldestSubmissionAge != null
                    ? tr(
                        context,
                        'Oldest submitted {age}.',
                      ).replaceAll('{age}', oldestSubmissionAge)
                    : tr(context, 'Reports waiting for assessment.'),
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (c, a, s) =>
                        const UserReportsScreen(isStandalone: true),
                    transitionsBuilder: (c, a, s, child) =>
                        FadeTransition(opacity: a, child: child),
                    transitionDuration: const Duration(milliseconds: 200),
                  ),
                ),
              ),
              if (workload.waiting > 0)
                _buildNeedsYouRow(
                  icon: Icons.question_answer_outlined,
                  iconColor: const Color(0xFF0056C6),
                  iconBgColor: const Color(0xFFE3EFFC),
                  title: tr(context, 'Waiting for resident'),
                  subtitle:
                      appState.syncHealth.channels['reports'] ==
                          SyncCondition.live
                      ? '${workload.waiting} ${tr(context, 'reports awaiting a reply')}'
                      : tr(context, 'Report queue not confirmed'),
                  isDark: isDark,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UserReportsScreen(
                        isStandalone: true,
                        initiallyWaitingResident: true,
                      ),
                    ),
                  ),
                ),
              Divider(
                height: 1,
                indent: 64,
                color: isDark
                    ? const Color(0xFF2C3440)
                    : const Color(0xFFEDF2F7),
              ),
              _buildNeedsYouRow(
                icon: Icons.campaign_outlined,
                iconColor: const Color(0xFFC53030),
                iconBgColor: const Color(0xFFFED7D7),
                title:
                    appState.syncHealth.channels['alerts'] != SyncCondition.live
                    ? tr(context, 'Alerts not confirmed')
                    : liveAlertsCount == 1
                    ? tr(context, '1 alert is still live')
                    : tr(
                        context,
                        '{count} alerts are still live',
                      ).replaceAll('{count}', '$liveAlertsCount'),
                subtitle: tr(
                  context,
                  appState.syncHealth.channels['alerts'] != SyncCondition.live
                      ? 'Connect to check active alerts.'
                      : liveAlertsCount == 0
                      ? 'No active alerts.'
                      : 'Review active alerts and withdraw those no longer needed.',
                ),
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (c, a, s) => const BroadcastAlertScreen(
                      isStandalone: true,
                      initiallyActive: true,
                    ),
                    transitionsBuilder: (c, a, s, child) =>
                        FadeTransition(opacity: a, child: child),
                    transitionDuration: const Duration(milliseconds: 200),
                  ),
                ),
              ),
              Divider(
                height: 1,
                indent: 64,
                color: isDark
                    ? const Color(0xFF2C3440)
                    : const Color(0xFFEDF2F7),
              ),
              if (restrictedRecheckCount > 0)
                _buildNeedsYouRow(
                  icon: Icons.warning_amber_rounded,
                  iconColor: AppPalette.of(context).warning,
                  iconBgColor: AppPalette.of(
                    context,
                  ).warning.withValues(alpha: .10),
                  title: appState.syncHealth.roadsLive
                      ? tr(
                          context,
                          'Restricted roads to recheck: {count}',
                        ).replaceAll('{count}', '$restrictedRecheckCount')
                      : tr(context, 'Saved road restrictions need checking'),
                  subtitle: tr(
                    context,
                    'Restrictions remain in effect until a new verified update.',
                  ),
                  isDark: isDark,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UpdateRoadStatusScreen(
                        isStandalone: true,
                        initialFilter: 'restricted_recheck',
                      ),
                    ),
                  ),
                ),
              _buildNeedsYouRow(
                icon: Icons.add_road_rounded,
                iconColor: const Color(0xFF2B6CB0),
                iconBgColor: const Color(0xFFBEE3F8),
                title: !appState.syncHealth.roadsLive
                    ? tr(context, 'Road updates not confirmed')
                    : staleRoadsDisplay == 1
                    ? tr(context, '1 road needs a check')
                    : tr(
                        context,
                        '{count} roads need a check',
                      ).replaceAll('{count}', '$staleRoadsDisplay'),
                subtitle: tr(
                  context,
                  !appState.syncHealth.roadsLive
                      ? 'Saved conditions may be outdated. Reconnect to check.'
                      : staleRoadsDisplay == 0
                      ? 'No road checks are currently flagged.'
                      : 'Old, unverified or reported conditions need a barangay check.',
                ),
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UpdateRoadStatusScreen(
                      isStandalone: true,
                      initialFilter: 'needs_check',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNeedsYouRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1B2430),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white38 : const Color(0xFF9CA3AF),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardCard(BuildContext context, Widget child) {
    final p = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .65)),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    String action,
    VoidCallback onTap,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Text(
        tr(context, title),
        style: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppPalette.of(context).onSurface,
        ),
      );
      final button = TextButton(
        onPressed: onTap,
        child: Text(tr(context, action)),
      );
      if (MediaQuery.textScalerOf(context).scale(12) > 17 ||
          constraints.maxWidth < 280)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            Align(alignment: Alignment.centerRight, child: button),
          ],
        );
      return Row(
        children: [
          Expanded(child: heading),
          const SizedBox(width: 8),
          button,
        ],
      );
    },
  );
  void _openInsights() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminInsightsScreen(load: widget.loadInsights),
    ),
  );
  Widget _buildThisWeekSection(
    BuildContext context,
    bool isDark,
    AppStateService appState,
  ) => FutureBuilder<AdminInsightsData>(
    future: _weekData,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final data = loading ? null : snapshot.data;
      final p = AppPalette.of(context);
      return _dashboardCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              'Last 7 days',
              'See insights',
              _openInsights,
            ),
            if (loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(tr(context, 'Checking insights...')),
            ] else if (data == null) ...[
              Text(
                tr(
                  context,
                  'Insights unavailable. Connect and refresh; no totals are assumed.',
                ),
              ),
              TextButton.icon(
                onPressed: _refreshInsights,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'Refresh')),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tr(context, 'Checked')}: ${localizedDateTime(context, data.checkedAt)}',
                      style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshInsights,
                    tooltip: tr(context, 'Refresh'),
                    icon: Icon(Icons.refresh, size: 20, color: p.primary),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = [
                    ('Reports received', '${data.received}'),
                    (
                      'Verified',
                      data.verifiedPercent == null
                          ? '--'
                          : '${data.verifiedPercent}%',
                    ),
                    (
                      'Avg. final review',
                      data.averageReviewMinutes == null
                          ? '--'
                          : data.averageReviewMinutes == 0
                          ? '<1 min'
                          : '${data.averageReviewMinutes} min',
                    ),
                  ];
                  Widget tile((String, String) metric) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$2,
                          style: GoogleFonts.manrope(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: p.primary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tr(context, metric.$1),
                          style: TextStyle(
                            fontSize: 12,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                  if (MediaQuery.textScalerOf(context).scale(12) > 17)
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final metric in metrics)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: tile(metric),
                          ),
                      ],
                    );
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < metrics.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: tile(metrics[i])),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (data.received == 0)
                _emptyDashboardState(
                  context,
                  Icons.inbox_outlined,
                  'No reports in this period.',
                )
              else
                _buildMiniWeekBarChart(isDark, data),
            ],
          ],
        ),
      );
    },
  );
  Widget _emptyDashboardState(
    BuildContext context,
    IconData icon,
    String message,
  ) {
    final p = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: p.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(context, message),
              style: TextStyle(fontSize: 13, color: p.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniWeekBarChart(bool isDark, AdminInsightsData data) {
    final maximum = data.buckets.map((b) => b.count).fold<int>(1, max);
    final bars = data.buckets
        .map(
          (b) => {
            'day': DateFormat(
              'MMM d',
              Localizations.localeOf(context).toLanguageTag(),
            ).format(b.start),
            'val': b.count / maximum,
          },
        )
        .toList();

    return SizedBox(
      height: 90 * MediaQuery.textScalerOf(context).scale(12) / 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((b) {
          final fraction = b['val'] as double;
          final day = b['day'] as String;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction,
                      child: Container(
                        width: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2575FC),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  day,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF5A6474),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildYourRoadsSection(
    BuildContext context,
    bool isDark,
    AppStateService appState,
  ) {
    final p = AppPalette.of(context),
        weather = SimulatedWeatherService.instance;
    final overview = AdminRoadOverview(
      appState.roads,
      DateTime.now(),
      weather.currentState,
    );
    final prediction = AdminPredictionSummary(
      roads: appState.roads,
      computedAt: appState.syncHealth.lastRiskCompute,
      now: DateTime.now(),
      riskSync:
          appState.syncHealth.channels['risk'] ?? SyncCondition.connecting,
      roadsLive: appState.syncHealth.roadsLive,
      weatherFresh: !weather.isDataStale,
      drill: weather.isOverrideMode,
    );
    return _dashboardCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            'Your roads',
            'See all',
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const UpdateRoadStatusScreen(isStandalone: true),
              ),
            ),
          ),
          if (!appState.syncHealth.roadsLive)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                tr(
                  context,
                  'Saved conditions may be outdated. Reconnect to check.',
                ),
                style: TextStyle(color: p.warning),
              ),
            ),
          if (appState.syncHealth.roadsLive || appState.roads.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = MediaQuery.textScalerOf(context).scale(12) > 17
                    ? 1
                    : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final entry in [
                      (
                        'Confirmed passable',
                        'passable',
                        p.secondary,
                        Icons.check_circle_outline,
                      ),
                      (
                        'Partially passable',
                        'partial',
                        p.partial,
                        Icons.warning_amber_rounded,
                      ),
                      (
                        'Not passable',
                        'not_passable',
                        p.notPassable,
                        Icons.block,
                      ),
                      (
                        'Unconfirmed',
                        'unconfirmed',
                        p.warning,
                        Icons.help_outline,
                      ),
                    ])
                      SizedBox(
                        width: width,
                        child: Material(
                          color: entry.$3.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: ValueKey('dashboard-road-${entry.$2}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UpdateRoadStatusScreen(
                                  isStandalone: true,
                                  initialFilter: entry.$2,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(entry.$4, color: entry.$3, size: 19),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${overview.count(entry.$2)}',
                                          style: GoogleFonts.manrope(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w800,
                                            color: p.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    tr(context, entry.$1),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: p.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (appState.syncHealth.lastRoadSync != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${tr(context, 'Last synced')}: ${localizedAge(context, appState.syncHealth.lastRoadSync!, DateTime.now())}',
                style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              tr(context, 'More details'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              tr(context, 'Prediction outlook'),
              style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
            ),
            leading: Icon(Icons.insights_outlined, color: p.primary, size: 21),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'Prediction details'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, prediction.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: prediction.current ? p.primary : p.warning,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (prediction.current)
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final risk in ['Critical', 'Warning', 'Watch'])
                            Text(
                              '${tr(context, risk)}: ${prediction.count(risk)}',
                            ),
                        ],
                      ),
                    if (prediction.knownTime)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${tr(context, 'Last calculation')}: ${localizedDateTime(context, prediction.computedAt!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Model estimates are separate from barangay-confirmed road conditions.',
                      ),
                      style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(
    BuildContext context,
    bool isDark,
    AppStateService appState,
  ) => FutureBuilder<AdminInsightsData>(
    future: _weekData,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData)
        return const SizedBox.shrink();
      final reports = snapshot.data!.reports.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final p = AppPalette.of(context);
      return _dashboardCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              'Recent submissions',
              'See all',
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const UserReportsScreen(
                    isStandalone: true,
                    initiallyHistory: true,
                  ),
                ),
              ),
            ),
            Text(
              tr(context, 'Submitted in the checked 7-day period'),
              style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              _emptyDashboardState(
                context,
                Icons.description_outlined,
                'No reports in this period.',
              ),
            for (final report in reports.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: p.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('dashboard-submission-${report.id}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserReportsScreen(
                          isStandalone: true,
                          initialReportId: report.id,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            color: p.primary,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  residentRoadTitle(
                                    appState.roads
                                            .where((r) => r.id == report.roadId)
                                            .firstOrNull
                                            ?.name ??
                                        report.title,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  report.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: p.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${tr(context, 'Submitted')}: ${localizedAge(context, report.createdAt, DateTime.now())}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right, size: 20, color: p.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  void _showTemplatesAndToolsSheet(
    BuildContext context,
    AppStateService appState,
  ) {
    final p = AppPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      builder: (sheetContext) {
        void open(Widget page) {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
        }

        Widget group(String title) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(
            tr(context, title),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: p.primary,
              letterSpacing: .5,
            ),
          ),
        );
        Widget tool(
          IconData icon,
          String title,
          String subtitle,
          VoidCallback tap,
        ) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: p.outlineVariant.withValues(alpha: .55)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: p.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, title),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tr(context, subtitle),
                            style: TextStyle(
                              fontSize: 12,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      color: p.onSurfaceVariant,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Admin tools'),
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Close'),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              group('Alerts and community'),
              tool(
                Icons.campaign_outlined,
                'Broadcast Templates',
                'Reuse an alert message',
                () => open(const BroadcastAlertScreen(isStandalone: true)),
              ),
              tool(
                Icons.people_outline,
                'Reporter review',
                'Review reporter trust and observations',
                () => open(const ConsensusAuditScreen()),
              ),
              group('System checks'),
              tool(
                Icons.monitor_heart_outlined,
                'Technical diagnostics',
                'Feed states, road connections and local activity',
                () => open(const AdminDiagnosticsScreen()),
              ),
              group('Advanced maintenance'),
              tool(
                Icons.science_outlined,
                'Weather drill',
                'Simulate conditions for a clearly identified area',
                () => open(const WeatherSimulatorScreen()),
              ),
              tool(
                Icons.map_outlined,
                'Import roads',
                'Review map data before importing',
                () => open(const ImportRoadsScreen()),
              ),
              tool(
                Icons.hub_outlined,
                'Rebuild road connections',
                'Update routing links between roads',
                () {
                  Navigator.of(sheetContext).pop();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const AdminGraphRebuildDialog(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
