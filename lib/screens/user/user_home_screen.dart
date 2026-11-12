import '../../widgets/home_alert_banner.dart';
import 'communication_update_screen.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/geo_utils.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_service.dart';
import '../../services/location_service.dart';
import '../../services/account_security.dart';
import '../../utils/location_fix.dart';
import '../../widgets/report_verified_celebration_dialog.dart';
import 'map_dashboard_screen.dart';
import 'route_planner_screen.dart';
import 'notifications_screen.dart';
import 'report_history_screen.dart';
import 'report_update_screen.dart';
import '../shared/feedback_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _currentIndex = 0;
  bool _reportsOpened = false;
  bool _mapRoadSelected = false;
  late final int _notificationTapOwner;
  bool _isLoading = true;
  final GlobalKey<MapDashboardScreenState> _mapDashboardKey =
      GlobalKey<MapDashboardScreenState>();
  StreamSubscription<Position>? _positionStream;
  Position? _lastProximityCheck;
  final Set<String> _promptedRoads = {};

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapDashboardScreen(
        key: _mapDashboardKey,
        onRoadSelectionChanged: (selected) {
          if (mounted && _mapRoadSelected != selected) {
            setState(() => _mapRoadSelected = selected);
          }
        },
      ),
      const RoutePlannerScreen(),
      const NotificationsScreen(),
    ];

    // Register notification tap handler with payload-aware deep routing
    _notificationTapOwner = NotificationService.instance.setOnNotificationTap((
      data,
    ) {
      if (!mounted) return;
      final type = data?['type'];
      if (type == 'feedback_update' || type == 'broadcast_update') {
        final kind = type == 'feedback_update' ? 'feedback' : 'broadcast',
            field = type == 'feedback_update' ? 'feedbackId' : 'alertId';
        if (data?[field] is String)
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CommunicationUpdateScreen(
                kind: kind,
                id: data![field] as String,
              ),
            ),
          );
      } else if (type == 'report_update' &&
          data?['reportId'] is String &&
          RegExp(
            r'^[A-Za-z0-9_-]{1,128}$',
          ).hasMatch(data!['reportId'] as String)) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ReportUpdateScreen(reportId: data['reportId'] as String),
          ),
        );
      } else if (type == 'report_verified' ||
          type == 'report_reply' ||
          type == 'report_dismissed' ||
          type == 'report_under_review') {
        setState(() {
          _currentIndex = 3;
          _reportsOpened = true;
        });
      } else if (type == 'feedback_resolved') {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const FeedbackScreen()));
      } else {
        setState(() => _currentIndex = 2);
        AppStateService.instance.markAlertsSeen();
      }
    });

    AppStateService.instance
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() => _isLoading = false);
            _startProximityListener();
            _checkVerifiedReportsCelebration();
          }
        })
        .catchError((Object error) {
          if (mounted) setState(() => _isLoading = false);
          AppStateService.instance.retrySync();
        });

    AppStateService.instance.addListener(_onAppStateUpdated);
  }

  void _onAppStateUpdated() {
    if (mounted) {
      _checkVerifiedReportsCelebration();
    }
  }

  Future<void> _checkVerifiedReportsCelebration() async {
    try {
      final uid = await UserService.getUserId();
      final appState = AppStateService.instance;
      final prefs = await SharedPreferences.getInstance();
      final ackList = prefs.getStringList('ack_celebrated_reports') ?? [];

      for (var report in appState.reports) {
        if (report.userId == uid &&
            report.status == 'verified' &&
            !ackList.contains(report.id)) {
          ackList.add(report.id);
          await prefs.setStringList('ack_celebrated_reports', ackList);

          final matchingRoads = appState.roads.where(
            (r) => r.id == report.roadId,
          );
          final roadName = matchingRoads.isNotEmpty
              ? matchingRoads.first.name
              : 'Monitored Barangay Road';

          if (mounted) {
            ReportVerifiedCelebrationDialog.showIfEligible(
              context,
              report,
              roadName,
            );
          }
          break; // Pop one celebration at a time
        }
      }
    } catch (e) {
      debugPrint('[Celebration] Error checking verified reports: $e');
    }
  }

  @override
  void dispose() {
    NotificationService.instance.clearOnNotificationTap(_notificationTapOwner);
    AppStateService.instance.removeListener(_onAppStateUpdated);
    _positionStream?.cancel();
    super.dispose();
  }

  void _startProximityListener() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever)
      return;

    if (!mounted) return;
    _positionStream = LocationService.getPositionStream().listen(
      (Position position) {
        _checkProximityToStaleRoads(position);
      },
      onError: (e) {
        debugPrint('[UserHomeScreen] Location stream error: $e');
      },
    );
  }

  void _checkProximityToStaleRoads(Position position) {
    if (!mounted) return;
    final appState = AppStateService.instance;

    // Only prompt if they are on the map screen
    if (!mounted || _currentIndex != 0 || SessionActivity.navigating) return;
    if (!usableLocationFix(position, now: DateTime.now())) return;
    final previous = _lastProximityCheck;
    if (previous != null &&
        Geolocator.distanceBetween(
              previous.latitude,
              previous.longitude,
              position.latitude,
              position.longitude,
            ) <
            100)
      return;
    _lastProximityCheck = position;

    RoadStatus? closestRoad;
    double closestDistance = double.infinity;

    for (var road in appState.roads) {
      // Use effective status (includes predictive risk during storms)
      final weatherState = SimulatedWeatherService.instance.currentState;
      final effectiveStatus = road.getEffectiveStatus(weatherState);

      // Prompt for ANY road that is not passable (including predicted-risk roads)
      if (effectiveStatus == 'passable') continue;
      if (_promptedRoads.contains(road.id)) continue;

      if (road.geometry != null) {
        final geoPts = GeoUtils.extractPoints(road.geometry);
        if (geoPts.isEmpty) continue;

        double minDistanceForRoad = double.infinity;
        for (int i = 0; i < geoPts.length; i++) {
          final p = geoPts[i];
          final dist = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            p.lat,
            p.lng,
          );
          if (dist < minDistanceForRoad) minDistanceForRoad = dist;

          if (i < geoPts.length - 1) {
            final pNext = geoPts[i + 1];
            final segDist = GeoUtils.pointToSegmentDistanceMeters(
              position.longitude,
              position.latitude,
              p.lng,
              p.lat,
              pNext.lng,
              pNext.lat,
            );
            if (segDist < minDistanceForRoad) minDistanceForRoad = segDist;
          }
        }

        if (minDistanceForRoad <= 500 && minDistanceForRoad < closestDistance) {
          closestDistance = minDistanceForRoad;
          closestRoad = road;
        }
      }
    }

    if (closestRoad != null) {
      _promptedRoads.add(closestRoad.id);
      _showAccuracyPrompt(closestRoad);
    }
  }

  void _showAccuracyPrompt(RoadStatus road) {
    bool isInteracted = false;
    Timer? autoDismissTimer;

    final duration = DateTime.now().difference(road.updatedAt);
    String timeAgo;
    if (duration.inMinutes < 2) {
      timeAgo = 'just now';
    } else if (duration.inMinutes < 60) {
      timeAgo = '${duration.inMinutes} minutes ago';
    } else if (duration.inHours == 1) {
      timeAgo = '1 hour ago';
    } else {
      timeAgo = '${duration.inHours} hours ago';
    }

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        autoDismissTimer ??= Timer(const Duration(seconds: 15), () {
          if (!isInteracted && mounted) {
            Navigator.of(context).pop();
          }
        });

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: AppPalette.of(context).primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'PROXIMITY DETECTED'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppPalette.of(context).primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'You are near ${road.name}',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This road was reported as flooded $timeAgo. Is this still accurate?',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _PromptButton(
                      label: tr(context, "No, it's clear"),
                      icon: Icons.check_circle_outline,
                      color: AppPalette.of(context).secondary,
                      onTap: () async {
                        isInteracted = true;
                        autoDismissTimer?.cancel();
                        if (context.mounted) Navigator.pop(context);
                        try {
                          await AppStateService.instance.submitReport(
                            'Road Cleared: ${road.name}',
                            'Automated proximity response: user reported road is clear.',
                            'Low',
                            road.id,
                            null,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(context, 'Thank you for the update!'),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!e.toString().contains('SPAM_COOLDOWN')) rethrow;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PromptButton(
                      label: tr(context, "Yes, still flooded"),
                      icon: Icons.water_drop_outlined,
                      color: AppPalette.of(context).tertiary,
                      onTap: () async {
                        isInteracted = true;
                        autoDismissTimer?.cancel();
                        if (context.mounted) Navigator.pop(context);
                        String currentSeverity = road.status == 'not_passable'
                            ? 'High'
                            : 'Medium';
                        try {
                          await AppStateService.instance.submitReport(
                            'Ongoing Flood: ${road.name}',
                            'Automated proximity response: user verified flood is still present.',
                            currentSeverity,
                            road.id,
                            null,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(context, 'Thank you for the update!'),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!e.toString().contains('SPAM_COOLDOWN')) rethrow;
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    isInteracted = true;
                    autoDismissTimer?.cancel();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(
                    tr(context, "I'm not sure"),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.of(context).onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final appState = AppStateService.instance;

    return PopScope(
      canPop: _currentIndex == 0 && !_mapRoadSelected,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex == 0 && _mapRoadSelected) {
          _mapDashboardKey.currentState?.clearRoadSelection();
          return;
        }
        if (_currentIndex > 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        extendBody: _currentIndex == 0,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_currentIndex < 2)
                ListenableBuilder(
                  listenable: appState,
                  builder: (context, _) {
                    if (appState.unreadAlertCount == 0 ||
                        appState.alerts.isEmpty)
                      return const SizedBox.shrink();
                    final alert = appState.alerts.first;
                    return HomeAlertBanner(
                      title: alert.title,
                      severity: alert.severity,
                      roadName: alert.roadName,
                      onOpen: () {
                        setState(() => _currentIndex = 2);
                        appState.markAlertsSeen();
                      },
                      onDismiss: appState.markAlertsSeen,
                    );
                  },
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    ..._screens,
                    if (_reportsOpened)
                      const ReportHistoryScreen(embedded: true)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: IgnorePointer(
          ignoring: _currentIndex == 0 && _mapRoadSelected,
          child: ExcludeSemantics(
            excluding: _currentIndex == 0 && _mapRoadSelected,
            child: AnimatedSlide(
              offset: _currentIndex == 0 && _mapRoadSelected
                  ? const Offset(0, 1.3)
                  : Offset.zero,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              child: BottomNavBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                    if (index == 3) _reportsOpened = true;
                  });
                  if (index == 2) {
                    AppStateService.instance.markAlertsSeen();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PromptButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
