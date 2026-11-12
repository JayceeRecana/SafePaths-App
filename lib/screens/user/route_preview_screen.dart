import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show
        Position,
        MapboxMap,
        Point,
        CameraOptions,
        MbxEdgeInsets,
        MapAnimationOptions;
import '../../l10n/app_strings.dart';
import '../../models/planned_route.dart';
import '../../services/app_state_service.dart';
import '../../services/map_load_state.dart';
import '../../services/routing_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/app_map.dart';
import '../../widgets/map_status_banner.dart';
import '../../widgets/planner_preview_controls.dart';
import '../../widgets/route_navigation.dart';
import 'road_details_screen.dart';

class RoutePreviewScreen extends StatefulWidget {
  final PlannedRoute route;

  /// Replaces only the native map boundary in real-screen tests.
  final Widget Function(List<Position>)? routeMapBuilder;
  const RoutePreviewScreen({
    super.key,
    required this.route,
    this.routeMapBuilder,
  });
  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  late PlannedRoute _selectedRoute;
  bool _openingNavigation = false;
  final _mapStatus = MapLoadState();
  final _mapKey = GlobalKey<AppMapState>();
  final _mapViewportKey = GlobalKey();
  final _headerKey = GlobalKey();
  MapboxMap? _map;
  List<Position>? _fitPoints;
  Size? _fitSize;
  double? _fitHeaderHeight;
  int _fitGeneration = 0;
  int _dataRevision = 0, _evaluatedRevision = -1;
  List<PlannedRoute>? _sourceSnapshot;
  List<PlannedRoute> _evaluatedRoutes = [];
  PlannedRoute? _evaluatedFallback;

  void _refresh() {
    if (mounted) setState(() => _dataRevision++);
  }

  @override
  void initState() {
    super.initState();
    _selectedRoute = widget.route;
    RoutingService.instance.addListener(_refresh);
    AppStateService.instance.mapChanges.addListener(_refresh);
    AppStateService.instance.addListener(_refresh);
    SimulatedWeatherService.instance.listenable.addListener(_refresh);
  }

  @override
  void dispose() {
    _fitGeneration++;
    RoutingService.instance.removeListener(_refresh);
    AppStateService.instance.mapChanges.removeListener(_refresh);
    AppStateService.instance.removeListener(_refresh);
    SimulatedWeatherService.instance.listenable.removeListener(_refresh);
    _mapStatus.dispose();
    super.dispose();
  }

  Future<void> _navigate(PlannedRoute route) async {
    if (_openingNavigation || !route.canStartNavigation) return;
    setState(() => _openingNavigation = true);
    try {
      await startRouteNavigation(context, route, replacePreview: true);
    } finally {
      if (mounted) setState(() => _openingNavigation = false);
    }
  }

  void _scheduleFit(List<Position> points) {
    if (widget.routeMapBuilder != null || _map == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_fitRoute(points)),
    );
  }

  Future<void> _fitRoute(List<Position> points) async {
    final map = _map;
    if (!mounted ||
        map == null ||
        points.length < 2 ||
        points.any((p) => !p.lat.isFinite || !p.lng.isFinite)) {
      return;
    }
    final size = _mapViewportKey.currentContext?.size;
    final header = _headerKey.currentContext?.size?.height ?? 80;
    if (size == null || size.height < 60 || size.width < 60) return;
    if (identical(_fitPoints, points) &&
        _fitSize == size &&
        _fitHeaderHeight == header) {
      return;
    }
    _fitPoints = points;
    _fitSize = size;
    _fitHeaderHeight = header;
    final generation = ++_fitGeneration;
    try {
      final camera = await map.cameraForCoordinatesPadding(
        points.map((p) => Point(coordinates: p)).toList(),
        CameraOptions(bearing: 0, pitch: 0),
        MbxEdgeInsets(
          top: math.min(header + 20, size.height * .45),
          left: 24,
          bottom: 24,
          right: 24,
        ),
        17,
        null,
      );
      if (!mounted || generation != _fitGeneration || !identical(map, _map)) {
        return;
      }
      await map.flyTo(camera, MapAnimationOptions(duration: 650));
    } catch (_) {
      // A camera-fit failure does not replace routing or remove manual map gestures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = RoutingService.instance;
    final sourceRoutes = service.routes;
    if (_evaluatedRevision != _dataRevision ||
        !identical(_sourceSnapshot, sourceRoutes)) {
      _sourceSnapshot = sourceRoutes;
      _evaluatedRevision = _dataRevision;
      _evaluatedRoutes = sourceRoutes
          .map((r) => service.refreshRoute(r))
          .toList();
      _evaluatedFallback = service.refreshRoute(_selectedRoute);
    }
    final options = <PreviewRouteOption>[
      for (var i = 0; i < sourceRoutes.length; i++)
        PreviewRouteOption(
          _evaluatedRoutes[i],
          i == 0
              ? tr(context, 'Best available')
              : '${tr(context, 'Alternative')} $i',
        ),
    ];
    var selectedIndex = options.indexWhere(
      (o) => identical(o.route.points, _selectedRoute.points),
    );
    final retained = selectedIndex < 0;
    if (retained) {
      options.add(
        PreviewRouteOption(_evaluatedFallback!, tr(context, 'Selected route')),
      );
      selectedIndex = options.length - 1;
    }
    final active = options[selectedIndex].route;
    final title = !retained && selectedIndex == 0
        ? tr(context, 'Best available route')
        : options[selectedIndex].label;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) {
          // Fixed for this viewport/text scale. Content scrolls within the panel;
          // dragging must never resize it or consume the visible map.
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          final fraction = bounds.maxHeight < 500
              ? .5
              : largeText
              ? .45
              : .35;
          final panelHeight = bounds.maxHeight * fraction;
          _scheduleFit(active.points);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: panelHeight,
                child: SizedBox(
                  key: _mapViewportKey,
                  child:
                      widget.routeMapBuilder?.call(active.points) ??
                      AppMap(
                        key: _mapKey,
                        routePoints: active.points,
                        destinationPoint: active.points.isEmpty
                            ? null
                            : active.points.last,
                        loadState: _mapStatus,
                        showStatusBanner: false,
                        onMapCreatedCallback: (map) {
                          _map = map;
                          _fitPoints = null;
                          _scheduleFit(active.points);
                        },
                        onRoadTapped: (id, _) => Navigator.of(
                          context,
                        ).push(RoadDetailsScreen.route(id)),
                      ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 16,
                right: 16,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bounds.maxHeight * .3),
                  child: Column(
                    key: _headerKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RoutePreviewHeader(
                        title: title,
                        route: active,
                        onBack: () => Navigator.of(context).pop(),
                      ),
                      Flexible(
                        fit: FlexFit.loose,
                        child: SingleChildScrollView(
                          child: MapStatusBanner(
                            status: _mapStatus,
                            onRetry: () => _mapKey.currentState?.retryMap(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: panelHeight,
                child: RoutePreviewPanel(
                  options: options,
                  selectedIndex: selectedIndex,
                  opening: _openingNavigation,
                  liveDataUnavailable:
                      AppStateService.instance.requiresLiveDataWarning ||
                      SimulatedWeatherService.instance.isDataStale,
                  onSelect: (index) {
                    if (_openingNavigation) return;
                    final chosen = options[index].route;
                    setState(() => _selectedRoute = chosen);
                    final providerIndex = service.routes.indexWhere(
                      (r) => identical(r.points, chosen.points),
                    );
                    if (providerIndex >= 0) service.selectRoute(providerIndex);
                  },
                  onNavigate: active.canStartNavigation && !_openingNavigation
                      ? () => _navigate(active)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
