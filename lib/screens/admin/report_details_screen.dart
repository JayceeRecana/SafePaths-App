import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';
import '../../services/app_state_service.dart';
import 'update_road_status_screen.dart';
import '../../widgets/app_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class ReportDetailsScreen extends StatefulWidget {
  final UserReport report;

  const ReportDetailsScreen({super.key, required this.report});

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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

  String _formatTime(DateTime dateTime) {
    String hour = dateTime.hour > 12 ? '${dateTime.hour - 12}' : (dateTime.hour == 0 ? '12' : '${dateTime.hour}');
    String minute = dateTime.minute.toString().padLeft(2, '0');
    String amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;
    final userProfile = appState.users.firstWhere(
      (u) => u.id == widget.report.userId,
      orElse: () => UserProfile(id: '', trustScore: 50),
    );

    int trustLevel = 3;
    if (userProfile.trustScore >= 80) {
      trustLevel = 5;
    } else if (userProfile.trustScore >= 60) trustLevel = 4;
    else if (userProfile.trustScore >= 40) trustLevel = 3;
    else if (userProfile.trustScore >= 20) trustLevel = 2;
    else trustLevel = 1;

    final roadName = widget.report.roadId != null
        ? appState.roads.firstWhere((r) => r.id == widget.report.roadId, orElse: () => RoadStatus(id: '', name: 'Unknown Road', status: '', notes: '', updatedAt: DateTime.now())).name
        : 'Unknown Location';

    final parts = widget.report.title.split(':');
    final incidentType = parts.length > 1 ? parts[0].trim() : widget.report.title;

    Color severityColor = AppColors.primary;
    if (widget.report.severity == 'High') severityColor = AppColors.tertiary;
    if (widget.report.severity == 'Medium') severityColor = AppColors.primary;
    if (widget.report.severity == 'Low') severityColor = AppColors.secondary;

    String distanceString = 'Unknown distance';
    if (widget.report.location != null && widget.report.roadId != null) {
      try {
        final road = appState.roads.firstWhere((r) => r.id == widget.report.roadId);
        if (road.geometry != null && road.geometry!['coordinates'] != null) {
          final coords = road.geometry!['coordinates'] as List<dynamic>;
          double minDistance = double.infinity;
          
          for (var coord in coords) {
            if (coord is List && coord.length >= 2) {
              double rLng = (coord[0] as num).toDouble();
              double rLat = (coord[1] as num).toDouble();
              double userLat = (widget.report.location!['lat'] as num).toDouble();
              double userLng = (widget.report.location!['lng'] as num).toDouble();
              
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

    final breakdown = appState.getLiveConfidenceBreakdown(widget.report);
    double liveConfidence = breakdown['total'] as double;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface.withValues(alpha: 0.9),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Report Details',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Reporter Trust Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                            ),
                            child: Center(
                              child: Text(
                                'AU',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'REPORTER IDENTITY',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Community Reporter',
                                style: GoogleFonts.manrope(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Trust Score',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${userProfile.trustScore}%',
                                  style: GoogleFonts.manrope(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 8,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: userProfile.trustScore / 100.0,
                                child: AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: _pulseAnimation.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.secondaryFixed,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified, size: 16, color: AppColors.secondaryFixed),
                            const SizedBox(width: 8),
                            Text(
                              'LEVEL $trustLevel TRUST',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Primary Status Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: severityColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 14, color: severityColor),
                                const SizedBox(width: 6),
                                Text(
                                  '${widget.report.severity.toUpperCase()} PRIORITY',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: severityColor,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Reported ${_getTimeAgo(widget.report.createdAt)} • ${_formatTime(widget.report.createdAt)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        incidentType,
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 20, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              roadName,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'VERIFIED BY USER',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.outline,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '"${widget.report.description}"',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: AppColors.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'GEOFENCE MAP PREVIEW',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.outline,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            IgnorePointer(
                              child: AppMap(
                                onMapCreatedCallback: (mapboxMap) {
                                  if (widget.report.location != null) {
                                    double lat = (widget.report.location!['lat'] as num).toDouble();
                                    double lng = (widget.report.location!['lng'] as num).toDouble();
                                    mapboxMap.flyTo(
                                      mapbox.CameraOptions(
                                        center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
                                        zoom: 16.0,
                                      ),
                                      mapbox.MapAnimationOptions(duration: 0),
                                    );
                                  }
                                }
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.gps_fixed, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      distanceString,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Evidence Section
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_library, color: AppColors.outline),
                            const SizedBox(width: 12),
                            Text(
                              'Evidence Image',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              (widget.report.imageUrl != null && widget.report.imageUrl!.isNotEmpty) ? 'ATTACHED' : 'NO IMAGE',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: (widget.report.imageUrl != null && widget.report.imageUrl!.isNotEmpty) ? AppColors.primary : AppColors.outline,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (widget.report.imageUrl != null && widget.report.imageUrl!.isNotEmpty)
                            ? Image.network(
                                widget.report.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: AppColors.surfaceContainerHigh,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image, size: 48, color: AppColors.outlineVariant),
                                          const SizedBox(height: 8),
                                          Text('Image failed to load', style: GoogleFonts.inter(fontSize: 12, color: AppColors.outlineVariant)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: AppColors.surfaceContainerHigh,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: AppColors.surfaceContainerHigh,
                                child: const Center(
                                  child: Icon(Icons.image_not_supported, size: 48, color: AppColors.outlineVariant),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Admin Diagnostics
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.admin_panel_settings, size: 18, color: AppColors.tertiary),
                          const SizedBox(width: 8),
                          Text(
                            'ADMIN DIAGNOSTICS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.tertiary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Live Confidence Score', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                          Text('${liveConfidence.toStringAsFixed(1)}%', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.tertiary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Breakdown bars
                      _buildConfidenceBar('Authority Contribution', breakdown['authorityContribution'], 50.0),
                      const SizedBox(height: 12),
                      _buildConfidenceBar('Consensus (x${(breakdown['weatherMultiplier'] as double).toStringAsFixed(2)})', breakdown['consensusContribution'], 30.0),
                      const SizedBox(height: 12),
                      _buildConfidenceBar('Recency', breakdown['recencyContribution'], 20.0),
                      
                      if ((breakdown['proximity'] as double) != 0.0) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Proximity Bonus/Penalty', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                            Text(
                              '${(breakdown['proximity'] as double) > 0 ? '+' : ''}${(breakdown['proximity'] as double).toStringAsFixed(1)}',
                              style: GoogleFonts.inter(
                                fontSize: 12, 
                                fontWeight: FontWeight.w700, 
                                color: (breakdown['proximity'] as double) > 0 ? AppColors.secondary : AppColors.notPassable,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Fixed Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                border: Border(top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () {
                        appState.dismissReport(widget.report.id);
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                        backgroundColor: AppColors.surfaceContainerLowest,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.flag, size: 20, color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            'Flag False',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        String suggestedStatus = 'passable';
                        if (widget.report.severity == 'Medium') suggestedStatus = 'partial';
                        if (widget.report.severity == 'High') suggestedStatus = 'not_passable';

                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UpdateRoadStatusScreen(
                              prefilledRoadId: widget.report.roadId,
                              reportIdToVerify: widget.report.id,
                              suggestedStatus: suggestedStatus,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.task_alt, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Verify & Update',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBar(String label, double value, double max) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
            Text('${value.toStringAsFixed(1)} / ${max.toInt()}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
          backgroundColor: AppColors.tertiary.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.tertiary.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(4),
          minHeight: 6,
        ),
      ],
    );
  }
}
