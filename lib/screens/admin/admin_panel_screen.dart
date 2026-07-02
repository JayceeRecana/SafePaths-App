import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../../services/routing_service.dart';
import '../../config/risk_config.dart';
import 'broadcast_alert_screen.dart';
import 'update_road_status_screen.dart';
import 'user_reports_screen.dart';
import 'weather_simulator_screen.dart';
import 'consensus_audit_screen.dart';
import 'import_roads_screen.dart';
import '../../widgets/user_report_card.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'JUST NOW';
    if (difference.inMinutes < 60) return '${difference.inMinutes} MIN AGO';
    if (difference.inHours < 24) return '${difference.inHours} HR AGO';
    return '${difference.inDays} DAYS AGO';
  }

  void _showVerifyBottomSheet(BuildContext context, UserReport report) {
    final appState = AppStateService.instance;
    final road = appState.roads.firstWhere(
      (r) => r.id == report.roadId, 
      orElse: () => RoadStatus(id: '', name: 'Unknown Road', status: '', notes: '', updatedAt: DateTime.now())
    );

    String suggestedStatus = 'passable';
    if (report.severity == 'Medium') suggestedStatus = 'partial';
    if (report.severity == 'High') suggestedStatus = 'not_passable';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VERIFY REPORT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: AppColors.primary)),
              const SizedBox(height: 8),
              Text('Update Map Status?', style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Road: ${report.roadId != null ? road.name : "Unknown"}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    const SizedBox(height: 4),
                    Text('Reported Severity: ${report.severity}', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Suggested Map Status: $suggestedStatus', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: AppColors.outlineVariant)),
                      child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => UpdateRoadStatusScreen(prefilledRoadId: report.roadId, reportIdToVerify: report.id, suggestedStatus: suggestedStatus)));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                      child: Text('Proceed', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showConfirmSafeDialog(BuildContext context, AppStateService appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final passableRoads = appState.roads.where((r) => r.status == 'passable').toList();
            passableRoads.sort((a, b) {
              final aStale = (DateTime.now().difference(a.updatedAt).inMinutes / 60.0) > RiskConfig.getPassableStaleThresholdHours(a.vulnerability);
              final bStale = (DateTime.now().difference(b.updatedAt).inMinutes / 60.0) > RiskConfig.getPassableStaleThresholdHours(b.vulnerability);
              if (aStale && !bStale) return -1;
              if (!aStale && bStale) return 1;
              return a.name.compareTo(b.name);
            });
            final staleRoads = passableRoads.where((r) => (DateTime.now().difference(r.updatedAt).inMinutes / 60.0) > RiskConfig.getPassableStaleThresholdHours(r.vulnerability)).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                if (passableRoads.isEmpty) {
                  return Center(child: Text('No passable roads to confirm.', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)));
                }

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Text('CONFIRM SAFE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: AppColors.primary)),
                    const SizedBox(height: 8),
                    Text('Re-verify Passable Roads', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                    const SizedBox(height: 4),
                    Text('This resets the Predictive Risk timer so roads stay green during storms.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    
                    if (staleRoads.isNotEmpty) ...[
                      FilledButton.icon(
                        onPressed: () async {
                          for (var road in staleRoads) {
                            await appState.updateRoadStatus(road.id, road.status, road.notes);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${staleRoads.length} roads confirmed safe.')));
                          }
                        },
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.verified, size: 20),
                        label: Text('Verify All ${staleRoads.length} Stale Roads', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      const SizedBox(height: 24),
                    ],

                    ...passableRoads.map((road) {
                      final hoursOld = DateTime.now().difference(road.updatedAt).inMinutes / 60.0;
                      final isStale = hoursOld > RiskConfig.getPassableStaleThresholdHours(road.vulnerability);

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isStale ? Colors.orange.withValues(alpha: 0.1) : AppColors.secondary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isStale ? Icons.warning_amber_rounded : Icons.check_circle,
                                    size: 20,
                                    color: isStale ? Colors.orange : AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(road.name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                                      const SizedBox(height: 2),
                                      Text(isStale ? 'Requires re-verification' : 'Recently verified', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                if (isStale)
                                  TextButton(
                                    onPressed: () async {
                                      await appState.updateRoadStatus(road.id, road.status, road.notes);
                                    },
                                    style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: AppColors.primary.withValues(alpha: 0.1)),
                                    child: Text('Verify', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                                    child: Text('FRESH', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.secondary)),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.outlineVariant),
                        ],
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;
    final routing = RoutingService.instance;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const AppTopBar(
        title: 'SafePaths Admin',
        showBackButton: false,
        showProfile: true,
        showSettingsAction: true,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([appState, routing]),
        builder: (context, _) {
          final weatherState = SimulatedWeatherService.instance.currentState;
          final floodedCount = appState.roads.where((r) => r.getEffectiveStatus(weatherState) == 'not_passable').length;
          final activeCount = appState.reports.where((r) => r.status == 'pending').length;
          final resolvedCount = appState.reports.where((r) => r.status == 'verified').length;

          var activeReports = appState.reports.where((r) => r.status != 'dismissed').toList();
          activeReports.sort((a, b) {
            if (a.status == 'pending' && b.status != 'pending') return -1;
            if (a.status != 'pending' && b.status == 'pending') return 1;
            return appState.calculateLiveConfidence(b).compareTo(appState.calculateLiveConfidence(a));
          });
          final displayReports = activeReports.take(3).toList();

          return CustomScrollView(
            slivers: [
              // Sticky Glassmorphism Header
              SliverAppBar(
                backgroundColor: AppColors.surface.withValues(alpha: 0.8),
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.0), BlendMode.dstOut), // Using BackdropFilter in a Stack is better, wait, SliverAppBar natively supports blur in newer versions if you use flexibleSpace
                    // Since we want glassmorphism, let's just make it slightly translucent.
                    child: Container(color: Colors.transparent),
                  ),
                ),
                floating: true,
                pinned: true,
                elevation: 0,
                title: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const UpdateRoadStatusScreen(isStandalone: true, autoFocusSearch: true),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              transitionDuration: const Duration(milliseconds: 200),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface, // Crisp white
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: AppColors.onSurfaceVariant, size: 18),
                              const SizedBox(width: 12),
                              Text('Search roads, reports, or incidents...', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeatherSimulatorScreen()));
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: AppColors.surface, // Matches search bar
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.science, color: AppColors.primary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Barangay Central Dashboard',
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // BENTO BOX GRID
                    _buildBentoGrid(appState, floodedCount, activeCount, resolvedCount),

                    const SizedBox(height: 24),
                    // Quick Actions
                    _buildQuickActions(context, appState),

                    const SizedBox(height: 32),
                    // User reports section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Reports', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserReportsScreen())),
                          child: Text('View All', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (displayReports.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1))),
                        child: Center(child: Text('No reports to display', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500))),
                      )
                    else
                      ...displayReports.map((report) {
                        final isPending = report.status == 'pending';
                        final isVerified = report.status == 'verified';

                        IconData icon = Icons.info_outline;
                        Color iconColor = AppColors.primary;
                        if (report.severity == 'High') { icon = Icons.warning_rounded; iconColor = AppColors.tertiary; }
                        else if (report.severity == 'Medium') { icon = Icons.cloud_upload; iconColor = AppColors.primary; }
                        else if (report.severity == 'Low') { icon = Icons.verified; iconColor = AppColors.secondary; }

                        int trustLevel = 3;
                        String rName = 'Anonymous';
                        String rInitials = 'AN';
                        try {
                          final userProfile = appState.users.firstWhere((u) => u.id == report.userId);
                          if (userProfile.name.isNotEmpty) {
                            rName = userProfile.name;
                            final nameParts = rName.split(' ');
                            if (nameParts.length > 1) { rInitials = '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase(); }
                            else { rInitials = rName.substring(0, rName.length >= 2 ? 2 : 1).toUpperCase(); }
                          }
                          if (userProfile.trustScore >= 80) trustLevel = 5;
                          else if (userProfile.trustScore >= 60) trustLevel = 4;
                          else if (userProfile.trustScore >= 40) trustLevel = 3;
                          else if (userProfile.trustScore >= 20) trustLevel = 2;
                          else trustLevel = 1;
                        } catch (_) {}

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: UserReportCard(
                            icon: icon, iconColor: iconColor, title: report.title, time: _getTimeAgo(report.createdAt), description: report.description,
                            showActions: isPending, isVerified: isVerified, confidence: isPending ? appState.calculateLiveConfidence(report) : null,
                            trustLevel: trustLevel, reporterName: rName, reporterInitials: rInitials,
                            onVerify: () => _showVerifyBottomSheet(context, report),
                            onDismiss: () => appState.dismissReport(report.id),
                            onTap: () {
                              // Send them to the main reports screen to view it properly
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserReportsScreen()));
                            },
                          ),
                        );
                      }),
                      
                    const SizedBox(height: 32),
                    // Activity Log
                    Text('System Activity Log', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                    const SizedBox(height: 16),
                    if (appState.systemLogs.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1))),
                        child: Center(child: Text('No automated actions yet', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500))),
                      )
                    else
                      ...appState.systemLogs.take(5).map((log) {
                        final isEscalation = log.action == 'Auto-Escalation';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isEscalation ? AppColors.tertiary.withValues(alpha: 0.1) : AppColors.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isEscalation ? AppColors.tertiary.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.3), width: isEscalation ? 2.0 : 1.0),
                            boxShadow: isEscalation ? [BoxShadow(color: AppColors.tertiary.withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 2)] : [],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: isEscalation ? AppColors.tertiary : AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: Icon(isEscalation ? Icons.auto_awesome : Icons.smart_toy, size: isEscalation ? 24 : 20, color: isEscalation ? Colors.white : AppColors.primary),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(log.action.toUpperCase(), style: GoogleFonts.inter(fontSize: isEscalation ? 14 : 13, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: isEscalation ? AppColors.tertiary : AppColors.primary)),
                                        Text(_getTimeAgo(log.timestamp), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isEscalation ? AppColors.tertiary : AppColors.onSurfaceVariant)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(log.details, style: GoogleFonts.inter(fontSize: 14, fontWeight: isEscalation ? FontWeight.w600 : FontWeight.w400, color: AppColors.onSurface, height: 1.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBentoGrid(AppStateService appState, int floodedCount, int activeCount, int resolvedCount) {
    final totalRoads = appState.roads.length;
    final passable = appState.roads.where((r) => r.status == 'passable').length;
    final partial = appState.roads.where((r) => r.status == 'partial').length;
    final notPassable = appState.roads.where((r) => r.status == 'not_passable').length;

    return Column(
      children: [
        // Top Large Bento: Road Network
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('NETWORK STATUS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 16),
              if (totalRoads > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        if (passable > 0) Expanded(flex: passable, child: Container(color: AppColors.secondary)),
                        if (partial > 0) Expanded(flex: partial, child: Container(color: AppColors.partial)),
                        if (notPassable > 0) Expanded(flex: notPassable, child: Container(color: AppColors.notPassable)),
                      ],
                    ),
                  ),
                )
              else
                Container(height: 24, decoration: BoxDecoration(color: AppColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(12))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildChartLegend('Passable', passable, AppColors.secondary),
                  _buildChartLegend('Partial', partial, AppColors.partial),
                  _buildChartLegend('Impassable', notPassable, AppColors.notPassable),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 24),
              _SystemHealthDashboard(appState: appState, routing: RoutingService.instance, weatherState: SimulatedWeatherService.instance.currentState),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Bottom Small Bentos
        Row(
          children: [
            Expanded(child: _AnimatedStatCard(icon: Icons.flood, iconColor: AppColors.tertiary, label: 'Flooded', value: floodedCount)),
            const SizedBox(width: 16),
            Expanded(child: _AnimatedStatCard(icon: Icons.assignment_late, iconColor: AppColors.primary, label: 'Reports', value: activeCount)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _AnimatedStatCard(icon: Icons.check_circle, iconColor: AppColors.secondary, label: 'Resolved', value: resolvedCount)),
            const SizedBox(width: 16),
            Expanded(
              child: _AnimatedStatCard(
                icon: Icons.warning_amber_rounded,
                iconColor: Colors.orange,
                label: 'At Risk',
                value: appState.roads.where((r) => r.riskCategory != 'Safe').length,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, AppStateService appState) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('QUICK ACTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ActionButton(icon: Icons.edit_road, label: 'Roads', onTap: () => Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, s) => const UpdateRoadStatusScreen(isStandalone: true), transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 200))))),
                const SizedBox(width: 8),
                Expanded(child: _ActionButton(icon: Icons.campaign, label: 'Alerts', onTap: () => Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, s) => const BroadcastAlertScreen(isStandalone: true), transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 200))))),
                const SizedBox(width: 8),
                Expanded(child: _ActionButton(icon: Icons.verified_user, label: 'Verify', onTap: () => _showConfirmSafeDialog(context, appState))),
                const SizedBox(width: 8),
                Expanded(child: _ActionButton(icon: Icons.receipt_long, label: 'Audit', onTap: () => Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, s) => const ConsensusAuditScreen(), transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 200))))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 24),
          Text('DEVELOPER TOOLS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportRoadsScreen())),
              icon: const Icon(Icons.download), label: Text('Bulk Import Roads (OSM)', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceContainerLow, foregroundColor: AppColors.onSurfaceVariant, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              onPressed: () async {
                await AppStateService.instance.buildAndVerifyRoadGraph();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Graph generated!')));
              },
              icon: const Icon(Icons.hub), label: Text('Build Road Graph', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int value;

  const _AnimatedStatCard({required this.icon, required this.iconColor, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(height: 24),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutQuart,
            builder: (context, val, child) {
              return Text(
                val.toString(),
                style: GoogleFonts.manrope(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Below are the preserved utility classes: _ActionButton, _LegendRow, _buildChartLegend, _SystemHealthDashboard
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (val) => setState(() => _isHovered = val),
        onHighlightChanged: (val) => setState(() => _isHovered = val),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            gradient: _isHovered ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryContainer]) : null,
            color: _isHovered ? null : AppColors.surfaceContainerLow,
            border: Border.all(color: _isHovered ? Colors.transparent : AppColors.outlineVariant.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isHovered ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 4))] : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _isHovered ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(widget.icon, size: 20, color: _isHovered ? Colors.white : AppColors.primary),
              ),
              const SizedBox(height: 12),
              Text(widget.label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _isHovered ? Colors.white : AppColors.onSurface, height: 1.2, letterSpacing: -0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
      ],
    );
  }
}

Widget _buildChartLegend(String label, int count, Color color) {
  return Row(
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
          Text(count.toString(), style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
        ],
      ),
    ],
  );
}

class _SystemHealthDashboard extends StatefulWidget {
  final AppStateService appState;
  final RoutingService routing;
  final WeatherState weatherState;
  const _SystemHealthDashboard({required this.appState, required this.routing, required this.weatherState});
  @override
  State<_SystemHealthDashboard> createState() => _SystemHealthDashboardState();
}

class _SystemHealthDashboardState extends State<_SystemHealthDashboard> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  @override
  void dispose() { _pageController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final totalRoads = widget.appState.roads.length;
    final disconnectedRoads = widget.appState.roads.where((r) => r.neighbors.isEmpty).length;
    final connectedRoads = totalRoads - disconnectedRoads;
    final totalConnections = widget.appState.roads.fold<int>(0, (sum, r) => sum + r.neighbors.length);
    final avgNeighbors = totalRoads > 0 ? (totalConnections / totalRoads) : 0.0;
    final engineMs = widget.appState.lastRiskEngineExecutionMs;
    String engineStatus = 'Healthy'; Color engineColor = AppColors.secondary;
    if (engineMs > 300) { engineStatus = 'Slow'; engineColor = AppColors.tertiary; }
    else if (engineMs >= 100) { engineStatus = 'Moderate'; engineColor = Colors.orange; }
    final String lastUpdateStr = widget.appState.lastRiskEngineRun != null ? DateFormat('h:mm:ss a').format(widget.appState.lastRiskEngineRun!) : 'Never';
    String weatherName = widget.weatherState.name; double propMult = 0.0;
    switch (widget.weatherState) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy: propMult = 0.0; break;
      case WeatherState.lightRain: propMult = 0.2; break;
      case WeatherState.moderateRain: propMult = 0.4; break;
      case WeatherState.heavyRain: propMult = 0.7; break;
      case WeatherState.typhoon: propMult = 1.0; break;
    }
    final critical = widget.appState.roads.where((r) => r.riskCategory == 'Critical').length;
    final warning = widget.appState.roads.where((r) => r.riskCategory == 'Warning').length;
    final watch = widget.appState.roads.where((r) => r.riskCategory == 'Watch').length;
    bool isOperational = true;
    if (engineMs > 300 || disconnectedRoads > (totalRoads * 0.2) || totalRoads == 0) isOperational = false;
    final pages = [
      _buildDashboardSection('ROAD NETWORK', ['Roads: $totalRoads', 'Connected: $connectedRoads', 'Disconnected: $disconnectedRoads', 'Avg Neighbors: ${avgNeighbors.toStringAsFixed(1)}']),
      _buildDashboardSection('RISK ENGINE', ['Execution: ${engineMs} ms', 'Last Update: $lastUpdateStr', 'Status: $engineStatus'], statusColor: engineColor),
      _buildDashboardSection('CURRENT CONDITIONS', ['Weather: ${weatherName.toUpperCase()}', 'Propagation: ×$propMult']),
      _buildDashboardSection('ACTIVE RISKS', ['Critical: $critical', 'Warning: $warning', 'Watch: $watch']),
      StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('analytics').doc('routing').snapshots(),
        builder: (context, snapshot) {
          int count = 0;
          double reduction = 0.0;
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data != null) {
              count = (data['routesProtectedCount'] as num?)?.toInt() ?? 0;
              final totalRed = (data['totalRiskReduction'] as num?)?.toDouble() ?? 0.0;
              if (count > 0) {
                reduction = totalRed / count;
              }
            }
          }
          return _buildDashboardSection('ALERTS & ANALYTICS', [
            'Active Alerts: ${widget.appState.alerts.where((a) => a.isActive).length}',
            'Routes Protected: $count',
            'Avg Risk Reduction: ${reduction.toStringAsFixed(0)}%'
          ]);
        },
      ),
      _buildDashboardSection('PREDICTION MODEL', ['Accuracy: Not Enough Data', 'Lead Time: Pending Validation']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SYSTEM HEALTH', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2.0, color: AppColors.onSurfaceVariant)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: isOperational ? AppColors.secondary.withValues(alpha: 0.2) : AppColors.tertiary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(100)),
              child: Text(isOperational ? 'OPERATIONAL' : 'DEGRADED', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: isOperational ? AppColors.secondary : AppColors.tertiary)),
            )
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: PageView.builder(controller: _pageController, onPageChanged: (index) { setState(() { _currentPage = index; }); }, itemCount: pages.length, itemBuilder: (context, index) { return Padding(padding: const EdgeInsets.only(right: 8.0), child: pages[index]); }),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(pages.length, (index) {
          return AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 4), height: 6, width: _currentPage == index ? 16 : 6, decoration: BoxDecoration(color: _currentPage == index ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)));
        })),
      ],
    );
  }
  Widget _buildDashboardSection(String title, List<String> lines, {Color? statusColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...lines.map((line) {
          final parts = line.split(': ');
          final label = parts[0];
          final val = parts.length > 1 ? parts[1] : '';
          Color valColor = AppColors.onSurface;
          if (label == 'Status' && statusColor != null) valColor = statusColor;
          else if (label == 'Accuracy' || label == 'Lead Time') valColor = AppColors.onSurfaceVariant;
          return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)), Text(val, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: valColor))]));
        }),
      ],
    );
  }
}