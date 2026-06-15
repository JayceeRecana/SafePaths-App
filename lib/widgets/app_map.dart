import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/app_state_service.dart';
 
class AppMap extends StatefulWidget {
  const AppMap({super.key});
 
  @override
  State<AppMap> createState() => _AppMapState();
}
 
class _AppMapState extends State<AppMap> {
  MapboxMap? _mapboxMap;
 
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
    super.dispose();
  }
 
  void _onStateChanged() {
    _drawData();
  }
 
  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('[AppMap] Map created successfully!');
    _drawData();
  }
 
  void _drawData() async {
    if (_mapboxMap == null) return;
    // Implementation for drawing road lines and markers will go here
  }
 
  @override
  Widget build(BuildContext context) {
    return MapWidget(
      styleUri: MapboxStyles.MAPBOX_STREETS,
      androidHostingMode: AndroidPlatformViewHostingMode.HC,
      textureView: false,
      onMapCreated: _onMapCreated,
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
    );
  }
}