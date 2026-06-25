import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:http/http.dart' as http;
import '../../theme/app_colors.dart';
import '../../widgets/app_map.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/routing_service.dart';
import '../../models/planned_route.dart';
import 'navigation_screen.dart';
import 'route_preview_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  final Position? prefilledDestination;
  final String? prefilledName;

  const RoutePlannerScreen({
    super.key,
    this.prefilledDestination,
    this.prefilledName,
  });

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final RoutingService _routingService = RoutingService.instance;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  
  Timer? _debounce;
  List<Map<String, dynamic>> _destinationSuggestions = [];
  bool _isSearching = false;

  // Retrieve the mapbox token from environment
  final String _mapboxToken = const String.fromEnvironment('MAPBOX_TOKEN', defaultValue: 'pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTljamszcDAxZ2gycXBocmQxczhxN3kifQ.19WWZ3DXdaSG-LG2_zGpbg');

  @override
  void initState() {
    super.initState();
    _routingService.addListener(_onRoutingStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routingService.startPlanning(
        prefillDestination: widget.prefilledDestination,
        name: widget.prefilledName,
      );
    });
    if (widget.prefilledDestination != null) {
      _destinationController.text = widget.prefilledName ?? 'Selected Location';
    }
  }

  @override
  void dispose() {
    _routingService.removeListener(_onRoutingStateChanged);
    _originController.dispose();
    _destinationController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onRoutingStateChanged() {
    setState(() {});
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _destinationSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query.trim());
    });
  }

  // Hardcoded Valenzuela Landmarks for Capstone Demo
  // This ensures perfect, free, and instant POI results without relying on external API quirks.
  static const List<Map<String, dynamic>> _localLandmarks = [
    {
      'text': 'Our Lady of Fatima University',
      'place_name': 'Our Lady of Fatima University, MacArthur Highway, Marulas, Valenzuela',
      'center': [120.9783, 14.6788], // Lng, Lat
    },
    {
      'text': 'SM City Valenzuela',
      'place_name': 'SM City Valenzuela, MacArthur Highway, Karuhatan, Valenzuela',
      'center': [120.9772, 14.6795],
    },
    {
      'text': 'Valenzuela Medical Center',
      'place_name': 'Valenzuela Medical Center, Padrigal St, Karuhatan, Valenzuela',
      'center': [120.9765, 14.6858],
    },
    {
      'text': 'Valenzuela City Emergency Hospital',
      'place_name': 'Valenzuela City Emergency Hospital, Dalandanan, Valenzuela',
      'center': [120.9715, 14.6853],
    },
    {
      'text': 'Dalandanan National High School (Evacuation)',
      'place_name': 'Dalandanan National High School, Dalandanan, Valenzuela',
      'center': [120.9632, 14.6953],
    },
    {
      'text': 'Valenzuela City Hall',
      'place_name': 'Valenzuela City Hall, MacArthur Highway, Malinta, Valenzuela',
      'center': [120.9660, 14.7011],
    },
    {
      'text': 'Valenzuela Police Station',
      'place_name': 'Valenzuela Police Station, MacArthur Highway, Valenzuela',
      'center': [120.9665, 14.7005],
    },
  ];

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;

    // 1. Check Local Custom Database FIRST (Instant & Free)
    final lowerQuery = query.toLowerCase().replaceAll('valenzuela', '').trim();
    final localMatches = _localLandmarks.where((landmark) {
      final name = landmark['text'].toString().toLowerCase();
      final place = landmark['place_name'].toString().toLowerCase();
      return name.contains(lowerQuery) || place.contains(lowerQuery);
    }).toList();

    if (localMatches.isNotEmpty) {
      setState(() {
        _destinationSuggestions = localMatches;
        _isSearching = false;
      });
      return; // Stop here if we found a local landmark!
    }

    // 2. Fallback to OpenStreetMap (Nominatim) Free Public API
    // This is 100% free, requires no API key, and provides great redundancy.
    try {
      final nominatimUrl = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent('$query Valenzuela')}'
          '&format=json'
          '&limit=5'
          '&countrycodes=ph'
      );
      
      final nomResponse = await http.get(nominatimUrl, headers: {
        'User-Agent': 'SafePathsCapstoneApp/1.0', // Nominatim requires a User-Agent
      });

      if (nomResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(nomResponse.body);
        if (data.isNotEmpty) {
          final osmResults = data.map((item) {
            final displayName = item['display_name'] as String;
            final parts = displayName.split(',');
            final text = parts.isNotEmpty ? parts.first.trim() : displayName;
            
            return {
              'text': text,
              'place_name': displayName,
              'center': [
                double.parse(item['lon'].toString()),
                double.parse(item['lat'].toString()),
              ],
            };
          }).toList();

          setState(() {
            _destinationSuggestions = osmResults;
            _isSearching = false;
          });
          return; // Stop here if OSM found it!
        }
      }
    } catch (e) {
      debugPrint('OSM Fallback error: $e');
    }

    // 3. Final Fallback to Mapbox API
    if (_mapboxToken.isEmpty) return;

    final searchQuery = '$query Valenzuela';
    final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(searchQuery)}.json'
        '?access_token=$_mapboxToken'
        '&proximity=${_routingService.originPoint?.lng ?? 120.9842},${_routingService.originPoint?.lat ?? 14.6761}'
        '&bbox=120.8500,14.5500,121.1500,14.8500' // Greater Northern Metro Manila BBox
        '&country=ph' // Keep it within the Philippines
        '&limit=5' // Fetch top 5 suggestions
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;
        if (mounted) {
          setState(() {
            _destinationSuggestions = features?.cast<Map<String, dynamic>>() ?? [];
            _isSearching = false;
          });
        }
      } else {
        if (mounted) setState(() => _isSearching = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
      debugPrint('[RoutePlannerScreen] Geocoding error: $e');
    }
  }

  Future<void> _selectDestination(Map<String, dynamic> feature) async {
    final placeName = feature['place_name'] as String?;
    final center = feature['center'] as List?;
    
    if (placeName != null && center != null && center.length >= 2) {
      final lon = (center[0] as num).toDouble();
      final lat = (center[1] as num).toDouble();
      
      setState(() {
        _destinationController.text = feature['text'] ?? placeName; // Set short name if available
        _destinationSuggestions = []; // Hide suggestions
        FocusScope.of(context).unfocus(); // Close keyboard
      });
      
      _routingService.setDestination(Position(lon, lat), placeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.surface,
          extendBodyBehindAppBar: true,
          appBar: const AppTopBar(
            showBackButton: false,
            showProfile: true,
            showSettingsAction: true,
          ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 64 + 16,
          left: 16,
          right: 16,
          bottom: 120, // Extra padding for BottomNavBar
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchSection(),
            const SizedBox(height: 24),
            _buildVehicleSelector(),
            const SizedBox(height: 24),
            _buildSuggestedRoutesHeader(),
            const SizedBox(height: 16),
            // Blocking error: only when NO routes exist at all
            if (_routingService.routeErrorMessage != null && _routingService.routes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.block, color: AppColors.error, size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Destination Unreachable',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _routingService.routeErrorMessage!,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppColors.onErrorContainer,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (_routingService.routes.isNotEmpty) ...[
              // Non-blocking weather warning banner (shows ABOVE routes)
              if (_routingService.routeWarningMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE65100).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _routingService.routeWarningMessage!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFBF360C),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _buildSafestRouteCard(_routingService.routes[_routingService.selectedRouteIndex]),
              const SizedBox(height: 16),
              ..._routingService.routes.asMap().entries.where((e) => e.key != _routingService.selectedRouteIndex).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildAlternativeRouteCard(entry.value, entry.key),
                );
              }),
            ] else ...[
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Enter a destination to see routes.',
                  style: GoogleFonts.inter(color: AppColors.outline),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
    if (_routingService.isRouteLoading)
      Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Calculating safest route...',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 21,
                top: 40,
                bottom: 40,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(left: 16, right: 16),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 4),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FROM',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.outline,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      RoutingService.devMode
                                          ? 'Brgy. Marulas (Dev Mode)'
                                          : _routingService.originPoint != null
                                              ? 'Current Location'
                                              : 'Locating...',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: RoutingService.devMode
                                            ? AppColors.tertiary
                                            : _routingService.originPoint != null
                                                ? AppColors.onSurface
                                                : AppColors.outline,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    _routingService.originPoint != null
                                        ? Icons.my_location
                                        : Icons.location_searching,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(left: 16, right: 16),
                        decoration: BoxDecoration(
                          color: AppColors.tertiary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2), width: 4),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TO',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.outline,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextField(
                                controller: _destinationController,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface,
                                ),
                                onChanged: _onSearchChanged,
                                onSubmitted: (value) {
                                  if (_destinationSuggestions.isNotEmpty) {
                                    _selectDestination(_destinationSuggestions.first);
                                  } else if (value.trim().isNotEmpty) {
                                    _onSearchChanged(value);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Enter destination...',
                                  hintStyle: GoogleFonts.inter(color: AppColors.outline),
                                  border: InputBorder.none,
                                  filled: false,
                                  suffixIcon: _isSearching
                                      ? const Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                          ),
                                        )
                                      : _destinationController.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, size: 20),
                                              onPressed: () {
                                                _destinationController.clear();
                                                _onSearchChanged('');
                                              },
                                            )
                                          : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Autocomplete Suggestions List
        if (_destinationSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _destinationSuggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 48),
              itemBuilder: (context, index) {
                final feature = _destinationSuggestions[index];
                final text = feature['text'] ?? '';
                final placeName = feature['place_name'] ?? '';
                final subText = placeName.replaceFirst('$text, ', '');
                
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: AppColors.outline),
                  title: Text(
                    text,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: subText.isNotEmpty
                      ? Text(
                          subText,
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => _selectDestination(feature),
                );
              },
            ),
          ),
        
        const SizedBox(height: 24),
        Text(
          'Quick Destinations',
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        // Emergency Landmarks Chips
        Column(
          children: [
            Row(
              children: [
                _buildLandmarkChip('Hospitals', Icons.local_hospital, 'Hospital Medical Center Valenzuela'),
                const SizedBox(width: 12),
                _buildLandmarkChip('Evac Centers', Icons.school, 'Elementary School Barangay Hall Valenzuela'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildLandmarkChip('Police', Icons.local_police, 'Police Station Valenzuela'),
                const SizedBox(width: 12),
                _buildLandmarkChip('Fire Station', Icons.local_fire_department, 'Fire Station Valenzuela'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLandmarkChip(String label, IconData icon, String query) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _destinationController.text = label;
          _onSearchChanged(query);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleSelector() {
    final vehicles = [
      {'label': 'Walking', 'icon': Icons.directions_walk},
      {'label': 'Motorcycle', 'icon': Icons.motorcycle},
      {'label': 'Sedan', 'icon': Icons.directions_car},
      {'label': 'SUV / Pickup', 'icon': Icons.airport_shuttle},
      {'label': 'Truck', 'icon': Icons.local_shipping},
    ];

    Widget buildVehicleCard(Map<String, dynamic> v) {
      final isSelected = _routingService.selectedVehicleType == v['label'];
      return Expanded(
        child: GestureDetector(
          onTap: () => _routingService.setVehicleType(v['label'] as String),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  v['icon'] as IconData,
                  size: 20,
                  color: isSelected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    v['label'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel Mode',
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buildVehicleCard(vehicles[0]),
            const SizedBox(width: 12),
            buildVehicleCard(vehicles[1]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buildVehicleCard(vehicles[2]),
            const SizedBox(width: 12),
            buildVehicleCard(vehicles[3]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buildVehicleCard(vehicles[4]),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()), // Empty spacer to keep truck half-width
          ],
        ),
      ],
    );
  }

  Widget _buildSuggestedRoutesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Suggested Routes',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        Text(
          'LIVE UPDATES ACTIVE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSafestRouteCard(PlannedRoute route) {
    bool isSafe = route.safetyStatus == 'safe';
    bool isPassablePartial = route.safetyStatus == 'passable_partial';
    bool isUnverified = route.safetyStatus == 'unverified_risk';
    bool isPartial = route.safetyStatus == 'partial';
    // flooded or any other status is treated as danger
    
    Color tagBg = isSafe
        ? AppColors.secondaryContainer
        : isUnverified
            ? AppColors.onSurfaceVariant.withValues(alpha: 0.10)
            : isPassablePartial 
                ? AppColors.partial.withValues(alpha: 0.10)
                : isPartial
                    ? AppColors.partial.withValues(alpha: 0.15)
                    : AppColors.errorContainer;
    Color tagText = isSafe
        ? AppColors.onSecondaryContainer
        : isUnverified
            ? AppColors.onSurfaceVariant
            : isPassablePartial
                ? AppColors.onSurfaceVariant
                : isPartial
                    ? AppColors.partial
                    : AppColors.onErrorContainer;
    IconData tagIcon = isSafe
        ? Icons.verified_user
        : isUnverified
            ? Icons.help_outline
            : isPassablePartial
                ? Icons.water
                : isPartial
                    ? Icons.info_outline
                    : Icons.warning;
    String tagLabel = isSafe
        ? 'SAFEST ROUTE'
        : isUnverified
            ? 'UNVERIFIED ROUTE'
            : isPassablePartial
                ? 'PARTIAL FLOOD (PASSABLE)'
                : isPartial
                    ? 'CAUTION: PARTIAL FLOOD'
                    : 'WARNING: FLOODED';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSafe
              ? AppColors.secondary.withValues(alpha: 0.1)
              : isPassablePartial
                  ? AppColors.partial.withValues(alpha: 0.2)
                  : isPartial
                      ? AppColors.partial.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(tagIcon, size: 14, color: tagText),
                                    const SizedBox(width: 4),
                                    Text(
                                      tagLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: tagText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  'Safety Score: ${route.safetyScore}/100',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              if (route.riskReductionPercentage != null && route.riskReductionPercentage! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.trending_down, size: 14, color: AppColors.secondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        route.timePenaltyMin != null && route.timePenaltyMin! > 0
                                            ? 'Risk Reduced by ${route.riskReductionPercentage}% (+${route.timePenaltyMin} mins)'
                                            : 'Risk Reduced by ${route.riskReductionPercentage}%',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            route.summary,
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${route.durationMin} min',
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          '${route.distanceMiles} miles',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSafe 
                        ? AppColors.secondary.withValues(alpha: 0.05) 
                        : isPassablePartial
                            ? AppColors.partial.withValues(alpha: 0.05)
                            : AppColors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          isSafe ? Icons.check_circle : (isPassablePartial ? Icons.info_outline : Icons.error_outline), 
                          color: isSafe ? AppColors.secondary : (isPassablePartial ? AppColors.onSurfaceVariant : AppColors.error), 
                          size: 20
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSafe
                                  ? 'Recommended route. Clear of known flood zones.'
                                  : isPassablePartial
                                      ? 'Recommended route. Passes through shallow water safe for your vehicle.'
                                      : 'Recommended route. Balances travel time and risk exposure.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isSafe 
                                    ? AppColors.onSecondaryContainer 
                                    : isPassablePartial 
                                        ? AppColors.onSurfaceVariant 
                                        : AppColors.onErrorContainer,
                              ),
                            ),
                            if (route.routeExplanations.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ...route.routeExplanations.map((explanation) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      explanation.startsWith('Avoids') ? Icons.check : Icons.warning_amber_rounded, 
                                      size: 14, 
                                      color: explanation.startsWith('Avoids') ? AppColors.secondary : AppColors.error
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        explanation,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Mini Map Preview
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePreviewScreen(route: route)));
                  },
                  child: Container(
                    height: 192,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surfaceContainerHigh,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AppMap(
                          routePoints: route.points,
                          // Ignore gestures to keep it as a static preview in the scrollable list
                        ),
                      ),
                      // Gradient overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 80,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'TAP TO EXPAND',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          ),
                          child: const Icon(Icons.fullscreen, color: AppColors.primary, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 20),
                // Start Navigation Button
                if (route.safetyStatus == 'flooded')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Route Blocked',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryContainer],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => NavigationScreen(route: route)));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Start Navigation',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.navigation, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlternativeRouteCard(PlannedRoute route, int index) {
    int risks = route.avoidedRoads.length;
    bool isSafe = route.safetyStatus == 'safe';
    bool isPassablePartial = route.safetyStatus == 'passable_partial';
    bool isPartial = route.safetyStatus == 'partial';

    Color statusColor = isSafe
        ? AppColors.secondary
        : isPassablePartial
            ? AppColors.outline
            : isPartial
                ? AppColors.partial
                : AppColors.error;

    return GestureDetector(
      onTap: () => _routingService.selectRoute(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Safety dot indicator
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        route.summary,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Score: ${route.safetyScore}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (risks > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$risks RISK${risks > 1 ? 'S' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSafe
                        ? 'Not recommended because:'
                        : 'Not recommended because:',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (route.routeExplanations.isNotEmpty)
                    ...route.routeExplanations.map((explanation) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: AppColors.outline, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              explanation,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))
                  else
                    Text(
                      'Longer travel time than the safest route.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${route.durationMin} min',
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  '${route.distanceMiles} mi',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: AppColors.outlineVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }


}
