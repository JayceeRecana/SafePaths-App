import '../../widgets/route_navigation.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../config/app_environment.dart';
import '../../data/marulas_landmarks.dart';
import '../../data/marulas_evacuation_sites.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../widgets/app_map.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/planner_route_card.dart';
import '../../widgets/planner_travel_selector.dart';
import '../../services/weather_service.dart';
import '../../services/routing_service.dart';
import '../../services/app_state_service.dart';
import '../../services/mapbox_place_search.dart';
import '../../models/planned_route.dart';
import '../../utils/geo_utils.dart';
import '../../utils/place_search.dart';
import 'route_preview_screen.dart';
import 'location_picker_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  final Position? prefilledDestination;
  final String? prefilledName;
  // Replace platform/provider boundaries for real-screen regression tests.
  final Future<Position?> Function()? locate;
  final DirectionsFetcher? directionsFetcher;
  final Future<List<MapboxPlace>> Function(String, List<String>)? placeLookup;
  final Future<Position?> Function(BuildContext, MarulasLandmark)?
  quickDestinationPicker;
  final Widget Function(List<Position>)? routeMapBuilder;
  final List<MarulasLandmark>? quickLandmarks;

  const RoutePlannerScreen({
    super.key,
    this.prefilledDestination,
    this.prefilledName,
    this.locate,
    this.directionsFetcher,
    this.placeLookup,
    this.quickDestinationPicker,
    this.routeMapBuilder,
    this.quickLandmarks,
  });

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final RoutingService _routingService = RoutingService.instance;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _lookupController = TextEditingController();

  Timer? _debounce;
  int _searchId = 0;
  String? _searchMessage;
  List<Map<String, dynamic>> _destinationSuggestions = [];
  bool _isSearching = false;
  final _searchUpdates = ValueNotifier<int>(0);
  final _searchFocus = FocusNode();
  bool _destinationSearchOpen = false;
  BuildContext? _destinationSearchContext;
  int? _session;
  bool _openingNavigation = false;
  QuickDestinationCategory? _quickCategory;
  String? _resolvingSite;
  bool _confirmingQuickDestination = false;
  MapboxMap? _previewMap;
  void _beginPlanning({Position? prefillDestination, String? name}) {
    _session = _routingService.startPlanning(
      prefillDestination: prefillDestination,
      name: name,
      locate: widget.locate,
    );
  }

  Future<void> _navigate(PlannedRoute route) async {
    if (_openingNavigation) return;
    _openingNavigation = true;
    try {
      await startRouteNavigation(context, route);
    } finally {
      _openingNavigation = false;
    }
  }

  void _update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _searchUpdates.value++;
  }

  Future<void> _openDestinationSearch() async {
    if (_destinationSearchOpen) return;
    _destinationSearchOpen = true;
    if (_lookupController.text.trim().isNotEmpty && _quickCategory == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _destinationSearchOpen)
          _onSearchChanged(_lookupController.text);
      });
    }
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (routeContext) {
            _destinationSearchContext = routeContext;
            return ValueListenableBuilder<int>(
              valueListenable: _searchUpdates,
              builder: (context, _, child) => _buildDestinationSearch(context),
            );
          },
        ),
      );
    } finally {
      _destinationSearchOpen = false;
      _destinationSearchContext = null;
      _debounce?.cancel();
      _searchId++;
      if (mounted)
        _update(() {
          _isSearching = false;
          _resolvingSite = null;
          _destinationSuggestions = [];
          _quickCategory = null;
          _searchMessage = null;
        });
    }
  }

  void _closeDestinationSearchIfChosen(Position? previous) {
    final screen = _destinationSearchContext;
    if (_routingService.destinationPoint != null &&
        !identical(_routingService.destinationPoint, previous) &&
        screen != null &&
        screen.mounted &&
        ModalRoute.of(screen)?.isCurrent == true) {
      _lookupController.clear();
      Navigator.of(screen).pop();
    }
  }

  Future<void> _chooseSearchResult(Map<String, dynamic> feature) async {
    final previous = _routingService.destinationPoint;
    await _selectDestination(feature);
    if (mounted) _closeDestinationSearchIfChosen(previous);
  }

  // Retrieve the mapbox token from environment
  final String _mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  @override
  void initState() {
    super.initState();
    _routingService.addListener(_onRoutingStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _beginPlanning(
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
    if (_session == _routingService.planningSessionId)
      _routingService.exitPlanning(notify: false);
    _searchFocus.dispose();
    _searchUpdates.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _lookupController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onRoutingStateChanged() {
    if (mounted) _update(() {});
  }

  void _onSearchChanged(String query) {
    _quickCategory = null;
    _resolvingSite = null;
    _destinationSuggestions = [];
    if (!_destinationSearchOpen) _routingService.clearDestination();
    _searchId++;
    _searchMessage = null;
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().length < 2) {
      _update(() {
        _destinationSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    _update(() {
      _isSearching = true;
    });

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchSuggestions(query.trim());
    });
  }

  void _showQuickDestinations(QuickDestinationCategory category, String label) {
    _debounce?.cancel();
    _searchId++;
    _resolvingSite = null;
    if (!_destinationSearchOpen) _routingService.clearDestination();
    if (_destinationSearchOpen)
      _lookupController.clear();
    else
      _destinationController.clear();
    FocusScope.of(context).unfocus();
    final places = MarulasLandmarksCatalog.quickDestinations(
      category,
      widget.quickLandmarks ?? AppEnvironment.area.landmarks,
      isInScope: (lat, lng) =>
          GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
    );
    final listedEvacuationSites =
        category == QuickDestinationCategory.evacuationCenters &&
            widget.quickLandmarks == null &&
            !AppEnvironment.isFieldTest
        ? MarulasEvacuationSites.names
        : const <String>[];
    _update(() {
      _quickCategory = category;
      _isSearching = false;
      _destinationSuggestions = [
        for (final place in places)
          {...place.toFeatureMap(), 'quickDestination': place},
        for (final name in listedEvacuationSites)
          {
            'text': name,
            'category': 'Evacuation site',
            'place_name': MarulasEvacuationSites.removedNames.contains(name)
                ? 'Reported removed; directions unavailable'
                : 'LGU-listed site; find its mapped location',
            'icon': Icons.home_work_outlined,
            'routingUnavailable': MarulasEvacuationSites.removedNames.contains(
              name,
            ),
            'listedSite': name,
          },
      ];
      _searchMessage = listedEvacuationSites.isNotEmpty
          ? 'Choose a listed site to find its mapped location. Map pins do not confirm an entrance or that the site is open.'
          : places.isEmpty
          ? 'No confirmed catalog locations in this category for ${AppEnvironment.area.name}. Choose a known destination pin on the map; confirm emergency availability locally.'
          : '$label: choose a listed place, then review its mapped location. Location and availability need local confirmation.';
    });
  }

  Future<void> _confirmQuickDestination(MarulasLandmark place) async {
    if (_confirmingQuickDestination) return;
    _confirmingQuickDestination = true;
    final request = ++_searchId;
    final session = _routingService.planningSessionId;
    try {
      final Position? point;
      if (widget.quickDestinationPicker != null) {
        point = await widget.quickDestinationPicker!(context, place);
      } else {
        final result = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => LocationPickerScreen(
              forRouting: true,
              initialPosition: Position(place.lng, place.lat),
              placeName: place.name,
              instructions:
                  'Review the mapped location for ${place.name}. This is not a verified entrance. Check access and current availability locally.',
            ),
          ),
        );
        final lat = result?['lat'], lng = result?['lng'];
        point = lat is num && lng is num ? Position(lng, lat) : null;
      }
      if (!mounted ||
          request != _searchId ||
          session != _routingService.planningSessionId ||
          point == null)
        return;
      if (!RoutingService.validRoutePoint(point) ||
          !GeoUtils.isInsideStudyArea(
            point.lat.toDouble(),
            point.lng.toDouble(),
            bufferMeters: 80,
          )) {
        _update(
          () => _searchMessage =
              'The confirmed pin must be within the selected study area. Choose the entrance again.',
        );
        return;
      }
      _update(() {
        _destinationController.text = place.name;
        _destinationSuggestions = [];
        _quickCategory = null;
        _searchMessage = null;
      });
      _routingService.setDestination(
        point,
        place.name,
        directionsFetcher: widget.directionsFetcher,
      );
    } catch (_) {
      if (mounted && request == _searchId) {
        _update(
          () => _searchMessage =
              'Could not confirm this destination. Please retry or choose a pin on the map.',
        );
      }
    } finally {
      _confirmingQuickDestination = false;
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    final requestId = ++_searchId;

    List<Map<String, dynamic>> combinedMatches = [];

    // Listed sites are resolved live rather than reusing uncorroborated legacy pins.
    if (!AppEnvironment.isFieldTest) {
      for (final name in MarulasEvacuationSites.names) {
        if (matchesPlaceSearch(query, [
          name,
          'evacuation center',
          'evac center',
        ], ignoreAreaWords: true)) {
          combinedMatches.add({
            'text': name,
            'category': 'Evacuation site',
            'listedSite': name,
            'place_name': 'LGU-listed site; find its mapped location',
            'icon': Icons.home_work_outlined,
          });
        }
      }
    }

    // 1. Search local Barangay Marulas Landmarks Catalog (First priority - high precision POIs)
    final localLandmarks = AppEnvironment.area.searchLandmarks(query);
    for (var landmark in localLandmarks) {
      if (!GeoUtils.isInsideStudyArea(
        landmark.lat,
        landmark.lng,
        bufferMeters: 80,
      ))
        continue;
      if (!combinedMatches.any((m) => m['id'] == landmark.id)) {
        combinedMatches.add({
          ...landmark.toFeatureMap(),
          'quickDestination': landmark,
        });
      }
    }

    // 2. Search Monitored Firestore Roads Network (Admin Imported Streets)
    final appStateRoads = AppStateService.instance.roads;
    for (var road in appStateRoads) {
      if (road.name.isNotEmpty &&
          matchesPlaceSearch(query, [road.name], ignoreAreaWords: true)) {
        GeoCoord? center;
        try {
          center = GeoUtils.getRoadCenter(road.geometry);
        } catch (_) {
          continue;
        }
        if (center != null &&
            GeoUtils.isInsideStudyArea(
              center.lat,
              center.lng,
              bufferMeters: 80,
            )) {
          final roadName = road.name;
          if (!combinedMatches.any((m) => m['roadId'] == road.id)) {
            combinedMatches.add({
              'roadId': road.id,
              'text': roadName,
              'place_name': '$roadName, ${AppEnvironment.area.name}',
              'category': 'Monitored Street',
              'center': [center.lng, center.lat],
              'icon': Icons.add_road_rounded,
            });
          }
        }
      }
    }

    if (combinedMatches.isNotEmpty) {
      _update(() {
        _destinationSuggestions = combinedMatches.take(10).toList();
        _isSearching = false;
      });
      return;
    }

    bool remoteUnavailable = false;
    try {
      final places = await _lookupPlaces(query);
      combinedMatches.addAll(
        places.map(
          (place) => {
            ...place.toFeatureMap(),
            'icon': Icons.location_on_outlined,
          },
        ),
      );
    } catch (_) {
      remoteUnavailable = true;
    }

    if (!mounted || requestId != _searchId) return;
    // Public Nominatim does not permit client-side autocomplete. Local
    // results and the configured provider are the search-as-you-type sources.
    if (mounted && requestId == _searchId) {
      _update(() {
        _searchMessage = combinedMatches.isEmpty
            ? remoteUnavailable
                  ? 'Map search is unavailable. Try again or choose on the map.'
                  : 'No matches found. Try another name or choose on the map.'
            : null;
        _destinationSuggestions = combinedMatches.take(10).toList();
        _isSearching = false;
      });
    }
  }

  Future<List<MapboxPlace>> _lookupPlaces(
    String query, {
    List<String> expectedNames = const [],
  }) =>
      widget.placeLookup?.call(query, expectedNames) ??
      MapboxPlaceSearch.search(
        query: query,
        token: _mapboxToken,
        area: AppEnvironment.area,
        expectedNames: expectedNames,
        isInScope: (lat, lng) =>
            GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80),
      );

  Future<void> _resolveListedSite(String name) async {
    if (_resolvingSite != null ||
        MarulasEvacuationSites.removedNames.contains(name))
      return;
    final request = ++_searchId, session = _routingService.planningSessionId;
    _update(() {
      _resolvingSite = name;
      _isSearching = true;
      _searchMessage = null;
    });
    try {
      final places = await _lookupPlaces(
        name,
        expectedNames: MarulasEvacuationSites.searchNames(name),
      );
      if (!mounted ||
          request != _searchId ||
          session != _routingService.planningSessionId)
        return;
      _update(() {
        _resolvingSite = null;
        _isSearching = false;
      });
      if (places.isEmpty) {
        _update(
          () => _searchMessage =
              'No matching mapped site was found. Try another name or choose a known location on the map.',
        );
        return;
      }
      MarulasLandmark mapped(MapboxPlace place) => MarulasLandmark(
        id: place.id,
        name: name,
        category: 'LGU-listed evacuation site',
        address: place.address,
        lat: place.lat,
        lng: place.lng,
        tags: const [],
      );
      if (places.length == 1) {
        await _confirmQuickDestination(mapped(places.single));
      } else {
        _update(() {
          _destinationSuggestions = [
            for (final place in places)
              {
                ...place.toFeatureMap(),
                'quickDestination': mapped(place),
                'icon': Icons.place_outlined,
              },
          ];
          _searchMessage =
              'Several mapped locations match. Choose one and review its position.';
        });
      }
    } catch (_) {
      if (mounted && request == _searchId) {
        _update(
          () => _searchMessage =
              'Map search is unavailable. Try again or choose on the map.',
        );
      }
    } finally {
      if (mounted && request == _searchId)
        _update(() {
          _resolvingSite = null;
          _isSearching = false;
        });
    }
  }

  Future<void> _selectDestination(Map<String, dynamic> feature) async {
    if (feature['routingUnavailable'] == true) return;
    if (feature['listedSite'] is String) {
      await _resolveListedSite(feature['listedSite'] as String);
      return;
    }
    final quick = feature['quickDestination'];
    if (quick is MarulasLandmark) {
      await _confirmQuickDestination(quick);
      return;
    }
    _debounce?.cancel();
    _searchId++;
    _isSearching = false;
    _searchMessage = null;
    final placeName = feature['place_name'] as String?;
    final center = feature['center'] as List?;

    if (placeName != null && center != null && center.length >= 2) {
      final lon = (center[0] as num).toDouble();
      final lat = (center[1] as num).toDouble();

      if (!RoutingService.validRoutePoint(Position(lon, lat)) ||
          !GeoUtils.isInsideStudyArea(lat, lon, bufferMeters: 80.0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  context,
                  'Selected location is outside the selected study area scope.',
                ),
              ),
              backgroundColor: AppPalette.of(context).error,
            ),
          );
        }
        return;
      }

      _update(() {
        _destinationController.text =
            feature['text'] ?? placeName; // Set short name if available
        _destinationSuggestions = []; // Hide suggestions
        FocusScope.of(context).unfocus(); // Close keyboard
      });

      _routingService.setDestination(
        Position(lon, lat),
        placeName,
        directionsFetcher: widget.directionsFetcher,
      );
    }
  }

  Future<void> _pickLocationOnMap({bool forOrigin = false}) async {
    _debounce?.cancel();
    _searchId++;
    _update(() {
      _quickCategory = null;
      _resolvingSite = null;
      _isSearching = false;
      _searchMessage = null;
      _destinationSuggestions = [];
    });
    FocusScope.of(context).unfocus();
    final initialPos =
        (forOrigin
            ? _routingService.originPoint
            : _routingService.destinationPoint) ??
        _routingService.originPoint ??
        Position(AppEnvironment.area.longitude, AppEnvironment.area.latitude);

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          forRouting: true,
          forOrigin: forOrigin,
          initialPosition: initialPos,
        ),
      ),
    );

    if (result != null && mounted) {
      final lat = (result['lat'] as num).toDouble();
      final lng = (result['lng'] as num).toDouble();
      final placeName =
          (result['placeName'] as String?) ?? 'Pinned Destination';

      if (!GeoUtils.isInsideStudyArea(lat, lng, bufferMeters: 80.0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Pinned location is outside the selected study area scope. Please choose a location within the selected study area.',
              ),
            ),
            backgroundColor: AppPalette.of(context).error,
          ),
        );
        return;
      }

      _update(() {
        if (!forOrigin) _destinationController.text = placeName;
        _destinationSuggestions = [];
      });

      if (forOrigin) {
        _routingService.setOrigin(Position(lng, lat), placeName);
      } else {
        _routingService.setDestination(Position(lng, lat), placeName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final hasTrip = _routingService.destinationPoint != null;
    final routes = _routingService.routes;
    final error = _routingService.routeErrorMessage;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: p.surface,
          appBar: const AppTopBar(
            inset: true,
            showBackButton: false,
            showProfile: true,
            showSettingsAction: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasTrip) ...[
                  Text(
                    tr(context, 'Where are you going?'),
                    style: GoogleFonts.manrope(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSearchSection(),
                  const SizedBox(height: 20),
                  _buildQuickDestinations(),
                  if (_searchMessage != null ||
                      _destinationSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSearchResults(),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    tr(context, 'How are you traveling?'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildVehicleSelector(),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, 'Travel mode helps assess route suitability.'),
                    style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
                  ),
                ] else ...[
                  _buildTripSummary(),
                  const SizedBox(height: 20),
                ],
                if (error != null && routes.isEmpty)
                  _buildPlanningError(error)
                else if (routes.isNotEmpty) ...[
                  _buildSuggestedRoutesHeader(),
                  const SizedBox(height: 12),
                  if (error != null) _notice(error, danger: true),
                  if (_routingService.routeWarningMessage != null)
                    _notice(_routingService.routeWarningMessage!),
                  _buildSafestRouteCard(
                    routes[_routingService.selectedRouteIndex],
                  ),
                  if (routes.length > 1) ...[
                    const SizedBox(height: 18),
                    Text(
                      tr(context, 'Other routes'),
                      style: TextStyle(
                        color: p.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in routes.asMap().entries)
                      if (entry.key != _routingService.selectedRouteIndex)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildAlternativeRouteCard(
                            entry.value,
                            entry.key,
                          ),
                        ),
                  ],
                ],
              ],
            ),
          ),
        ),
        if (_routingService.isRouteLoading)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: .45),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          tr(context, 'Checking available routes...'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _originLabel => _routingService.originName.isNotEmpty
      ? _routingService.originName
      : _routingService.isLocatingGps
      ? 'Locating...'
      : _routingService.isUsingGpsFallback
      ? 'Choose a start point'
      : 'Current Location';

  Widget _panel(Widget child) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .5)),
      ),
      child: child,
    );
  }

  Widget _buildSearchSection() {
    final p = AppPalette.of(context);
    return _panel(
      Column(
        children: [
          _tripField(
            tr(context, 'FROM'),
            p.primary,
            TextField(
              key: const ValueKey('planner-origin-field'),
              readOnly: true,
              controller: _originController..text = _originLabel,
              onTap: () => _pickLocationOnMap(forOrigin: true),
              decoration: InputDecoration(
                hintText: tr(context, 'Choose starting point'),
                suffixIcon: IconButton(
                  tooltip: tr(context, 'Use current GPS location'),
                  onPressed: () => _beginPlanning(
                    prefillDestination: _routingService.destinationPoint,
                    name: _routingService.destinationName,
                  ),
                  icon: Icon(Icons.my_location, color: p.primary),
                ),
              ),
              style: TextStyle(fontSize: 14, color: p.onSurface),
            ),
          ),
          const SizedBox(height: 12),
          _tripField(
            tr(context, 'TO'),
            p.notPassable,
            TextField(
              key: const ValueKey('planner-destination-field'),
              readOnly: true,
              controller: _destinationController,
              onTap: _openDestinationSearch,
              decoration: InputDecoration(
                hintText: tr(context, 'Search a street or landmark'),
                suffixIcon: IconButton(
                  tooltip: tr(context, 'Choose on map'),
                  onPressed: () => _pickLocationOnMap(),
                  icon: Icon(Icons.place_outlined, color: p.primary),
                ),
              ),
              style: TextStyle(fontSize: 14, color: p.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripField(String label, Color color, Widget field) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.of(context).onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            field,
          ],
        ),
      ),
    ],
  );

  Widget _buildTripSummary() {
    final p = AppPalette.of(context);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickLocationOnMap(forOrigin: true),
                  child: Row(
                    children: [
                      Icon(Icons.trip_origin, size: 14, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _originLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: tr(context, 'Use current GPS location'),
                onPressed: () => _beginPlanning(
                  prefillDestination: _routingService.destinationPoint,
                  name: _routingService.destinationName,
                ),
                icon: Icon(Icons.my_location, size: 20, color: p.primary),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.place, size: 14, color: p.notPassable),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _routingService.destinationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openDestinationSearch,
                child: Text(tr(context, 'Change')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildVehicleSelector(),
        ],
      ),
    );
  }

  Widget _buildVehicleSelector() => PlannerTravelSelector(
    selected: _routingService.selectedVehicleType,
    onSelected: _routingService.setVehicleType,
  );

  Widget _buildQuickDestinations() {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, 'Quick Destinations'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: p.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _quickTile(
              'Hospitals',
              Icons.local_hospital_outlined,
              QuickDestinationCategory.hospitals,
              p.error,
            ),
            const SizedBox(width: 10),
            _quickTile(
              'Evac Centers',
              Icons.home_outlined,
              QuickDestinationCategory.evacuationCenters,
              p.passable,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _quickTile(
              'Barangay Hall',
              Icons.account_balance_outlined,
              QuickDestinationCategory.barangayHall,
              p.primary,
            ),
            const SizedBox(width: 10),
            _quickTile(
              'Emergency/Police',
              Icons.shield_outlined,
              QuickDestinationCategory.emergencyServices,
              p.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickTile(
    String label,
    IconData icon,
    QuickDestinationCategory category,
    Color color,
  ) {
    final p = AppPalette.of(context);
    return Expanded(
      child: Material(
        color: p.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.outlineVariant.withValues(alpha: .5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showQuickDestinations(category, tr(context, label)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, label),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationSearch(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr(context, 'Back'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${tr(context, 'FROM')}: $_originLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const ValueKey('planner-destination-search'),
                          focusNode: _searchFocus,
                          autofocus: true,
                          controller: _lookupController,
                          onChanged: _onSearchChanged,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            if (_quickCategory != null)
                              FocusScope.of(context).unfocus();
                            else if (_destinationSuggestions.length == 1)
                              _chooseSearchResult(
                                _destinationSuggestions.single,
                              );
                            else if (_destinationSuggestions.isNotEmpty)
                              FocusScope.of(context).unfocus();
                            else if (value.trim().isNotEmpty)
                              _onSearchChanged(value);
                          },
                          decoration: InputDecoration(
                            hintText: tr(
                              context,
                              'Search a street or landmark',
                            ),
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
                                    tooltip: tr(context, 'Clear search'),
                                    onPressed: () {
                                      _lookupController.clear();
                                      _onSearchChanged('');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_destinationSuggestions.isEmpty &&
                        _lookupController.text.trim().isEmpty &&
                        _quickCategory == null)
                      _buildQuickDestinations(),
                    _buildSearchResults(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final previous = _routingService.destinationPoint;
                    await _pickLocationOnMap();
                    if (mounted) _closeDestinationSearchIfChosen(previous);
                  },
                  icon: const Icon(Icons.place_outlined),
                  label: Text(tr(context, 'Choose on the map instead')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final p = AppPalette.of(context);
    String group(Map<String, dynamic> item) =>
        item['category'] == 'Monitored Street'
        ? 'Roads we monitor'
        : item['category'] == 'Evacuation site' ||
              item['quickDestination'] is MarulasLandmark ||
              AppEnvironment.area.landmarks.any(
                (place) => place.id == item['id'],
              )
        ? 'Landmarks'
        : 'Other places';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              tr(context, _searchMessage!),
              style: TextStyle(
                color: p.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        for (final heading in ['Roads we monitor', 'Landmarks', 'Other places'])
          if (_destinationSuggestions.any(
            (item) => group(item) == heading,
          )) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                tr(context, heading),
                style: TextStyle(
                  color: p.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final item in _destinationSuggestions.where(
              (item) => group(item) == heading,
            ))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item['icon'] as IconData? ?? Icons.place_outlined,
                    color: p.primary,
                    size: 20,
                  ),
                ),
                trailing: _resolvingSite == item['text']
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                title: Text(
                  item['text']?.toString() ?? '',
                  style: TextStyle(
                    color: p.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  (item['routingUnavailable'] == true
                          ? tr(
                              context,
                              'Reported removed; directions unavailable',
                            )
                          : tr(context, item['place_name']?.toString() ?? ''))
                      .replaceFirst('${item['text']}, ', ''),
                  style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
                ),
                onTap:
                    _confirmingQuickDestination ||
                        _resolvingSite != null ||
                        item['routingUnavailable'] == true
                    ? null
                    : () => _chooseSearchResult(item),
              ),
          ],
      ],
    );
  }

  Widget _buildSuggestedRoutesHeader() => Row(
    children: [
      Expanded(
        child: Text(
          tr(context, 'Suggested Routes'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppPalette.of(context).onSurface,
          ),
        ),
      ),
      Text(
        '${_routingService.routes.length} ${tr(context, _routingService.routes.length == 1 ? 'option' : 'options')}',
        style: TextStyle(
          color: AppPalette.of(context).onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ],
  );

  Widget _notice(String message, {bool danger = false}) {
    final p = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger ? p.errorContainer : p.warningContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        tr(context, message),
        style: TextStyle(
          color: danger ? p.onErrorContainer : p.onWarningContainer,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildPlanningError(String error) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.route_outlined, color: p.warning, size: 34),
            const SizedBox(height: 12),
            Text(
              tr(context, 'Unable to plan this trip'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: p.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _routingService.originPoint == null
                  ? () => _pickLocationOnMap(forOrigin: true)
                  : () => _routingService.calculateRoute(
                      directionsFetcher: widget.directionsFetcher,
                    ),
              child: Text(
                tr(
                  context,
                  _routingService.originPoint == null
                      ? 'Choose starting point'
                      : 'Try again',
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _openDestinationSearch,
              child: Text(tr(context, 'Choose another place')),
            ),
          ],
        ),
      ),
    );
  }

  PlannedRoute _displayRoute(PlannedRoute route) {
    final unavailable =
        AppStateService.instance.requiresLiveDataWarning ||
        SimulatedWeatherService.instance.isDataStale;
    return unavailable && !route.needsCaution
        ? route.copyWith(safetyStatus: 'unverified_risk')
        : route;
  }

  Widget _buildSafestRouteCard(PlannedRoute route) {
    final records = <RoadStatus>[];
    for (final road in AppStateService.instance.roads) {
      try {
        if (RoutingService.doesRouteCrossGeometry(
          route.points,
          road.geometry,
        )) {
          records.add(road);
        }
      } catch (_) {
        /* A malformed record cannot invent a check time. */
      }
    }
    return PlannerRouteCard(
      key: ValueKey('planner-selected-${identityHashCode(route.points)}'),
      route: _displayRoute(route),
      roadRecords: records,
      map:
          widget.routeMapBuilder?.call(route.points) ??
          AppMap(
            showSearchButton: false,
            routePoints: route.points,
            onMapCreatedCallback: (map) => _frameRouteCard(map, route),
          ),
      onPreview: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoutePreviewScreen(
            route: route,
            routeMapBuilder: widget.routeMapBuilder,
          ),
        ),
      ),
      onNavigate: () => _navigate(route),
    );
  }

  Future<void> _frameRouteCard(MapboxMap map, PlannedRoute route) async {
    _previewMap = map;
    if (route.points.length < 2) return;
    try {
      // A static overview needs the route in view, rather than the area's
      // default camera. Full-screen maps keep their own controls and scale.
      await map.compass.updateSettings(CompassSettings(enabled: false));
      await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      final camera = await map
          .cameraForCoordinatesPadding(
            route.points.map((p) => Point(coordinates: p)).toList(),
            CameraOptions(
              pitch: 0,
              bearing: 0,
              padding: MbxEdgeInsets(top: 22, left: 24, bottom: 30, right: 24),
            ),
            null,
            17.5,
            null,
          )
          .timeout(const Duration(seconds: 3));
      if (!mounted ||
          !identical(_previewMap, map) ||
          _routingService.routes.isEmpty ||
          !identical(
            _routingService.routes[_routingService.selectedRouteIndex].points,
            route.points,
          )) {
        return;
      }
      await map.setCamera(camera).timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Full-screen route review remains available. */
    }
  }

  Widget _buildAlternativeRouteCard(PlannedRoute route, int index) =>
      PlannerRouteCard(
        route: _displayRoute(route),
        compact: true,
        onSelect: () => _routingService.selectRoute(index),
      );
}
