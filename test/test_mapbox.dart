import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<Test> createState() => _TestState();
}

class _TestState extends State<Test> {
  MapboxMap? _mapboxMap;
  
  @override
  Widget build(BuildContext context) {
    return MapWidget(
      onMapCreated: (map) => _mapboxMap = map,
      onTapListener: (MapContentGestureContext ctx) async {
        if (_mapboxMap == null) return;
        final screenCoordinate = await _mapboxMap!.pixelForCoordinate(ctx.point);
        final features = await _mapboxMap!.queryRenderedFeatures(
          RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
          RenderedQueryOptions(layerIds: null, filter: null)
        );
        for (final feature in features) {
          final props = feature?.queriedFeature.feature['properties'] as Map?;
          if (props != null && props.containsKey('name')) {
            print(props['name']);
            break;
          }
        }
      },
    );
  }
}
