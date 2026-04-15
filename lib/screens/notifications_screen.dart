import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../widgets/app_top_bar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_NotificationItemData> _notifications = [
    _NotificationItemData(
      icon: Icons.warning_rounded,
      iconColor: AppColors.tertiary,
      iconBgColor: AppColors.tertiary.withValues(alpha: 0.1),
      category: 'EMERGENCY',
      categoryColor: AppColors.tertiary,
      time: '2 MINS AGO',
      title: 'Passability Change',
      description:
          'Alert: McArthur Hwy is now Not Passable (Flooded). Please seek alternative routes immediately.',
    ),
    _NotificationItemData(
      icon: Icons.thunderstorm_rounded,
      iconColor: AppColors.primary,
      iconBgColor: AppColors.primary.withValues(alpha: 0.1),
      category: 'WEATHER UPDATE',
      categoryColor: AppColors.primary,
      time: '45 MINS AGO',
      title: 'Heavy Rain Forecast',
      description:
          'Intense precipitation expected in Northern Sector within 30 minutes. Visibility may be reduced.',
    ),
    _NotificationItemData(
      icon: Icons.emergency_rounded,
      iconColor: AppColors.tertiary,
      iconBgColor: AppColors.tertiary.withValues(alpha: 0.1),
      category: 'EMERGENCY',
      categoryColor: AppColors.tertiary,
      time: '2 HOURS AGO',
      title: 'Evacuation Route Update',
      description:
          'Zone B primary exit is now active. Follow the green markers for the safest path to Shelter Alpha.',
    ),
    _NotificationItemData(
      icon: Icons.storage_rounded,
      iconColor: Colors.grey.shade500,
      iconBgColor: Colors.grey.shade100,
      category: 'SYSTEM',
      categoryColor: Colors.grey.shade500,
      time: '4 HOURS AGO',
      title: 'Map Data Updated',
      description:
          'Offline maps for your current region have been synchronized with the latest satellite terrain data.',
    ),
    _NotificationItemData(
      icon: Icons.waves_rounded,
      iconColor: AppColors.primary,
      iconBgColor: AppColors.primary.withValues(alpha: 0.1),
      category: 'WEATHER UPDATE',
      categoryColor: AppColors.primary,
      time: 'YESTERDAY',
      title: 'Tidal Advisory',
      description:
          'High tide warning for coastal paths. All beach-level access routes are temporarily restricted.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIVE UPDATES',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3.0,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Alerts',
                          style: GoogleFonts.manrope(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.0,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(_notifications.clear);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All alerts cleared.')),
                      );
                    },
                    child: Text(
                      'Clear All',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Notification list
            if (_notifications.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'No active alerts right now.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              ..._notifications.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _NotificationCard(
                    icon: item.icon,
                    iconColor: item.iconColor,
                    iconBgColor: item.iconBgColor,
                    category: item.category,
                    categoryColor: item.categoryColor,
                    time: item.time,
                    title: item.title,
                    description: item.description,
                    onDismiss: () {
                      setState(() {
                        _notifications.removeAt(index);
                      });
                    },
                  ),
                );
              }),

            const SizedBox(height: 32),

            // Decorative map element
            Container(
              height: 192,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: Stack(
                  children: [
                    // Abstract map pattern
                    CustomPaint(
                      size: const Size(double.infinity, 192),
                      painter: _MapPatternPainter(),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.surface,
                            AppColors.surface.withValues(alpha: 0.0),
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
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String category;
  final Color categoryColor;
  final String time;
  final String title;
  final String description;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.category,
    required this.categoryColor,
    required this.time,
    required this.title,
    required this.description,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('$title-$time'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(32),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: iconColor),
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
                          category,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                            color: categoryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        time,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationItemData {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String category;
  final Color categoryColor;
  final String time;
  final String title;
  final String description;

  const _NotificationItemData({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.category,
    required this.categoryColor,
    required this.time,
    required this.title,
    required this.description,
  });
}

class _MapPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.outlineVariant.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Grid lines
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Curved roads
    final roadPaint = Paint()
      ..color = AppColors.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.3);
    path.cubicTo(
      size.width * 0.3, size.height * 0.5,
      size.width * 0.6, size.height * 0.2,
      size.width, size.height * 0.4,
    );
    canvas.drawPath(path, roadPaint);

    final path2 = Path();
    path2.moveTo(size.width * 0.2, 0);
    path2.cubicTo(
      size.width * 0.3, size.height * 0.4,
      size.width * 0.5, size.height * 0.6,
      size.width * 0.7, size.height,
    );
    canvas.drawPath(path2, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}