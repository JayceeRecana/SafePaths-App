import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:http/http.dart' as http;
import '../../theme/app_colors.dart';
import '../../widgets/app_map.dart';
import '../../services/routing_service.dart';
import '../../models/planned_route.dart';
import '../shared/settings_screen.dart';
import 'profile_screen.dart';
import 'navigation_screen.dart';

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
  final TextEditingController _originController = TextEditingController(text: 'Current Location');
  final TextEditingController _destinationController = TextEditingController();

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
    super.dispose();
  }

  void _onRoutingStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: AppBar(
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 16,
              title: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                        image: const DecorationImage(
                          image: NetworkImage('https://i.pravatar.cc/150?img=32'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'SafePaths',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings, color: AppColors.onSurfaceVariant),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
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
            if (_routingService.isRouteLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_routingService.routeErrorMessage != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _routingService.routeErrorMessage!,
                  style: GoogleFonts.inter(color: AppColors.onErrorContainer),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_routingService.routes.isNotEmpty) ...[
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
            _buildSafetyContextCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
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
          // Vertical connector line
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
              // FROM
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
              // TO
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
                            decoration: InputDecoration(
                              hintText: 'Enter destination...',
                              hintStyle: GoogleFonts.inter(color: AppColors.outline),
                              border: InputBorder.none,
                            ),
                             onSubmitted: (value) async {
                               final query = value.trim();
                               if (query.isEmpty) return;
                               
                               // Perform geocoding to resolve destination coordinates dynamically
                               final url = Uri.parse(
                                 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
                                 '?access_token=pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTlldHMweDAyOGYzMnM3a202dWc1encifQ.3bSUr0nz6i29AtlnB2HlHw'
                                 '&proximity=${_routingService.originPoint?.lng ?? 120.9842},${_routingService.originPoint?.lat ?? 14.6761}'
                                 '&limit=1'
                                );
                                try {
                                  final response = await http.get(url);
                                  if (response.statusCode == 200) {
                                    final data = json.decode(response.body);
                                    final features = data['features'] as List?;
                                    if (features != null && features.isNotEmpty) {
                                      final center = features.first['center'] as List?;
                                      if (center != null && center.length >= 2) {
                                        final lon = (center[0] as num).toDouble();
                                        final lat = (center[1] as num).toDouble();
                                        _routingService.setDestination(Position(lon, lat), query);
                                        return;
                                      }
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('Geocoding error: \$e');
                                }
                                
                                // Fallback/default logic if not found
                                _routingService.setDestination(Position(120.9850, 14.6780), query);
                              },
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
    bool isPartial = route.safetyStatus == 'partial';
    // flooded or any other status is treated as danger
    
    Color tagBg = isSafe
        ? AppColors.secondaryContainer
        : isPartial
            ? AppColors.partial.withValues(alpha: 0.15)
            : AppColors.errorContainer;
    Color tagText = isSafe
        ? AppColors.onSecondaryContainer
        : isPartial
            ? AppColors.partial
            : AppColors.onErrorContainer;
    IconData tagIcon = isSafe
        ? Icons.verified_user
        : isPartial
            ? Icons.info_outline
            : Icons.warning;
    String tagLabel = isSafe
        ? 'SAFEST ROUTE'
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
                    color: isSafe ? AppColors.secondary.withValues(alpha: 0.05) : AppColors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(isSafe ? Icons.check_circle : Icons.error_outline, color: isSafe ? AppColors.secondary : AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isSafe
                              ? 'Avoids known flooded areas.'
                              : 'Passes near ${route.avoidedRoads.length} reported hazards.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSafe ? AppColors.onSecondaryContainer : AppColors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Mini Map Preview
                Container(
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
                            'ROUTE PREVIEW',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Start Navigation Button
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
    bool isPartial = route.safetyStatus == 'partial';

    Color statusColor = isSafe
        ? AppColors.secondary
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
                      if (risks > 0) ...[
                        const SizedBox(width: 8),
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
                  const SizedBox(height: 3),
                  Text(
                    isSafe
                        ? 'Clear of flood zones'
                        : isPartial
                            ? 'Partial flooding reported'
                            : 'Flooding reported',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.outline,
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

  Widget _buildSafetyContextCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guardian Mode Active',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Routes are dynamically adjusted based on real-time emergency responder data and crowd-sourced safety reports.',
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
    );
  }
}
