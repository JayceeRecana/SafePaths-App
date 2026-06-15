import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';

class RoutePlannerScreen extends StatelessWidget {
  const RoutePlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return Scaffold(
      appBar: const AppTopBar(),
      backgroundColor: AppColors.surface,
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          if (appState.roads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, size: 64, color: AppColors.outline),
                    const SizedBox(height: 16),
                    Text(
                      'No routes available.',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'There is currently no road data to plan a route.',
                      textAlign: TextAlign.center,
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

          final safestRoad = appState.roads.first;

          // Determine Safest Route status
          String safestRouteSubtitle = 'Avoids 3 flooded areas and heavy construction.';
          Color safestBorderColor = AppColors.secondary.withValues(alpha: 0.1);
          Color safestBgColor = AppColors.secondary.withValues(alpha: 0.05);
          Color safestTextColor = AppColors.onSecondaryContainer;
          IconData safestIcon = Icons.check_circle;

          if (safestRoad.status == 'partial') {
            safestRouteSubtitle = 'Caution: Partial flooding reported on this route.';
            safestBorderColor = AppColors.partial.withValues(alpha: 0.2);
            safestBgColor = AppColors.partial.withValues(alpha: 0.05);
            safestTextColor = AppColors.partial;
            safestIcon = Icons.info;
          } else if (safestRoad.status == 'not_passable') {
            safestRouteSubtitle = 'Warning: This route is currently not passable!';
            safestBorderColor = AppColors.notPassable.withValues(alpha: 0.2);
            safestBgColor = AppColors.notPassable.withValues(alpha: 0.05);
            safestTextColor = AppColors.notPassable;
            safestIcon = Icons.warning;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route input section
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dot connector
                          Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: Column(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Container(
                                  width: 1.5,
                                  height: 64,
                                  color: AppColors.outlineVariant,
                                ),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Input fields
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FROM',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Current Location',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.onSurface,
                                        ),
                                      ),
                                      const Icon(Icons.my_location,
                                          size: 16, color: AppColors.primary),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'TO',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Northside Medical Center',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Suggested routes header
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 350;
                    return isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Suggested Routes',
                                style: GoogleFonts.manrope(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppColors.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'LIVE UPDATES ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Suggested Routes',
                                  style: GoogleFonts.manrope(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: AppColors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                'LIVE UPDATES ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          );
                  },
                ),

                const SizedBox(height: 16),

                // Safest route card
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: safestBorderColor,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondaryContainer,
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified_user,
                                              size: 14,
                                              color:
                                                  AppColors.onSecondaryContainer),
                                          const SizedBox(width: 4),
                                          Text(
                                            'SAFEST ROUTE',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color:
                                                  AppColors.onSecondaryContainer,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      safestRoad.name,
                                      style: GoogleFonts.manrope(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '14 min',
                                      style: GoogleFonts.manrope(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                    Text(
                                      '4.2 miles',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: safestBgColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(safestIcon,
                                      size: 20, color: safestTextColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      safestRouteSubtitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: safestTextColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Map preview placeholder
                            Container(
                              height: 192,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFC5D8A8),
                                    Color(0xFFB8CCB0),
                                    Color(0xFFADC4A8),
                                  ],
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Route line illustration
                                  CustomPaint(
                                    size: const Size(double.infinity, 192),
                                    painter: _RoutePreviewPainter(safestRoad.status),
                                  ),
                                  Positioned(
                                    bottom: 12,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.08),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        safestRoad.status == 'passable'
                                            ? 'ELEVATED PATH'
                                            : 'FLOOD ALERT ACTIVE',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.0,
                                          color: safestRoad.status == 'passable'
                                              ? AppColors.onSurface
                                              : AppColors.notPassable,
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
                      // Start navigation button
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24)),
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryContainer,
                              ],
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      safestRoad.status == 'passable'
                                          ? 'Navigation started on ${safestRoad.name}.'
                                          : 'Warning: Starting navigation on a route with flood warnings.',
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Start Navigation',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.navigation,
                                        size: 20, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                ...appState.roads.skip(1).take(2).map((altRoad) {
                  String? riskLabel;
                  Color? riskColor;
                  String subtitle = 'Direct route, normal conditions.';
                  if (altRoad.status == 'partial') {
                    riskLabel = '1 WARNING';
                    riskColor = AppColors.partial;
                    subtitle = 'Moderate flooding reported.';
                  } else if (altRoad.status == 'not_passable') {
                    riskLabel = 'FLOODED';
                    riskColor = AppColors.notPassable;
                    subtitle = 'Avoid: Route is Not Passable.';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _AlternativeRouteCard(
                      name: altRoad.name,
                      riskLabel: riskLabel,
                      riskColor: riskColor,
                      subtitle: subtitle,
                      time: '11 min', // dynamic time placeholder
                      distance: '3.8 MI', // dynamic distance placeholder
                    ),
                  );
                }),

                const SizedBox(height: 24),

                // Safety context card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                        child: const Icon(Icons.shield,
                            color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guardian Mode Active',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Routes are being dynamically adjusted based on real-time emergency responder data and crowd-sourced safety reports.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AlternativeRouteCard extends StatelessWidget {
  final String name;
  final String? riskLabel;
  final Color? riskColor;
  final String subtitle;
  final String time;
  final String distance;

  const _AlternativeRouteCard({
    required this.name,
    this.riskLabel,
    this.riskColor,
    required this.subtitle,
    required this.time,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (riskLabel != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (riskColor ?? AppColors.error)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        riskLabel!,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: riskColor ?? AppColors.error,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    time,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                distance,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  final String status;
  _RoutePreviewPainter(this.status);

  @override
  void paint(Canvas canvas, Size size) {
    Color routeColor = AppColors.primary;
    if (status == 'partial') {
      routeColor = AppColors.partial;
    } else if (status == 'not_passable') {
      routeColor = AppColors.notPassable;
    }

    final paint = Paint()
      ..color = routeColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.1, size.height * 0.8);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.6,
      size.width * 0.4,
      size.height * 0.3,
      size.width * 0.6,
      size.height * 0.2,
    );
    path.cubicTo(
      size.width * 0.8,
      size.height * 0.1,
      size.width * 0.85,
      size.height * 0.4,
      size.width * 0.9,
      size.height * 0.3,
    );

    canvas.drawPath(path, paint);

    // Draw dots along the path
    final dotPaint = Paint()
      ..color = routeColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.8), 5, dotPaint);
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.3), 5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.status != status;
  }
}