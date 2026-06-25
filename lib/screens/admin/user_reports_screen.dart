import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import 'update_road_status_screen.dart';
import 'report_details_screen.dart';
import '../../widgets/user_report_card.dart';

class UserReportsScreen extends StatefulWidget {
  final bool isStandalone;
  const UserReportsScreen({super.key, this.isStandalone = false});

  @override
  State<UserReportsScreen> createState() => _UserReportsScreenState();
}

class _UserReportsScreenState extends State<UserReportsScreen> {
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VERIFY REPORT',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Update Map Status?',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
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
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppColors.outlineVariant),
                      ),
                      child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close bottom sheet
                        // Navigate to UpdateRoadStatusScreen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UpdateRoadStatusScreen(
                              prefilledRoadId: report.roadId,
                              reportIdToVerify: report.id,
                              suggestedStatus: suggestedStatus,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return Scaffold(
      appBar: AppTopBar(
        title: 'User Reports',
        showBackButton: widget.isStandalone,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: widget.isStandalone ? () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        } : null,
      ),
      backgroundColor: AppColors.surface,
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          var activeReports = appState.reports
              .where((r) => r.status != 'dismissed')
              .toList();
          activeReports.sort((a, b) {
            if (a.status == 'pending' && b.status != 'pending') return -1;
            if (a.status != 'pending' && b.status == 'pending') return 1;
            return appState.calculateLiveConfidence(b).compareTo(appState.calculateLiveConfidence(a));
          });

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: activeReports.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INCIDENT MANAGEMENT',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'User Reports',
                      style: GoogleFonts.manrope(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: AppColors.onSurface,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        'Latest barangay submissions for verification',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final item = activeReports[index - 1];
              final isPending = item.status == 'pending';
              final isVerified = item.status == 'verified';

              Color severityColor = AppColors.primary;
              if (item.severity == 'High') {
                severityColor = AppColors.tertiary;
              } else if (item.severity == 'Medium') {
                severityColor = AppColors.primary;
              } else if (item.severity == 'Low') {
                severityColor = AppColors.secondary;
              }

              int trustLevel = 3;
              String rName = 'Anonymous';
              String rInitials = 'AN';
              try {
                final userProfile = appState.users.firstWhere((u) => u.id == item.userId);
                if (userProfile.name.isNotEmpty) {
                  rName = userProfile.name;
                  final nameParts = rName.split(' ');
                  if (nameParts.length > 1) {
                    rInitials = '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
                  } else {
                    rInitials = rName.substring(0, rName.length >= 2 ? 2 : 1).toUpperCase();
                  }
                }
                if (userProfile.trustScore >= 80) {
                  trustLevel = 5;
                } else if (userProfile.trustScore >= 60) trustLevel = 4;
                else if (userProfile.trustScore >= 40) trustLevel = 3;
                else if (userProfile.trustScore >= 20) trustLevel = 2;
                else trustLevel = 1;
              } catch (_) {}

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Dismissible(
                  key: Key(item.id),
                  direction: isPending ? DismissDirection.horizontal : DismissDirection.none,
                  background: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 32),
                  ),
                  secondaryBackground: Container(
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.endToStart) {
                      appState.dismissReport(item.id);
                      return true;
                    } else if (direction == DismissDirection.startToEnd) {
                      _showVerifyBottomSheet(context, item);
                      return false;
                    }
                    return false;
                  },
                  child: UserReportCard(
                    icon: Icons.info_outline,
                    iconColor: severityColor,
                    title: item.title,
                    time: _getTimeAgo(item.createdAt),
                    description: item.description,
                    showActions: isPending,
                    isVerified: isVerified,
                    confidence: isPending ? appState.calculateLiveConfidence(item) : null,
                    trustLevel: trustLevel,
                    reporterName: rName,
                    reporterInitials: rInitials,
                    onVerify: () => _showVerifyBottomSheet(context, item),
                    onDismiss: () => appState.dismissReport(item.id),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReportDetailsScreen(report: item),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
        );
       },
      ),
    );
  }
}