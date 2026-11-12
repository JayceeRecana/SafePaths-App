import 'navigation_car_model.dart';
import 'navigation_location_icon.dart';
import '../services/noah_awareness.dart';
import '../l10n/app_strings.dart';
import '../config/app_environment.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/app_state_service.dart';
import '../services/user_service.dart';
import '../services/weather_service.dart';
import '../utils/geo_utils.dart';
import '../services/map_road_data.dart';
import '../services/map_load_state.dart';
import 'map_status_banner.dart';
import '../screens/user/road_details_screen.dart';
import '../screens/admin/update_road_status_screen.dart';
import '../screens/admin/import_roads_screen.dart';

class AppMap extends StatefulWidget {
  final NoahMapController? awareness;
  final String? selectedRoadId;
  final Position? initialCenter;
  final MbxEdgeInsets? initialCameraPadding;
  final ValueChanged<CameraState>? onCameraChanged;
  final VoidCallback? onCameraIdle;
  final bool showSearchButton;
  final bool followMode;
  final bool navigationMode;

  /// The old geometry remains visible while guidance is paused, not as an
  /// instruction to proceed. Defaults off for every non-navigation caller.
  final bool routeReferenceOnly;
  final String? navigationVehicleType;
  final double navigationBearing;
  final Position? destinationPoint;
  final List<Position>? travelledRoutePoints;
  final VoidCallback? onUserPan;
  final Function(MapboxMap mapboxMap)? onMapCreatedCallback;
  final Function(String roadId, Position? tappedPosition)? onRoadTapped;
  final List<Position>? routePoints;

  /// Optional externally owned state for a screen that places its own banner.
  final MapLoadState? loadState;
  final bool showStatusBanner;
  const AppMap({
    super.key,
    this.showSearchButton = false,
    this.selectedRoadId,
    this.initialCenter,
    this.initialCameraPadding,
    this.onCameraChanged,
    this.onCameraIdle,
    this.awareness,
    this.followMode = false,
    this.navigationMode = false,
    this.routeReferenceOnly = false,
    this.navigationVehicleType,
    this.navigationBearing = 0,
    this.destinationPoint,
    this.travelledRoutePoints,
    this.onUserPan,
    this.onMapCreatedCallback,
    this.onRoadTapped,
    this.routePoints,
    this.loadState,
    this.showStatusBanner = true,
  });

  @override
  State<AppMap> createState() => AppMapState();
}

class AppMapState extends State<AppMap> {
  MapboxMap? _mapboxMap;
  String get _styleUri => Theme.of(context).brightness == Brightness.dark
      ? MapboxStyles.DARK
      : 'mapbox://styles/jayceerecana/cmqk7pl2d000a01rdfw0ubgo0';
  String? _themeStyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final style = _styleUri;
    final changed = _themeStyle != null && _themeStyle != style;
    _themeStyle = style;
    if (changed && _mapboxMap != null) _changeMapTheme();
  }

  Future<void> _changeMapTheme() async {
    // Invalidate in-flight overlay writes before loading the new base style.
    _loadState.loaded();
    await _retryMap();
  }

  final _roadData = MapRoadData();
  late final MapLoadState _loadState = widget.loadState ?? MapLoadState();
  Future<void> retryMap() => _retryMap();
  int _styleEpoch = 0;
  int _mapKey = 0;
  bool _styleReady = false;
  String? _noahRenderKey;
  bool? _lastSafePaths;
  List<Position>? _projectedRoute;
  String? _routeData;
  String? _lastTravelledJson;
  String? _lastDestinationJson;
  bool? _lastNavigationMode;
  bool? _lastRouteReferenceOnly;

  final TextEditingController _searchController = TextEditingController();
  bool _isDrawing = false;
  bool _drawPending = false;
  String? _lastRoadsGeoJsonString;
  String? _lastSelectedRoadId;
  String? _lastRouteGeoJsonString;

  static final String _publicToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  @override
  void initState() {
    super.initState();
    widget.awareness?.addListener(_drawData);
    MapboxOptions.setAccessToken(_publicToken);
    _loadState.begin();
    AppStateService.instance.mapChanges.addListener(_onStateChanged);
    SimulatedWeatherService.instance.listenable.addListener(_onWeatherChanged);
  }

  @override
  void dispose() {
    _styleEpoch++;
    widget.awareness?.removeListener(_drawData);
    _mapboxMap = null;
    if (widget.loadState == null) _loadState.dispose();
    AppStateService.instance.mapChanges.removeListener(_onStateChanged);
    SimulatedWeatherService.instance.listenable.removeListener(
      _onWeatherChanged,
    );
    _searchController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      _drawData();
    }
  }

  void _onWeatherChanged() {
    if (mounted) {
      _drawData();
    }
  }

  @override
  void didUpdateWidget(covariant AppMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationBearing != widget.navigationBearing) {
      _updateCarBearing();
    }
    if (oldWidget.navigationVehicleType != widget.navigationVehicleType ||
        oldWidget.navigationMode != widget.navigationMode) {
      final map = _mapboxMap;
      if (map != null) _updateLocationIcon(map);
    }
    if (oldWidget.awareness != widget.awareness) {
      oldWidget.awareness?.removeListener(_drawData);
      widget.awareness?.addListener(_drawData);
      _noahRenderKey = null;
      _lastSafePaths = null;
      _drawData();
    }
    if (widget.selectedRoadId != oldWidget.selectedRoadId ||
        widget.routePoints != oldWidget.routePoints ||
        widget.travelledRoutePoints != oldWidget.travelledRoutePoints ||
        widget.navigationMode != oldWidget.navigationMode ||
        widget.routeReferenceOnly != oldWidget.routeReferenceOnly ||
        widget.destinationPoint != oldWidget.destinationPoint) {
      _drawData();
      if (!widget.followMode &&
          !widget.navigationMode &&
          widget.routePoints != null &&
          widget.routePoints!.isNotEmpty &&
          _mapboxMap != null) {
        final firstPt = widget.routePoints!.first;
        _mapboxMap!.flyTo(
          CameraOptions(center: Point(coordinates: firstPt), zoom: 14.5),
          MapAnimationOptions(duration: 1500),
        );
      }
    }
  }

  int _locationIconRequest = 0;
  bool _locationUsesCar = false;
  bool _carModelFailed = false;
  bool _bearingUpdating = false;
  bool _bearingPending = false;
  Future<void> _locationWrites = Future.value();

  bool _currentLocationRequest(MapboxMap map, int request) =>
      mounted && identical(_mapboxMap, map) && request == _locationIconRequest;

  Future<bool> _writeLocationSettings(
    MapboxMap map,
    int request,
    LocationComponentSettings settings,
  ) async {
    var applied = false;
    final write = _locationWrites.then((_) async {
      if (!_currentLocationRequest(map, request)) return;
      await map.location
          .updateSettings(settings)
          .timeout(const Duration(seconds: 5));
      applied = true;
    });
    // Serialize cosmetic writes; a late heading cannot overwrite a new style/mode.
    _locationWrites = write.catchError((Object _) {});
    await write;
    return applied && _currentLocationRequest(map, request);
  }

  Future<void> _updateCarBearing() async {
    if (!_locationUsesCar) return;
    if (_bearingUpdating) {
      _bearingPending = true;
      return;
    }
    _bearingUpdating = true;
    final request = _locationIconRequest;
    final map = _mapboxMap;
    try {
      do {
        _bearingPending = false;
        if (map == null ||
            !_currentLocationRequest(map, request) ||
            !_locationUsesCar) {
          return;
        }
        // Partial update preserves the loaded model, rather than loading it per fix.
        await _writeLocationSettings(
          map,
          request,
          LocationComponentSettings(
            locationPuck: LocationPuck(
              locationPuck3D: LocationPuck3D(
                modelRotation: NavigationCarModel.rotation(
                  widget.navigationBearing,
                ),
              ),
            ),
          ),
        );
      } while (_bearingPending);
    } catch (_) {
      if (map != null && _currentLocationRequest(map, request)) {
        _carModelFailed = true;
        _locationUsesCar = false;
        await _updateLocationIcon(map);
      }
    } finally {
      _bearingUpdating = false;
    }
  }

  Future<void> _updateLocationIcon(MapboxMap map) async {
    final request = ++_locationIconRequest;
    _locationUsesCar = false;
    try {
      final image = widget.navigationMode
          ? await NavigationLocationIcon.image(widget.navigationVehicleType)
          : null;
      final applied = await _writeLocationSettings(
        map,
        request,
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          puckBearingEnabled: false,
          locationPuck: LocationPuck(
            locationPuck2D: DefaultLocationPuck2D(
              topImage: image,
              scaleExpression: image == null ? null : '0.5',
            ),
          ),
        ),
      );
      if (!applied) return;
      if (widget.navigationMode &&
          !_carModelFailed &&
          NavigationCarModel.supports(widget.navigationVehicleType)) {
        try {
          await NavigationCarModel.ensureBundled();
          if (!_currentLocationRequest(map, request)) return;
          final applied = await _writeLocationSettings(
            map,
            request,
            LocationComponentSettings(
              enabled: true,
              puckBearingEnabled: false,
              locationPuck: NavigationCarModel.puck(widget.navigationBearing),
            ),
          );
          if (!applied) return;
          _locationUsesCar = true;
          _updateCarBearing();
        } catch (_) {
          if (!_currentLocationRequest(map, request)) return;
          _carModelFailed = true;
          debugPrint('[AppMap] 3D car unavailable; using travel-mode icon.');
          await _updateLocationIcon(map);
        }
      }
    } catch (e) {
      debugPrint(
        '[AppMap] Location icon could not be updated: ${e.runtimeType}',
      );
      if (_currentLocationRequest(map, request)) {
        try {
          await _writeLocationSettings(
            map,
            request,
            LocationComponentSettings(
              enabled: true,
              pulsingEnabled: true,
              puckBearingEnabled: false,
              locationPuck: LocationPuck(
                locationPuck2D: DefaultLocationPuck2D(),
              ),
            ),
          );
        } catch (_) {
          /* A subsequent map recreation can retry. */
        }
      }
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    debugPrint('[AppMap] Map created successfully!');

    try {
      await mapboxMap.scaleBar.updateSettings(
        ScaleBarSettings(isMetricUnits: true),
      );
      await _updateLocationIcon(mapboxMap);
    } catch (e) {
      debugPrint('[AppMap] Error enabling location puck: $e');
    }

    if (!mounted || !identical(_mapboxMap, mapboxMap)) return;
    if (widget.onMapCreatedCallback != null) {
      widget.onMapCreatedCallback!(mapboxMap);
    }
    _drawData();
  }

  void _onMapTapped(MapContentGestureContext ctx) async {
    if (_mapboxMap == null) return;

    final screenCoordinate = await _mapboxMap!.pixelForCoordinate(ctx.point);
    if (!mounted) return;

    final x = screenCoordinate.x;
    final y = screenCoordinate.y;
    final tapBox = RenderedQueryGeometry.fromScreenBox(
      ScreenBox(
        min: ScreenCoordinate(x: x - 15, y: y - 15),
        max: ScreenCoordinate(x: x + 15, y: y + 15),
      ),
    );

    // 1. Try to query our custom flood-monitored roads layer first (for both users and admins)
    try {
      final roadFeatures = await _mapboxMap!.queryRenderedFeatures(
        tapBox,
        RenderedQueryOptions(
          layerIds: ['roads-layer', 'roads-unconfirmed-layer'],
          filter: null,
        ),
      );
      if (!mounted) return;

      if (roadFeatures.isNotEmpty) {
        final feature = roadFeatures.first;
        final mapFeature = feature?.queriedFeature.feature;
        if (mapFeature != null) {
          final properties = mapFeature['properties'] as Map?;
          if (properties != null) {
            final roadId = properties['id']?.toString();
            if (roadId != null) {
              if (widget.onRoadTapped != null) {
                widget.onRoadTapped!(roadId, ctx.point.coordinates);
              } else {
                final role = await UserService.getUserRole();
                if (!mounted) return;
                if (role == UserRole.admin) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UpdateRoadStatusScreen(
                        prefilledRoadId: roadId,
                        isStandalone: true,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(RoadDetailsScreen.route(roadId));
                }
              }
              return; // Handled click on monitored road, stop execution
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AppMap] Error querying roads-layer: $e');
    }

    // 2. If not a flood-monitored road, check if user is admin (to add a road)
    final role = await UserService.getUserRole();
    if (!mounted) return;
    if (role != UserRole.admin) return;

    try {
      final features = await _mapboxMap!.queryRenderedFeatures(
        tapBox,
        RenderedQueryOptions(layerIds: null, filter: null),
      );

      String? roadName;

      // 1. Prioritize line features (roads) that have a name
      for (final feature in features) {
        final mapFeat = feature?.queriedFeature.feature;
        if (mapFeat != null) {
          final props = mapFeat['properties'] as Map?;
          final geom = mapFeat['geometry'] as Map?;
          if (props != null && props.containsKey('name') && geom != null) {
            final type = geom['type'].toString();
            if (type == 'LineString' || type == 'MultiLineString') {
              roadName = props['name'].toString();
              break;
            }
          }
        }
      }

      // 2. Fallback if no line was found (maybe it's a weird geometry), but explicitly ignore neighborhoods
      if (roadName == null) {
        for (final feature in features) {
          final props = feature?.queriedFeature.feature['properties'] as Map?;
          if (props != null && props.containsKey('name')) {
            final name = props['name'].toString().toLowerCase();
            if (!name.contains('barangay') &&
                !name.contains('approximate') &&
                !name.contains('philippines') &&
                !name.contains('city')) {
              roadName = props['name'].toString();
              break;
            }
          }
        }
      }

      // 2. If no explicit road name found, look for something with class 'street' or 'road'
      if (roadName == null) {
        for (final feature in features) {
          final props = feature?.queriedFeature.feature['properties'] as Map?;
          if (props != null && props.containsKey('name')) {
            final String featureClass = (props['class'] ?? '')
                .toString()
                .toLowerCase();
            final String featureType = (props['type'] ?? '')
                .toString()
                .toLowerCase();
            if (featureClass == 'street' ||
                featureClass == 'road' ||
                featureClass == 'motorway' ||
                featureClass == 'primary' ||
                featureClass == 'secondary' ||
                featureClass == 'tertiary' ||
                featureType == 'road') {
              roadName = props['name'];
              break;
            }
          }
        }
      }

      // 3. Absolute fallback: take anything that doesn't sound like a neighborhood
      if (roadName == null) {
        for (final feature in features) {
          final props = feature?.queriedFeature.feature['properties'] as Map?;
          if (props != null && props.containsKey('name')) {
            final nameLower = props['name'].toString().toLowerCase();
            if (!nameLower.contains('barangay') &&
                !nameLower.contains('city') &&
                !nameLower.contains('philippines') &&
                !nameLower.contains('approximate')) {
              roadName = props['name'];
              break;
            }
          }
        }
      }

      if (roadName != null && roadName.isNotEmpty) {
        await fetchRoadGeometry(roadName);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  context,
                  'Could not detect street name. Please type it in the Search bar above.',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AppMap] Error querying map for road name: $e');
    }
  }

  Future<void> fetchRoadGeometry(String roadName) async {
    if (!mounted) return;
    if (AppEnvironment.isFieldTest) {
      // The legacy name-based shortcut omits the study-area/worker metadata
      // and can create duplicate roads beside the stable OSM-way imports.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preview and select the test-area segments in Import Roads, then review their conditions.',
          ),
        ),
      );
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ImportRoadsScreen()));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fetching geometry for "$roadName"...')),
    );

    // Clean up name to match OSM easier (remove suffixes)
    String cleanName = roadName.toLowerCase();
    cleanName = cleanName.replaceAll(RegExp(r'\s+street$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+st\.?$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+road$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+rd\.?$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+avenue$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+ave\.?$'), '');

    // Fetch ONLY way segments whose nodes are strictly within the selected study area.
    // We intentionally exclude relation+way(r) because OSM relations for city-wide
    // roads (e.g. MacArthur Highway) pull in segments from other barangays,
    // creating the diagonal / cross-block polyline artifacts on the map.
    final String query =
        '''
      [out:json][timeout:20];
      way["name"~"$cleanName",i](poly:"${AppEnvironment.area.polygon}");
      out geom;
    ''';

    final endpoints = [
      'https://overpass.openstreetmap.fr/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://lz4.overpass-api.de/api/interpreter',
      'https://overpass-api.de/api/interpreter',
    ];

    try {
      http.Response? response;
      for (final ep in endpoints) {
        try {
          final res = await http
              .post(
                Uri.parse(ep),
                headers: {
                  'User-Agent': 'SafePathsApp/1.0',
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 12));

          if (res.statusCode == 200) {
            response = res;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['elements'] != null && data['elements'].isNotEmpty) {
          final elements = data['elements'] as List;

          // Aggregate ALL segments that match this road name into a single MultiLineString structure
          final List<List<Map<String, dynamic>>> allSegments = [];

          for (final way in elements) {
            if (way['geometry'] != null) {
              final coordinates = way['geometry']
                  .map((g) => {'lon': g['lon'], 'lat': g['lat']})
                  .cast<Map<String, dynamic>>()
                  .toList();

              if (coordinates.isNotEmpty) {
                allSegments.add(coordinates);
              }
            }
          }

          if (allSegments.isNotEmpty) {
            // FLY CAMERA TO THE FIRST COORDINATE OF THE FIRST SEGMENT
            if (_mapboxMap != null) {
              final firstCoord = allSegments.first.first;
              _mapboxMap!.flyTo(
                CameraOptions(
                  center: Point(
                    coordinates: Position(
                      firstCoord['lon'] as num,
                      firstCoord['lat'] as num,
                    ),
                  ),
                  zoom: 16.0, // Zoom in closer
                ),
                MapAnimationOptions(
                  duration: 1500,
                ), // 1.5 seconds smooth animation
              );
            }

            final roadId =
                !AppEnvironment.isFieldTest && cleanName.contains('macarthur')
                ? 'macarthur_market'
                : roadName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

            // Special handling for MacArthur Highway: Segment into 3 realistic CCTV zones
            if (!AppEnvironment.isFieldTest &&
                cleanName.contains('macarthur')) {
              // 1. Fatima / OLFU (North): lat >= 14.6780
              // 2. Marulas Market (Center): 14.6755 <= lat < 14.6780
              // 3. BBB (South): lat < 14.6755
              List<List<Map<String, dynamic>>> fatimaSegments = [];
              List<List<Map<String, dynamic>>> marketSegments = [];
              List<List<Map<String, dynamic>>> bbbSegments = [];

              for (final seg in allSegments) {
                List<Map<String, dynamic>> fPts = [];
                List<Map<String, dynamic>> mPts = [];
                List<Map<String, dynamic>> bPts = [];

                for (final pt in seg) {
                  final double lat = (pt['lat'] as num).toDouble();
                  if (lat >= 14.6780) {
                    fPts.add(pt);
                  } else if (lat >= 14.6755) {
                    mPts.add(pt);
                  } else {
                    bPts.add(pt);
                  }
                }
                if (fPts.isNotEmpty) fatimaSegments.add(fPts);
                if (mPts.isNotEmpty) marketSegments.add(mPts);
                if (bPts.isNotEmpty) bbbSegments.add(bPts);
              }

              final macArthurParts = [
                {
                  'id': 'macarthur_fatima',
                  'name': 'MacArthur Highway (Fatima / OLFU)',
                  'segments': fatimaSegments,
                },
                {
                  'id': 'macarthur_market',
                  'name': 'MacArthur Highway (Marulas Public Market)',
                  'segments': marketSegments,
                },
                {
                  'id': 'macarthur_bbb',
                  'name': 'MacArthur Highway (BBB)',
                  'segments': bbbSegments,
                },
              ];

              for (final part in macArthurParts) {
                final segs =
                    part['segments'] as List<List<Map<String, dynamic>>>;
                if (segs.isNotEmpty) {
                  final pId = part['id'] as String;
                  final pName = part['name'] as String;
                  final pSafeSegs = segs.map((s) => {'points': s}).toList();

                  await AppStateService.instance.updateRoadStatus(
                    pId,
                    'passable',
                    'Segmented arterial highway',
                    geometry: {
                      'type': 'MultiLineString',
                      'segments': pSafeSegs,
                    },
                    name: pName,
                    vulnerability: 'high',
                  );
                }
              }
            } else {
              // Standard single road import
              final firestoreSafeSegments = allSegments
                  .map((seg) => {'points': seg})
                  .toList();

              final existing = AppStateService.instance.roads
                  .where((r) => r.id == roadId)
                  .firstOrNull;
              if (existing == null) {
                await AppStateService.instance.updateRoadStatus(
                  roadId,
                  'passable',
                  'Imported from live map click',
                  geometry: {
                    'type': 'MultiLineString',
                    'segments': firestoreSafeSegments,
                  },
                  name: roadName,
                );
              }
            }

            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UpdateRoadStatusScreen(
                    prefilledRoadId: roadId,
                    isStandalone: true,
                  ),
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Road "$roadName" not found in the selected study area',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context, 'Failed to fetch from Overpass API')),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching from Overpass: $e');
    }
  }

  Future<void> _userSearchAndHighlight(String query) async {
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
      if (_mapboxMap != null && matchedRoad.geometry != null) {
        final center = GeoUtils.getRoadCenter(matchedRoad.geometry);
        if (center != null) {
          _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(center.lng, center.lat)),
              zoom: 16.0,
            ),
            MapAnimationOptions(duration: 1500),
          );
        }
      }

      if (mounted) {
        // Open Road Details screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoadDetailsScreen(roadId: matchedRoad!.id),
          ),
        );
      }
      return;
    }

    // 2. Search local Barangay Marulas Landmarks Catalog
    final landmarkMatches = AppEnvironment.area.searchLandmarks(query);
    if (landmarkMatches.isNotEmpty && _mapboxMap != null) {
      final landmark = landmarkMatches.first;
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(landmark.lng, landmark.lat)),
          zoom: 16.5,
        ),
        MapAnimationOptions(duration: 1200),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Landmark found: ${landmark.name} (${landmark.category})',
            ),
          ),
        );
      }
      return;
    }

    // 3. Query Mapbox Geocoding API within the selected study area bounding box
    final searchQuery = '$query ${AppEnvironment.area.searchSuffix}';
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(searchQuery)}.json'
      '?access_token=$_publicToken'
      '&proximity=${AppEnvironment.area.longitude},${AppEnvironment.area.latitude}'
      '&bbox=${GeoUtils.studyAreaBBox}'
      '&country=ph'
      '&limit=1',
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

            if (!GeoUtils.isInsideStudyArea(lat, lon, bufferMeters: 80.0)) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr(
                        context,
                        'No places found within the selected study area.',
                      ),
                    ),
                  ),
                );
              }
              return;
            }

            _mapboxMap!.flyTo(
              CameraOptions(
                center: Point(coordinates: Position(lon, lat)),
                zoom: 16.0,
              ),
              MapAnimationOptions(duration: 1500),
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Showing result for: ${placeName ?? query}'),
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    'No places found within the selected study area.',
                  ),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[AppMap] Geocoding error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'Network error: Could not connect to map service.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _retryMap() async {
    if (_loadState.loading || !mounted) return;
    _loadState.begin();
    _styleEpoch++;
    _styleReady = false;
    _noahRenderKey = null;
    _lastSafePaths = null;
    _lastRoadsGeoJsonString = null;
    _lastSelectedRoadId = null;
    _lastRouteGeoJsonString = null;
    _lastTravelledJson = null;
    _lastDestinationJson = null;
    _lastNavigationMode = null;
    _lastRouteReferenceOnly = null;
    final map = _mapboxMap;
    if (map == null) {
      setState(() => _mapKey++);
      return;
    }
    try {
      await map.loadStyleURI(_styleUri).timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted && identical(map, _mapboxMap)) _loadState.failed();
    }
  }

  Future<void> viewNoahCoverage() async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) return;
    try {
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(120.98375, 14.67575)),
          zoom: 13.8,
          pitch: 0,
          bearing: 0,
        ),
        MapAnimationOptions(duration: 600),
      );
    } catch (_) {
      /* A camera failure must not affect road information. */
    }
  }

  bool _noahDrawing = false, _noahPending = false;
  void _refreshNoah() async {
    if (!mounted ||
        !_styleReady ||
        _mapboxMap == null ||
        widget.awareness == null)
      return;
    if (_noahDrawing) {
      _noahPending = true;
      return;
    }
    _noahDrawing = true;
    try {
      await _drawNoah(_mapboxMap!, _styleEpoch);
    } on _ObsoleteMapDraw {
      /* A newer style owns rendering. */
    } finally {
      _noahDrawing = false;
      if (_noahPending) {
        _noahPending = false;
        _refreshNoah();
      }
    }
  }

  Future<void> _drawNoah(MapboxMap map, int epoch) async {
    final control = widget.awareness;
    if (control == null) return;
    final dataset = control.data;
    final key =
        '${control.enabled}:${identityHashCode(dataset)}:${control.renderAttempt}';
    if (_noahRenderKey == key) return;
    bool current() =>
        mounted && identical(map, _mapboxMap) && epoch == _styleEpoch;
    Future<T> checked<T>(Future<T> op) async {
      final result = await op.timeout(const Duration(seconds: 8));
      if (!current()) throw const _ObsoleteMapDraw();
      return result;
    }

    const source = 'noah-awareness-source', layer = 'noah-awareness-fill';
    var operation = 'check source';
    try {
      final style = map.style;
      if (control.enabled && dataset != null) {
        if (!await checked(style.styleLayerExists('roads-glow-layer'))) return;
        if (!await checked(style.styleSourceExists(source))) {
          operation = 'add data source';
          await checked(
            style.addSource(GeoJsonSource(id: source, data: dataset.geoJson)),
          );
        }
        if (!await checked(style.styleLayerExists(layer))) {
          operation = 'add fill layer';
          final fill = FillLayer(
            id: layer,
            sourceId: source,
            fillOpacity: .28,
            fillColorExpression: [
              'match',
              ['get', 'Var'],
              1,
              '#F2C94C',
              2,
              '#E98A24',
              3,
              '#C63A46',
              '#000000',
            ],
          );
          if (await checked(style.styleLayerExists('roads-glow-layer'))) {
            final anchor =
                await checked(style.styleLayerExists('admin-selected-road'))
                ? 'admin-selected-road'
                : 'roads-glow-layer';
            await checked(style.addLayerAt(fill, LayerPosition(below: anchor)));
          } else {
            await checked(style.addLayer(fill));
          }
        }
      }
      if (await checked(style.styleLayerExists(layer))) {
        operation = 'set layer visibility';
        await checked(
          style.setStyleLayerProperty(
            layer,
            'visibility',
            control.enabled && dataset != null ? 'visible' : 'none',
          ),
        );
      }
      _noahRenderKey = key;
    } on _ObsoleteMapDraw {
      rethrow;
    } catch (error) {
      debugPrint('[NOAH] $operation failed (${error.runtimeType}).');
      if (current()) control.renderFailed();
    }
  }

  void _drawData() async {
    if (!mounted || _mapboxMap == null || !_styleReady) return;
    if (_isDrawing) {
      _drawPending = true;
      return;
    }
    _isDrawing = true;

    try {
      final map = _mapboxMap!;
      final epoch = _styleEpoch;
      bool current() =>
          mounted && identical(_mapboxMap, map) && epoch == _styleEpoch;
      Future<T> checked<T>(Future<T> operation) async {
        final result = await operation.timeout(const Duration(seconds: 8));
        if (!current()) throw const _ObsoleteMapDraw();
        return result;
      }

      final selectedRoadId = widget.selectedRoadId;
      final geoJsonString = _roadData.project(
        AppStateService.instance.roads,
        SimulatedWeatherService.instance.currentState,
      );
      if (!identical(_projectedRoute, widget.routePoints)) {
        _projectedRoute = widget.routePoints;
        _routeData =
            widget.routePoints == null || widget.routePoints!.length < 2
            ? null
            : jsonEncode({
                'type': 'Feature',
                'geometry': {
                  'type': 'LineString',
                  'coordinates': widget.routePoints!
                      .map((point) => [point.lng, point.lat])
                      .toList(),
                },
                'properties': {},
              });
      }
      final travelledJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          if ((widget.travelledRoutePoints?.length ?? 0) >= 2)
            {
              'type': 'Feature',
              'properties': {},
              'geometry': {
                'type': 'LineString',
                'coordinates': widget.travelledRoutePoints!
                    .map((p) => [p.lng, p.lat])
                    .toList(),
              },
            },
        ],
      });
      final destination = widget.destinationPoint;
      final destinationJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          if (widget.navigationMode && destination != null)
            {
              'type': 'Feature',
              'properties': {},
              'geometry': {
                'type': 'Point',
                'coordinates': [destination.lng, destination.lat],
              },
            },
        ],
      });
      if (_lastSafePaths == (widget.awareness?.safePaths ?? true) &&
          _lastRoadsGeoJsonString == geoJsonString &&
          _lastDestinationJson == destinationJson &&
          _lastTravelledJson == travelledJson &&
          _lastNavigationMode == widget.navigationMode &&
          _lastRouteReferenceOnly == widget.routeReferenceOnly &&
          _lastRouteGeoJsonString == _routeData &&
          _lastSelectedRoadId == selectedRoadId)
        return;
      final style = map.style;
      if (_lastRoadsGeoJsonString != geoJsonString) {
        final sourceId = 'roads-source';
        final layerId = 'roads-layer';
        final glowLayerId = 'roads-glow-layer';
        final unconfirmedLayerId = 'roads-unconfirmed-layer';

        final sourceExists = await checked(style.styleSourceExists(sourceId));

        if (sourceExists) {
          await checked(
            style.setStyleSourceProperty(sourceId, 'data', geoJsonString),
          );
        } else {
          await checked(
            style.addSource(GeoJsonSource(id: sourceId, data: geoJsonString)),
          );
        }

        // 1. Glow Layer (Only for confirmed hazards - suppress glow on unconfirmed/dashed roads)
        if (!await checked(style.styleLayerExists(glowLayerId))) {
          await checked(
            style.addLayer(
              LineLayer(
                id: glowLayerId,
                sourceId: sourceId,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                lineColorExpression: [
                  'to-color',
                  ['get', 'glowColor'],
                ],
                lineWidth: 16.0, // Wider for glow effect
                filter: [
                  '!=',
                  ['get', 'isUnconfirmed'],
                  true,
                ],
              ),
            ),
          );
        }

        // 2. Solid Road Layer (Confirmed roads only)
        if (!await checked(style.styleLayerExists(layerId))) {
          await checked(
            style.addLayer(
              LineLayer(
                id: layerId,
                sourceId: sourceId,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                lineColorExpression: [
                  'to-color',
                  ['get', 'color'],
                ],
                lineWidth: 6.0,
                filter: [
                  '!=',
                  ['get', 'isUnconfirmed'],
                  true,
                ],
              ),
            ),
          );
        }

        // 3. Dashed Road Layer (Unconfirmed / stale roads that need reconfirmation)
        if (!await checked(style.styleLayerExists(unconfirmedLayerId))) {
          await checked(
            style.addLayer(
              LineLayer(
                id: unconfirmedLayerId,
                sourceId: sourceId,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                lineColorExpression: [
                  'to-color',
                  ['get', 'color'],
                ],
                lineWidth: 6.0,
                lineDasharray: [2.5, 1.5],
                filter: [
                  '==',
                  ['get', 'isUnconfirmed'],
                  true,
                ],
              ),
            ),
          );
        }

        _lastRoadsGeoJsonString = geoJsonString;
      }
      // Selection is a blue casing BELOW the status lines: colour and dashed
      // uncertainty remain intact, including disconnected segments of one road.
      if (selectedRoadId != null || _lastSelectedRoadId != null) {
        const selectionLayer = 'admin-selected-road';
        final filter = <Object>[
          '==',
          ['get', 'id'],
          selectedRoadId ?? '',
        ];
        if (!await checked(style.styleLayerExists(selectionLayer))) {
          await checked(
            style.addLayerAt(
              LineLayer(
                id: selectionLayer,
                sourceId: 'roads-source',
                lineColor: 0xFF005BBB,
                lineWidth: 15,
                lineOpacity: .8,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                filter: filter,
              ),
              LayerPosition(below: 'roads-glow-layer'),
            ),
          );
        } else {
          await checked(
            style.setStyleLayerProperty(selectionLayer, 'filter', filter),
          );
        }
      }
      _lastSelectedRoadId = selectedRoadId;
      // Keep the travelled portion below remaining guidance and all hazards.
      const travelledSource = 'travelled-route-source';
      if (_lastTravelledJson != travelledJson) {
        if (await checked(style.styleSourceExists(travelledSource))) {
          await checked(
            style.setStyleSourceProperty(
              travelledSource,
              'data',
              travelledJson,
            ),
          );
        } else {
          await checked(
            style.addSource(
              GeoJsonSource(id: travelledSource, data: travelledJson),
            ),
          );
        }
        if (!await checked(style.styleLayerExists('travelled-route-layer'))) {
          await checked(
            style.addLayerAt(
              LineLayer(
                id: 'travelled-route-layer',
                sourceId: travelledSource,
                lineColor: 0xFF78909C,
                lineOpacity: 0.65,
                lineWidth: 5,
                lineCap: LineCap.ROUND,
                lineJoin: LineJoin.ROUND,
              ),
              LayerPosition(below: 'roads-glow-layer'),
            ),
          );
        }
        _lastTravelledJson = travelledJson;
      }
      if (_lastNavigationMode != widget.navigationMode) {
        final dim = widget.navigationMode;
        const backgroundRoad = <Object>[
          'all',
          [
            '==',
            ['get', 'status'],
            'passable',
          ],
          [
            '==',
            ['get', 'glowColor'],
            'rgba(0, 0, 0, 0.0)',
          ],
        ];
        for (final layer in ['roads-layer', 'roads-glow-layer']) {
          await checked(
            style.setStyleLayerProperty(
              layer,
              'line-opacity',
              dim ? ['case', backgroundRoad, 0.25, 1.0] : 1.0,
            ),
          );
        }
        await checked(
          style.setStyleLayerProperty(
            'roads-layer',
            'line-width',
            dim ? ['case', backgroundRoad, 2.0, 6.0] : 6.0,
          ),
        );
        _lastNavigationMode = widget.navigationMode;
      }
      if (_lastRouteGeoJsonString != _routeData ||
          _lastRouteReferenceOnly != widget.routeReferenceOnly) {
        const routeSourceId = 'route-source', routeLayerId = 'route-layer';
        final routeData = _routeData;
        if (routeData != null) {
          if (await checked(style.styleSourceExists(routeSourceId))) {
            await checked(
              style.setStyleSourceProperty(routeSourceId, 'data', routeData),
            );
          } else {
            await checked(
              style.addSource(
                GeoJsonSource(id: routeSourceId, data: routeData),
              ),
            );
          }
          final routeLayerMissing = !await checked(
            style.styleLayerExists(routeLayerId),
          );
          if (routeLayerMissing) {
            await checked(
              style.addLayer(
                LineLayer(
                  id: routeLayerId,
                  sourceId: routeSourceId,
                  lineJoin: LineJoin.ROUND,
                  lineCap: LineCap.ROUND,
                  lineColor: 0xFF1E88E5,
                  lineWidth: 8,
                ),
              ),
            );
          }
          if (widget.navigationMode &&
              !await checked(style.styleLayerExists('route-direction-layer'))) {
            await checked(
              style.addLayer(
                SymbolLayer(
                  id: 'route-direction-layer',
                  sourceId: routeSourceId,
                  symbolPlacement: SymbolPlacement.LINE,
                  symbolSpacing: 110,
                  textField: '>',
                  textSize: 22,
                  textColor: 0xFFFFFFFF,
                  textHaloColor: 0xFF1565C0,
                  textHaloWidth: 1,
                  textKeepUpright: false,
                  textRotationAlignment: TextRotationAlignment.MAP,
                  textPitchAlignment: TextPitchAlignment.MAP,
                ),
              ),
            );
          }
          // Change paint only: preserve the previous geometry, destination
          // and map lifecycle, but remove the visual cue to follow it.
          if (routeLayerMissing ||
              _lastRouteReferenceOnly != widget.routeReferenceOnly) {
            await checked(
              style.setStyleLayerProperty(
                routeLayerId,
                'line-color',
                widget.routeReferenceOnly ? '#64748B' : '#1E88E5',
              ),
            );
            await checked(
              style.setStyleLayerProperty(
                routeLayerId,
                'line-dasharray',
                widget.routeReferenceOnly ? [1.5, 1.5] : [1.0, 0.0],
              ),
            );
            if (await checked(
              style.styleLayerExists('route-direction-layer'),
            )) {
              await checked(
                style.setStyleLayerProperty(
                  'route-direction-layer',
                  'visibility',
                  widget.routeReferenceOnly ? 'none' : 'visible',
                ),
              );
            }
          }
        } else {
          if (await checked(style.styleLayerExists('route-direction-layer')))
            await checked(style.removeStyleLayer('route-direction-layer'));
          if (await checked(style.styleLayerExists(routeLayerId)))
            await checked(style.removeStyleLayer(routeLayerId));
          if (await checked(style.styleSourceExists(routeSourceId)))
            await checked(style.removeStyleSource(routeSourceId));
        }
        _lastRouteGeoJsonString = routeData;
        _lastRouteReferenceOnly = widget.routeReferenceOnly;
      }
      if (_lastDestinationJson != destinationJson) {
        const source = 'navigation-destination';
        if (await checked(style.styleSourceExists(source))) {
          await checked(
            style.setStyleSourceProperty(source, 'data', destinationJson),
          );
        } else {
          await checked(
            style.addSource(GeoJsonSource(id: source, data: destinationJson)),
          );
        }
        if (!await checked(style.styleLayerExists('destination-dot'))) {
          await checked(
            style.addLayer(
              CircleLayer(
                id: 'destination-dot',
                sourceId: source,
                circleColor: 0xFF1565C0,
                circleRadius: 7,
                circleStrokeColor: 0xFFFFFFFF,
                circleStrokeWidth: 3,
              ),
            ),
          );
          await checked(
            style.addLayer(
              SymbolLayer(
                id: 'destination-label',
                sourceId: source,
                textField: 'Destination',
                textSize: 13,
                textColor: 0xFF1565C0,
                textHaloColor: 0xFFFFFFFF,
                textHaloWidth: 2,
                textOffset: [0, 1.5],
              ),
            ),
          );
        }
        _lastDestinationJson = destinationJson;
      }
      if (widget.awareness != null) {
        for (final id in [
          'roads-layer',
          'roads-glow-layer',
          'roads-unconfirmed-layer',
          'admin-selected-road',
        ]) {
          if (await checked(style.styleLayerExists(id))) {
            await checked(
              style.setStyleLayerProperty(
                id,
                'visibility',
                widget.awareness!.safePaths ? 'visible' : 'none',
              ),
            );
          }
        }
      }
      _lastSafePaths = widget.awareness?.safePaths ?? true;
      _loadState.overlaysLoaded();
    } on _ObsoleteMapDraw {
      // A disposed map or a newer style owns subsequent writes.
    } catch (e) {
      _loadState.overlaysFailed();
      debugPrint('[AppMap] Error drawing overlays: $e');
    } finally {
      _isDrawing = false;
      _refreshNoah();
      if (_drawPending) {
        _drawPending = false;
        _drawData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapWidget(
          key: ValueKey(_mapKey),
          styleUri: _styleUri,
          // Keep the pinned SDK's texture-based hosting default. A separate
          // SurfaceView can resurface over report/profile routes when an
          // external camera or gallery activity returns to Flutter.
          textureView: true,
          onMapCreated: _onMapCreated,
          onTapListener: _onMapTapped,
          onScrollListener: (_) => widget.onUserPan?.call(),
          onCameraChangeListener: widget.onCameraChanged == null
              ? null
              : (event) => widget.onCameraChanged?.call(event.cameraState),
          onMapIdleListener: (_) async {
            widget.onCameraIdle?.call();
            final map = _mapboxMap;
            final epoch = _styleEpoch;
            if (map == null || widget.awareness == null) return;
            try {
              final camera = await map.getCameraState();
              if (mounted &&
                  identical(map, _mapboxMap) &&
                  epoch == _styleEpoch) {
                widget.awareness?.observeCenter(
                  camera.center.coordinates.lng.toDouble(),
                  camera.center.coordinates.lat.toDouble(),
                );
              }
            } catch (_) {
              /* Optional awareness location does not change navigation. */
            }
          },
          onStyleLoadedListener: (StyleLoadedEventData data) async {
            if (!mounted) return;
            _styleEpoch++;
            _styleReady = true;
            _noahRenderKey = null;
            _lastSafePaths = null;
            _lastRoadsGeoJsonString = null;
            _lastSelectedRoadId = null;
            _lastRouteGeoJsonString = null;
            _lastTravelledJson = null;
            _lastDestinationJson = null;
            _lastNavigationMode = null;
            _lastRouteReferenceOnly = null;
            final map = _mapboxMap;
            if (map != null) _updateLocationIcon(map);
            debugPrint('[AppMap] Style loaded successfully!');
            _drawData();
            try {
              if (_mapboxMap != null) {
                // Add the Mapbox composite source for buildings if it exists in the style
                await _mapboxMap!.style.addStyleLayer(
                  jsonEncode({
                    'id': '3d-buildings',
                    'source': 'composite',
                    'source-layer': 'building',
                    'filter': ['==', 'extrude', 'true'],
                    'type': 'fill-extrusion',
                    'minzoom': 15,
                    'paint': {
                      'fill-extrusion-color': '#aaaaaa',
                      'fill-extrusion-height': [
                        'interpolate',
                        ['linear'],
                        ['zoom'],
                        15,
                        0,
                        15.05,
                        ['get', 'height'],
                      ],
                      'fill-extrusion-base': [
                        'interpolate',
                        ['linear'],
                        ['zoom'],
                        15,
                        0,
                        15.05,
                        ['get', 'min_height'],
                      ],
                      'fill-extrusion-opacity': 0.6,
                    },
                  }),
                  null,
                );
              }
            } catch (e) {
              debugPrint('[AppMap] Could not add 3D buildings layer: $e');
            }
          },
          onMapLoadedListener: (MapLoadedEventData data) {
            _loadState.loaded();
          },
          onMapLoadErrorListener: (MapLoadingErrorEventData data) {
            if (data.message.contains('safepaths-sedan-v1.glb') ||
                (data.message.contains('location-indicator') &&
                    data.message.toLowerCase().contains('model'))) {
              _carModelFailed = true;
              _locationUsesCar = false;
              final map = _mapboxMap;
              if (map != null) _updateLocationIcon(map);
              return;
            }
            if (data.sourceId == 'noah-awareness-source') {
              _noahRenderKey = null;
              widget.awareness?.renderFailed();
              return;
            }
            _loadState.failed();
            debugPrint('[AppMap] Map load failed: ${data.type}');
          },
          cameraOptions: CameraOptions(
            padding: widget.initialCameraPadding,
            center: Point(
              coordinates:
                  widget.initialCenter ??
                  Position(
                    AppEnvironment.area.longitude,
                    AppEnvironment.area.latitude,
                  ), // Barangay Marulas, Valenzuela City
            ),
            zoom: widget.initialCenter == null ? 14.5 : 16,
            pitch: 60.0,
            bearing: -15.0,
          ),
        ),

        if (widget.showStatusBanner)
          Positioned(
            top:
                MediaQuery.of(context).padding.top +
                (widget.showSearchButton ? 148 : 8),
            left: 12,
            right: 12,
            child: MapStatusBanner(status: _loadState, onRetry: _retryMap),
          ),

        if (widget.showSearchButton)
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: const Color(0xFF005AB6).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF005AB6), Color(0xFF1672DF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF005AB6).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: tr(context, 'Search street or road...'),
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (value) async {
                        final query = value.trim();
                        if (query.isNotEmpty) {
                          _searchController.clear();
                          final role = await UserService.getUserRole();
                          if (role == UserRole.admin) {
                            fetchRoadGeometry(query);
                          } else {
                            _userSearchAndHighlight(query);
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ObsoleteMapDraw implements Exception {
  const _ObsoleteMapDraw();
}
