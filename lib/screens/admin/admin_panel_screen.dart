import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import 'broadcast_alert_screen.dart';
import 'update_road_status_screen.dart';
import 'user_reports_screen.dart';
import '../../widgets/app_map.dart';
import '../shared/full_screen_map_screen.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final floodedCount = appState.roads.where((r) => r.status == 'not_passable').length;
        final activeCount = appState.reports.where((r) => r.status == 'pending').length;
        final resolvedCount = appState.reports.where((r) => r.status == 'verified').length;

        final displayReports = appState.reports.where((r) => r.status != 'dismissed').take(3).toList();

        return Scaffold(
          appBar: const AppTopBar(),
          backgroundColor: AppColors.surface,
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'COMMAND CENTER',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Barangay Central\nDashboard',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.edit_road,
                        label: 'Update Road\nStatus',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UpdateRoadStatusScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.campaign,
                        label: 'Broadcast\nAlert',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BroadcastAlertScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stats grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: [
                    _StatCard(
                      icon: Icons.flood,
                      iconColor: AppColors.tertiary,
                      label: 'Flooded Roads',
                      value: floodedCount.toString(),
                    ),
                    _StatCard(
                      icon: Icons.analytics,
                      iconColor: AppColors.primary,
                      label: 'Active Reports',
                      value: activeCount.toString(),
                    ),
                    _StatCard(
                      icon: Icons.check_circle,
                      iconColor: AppColors.secondary,
                      label: 'Resolved Today',
                      value: resolvedCount.toString(),
                    ),
                    _StatCard(
                      icon: Icons.groups,
                      iconColor: AppColors.onSurfaceVariant,
                      label: 'Volunteers Active',
                      value: '8',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Interactive route monitor
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Interactive Route Monitor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'LIVE MAP',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Map area
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FullScreenMapScreen(),
                      ),
                    );
                  },
                  child: Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: AppColors.surfaceContainer,
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Map illustration
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: const AppMap(),
                        ),

                        // Floating Full Screen Button
                        Positioned(
                          top: 16,
                          right: 16,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FullScreenMapScreen(),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: AppColors.outlineVariant.withValues(alpha: 0.15),
                                ),
                              ),
                              child: const Icon(
                                Icons.fullscreen_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),

                      // Legend
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MAP LEGEND',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LegendRow(
                                  color: AppColors.tertiary,
                                  label: 'Flooded / Blocked'),
                              const SizedBox(height: 8),
                              _LegendRow(
                                  color: AppColors.primary,
                                  label: 'Clear / Open'),
                              const SizedBox(height: 8),
                              _LegendRow(
                                  color: AppColors.secondaryFixedDim,
                                  label: 'Verified Safe Path'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

                const SizedBox(height: 24),

                // User reports section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'User Reports',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const UserReportsScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'View All',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Dynamic Report cards
                if (displayReports.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No reports to display',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                else
                  ...displayReports.map((report) {
                    final isPending = report.status == 'pending';
                    final isVerified = report.status == 'verified';

                    IconData icon = Icons.info_outline;
                    Color iconColor = AppColors.primary;
                    if (report.severity == 'High') {
                      icon = Icons.warning_rounded;
                      iconColor = AppColors.tertiary;
                    } else if (report.severity == 'Medium') {
                      icon = Icons.cloud_upload;
                      iconColor = AppColors.primary;
                    } else if (report.severity == 'Low') {
                      icon = Icons.verified;
                      iconColor = AppColors.secondary;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UserReportCard(
                        icon: icon,
                        iconColor: iconColor,
                        title: report.title,
                        time: _getTimeAgo(report.createdAt),
                        description: report.description,
                        showActions: isPending,
                        isVerified: isVerified,
                        onVerify: () => appState.resolveReport(report.id),
                        onDismiss: () => appState.dismissReport(report.id),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onHover: (val) => setState(() => _isHovered = val),
      onHighlightChanged: (val) => setState(() => _isHovered = val),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: _isHovered
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                )
              : null,
          color: _isHovered ? null : AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 20,
              color: _isHovered ? Colors.white : AppColors.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _isHovered ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          color: AppColors.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 24, color: iconColor),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.manrope(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ],
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
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _UserReportCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String time;
  final String description;
  final bool showActions;
  final bool isVerified;
  final VoidCallback? onVerify;
  final VoidCallback? onDismiss;

  const _UserReportCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.time,
    required this.description,
    required this.showActions,
    this.isVerified = false,
    this.onVerify,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (showActions)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (onVerify != null) onVerify!();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report verified and marked resolved.'),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Verify & Clear',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (onDismiss != null) onDismiss!();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report dismissed.')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Dismiss',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (isVerified)
            Row(
              children: [
                Icon(Icons.done_all, size: 16, color: AppColors.secondary),
                const SizedBox(width: 4),
                Text(
                  'Verified by Admin',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AdminMapPainter extends CustomPainter {
  final List<RoadStatus> roads;
  _AdminMapPainter(this.roads);

  @override
  void paint(Canvas canvas, Size size) {
    // Grid background
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Color getColor(String roadId, Color defaultColor) {
      final road = roads.firstWhere(
        (r) => r.id == roadId,
        orElse: () => RoadStatus(id: '', name: '', status: '', notes: '', updatedAt: DateTime.now()),
      );
      if (road.status == 'passable') return AppColors.secondaryFixedDim;
      if (road.status == 'partial') return AppColors.partial;
      if (road.status == 'not_passable') return AppColors.tertiary;
      return defaultColor;
    }

    // Flooded / Blocked road (represented by pio_valenzuela road status)
    final pioColor = getColor('pio_valenzuela', AppColors.tertiary);
    final redPaint = Paint()
      ..color = pioColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.33),
      Offset(size.width * 0.5, size.height * 0.33),
      redPaint,
    );

    // Clear road (represented by sampaguita)
    final sampaguitaColor = getColor('sampaguita', AppColors.primary);
    final bluePaint = Paint()
      ..color = sampaguitaColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.4, size.height * 0.5),
      Offset(size.width * 0.7, size.height * 0.5),
      bluePaint,
    );

    // Safe path (represented by ems_barrio)
    final emsColor = getColor('ems_barrio', AppColors.secondaryFixedDim);
    final greenPaint = Paint()
      ..color = emsColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.7),
      Offset(size.width * 0.6, size.height * 0.7),
      greenPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AdminMapPainter oldDelegate) {
    return oldDelegate.roads != roads;
  }
}