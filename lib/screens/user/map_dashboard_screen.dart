import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/app_state_service.dart';
import 'report_submission_screen.dart';
import 'road_details_screen.dart';
import '../shared/settings_screen.dart';
import 'profile_screen.dart';
import '../../widgets/app_map.dart';
import '../shared/full_screen_map_screen.dart';
import '../../models/planned_route.dart';

class MapDashboardScreen extends StatefulWidget {
  const MapDashboardScreen({super.key});

  @override
  MapDashboardScreenState createState() => MapDashboardScreenState();
}

class MapDashboardScreenState extends State<MapDashboardScreen> {
  String? _selectedRoadId;
  MapboxMap? _mapboxMap;
  bool _isSearching = false;

  // DUMMY ROUTING VARIABLES TO FIX COMPILATION
  bool _isRoutePlanning = false;
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isRouteLoading = false;
  String? _routeErrorMessage;
  final Position _originPoint = Position(120.9842, 14.6761);
  Position? _destinationPoint;
  List<dynamic> _routes = [];
  int _selectedRouteIndex = 0;
  bool get isRoutePlanningMode => _isRoutePlanning;

  void enterRoutePlanningMode() {}
  void exitRoutePlanningMode() {}
  void _calculateRoute() {}
  Future<void> _onDestinationChanged(String q) async {}
  void _selectDestination(String p, double a, double b) {}






  void _flyToRoad(RoadStatus road) {
    if (_mapboxMap == null || road.geometry == null) return;
    final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
    if (coordsDyn == null || coordsDyn.isEmpty) return;

    double? lon;
    double? lat;

    final first = coordsDyn.first;
    if (first is Map) {
      lon = (first['lon'] as num?)?.toDouble();
      lat = (first['lat'] as num?)?.toDouble();
    } else if (first is List && first.length >= 2) {
      lon = (first[0] as num?)?.toDouble();
      lat = (first[1] as num?)?.toDouble();
    }

    if (lon != null && lat != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(lon, lat)),
          zoom: 16.0,
        ),
        MapAnimationOptions(duration: 1500),
      );
    }
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
      });
      // Open Road Details screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoadDetailsScreen(roadId: matchedRoad!.id),
        ),
      );
      return;
    }

    // 2. Query Mapbox Geocoding API within Barangay Marulas bounding box
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
      '?access_token=pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTlldHMweDAyOGYzMnM3a202dWc1encifQ.3bSUr0nz6i29AtlnB2HlHw'
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
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

          if (selectedRoad.status == 'partial') {
            statusColor = AppColors.partial;
            statusIcon = Icons.info;
            statusLabel = 'Partial Blockage';
            statusBgColor = AppColors.partial.withValues(alpha: 0.15);
          } else if (selectedRoad.status == 'not_passable') {
            statusColor = AppColors.notPassable;
            statusIcon = Icons.warning;
            statusLabel = 'Not Passable';
            statusBgColor = AppColors.notPassable.withValues(alpha: 0.15);
          }
        }

        return Scaffold(
          body: Stack(
            children: [
              // Map background
              Positioned.fill(
                child: AppMap(
                  onMapCreatedCallback: (map) {
                    _mapboxMap = map;
                  },
                  routePoints: _isRoutePlanning && _routes.isNotEmpty ? _routes[_selectedRouteIndex].points : null,
                ),
              ),

              // GPS pulse at center
              Center(
                child: _GPSPulse(),
              ),

              // Top header with search (Only shown if NOT route planning)
              if (!_isRoutePlanning)
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.thunderstorm,
                                          size: 20, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        '28°C',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
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
                    ),
                  ),
                ),

              // Route Entry Panel (Shown if Route Planning is Active)
              if (_isRoutePlanning)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                                  onPressed: exitRoutePlanningMode,
                                ),
                                Text(
                                  'Plan Safest Route',
                                  style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dot connector
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      Container(
                                        width: 1.5,
                                        height: 48,
                                        color: AppColors.outlineVariant,
                                      ),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Inputs
                                Expanded(
                                  child: Column(
                                    children: [
                                      // From: Current Location
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Current Location',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.onSurface,
                                              ),
                                            ),
                                            const Icon(Icons.my_location, size: 14, color: AppColors.primary),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // To: Search destination
                                      Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: TextField(
                                          controller: _destinationController,
                                          focusNode: _destinationFocus,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.onSurface,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Search destination...',
                                            hintStyle: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: AppColors.outline,
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            border: InputBorder.none,
                                            isDense: true,
                                            suffixIcon: _destinationController.text.isNotEmpty
                                                ? GestureDetector(
                                                    child: const Icon(Icons.clear, size: 14),
                                                    onTap: () {
                                                      _destinationController.clear();
                                                      setState(() {
                                                        _suggestions.clear();
                                                        _routes.clear();
                                                        _destinationPoint = null;
                                                        _routeErrorMessage = null;
                                                      });
                                                    },
                                                  )
                                                : null,
                                          ),
                                          onChanged: _onDestinationChanged,
                                          onSubmitted: (value) async {
                                            if (_suggestions.isNotEmpty) {
                                              final suggestion = _suggestions.first;
                                              final center = suggestion['center'] as List;
                                              final lon = (center[0] as num).toDouble();
                                              final lat = (center[1] as num).toDouble();
                                              _selectDestination(suggestion['place_name'], lon, lat);
                                            } else if (value.trim().isNotEmpty) {
                                              setState(() {
                                                _isRouteLoading = true;
                                                _routeErrorMessage = null;
                                              });
                                              await _onDestinationChanged(value);
                                              if (_suggestions.isNotEmpty) {
                                                final suggestion = _suggestions.first;
                                                final center = suggestion['center'] as List;
                                                final lon = (center[0] as num).toDouble();
                                                final lat = (center[1] as num).toDouble();
                                                _selectDestination(suggestion['place_name'], lon, lat);
                                              } else {
                                                setState(() {
                                                  _routeErrorMessage = 'No location found for "$value". Try another search.';
                                                  _isRouteLoading = false;
                                                });
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_suggestions.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8, left: 20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _suggestions.length,
                                  itemBuilder: (context, idx) {
                                    final suggestion = _suggestions[idx];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        suggestion['place_name'],
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      onTap: () {
                                        final center = suggestion['center'] as List;
                                        final lon = (center[0] as num).toDouble();
                                        final lat = (center[1] as num).toDouble();
                                        _selectDestination(suggestion['place_name'], lon, lat);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Legend overlay
              Positioned(
                top: _isRoutePlanning ? 240 : 200,
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

              // Fullscreen FAB (Only show when NOT route planning)
              if (!_isRoutePlanning)
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



              // Emergency FAB (Only show when NOT route planning)
              if (!_isRoutePlanning)
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
              if (!_isRoutePlanning && appState.roads.isNotEmpty && selectedRoad != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoadDetailsScreen(roadId: selectedRoad!.id),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(40),
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
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              statusIcon,
                              size: 28,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 16),
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
                                  selectedRoad.notes.isEmpty
                                      ? 'No active obstructions reported.'
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
                          Column(
                            children: [
                              Text(
                                statusLabel.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Route details Loader (Only show when Route Planning is loading)
              if (_isRoutePlanning && _isRouteLoading)
                Positioned(
                  bottom: 32,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 32,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                ),

              // Route details Error Card (Only show when Route Planning has errors)
              if (_isRoutePlanning && _routeErrorMessage != null && !_routeErrorMessage!.startsWith('Warning:'))
                Positioned(
                  bottom: 32,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _routeErrorMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                          onPressed: _calculateRoute,
                          child: const Text('Retry', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),

              // Route details Warning alert (displayed above route card if route found with warnings)
              if (_isRoutePlanning && _routeErrorMessage != null && _routeErrorMessage!.startsWith('Warning:'))
                Positioned(
                  bottom: _routes.isNotEmpty ? 290 : 32,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.orange, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _routeErrorMessage!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Integrated Route details Sheet/Card (Shown if routes are successfully planned)
              if (_isRoutePlanning && !_isRouteLoading && _routes.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Builder(
                    builder: (context) {
                      final selectedRoute = _routes[_selectedRouteIndex];
                      
                      String safestRouteSubtitle = 'Route is clear. Bypasses all active blocks.';
                      Color safestBorderColor = AppColors.secondary.withValues(alpha: 0.1);
                      Color safestBgColor = AppColors.secondary.withValues(alpha: 0.05);
                      Color safestTextColor = AppColors.onSecondaryContainer;
                      IconData safestIcon = Icons.check_circle;

                      if (selectedRoute.safetyStatus == 'partial') {
                        safestRouteSubtitle = 'Caution: Partial flooding reported.';
                        safestBorderColor = AppColors.partial.withValues(alpha: 0.2);
                        safestBgColor = AppColors.partial.withValues(alpha: 0.05);
                        safestTextColor = AppColors.partial;
                        safestIcon = Icons.info;
                      } else if (selectedRoute.safetyStatus == 'not_passable') {
                        safestRouteSubtitle = 'Warning: Flooded/blocked streets on path!';
                        safestBorderColor = AppColors.notPassable.withValues(alpha: 0.2);
                        safestBgColor = AppColors.notPassable.withValues(alpha: 0.05);
                        safestTextColor = AppColors.notPassable;
                        safestIcon = Icons.warning;
                      } else if (selectedRoute.avoidedRoads.isNotEmpty) {
                        safestRouteSubtitle = 'Bypasses ${selectedRoute.avoidedRoads.length} flood-prone areas: ${selectedRoute.avoidedRoads.join(", ")}';
                        safestBorderColor = AppColors.secondary.withValues(alpha: 0.2);
                        safestBgColor = AppColors.secondary.withValues(alpha: 0.05);
                        safestTextColor = AppColors.primary;
                        safestIcon = Icons.shield;
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: safestBorderColor,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.secondaryContainer,
                                                borderRadius: BorderRadius.circular(100),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    selectedRoute.safetyStatus == 'safe' ? Icons.verified_user : Icons.warning_amber_rounded,
                                                    size: 12,
                                                    color: AppColors.onSecondaryContainer,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    selectedRoute.safetyStatus == 'safe' ? 'SAFEST ROUTE' : 'CAUTION REQUIRED',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 1.2,
                                                      color: AppColors.onSecondaryContainer,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              selectedRoute.summary,
                                              style: GoogleFonts.manrope(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${selectedRoute.durationMin} min',
                                            style: GoogleFonts.manrope(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                              color: AppColors.onSurface,
                                            ),
                                          ),
                                          Text(
                                            '${selectedRoute.distanceMiles.toStringAsFixed(1)} miles',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: safestBgColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(safestIcon, size: 16, color: safestTextColor),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            safestRouteSubtitle,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: safestTextColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Alternatives trigger if there are more than 1 routes
                                  if (_routes.length > 1) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 36,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _routes.length,
                                        itemBuilder: (context, idx) {
                                          final isSelected = idx == _selectedRouteIndex;
                                          final route = _routes[idx];
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text('${route.summary} (${route.durationMin}m)'),
                                              selected: isSelected,
                                              selectedColor: AppColors.primaryContainer,
                                              labelStyle: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                color: isSelected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
                                              ),
                                              onSelected: (selected) {
                                                if (selected) {
                                                  setState(() {
                                                    _selectedRouteIndex = idx;
                                                  });
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Start navigation button
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                              child: Container(
                                width: double.infinity,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppColors.primary, AppColors.primaryContainer],
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            selectedRoute.safetyStatus == 'safe'
                                                ? 'Navigation started on ${selectedRoute.summary}.'
                                                : 'Warning: Starting navigation on a route with flood warnings.',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Start Navigation',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.navigation, size: 18, color: Colors.white),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
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

class _GPSPulse extends StatefulWidget {
  @override
  State<_GPSPulse> createState() => _GPSPulseState();
}

class _GPSPulseState extends State<_GPSPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Ping
            Container(
              width: 40 + (20 * _animation.value),
              height: 40 + (20 * _animation.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary
                    .withValues(alpha: 0.3 * (1 - _animation.value)),
              ),
            ),
            // Dot
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

