import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../services/app_state_service.dart';
import '../services/user_service.dart';
import '../screens/user/road_details_screen.dart';
 
class AppMap extends StatefulWidget {
  final bool showSearchButton;
  const AppMap({super.key, this.showSearchButton = false});
 
  @override
  State<AppMap> createState() => _AppMapState();
}
 
class _AppMapState extends State<AppMap> implements OnPolylineAnnotationClickListener {
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineManager;
  
  final Map<String, String> _annotationIdToRoadId = {};
  final TextEditingController _searchController = TextEditingController();
 
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
 
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    debugPrint('[AppMap] Map created successfully!');
    
    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _polylineManager?.addOnPolylineAnnotationClickListener(this);

    _drawData();
  }

  @override
  void onPolylineAnnotationClick(PolylineAnnotation annotation) {
    final roadId = _annotationIdToRoadId[annotation.id];
    if (roadId != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => RoadDetailsScreen(roadId: roadId),
      );
    }
  }

  void _onMapTapped(MapContentGestureContext ctx) async {
    final role = await UserService.getUserRole();
    if (role != UserRole.admin) return;

    if (_mapboxMap == null) return;
    
    final screenCoordinate = await _mapboxMap!.pixelForCoordinate(ctx.point);
    final features = await _mapboxMap!.queryRenderedFeatures(
      RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
      RenderedQueryOptions(layerIds: null, filter: null)
    );

    String? roadName;
    for (final feature in features) {
      final props = feature?.queriedFeature?.feature['properties'] as Map?;
      if (props != null && props.containsKey('name')) {
        roadName = props['name'];
        break;
      }
    }

    if (roadName != null && roadName.isNotEmpty) {
      await _fetchRoadGeometry(roadName);
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
                    if (mounted) {
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
    if (_polylineManager == null || _mapboxMap == null) return;
    
    await _polylineManager!.deleteAll();
    _annotationIdToRoadId.clear();

    List<PolylineAnnotationOptions> optionsList = [];
    List<String> roadIds = [];

    debugPrint('[_drawData] Fetching roads: \${AppStateService.instance.roads.length}');

    for (var road in AppStateService.instance.roads) {
      if (road.geometry == null) {
        debugPrint('[_drawData] Road \${road.name} has no geometry');
        continue;
      }
      
      final coordsDyn = road.geometry!['coordinates'] as List<dynamic>?;
      if (coordsDyn == null) {
        debugPrint('[_drawData] Road \${road.name} has null coordinates array');
        continue;
      }

      try {
        List<Position> points = coordsDyn.map((c) {
          final pt = c as Map;
          return Position(pt['lon'] as num, pt['lat'] as num);
        }).toList();

        debugPrint('[_drawData] Road \${road.name} has \${points.length} points');

        int colorCode = 0xFF006E1C; 
        if (road.status == 'partial') {
          colorCode = 0xFFEAB308; 
        } else if (road.status == 'not_passable') {
          colorCode = 0xFFB81311; 
        }

        optionsList.add(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: points),
            lineColor: colorCode,
            lineWidth: 6.0,
            lineOpacity: 0.9,
            lineJoin: LineJoin.ROUND,
          ),
        );
        roadIds.add(road.id);
      } catch (e) {
        debugPrint('[_drawData] Error processing road \${road.name}: $e');
      }
    }

    if (optionsList.isNotEmpty) {
      debugPrint('[_drawData] Creating \${optionsList.length} polylines');
      final annotations = await _polylineManager!.createMulti(optionsList);
      for (int i = 0; i < annotations.length; i++) {
        final annotation = annotations[i];
        if (annotation != null) {
          _annotationIdToRoadId[annotation.id] = roadIds[i];
        }
      }
      debugPrint('[_drawData] Done creating polylines');
    }
  }
 
  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search Road'),
          content: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: 'e.g., MacArthur Highway',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005AB6)),
              onPressed: () {
                Navigator.pop(context);
                if (searchController.text.trim().isNotEmpty) {
                  _fetchRoadGeometry(searchController.text.trim());
                }
              },
              child: const Text('Search', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
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
          FutureBuilder<UserRole?>(
            future: UserService.getUserRole(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == UserRole.admin) {
                return Positioned(
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
                            onSubmitted: (value) {
                              final query = value.trim();
                              if (query.isNotEmpty) {
                                _searchController.clear();
                                _fetchRoadGeometry(query);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
      ],
    );
  }
}