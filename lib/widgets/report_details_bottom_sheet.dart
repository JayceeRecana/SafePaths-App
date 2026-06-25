import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_colors.dart';
import '../services/app_state_service.dart';

class ReportDetailsBottomSheet extends StatelessWidget {
  final UserReport report;
  final bool isAdmin;
  
  const ReportDetailsBottomSheet({
    super.key,
    required this.report,
    this.isAdmin = false,
  });

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String hour = dt.hour > 12 ? '${dt.hour - 12}' : (dt.hour == 0 ? '12' : '${dt.hour}');
    String minute = dt.minute.toString().padLeft(2, '0');
    String amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    Color severityColor = AppColors.secondary;
    IconData severityIcon = Icons.water_drop_outlined;
    
    if (report.severity == 'Medium') {
      severityColor = AppColors.partial;
      severityIcon = Icons.warning_amber_rounded;
    } else if (report.severity == 'High') {
      severityColor = AppColors.notPassable;
      severityIcon = Icons.water_damage;
    }

    final appState = AppStateService.instance;

    final userProfiles = appState.users.where((u) => u.id == report.userId);
    final userProfile = userProfiles.isNotEmpty ? userProfiles.first : null;
    int trustScore = userProfile?.trustScore ?? 50;
    int userLevel = 1 + ((trustScore - 50) ~/ 20).clamp(0, 4);
    
    // Calculate Geofence Proximity Distance if available
    String distanceString = 'Unknown distance';
    if (report.location != null && report.roadId != null) {
      try {
        final road = appState.roads.firstWhere((r) => r.id == report.roadId);
        if (road.geometry != null && road.geometry!['coordinates'] != null) {
          final coords = road.geometry!['coordinates'] as List<dynamic>;
          double minDistance = double.infinity;
          
          for (var coord in coords) {
            if (coord is List && coord.length >= 2) {
              double rLng = (coord[0] as num).toDouble();
              double rLat = (coord[1] as num).toDouble();
              double userLat = (report.location!['lat'] as num).toDouble();
              double userLng = (report.location!['lng'] as num).toDouble();
              
              double dist = Geolocator.distanceBetween(userLat, userLng, rLat, rLng);
              if (dist < minDistance) minDistance = dist;
            }
          }
          
          if (minDistance != double.infinity) {
            if (minDistance < 1000) {
              distanceString = '${minDistance.round()} meters from road';
            } else {
              distanceString = '${(minDistance / 1000).toStringAsFixed(1)} km from road';
            }
          }
        }
      } catch (e) {
        // Road not found
      }
    }

    double liveConfidence = appState.calculateLiveConfidence(report);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: severityColor.withValues(alpha: 0.1),
                ),
                child: Icon(severityIcon, size: 24, color: severityColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(report.createdAt),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Description
          Text(
            'Report Details',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              report.description.isEmpty ? "No description provided." : report.description,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.onSurface,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Proximity Data
          Row(
            children: [
              const Icon(Icons.gps_fixed, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Geofence GPS: ',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  distanceString,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // User Reputation
          Text(
            'Reporter Profile',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Level $userLevel Trust',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (userProfile != null)
                Text(
                  '${userProfile.verifiedReports} verified reports',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Admin Diagnostics
          if (isAdmin) ...[
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.admin_panel_settings, size: 18, color: AppColors.notPassable),
                const SizedBox(width: 8),
                Text(
                  'Admin Diagnostics',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.notPassable,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.notPassable.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.notPassable.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Live Confidence Score', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface)),
                      Text('${liveConfidence.toStringAsFixed(1)}%', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.notPassable)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Authority Weight (0.5)', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                      Text((report.authorityScore * 0.5).toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Proximity Bonus', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                      Text('Calculated Live', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
