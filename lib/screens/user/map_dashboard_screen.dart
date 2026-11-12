import '../../services/noah_awareness.dart';
import '../../widgets/noah_awareness_card.dart';
import '../../widgets/map_home_controls.dart';
import '../../utils/location_fix.dart';
import '../../services/pin_road_context.dart';
import '../../services/mapbox_place_search.dart';
import '../../widgets/local_map_search_results.dart';
import '../../services/map_load_state.dart';
import '../../widgets/map_status_banner.dart';
import 'road_list_screen.dart';
import '../../l10n/app_strings.dart';
import '../../config/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Visibility;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import 'report_submission_screen.dart';
import 'road_details_screen.dart';
import '../shared/settings_screen.dart';
import 'profile_screen.dart';
import '../../widgets/app_map.dart';
import '../../widgets/weather_map_overlay.dart';
import '../../widgets/weather_detail_sheet.dart';
import '../shared/full_screen_map_screen.dart';
import '../../utils/geo_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapDashboardScreen extends StatefulWidget {
  final ValueChanged<bool>? onRoadSelectionChanged;
  const MapDashboardScreen({super.key, this.onRoadSelectionChanged});

  @override
  MapDashboardScreenState createState() => MapDashboardScreenState();
}

class MapDashboardScreenState extends State<MapDashboardScreen> {
  final _awareness = NoahMapController();
  String? _selectedRoadId;
  MapboxMap? _mapboxMap;
  bool _isSearching = false;
  bool _searchBusy = false;
  bool _locating = false;
  int _searchGeneration = 0;
  final _areaSearchController = TextEditingController();
  final _mapStatus = MapLoadState();
  final _mapKey = GlobalKey<AppMapState>();
  bool get _cameraReady =>
      _mapboxMap != null && !_mapStatus.loading && _mapStatus.mapError == null;

  @override
  void dispose() {
    _searchGeneration++;
    _awareness.dispose();
    _mapStatus.dispose();
    _areaSearchController.dispose();
    super.dispose();
  }

  bool _isDetailsOpen = false;
  double _bottomInset = 0;
  double get _homeBottomInset => _selectedRoadId != null
      ? MediaQuery.viewPaddingOf(context).bottom
      : MediaQuery.paddingOf(context).bottom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshBottomInset();
  }

  void _refreshBottomInset() {
    final inset = _homeBottomInset;
    if (inset != _bottomInset) {
      _bottomInset = inset;
      _updateMapOrnaments();
    }
  }

  Future<void> _updateMapOrnaments() async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.logo.updateSettings(
        LogoSettings(marginBottom: _bottomInset + 8),
      );
      if (!mounted || !identical(map, _mapboxMap)) return;
      await map.attribution.updateSettings(
        AttributionSettings(marginBottom: _bottomInset + 8),
      );
    } catch (_) {
      // Native map recreation must not interrupt road selection.
    }
  }

  void clearRoadSelection() {
    setState(() => _selectedRoadId = null);
    _refreshBottomInset();
    widget.onRoadSelectionChanged?.call(false);
  }

  Future<void> _openRoadDetails(String roadId) async {
    setState(() {
      _selectedRoadId = roadId;
      _isDetailsOpen = true;
    });
    _refreshBottomInset();
    widget.onRoadSelectionChanged?.call(true);
    try {
      await Navigator.of(context).push(RoadDetailsScreen.route(roadId));
    } finally {
      if (mounted) {
        // Return to the selected road card. Only closing that card ends the
        // selection and brings back the resident navigation.
        setState(() => _isDetailsOpen = false);
      }
    }
  }

  static final String _mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  void _onMapCreated(MapboxMap map) {
    _mapboxMap = map;
    _updateMapOrnaments();
  }

  Future<void> _flyToMyLocation() async {
    if (!_cameraReady || _locating) return;
    setState(() => _locating = true);
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
        geo.Position? position = await geo.Geolocator.getLastKnownPosition();
        if (position == null ||
            !usableLocationFix(position, now: DateTime.now())) {
          position = await geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
        }
        if (!mounted || !_cameraReady) return;
        if (!usableLocationFix(position, now: DateTime.now())) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  context,
                  'A reliable location is not available yet. Try again with a clearer view of the sky.',
                ),
              ),
            ),
          );
          return;
        }
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(position.longitude, position.latitude),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Location permission denied.'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Location could not be updated. Check location access and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _flyToRoad(RoadStatus road) {
    if (!_cameraReady) return;
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

  void _handleRoadTapped(String roadId, Position? tappedPosition) async {
    if (!mounted || _isDetailsOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
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

    await _openRoadDetails(roadId);
  }

  Future<void> _searchAndHighlight(String query) async {
    final queryLower = query.trim().toLowerCase();
    if (queryLower.isEmpty || _searchBusy || _isDetailsOpen) return;
    FocusScope.of(context).unfocus();
    if (!_cameraReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'The map is not ready. Retry the map or browse roads.'),
          ),
        ),
      );
      return;
    }

    if (queryLower == AppEnvironment.area.name.toLowerCase() ||
        !AppEnvironment.isFieldTest &&
            const {
              'marulas',
              'brgy marulas',
              'marulas valenzuela',
            }.contains(queryLower)) {
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              AppEnvironment.area.longitude,
              AppEnvironment.area.latitude,
            ),
          ),
          zoom: 14.5,
        ),
        MapAnimationOptions(duration: 1000),
      );
      if (mounted) setState(() => _isSearching = false);
      return;
    }

    final appState = AppStateService.instance;

    // A query can match several streets or landmarks. Never silently pick
    // the first catalog entry for an ambiguous search.
    final choices = pinPlaceSuggestions(
      query,
      appState.roads,
      AppEnvironment.area,
      isInScope: (lat, lng) =>
          GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
    );
    if (choices.isNotEmpty) {
      final generation = ++_searchGeneration;
      final choice = await chooseLocalMapResult(context, choices);
      if (!mounted || generation != _searchGeneration || choice == null) return;
      if (!choice.landmark) {
        final road = appState.roads.where((r) => r.id == choice.id).firstOrNull;
        if (road == null) return;
        _flyToRoad(road);
        setState(() => _isSearching = false);
        await _openRoadDetails(road.id);
      } else {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(choice.lng, choice.lat)),
            zoom: 16.5,
            pitch: 50,
          ),
          MapAnimationOptions(duration: 1200),
        );
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(choice.title)));
      }
      return;
    }

    final generation = ++_searchGeneration;
    bool current() => mounted && generation == _searchGeneration;
    setState(() => _searchBusy = true);
    try {
      final places = await MapboxPlaceSearch.search(
        query: query,
        token: _mapboxToken,
        area: AppEnvironment.area,
        isInScope: (lat, lng) =>
            GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
      );
      if (!mounted || !current()) return;
      if (places.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'No places found within the selected study area.'),
            ),
          ),
        );
        return;
      }
      final options = [
        for (final place in places)
          PinPlaceSuggestion(
            id: place.id,
            title: place.name,
            subtitle: place.address,
            landmark: true,
            lat: place.lat,
            lng: place.lng,
          ),
      ];
      final choice = await chooseLocalMapResult(context, options);
      if (!mounted || !current() || choice == null || !_cameraReady) return;
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(choice.lng, choice.lat)),
          zoom: 16,
          pitch: 50,
        ),
        MapAnimationOptions(duration: 1200),
      );
      if (!mounted || !current()) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(choice.title)));
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Search unavailable. Check your connection and try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted && current()) setState(() => _searchBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;
    final weatherService = SimulatedWeatherService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, weatherService.listenable]),
      child: Stack(
        children: [
          Positioned.fill(
            child: AppMap(
              key: _mapKey,
              awareness: _awareness,
              selectedRoadId: _selectedRoadId,
              loadState: _mapStatus,
              showStatusBanner: false,
              onMapCreatedCallback: _onMapCreated,
              onRoadTapped: _handleRoadTapped,
            ),
          ),
          const Positioned.fill(child: WeatherMapOverlay()),
        ],
      ),
      builder: (context, map) {
        final selectedRoad = appState.roads
            .where((road) => road.id == _selectedRoadId)
            .firstOrNull;
        final user = appState.users
            .where((user) => user.id == FirebaseAuth.instance.currentUser?.uid)
            .firstOrNull;
        final weather = weatherService.currentState;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                if (map != null) map,
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: Visibility(
                    visible: !_isDetailsOpen,
                    maintainState: true,
                    child: SafeArea(
                      bottom: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              constraints.maxHeight *
                              (keyboardOpen ? .95 : .48),
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                MapStatusBanner(
                                  status: _mapStatus,
                                  onRetry: () =>
                                      _mapKey.currentState?.retryMap(),
                                ),
                                MapHomeHeader(
                                  photoUrl: user?.photoUrl,
                                  searching: _isSearching,
                                  busy: _searchBusy,
                                  controller: _areaSearchController,
                                  weatherLabel: tr(
                                    context,
                                    weatherService.getWeatherDescription(
                                      weather,
                                    ),
                                  ),
                                  weatherIcon: weatherService.getWeatherIcon(
                                    weather,
                                  ),
                                  severeWeather:
                                      weather == WeatherState.heavyRain ||
                                      weather == WeatherState.typhoon,
                                  onProfile: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const ProfileScreen(),
                                    ),
                                  ),
                                  onSettings: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                                  onStartSearch: () {
                                    clearRoadSelection();
                                    setState(() => _isSearching = true);
                                  },
                                  onCloseSearch: () {
                                    _searchGeneration++;
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _isSearching = false;
                                      _searchBusy = false;
                                    });
                                  },
                                  onSearch: () => _searchAndHighlight(
                                    _areaSearchController.text,
                                  ),
                                  onWeather: () => _showWeatherStatsBottomSheet(
                                    context,
                                    weatherService,
                                    weather,
                                  ),
                                  onWeatherInfo: () =>
                                      _showSevereWeatherInfo(context, weather),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: NoahLayerControls(
                                    controller: _awareness,
                                    onViewCoverage: () => _mapKey.currentState
                                        ?.viewNoahCoverage(),
                                    onRoadLegend: () => showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      builder: (sheet) => RoadConditionsSheet(
                                        onBrowseRoads: () async {
                                          Navigator.pop(sheet);
                                          final roadId =
                                              await Navigator.of(
                                                context,
                                              ).push<String>(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const RoadListScreen(),
                                                ),
                                              );
                                          if (mounted && roadId != null) {
                                            _handleRoadTapped(roadId, null);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_isDetailsOpen && !keyboardOpen)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16 + _homeBottomInset,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            constraints.maxHeight *
                            (selectedRoad == null ||
                                    MediaQuery.textScalerOf(context).scale(14) >
                                        20
                                ? .45
                                : .6),
                      ),
                      child: MapHomeBottomOverlay(
                        actions: ListenableBuilder(
                          listenable: _mapStatus,
                          builder: (context, _) => MapQuickActions(
                            canLocate: _cameraReady,
                            horizontal:
                                selectedRoad != null ||
                                constraints.maxHeight < 640 ||
                                MediaQuery.textScalerOf(context).scale(14) > 20,
                            locating: _locating,
                            onLocate: _flyToMyLocation,
                            onFullscreen: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FullScreenMapScreen(),
                              ),
                            ),
                            onReport: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportSubmissionScreen(
                                  prefilledRoadId: selectedRoad?.id,
                                ),
                              ),
                            ),
                          ),
                        ),
                        preview: selectedRoad == null
                            ? null
                            : MapRoadPreview(
                                road: selectedRoad,
                                weather: weather,
                                onOpen: () =>
                                    _handleRoadTapped(selectedRoad.id, null),
                                onDismiss: clearRoadSelection,
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

  void _showSevereWeatherInfo(BuildContext context, WeatherState weather) {
    final severe = weather == WeatherState.typhoon;
    final title = AppEnvironment.sparkCoreEnabled
        ? 'SEVERE WEATHER ESTIMATE'
        : severe
        ? 'TYPHOON ALERT'
        : 'HEAVY RAIN ALERT';
    final message = AppEnvironment.sparkCoreEnabled
        ? 'Weather estimates do not confirm flooding on a particular road. Check current road updates before travel.'
        : severe
        ? 'Roads may be impassable. Seek safe shelter immediately.'
        : 'Flooding possible. Vulnerable roads may be auto-escalated.';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr(context, title)),
        content: Text(tr(context, message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'OK')),
          ),
        ],
      ),
    );
  }

  void _showWeatherStatsBottomSheet(
    BuildContext context,
    SimulatedWeatherService weatherService,
    WeatherState weatherState,
  ) {
    WeatherDetailSheet.show(
      context,
      weatherService: weatherService,
      weatherState: weatherState,
    );
  }
}
