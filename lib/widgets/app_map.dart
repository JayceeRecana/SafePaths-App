import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../services/app_state_service.dart';
import '../services/user_service.dart';
import '../screens/user/road_details_screen.dart';
 
class AppMap extends StatefulWidget {
  final bool showSearchButton;
  final Function(MapboxMap mapboxMap)? onMapCreatedCallback;
  final List<Position>? routePoints;
  const AppMap({
    super.key,
    this.showSearchButton = false,
    this.onMapCreatedCallback,
    this.routePoints,
  });
 
  @override
  State<AppMap> createState() => _AppMapState();
}
 
class _AppMapState extends State<AppMap> {
  MapboxMap? _mapboxMap;
  
  final TextEditingController _searchController = TextEditingController();
  bool _isDrawing = false;
  bool _drawPending = false;
 
  static const String _publicToken =
      'pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTlldHMweDAyOGYzMnM3a202dWc1encifQ.3bSUr0nz6i29AtlnB2HlHw';
 
  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_publicToken);
    AppStateService.instance.addListener(_onStateChanged);
  }
 
  @override
  void dispose() {
    AppStateService.instance.removeListener(_onStateChanged);
    _searchController.dispose();
    super.dispose();
  }
 
  void _onStateChanged() {
    _drawData();
  }

  @override
  void didUpdateWidget(covariant AppMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routePoints != oldWidget.routePoints) {
      _drawData();
      if (widget.routePoints != null && widget.routePoints!.isNotEmpty && _mapboxMap != null) {
        final firstPt = widget.routePoints!.first;
        _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: firstPt),
            zoom: 14.5,
          ),
          MapAnimationOptions(duration: 1500),
        );
      }
    }
  }
 
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    debugPrint('[AppMap] Map created successfully!');
    
    try {
      await _mapboxMap!.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
      ));
    } catch (e) {
      debugPrint('[AppMap] Error enabling location puck: $e');
    }

    if (widget.onMapCreatedCallback != null) {
      widget.onMapCreatedCallback!(mapboxMap);
    }
    _drawData();
  }

  void _onMapTapped(MapContentGestureContext ctx) async {
    if (_mapboxMap == null) return;

    final screenCoordinate = await _mapboxMap!.pixelForCoordinate(ctx.point);
    if (!mounted) return;

    // 1. Try to query our custom flood-monitored roads layer first (for both users and admins)
    try {
      final roadFeatures = await _mapboxMap!.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
        RenderedQueryOptions(layerIds: ['roads-layer'], filter: null),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoadDetailsScreen(roadId: roadId),
                ),
              );
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
        RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
        RenderedQueryOptions(layerIds: null, filter: null)
      );

      String? roadName;
      for (final feature in features) {
        final props = feature?.queriedFeature.feature['properties'] as Map?;
        if (props != null && props.containsKey('name')) {
          roadName = props['name'];
          break;
        }
      }

      if (roadName != null && roadName.isNotEmpty) {
        await _fetchRoadGeometry(roadName);
      }
    } catch (e) {
      debugPrint('[AppMap] Error querying map for road name: $e');
    }
  }

  Future<void> _fetchRoadGeometry(String roadName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fetching geometry for "$roadName"...')));

    final String query = '''
      [out:json];
      way["name"~"$roadName",i](14.6740, 120.9810, 14.6820, 120.9890);
      out geom;
    ''';
    
    final url = Uri.parse('https://overpass-api.de/api/interpreter');
    try {
      final response = await http.post(
        url,
        headers: {
          'User-Agent': 'SafePathsApp/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'data': query
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['elements'] != null && data['elements'].isNotEmpty) {
          final way = data['elements'][0];
          if (way['geometry'] != null) {
            final coordinates = way['geometry'].map((g) => {
              'lon': g['lon'],
              'lat': g['lat']
            }).toList();
            
            // FLY CAMERA TO THE FOUND ROAD
            if (coordinates.isNotEmpty && _mapboxMap != null) {
              final firstCoord = coordinates[0];
              _mapboxMap!.flyTo(
                CameraOptions(
                  center: Point(
                    coordinates: Position(firstCoord['lon'] as num, firstCoord['lat'] as num),
                  ),
                  zoom: 16.0, // Zoom in closer
                ),
                MapAnimationOptions(duration: 1500) // 1.5 seconds smooth animation
              );
            }

            final geometry = {
              "type": "LineString",
              "coordinates": coordinates
            };
            if (mounted) {
              _showAddRoadDialog(roadName, geometry);
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Road "$roadName" not found in Marulas')));
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch from Overpass API')));
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
        final coordsDyn = matchedRoad.geometry!['coordinates'] as List<dynamic>?;
        if (coordsDyn != null && coordsDyn.isNotEmpty) {
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

    // 2. Query Mapbox Geocoding API within Barangay Marulas bounding box
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
      '?access_token=$_publicToken'
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
      debugPrint('[AppMap] Geocoding error: $e');
    }
  }

  void _showAddRoadDialog(String roadName, Map<String, dynamic> geometry) {
    String selectedStatus = 'not_passable';
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Add Road: $roadName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'passable', child: Text('Passable (Green)')),
                      DropdownMenuItem(value: 'partial', child: Text('Partial (Yellow)')),
                      DropdownMenuItem(value: 'not_passable', child: Text('Not Passable (Red)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => selectedStatus = val);
                    },
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Admin Notes'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005AB6)),
                  onPressed: () async {
                    Navigator.pop(context);
                    // Sanitize road ID to prevent invalid Firestore paths (e.g. from slashes)
                    final roadId = roadName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                    await AppStateService.instance.updateRoadStatus(
                      roadId,
                      selectedStatus,
                      notesController.text,
                      geometry: geometry,
                      name: roadName,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Road "$roadName" added!')));
                    }
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }
 
  void _drawData() async {
    if (_mapboxMap == null) return;
    if (_isDrawing) {
      _drawPending = true;
      return;
    }
    _isDrawing = true;

    try {
      final roads = AppStateService.instance.roads;
      final features = <Map<String, dynamic>>[];

      for (var road in roads) {
        if (road.geometry == null) continue;

        final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
        if (coordsDyn == null) continue;

        List<List<double>> geojsonCoords = [];
        for (final pt in coordsDyn) {
          if (pt is Map) {
            final lon = pt['lon'] as num?;
            final lat = pt['lat'] as num?;
            if (lon != null && lat != null) {
              geojsonCoords.add([lon.toDouble(), lat.toDouble()]);
            }
          } else if (pt is List && pt.length >= 2) {
            final lon = pt[0] as num?;
            final lat = pt[1] as num?;
            if (lon != null && lat != null) {
              geojsonCoords.add([lon.toDouble(), lat.toDouble()]);
            }
          }
        }

        if (geojsonCoords.isEmpty) continue;

        String colorHex = '#006E1C';
        if (road.status == 'partial') {
          colorHex = '#EAB308';
        } else if (road.status == 'not_passable') {
          colorHex = '#B81311';
        }

        features.add({
          'type': 'Feature',
          'id': road.id,
          'geometry': {
            'type': 'LineString',
            'coordinates': geojsonCoords,
          },
          'properties': {
            'id': road.id,
            'name': road.name,
            'status': road.status,
            'color': colorHex,
          },
        });
      }

      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      final geoJsonString = jsonEncode(geoJson);
      final sourceId = 'roads-source';
      final layerId = 'roads-layer';

      final style = _mapboxMap!.style;
      final sourceExists = await style.styleSourceExists(sourceId);

      if (sourceExists) {
        final source = await style.getSource(sourceId);
        if (source is GeoJsonSource) {
          await source.updateGeoJSON(geoJsonString);
        }
      } else {
        await style.addSource(GeoJsonSource(id: sourceId, data: geoJsonString));
      }

      final layerExists = await style.styleLayerExists(layerId);
      if (!layerExists) {
        await style.addLayer(LineLayer(
          id: layerId,
          sourceId: sourceId,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineColorExpression: ['get', 'color'],
          lineWidth: 6.0,
        ));
      }

      // Draw route if provided
      final routeSourceId = 'route-source';
      final routeLayerId = 'route-layer';
      if (widget.routePoints != null && widget.routePoints!.isNotEmpty) {
        final routeGeoJson = {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': widget.routePoints!.map((p) => [p.lng, p.lat]).toList(),
          },
          'properties': {},
        };
        final routeGeoJsonString = jsonEncode(routeGeoJson);

        if (await style.styleSourceExists(routeSourceId)) {
          final source = await style.getSource(routeSourceId);
          if (source is GeoJsonSource) {
            await source.updateGeoJSON(routeGeoJsonString);
          }
        } else {
          await style.addSource(GeoJsonSource(id: routeSourceId, data: routeGeoJsonString));
        }

        if (!await style.styleLayerExists(routeLayerId)) {
          await style.addLayer(LineLayer(
            id: routeLayerId,
            sourceId: routeSourceId,
            lineJoin: LineJoin.ROUND,
            lineCap: LineCap.ROUND,
            lineColor: 0xFF1E88E5, // Premium Blue for route
            lineWidth: 8.0,
          ));
        }
      } else {
        if (await style.styleLayerExists(routeLayerId)) {
          await style.removeStyleLayer(routeLayerId);
        }
        if (await style.styleSourceExists(routeSourceId)) {
          await style.removeStyleSource(routeSourceId);
        }
      }
    } catch (e) {
      debugPrint('[AppMap] Error drawing data: $e');
    } finally {
      _isDrawing = false;
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
          styleUri: MapboxStyles.MAPBOX_STREETS,
          androidHostingMode: AndroidPlatformViewHostingMode.HC,
          textureView: false,
          onMapCreated: _onMapCreated,
          onTapListener: _onMapTapped,
          onStyleLoadedListener: (StyleLoadedEventData data) {
            debugPrint('[AppMap] Style loaded successfully!');
            _drawData();
          },
          onMapLoadedListener: (MapLoadedEventData data) {
            debugPrint('[AppMap] Map fully loaded with tiles!');
          },
          onMapLoadErrorListener: (MapLoadingErrorEventData data) {
            debugPrint('[AppMap] MAP LOAD ERROR: ${data.type} — ${data.message}');
          },
          cameraOptions: CameraOptions(
            center: Point(
              coordinates: Position(120.9842, 14.6761), // Barangay Marulas, Valenzuela City
            ),
            zoom: 14.0,
          ),
        ),
        if (widget.showSearchButton)
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
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
                  color: const Color(0xFFC1C6D5).withValues(alpha: 0.3),
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
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF191C1E),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search street or road...',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF727785),
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
                            _fetchRoadGeometry(query);
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