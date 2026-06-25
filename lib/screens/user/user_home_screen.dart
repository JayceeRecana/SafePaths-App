import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../config/risk_config.dart';
import 'map_dashboard_screen.dart';
import 'route_planner_screen.dart';
import 'notifications_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;
  final GlobalKey<MapDashboardScreenState> _mapDashboardKey = GlobalKey<MapDashboardScreenState>();
  StreamSubscription<Position>? _positionStream;
  final Set<String> _promptedRoads = {};

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapDashboardScreen(key: _mapDashboardKey),
      const RoutePlannerScreen(),
      const NotificationsScreen(),
    ];
    AppStateService.instance.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _startProximityListener();
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _startProximityListener() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100, // Trigger every 100 meters
      ),
    ).listen((Position position) {
      _checkProximityToStaleRoads(position);
    });
  }

  void _checkProximityToStaleRoads(Position position) {
    if (!mounted) return;
    final appState = AppStateService.instance;
    
    // Only prompt if they are on the map screen
    if (_currentIndex != 0) return;

    RoadStatus? closestRoad;
    double closestDistance = double.infinity;

    for (var road in appState.roads) {
      // Use effective status (includes predictive risk during storms)
      final weatherState = SimulatedWeatherService.instance.currentState;
      final effectiveStatus = road.getEffectiveStatus(weatherState);
      
      // Prompt for ANY road that is not passable (including predicted-risk roads)
      if (effectiveStatus == 'passable') continue;
      
      // Check staleness (dynamic based on weather)
      double staleThresholdHours = 2.0; // default 2 hours
      if (weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon) {
        staleThresholdHours = 0.5; // 30 minutes
      }

      final hoursOld = DateTime.now().difference(road.updatedAt).inMinutes / 60.0;
      if (hoursOld < staleThresholdHours) continue;

      if (_promptedRoads.contains(road.id)) continue;
      
      if (road.geometry != null && road.geometry!['coordinates'] != null) {
        final coords = road.geometry!['coordinates'] as List<dynamic>;
        double minDistanceForRoad = double.infinity;
        
        for (var coord in coords) {
          double? rLng, rLat;
          if (coord is Map) {
            rLng = (coord['lon'] as num?)?.toDouble();
            rLat = (coord['lat'] as num?)?.toDouble();
          } else if (coord is List && coord.length >= 2) {
            rLng = (coord[0] as num?)?.toDouble();
            rLat = (coord[1] as num?)?.toDouble();
          }
          if (rLng == null || rLat == null) continue;
            
          double dist = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            rLat,
            rLng,
          );
          if (dist < minDistanceForRoad) minDistanceForRoad = dist;
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
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'PROXIMITY DETECTED',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.primary,
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
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This road was reported as flooded over 2 hours ago. Is this still accurate?',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _PromptButton(
                      label: "No, it's clear",
                      icon: Icons.check_circle_outline,
                      color: AppColors.secondary,
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
                              const SnackBar(content: Text('Thank you for the update!')),
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
                      label: "Yes, still flooded",
                      icon: Icons.water_drop_outlined,
                      color: AppColors.tertiary,
                      onTap: () async {
                        isInteracted = true;
                        autoDismissTimer?.cancel();
                        if (context.mounted) Navigator.pop(context);
                        String currentSeverity = road.status == 'not_passable' ? 'High' : 'Medium';
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
                              const SnackBar(content: Text('Thank you for the update!')),
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
                    "I'm not sure",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
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
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PromptButton({required this.label, required this.icon, required this.color, required this.onTap});

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
