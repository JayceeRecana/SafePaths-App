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
                               return GestureDetector(
                                 onTap: () => _showWeatherStatsBottomSheet(context, weatherService, weatherState),
                                 child: Container(
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
                                         weatherService.isOverrideMode 
                                             ? 'Drill: ${weatherService.getWeatherDescription(weatherState)}'
                                             : 'Live: ${weatherService.getWeatherDescription(weatherState)}',
                                         style: GoogleFonts.inter(
                                           fontSize: 12,
                                           fontWeight: FontWeight.w700,
                                           color: weatherService.getWeatherColor(weatherState),
                                         ),
                                       ),
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
