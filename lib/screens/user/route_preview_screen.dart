import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/planned_route.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_map.dart';
import 'navigation_screen.dart';

class RoutePreviewScreen extends StatelessWidget {
  final PlannedRoute route;

  const RoutePreviewScreen({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    int risks = route.avoidedRoads.length;

    return Scaffold(
      body: Stack(
        children: [
          // Full Screen Map
          AppMap(routePoints: route.points),
          
          // Gradient at top for better visibility of back button and card
          Positioned(
            top: 0, left: 0, right: 0, height: 160,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
                ),
              ),
            ),
          ),

          // Top Header (Unified Info Card)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.only(left: 8, right: 16, top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.safetyStatus == 'flooded' ? 'Destination Unreachable' : route.summary,
                          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: route.safetyStatus == 'flooded' ? AppColors.error : AppColors.onSurface),
                        ),
                        if (route.safetyStatus != 'flooded') ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${route.durationMin} min (${route.distanceMiles} mi)',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                              ),
                              if (risks > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.warning, color: AppColors.error, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$risks Hazards Avoided',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: AppColors.secondary, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Clear Route',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary),
                                    ),
                                  ],
                                )
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            'No safe paths available',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Start Navigation Floating Bar
          if (route.safetyStatus == 'flooded')
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(color: AppColors.error.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, color: AppColors.error, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Route Blocked by Flood',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'All available paths are currently impassable. Please wait for water levels to subside or select an alternative safe zone.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.error.withValues(alpha: 0.8), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 24,
              right: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close preview
                    Navigator.push(context, MaterialPageRoute(builder: (_) => NavigationScreen(route: route))); // Start navigation
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Start Navigation',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.navigation, color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
