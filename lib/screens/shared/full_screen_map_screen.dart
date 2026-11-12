import '../../services/noah_awareness.dart';
import '../../widgets/noah_awareness_card.dart';
import '../../widgets/map_home_controls.dart';
import '../../widgets/map_road_review_sheet.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_map.dart';
import '../../widgets/weather_detail_sheet.dart';
import '../../services/weather_service.dart';
import '../shared/settings_screen.dart';
import '../../services/app_state_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../user/road_details_screen.dart';
import '../../services/user_service.dart';

import '../../utils/geo_utils.dart';

class FullScreenMapScreen extends StatefulWidget {
  final String? initialRoadId;
  final bool showNoahInitially;
  const FullScreenMapScreen({
    super.key,
    this.initialRoadId,
    this.showNoahInitially = false,
  });

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  final GlobalKey<AppMapState> _mapStateKey = GlobalKey<AppMapState>();
  final _awareness = NoahMapController();
  @override
  void initState() {
    super.initState();
    if (widget.showNoahInitially) _awareness.setEnabled(true);
  }

  @override
  void dispose() {
    _awareness.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  MapboxMap? _mapboxMap;
  bool _isDetailsOpen = false;
  String? _selectedRoadId;

  void _flyToRoad(RoadStatus road) {
    if (_mapboxMap == null) return;
    final center = GeoUtils.getRoadCenter(road.geometry);
    if (center != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(center.lng, center.lat)),
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

  Future<void> _frameRoadForEditor(RoadStatus road) async {
    final map = _mapboxMap;
    if (map == null || !mounted) return;
    final points = GeoUtils.extractSegments(road.geometry)
        .expand((s) => s)
        .where(
          (p) =>
              p.lat.isFinite &&
              p.lng.isFinite &&
              p.lat.abs() <= 90 &&
              p.lng.abs() <= 180,
        )
        .map((p) => Point(coordinates: Position(p.lng, p.lat)))
        .toList();
    if (points.isEmpty) return;
    try {
      final camera = await map
          .cameraForCoordinatesPadding(
            points,
            CameraOptions(
              bearing: 0,
              pitch: 0,
              padding: MbxEdgeInsets(
                top: MediaQuery.paddingOf(context).top + 24,
                left: 36,
                right: 36,
                bottom: MediaQuery.sizeOf(context).height * .67,
              ),
            ),
            null,
            17.5,
            null,
          )
          .timeout(const Duration(seconds: 3));
      if (mounted && identical(map, _mapboxMap) && _selectedRoadId == road.id)
        await map
            .flyTo(camera, MapAnimationOptions(duration: 500))
            .timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Camera failure must not change the checked save flow. */
    }
  }

  void _handleRoadTapped(String roadId, Position? tappedPosition) async {
    if (_isDetailsOpen) return;
    final road = AppStateService.instance.roads
        .where((r) => r.id == roadId)
        .firstOrNull;
    if (road == null) return;
    setState(() => _isDetailsOpen = true);
    try {
      final role = await UserService.getUserRole();
      if (!mounted) return;
      if (role == UserRole.admin) {
        setState(() => _selectedRoadId = roadId);
        await _frameRoadForEditor(road);
        if (!mounted) return;
        final result = await showMapRoadReview(context, road);
        if (mounted && result != null)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.confirmation)));
      } else {
        _flyToRoad(road);
        await Navigator.of(context).push(RoadDetailsScreen.route(roadId));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'The road editor could not be opened. Please retry.'),
            ),
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _isDetailsOpen = false;
          _selectedRoadId = null;
        });
    }
  }

  Future<void> _searchAndHighlight(String query) async {
    if (_mapboxMap == null) return;
    try {
      final appState = AppStateService.instance;
      final roads = appState.roads;
      final matchedRoad = roads
          .where((r) => r.name.toLowerCase().contains(query.toLowerCase()))
          .firstOrNull;

      if (matchedRoad != null && matchedRoad.geometry != null) {
        final center = GeoUtils.getRoadCenter(matchedRoad.geometry);
        if (center != null) {
          _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(center.lng, center.lat)),
              zoom: 17.5,
              pitch: 60.0,
              bearing: -15.0,
            ),
            MapAnimationOptions(duration: 1500),
          );
        }
      } else {
        final role = await UserService.getUserRole();
        if (!mounted) return;
        if (role == UserRole.admin) {
          // If admin, try to fetch the road from OSM dataset directly
          _mapStateKey.currentState?.fetchRoadGeometry(query);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not find road: $query')),
          );
        }
      }
    } catch (e) {
      debugPrint('[FullScreenSearch] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: !_isDetailsOpen,
      body: Stack(
        children: [
          // Full Screen Map
          Positioned.fill(
            child: AppMap(
              key: _mapStateKey,
              awareness: _awareness,
              showSearchButton: false,
              selectedRoadId: _selectedRoadId,
              onMapCreatedCallback: (map) {
                _mapboxMap = map;
                if (widget.initialRoadId != null) {
                  final road = AppStateService.instance.roads
                      .where((r) => r.id == widget.initialRoadId)
                      .firstOrNull;
                  if (road != null) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) _flyToRoad(road);
                    });
                  } else {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                context,
                                'The road referenced in this alert is no longer active on the map.',
                              ),
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    });
                  }
                }
              },
              onRoadTapped: _handleRoadTapped,
            ),
          ),

          // Keep the road above the editor visible.
          if (!_isDetailsOpen)
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppPalette.of(
                                        context,
                                      ).onPrimaryContainer,
                                      width: 2,
                                    ),
                                    color: AppPalette.of(
                                      context,
                                    ).primaryContainer,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.arrow_back,
                                    size: 18,
                                    color: AppPalette.of(
                                      context,
                                    ).onPrimaryContainer,
                                  ),
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
                                    color: AppPalette.of(context).primary,
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
                                  color: AppPalette.of(context).outline,
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
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _isSearching
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppPalette.of(context)
                                              .surfaceContainerLow
                                              .withValues(alpha: 0.8),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: AppPalette.of(
                                              context,
                                            ).primary,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () => setState(
                                                () => _isSearching = false,
                                              ),
                                              child: Icon(
                                                Icons.arrow_back,
                                                size: 20,
                                                color: AppPalette.of(
                                                  context,
                                                ).primary,
                                              ),
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
                                                  color: AppPalette.of(
                                                    context,
                                                  ).onSurface,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: tr(
                                                    context,
                                                    'Type road or area name...',
                                                  ),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                        vertical: 6,
                                                      ),
                                                ),
                                                onSubmitted: (value) {
                                                  if (value.trim().isNotEmpty) {
                                                    _searchAndHighlight(
                                                      value.trim(),
                                                    );
                                                    setState(
                                                      () =>
                                                          _isSearching = false,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: () =>
                                            setState(() => _isSearching = true),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppPalette.of(context)
                                                .surfaceContainerLow
                                                .withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.search,
                                                size: 20,
                                                color: AppPalette.of(
                                                  context,
                                                ).outline,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                tr(context, 'Search areas...'),
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppPalette.of(
                                                    context,
                                                  ).outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              ValueListenableBuilder<WeatherState>(
                                valueListenable:
                                    SimulatedWeatherService.instance.listenable,
                                builder: (context, weatherState, _) {
                                  final weatherService =
                                      SimulatedWeatherService.instance;
                                  return GestureDetector(
                                    onTap: () => WeatherDetailSheet.show(
                                      context,
                                      weatherService: weatherService,
                                      weatherState: weatherState,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: weatherService
                                            .getWeatherColor(weatherState)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            weatherService.getWeatherIcon(
                                              weatherState,
                                            ),
                                            size: 20,
                                            color: weatherService
                                                .getWeatherColor(weatherState),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            weatherService.isOverrideMode
                                                ? '⚡ DRILL: ${weatherService.getWeatherDescription(weatherState)}'
                                                : weatherService
                                                      .getWeatherDescription(
                                                        weatherState,
                                                      ),
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: weatherService
                                                  .getWeatherColor(
                                                    weatherState,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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

          if (!_isDetailsOpen)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              left: 16,
              right: 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .35,
                ),
                child: SingleChildScrollView(
                  child: NoahLayerControls(
                    controller: _awareness,
                    onViewCoverage: () =>
                        _mapStateKey.currentState?.viewNoahCoverage(),
                    onRoadLegend: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (sheet) => RoadConditionsSheet(
                        onBrowseRoads: () {
                          Navigator.pop(sheet);
                          Navigator.of(context).pop();
                        },
                      ),
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
