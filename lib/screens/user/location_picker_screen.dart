import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  MapboxMap? _mapboxMap;
  static const String _publicToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: 'pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTljamszcDAxZ2gycXBocmQxczhxN3kifQ.19WWZ3DXdaSG-LG2_zGpbg');
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_publicToken);
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      await _mapboxMap!.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
      ));
    } catch (e) {
      debugPrint('Error enabling location puck: $e');
    }
  }

  Future<void> _confirmLocation() async {
    if (_mapboxMap == null) return;
    try {
      final cameraState = await _mapboxMap!.getCameraState();
      final point = cameraState.center;
      final lat = point.coordinates.lat.toDouble();
      final lng = point.coordinates.lng.toDouble();

      // Pin-to-Road Snapping logic
      String? nearestRoadId;
      double minGlobalDistance = double.infinity;
      
      for (var road in AppStateService.instance.roads) {
        if (road.geometry != null && road.geometry!['coordinates'] != null) {
          final coords = road.geometry!['coordinates'] as List<dynamic>;
          
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
              
            double dist = geo.Geolocator.distanceBetween(lat, lng, rLat, rLng);
            if (dist < minGlobalDistance) {
              minGlobalDistance = dist;
              nearestRoadId = road.id;
            }
          }
        }
      }

      // Must be within 500 meters of a monitored road
      if (minGlobalDistance > 500 || nearestRoadId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pin is too far from any monitored road. Please place it closer to a valid road.')),
        );
        return;
      }

      Navigator.of(context).pop({
        'lat': lat,
        'lng': lng,
        'roadId': nearestRoadId,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read map location: $e')),
      );
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty || _mapboxMap == null) return;
    
    setState(() => _isSearching = true);
    
    try {
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
        '?access_token=$_publicToken'
        '&bbox=120.9667,14.6640,120.9990,14.6860' // Valenzuela bounding box
        '&limit=1'
      );
      
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final center = feature['center'] as List;
          final double lng = center[0].toDouble();
          final double lat = center[1].toDouble();
          
          _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(lng, lat)),
              zoom: 16.0,
            ),
            MapAnimationOptions(duration: 1000)
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location not found in Valenzuela area.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
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
        geo.Position position = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(position.longitude, position.latitude)),
            zoom: 16.0,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Pin Location',
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(120.9810, 14.6740)), // Brgy. Marulas
              zoom: 15.0,
            ),
          ),
          
          // Center Pin Overlay
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0), // offset for pin tail
              child: Icon(
                Icons.location_on,
                size: 50,
                color: AppColors.error,
              ),
            ),
          ),

          // Instructions and Search at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Instructions
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Drag the map or search to place the pin.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search for a street or landmark...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_forward_ios, size: 16),
                              onPressed: () => _searchLocation(_searchController.text),
                              color: AppColors.primary,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    onSubmitted: _searchLocation,
                  ),
                ),
              ],
            ),
          ),

          // Locate Me Button
          Positioned(
            bottom: 110, // Just above the confirm button
            right: 24,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _flyToMyLocation,
                icon: const Icon(Icons.my_location, color: AppColors.primary),
                tooltip: 'My Location',
              ),
            ),
          ),

          // Confirm Button at bottom
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _confirmLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'CONFIRM LOCATION',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
