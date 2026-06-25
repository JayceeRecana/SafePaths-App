import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import 'report_submission_screen.dart';
import '../../widgets/app_map.dart';
import '../../widgets/report_details_bottom_sheet.dart';
import '../../services/user_service.dart';
import '../admin/update_road_status_screen.dart';

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
        return FadeTransition(
          opacity: fadeAnimation,
          child: child,
        );
      },
    );
  }

  @override
  State<RoadDetailsScreen> createState() => _RoadDetailsScreenState();
}

class _RoadDetailsScreenState extends State<RoadDetailsScreen> {
  UserRole? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final role = await UserService.getUserRole();
    if (mounted) setState(() => _userRole = role);
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) {
      return 'JUST NOW';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} MIN AGO';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} HR AGO';
    } else {
      return '${difference.inDays} DAYS AGO';
    }
  }

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
                color: AppColors.onSurfaceVariant,
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
                color: AppColors.onSurface,
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
        final roadIndex = appState.roads.indexWhere((r) => r.id == widget.roadId);
        
        if (roadIndex == -1) {
          return Scaffold(
            appBar: const AppTopBar(title: 'Road Details', showBackButton: true),
            backgroundColor: AppColors.surface,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.not_interested, size: 64, color: AppColors.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Road Not Found',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The requested road details are unavailable.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final road = appState.roads[roadIndex];

        // Filter reports matching this road (ONLY pending reports are active warnings)
        final activeReports = appState.reports
            .where((r) => r.status == 'pending' && r.roadId == road.id)
            .toList();

        String statusText = 'SAFE AND PASSABLE';
        Color statusBgColor = AppColors.secondaryContainer;
        Color statusColor = AppColors.secondary;
        IconData statusIcon = Icons.check_circle;

        final effectiveStatus = road.getEffectiveStatus(SimulatedWeatherService.instance.currentState);

        if (effectiveStatus == 'partial') {
          statusText = 'PARTIALLY FLOODED';
          statusBgColor = AppColors.surfaceContainerHigh; 
          statusColor = AppColors.partial;
          statusIcon = Icons.info;
        } else if (effectiveStatus == 'not_passable') {
          statusText = 'NOT PASSABLE';
          statusBgColor = AppColors.errorContainer;
          statusColor = AppColors.notPassable;
          statusIcon = Icons.warning;
        }

        int dynamicConfidence = road.confidence ?? 100;
        int hoursOld = DateTime.now().difference(road.updatedAt).inHours;
        dynamicConfidence -= hoursOld;
        if (dynamicConfidence < 60) dynamicConfidence = 60;

        if (activeReports.isNotEmpty) {
          double maxConflictingConfidence = 0.0;
          double maxReinforcingConfidence = 0.0;

          for (var r in activeReports) {
            double conf = appState.calculateLiveConfidence(r);
            bool isConflicting = false;
            if (effectiveStatus == 'passable' && r.severity != 'Low') isConflicting = true;
            if (effectiveStatus == 'not_passable' && r.severity == 'Low') isConflicting = true;
            if (effectiveStatus == 'partial' && r.severity != 'Medium') isConflicting = true;
            
            if (isConflicting) {
              if (conf > maxConflictingConfidence) maxConflictingConfidence = conf;
            } else {
              if (conf > maxReinforcingConfidence) maxReinforcingConfidence = conf;
            }
          }

          if (maxConflictingConfidence > 0) {
            dynamicConfidence = 100 - maxConflictingConfidence.round();
          } else if (maxReinforcingConfidence > 0) {
            dynamicConfidence = 50 + (maxReinforcingConfidence / 2).round();
          }
        }
        
        if (dynamicConfidence < 5) dynamicConfidence = 5;
        if (dynamicConfidence > 100) dynamicConfidence = 100;

        String confidenceLabel = 'High Accuracy';
        Color confidenceColor = AppColors.secondary;
        if (dynamicConfidence < 50) {
          confidenceLabel = 'Low Accuracy';
          confidenceColor = AppColors.notPassable;
        } else if (dynamicConfidence < 75) {
          confidenceLabel = 'Moderate Accuracy';
          confidenceColor = AppColors.partial;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Tap background to dismiss
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Content Draggable
              DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Header
                          Text(
                            road.name,
                            style: GoogleFonts.manrope(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Updated ${_getTimeAgo(road.updatedAt)} by Admin',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Status pill
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(statusIcon, size: 20, color: statusColor),
                                const SizedBox(width: 8),
                                Text(
                                  statusText,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          if (road.vulnerability != 'low') ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.analytics_outlined,
                                      size: 18,
                                      color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Predictive Risk Model: ${road.vulnerability.toUpperCase()} VULNERABILITY',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // Status bento grid
                          LayoutBuilder(
                            builder: (context, constraints) {
                              String weatherName = 'Clear';
                              if (SimulatedWeatherService.instance.currentState == WeatherState.heavyRain) weatherName = 'Heavy Rain';
                              else if (SimulatedWeatherService.instance.currentState == WeatherState.typhoon) weatherName = 'Typhoon';

                              return Column(
                                children: [
                                  // PREDICTIVE INTELLIGENCE
                                  if (road.riskScore > 0) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.orange.withValues(alpha: 0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.hub_outlined, size: 16, color: Colors.orange),
                                              const SizedBox(width: 8),
                                              Text(
                                                'PREDICTIVE INTELLIGENCE',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.5,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow('Risk Category', road.riskCategory, isBold: true),
                                          _buildDetailRow('Risk Score', road.riskScore.toStringAsFixed(1)),
                                          _buildDetailRow('Primary Source', 
                                            road.propagationSource != null 
                                              ? (appState.roads.cast<RoadStatus?>().firstWhere((r) => r?.id == road.propagationSource, orElse: () => null)?.name ?? road.propagationSource!)
                                              : 'None (Local Source)'
                                          ),
                                          _buildDetailRow('Weather Condition', weatherName),
                                          _buildDetailRow('Warning Duration', road.warningStartTime != null ? '${DateTime.now().difference(road.warningStartTime!).inMinutes} minutes' : '0 minutes'),
                                          _buildDetailRow('Confidence Level', dynamicConfidence >= 75 ? 'High' : (dynamicConfidence >= 50 ? 'Medium' : 'Low')),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Current Conditions
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.water_drop,
                                                size: 16,
                                                color: AppColors.primary),
                                            const SizedBox(width: 8),
                                            Text(
                                              'CURRENT CONDITIONS',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.5,
                                                color: AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          (road.notes.isNotEmpty && road.notes != 'Imported from OSM')
                                              ? road.notes
                                              : 'No specific conditions reported by the admin.',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.onSurface,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Trust/Confidence Score
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.timeline,
                                                size: 16,
                                                color: AppColors.primary),
                                            const SizedBox(width: 8),
                                            Text(
                                              'CONFIDENCE',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.5,
                                                color: AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '$dynamicConfidence%',
                                              style: GoogleFonts.manrope(
                                                fontSize: 36,
                                                fontWeight: FontWeight.w800,
                                                height: 1.0,
                                                letterSpacing: -1,
                                                color: AppColors.onSurface,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 4),
                                              child: Text(
                                                confidenceLabel,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: confidenceColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: dynamicConfidence / 100,
                                            minHeight: 6,
                                            backgroundColor: AppColors.surfaceContainerHigh,
                                            valueColor: AlwaysStoppedAnimation<Color>(confidenceColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          // Live Reports Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active User Reports',
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${activeReports.length} Reports',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (activeReports.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.outlineVariant.withValues(alpha: 0.2),
                                  strokeAlign: BorderSide.strokeAlignOutside,
                                ),
                              ),
                              child: Text(
                                'No active incident reports for this road.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: activeReports.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final report = activeReports[index];
                                return _ReportItem(
                                  name: 'Anonymous User',
                                  time: _getTimeAgo(report.createdAt),
                                  comment: report.description,
                                  severity: report.severity,
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => ReportDetailsBottomSheet(report: report),
                                    );
                                  },
                                );
                              },
                            ),

                          const SizedBox(height: 24),



                          // Actions
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReportSubmissionScreen(prefilledRoadId: road.id),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primaryContainer,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.campaign,
                                      size: 20,
                                      color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Report Update',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          FutureBuilder<UserRole?>(
                            future: UserService.getUserRole(),
                            builder: (context, snapshot) {
                              if (snapshot.data == UserRole.admin) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => UpdateRoadStatusScreen(prefilledRoadId: road.id),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppColors.notPassable, AppColors.errorContainer],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.notPassable.withValues(alpha: 0.2),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.admin_panel_settings, size: 20, color: Colors.white),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Admin: Update Status',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
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

class _ReportItem extends StatelessWidget {
  final String name;
  final String time;
  final String comment;
  final String severity;
  final VoidCallback? onTap;

  const _ReportItem({
    required this.name,
    required this.time,
    required this.comment,
    required this.severity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color severityColor = AppColors.secondary;
    IconData severityIcon = Icons.water_drop_outlined;
    
    if (severity == 'Medium') {
      severityColor = AppColors.partial;
      severityIcon = Icons.warning_amber_rounded;
    } else if (severity == 'High') {
      severityColor = AppColors.notPassable;
      severityIcon = Icons.water_damage;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: severityColor.withValues(alpha: 0.1),
            ),
            child: Icon(severityIcon, size: 20, color: severityColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
       ),
      ),
     ),
    ),
   );
  }
}