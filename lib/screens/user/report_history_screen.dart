import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/user_service.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    UserService.getUserId().then((uid) {
      if (mounted) {
        setState(() {
          _userId = uid;
        });
      }
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'verified': return AppColors.primary;
      case 'pending': return AppColors.secondary;
      case 'dismissed': return AppColors.error;
      case 'expired': return AppColors.onSurfaceVariant;
      default: return AppColors.secondary;
    }
  }

  String _formatStatus(String status) {
    if (status.isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Report History',
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppColors.surface,
      body: _userId == null 
        ? const Center(child: CircularProgressIndicator())
        : ListenableBuilder(
            listenable: AppStateService.instance,
            builder: (context, _) {
              final history = AppStateService.instance.reports
                  .where((r) => r.userId == _userId)
                  .toList();

              if (history.isEmpty) {
                return Center(
                  child: Text(
                    'No reports submitted yet.',
                    style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 24),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final item = history[index];
                  final statusColor = _getStatusColor(item.status);
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _formatStatus(item.status),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Submitted on ${DateFormat('MMM d, yyyy h:mm a').format(item.createdAt)}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                              ),
                              if (item.imageUrl != null)
                                Icon(Icons.image, size: 16, color: AppColors.primary),
                            ],
                          ),
                        ],
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
