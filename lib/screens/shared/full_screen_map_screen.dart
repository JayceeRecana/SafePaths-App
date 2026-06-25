import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_map.dart';

import '../../services/weather_service.dart';
import '../shared/settings_screen.dart';
import '../../services/app_state_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../user/road_details_screen.dart';
import '../../services/user_service.dart';

class FullScreenMapScreen extends StatefulWidget {
  const FullScreenMapScreen({super.key});

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  final GlobalKey<AppMapState> _mapStateKey = GlobalKey<AppMapState>();
  bool _isSearching = false;
  MapboxMap? _mapboxMap;
  bool _isDetailsOpen = false;

  void _flyToRoad(RoadStatus road) {
    if (_mapboxMap == null || road.geometry == null) return;
    final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
    if (coordsDyn == null || coordsDyn.isEmpty) return;

    double? lon;
    double? lat;

    final middleIndex = coordsDyn.length ~/ 2;
    final middleCoord = coordsDyn[middleIndex];
    if (middleCoord is Map) {
      lon = (middleCoord['lon'] as num?)?.toDouble();
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
      _isDetailsOpen = true;
    });
    await Navigator.of(context).push(RoadDetailsScreen.route(roadId));
    if (mounted) setState(() => _isDetailsOpen = false);
  }

  Future<void> _searchAndHighlight(String query) async {
    if (_mapboxMap == null) return;
    try {
      final appState = AppStateService.instance;
      final roads = appState.roads;
      final matchedRoad = roads.where((r) => r.name.toLowerCase().contains(query.toLowerCase())).firstOrNull;

      if (matchedRoad != null && matchedRoad.geometry != null) {
        final coordsDyn = matchedRoad.geometry!['coordinates'] as List<dynamic>?;
        if (coordsDyn != null && coordsDyn.isNotEmpty) {
          final middleIndex = coordsDyn.length ~/ 2;
          final middleCoord = coordsDyn[middleIndex];
          double? lon;
          double? lat;
          if (middleCoord is Map) {
            lon = (middleCoord['lon'] as num?)?.toDouble();
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
              ),
              MapAnimationOptions(duration: 1500),
            );
          }
        }
      } else {
        final role = await UserService.getUserRole();
        if (role == UserRole.admin) {
          // If admin, try to fetch the road from OSM dataset directly
          _mapStateKey.currentState?.fetchRoadGeometry(query);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find road: $query')));
        }
      }
    } catch (e) {
      debugPrint('[FullScreenSearch] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full Screen Map
          Positioned.fill(
            child: AppMap(
              key: _mapStateKey,
              showSearchButton: false,
              onMapCreatedCallback: (map) => _mapboxMap = map,
              onRoadTapped: _handleRoadTapped,
            ),
          ),

          // Unified Top Bar (Matches Dashboard exactly)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                color: AppColors.primaryContainer,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.arrow_back,
                                  size: 18, color: AppColors.onPrimaryContainer),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _isSearching
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLow.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.primary, width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () => setState(() => _isSearching = false),
                                          child: const Icon(Icons.arrow_back, size: 20, color: AppColors.primary),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            autofocus: true,
                                            textInputAction: TextInputAction.search,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.onSurface,
                                            ),
                                            decoration: const InputDecoration(
                                              hintText: 'Type road or area name...',
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(vertical: 6),
                                            ),
                                            onSubmitted: (value) {
                                              if (value.trim().isNotEmpty) {
                                                _searchAndHighlight(value.trim());
                                                setState(() => _isSearching = false);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () => setState(() => _isSearching = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.search, size: 20, color: AppColors.outline),
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
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                      weatherService.getWeatherDescription(weatherState),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: weatherService.getWeatherColor(weatherState),
                                      ),
                                    ),
                                  ],
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
          ),

          // Floating Legend
          if (!_isDetailsOpen)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
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
                  const _LegendItem(
                    color: AppColors.passable,
                    label: 'PASSABLE',
                  ),
                  const SizedBox(height: 12),
                  const _LegendItem(
                    color: AppColors.partial,
                    label: 'PARTIAL',
                  ),
                  const SizedBox(height: 12),
                  const _LegendItem(
                    color: AppColors.notPassable,
                    label: 'NOT PASSABLE',
                  ),
                ],
              ),
            ),
          ),
        ],
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
