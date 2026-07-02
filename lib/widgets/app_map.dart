import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/app_state_service.dart';
import '../services/user_service.dart';
import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../../utils/constants.dart';
import '../screens/user/road_details_screen.dart';

class AppMap extends StatefulWidget {
  final bool showSearchButton;
  final Function(MapboxMap mapboxMap)? onMapCreatedCallback;
  final Function(String roadId, Position? tappedPosition)? onRoadTapped;
  final List<Position>? routePoints;
  const AppMap({
    super.key,
    this.showSearchButton = false,
    this.onMapCreatedCallback,
    this.onRoadTapped,
    this.routePoints,
  });
 
  @override
  State<AppMap> createState() => AppMapState();
}
 
class AppMapState extends State<AppMap> {
  MapboxMap? _mapboxMap;
  
  final TextEditingController _searchController = TextEditingController();
  bool _isDrawing = false;
  bool _drawPending = false;
 
  static final String _publicToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
 
  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_publicToken);
    AppStateService.instance.addListener(_onStateChanged);
    SimulatedWeatherService.instance.listenable.addListener(_onWeatherChanged);
  }
 
  @override
  void dispose() {
    AppStateService.instance.removeListener(_onStateChanged);
    SimulatedWeatherService.instance.listenable.removeListener(_onWeatherChanged);
    _searchController.dispose();
    super.dispose();
  }
 
  void _onStateChanged() {
    if (mounted) {
      setState(() {});
      _drawData();
    }
  }

  void _onWeatherChanged() {
    if (mounted) {
      setState(() {});
      _drawData();
    }
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
              if (widget.onRoadTapped != null) {
                widget.onRoadTapped!(roadId, ctx.point.coordinates);
              } else {
                Navigator.of(context).push(RoadDetailsScreen.route(roadId));
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
        RenderedQueryOptions(layerIds: null, filter: null)
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
            if (!name.contains('barangay') && !name.contains('approximate') && !name.contains('philippines') && !name.contains('city')) {
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
            final String featureClass = (props['class'] ?? '').toString().toLowerCase();
            final String featureType = (props['type'] ?? '').toString().toLowerCase();
            if (featureClass == 'street' || featureClass == 'road' || featureClass == 'motorway' || featureClass == 'primary' || featureClass == 'secondary' || featureClass == 'tertiary' || featureType == 'road') {
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
             if (!nameLower.contains('barangay') && !nameLower.contains('city') && !nameLower.contains('philippines') && !nameLower.contains('approximate')) {
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not detect street name. Please type it in the Search bar above.')));
        }
      }
    } catch (e) {
      debugPrint('[AppMap] Error querying map for road name: $e');
    }
  }

  Future<void> fetchRoadGeometry(String roadName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fetching geometry for "$roadName"...')));

    // Clean up name to match OSM easier (remove suffixes)
    String cleanName = roadName.toLowerCase();
    cleanName = cleanName.replaceAll(RegExp(r'\s+street$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+st\.?$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+road$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+rd\.?$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+avenue$'), '');
    cleanName = cleanName.replaceAll(RegExp(r'\s+ave\.?$'), '');

    // Use the exact polygon boundary of Barangay Marulas
    final String query = '''
      [out:json];
      (
        way["name"~"$cleanName",i](poly:"${Constants.marulasPoly}");
        relation["name"~"$cleanName",i](poly:"${Constants.marulasPoly}");
        way(r);
      );
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
          final elements = data['elements'] as List;
          
          // Aggregate ALL segments that match this road name into a single MultiLineString structure
          final List<List<Map<String, dynamic>>> allSegments = [];

          for (final way in elements) {
            if (way['geometry'] != null) {
              final coordinates = way['geometry'].map((g) => {
                'lon': g['lon'],
                'lat': g['lat']
              }).cast<Map<String, dynamic>>().toList();
              
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
                    coordinates: Position(firstCoord['lon'] as num, firstCoord['lat'] as num),
                  ),
                  zoom: 16.0, // Zoom in closer
                ),
                MapAnimationOptions(duration: 1500) // 1.5 seconds smooth animation
              );
            }

            // Wrap segments in a map to avoid Firestore nested array crash
            final firestoreSafeSegments = allSegments.map((seg) => {'points': seg}).toList();

            // Open dialog to save ALL segments
            if (mounted) {
              _showAddRoadDialog(roadName, {
                'type': 'MultiLineString',
                'segments': firestoreSafeSegments,
              });
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
          final middleIndex = coordsDyn.length ~/ 2;
          final middleCoord = coordsDyn[middleIndex];
            
          double? lon;
          double? lat;
            
          if (middleCoord is Map) {
            lon = (middleCoord['lon'] as num?)?.toDouble();
            lat = (middleCoord['lat'] as num?)?.toDouble();
          } else if (middleCoord is List && middleCoord.length >= 2) {
            lon = (middleCoord[0] as num?)?.toDouble();
            lat = (middleCoord[1] as num?)?.toDouble();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error: Could not connect to map service.')),
        );
      }
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

        List<List<List<double>>> allSegmentsCoords = [];

        // Check if geometry contains 'segments' (our Firestore-safe MultiLineString)
        bool isMultiSegment = road.geometry!.containsKey('segments');
        final segmentsDyn = road.geometry!['segments'] as List<dynamic>?;
        
        if (isMultiSegment && segmentsDyn != null) {
          for (var segmentWrapper in segmentsDyn) {
            if (segmentWrapper is Map && segmentWrapper.containsKey('points')) {
              var segmentDyn = segmentWrapper['points'];
              if (segmentDyn is List) {
                List<List<double>> segCoords = [];
                for (var pt in segmentDyn) {
                  if (pt is Map) {
                    final lon = (pt['lon'] as num?) ?? (pt['lng'] as num?);
                    final lat = pt['lat'] as num?;
                    if (lon != null && lat != null) {
                      segCoords.add([lon.toDouble(), lat.toDouble()]);
                    }
                  }
                }
                if (segCoords.isNotEmpty) {
                  allSegmentsCoords.add(segCoords);
                }
              }
            }
          }
        } else if (coordsDyn != null) {
          // Old single-segment format
          List<List<double>> geojsonCoords = [];
          for (final pt in coordsDyn) {
            if (pt is Map) {
              final lon = (pt['lon'] as num?) ?? (pt['lng'] as num?);
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
          if (geojsonCoords.isNotEmpty) {
            allSegmentsCoords.add(geojsonCoords);
          }
        }

        if (allSegmentsCoords.isEmpty) continue;

        final weatherState = SimulatedWeatherService.instance.currentState;
        final effectiveStatus = road.getEffectiveStatus(weatherState);

        String colorHex = '#006E1C';
        if (effectiveStatus == 'partial') {
          colorHex = '#EAB308';
        } else if (effectiveStatus == 'not_passable') {
          colorHex = '#B81311';
        }

        String glowHex = 'rgba(0, 0, 0, 0.0)'; // Transparent by default
        if (road.riskCategory == 'Critical') {
          glowHex = 'rgba(255, 0, 0, 0.5)'; // Red 50%
        } else if (road.riskCategory == 'Warning') {
          glowHex = 'rgba(255, 165, 0, 0.4)'; // Orange 40%
        } else if (road.riskCategory == 'Watch') {
          glowHex = 'rgba(255, 255, 0, 0.3)'; // Yellow 30%
        }

        for (int i = 0; i < allSegmentsCoords.length; i++) {
          features.add({
            'type': 'Feature',
            'id': '${road.id}_$i',
            'geometry': {
              'type': 'LineString',
              'coordinates': allSegmentsCoords[i],
            },
            'properties': {
              'id': road.id,
              'name': road.name,
              'status': effectiveStatus, // Using effective status for clicks
              'color': colorHex,
              'glowColor': glowHex,
            },
          });
        }
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
      final glowLayerId = 'roads-glow-layer';

      if (!await style.styleLayerExists(glowLayerId)) {
        await style.addLayer(LineLayer(
          id: glowLayerId,
          sourceId: sourceId,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineColorExpression: ['to-color', ['get', 'glowColor']],
          lineWidth: 16.0, // Wider for glow effect
        ));
      }

      if (!layerExists) {
        await style.addLayer(LineLayer(
          id: layerId,
          sourceId: sourceId,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineColorExpression: ['to-color', ['get', 'color']],
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
          styleUri: 'mapbox://styles/jayceerecana/cmqk7pl2d000a01rdfw0ubgo0',
          androidHostingMode: AndroidPlatformViewHostingMode.HC,
          textureView: false,
          onMapCreated: _onMapCreated,
          onTapListener: _onMapTapped,
          onStyleLoadedListener: (StyleLoadedEventData data) async {
            debugPrint('[AppMap] Style loaded successfully!');
            _drawData();
            try {
              if (_mapboxMap != null) {
                // Add the Mapbox composite source for buildings if it exists in the style
                await _mapboxMap!.style.addStyleLayer(jsonEncode({
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
                      ['get', 'height']
                    ],
                    'fill-extrusion-base': [
                      'interpolate',
                      ['linear'],
                      ['zoom'],
                      15,
                      0,
                      15.05,
                      ['get', 'min_height']
                    ],
                    'fill-extrusion-opacity': 0.6
                  }
                }), null);
              }
            } catch (e) {
              debugPrint('[AppMap] Could not add 3D buildings layer: $e');
            }
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
            zoom: 14.5,
            pitch: 60.0,
            bearing: -15.0,
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