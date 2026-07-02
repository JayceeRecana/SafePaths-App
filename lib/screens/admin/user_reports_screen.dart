import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import 'update_road_status_screen.dart';
import '../../widgets/user_report_card.dart';
import 'dart:io';

class UserReportsScreen extends StatefulWidget {
  final bool isStandalone;
  final Function(bool)? onSelectionChanged;
  const UserReportsScreen({super.key, this.isStandalone = false, this.onSelectionChanged});

  @override
  State<UserReportsScreen> createState() => _UserReportsScreenState();
}

class _UserReportsScreenState extends State<UserReportsScreen> {
  String? _selectedReportId;
  bool _lastHasSelection = false;

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

  String _formatTime(DateTime dt) {
    String hour = dt.hour > 12 ? '${dt.hour - 12}' : (dt.hour == 0 ? '12' : '${dt.hour}');
    String minute = dt.minute.toString().padLeft(2, '0');
    String amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $amPm';
  }

  void _verifyReport(UserReport report) {
    final appState = AppStateService.instance;
    String suggestedStatus = 'passable';
    if (report.severity == 'Medium') suggestedStatus = 'partial';
    if (report.severity == 'High') suggestedStatus = 'not_passable';

    setState(() {
      _selectedReportId = null; // Close card
    });

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
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;
    final bool hasSelection = _selectedReportId != null;
    
    if (hasSelection != _lastHasSelection) {
      _lastHasSelection = hasSelection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelectionChanged?.call(hasSelection);
      });
    }

    return Scaffold(
      appBar: AppTopBar(
        title: 'User Reports',
        showBackButton: Navigator.canPop(context),
        showProfile: true,
        showSettingsAction: true,
        onBackPressed: Navigator.canPop(context) ? () => Navigator.pop(context) : null,
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

          UserReport? selectedReport;
          if (_selectedReportId != null) {
            try {
              selectedReport = activeReports.firstWhere((r) => r.id == _selectedReportId);
            } catch (_) {}
          }

          return Stack(
            children: [
              // 1. The List Layer
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (_selectedReportId != null) {
                      setState(() => _selectedReportId = null);
                    }
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, _selectedReportId != null ? 400 : 120),
                    itemCount: activeReports.length,
                    itemBuilder: (context, index) {
                      final item = activeReports[index];
                      final isPending = item.status == 'pending';
                      final isVerified = item.status == 'verified';

                      Color severityColor = AppColors.primary;
                      if (item.severity == 'High') severityColor = AppColors.tertiary;
                      else if (item.severity == 'Medium') severityColor = AppColors.primary;
                      else if (item.severity == 'Low') severityColor = AppColors.secondary;

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
                        if (userProfile.trustScore >= 80) trustLevel = 5;
                        else if (userProfile.trustScore >= 60) trustLevel = 4;
                        else if (userProfile.trustScore >= 40) trustLevel = 3;
                        else if (userProfile.trustScore >= 20) trustLevel = 2;
                        else trustLevel = 1;
                      } catch (_) {}

                      final isSelected = item.id == _selectedReportId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: severityColor.withValues(alpha: 0.3),
                                blurRadius: 16,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              )
                            ] : [],
                          ),
                          child: Dismissible(
                            key: Key(item.id),
                            direction: isPending ? DismissDirection.horizontal : DismissDirection.none,
                            background: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 32),
                            ),
                            secondaryBackground: Container(
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Dismiss Report', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.error)),
                                    content: Text('Are you sure you want to dismiss this report? This will penalize the citizen\'s trust score.', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600))),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                                        onPressed: () => Navigator.pop(context, true), 
                                        child: Text('Dismiss', style: GoogleFonts.inter(fontWeight: FontWeight.w600))
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return false;

                                appState.dismissReport(item.id);
                                if (_selectedReportId == item.id) setState(() => _selectedReportId = null);
                                return true;
                              } else if (direction == DismissDirection.startToEnd) {
                                _verifyReport(item);
                                return false;
                              }
                              return false;
                            },
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  setState(() {
                                    if (_selectedReportId == item.id) {
                                      _selectedReportId = null;
                                    } else {
                                      _selectedReportId = item.id;
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected ? severityColor : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: UserReportCard(
                                    icon: Icons.info_outline,
                                    iconColor: severityColor,
                                    title: item.title,
                                    time: _getTimeAgo(item.createdAt),
                                    description: item.description,
                                    showActions: false, // Actions moved to floating card
                                    isVerified: isVerified,
                                    confidence: isPending ? appState.calculateLiveConfidence(item) : null,
                                    trustLevel: trustLevel,
                                    reporterName: rName,
                                    reporterInitials: rInitials,
                                    onVerify: null,
                                    onDismiss: null,
                                    onTap: null, // Handled by outer InkWell
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 2. The Dynamic Floating Card
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                bottom: selectedReport != null ? 16 : -500,
                left: 16,
                right: 16,
                child: selectedReport != null ? _buildFloatingCard(selectedReport) : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFloatingCard(UserReport report) {
    Color severityColor = AppColors.primary;
    if (report.severity == 'High') severityColor = AppColors.tertiary;
    else if (report.severity == 'Medium') severityColor = AppColors.primary;
    else if (report.severity == 'Low') severityColor = AppColors.secondary;

    IconData badgeIcon = Icons.info_outline;
    if (report.severity == 'High') badgeIcon = Icons.warning_rounded;
    else if (report.severity == 'Medium') badgeIcon = Icons.water_drop;
    else if (report.severity == 'Low') badgeIcon = Icons.check_circle;

    final isPending = report.status == 'pending';
    final roadName = AppStateService.instance.roads.firstWhere((r) => r.id == report.roadId, orElse: () => RoadStatus(id: '', name: 'Unknown Road', status: '', notes: '', updatedAt: DateTime.now())).name;
    
    UserProfile reporter = UserProfile(id: report.userId);
    try {
      reporter = AppStateService.instance.users.firstWhere((u) => u.id == report.userId);
    } catch (_) {}

    String timeStr = '${_getTimeAgo(report.createdAt)} • ${_formatTime(report.createdAt)}';

    return Material(
      elevation: 24,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      color: AppColors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setState(() => _selectedReportId = null),
                  icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
                Text(
                  'Report Details',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.admin_panel_settings, size: 16, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reporter Box
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            reporter.name.isNotEmpty ? reporter.name.substring(0, 1).toUpperCase() : 'U',
                            style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('REPORTER', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: AppColors.outlineVariant)),
                              Text(reporter.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            ],
                          ),
                        ),
                        // Trust Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: reporter.trustScore >= 70 ? AppColors.secondary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: reporter.trustScore >= 70 ? AppColors.secondary.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 12, color: reporter.trustScore >= 70 ? AppColors.secondary : AppColors.primary),
                              const SizedBox(width: 4),
                              Text('${reporter.trustScore}% Trust', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: reporter.trustScore >= 70 ? AppColors.secondary : AppColors.primary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Priority Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: severityColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('${report.severity.toUpperCase()} PRIORITY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Time
                    Text(timeStr, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.outlineVariant)),
                    const SizedBox(height: 12),

                    // Headline
                    Text(
                      report.title,
                      style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 12),

                    // Location Box (Borderless)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            roadName,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // The Quote Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
                        ],
                        border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
                      ),
                      child: Text(
                        '"${report.description}"', 
                        style: GoogleFonts.inter(
                          fontSize: 14, 
                          fontWeight: FontWeight.w500, 
                          color: AppColors.onSurfaceVariant, 
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Evidence Image
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.image_outlined, size: 16, color: AppColors.outlineVariant),
                            const SizedBox(width: 8),
                            Text('Evidence Image', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                          ],
                        ),
                        Text('FULL RESOLUTION', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (report.imageUrl != null && report.imageUrl!.isNotEmpty)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              report.imageUrl!,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (report.location != null)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  'GPS - ${report.location!['lat'].toStringAsFixed(5)}°, ${report.location!['lng'].toStringAsFixed(5)}°',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text('No Image Attached', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
            
            // Action Buttons
            if (isPending) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _verifyReport(report),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle, size: 20, color: Colors.white),
                      label: Text('VERIFY & UPDATE MAP', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: FilledButton.icon(
                      onPressed: () {
                        AppStateService.instance.dismissReport(report.id);
                        setState(() => _selectedReportId = null);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerHigh,
                        foregroundColor: AppColors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.close, size: 20),
                      label: Text('DISMISS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ); }
}