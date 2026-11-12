import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/road_status.dart';
import '../utils/geo_utils.dart';

/// Location only: blue lines identify selected geometry, not passability.
/// Preserve separate ways and never invent a line between disconnected pieces.
class RoadPreviewRequest {
  final double width, height;
  final bool dark;
  final int requestedCount;
  final GeoCoord? reportedPoint;
  final List<String> mappedRoadIds;
  final List<List<List<double>>> segments;
  RoadPreviewRequest(
    List<RoadStatus> roads, {
    required this.width,
    this.height = 180,
    required this.dark,
    GeoCoord? reportedPoint,
  }) : reportedPoint =
           reportedPoint != null &&
               reportedPoint.lat.isFinite &&
               reportedPoint.lng.isFinite &&
               reportedPoint.lat.abs() <= 90 &&
               reportedPoint.lng.abs() <= 180
           ? reportedPoint
           : null,
       requestedCount = roads.length,
       mappedRoadIds = [
         for (final r in roads)
           if (_segments(r).isNotEmpty) r.id,
       ],
       segments = [for (final r in roads) ..._segments(r)];
  static List<List<List<double>>> _segments(RoadStatus road) => [
    for (final segment in GeoUtils.extractSegments(road.geometry))
      if (segment.every(
        (p) =>
            p.lng.isFinite &&
            p.lat.isFinite &&
            p.lng.abs() <= 180 &&
            p.lat.abs() <= 90,
      ))
        [
          for (final p in segment) [p.lng, p.lat],
        ],
  ];
  bool get available => segments.isNotEmpty || reportedPoint != null;
  String get identity => jsonEncode([
    width,
    height,
    dark,
    requestedCount,
    mappedRoadIds,
    segments,
    if (reportedPoint != null) [reportedPoint!.lng, reportedPoint!.lat],
  ]);
  String get geoJson => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final line in segments)
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {'type': 'LineString', 'coordinates': line},
        },
    ],
  });
}

abstract class RoadPreviewCapture {
  Future<Uint8List> render(RoadPreviewRequest request);
  Future<void> cancel();
}

/// Uses the existing native SDK, not a second interactive platform view.
class MapboxRoadPreviewCapture implements RoadPreviewCapture {
  Snapshotter? _snapshot;
  final _styleReady = Completer<void>();
  bool _cancelled = false, _styleFailed = false;
  void _check() {
    if (_cancelled) throw StateError('Preview cancelled');
  }

  @override
  Future<Uint8List> render(RoadPreviewRequest request) =>
      _render(request).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          unawaited(cancel());
          throw TimeoutException('Map preview unavailable');
        },
      );
  Future<Uint8List> _render(RoadPreviewRequest request) async {
    try {
      _check();
      if (!request.available) throw StateError('No road geometry');
      if (kIsWeb || !(Platform.isAndroid || Platform.isIOS))
        throw UnsupportedError(
          'Native map previews are unavailable on this platform',
        );
      final token = dotenv.isInitialized
          ? dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? ''
          : '';
      if (token.isEmpty) throw StateError('Map configuration unavailable');
      MapboxOptions.setAccessToken(token);
      final created = await Snapshotter.create(
        options: MapSnapshotOptions(
          size: Size(width: request.width, height: request.height),
          pixelRatio: 2,
          showsLogo: true,
          showsAttribution: true,
        ),
        onStyleLoadedListener: (_) {
          if (!_styleReady.isCompleted) _styleReady.complete();
        },
        onMapLoadErrorListener: (_) {
          _styleFailed = true;
          if (!_styleReady.isCompleted) _styleReady.complete();
        },
      );
      if (_cancelled) {
        await created.dispose();
        throw StateError('Preview cancelled');
      }
      _snapshot = created;
      await created.style.setStyleURI(
        request.dark ? MapboxStyles.DARK : MapboxStyles.MAPBOX_STREETS,
      );
      _check();
      await _styleReady.future;
      _check();
      if (_styleFailed) throw StateError('Map style unavailable');
      await created.style.addSource(
        GeoJsonSource(id: 'selected-road', data: request.geoJson),
      );
      _check();
      await created.style.addLayer(
        LineLayer(
          id: 'selected-road-outline',
          sourceId: 'selected-road',
          lineColor: 0xFFFFFFFF,
          lineWidth: 9,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
      );
      _check();
      await created.style.addLayer(
        LineLayer(
          id: 'selected-road-line',
          sourceId: 'selected-road',
          lineColor: 0xFF005BBB,
          lineWidth: 5,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
      );
      _check();
      if (request.reportedPoint != null) {
        final point = request.reportedPoint!;
        await created.style.addSource(
          GeoJsonSource(
            id: 'reported-point',
            data: jsonEncode({
              'type': 'Feature',
              'properties': <String, Object>{},
              'geometry': {
                'type': 'Point',
                'coordinates': [point.lng, point.lat],
              },
            }),
          ),
        );
        _check();
        await created.style.addLayer(
          CircleLayer(
            id: 'reported-point-marker',
            sourceId: 'reported-point',
            circleRadius: 9,
            circleColor: 0xFFFFA000,
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 3,
          ),
        );
        _check();
      }
      final camera = request.segments.isEmpty && request.reportedPoint != null
          ? CameraOptions(
              center: Point(
                coordinates: Position(
                  request.reportedPoint!.lng,
                  request.reportedPoint!.lat,
                ),
              ),
              zoom: 16.5,
              bearing: 0,
              pitch: 0,
            )
          : await created.camera(
              coordinates: [
                if (request.reportedPoint != null)
                  Point(
                    coordinates: Position(
                      request.reportedPoint!.lng,
                      request.reportedPoint!.lat,
                    ),
                  ),
                for (final line in request.segments)
                  for (final p in line)
                    Point(coordinates: Position(p[0], p[1])),
              ],
              padding: MbxEdgeInsets(top: 36, left: 36, right: 36, bottom: 40),
              bearing: 0,
              pitch: 0,
            );
      _check();
      // Keep surrounding streets visible when the selected road is very short.
      if (camera.zoom != null && camera.zoom! > 17.5) camera.zoom = 17.5;
      await created.setCamera(camera);
      _check();
      final bytes = await created.start();
      _check();
      if (bytes == null || bytes.isEmpty)
        throw StateError('Map preview unavailable');
      return bytes;
    } finally {
      await cancel();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (!_styleReady.isCompleted) _styleReady.complete();
    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot != null) {
      try {
        await snapshot.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await snapshot.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}
