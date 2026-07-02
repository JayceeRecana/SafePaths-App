import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../theme/app_colors.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import 'report_submission_screen.dart';
import 'road_details_screen.dart';
import '../shared/settings_screen.dart';
import 'profile_screen.dart';
import '../../widgets/app_map.dart';
import '../../widgets/weather_map_overlay.dart';
import '../shared/full_screen_map_screen.dart';

class MapDashboardScreen extends StatefulWidget {
  const MapDashboardScreen({super.key});

  @override
  MapDashboardScreenState createState() => MapDashboardScreenState();
}

class MapDashboardScreenState extends State<MapDashboardScreen> {
  String? _selectedRoadId;
  MapboxMap? _mapboxMap;
  bool _isSearching = false;
  bool _isDetailsOpen = false;

  static final String _mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  void _onMapCreated(MapboxMap map) {
    _mapboxMap = map;
  }

  Future<void> _flyToMyLocation() async {
    if (_mapboxMap == null) return;
    try {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services disabled.')));
        return;
      }
      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.whileInUse || permission == geo.LocationPermission.always) {
        geo.Position? position = await geo.Geolocator.getLastKnownPosition();
        position ??= await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(position.longitude, position.latitude)),
            zoom: 17.0,
            padding: MbxEdgeInsets(
              top: MediaQuery.sizeOf(context).height * 0.2,
              left: 0,
              bottom: MediaQuery.sizeOf(context).height * 0.3,
              right: 0,
            ),
          ),
          MapAnimationOptions(duration: 1000),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    }
  }








  void _flyToRoad(RoadStatus road) {
    if (_mapboxMap == null || road.geometry == null) return;
    final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
    if (coordsDyn == null || coordsDyn.isEmpty) return;

    double? lon;
    double? lat;

    final middleIndex = coordsDyn.length ~/ 2;
    final middleCoord = coordsDyn[middleIndex];
    if (middleCoord is Map) {
      lon = (middleCoord['lon'] as num?)?.toDouble() ?? (middleCoord['lng'] as num?)?.toDouble();
      lat = (middleCoord['lat'] as num?)?.toDouble();
    } else if (middleCoord is List && middleCoord.length >= 2) {
      lon = (middleCoord[0] as num?)?.toDouble();
      lat = (middleCoord[1] as num?)?.toDouble();
    }

    if (lon != null && lat != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(lon, lat)),
          zoom: 17.5,
          pitch: 60.0,
          bearing: -15.0,
          padding: MbxEdgeInsets(
            top: 0,
            left: 0,
            bottom: MediaQuery.sizeOf(context).height * 0.4,
            right: 0,
          ),
        ),
        MapAnimationOptions(duration: 1500),
      );
    }
  }

  void _handleRoadTapped(String roadId, Position? tappedPosition) async {
    final appState = AppStateService.instance;
    final roadIndex = appState.roads.indexWhere((r) => r.id == roadId);
    if (roadIndex != -1) {
      if (tappedPosition != null) {
        _mapboxMap?.flyTo(
          CameraOptions(
            center: Point(coordinates: tappedPosition),
            zoom: 17.5,
            pitch: 60.0,
            bearing: -15.0,
            padding: MbxEdgeInsets(
              top: 0,
              left: 0,
              bottom: MediaQuery.sizeOf(context).height * 0.4,
              right: 0,
            ),
          ),
          MapAnimationOptions(duration: 1500),
        );
      } else {
        _flyToRoad(appState.roads[roadIndex]);
      }
    }
    
    setState(() {
      _selectedRoadId = roadId;
      _isDetailsOpen = true;
    });
    await Navigator.of(context).push(RoadDetailsScreen.route(roadId));
    if (mounted) setState(() => _isDetailsOpen = false);
  }

  Future<void> _searchAndHighlight(String query) async {
    final queryLower = query.trim().toLowerCase();
    if (queryLower.isEmpty) return;

    final appState = AppStateService.instance;
    
    // 1. Search locally in the monitored roads list
    RoadStatus? matchedRoad;
    for (final road in appState.roads) {
      if (road.name.toLowerCase().contains(queryLower)) {
        matchedRoad = road;
        break;
      }
    }

    if (matchedRoad != null) {
      _flyToRoad(matchedRoad);
      setState(() {
        _selectedRoadId = matchedRoad!.id;
        _isSearching = false;
        _isDetailsOpen = true;
      });
      // Open Road Details screen as a transparent overlay
      await Navigator.of(context).push(RoadDetailsScreen.route(matchedRoad!.id));
      if (mounted) setState(() => _isDetailsOpen = false);
      return;
    }

    // 2. Query Mapbox Geocoding API within Barangay Marulas bounding box
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
      '?access_token=$_mapboxToken'
      '&proximity=120.9842,14.6761'
      '&limit=1'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final firstPlace = features.first;
          final center = firstPlace['center'] as List?;
          final placeName = firstPlace['place_name'] as String?;
          if (center != null && center.length >= 2 && _mapboxMap != null) {
            final lon = (center[0] as num).toDouble();
            final lat = (center[1] as num).toDouble();

            _mapboxMap!.flyTo(
              CameraOptions(
                center: Point(coordinates: Position(lon, lat)),
                zoom: 16.0,
                pitch: 60.0,
                bearing: -15.0,
              ),
              MapAnimationOptions(duration: 1500),
            );

            setState(() {
              _isSearching = false;
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Showing result for: ${placeName ?? query}')),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No places found within Marulas.')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[MapDashboard] Geocoding error: $e');
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error: Could not connect to map service.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return ListenableBuilder(
      listenable: appState,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppMap(
              onMapCreatedCallback: _onMapCreated,
              onRoadTapped: _handleRoadTapped,
            ),
          ),
          const Positioned.fill(
            child: WeatherMapOverlay(),
          ),
        ],
      ),
      builder: (context, child) {
        RoadStatus? selectedRoad;
        Color statusColor = AppColors.passable;
        IconData statusIcon = Icons.verified_user;
        String statusLabel = 'Passable';
        Color statusBgColor = AppColors.secondary.withValues(alpha: 0.15);

        if (appState.roads.isNotEmpty) {
          _selectedRoadId ??= appState.roads.first.id;
          
          selectedRoad = appState.roads.firstWhere(
            (r) => r.id == _selectedRoadId,
            orElse: () => appState.roads.first,
          );

          final effectiveStatus = selectedRoad.getEffectiveStatus(SimulatedWeatherService.instance.currentState);

          if (effectiveStatus == 'partial') {
            statusColor = AppColors.partial;
            statusIcon = Icons.info;
            statusLabel = 'Partial Blockage';
            statusBgColor = AppColors.partial.withValues(alpha: 0.15);
          } else if (effectiveStatus == 'not_passable') {
            statusColor = AppColors.notPassable;
            statusIcon = Icons.warning;
            statusLabel = 'Not Passable';
            statusBgColor = AppColors.notPassable.withValues(alpha: 0.15);
          }
        }

        return Scaffold(
          body: SizedBox.expand(
            child: Stack(
              children: [
              // Cached heavy map and weather layers
              if (child != null) child,

              // Top header with search
              if (!_isDetailsOpen)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand row
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const ProfileScreen(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border:
                                          Border.all(color: Colors.white, width: 2),
                                      color: AppColors.primaryContainer,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.person,
                                        size: 18,
                                        color: AppColors.onPrimaryContainer),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'SafePaths',
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: AppColors.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SettingsScreen(),
                                      ),
                                    );
                                  },
                                  child: Icon(
                                    Icons.settings_outlined,
                                    size: 24,
                                    color: AppColors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Search & weather row
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.05),
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _isSearching
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceContainerLow
                                                .withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                                color: AppColors.primary,
                                                width: 1.5),
                                          ),
                                          child: Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () => setState(
                                                    () => _isSearching = false),
                                                child: const Icon(Icons.arrow_back,
                                                    size: 20,
                                                    color: AppColors.primary),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  autofocus: true,
                                                  textInputAction:
                                                      TextInputAction.search,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppColors.onSurface,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    hintText:
                                                        'Type road or area name...',
                                                    border: InputBorder.none,
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                            vertical: 6),
                                                  ),
                                                  onSubmitted: (value) {
                                                    if (value.trim().isNotEmpty) {
                                                      _searchAndHighlight(
                                                          value.trim());
                                                    }
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: () => setState(
                                              () => _isSearching = true),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceContainerLow
                                                  .withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.search,
                                                    size: 20,
                                                    color: AppColors.outline),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Search areas...',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppColors.outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                ValueListenableBuilder<WeatherState>(
                                  valueListenable: SimulatedWeatherService.instance.listenable,
                                  builder: (context, weatherState, _) {
                                    final weatherService = SimulatedWeatherService.instance;
                                    return GestureDetector(
                                      onTap: () => _showWeatherStatsBottomSheet(context, weatherService, weatherState),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: weatherService.getWeatherColor(weatherState).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(weatherService.getWeatherIcon(weatherState),
                                                size: 20, color: weatherService.getWeatherColor(weatherState)),
                                            const SizedBox(width: 4),
                                            Text(
                                              weatherService.isOverrideMode 
                                                  ? 'Drill: ${weatherService.getWeatherDescription(weatherState)}'
                                                  : 'Live: ${weatherService.getWeatherDescription(weatherState)}',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: weatherService.getWeatherColor(weatherState),
                                              ),
                                            ),
                                            if (weatherService.isDataStale) ...[
                                              const SizedBox(width: 6),
                                              const Icon(Icons.cloud_off, size: 14, color: AppColors.error),
                                            ],
                                            if (weatherState == WeatherState.heavyRain || weatherState == WeatherState.typhoon) ...[
                                              const SizedBox(width: 8),
                                              _BlinkingInfoIcon(
                                                color: weatherService.getWeatherColor(weatherState),
                                                onTap: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) {
                                                      final isTyphoon = weatherState == WeatherState.typhoon;
                                                      final color = weatherService.getWeatherColor(weatherState);
                                                      final title = isTyphoon ? 'TYPHOON ALERT' : 'HEAVY RAIN ALERT';
                                                      final sub = isTyphoon 
                                                        ? 'Roads may be impassable. Seek safe shelter immediately.'
                                                        : 'Flooding possible. Vulnerable roads may be auto-escalated.';

                                                      return Dialog(
                                                        backgroundColor: Colors.white,
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(24),
                                                          child: Column(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                isTyphoon ? Icons.cyclone_rounded : Icons.thunderstorm_outlined,
                                                                size: 48,
                                                                color: color,
                                                              ),
                                                              const SizedBox(height: 16),
                                                              Text(
                                                                title,
                                                                style: GoogleFonts.inter(
                                                                  fontSize: 18,
                                                                  fontWeight: FontWeight.w800,
                                                                  letterSpacing: 1.2,
                                                                  color: AppColors.onSurface,
                                                                ),
                                                                textAlign: TextAlign.center,
                                                              ),
                                                              const SizedBox(height: 8),
                                                              Text(
                                                                sub,
                                                                style: GoogleFonts.inter(
                                                                  fontSize: 14,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: AppColors.onSurfaceVariant,
                                                                  height: 1.4,
                                                                ),
                                                                textAlign: TextAlign.center,
                                                              ),
                                                              const SizedBox(height: 24),
                                                              SizedBox(
                                                                width: double.infinity,
                                                                child: ElevatedButton(
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: color,
                                                                    foregroundColor: Colors.white,
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                                                    elevation: 0,
                                                                  ),
                                                                  onPressed: () => Navigator.of(context).pop(),
                                                                  child: Text(
                                                                    'OK',
                                                                    style: GoogleFonts.inter(
                                                                      fontSize: 14,
                                                                      fontWeight: FontWeight.bold,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ]
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Legend overlay
              if (!_isDetailsOpen)
                Positioned(
                  top: 200,
                  right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  width: 180,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      _LegendItem(
                        color: AppColors.passable,
                        label: 'PASSABLE',
                      ),
                      const SizedBox(height: 12),
                      _LegendItem(
                        color: AppColors.partial,
                        label: 'PARTIAL',
                      ),
                      const SizedBox(height: 12),
                      _LegendItem(
                        color: AppColors.notPassable,
                        label: 'NOT PASSABLE',
                      ),
                    ],
                  ),
                ),
              ),

              // Fullscreen FAB
                Positioned(
                  bottom: 226,
                  right: 24,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FullScreenMapScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.fullscreen_rounded,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

              // Locate Me FAB
                Positioned(
                  bottom: 298,
                  right: 24,
                  child: GestureDetector(
                    onTap: _flyToMyLocation,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.my_location,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

              // Emergency FAB (Only show when NOT route planning)
                Positioned(
                  bottom: 154,
                  right: 24,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportSubmissionScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_alert,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              // Dynamic Status card (Only show when NOT route planning)
              if (!_isDetailsOpen && appState.roads.isNotEmpty && selectedRoad != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () async {
                      setState(() => _isDetailsOpen = true);
                      await Navigator.of(context).push(RoadDetailsScreen.route(selectedRoad!.id));
                      if (mounted) setState(() => _isDetailsOpen = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedRoad.name,
                                  style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (selectedRoad.notes.isEmpty || selectedRoad.notes == 'Imported from OSM')
                                      ? 'No recent reports'
                                      : selectedRoad.notes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  statusIcon,
                                  size: 24,
                                  color: statusColor,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  statusLabel.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

            ],
          ),
        ),
      );
      },
    );
  }

  void _showWeatherStatsBottomSheet(BuildContext context, SimulatedWeatherService weatherService, WeatherState weatherState) {
    final weatherColor = weatherService.getWeatherColor(weatherState);
    final weatherIcon = weatherService.getWeatherIcon(weatherState);
    final weatherDesc = weatherService.getWeatherDescription(weatherState);
    final intensity = weatherService.precipitationIntensity;
    final wind = weatherService.windSpeed;
    final multiplier = weatherService.weatherMultiplier;
    final isOverride = weatherService.isOverrideMode;

    // Localized emergency guidelines based on weather
    String guidanceTitle;
    String guidanceText;
    IconData guidanceIcon;
    Color guidanceColor;

    if (weatherState == WeatherState.clear || weatherState == WeatherState.lightRain) {
      guidanceTitle = 'System Status: Normal';
      guidanceText = 'No severe weather detected. Standard routing algorithms are active without weather penalties.';
      guidanceIcon = Icons.check_circle_outline;
      guidanceColor = Colors.green;
    } else if (weatherState == WeatherState.moderateRain) {
      guidanceTitle = 'System Status: Elevated';
      guidanceText = 'Precipitation detected. Risk propagation model is actively monitoring network vulnerability.';
      guidanceIcon = Icons.warning_amber_rounded;
      guidanceColor = Colors.amber;
    } else {
      guidanceTitle = 'System Status: Critical';
      guidanceText = 'High risk weather active. SafePaths is actively penalizing flood-prone road edges and calculating detours.';
      guidanceIcon = Icons.gpp_bad_outlined;
      guidanceColor = Colors.red;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${weatherService.temperature.toStringAsFixed(1)}°',
                          style: GoogleFonts.manrope(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'C',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Icon(weatherIcon, color: weatherColor, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  weatherDesc,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Barangay Marulas',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOverride 
                            ? AppColors.errorContainer 
                            : AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOverride 
                              ? AppColors.notPassable.withValues(alpha: 0.3) 
                              : AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOverride ? Icons.science_outlined : Icons.sensors_outlined,
                            size: 16,
                            color: isOverride ? AppColors.notPassable : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isOverride 
                                  ? 'Simulation Active (Drill Mode)' 
                                  : 'Tomorrow.io Live Feed Active',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isOverride ? AppColors.notPassable : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: weatherService.getHourlyForecast().length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final hourData = weatherService.getHourlyForecast()[index];
                          final time = hourData['time'] as DateTime;
                          final temp = hourData['temperature'] as double;
                          final rainChance = hourData['rainChance'] as double;
                          final state = hourData['state'] as WeatherState;
                          final icon = weatherService.getWeatherIcon(state);
                          final color = weatherService.getWeatherColor(state);
                          
                          String hourStr = time.hour > 12 ? '${time.hour - 12}' : (time.hour == 0 ? '12' : '${time.hour}');
                          String amPm = time.hour >= 12 ? 'PM' : 'AM';
                          
                          return Container(
                            width: 60,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: index == 0 ? color.withValues(alpha: 0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: index == 0 ? color.withValues(alpha: 0.3) : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  index == 0 ? 'Now' : '$hourStr $amPm',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
                                    color: index == 0 ? color : AppColors.onSurfaceVariant,
                                  ),
                                ),
                                Icon(icon, color: color, size: 22),
                                Text(
                                  '${temp.toStringAsFixed(0)}°',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                Text(
                                  '${rainChance.toStringAsFixed(0)}%',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            icon: Icons.water_drop_outlined,
                            title: 'Rainfall Rate',
                            value: '${intensity.toStringAsFixed(1)} mm/h',
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            icon: Icons.air_outlined,
                            title: 'Wind Speed',
                            value: '${wind.toStringAsFixed(1)} m/s',
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.query_stats_outlined, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Predictive Risk Impact',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Risk Propagation Factor:',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: multiplier > 0.0 
                                      ? AppColors.errorContainer 
                                      : AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${multiplier.toStringAsFixed(1)}x',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: multiplier > 0.0 ? AppColors.notPassable : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            multiplier > 0.0 
                                ? 'Active weather adds a risk bonus to neighboring roads based on connectivity and vulnerability.'
                                : 'Clear weather does not propagate precipitation risk across Marulas networks.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: guidanceColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: guidanceColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(guidanceIcon, color: guidanceColor, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guidanceTitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: guidanceColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  guidanceText,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Dismiss',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingInfoIcon extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  
  const _BlinkingInfoIcon({required this.color, required this.onTap});

  @override
  State<_BlinkingInfoIcon> createState() => _BlinkingInfoIconState();
}

class _BlinkingInfoIconState extends State<_BlinkingInfoIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          return Opacity(
            opacity: 0.3 + (_ctrl.value * 0.7),
            child: Icon(Icons.info_outline, color: widget.color, size: 20),
          );
        }
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 4,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              color: AppColors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
