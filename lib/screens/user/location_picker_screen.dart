import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../config/app_environment.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/app_map.dart';
import '../../widgets/planner_pin_card.dart';
import '../../services/pin_road_context.dart';
import '../../services/mapbox_place_search.dart';
import '../../widgets/local_map_search_results.dart';
import '../../services/weather_service.dart';
import '../../services/map_load_state.dart';
import '../../widgets/map_status_banner.dart';
import '../../utils/location_fix.dart';
import '../../services/pin_selection_state.dart';
import '../../widgets/planner_pin_suggestions.dart';

class LocationPickerScreen extends StatefulWidget {
  final bool forRouting;
  final bool forOrigin;
  final Position? initialPosition;
  final String? placeName;
  final String? instructions;
  const LocationPickerScreen({
    super.key,
    this.forRouting = false,
    this.forOrigin = false,
    this.initialPosition,
    this.placeName,
    this.instructions,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  MapboxMap? _mapboxMap;
  static final String _publicToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isConfirming = false;
  bool _locating = false;
  late final PinSelectionState _selection;
  bool get _pinMoving => _selection.moving;
  int get _pinRevision => _selection.revision;
  Position? get _pin => _selection.point == null
      ? null
      : Position(_selection.point!.lng, _selection.point!.lat);
  int _pinIntent = 0;
  bool _suggestionsVisible = false;
  String? _chosenPlaceName;
  ScreenCoordinate? _pinPixel;
  MbxEdgeInsets? _cameraPadding;
  String? _viewportSignature;
  final _routingMapKey = GlobalKey<AppMapState>();
  final _mapStatus = MapLoadState();

  @override
  void dispose() {
    _selection.dispose();
    _mapStatus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _chosenPlaceName = widget.placeName;
    _selection = PinSelectionState(
      readPoint: () async {
        final map = _mapboxMap;
        final pixel = _pinPixel;
        if (map == null || pixel == null) throw StateError('Map not ready');
        final point = await map.coordinateForPixel(pixel);
        return GeoCoord(
          point.coordinates.lat.toDouble(),
          point.coordinates.lng.toDouble(),
        );
      },
    )..addListener(_onSelectionUpdated);
    MapboxOptions.setAccessToken(_publicToken);
  }

  void _onSelectionUpdated() {
    if (mounted) setState(() {});
  }

  void _onCameraChanged(CameraState camera) {
    _selection.cameraChanged(
      jsonEncode([
        camera.center.coordinates.lng.toStringAsFixed(8),
        camera.center.coordinates.lat.toStringAsFixed(8),
        camera.zoom.toStringAsFixed(4),
        camera.pitch.toStringAsFixed(3),
        camera.bearing.toStringAsFixed(3),
        camera.padding.top.toStringAsFixed(1),
        camera.padding.bottom.toStringAsFixed(1),
        camera.padding.left.toStringAsFixed(1),
        camera.padding.right.toStringAsFixed(1),
      ]),
    );
  }

  Future<void> _readPin() => _selection.refresh();

  void _configureViewport(BoxConstraints bounds) {
    final bottom =
        (MediaQuery.sizeOf(context).height * .45 +
                MediaQuery.viewPaddingOf(context).bottom +
                20)
            .clamp(0.0, (bounds.maxHeight - 150).clamp(0.0, double.infinity));
    const top = 110.0;
    _pinPixel = ScreenCoordinate(
      x: bounds.maxWidth / 2,
      y: (top + (bounds.maxHeight - top - bottom) / 2).clamp(
        24.0,
        bounds.maxHeight,
      ),
    );
    _cameraPadding = MbxEdgeInsets(top: top, left: 0, right: 0, bottom: bottom);
    final signature = '${bounds.maxWidth}:${bounds.maxHeight}:$bottom';
    if (_viewportSignature == signature) return;
    _viewportSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final map = _mapboxMap;
      if (!mounted || map == null || signature != _viewportSignature) return;
      _selection.cameraChanged('viewport:$signature');
      try {
        await map.setCamera(CameraOptions(padding: _cameraPadding));
        await map.logo.updateSettings(LogoSettings(marginBottom: bottom + 8));
        await map.attribution.updateSettings(
          AttributionSettings(marginBottom: bottom + 8),
        );
        if (mounted && identical(map, _mapboxMap)) _readPin();
      } catch (_) {
        if (mounted) _readPin();
      }
    });
  }

  List<PinPlaceSuggestion> _localSuggestions() => pinPlaceSuggestions(
    _searchController.text,
    AppStateService.instance.roads,
    AppEnvironment.area,
    isInScope: (lat, lng) =>
        GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
  );

  Future<void> _selectSuggestion(PinPlaceSuggestion item) async {
    final map = _mapboxMap;
    if (map == null || _isConfirming) return;
    _pinIntent++;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _suggestionsVisible = false;
      _searchController.text = item.title;
      _chosenPlaceName = item.title;
    });
    _selection.cameraChanged('choice:$_pinIntent');
    try {
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(item.lng, item.lat)),
          zoom: 17,
        ),
        MapAnimationOptions(duration: 600),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _chosenPlaceName = null);
        _selection.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Could not move the map. Please retry.')),
          ),
        );
      }
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      await mapboxMap.scaleBar.updateSettings(
        ScaleBarSettings(isMetricUnits: true),
      );
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    } catch (e) {
      debugPrint('Error enabling location puck: $e');
    }

    // The initial camera already uses the chosen pin. A late camera animation
    // here could overwrite a pin the user moved while location setup awaited.
  }

  Future<void> _confirmLocation() async {
    if (_mapboxMap == null || _isConfirming) return;
    if (widget.forRouting &&
        (!_selection.canConfirm ||
            _mapStatus.loading ||
            _mapStatus.mapError != null))
      return;
    final revision = _pinRevision;
    setState(() => _isConfirming = true);
    try {
      final point = widget.forRouting
          ? await _mapboxMap!
                .coordinateForPixel(_pinPixel!)
                .timeout(const Duration(seconds: 5))
          : (await _mapboxMap!.getCameraState().timeout(
              const Duration(seconds: 5),
            )).center;
      final lat = point.coordinates.lat.toDouble();
      final lng = point.coordinates.lng.toDouble();
      if (!lat.isFinite || !lng.isFinite)
        throw const FormatException('Invalid pin');

      // Pin-to-Road Snapping logic using GeoUtils
      String? nearestRoadId;
      double minGlobalDistance = double.infinity;

      if (widget.forRouting) {
        final nearest = nearestPinRoad(
          AppStateService.instance.roads,
          lat,
          lng,
        );
        nearestRoadId = nearest?.road.id;
        minGlobalDistance = nearest?.meters ?? double.infinity;
      }
      for (var road
          in widget.forRouting
              ? <RoadStatus>[]
              : AppStateService.instance.roads) {
        if (road.geometry == null) continue;
        final geoPts = GeoUtils.extractPoints(road.geometry);
        if (geoPts.isEmpty) continue;

        for (int i = 0; i < geoPts.length; i++) {
          final p = geoPts[i];
          final dist = geo.Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
          if (dist < minGlobalDistance) {
            minGlobalDistance = dist;
            nearestRoadId = road.id;
          }

          if (i < geoPts.length - 1) {
            final pNext = geoPts[i + 1];
            final segDist = GeoUtils.pointToSegmentDistanceMeters(
              lng,
              lat,
              p.lng,
              p.lat,
              pNext.lng,
              pNext.lat,
            );
            if (segDist < minGlobalDistance) {
              minGlobalDistance = segDist;
              nearestRoadId = road.id;
            }
          }
        }
      }

      if (widget.forRouting) {
        if (!GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80.0)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  context,
                  'Pinned location is outside the selected study area scope. Please select a point within the selected study area.',
                ),
              ),
              backgroundColor: AppPalette.of(context).error,
            ),
          );
          return;
        }

        String placeTitle = _chosenPlaceName ?? 'Pinned Location';
        if (_chosenPlaceName == null)
          try {
            final revUrl = Uri.parse(
              'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
              '?access_token=$_publicToken&limit=1',
            );
            final res = await http
                .get(revUrl)
                .timeout(const Duration(seconds: 4));
            if (res.statusCode == 200) {
              final data = json.decode(res.body);
              if (data['features'] != null &&
                  (data['features'] as List).isNotEmpty) {
                final feature = data['features'][0];
                placeTitle =
                    feature['text'] ??
                    feature['place_name'] ??
                    'Pinned Location';
              }
            }
          } catch (_) {}

        if (!mounted || revision != _pinRevision || _pinMoving) return;
        Navigator.of(context).pop({
          'lat': lat,
          'lng': lng,
          'roadId': nearestRoadId,
          'placeName': placeTitle,
        });
        return;
      }

      // Must be within 500 meters of a monitored road
      if (minGlobalDistance > 500 ||
          nearestRoadId == null ||
          !GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80.0)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Pin is too far from any monitored road in the selected study area. Please place it closer to a valid road.',
              ),
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pop({'lat': lat, 'lng': lng, 'roadId': nearestRoadId});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Could not read the selected location. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty ||
        _mapboxMap == null ||
        _isSearching ||
        _isConfirming)
      return;
    if (widget.forRouting) {
      final choices = _localSuggestions();
      if (choices.isNotEmpty) {
        if (choices.length == 1) {
          await _selectSuggestion(choices.single);
        } else {
          setState(() => _suggestionsVisible = true);
        }
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final intent = ++_pinIntent;

    setState(() {
      _isSearching = true;
      if (widget.forRouting) _chosenPlaceName = null;
    });

    // 1. Check local Marulas Landmarks Catalog
    final landmarkMatches = AppEnvironment.area.searchLandmarks(query);
    if (!widget.forRouting && landmarkMatches.isNotEmpty) {
      final landmark = landmarkMatches.first;
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(landmark.lng, landmark.lat)),
          zoom: 16.5,
        ),
        MapAnimationOptions(duration: 1000),
      );
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Landmark found: ${landmark.name}')),
        );
      }
      return;
    }

    // Named places use the same POI-capable lookup as planner and home.
    try {
      final places = await MapboxPlaceSearch.search(
        query: query,
        token: _publicToken,
        area: AppEnvironment.area,
        isInScope: (lat, lng) =>
            GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
      );
      if (!mounted || intent != _pinIntent) return;
      if (places.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'Location not found in the selected study area.'),
            ),
          ),
        );
        return;
      }
      final choice = await chooseLocalMapResult(context, [
        for (final place in places)
          PinPlaceSuggestion(
            id: place.id,
            title: place.name,
            subtitle: place.address,
            landmark: true,
            lat: place.lat,
            lng: place.lng,
          ),
      ]);
      if (!mounted || intent != _pinIntent || choice == null) return;
      if (widget.forRouting) {
        await _selectSuggestion(choice);
      } else {
        await _mapboxMap?.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(choice.lng, choice.lat)),
            zoom: 16,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'Search could not finish. Please try again.'),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _flyToMyLocation() async {
    if (_mapboxMap == null || _locating || _isConfirming) return;
    final intent = ++_pinIntent;
    setState(() {
      _locating = true;
      _chosenPlaceName = null;
      _suggestionsVisible = false;
    });
    try {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Location services disabled.'))),
        );
        return;
      }
      geo.LocationPermission permission =
          await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.whileInUse ||
          permission == geo.LocationPermission.always) {
        geo.Position? position;
        try {
          position = await geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
        } catch (e) {
          position = await geo.Geolocator.getLastKnownPosition();
          if (position == null) rethrow;
          if (DateTime.now().difference(position.timestamp).inMinutes > 5) {
            throw Exception('GPS_STALE');
          }
        }
        if (!mounted || _mapboxMap == null) return;
        if (widget.forRouting && intent != _pinIntent) return;
        if (widget.forRouting &&
            !usableLocationFix(position, now: DateTime.now())) {
          throw StateError('Unreliable GPS fix');
        }
        _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(position.longitude, position.latitude),
            ),
            zoom: 16.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Location permission denied.'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'GPS unavailable — please pick a location on the map.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.forRouting) return _buildRoutingPicker(context);
    return Scaffold(
      appBar: AppTopBar(
        title: widget.placeName ?? tr(context, 'Pin Location'),
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
              center: Point(
                coordinates:
                    widget.initialPosition ??
                    Position(
                      AppEnvironment.area.longitude,
                      AppEnvironment.area.latitude,
                    ),
              ), // Brgy. Marulas
              zoom: widget.initialPosition == null ? 15.0 : 16.0,
            ),
          ),

          // Center Pin Overlay
          Center(
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: 40.0,
              ), // offset for pin tail
              child: Icon(
                Icons.location_on,
                size: 50,
                color: AppPalette.of(context).error,
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.of(
                      context,
                    ).surface.withValues(alpha: 0.9),
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
                      Icon(
                        Icons.info_outline,
                        color: AppPalette.of(context).primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr(
                            context,
                            widget.instructions ??
                                'Drag the map or search to place the pin.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.of(context).onSurface,
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
                    color: AppPalette.of(context).surface,
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
                      hintText: tr(
                        context,
                        'Search for a street or landmark...',
                      ),
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppPalette.of(
                          context,
                        ).onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppPalette.of(context).primary,
                      ),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onPressed: () =>
                                  _searchLocation(_searchController.text),
                              color: AppPalette.of(context).primary,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
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
                color: AppPalette.of(context).surface,
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
                icon: Icon(
                  Icons.my_location,
                  color: AppPalette.of(context).primary,
                ),
                tooltip: tr(context, 'My Location'),
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
                    color: AppPalette.of(
                      context,
                    ).primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isConfirming ? null : _confirmLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.of(context).primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  tr(
                    context,
                    _isConfirming
                        ? 'Confirming location...'
                        : 'CONFIRM LOCATION',
                  ),
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.of(context).onPrimary,
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

  Widget _buildRoutingPicker(BuildContext context) {
    final p = AppPalette.of(context);
    final state = AppStateService.instance;
    final weather = SimulatedWeatherService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([state, weather.listenable]),
      builder: (context, _) {
        final pin = _pin;
        final nearest = pin == null
            ? null
            : nearestPinRoad(
                state.roads,
                pin.lat.toDouble(),
                pin.lng.toDouble(),
              );
        final inside =
            pin == null ||
            GeoUtils.isInsideStudyArea(
              pin.lat.toDouble(),
              pin.lng.toDouble(),
              bufferMeters: 80,
            );
        return Scaffold(
          extendBody: true,
          resizeToAvoidBottomInset: false,
          backgroundColor: p.surface,
          appBar: AppTopBar(
            title: tr(
              context,
              widget.forOrigin ? 'Choose starting point' : 'Choose destination',
            ),
            showBackButton: true,
            showProfile: false,
            showSettingsAction: false,
          ),
          body: LayoutBuilder(
            builder: (context, bounds) {
              _configureViewport(bounds);
              return Stack(
                fit: StackFit.expand,
                children: [
                  AppMap(
                    key: _routingMapKey,
                    loadState: _mapStatus,
                    showStatusBanner: false,
                    initialCenter: widget.initialPosition,
                    initialCameraPadding: _cameraPadding,
                    selectedRoadId:
                        !_pinMoving && nearest != null && nearest.meters <= 40
                        ? nearest.road.id
                        : null,
                    onMapCreatedCallback: (map) async {
                      _mapboxMap = map;
                      try {
                        await map.logo.updateSettings(
                          LogoSettings(
                            marginBottom: (_cameraPadding?.bottom ?? 0) + 8,
                          ),
                        );
                        if (!mounted || !identical(map, _mapboxMap)) return;
                        await map.attribution.updateSettings(
                          AttributionSettings(
                            marginBottom: (_cameraPadding?.bottom ?? 0) + 8,
                          ),
                        );
                      } catch (_) {
                        /* Optional ornaments do not block pin selection. */
                      }
                      if (mounted && identical(map, _mapboxMap)) _readPin();
                    },
                    onCameraChanged: _onCameraChanged,
                    onCameraIdle: _readPin,
                    onUserPan: () {
                      _pinIntent++;
                      if (_chosenPlaceName != null || _suggestionsVisible) {
                        setState(() {
                          _chosenPlaceName = null;
                          _suggestionsVisible = false;
                        });
                      }
                    },
                    onRoadTapped: (_, position) {
                      if (position != null && !_isConfirming) {
                        _pinIntent++;
                        setState(() {
                          _chosenPlaceName = null;
                          _suggestionsVisible = false;
                        });
                        _mapboxMap?.flyTo(
                          CameraOptions(center: Point(coordinates: position)),
                          MapAnimationOptions(duration: 350),
                        );
                      }
                    },
                  ),
                  Positioned(
                    top: _pinPixel!.y - 48,
                    left: _pinPixel!.x - 24,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.location_pin,
                        size: 48,
                        color: p.primary,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: p.outlineVariant.withValues(alpha: .5),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onChanged: (query) => setState(
                              () => _suggestionsVisible =
                                  query.trim().length >= 2,
                            ),
                            onSubmitted: _isSearching || _isConfirming
                                ? null
                                : _searchLocation,
                            decoration: InputDecoration(
                              hintText: tr(context, 'Find a road or place'),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _isSearching
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: tr(context, 'Search'),
                                      onPressed: _isConfirming
                                          ? null
                                          : () => _searchLocation(
                                              _searchController.text,
                                            ),
                                      icon: const Icon(Icons.arrow_forward),
                                    ),
                            ),
                          ),
                          if (_suggestionsVisible)
                            PlannerPinSuggestions(
                              items: _localSuggestions(),
                              onSelected: _selectSuggestion,
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              tr(
                                context,
                                widget.instructions ??
                                    'Move the map to position the pin.',
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          MapStatusBanner(
                            status: _mapStatus,
                            onRetry: () =>
                                _routingMapKey.currentState?.retryMap(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: (_cameraPadding?.bottom ?? 0) + 16,
                    right: 16,
                    child: Material(
                      color: p.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: p.outlineVariant.withValues(alpha: .5),
                        ),
                      ),
                      child: IconButton(
                        tooltip: tr(context, 'Use current GPS location'),
                        onPressed: _isConfirming || _locating
                            ? null
                            : _flyToMyLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(Icons.my_location, color: p.primary),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .45,
                    ),
                    child: ListenableBuilder(
                      listenable: _mapStatus,
                      builder: (context, _) => PlannerPinCard(
                        forOrigin: widget.forOrigin,
                        moving: _pinMoving,
                        confirming: _isConfirming,
                        insideArea: inside,
                        roadsLive: state.syncHealth.roadsLive,
                        weather: weather.currentState,
                        match: nearest,
                        placeName: _chosenPlaceName,
                        pinUnavailable: _selection.failed,
                        onRetry: _readPin,
                        onConfirm:
                            !_selection.canConfirm ||
                                _locating ||
                                _isSearching ||
                                _mapboxMap == null ||
                                _mapStatus.loading ||
                                _mapStatus.mapError != null
                            ? null
                            : _confirmLocation,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
