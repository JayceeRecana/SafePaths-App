import 'dart:async';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../theme/app_colors.dart';
import '../../models/planned_route.dart';
import '../../widgets/app_map.dart';
import '../../services/app_state_service.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../services/weather_service.dart';
import '../../config/risk_config.dart';

class NavigationScreen extends StatefulWidget {
  final PlannedRoute route;

  const NavigationScreen({super.key, required this.route});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late PlannedRoute _currentRoute;
  int _currentStepIndex = 0;
  final FlutterTts flutterTts = FlutterTts();
  
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentLocation;
  bool _isReRouting = false;
  Timer? _stalenessTimer;
  Map<String, String> _roadStatusCache = {};

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.route;
    _initTts();
    _startLocationTracking();
    AppStateService.instance.addListener(_onAdminFloodUpdate);
    
    _stalenessTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkRouteStaleness();
    });
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
    _speakCurrentStep();
  }

  Future<void> _speakCurrentStep() async {
    if (_currentRoute.steps.isNotEmpty && _currentStepIndex < _currentRoute.steps.length) {
      final step = _currentRoute.steps[_currentStepIndex];
      // Speak the instruction, stripping out HTML if Mapbox includes it occasionally
      final textToSpeak = step.instruction.replaceAll(RegExp(r'<[^>]*>'), '');
      await flutterTts.speak(textToSpeak);
    }
  }

  void _nextStep() {
    if (_currentStepIndex < _currentRoute.steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      _speakCurrentStep();
    }
  }

  void _startLocationTracking() {
    _positionSubscription = LocationService.getPositionStream()?.listen((Position position) {
      if (!mounted || _isReRouting) return;
      
      setState(() {
        _currentLocation = position;
      });

      _checkAutoAdvance(position);
      _checkOffRoute(position);
    });
  }

  void _checkAutoAdvance(Position currentLoc) {
    if (_currentStepIndex >= _currentRoute.steps.length) return;
    
    final stepLoc = _currentRoute.steps[_currentStepIndex].location;
    final distance = geo.Geolocator.distanceBetween(
      currentLoc.lat.toDouble(), currentLoc.lng.toDouble(),
      stepLoc.lat.toDouble(), stepLoc.lng.toDouble()
    );

    // If within 20 meters of the turn/step, auto-advance
    if (distance < 20) {
      _nextStep();
    }
  }

  void _checkOffRoute(Position currentLoc) {
    if (_currentRoute.points.isEmpty) return;

    double minDistance = double.infinity;
    for (final pt in _currentRoute.points) {
      final d = geo.Geolocator.distanceBetween(
        currentLoc.lat.toDouble(), currentLoc.lng.toDouble(),
        pt.lat.toDouble(), pt.lng.toDouble()
      );
      if (d < minDistance) minDistance = d;
    }

    // If more than 50 meters away from the closest point on the route polyline, recalculate!
    if (minDistance > 50) {
      _triggerReRoute("Off route detected! Recalculating...");
    }
  }

  void _checkRouteStaleness() {
    if (!mounted || _isReRouting || _currentLocation == null) return;
    final weatherState = SimulatedWeatherService.instance.currentState;
    bool isSevereWeather = weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon;
    if (!isSevereWeather) return;

    final appState = AppStateService.instance;
    bool needsReRoute = false;

    for (final road in appState.roads) {
      double hoursOld = DateTime.now().difference(road.updatedAt).inMinutes / 60.0;
      bool isStaleData = hoursOld >= RiskConfig.getPassableStaleThresholdHours(road.vulnerability);
      if (road.status != 'passable' || !isStaleData) continue;
      if (road.geometry == null) continue;

      final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
      if (coordsDyn == null) continue;

      List<Position> roadPts = [];
      for (final c in coordsDyn) {
        double? roadLon, roadLat;
        if (c is Map) {
          roadLon = (c['lon'] as num?)?.toDouble();
          roadLat = (c['lat'] as num?)?.toDouble();
        } else if (c is List && c.length >= 2) {
          roadLon = (c[0] as num?)?.toDouble();
          roadLat = (c[1] as num?)?.toDouble();
        }
        if (roadLon != null && roadLat != null) {
          roadPts.add(Position(roadLon, roadLat));
        }
      }

      if (roadPts.length >= 2 && RoutingService.doesRouteCrossRoad(_currentRoute.points, roadPts, thresholdMeters: 30.0)) {
        needsReRoute = true;
        break;
      }
    }

    if (needsReRoute) {
      _triggerReRoute("Predictive Model Active: Re-evaluating safe routes due to stale road data.");
    }
  }

  void _onAdminFloodUpdate() {
    if (!mounted || _isReRouting || _currentLocation == null) return;
    
    final appState = AppStateService.instance;
    final weatherState = SimulatedWeatherService.instance.currentState;

    bool anyStatusChanged = false;
    for (final road in appState.roads) {
      final effStatus = road.getEffectiveStatus(weatherState);
      if (_roadStatusCache[road.id] != effStatus) {
        anyStatusChanged = true;
        _roadStatusCache[road.id] = effStatus;
      }
    }

    if (!anyStatusChanged) return;
    
    bool routeAffected = false;

    for (final road in appState.roads) {
      if (road.getEffectiveStatus(weatherState) == 'passable') continue;
      if (road.geometry == null) continue;

      final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
      if (coordsDyn == null) continue;

      List<Position> roadPts = [];
      for (final c in coordsDyn) {
        double? roadLon, roadLat;
        if (c is Map) {
          roadLon = (c['lon'] as num?)?.toDouble();
          roadLat = (c['lat'] as num?)?.toDouble();
        } else if (c is List && c.length >= 2) {
          roadLon = (c[0] as num?)?.toDouble();
          roadLat = (c[1] as num?)?.toDouble();
        }
        if (roadLon != null && roadLat != null) {
          roadPts.add(Position(roadLon, roadLat));
        }
      }

      if (roadPts.length >= 2 && RoutingService.doesRouteCrossRoad(_currentRoute.points, roadPts, thresholdMeters: 30.0)) {
        routeAffected = true;
        break;
      }
    }
    
    if (routeAffected) {
      _triggerReRoute("DANGER: Road conditions changed! Recalculating safe route...");
    }
  }

  Future<void> _triggerReRoute(String message) async {
    if (_isReRouting || _currentLocation == null) return;
    setState(() {
      _isReRouting = true;
    });

    flutterTts.speak(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );

    // Update the RoutingService origin to the live location and recalculate
    final routing = RoutingService.instance;
    routing.originPoint = _currentLocation;
    await routing.calculateRoute();

    if (!mounted) return;

    if (routing.routes.isNotEmpty) {
      final bestRoute = routing.routes.first;
      
      if (bestRoute.safetyStatus == 'flooded') {
        // Destination completely unreachable
        flutterTts.speak("Destination is blocked by floods. Please pull over safely.");
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Destination Unreachable', style: TextStyle(color: AppColors.error)),
            content: const Text('All paths to your destination are now blocked by impassable floods. For your safety, navigation has been halted.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close navigation
                },
                child: const Text('Exit Navigation'),
              )
            ],
          )
        );
      } else {
        // Successfully found a new safe route!
        setState(() {
          _currentRoute = bestRoute;
          _currentStepIndex = 0;
          _isReRouting = false;
        });
        flutterTts.speak("New safe route found. Continuing navigation.");
      }
    } else {
      // Failed to get routes from mapbox (e.g. no internet)
      setState(() {
        _isReRouting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t recalculate — check connection, proceed with caution.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    AppStateService.instance.removeListener(_onAdminFloodUpdate);
    _positionSubscription?.cancel();
    _stalenessTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = _currentRoute.steps.isNotEmpty && _currentStepIndex < _currentRoute.steps.length
        ? _currentRoute.steps[_currentStepIndex]
        : null;

    return Scaffold(
      body: Stack(
        children: [
          // 1. The Map
          AppMap(
            routePoints: _currentRoute.points,
          ),

          // 2. Top Maneuver Banner
          if (currentStep != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: _buildManeuverBanner(currentStep),
            ),

          // 3. Bottom Status Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomStatusBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildManeuverBanner(RouteStep step) {
    IconData maneuverIcon = Icons.directions;
    if (step.modifier.contains('left')) maneuverIcon = Icons.turn_left;
    if (step.modifier.contains('right')) maneuverIcon = Icons.turn_right;
    if (step.type.contains('arrive')) maneuverIcon = Icons.location_on;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(maneuverIcon, color: AppColors.onPrimaryContainer, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instruction,
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'In ${(step.distance).toStringAsFixed(0)} meters',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar(BuildContext context) {
    if (_isReRouting) {
      return Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 32,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(
              'Recalculating Route...',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_currentRoute.durationMin} min',
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  '${_currentRoute.distanceMiles} mi • ${_currentRoute.summary}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentStepIndex < _currentRoute.steps.length - 1)
                ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: AppColors.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Next',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.errorContainer,
                  foregroundColor: AppColors.onErrorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'End',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}