import '../../widgets/navigation_trip_details_sheet.dart';
import '../../widgets/navigation_car_model.dart';
import '../../utils/location_fix.dart';
import '../../utils/closure_exit_recovery.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/formatters.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../config/app_environment.dart';
import '../../services/navigation_diagnostics.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:flutter/material.dart';
import '../../services/account_security.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/planned_route.dart';
import '../../widgets/app_map.dart';
import '../../widgets/navigation_hud.dart';
import '../../widgets/road_condition_overview.dart' show residentRoadTitle;
import '../../services/app_state_service.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../services/weather_service.dart';
import '../../config/risk_config.dart';
import '../../utils/geo_utils.dart';
import '../../utils/route_tracker.dart';
import '../../utils/navigation_units.dart';

typedef NavigationRouteComputer =
    Future<List<PlannedRoute>> Function({
      required Position origin,
      required Position destination,
      required String vehicleType,
      double? headingDegrees,
      required Set<String> avoidRoadIds,
      required int maxDetourCandidates,
    });

class NavigationScreen extends StatefulWidget {
  final PlannedRoute route;
  // Injectable boundaries let tests replay trips without GPS, HTTP, or a native map.
  final Stream<geo.Position>? positionStream;
  final Future<geo.Position?> Function()? currentFix;
  final NavigationRouteComputer? routeComputer;
  final Widget Function(List<Position>)? mapBuilder;
  final DateTime Function()? now;
  final Future<Map<String, dynamic>?> Function(Position)? stagingSearch;
  final String? reviewedRiskKey;

  const NavigationScreen({
    super.key,
    required this.route,
    this.positionStream,
    this.currentFix,
    this.routeComputer,
    this.mapBuilder,
    this.now,
    this.stagingSearch,
    this.reviewedRiskKey,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late PlannedRoute _currentRoute;
  late RouteTracker _routeTracker;
  late final RerouteGate _rerouteGate;
  int _currentStepIndex = 0;
  double _liveDistanceToNextStep = 0.0;
  final Set<int> _spoken200mSteps = {};
  final Set<int> _spoken50mSteps = {};
  final FlutterTts flutterTts = FlutterTts();
  MapboxMap? _mapboxMap;

  StreamSubscription<geo.Position>? _positionSubscription;
  Position? _currentLocation;
  final _markerHeading = NavigationMarkerHeading();
  Position? _navDestination;
  String? _navDestinationName;
  geo.Position? _lastGeoPosition;
  bool _isReRouting = false;
  late final String _navVehicleType;
  bool _ttsReady = false, _gpsStreamFailed = false, _retryingGps = false;
  String? _gpsMessage = 'Waiting for a reliable GPS location.';
  Timer? _gpsFreshnessTimer;
  int _gpsRequestGeneration = 0, _gpsStreamGeneration = 0;
  int _rerouteAttempt = 0;
  PlannedRoute? _pendingRiskRoute;
  String? _pendingRiskKey, _acceptedCriticalKey;
  String _riskReviewMessage =
      'A route has critical predicted flood risk. Navigation is paused until conditions are reviewed.';
  bool _riskReviewRequired = false, _reviewingRisk = false;
  PlannedRoute? _riskPreview;
  BuildContext? _riskDialogContext;
  int _riskGeneration = 0;
  DateTime _timeNow() => widget.now?.call() ?? DateTime.now();
  bool get _hasReliableGps =>
      !_gpsStreamFailed &&
      _lastGeoPosition != null &&
      usableLocationFix(_lastGeoPosition!, now: _timeNow());
  void _gpsProblem(String message) {
    if (!mounted || (_gpsStreamFailed && _gpsMessage == message)) return;
    _closureExitRecovery.interrupt();
    setState(() {
      _gpsStreamFailed = true;
      _gpsMessage = message;
    });
    unawaited(flutterTts.stop().catchError((Object _) => null));
  }

  Future<void> _retryGps({bool restartStream = true}) async {
    if (_retryingGps) return;
    final generation = ++_gpsRequestGeneration;
    setState(() {
      _retryingGps = true;
      if (!_hasReliableGps) _gpsMessage = 'Requesting a current GPS fix...';
    });
    _diagnostics?.record('gps_retry_started');
    try {
      if (restartStream) {
        _gpsStreamGeneration++;
        await _positionSubscription?.cancel();
        if (!mounted || generation != _gpsRequestGeneration) return;
        _startLocationTracking();
      }
      // Test streams can be controlled independently of a one-shot provider.
      if (widget.currentFix != null || widget.positionStream == null) {
        final fix =
            await (widget.currentFix?.call() ?? LocationService.getCurrentFix())
                .timeout(const Duration(seconds: 20));
        if (!mounted || generation != _gpsRequestGeneration) return;
        if (fix != null) {
          _acceptPosition(fix, oneShot: true);
        } else if (!_hasReliableGps) {
          _gpsProblem(
            'No current GPS fix was received. Check location services and retry.',
          );
        }
      }
    } catch (error) {
      if (!mounted || generation != _gpsRequestGeneration) return;
      _diagnostics?.record('gps_retry_error', {
        'errorType': error.runtimeType.toString(),
      });
      if (!_hasReliableGps)
        _gpsProblem(
          'No current GPS fix was received. Check location services and retry.',
        );
    } finally {
      if (mounted && generation == _gpsRequestGeneration) {
        setState(() => _retryingGps = false);
        _diagnostics?.record('gps_retry_finished');
      }
    }
  }

  bool _hasArrived = false;
  Timer? _stalenessTimer;
  Timer? _pendingHazardTimer;
  BuildContext? _haltDialogContext;
  VoidCallback? _refreshHaltDialog;
  int _haltGeneration = 0;
  String? _pendingRouteRefresh;
  final Set<String> _pendingRefreshAvoidIds = {};
  Set<String> _lastRequestedAvoidIds = {};
  String? _lastRequestReason;
  VoidCallback? _refreshTripDetails;
  int _tripDetailsGeneration = 0;
  bool _forcePendingRouteRefresh = false;
  Timer? _pendingRouteRefreshTimer;
  final Set<String> _haltBlockingRoadIds = {};
  final _closureExitRecovery = ClosureExitRecovery();

  bool get _nearConfirmedClosure {
    final fix = _lastGeoPosition;
    if (!_hasReliableGps || fix == null || _currentLocation == null)
      return false;
    // Include GPS uncertainty: a fix just beyond the line buffer is not yet
    // evidence that the resident is clear of the closed road.
    final threshold = RiskConfig.roadCrossingBufferMeters + fix.accuracy;
    return AppStateService.instance.roads.any(
      (road) =>
          road.status == 'not_passable' &&
          RoutingService.doesRouteCrossGeometry(
            [_currentLocation!],
            road.geometry,
            thresholdMeters: threshold,
          ),
    );
  }

  void _checkClosureExitRecovery(geo.Position fix) {
    final recheck = _closureExitRecovery.observe(
      paused:
          !_hasArrived &&
          (_noClearRouteFound || _activeConfirmedHazard != null),
      reliable: _hasReliableGps,
      calculationPending:
          _isReRouting || _riskReviewRequired || _pendingRouteRefresh != null,
      nearClosure: _nearConfirmedClosure,
      fixTime: fix.timestamp,
    );
    if (!recheck) return;
    _pendingRouteRefresh =
        'Location changed. Checking routes around closed roads...';
    _pendingRefreshAvoidIds.addAll(
      AppStateService.instance.roads
          .where((r) => r.status == 'not_passable')
          .map((r) => r.id),
    );
    _processPendingRouteRefresh();
  }

  final Map<String, String> _roadStatusCache = {};
  final Map<String, String> _confirmedStatusCache = {};

  // ─── TIER 1 ADVISORY STATE ────────────────────────────────────────────────
  final Set<String> _dismissedAdvisoryRoadIds = {};
  int _advisoriesShownCount = 0;
  RoadStatus? _activeAdvisoryRoad;
  bool _collapsedAdvisoryMode = false;
  final List<RoadStatus> _unconfirmedStaleRoads = [];

  // ─── DEBOUNCE & GPS STABILITY ─────────────────────────────────────────────
  Timer? _rerouteRetryTimer;
  Timer? _adminUpdateDebounceTimer;
  NavigationDiagnostics? _diagnostics;
  RoadStatus? _activeConfirmedHazard;
  RoadStatus? _pendingConfirmedHazard;
  int _failedRetryCount = 0;
  String? _routeFailureMessage;
  String? _warningChipMessage;
  String? _routeUpdateSummary;
  String? _pendingUpdateReason;
  DateTime? _routeUpdatedAt;
  bool get _liveDataUnavailable =>
      AppStateService.instance.requiresLiveDataWarning ||
      SimulatedWeatherService.instance.isDataStale;
  late bool _lastLiveDataUnavailable;
  bool _offRoute = false;
  bool _noClearRouteFound = false, _noDifferentDetour = false;
  String? _calculationReason;
  DateTime? _routeNoticeUntil;
  Timer? _routeNoticeTimer;

  bool get _showRouteUpdate =>
      _routeUpdateSummary != null &&
      _routeNoticeUntil != null &&
      _timeNow().isBefore(_routeNoticeUntil!);

  void _clearRouteNotice() {
    _routeNoticeTimer?.cancel();
    _routeNoticeUntil = null;
  }

  String _roadLabel(String value) => residentRoadTitle(value);
  String _displayMessage(String value) =>
      value.replaceAll(RegExp(r'\s*\(OSM\s+\d+\)', caseSensitive: false), '');

  @override
  void initState() {
    super.initState();
    SessionActivity.navigating = true;
    _currentRoute = widget.route;
    _lastLiveDataUnavailable = _liveDataUnavailable;
    _acceptedCriticalKey = widget.reviewedRiskKey;
    if (AppEnvironment.isFieldTest) {
      _diagnostics = NavigationDiagnostics(now: widget.now)
        ..record('navigation_started', {
          'mode': RoutingService.instance.selectedVehicleType,
        });
    }
    _rerouteGate = RerouteGate(now: widget.now);
    final routing = RoutingService.instance;
    _navVehicleType = widget.route.vehicleType ?? routing.selectedVehicleType;
    _navDestination =
        widget.route.requestedDestination ??
        (_currentRoute.points.isNotEmpty ? _currentRoute.points.last : null);
    _navDestinationName = widget.route.destinationName;
    _routeTracker = RouteTracker(route: _currentRoute, now: widget.now);
    _currentStepIndex = _routeTracker.currentStepIndex;
    _initTts();
    _startLocationTracking();
    AppStateService.instance.addListener(_onAdminFloodUpdate);
    SimulatedWeatherService.instance.listenable.addListener(
      _onAdminFloodUpdate,
    );

    // Initial cache populate
    final weatherState = SimulatedWeatherService.instance.currentState;
    for (final r in AppStateService.instance.roads) {
      _roadStatusCache[r.id] = r.getEffectiveStatus(weatherState);
    }

    _handleAdminFloodUpdateCore();
    if (widget.currentFix != null || widget.positionStream == null)
      unawaited(_retryGps(restartStream: false));
    _gpsFreshnessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Weather freshness can expire without a new road document arriving.
      final unavailable = _liveDataUnavailable;
      if (unavailable != _lastLiveDataUnavailable) {
        _lastLiveDataUnavailable = unavailable;
        _onAdminFloodUpdate();
      }
      if (_lastGeoPosition != null && !_hasReliableGps && _gpsMessage == null) {
        _diagnostics?.record('gps_expired', {
          'fixAgeSeconds':
              _timeNow()
                  .difference(_lastGeoPosition!.timestamp)
                  .inMilliseconds /
              1000,
          'gpsOutcome': 'stale',
        });
        _gpsProblem(
          'GPS location is outdated. Guidance is paused until a fresh fix arrives.',
        );
      }
    });
    _stalenessTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkRouteStaleness();
    });
  }

  void _resetAdvisoryState() {
    _dismissedAdvisoryRoadIds.clear();
    _advisoriesShownCount = 0;
    _activeAdvisoryRoad = null;
    _collapsedAdvisoryMode = false;
    _unconfirmedStaleRoads.clear();
  }

  String? _routeConditionWarning(PlannedRoute route) {
    if (route.isBlocked)
      return 'Caution: Flooded road segment nearby on route.';
    if (route.hasUnverifiedConditions)
      return 'Current route conditions are unconfirmed. Check local updates.';
    if (route.needsCaution)
      return 'Route contains caution segments. Check current local conditions.';
    return null;
  }

  void _animateCameraToPosition(
    Position pos, {
    double zoom = 17.5,
    double pitch = 40.0,
  }) {
    if (_mapboxMap == null) return;
    try {
      _mapboxMap?.easeTo(
        CameraOptions(
          center: Point(coordinates: pos),
          zoom: zoom,
          pitch: pitch,
        ),
        MapAnimationOptions(duration: 800),
      );
    } catch (e) {
      debugPrint('[NavigationScreen] Camera animation error: $e');
    }
  }

  Future<void> _initTts() async {
    try {
      await flutterTts.setLanguage('en-US');
      await flutterTts.setPitch(1.0);
      await flutterTts.setSpeechRate(0.5);
      if (!mounted) return;
      _ttsReady = true;
      await _speakCurrentStep();
    } catch (_) {
      debugPrint('Voice guidance is unavailable.');
    }
  }

  Future<void> _speakCurrentStep() async {
    if (!mounted ||
        !_ttsReady ||
        !_hasReliableGps ||
        _hasArrived ||
        _offRoute ||
        _isReRouting ||
        _riskReviewRequired ||
        _activeConfirmedHazard != null ||
        _noClearRouteFound ||
        _routeFailureMessage != null)
      return;
    if (_currentRoute.steps.isNotEmpty &&
        _currentStepIndex < _currentRoute.steps.length) {
      final step =
          _routeTracker.initialDirectionStep ??
          _currentRoute.steps[_currentStepIndex];
      await flutterTts.speak(_stepSpeech(step));
    }
  }

  String _stepSpeech(RouteStep step) {
    final instruction = step.instruction.replaceAll(RegExp(r'<[^>]*>'), '');
    if (step.type == 'depart') return instruction;
    return _liveDistanceToNextStep > 8
        ? 'In ${navigationDistance(_liveDistanceToNextStep)}, $instruction'
        : 'Now, $instruction';
  }

  void _checkStepVoicePrompts(int stepIndex, double distanceToStep) {
    if (!_ttsReady ||
        !_hasReliableGps ||
        _hasArrived ||
        _offRoute ||
        _isReRouting ||
        _riskReviewRequired ||
        _activeConfirmedHazard != null ||
        _noClearRouteFound ||
        _routeFailureMessage != null)
      return;
    if (_routeTracker.initialDirectionStep != null) return;
    if (_currentRoute.steps.isEmpty || stepIndex >= _currentRoute.steps.length)
      return;

    final step = _currentRoute.steps[stepIndex];
    final cleanInstruction = step.instruction.replaceAll(
      RegExp(r'<[^>]*>'),
      '',
    );

    if (distanceToStep <= 200.0 &&
        distanceToStep > 60.0 &&
        !_spoken200mSteps.contains(stepIndex)) {
      _spoken200mSteps.add(stepIndex);
      flutterTts.speak(
        "In ${navigationDistance(distanceToStep)}, $cleanInstruction",
      );
    } else if (distanceToStep <= 50.0 && !_spoken50mSteps.contains(stepIndex)) {
      _spoken50mSteps.add(stepIndex);
      flutterTts.speak(
        distanceToStep <= 8
            ? "Now, $cleanInstruction"
            : "In ${navigationDistance(distanceToStep)}, $cleanInstruction",
      );
    }
  }

  bool _isFollowingUser = true;

  void _showDiagnostics() {
    final diagnostics = _diagnostics;
    if (diagnostics == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: AnimatedBuilder(
            animation: diagnostics,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'Navigation test diagnostics'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    tr(
                      context,
                      'GPS positions are real. Road conditions are simulated.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    diagnostics.latest.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: diagnostics.exportJson()),
                          );
                          if (sheetContext.mounted)
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(context, 'Session log copied.'),
                                ),
                              ),
                            );
                        },
                        child: Text(tr(context, 'Copy session log')),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            final path = await diagnostics.save();
                            if (sheetContext.mounted)
                              showDialog(
                                context: sheetContext,
                                builder: (context) => AlertDialog(
                                  title: Text(tr(context, 'Session log saved')),
                                  content: SelectableText(path),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(tr(context, 'OK')),
                                    ),
                                  ],
                                ),
                              );
                          } catch (_) {
                            if (sheetContext.mounted)
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tr(
                                      context,
                                      'Could not save the log. Use Copy session log.',
                                    ),
                                  ),
                                ),
                              );
                          }
                        },
                        child: Text(tr(context, 'Save local log')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _acceptPosition(geo.Position geoPosition, {bool oneShot = false}) {
    if (!mounted) return;
    final age = _timeNow().difference(geoPosition.timestamp);
    final older =
        _lastGeoPosition != null &&
        (geoPosition.timestamp.isBefore(_lastGeoPosition!.timestamp) ||
            (oneShot &&
                _hasReliableGps &&
                geoPosition.timestamp.isAtSameMomentAs(
                  _lastGeoPosition!.timestamp,
                )));
    final usable = usableLocationFix(geoPosition, now: _timeNow());
    _diagnostics?.record('gps_fix', {
      'accuracyMeters': geoPosition.accuracy.isFinite
          ? geoPosition.accuracy
          : null,
      'fixAgeSeconds': age.inMilliseconds / 1000,
      'gpsOutcome': older
          ? 'ignored_older'
          : usable
          ? 'accepted'
          : 'rejected',
      'fixSource': oneShot ? 'one_shot' : 'stream',
    });
    if (older) return;
    if (!usable) {
      String message =
          'GPS returned an invalid location. Waiting for a fresh fix.';
      if (geoPosition.accuracy.isFinite && geoPosition.accuracy > 60) {
        message =
            'GPS accuracy is ${geoPosition.accuracy.round()} m. Navigation needs 60 m or better. Waiting for a better fix.';
      } else if (age > const Duration(seconds: 30)) {
        message =
            'GPS fix is ${age.inSeconds} seconds old. Waiting for a fix no older than 30 seconds.';
      } else if (age < const Duration(seconds: -5)) {
        message =
            'GPS fix time is ahead of the phone clock. Check automatic date and time.';
      }
      _gpsProblem(message);
      return;
    }
    final recovering = !_hasReliableGps;
    final mapboxPos = Position(geoPosition.longitude, geoPosition.latitude);

    _markerHeading.update(
      heading: geoPosition.heading,
      speed: geoPosition.speed,
      accuracy: geoPosition.accuracy,
      headingAccuracy: geoPosition.headingAccuracy,
      age: age,
    );
    setState(() {
      _currentLocation = mapboxPos;
      _lastGeoPosition = geoPosition;
      _gpsStreamFailed = false;
      _gpsMessage = null;
    });
    _refreshHaltDialog?.call();

    if (_isFollowingUser) {
      _animateCameraToPosition(mapboxPos);
    }

    if (_hasArrived) return;
    if (recovering) {
      _handleAdminFloodUpdateCore();
      _processPendingHazard();
      if (_failedRetryCount > 0 && !_isReRouting) _scheduleRerouteRetry();
    }

    if (_riskReviewRequired) return;

    _checkClosureExitRecovery(geoPosition);

    // Item 6(c): tracker.update runs on every fix during a reroute
    final departing = _routeTracker.initialDirectionStep != null;
    final r = _routeTracker.update(geoPosition);
    _diagnostics?.record('gps', {
      'accuracyMeters': geoPosition.accuracy,
      'distanceToRouteMeters': r.distanceToRoute,
      'ignoredLowAccuracy': r.ignoredLowAccuracy,
      'shouldReroute': r.shouldReroute,
      'cooldownMs': _rerouteGate.remainingCooldown.inMilliseconds,
    });

    // Reaching the OLD geometry must not complete a trip whose guidance is
    // interrupted. Keep its warning until a current route is checked/adopted.
    if (r.arrived &&
        !_isReRouting &&
        !_riskReviewRequired &&
        _activeConfirmedHazard == null &&
        !_noClearRouteFound &&
        _routeFailureMessage == null &&
        _pendingRouteRefresh == null) {
      flutterTts.stop();
      final arrivalSpeech =
          _navDestinationName != null && _navDestinationName!.isNotEmpty
          ? "You have reached the planned destination: $_navDestinationName."
          : "You have reached the end of the planned route.";
      flutterTts.speak(arrivalSpeech);
      setState(() {
        _hasArrived = true;
        _clearRouteNotice();
        _liveDistanceToNextStep = 0.0;
      });
      return;
    }

    setState(() {
      _currentStepIndex = r.stepIndex;
      _liveDistanceToNextStep = r.distanceToNextStep;
      _offRoute =
          r.distanceToRoute > (35 + 1.2 * geoPosition.accuracy).clamp(35, 90);
    });

    if ((recovering ||
            (departing && _routeTracker.initialDirectionStep == null)) &&
        !_isReRouting) {
      _speakCurrentStep();
    } else {
      _checkStepVoicePrompts(r.stepIndex, r.distanceToNextStep);
    }

    if (r.shouldReroute && !_isReRouting && _rerouteGate.tryBegin()) {
      _routeTracker.resetOffRoute();
      _triggerReRoute("Off route detected. Recalculating safe path...");
    }
  }

  void _startLocationTracking() {
    final generation = ++_gpsStreamGeneration;
    try {
      _positionSubscription =
          (widget.positionStream ?? LocationService.getPositionStream()).listen(
            (fix) {
              if (generation == _gpsStreamGeneration) _acceptPosition(fix);
            },
            onError: (Object error) {
              if (!mounted || generation != _gpsStreamGeneration) return;
              _gpsProblem(
                'GPS tracking interrupted. Check location services and retry.',
              );
              _diagnostics?.record('gps_error', {
                'errorType': error.runtimeType.toString(),
              });
            },
            onDone: () {
              if (!mounted || generation != _gpsStreamGeneration) return;
              _gpsProblem(
                'GPS updates stopped. Retry to reconnect location tracking.',
              );
            },
          );
    } catch (error) {
      _gpsProblem(
        'GPS tracking could not start. Check location services and retry.',
      );
      _diagnostics?.record('gps_error', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  List<Position> _extractRoadPositions(RoadStatus road) {
    return GeoUtils.extractPoints(
      road.geometry,
    ).map((p) => Position(p.lng, p.lat)).toList();
  }

  // ─── TIER 1: STALE / UNCONFIRMED ROAD ADVISORY HANDLER ─────────────────────
  void _handleStaleRoadAdvisory(RoadStatus road) {
    if (_dismissedAdvisoryRoadIds.contains(road.id)) return;
    if (_activeAdvisoryRoad?.id == road.id) return;

    if (!_unconfirmedStaleRoads.any((r) => r.id == road.id)) {
      _unconfirmedStaleRoads.add(road);
    }

    if (_advisoriesShownCount >= 2) {
      if (mounted) {
        setState(() {
          _collapsedAdvisoryMode = true;
          _activeAdvisoryRoad = null;
        });
      }
    } else {
      _advisoriesShownCount++;
      if (mounted) {
        setState(() {
          _activeAdvisoryRoad = road;
        });
      }
      flutterTts.speak(
        "Advisory: unverified road conditions ahead on ${road.name}.",
      );
    }
  }

  void _refreshAdvisories({bool announce = true}) {
    final weather = SimulatedWeatherService.instance.currentState;
    final remaining = _routeTracker.remainingPoints();
    final ahead = AppStateService.instance.roads
        .where(
          (road) =>
              road.status == 'passable' &&
              road.getEffectiveStatus(weather, currentTime: _timeNow()) !=
                  'passable' &&
              RoutingService.doesRouteCrossGeometry(remaining, road.geometry),
        )
        .toList();
    final ids = ahead.map((r) => r.id).toSet();
    final active = ahead
        .where((r) => r.id == _activeAdvisoryRoad?.id)
        .firstOrNull;
    setState(() {
      _unconfirmedStaleRoads
        ..clear()
        ..addAll(ahead);
      _dismissedAdvisoryRoadIds.retainAll(ids);
      _activeAdvisoryRoad = active;
      if (ahead.isEmpty) {
        _collapsedAdvisoryMode = false;
        _advisoriesShownCount = 0;
      }
    });
    if (announce && active == null && !_collapsedAdvisoryMode) {
      final next = ahead
          .where((r) => !_dismissedAdvisoryRoadIds.contains(r.id))
          .firstOrNull;
      if (next != null) _handleStaleRoadAdvisory(next);
    }
  }

  // ─── TRIGGER 3: PERIODIC ROUTE STALENESS CHECK (TIER 1 ONLY) ──────────────
  void _checkRouteStaleness() {
    if (!mounted || _hasArrived) return;
    _refreshAdvisories(
      announce: !_isReRouting && _activeConfirmedHazard == null,
    );
  }

  // ─── TRIGGER 2: REALTIME FLOOD UPDATE (SPLIT TIER 1 VS TIER 2) ────────────
  void _onAdminFloodUpdate() {
    if (!mounted || _hasArrived) return;
    _lastLiveDataUnavailable = _liveDataUnavailable;
    _diagnostics?.record('roads_received');
    if (_adminUpdateDebounceTimer?.isActive ?? false) return;
    _adminUpdateDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted || _hasArrived) return;
      _handleAdminFloodUpdateCore();
    });
  }

  void _handleAdminFloodUpdateCore() {
    if (!mounted || _hasArrived) return;

    final appState = AppStateService.instance;
    final weatherState = SimulatedWeatherService.instance.currentState;

    // Safety-critical halt monitoring: auto-recalculate if an admin-blocked road re-opens
    if (_haltBlockingRoadIds.isNotEmpty) {
      final reopened = _haltBlockingRoadIds.where((id) {
        final r = appState.roads.cast<dynamic>().firstWhere(
          (road) => road.id == id,
          orElse: () => null,
        );
        return r != null && r.status != 'not_passable';
      }).toSet();

      if (reopened.isNotEmpty) {
        _haltBlockingRoadIds.removeAll(reopened);
        _pendingRouteRefresh =
            'A blocked road reopened. Checking the route again...';
        _forcePendingRouteRefresh = true;
      }
    }

    final active = _activeConfirmedHazard;
    if (active != null) {
      _activeConfirmedHazard = appState.roads
          .where(
            (r) =>
                r.id == active.id &&
                r.status != 'passable' &&
                RoutingService.doesRouteCrossGeometry(
                  _routeTracker.remainingPoints(),
                  r.geometry,
                ),
          )
          .firstOrNull;
    }
    _refreshHaltDialog?.call();

    final refreshed = RoutingService.instance.refreshRoute(
      _currentRoute,
      vehicleType: _navVehicleType,
      evaluationPoints: _routeTracker.remainingPoints(),
    );
    final warning = _routeConditionWarning(refreshed);
    if (!identical(refreshed, _currentRoute) || warning != _warningChipMessage)
      setState(() {
        _currentRoute = refreshed;
        _warningChipMessage = warning;
      });

    final pendingRisk = _pendingRiskRoute;
    if (pendingRisk != null) {
      final latest = RoutingService.instance.navigationAdmission(pendingRisk);
      if (!latest.route.canStartNavigation) {
        _riskGeneration++;
        _closeRiskDialog();
        setState(() {
          _pendingRiskRoute = null;
          _pendingRiskKey = null;
          _riskReviewMessage =
              'The alternative changed or closed. Navigation remains paused while another route is checked.';
        });
        _pendingRouteRefresh =
            'Alternative conditions changed. Checking routes again...';
      } else if (latest.key != _pendingRiskKey) {
        final wasCritical = pendingRisk.safetyStatus == 'critical';
        _setRiskReviewCandidate(latest.route);
        if (wasCritical && latest.route.safetyStatus != 'critical') {
          _pendingRouteRefresh =
              'Risk conditions changed. Checking routes again...';
        }
      }
    } else if (!_riskReviewRequired &&
        refreshed.safetyStatus == 'critical' &&
        !refreshed.isBlocked) {
      final admission = RoutingService.instance.navigationAdmission(refreshed);
      if (_acceptedCriticalKey != admission.key) {
        _setRiskReviewCandidate(admission.route);
        _pendingRouteRefresh =
            'High predicted risk detected. Checking alternatives...';
      }
    }

    final changedRoads = RoutingService.findStatusChangedRoads(
      appState.roads,
      _roadStatusCache,
      weatherState,
      confirmedStatusCache: _confirmedStatusCache,
    );
    _diagnostics?.record('roads_checked', {
      'roadIds': changedRoads.map((r) => r.id).toList(),
    });

    // Update _roadStatusCache for ALL roads on each pass
    for (final road in appState.roads) {
      _roadStatusCache[road.id] = road.getEffectiveStatus(weatherState);
      _confirmedStatusCache[road.id] = road.status;
    }

    final remainingPts = _routeTracker.remainingPoints();
    if (remainingPts.isEmpty || changedRoads.isEmpty) {
      _refreshAdvisories(
        announce: !_isReRouting && _activeConfirmedHazard == null,
      );
      _processPendingRouteRefresh();
      return;
    }

    RoadStatus? confirmedHazardRoad;

    for (final road in changedRoads) {
      final roadPts = _extractRoadPositions(road);
      if (roadPts.length >= 2 &&
          RoutingService.doesRouteCrossGeometry(
            remainingPts,
            road.geometry,
            thresholdMeters: RiskConfig.roadCrossingBufferMeters,
          )) {
        if (road.status != 'passable') {
          confirmedHazardRoad = road;
          break;
        }
      }
    }

    if (confirmedHazardRoad != null) {
      setState(() => _activeConfirmedHazard = confirmedHazardRoad);
      final statusLabel = confirmedHazardRoad.status == 'not_passable'
          ? 'flooded'
          : 'partially flooded';
      if (!_hasReliableGps) {
        _pendingConfirmedHazard = confirmedHazardRoad;
        _refreshAdvisories(announce: false);
        return;
      }
      if (!_isReRouting && _rerouteGate.tryBegin()) {
        _pendingConfirmedHazard = null;
        _triggerReRoute(
          "Confirmed: ${confirmedHazardRoad.name} is $statusLabel. Rerouting via safe path...",
          confirmedHazard: confirmedHazardRoad,
        );
      } else {
        _pendingConfirmedHazard = confirmedHazardRoad;
        _processPendingHazard();
      }
    }
    _refreshAdvisories(
      announce: !_isReRouting && _activeConfirmedHazard == null,
    );
    _processPendingRouteRefresh();
  }

  void _processPendingRouteRefresh() {
    if (!mounted ||
        _hasArrived ||
        _isReRouting ||
        !_hasReliableGps ||
        _pendingRouteRefresh == null)
      return;
    if (_rerouteGate.tryBegin(force: _forcePendingRouteRefresh)) {
      final reason = _pendingRouteRefresh!;
      final avoidIds = Set<String>.of(_pendingRefreshAvoidIds);
      _pendingRefreshAvoidIds.clear();
      _pendingRouteRefresh = null;
      _forcePendingRouteRefresh = false;
      _pendingRouteRefreshTimer?.cancel();
      _closeHaltDialog();
      _triggerReRoute(reason, avoidRoadIds: avoidIds);
    } else {
      _pendingRouteRefreshTimer?.cancel();
      final wait = _rerouteGate.remainingCooldown;
      _pendingRouteRefreshTimer = Timer(
        wait > Duration.zero ? wait : const Duration(seconds: 2),
        _processPendingRouteRefresh,
      );
    }
  }

  void _processPendingHazard() {
    if (!mounted ||
        _hasArrived ||
        _pendingConfirmedHazard == null ||
        !_hasReliableGps ||
        _isReRouting)
      return;

    // Resolve the queued road again: it may have reopened during the cooldown.
    RoadStatus? latestRoad;
    for (final road in AppStateService.instance.roads) {
      if (road.id == _pendingConfirmedHazard!.id) {
        latestRoad = road;
        break;
      }
    }
    if (latestRoad == null || latestRoad.status == 'passable') {
      if (_activeConfirmedHazard?.id == _pendingConfirmedHazard!.id) {
        setState(() => _activeConfirmedHazard = null);
      }
      _pendingConfirmedHazard = null;
      _pendingHazardTimer?.cancel();
      return;
    }
    _pendingConfirmedHazard = latestRoad;

    final remainingPts = _routeTracker.remainingPoints();
    final roadPts = _extractRoadPositions(_pendingConfirmedHazard!);
    if (roadPts.length < 2 ||
        !RoutingService.doesRouteCrossGeometry(
          remainingPts,
          _pendingConfirmedHazard!.geometry,
          thresholdMeters: RiskConfig.roadCrossingBufferMeters,
        )) {
      _pendingConfirmedHazard = null;
      return;
    }

    if (_rerouteGate.tryBegin()) {
      final pending = _pendingConfirmedHazard!;
      _pendingConfirmedHazard = null;
      final weatherState = SimulatedWeatherService.instance.currentState;
      _roadStatusCache[pending.id] = pending.getEffectiveStatus(weatherState);
      final statusLabel = pending.status == 'not_passable'
          ? 'flooded'
          : 'partially flooded';
      _triggerReRoute(
        "Confirmed: ${pending.name} is $statusLabel. Rerouting via safe path...",
        confirmedHazard: pending,
      );
    } else {
      _pendingHazardTimer?.cancel();
      final wait = _rerouteGate.remainingCooldown;
      _pendingHazardTimer = Timer(
        wait > Duration.zero ? wait : const Duration(seconds: 2),
        () {
          if (mounted) _processPendingHazard();
        },
      );
      _diagnostics?.record('hazard_queued', {
        'cooldownMs': wait.inMilliseconds,
      });
    }
  }

  bool _adoptNewRoute(
    PlannedRoute newRoute,
    String speechMessage, {
    Position? newDestination,
    String? newDestinationName,
    String? reviewedRiskKey,
  }) {
    final admission = RoutingService.instance.navigationAdmission(newRoute);
    if (!admission.route.canStartNavigation || !_hasReliableGps) return false;
    if (admission.route.safetyStatus == 'critical' &&
        reviewedRiskKey != admission.key) {
      _setRiskReviewCandidate(admission.route);
      return false;
    }
    newRoute = admission.route;
    _diagnostics?.record('route_adopted', {
      'outcome': newRoute.safetyStatus == 'critical'
          ? 'critical_reviewed'
          : 'noncritical',
    });
    _riskGeneration++;
    _closeRiskDialog();
    _riskReviewRequired = false;
    _pendingRiskRoute = null;
    _pendingRiskKey = null;
    _acceptedCriticalKey = newRoute.safetyStatus == 'critical'
        ? reviewedRiskKey
        : null;
    if (_haltDialogContext != null) _closeHaltDialog();
    _pendingRouteRefresh = null;
    _pendingRefreshAvoidIds.clear();
    _forcePendingRouteRefresh = false;
    _pendingRouteRefreshTimer?.cancel();
    _rerouteRetryTimer?.cancel();
    _activeConfirmedHazard = null;
    _closureExitRecovery.reset();
    _failedRetryCount = 0;
    _haltBlockingRoadIds.clear();
    _noClearRouteFound = false;
    _noDifferentDetour = false;
    _clearRouteNotice();

    if (newDestination != null) {
      _navDestination = newDestination;
    } else if (_navDestination == null && newRoute.points.isNotEmpty) {
      _navDestination = newRoute.points.last;
    }
    if (newDestinationName != null) {
      _navDestinationName = newDestinationName;
    }

    final appState = AppStateService.instance;
    final adminNotPassableRoads = appState.roads
        .where((r) => r.status == 'not_passable' && r.geometry != null)
        .expand(
          (r) => GeoUtils.extractSegments(r.geometry).map(
            (segment) => segment.map((p) => Position(p.lng, p.lat)).toList(),
          ),
        )
        .where((pts) => pts.length >= 2)
        .toList();

    // Warning chip evaluates FULL route (including first 50m)
    final bool crossedImpassableInFullRoute = adminNotPassableRoads.any(
      (badRoadPts) => RoutingService.doesRouteCrossRoad(
        newRoute.points,
        badRoadPts,
        thresholdMeters: RiskConfig.roadCrossingBufferMeters,
      ),
    );

    String? warning = _routeConditionWarning(newRoute);
    if (crossedImpassableInFullRoute || newRoute.isBlocked) {
      warning = 'Caution: Flooded road segment nearby on route.';
    }

    setState(() {
      _currentRoute = newRoute;
      _routeTracker = RouteTracker(route: _currentRoute, now: widget.now);
      _spoken200mSteps.clear();
      _spoken50mSteps.clear();
      if (_lastGeoPosition != null) {
        final initRes = _routeTracker.update(_lastGeoPosition!);
        _currentStepIndex = initRes.stepIndex;
        _liveDistanceToNextStep = initRes.distanceToNextStep;
        for (int i = 0; i < initRes.stepIndex; i++) {
          _spoken200mSteps.add(i);
          _spoken50mSteps.add(i);
        }
      } else {
        _currentStepIndex = _routeTracker.currentStepIndex;
        _liveDistanceToNextStep = 0.0;
      }
      _warningChipMessage = warning;
      _offRoute = false;
      _routeFailureMessage = null;
      _routeUpdateSummary = newDestinationName != null
          ? 'Route updated to $newDestinationName'
          : _pendingUpdateReason ??
                'Route updated after checking current conditions';
      _routeUpdatedAt = _timeNow();
      _resetAdvisoryState();
      _routeNoticeUntil = _timeNow().add(const Duration(seconds: 5));
    });
    _routeNoticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _routeNoticeUntil = null);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    if (_isFollowingUser) {
      _animateCameraToPosition(
        _currentLocation ?? _currentRoute.points.first,
        zoom: 17.5,
        pitch: 40.0,
      );
    }
    final step =
        _routeTracker.initialDirectionStep ??
        (_currentRoute.steps.isEmpty
            ? null
            : _currentRoute.steps[_currentStepIndex]);
    final instruction = step == null ? null : _stepSpeech(step);
    flutterTts.speak(
      '${_routeUpdateSummary!}. '
      '${instruction ?? speechMessage}',
    );
    return true;
  }

  void _closeRiskDialog() {
    final dialog = _riskDialogContext;
    _riskDialogContext = null;
    if (dialog != null && dialog.mounted) {
      final route = ModalRoute.of(dialog);
      if (route != null) Navigator.of(dialog).removeRoute(route);
    }
  }

  void _setRiskReviewCandidate(PlannedRoute route) {
    final admission = RoutingService.instance.navigationAdmission(route);
    if (_riskReviewRequired &&
        identical(_pendingRiskRoute?.points, route.points) &&
        _pendingRiskKey == admission.key)
      return;
    _riskGeneration++;
    _closeRiskDialog();
    _clearRouteNotice();
    setState(() {
      _riskReviewRequired = true;
      _pendingRiskRoute = admission.route;
      _pendingRiskKey = admission.key;
      _riskReviewMessage =
          'A route has critical predicted flood risk. Navigation is paused until conditions are reviewed.';
    });
    _diagnostics?.record('risk_review_required', {'outcome': 'paused'});
    unawaited(flutterTts.stop().catchError((Object _) => null));
    if (_hasReliableGps)
      flutterTts.speak(
        'Critical predicted flood risk. Navigation paused. Review current conditions before choosing an alternative.',
      );
  }

  void _retryRiskRoute() {
    _pendingRouteRefresh = 'Checking alternatives from the current location...';
    _forcePendingRouteRefresh = true;
    _processPendingRouteRefresh();
  }

  Future<void> _reviewRiskRoute() async {
    final candidate = _pendingRiskRoute;
    if (_reviewingRisk || candidate == null || _isReRouting) return;
    final admission = RoutingService.instance.navigationAdmission(candidate);
    if (!_hasReliableGps ||
        !admission.route.canStartNavigation ||
        RoutingService.distanceToRoute(
              _currentLocation!,
              admission.route.points,
            ) >
            90) {
      setState(
        () => _riskReviewMessage =
            'A current GPS fix and a route connected to your position are required. Retry the route before reviewing.',
      );
      return;
    }
    final generation = _riskGeneration;
    final following = _isFollowingUser;
    setState(() {
      _reviewingRisk = true;
      _riskPreview = admission.route;
      _isFollowingUser = false;
    });
    try {
      final accepted =
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (dialog) {
              _riskDialogContext = dialog;
              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(dialog).height * 0.65,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(context, 'Review critical-risk alternative'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tr(
                                  context,
                                  'The map is showing an alternative preview. Guidance is paused. This route has critical predicted flood risk; absence of an official closure does not establish passability.',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${admission.route.durationMin} min • ${navigationDistance(admission.route.distanceMeters ?? admission.route.distanceMiles * 1609.34)}',
                              ),
                              for (final hazard in admission.route.hazardAlerts)
                                Text('• $hazard'),
                              const SizedBox(height: 12),
                              Text(
                                tr(context, admission.route.conditionSummary),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tr(
                                  context,
                                  'Confirm current local conditions before selecting this route. You can cancel and search for another alternative.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: Text(tr(context, 'Cancel review')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: Text(
                                tr(context, 'Use reviewed alternative'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ) ??
          false;
      if (!mounted) return;
      if (!accepted || generation != _riskGeneration) {
        _diagnostics?.record('risk_review_finished', {
          'outcome': generation != _riskGeneration ? 'changed' : 'cancelled',
        });
        return;
      }
      final latest = RoutingService.instance.navigationAdmission(candidate);
      if (!_hasReliableGps ||
          !latest.route.canStartNavigation ||
          latest.key != admission.key ||
          RoutingService.distanceToRoute(
                _currentLocation!,
                latest.route.points,
              ) >
              90) {
        setState(
          () => _riskReviewMessage =
              'Conditions or your location changed. Navigation remains paused. Retry or review the alternative again.',
        );
        _diagnostics?.record('risk_review_finished', {
          'outcome': 'rejected_changed_conditions',
        });
        return;
      }
      _adoptNewRoute(
        latest.route,
        'Reviewed alternative selected. Conditions may change.',
        reviewedRiskKey: latest.key,
      );
    } finally {
      if (mounted)
        setState(() {
          _reviewingRisk = false;
          _riskPreview = null;
          _riskDialogContext = null;
          _isFollowingUser = following;
        });
    }
  }

  void _closeHaltDialog() {
    final dialog = _haltDialogContext;
    _haltGeneration++;
    _haltDialogContext = null;
    _refreshHaltDialog = null;
    if (dialog != null && dialog.mounted) {
      final route = ModalRoute.of(dialog);
      if (route != null) Navigator.of(dialog).removeRoute(route);
    }
  }

  void _showHaltDialog() {
    if (!mounted || _haltDialogContext != null) return;
    final generation = ++_haltGeneration;
    var loading = true, loaded = false, loadId = 0;
    Map<String, dynamic>? choice;
    String? message, cautionKey;
    void Function(VoidCallback)? updateDialog;
    bool current() => mounted && generation == _haltGeneration;
    final hasLocations =
        widget.stagingSearch != null ||
        RiskConfig.safeStagingFacilities.isNotEmpty;

    Future<void> reload() async {
      if (!current()) return;
      final request = ++loadId;
      updateDialog?.call(() {
        loading = false;
        choice = null;
        cautionKey = null;
        message = null;
      });
      if (!hasLocations) return;
      if (!_hasReliableGps || _currentLocation == null) {
        updateDialog?.call(
          () => message =
              'A reliable GPS fix is needed to check staging options.',
        );
        return;
      }
      updateDialog?.call(() => loading = true);
      try {
        final result =
            await (widget.stagingSearch?.call(_currentLocation!) ??
                    RoutingService.findNearestReachableStagingFacility(
                      origin: _currentLocation!,
                      facilities: RiskConfig.safeStagingFacilities,
                      routingService: RoutingService.instance,
                      vehicleType: _navVehicleType,
                      isCurrent: () => current() && request == loadId,
                    ))
                .timeout(const Duration(seconds: 22));
        if (!current() || request != loadId) return;
        final lat = result?['lat'],
            lng = result?['lng'],
            route = result?['reachableRoute'];
        final valid =
            result?['name'] is String &&
            lat is num &&
            lng is num &&
            RoutingService.validRoutePoint(Position(lng, lat)) &&
            route is PlannedRoute;
        updateDialog?.call(() {
          loading = false;
          choice = valid ? result : null;
          message = valid
              ? null
              : 'No staging route could be confirmed. Refresh options or follow current local emergency instructions.';
        });
      } catch (_) {
        if (!current() || request != loadId) return;
        updateDialog?.call(() {
          loading = false;
          message =
              'Staging options could not be checked. Retry when GPS and a connection are available.';
        });
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) {
        _haltDialogContext = dialog;
        return StatefulBuilder(
          builder: (dialog, setDialogState) {
            updateDialog = setDialogState;
            _refreshHaltDialog = () {
              if (current() && dialog.mounted) setDialogState(() {});
            };
            if (!loaded) {
              loaded = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => unawaited(reload()),
              );
            }
            final selected = choice;
            final admission = selected == null
                ? null
                : RoutingService.instance.navigationAdmission(
                    selected['reachableRoute'] as PlannedRoute,
                  );
            final eligible =
                admission != null &&
                RoutingService.isStagingRouteCandidate(admission.route);
            final name = selected?['name'] as String?;
            final nearClosure = _nearConfirmedClosure;

            void choose() {
              if (!current() || selected == null || _isReRouting) return;
              final latest = RoutingService.instance.navigationAdmission(
                selected['reachableRoute'] as PlannedRoute,
              );
              String? problem;
              if (!_hasReliableGps || _currentLocation == null) {
                problem =
                    'A reliable GPS fix is needed before starting this route.';
              } else if (!RoutingService.isStagingRouteCandidate(
                latest.route,
              )) {
                problem =
                    'Road conditions changed. Refresh staging options before continuing.';
              } else if (RoutingService.distanceToRoute(
                    _currentLocation!,
                    latest.route.points,
                  ) >
                  90) {
                problem =
                    'Your position changed. Refresh staging options from your current location.';
              }
              if (problem != null) {
                setDialogState(() {
                  message = problem;
                  cautionKey = null;
                });
                return;
              }
              if (latest.requiresCaution && cautionKey != latest.key) {
                setDialogState(() {
                  cautionKey = latest.key;
                  message =
                      'This route includes risk or unconfirmed conditions. Review current local conditions before choosing Start with Caution.';
                });
                return;
              }
              final destination = Position(
                selected['lng'] as num,
                selected['lat'] as num,
              );
              _closeHaltDialog();
              _adoptNewRoute(
                latest.route,
                'Staging destination selected: $name.',
                newDestination: destination,
                newDestinationName: name,
              );
            }

            return AlertDialog(
              scrollable: true,
              title: Text(
                tr(
                  context,
                  nearClosure
                      ? 'Closure near your location'
                      : 'No Clear Route Found',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      context,
                      nearClosure
                          ? 'Your GPS location is on or near a road marked not passable. Guidance is paused. The gray dashed line is the previous route, not updated guidance.'
                          : 'No route avoiding the confirmed closures was found. The previous route must not be treated as a checked alternative.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!hasLocations)
                    Text(
                      tr(
                        context,
                        'No staging locations are configured for this study area. Follow current local emergency instructions.',
                      ),
                    )
                  else if (loading)
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr(context, 'Checking listed staging locations...'),
                          ),
                        ),
                      ],
                    )
                  else if (selected != null) ...[
                    Text('${tr(context, 'Listed staging location')}: $name'),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        eligible
                            ? admission.route.conditionSummary
                            : 'This suggested route is no longer available. Refresh staging options.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Confirm locally that this location is open and suitable. A route does not establish that a location is safe.',
                      ),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(tr(context, message!)),
                  ],
                ],
              ),
              actions: [
                if (!loading && eligible)
                  FilledButton(
                    onPressed: choose,
                    child: Text(
                      cautionKey == admission.key
                          ? tr(context, 'Start with Caution')
                          : 'Go to $name',
                    ),
                  ),
                if (!loading && hasLocations)
                  TextButton(
                    onPressed: () => unawaited(reload()),
                    child: Text(tr(context, 'Refresh staging options')),
                  ),
                TextButton(
                  onPressed: _closeHaltDialog,
                  child: Text(tr(context, 'Dismiss Warning')),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (current()) {
        _haltGeneration++;
        _haltDialogContext = null;
        _refreshHaltDialog = null;
      }
    });
  }

  // ─── REROUTE ENGINE EXECUTION (STRUCTURALLY GUARDED GATE RELEASE) ──────────
  Future<void> _triggerReRoute(
    String message, {
    RoadStatus? confirmedHazard,
    Iterable<String>? avoidRoadIds,
  }) async {
    if (_isReRouting) {
      return;
    }
    if (!_hasReliableGps || _currentLocation == null) {
      if (confirmedHazard != null) _pendingConfirmedHazard = confirmedHazard;
      _rerouteGate.releaseNeutral();
      return;
    }

    final routing = RoutingService.instance;
    final destination =
        _navDestination ??
        (_currentRoute.points.isNotEmpty ? _currentRoute.points.last : null);
    if (destination == null) {
      _rerouteGate.releaseNeutral();
      return;
    }

    if (confirmedHazard != null) {
      _activeConfirmedHazard = confirmedHazard;
    }
    if (_nearConfirmedClosure) _closureExitRecovery.arm();
    final hazardForReason =
        confirmedHazard ??
        AppStateService.instance.roads
            .where(
              (road) =>
                  road.id == _activeConfirmedHazard?.id &&
                  road.status == 'not_passable',
            )
            .firstOrNull;
    _pendingUpdateReason = hazardForReason != null
        ? 'Route updated to avoid ${hazardForReason.name}'
        : message.toLowerCase().contains('off route')
        ? 'Route updated from your current position'
        : 'Route updated after checking current conditions';
    _pendingRouteRefresh = null;
    _pendingRefreshAvoidIds.clear();
    _forcePendingRouteRefresh = false;
    _pendingRouteRefreshTimer?.cancel();

    _closeRiskDialog();
    _clearRouteNotice();
    setState(() {
      _lastRequestReason = message;
      _lastRequestedAvoidIds = {...?avoidRoadIds};
      _calculationReason = message;
      _noDifferentDetour = false;
      _isReRouting = true;
      _routeUpdateSummary = null;
      _routeUpdatedAt = null;
    });
    final attempt = ++_rerouteAttempt;
    final requestOrigin = _currentLocation!;
    _diagnostics?.record('request_started', {'reason': message});

    flutterTts.speak(message);
    // Four possible outcomes: 'success', 'halt', 'neutral', 'failure'
    String outcome = 'failure';
    bool refreshForNewClosure = false;

    try {
      double? headingToSend;
      if (_lastGeoPosition != null &&
          _lastGeoPosition!.speed >= 2.0 &&
          _lastGeoPosition!.heading >= 0.0 &&
          _lastGeoPosition!.heading <= 360.0) {
        headingToSend = _lastGeoPosition!.heading;
      }

      final Set<String> avoidIds = {
        for (final road in AppStateService.instance.roads)
          if (road.status == 'not_passable') road.id,
        if (_activeConfirmedHazard != null) _activeConfirmedHazard!.id,
        ...?avoidRoadIds,
      };
      final timeoutDuration = (avoidIds.isNotEmpty || confirmedHazard != null)
          ? const Duration(seconds: 18)
          : const Duration(seconds: 12);

      final Future<List<PlannedRoute>> pending;
      if (widget.routeComputer != null) {
        pending = widget.routeComputer!(
          origin: requestOrigin,
          destination: destination,
          vehicleType: _navVehicleType,
          headingDegrees: headingToSend,
          avoidRoadIds: avoidIds,
          maxDetourCandidates: RoutingService.navigationDetourCandidateLimit,
        );
      } else {
        pending = routing.computeRoutes(
          origin: requestOrigin,
          destination: destination,
          vehicleType: _navVehicleType,
          headingDegrees: headingToSend,
          avoidRoadIds: avoidIds,
          maxDetourCandidates: RoutingService.navigationDetourCandidateLimit,
          timeBudget: timeoutDuration,
          isCurrent: () =>
              mounted &&
              attempt == _rerouteAttempt &&
              _isReRouting &&
              !_hasArrived,
        );
      }
      final returned = await pending.timeout(timeoutDuration);
      if (!mounted) return;
      if (!_hasReliableGps) {
        outcome = 'neutral';
        _pendingConfirmedHazard ??= _activeConfirmedHazard;
        _pendingRouteRefresh ??= message;
        _pendingRefreshAvoidIds.addAll(avoidRoadIds ?? const <String>[]);
        return;
      }
      var computedRoutes =
          returned
              .map((r) => routing.refreshRoute(r, vehicleType: _navVehicleType))
              .toList()
            ..sort(RoutingService.compareRoutes);
      final moved = GeoUtils.haversineMeters(
        requestOrigin.lat.toDouble(),
        requestOrigin.lng.toDouble(),
        _currentLocation!.lat.toDouble(),
        _currentLocation!.lng.toDouble(),
      );
      if (moved > 90 && computedRoutes.isNotEmpty) {
        computedRoutes = computedRoutes
            .where(
              (r) =>
                  RoutingService.distanceToRoute(_currentLocation!, r.points) <=
                  90,
            )
            .toList();
        if (computedRoutes.isEmpty) {
          outcome = 'neutral';
          refreshForNewClosure = true;
          return;
        }
      }

      if (!mounted) return;
      _diagnostics?.record('routes_returned', {
        'routeCount': computedRoutes.length,
      });
      if (_hasArrived) {
        outcome = 'neutral';
        return;
      }

      if (computedRoutes.isNotEmpty) {
        final appState = AppStateService.instance;

        // Revalidate against current closures, including updates during the request.
        final usableRoutes = RoutingService.routesAvoidingConfirmedClosures(
          computedRoutes,
          appState.roads,
        );
        final bool allRoutesBlockedByAdminNotPassable = usableRoutes.isEmpty;

        // The request used an older closure snapshot. Search again with the new
        // closure before declaring that no clear alternative could be found.
        if (allRoutesBlockedByAdminNotPassable) {
          for (final road in appState.roads) {
            if (road.status == 'not_passable' &&
                !avoidIds.contains(road.id) &&
                computedRoutes.any(
                  (route) => RoutingService.doesRouteCrossGeometry(
                    route.points,
                    road.geometry,
                  ),
                )) {
              _activeConfirmedHazard = road;
              refreshForNewClosure = true;
              outcome = 'neutral';
              return;
            }
          }
        }

        if (allRoutesBlockedByAdminNotPassable) {
          outcome = 'halt';
          setState(() => _noClearRouteFound = true);
          if (_nearConfirmedClosure) _closureExitRecovery.arm();

          // Track which road IDs triggered the halt so we can auto-resume if one opens
          _haltBlockingRoadIds.clear();
          for (final road in appState.roads) {
            if (road.status == 'not_passable' && road.geometry != null) {
              final roadPts = _extractRoadPositions(road);
              if (roadPts.length >= 2 &&
                  computedRoutes.any(
                    (r) => RoutingService.doesRouteCrossGeometry(
                      r.points,
                      road.geometry,
                      thresholdMeters: RiskConfig.roadCrossingBufferMeters,
                    ),
                  )) {
                _haltBlockingRoadIds.add(road.id);
              }
            }
          }

          _showHaltDialog();
        } else {
          final automatic = usableRoutes
              .where(RoutingService.canAdoptAutomatically)
              .toList();
          if (automatic.isEmpty) {
            _setRiskReviewCandidate(usableRoutes.first);
            outcome = 'review';
            return;
          }
          final bestRoute = automatic.first;

          // Compare remaining points of current route with new route
          final remainingPts = _routeTracker.remainingPoints();
          final basePts = remainingPts.length >= 2
              ? remainingPts
              : _currentRoute.points;

          if (avoidRoadIds != null &&
              avoidRoadIds.isNotEmpty &&
              RoutingService.routesEffectivelySame(basePts, bestRoute.points)) {
            outcome = 'neutral';
            setState(() => _noDifferentDetour = true);
            flutterTts.speak(
              'No different detour found. Conditions still need confirmation.',
            );
            return;
          }

          outcome =
              _adoptNewRoute(
                bestRoute,
                'New route found. Continuing navigation.',
              )
              ? 'success'
              : 'review';
        }
      } else {
        outcome = 'failure';
        _handleRerouteFailure(isNetworkError: false);
      }
    } catch (e) {
      // Ending a trip invalidates its request, including error/timeout results.
      // An old trip must not announce over the screen that replaced it.
      if (!mounted || _hasArrived || attempt != _rerouteAttempt) {
        outcome = 'neutral';
        return;
      }
      debugPrint(
        '[NavigationScreen] Reroute did not complete (${e.runtimeType}).',
      );
      if (mounted)
        _diagnostics?.record('request_error', {
          'errorType': e.runtimeType.toString(),
        });
      outcome = 'failure';
      final isNetwork =
          e is TimeoutException ||
          e is SocketException ||
          e.toString().contains('SocketException');
      _handleRerouteFailure(isNetworkError: isNetwork);
    } finally {
      // Structural gate release: exactly one release per attempt
      if (outcome == 'success') {
        _rerouteGate.endSuccess();
      } else if (outcome == 'halt' ||
          outcome == 'neutral' ||
          outcome == 'review') {
        _rerouteGate
            .releaseNeutral(); // Neutral release without backoff penalty
      } else {
        _rerouteGate.endFailure();
      }

      if (mounted) {
        _diagnostics?.record('request_finished', {
          'outcome': outcome,
          'cooldownMs': _rerouteGate.remainingCooldown.inMilliseconds,
        });
        setState(() {
          _isReRouting = false;
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        if ((outcome == 'failure' || refreshForNewClosure) && !_hasArrived) {
          _scheduleRerouteRetry();
        }
        _processPendingHazard();
        _processPendingRouteRefresh();
      }
    }
  }

  void _handleRerouteFailure({bool isNetworkError = false}) {
    if (!mounted || _hasArrived) return;
    _failedRetryCount++;
    if (mounted) {
      setState(() {
        _routeFailureMessage = isNetworkError
            ? 'Connection or route service unavailable. The previous route is shown for reference. Retry when a connection and GPS are available.'
            : 'No updated route could be checked. The previous route is shown for reference. Retry or review local conditions.';
      });
    }

    if (_activeConfirmedHazard != null) {
      flutterTts.speak(
        'Route update unavailable. The current path still contains a confirmed hazard.',
      );
    } else if (_failedRetryCount == 1 && _hasReliableGps) {
      flutterTts.speak(
        'Route update unavailable. The previous route has not been rechecked.',
      );
    }
  }

  void _scheduleRerouteRetry() {
    // Schedule only after endFailure records the new backoff and releases the lock.
    _rerouteRetryTimer?.cancel();
    if (!_hasReliableGps) return;
    if (_failedRetryCount <= 4) {
      final wait = _rerouteGate.remainingCooldown;
      _rerouteRetryTimer = Timer(
        wait > Duration.zero ? wait : const Duration(seconds: 2),
        () {
          if (mounted &&
              !_hasArrived &&
              !_isReRouting &&
              _hasReliableGps &&
              _rerouteGate.tryBegin()) {
            debugPrint(
              '[NavigationScreen] Auto-retrying reroute (attempt $_failedRetryCount of 4)...',
            );
            _triggerReRoute(
              _lastRequestReason ?? 'Retrying route calculation...',
              confirmedHazard: _activeConfirmedHazard,
              avoidRoadIds: Set<String>.of(_lastRequestedAvoidIds),
            );
          }
        },
      );
    } else {
      debugPrint(
        '[NavigationScreen] Auto-retry capped at 4 attempts. Persistent offline banner displayed.',
      );
    }
  }

  @override
  void dispose() {
    _gpsRequestGeneration++;
    _gpsStreamGeneration++;
    _riskGeneration++;
    _riskDialogContext = null;
    _refreshTripDetails = null;
    _tripDetailsGeneration++;
    _haltGeneration++;
    _refreshHaltDialog = null;
    _pendingRouteRefreshTimer?.cancel();
    SessionActivity.navigating = false;
    _diagnostics?.dispose();
    _adminUpdateDebounceTimer?.cancel();
    AppStateService.instance.removeListener(_onAdminFloodUpdate);
    SimulatedWeatherService.instance.listenable.removeListener(
      _onAdminFloodUpdate,
    );
    _positionSubscription?.cancel();
    _gpsFreshnessTimer?.cancel();
    _routeNoticeTimer?.cancel();
    _rerouteAttempt++;
    _stalenessTimer?.cancel();
    _rerouteRetryTimer?.cancel();
    _pendingHazardTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refreshDetails = _refreshTripDetails;
    if (refreshDetails != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(refreshDetails, _refreshTripDetails))
          refreshDetails();
      });
    }
    final currentStep =
        _routeTracker.initialDirectionStep ??
        (_currentRoute.steps.isNotEmpty &&
                _currentStepIndex < _currentRoute.steps.length
            ? _currentRoute.steps[_currentStepIndex]
            : null);

    return Scaffold(
      body: Stack(
        children: [
          // 1. The Map with 3D Navigation Perspective
          widget.mapBuilder?.call(
                _riskPreview?.points ?? _currentRoute.points,
              ) ??
              AppMap(
                followMode: _riskPreview == null,
                navigationMode: true,
                routeReferenceOnly: !_hasArrived && _progressPaused,
                navigationVehicleType: _navVehicleType,
                navigationBearing: _markerHeading.bearing,
                destinationPoint:
                    (_riskPreview?.points ?? _currentRoute.points).lastOrNull,
                onUserPan: () {
                  if (_isFollowingUser)
                    setState(() => _isFollowingUser = false);
                },
                routePoints:
                    _riskPreview?.points ?? _routeTracker.remainingPoints(),
                travelledRoutePoints: _riskPreview == null
                    ? _routeTracker.travelledPoints
                    : const [],
                onMapCreatedCallback: (map) {
                  _mapboxMap = map;
                  if (_currentRoute.points.isNotEmpty) {
                    _animateCameraToPosition(
                      _currentLocation ?? _currentRoute.points.first,
                      zoom: 17.5,
                      pitch: 40.0,
                    );
                  }
                },
              ),

          NavigationHud(
            guidance: _buildGuidance(currentStep),
            notice: _navigationNotice(),
            controls: _buildMapControls(),
            footer: _buildBottomStatusBar(context),
          ),
        ],
      ),
    );
  }

  // ─── ARRIVAL BANNER UI ────────────────────────────────────────────────────
  Widget _buildGuidance(RouteStep? step) {
    if (_hasArrived) {
      return NavigationGuidanceCard(
        title: tr(context, 'You Have Arrived!'),
        detail: _navDestinationName == null
            ? tr(context, 'End of the planned route reached.')
            : '${tr(context, 'Planned destination reached')}: $_navDestinationName',
        icon: Icons.flag_outlined,
        tone: NavigationTone.success,
      );
    }
    if (!_hasReliableGps) {
      return NavigationGuidanceCard(
        title: tr(context, 'Guidance paused'),
        detail: tr(
          context,
          _gpsMessage ?? 'Waiting for a reliable GPS location.',
        ),
        icon: Icons.location_disabled_outlined,
        tone: NavigationTone.caution,
        action: TextButton(
          onPressed: _retryingGps ? null : _retryGps,
          child: Text(
            tr(context, _retryingGps ? 'Checking GPS...' : 'Retry GPS'),
          ),
        ),
      );
    }
    if (_riskReviewRequired ||
        _activeConfirmedHazard != null ||
        _noClearRouteFound ||
        _routeFailureMessage != null) {
      return NavigationGuidanceCard(
        title: tr(context, 'Guidance paused'),
        detail: tr(
          context,
          _riskPreview != null
              ? 'Alternative preview only. Guidance is paused.'
              : 'Gray dashed line: previous route. Guidance is paused.',
        ),
        icon: Icons.pause_circle_outline,
        tone: NavigationTone.caution,
      );
    }
    if (_isReRouting || _offRoute) {
      return NavigationGuidanceCard(
        title: tr(
          context,
          _isReRouting ? 'Recalculating Route...' : 'Checking your position',
        ),
        detail: tr(
          context,
          _offRoute
              ? 'You are off the planned route.'
              : 'Updating directions...',
        ),
        icon: Icons.route_outlined,
        busy: _isReRouting,
      );
    }
    if (step == null) {
      return NavigationGuidanceCard(
        title: tr(context, 'Follow the displayed route'),
        detail: tr(
          context,
          'Turn instructions are unavailable for this route.',
        ),
        icon: Icons.route_outlined,
      );
    }
    IconData icon = Icons.straight;
    if (step.modifier.contains('left')) icon = Icons.turn_left;
    if (step.modifier.contains('right')) icon = Icons.turn_right;
    if (step.modifier.contains('uturn')) icon = Icons.u_turn_left;
    if (step.type.contains('arrive')) icon = Icons.location_on_outlined;
    final instruction = _displayMessage(
      step.instruction.replaceAll(RegExp(r'<[^>]*>'), ''),
    );
    // Provider instructions are authored data; static navigation hints translate.
    return NavigationGuidanceCard(
      title: step.type == 'depart'
          ? tr(context, 'Start in this direction')
          : _liveDistanceToNextStep <= 8
          ? tr(
              context,
              step.type == 'arrive' ? 'Destination ahead' : 'Turn now',
            )
          : navigationDistance(_liveDistanceToNextStep),
      detail: instruction,
      icon: icon,
    );
  }

  Widget _noticeAction(String label, VoidCallback? action) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    child: Text(tr(context, label)),
  );

  void _retryRoute() {
    if (_isReRouting || !_hasReliableGps) return;
    if (_pendingRouteRefresh != null) {
      _forcePendingRouteRefresh = true;
      _processPendingRouteRefresh();
      return;
    }
    if (!_rerouteGate.tryBegin(force: true)) return;
    _triggerReRoute(
      _lastRequestReason ?? 'Retrying route calculation...',
      confirmedHazard: _activeConfirmedHazard,
      avoidRoadIds: Set<String>.of(_lastRequestedAvoidIds),
    );
  }

  void _requestDetour() {
    if (_isReRouting || !_hasReliableGps) return;
    // Read the current advisory set when pressed; an old details sheet cannot
    // submit a stale list or bypass the existing reroute gate.
    final ids = _unconfirmedStaleRoads.map((r) => r.id).toSet();
    if (ids.isEmpty || !_rerouteGate.tryBegin(force: true)) return;
    _triggerReRoute(
      'Looking for a detour around unconfirmed road segments...',
      avoidRoadIds: ids,
    );
  }

  NavigationNotice? _navigationNotice() {
    if (_hasArrived) return null;
    final hazard = _activeConfirmedHazard;
    final hazardText = hazard == null
        ? ''
        : '${_roadLabel(hazard.name)}: ${tr(context, hazard.status == 'not_passable' ? 'Not passable' : 'Partially flooded')}.';
    final gpsWaiting = !_hasReliableGps
        ? tr(context, 'Waiting for GPS before checking another route.')
        : '';
    if (_riskReviewRequired) {
      return NavigationNotice(
        title: tr(
          context,
          _riskPreview == null
              ? 'Critical predicted risk: review required'
              : 'Alternative preview \u2014 guidance paused',
        ),
        detail: [
          tr(context, _riskReviewMessage),
          if (hazard != null) hazardText,
          if (gpsWaiting.isNotEmpty) gpsWaiting,
        ].join(' '),
        tone: NavigationTone.danger,
        icon: Icons.gpp_maybe_outlined,
        busy: _isReRouting,
        actions: [
          if (_pendingRiskRoute != null)
            _noticeAction(
              'Review alternative',
              _reviewingRisk || _isReRouting || !_hasReliableGps
                  ? null
                  : _reviewRiskRoute,
            ),
          _noticeAction(
            'Retry route',
            _isReRouting || !_hasReliableGps ? null : _retryRiskRoute,
          ),
        ],
      );
    }
    if (_noClearRouteFound || hazard != null) {
      final blocked = hazard?.status == 'not_passable';
      final nearClosure = _nearConfirmedClosure;
      final reopening =
          _isReRouting &&
          (_calculationReason ?? '').toLowerCase().contains('reopen');
      return NavigationNotice(
        title: tr(
          context,
          reopening
              ? 'Road reopened'
              : nearClosure
              ? 'Closure near your location'
              : _noClearRouteFound
              ? 'No clear route found'
              : blocked
              ? 'Road ahead not passable'
              : 'Flooding reported ahead',
        ),
        detail: [
          if (hazard != null) hazardText,
          if (nearClosure)
            tr(
              context,
              'Your GPS location is on or near a road marked not passable.',
            ),
          if (_noClearRouteFound && !reopening && !nearClosure)
            tr(context, 'No returned route avoids the confirmed closures.'),
          if (gpsWaiting.isNotEmpty)
            gpsWaiting
          else if (_isReRouting)
            tr(context, 'Finding another route...')
          else if (_routeFailureMessage != null)
            tr(
              context,
              'Route update unavailable. The previous route contains a confirmed hazard.',
            )
          else
            tr(
              context,
              'Wait for a checked alternative and follow local instructions.',
            ),
        ].join(' '),
        tone: NavigationTone.danger,
        icon: Icons.block_outlined,
        busy: _isReRouting,
        actions: [
          _noticeAction(
            'Retry Now',
            _isReRouting || !_hasReliableGps ? null : _retryRoute,
          ),
          if (_noClearRouteFound)
            _noticeAction('View options', _showHaltDialog),
        ],
      );
    }
    if (_routeFailureMessage != null) {
      return NavigationNotice(
        title: tr(context, 'Could not update route'),
        detail: tr(context, _routeFailureMessage!),
        tone: NavigationTone.caution,
        icon: Icons.error_outline,
        busy: _isReRouting,
        actions: [
          _noticeAction(
            'Retry Now',
            _isReRouting || !_hasReliableGps ? null : _retryRoute,
          ),
        ],
      );
    }
    if (_isReRouting) {
      // The main direction card already explains off-route recalculation.
      if (_offRoute) return null;
      return NavigationNotice(
        title: tr(
          context,
          (_calculationReason ?? '').toLowerCase().contains('reopen')
              ? 'Road reopened'
              : 'Looking for another route',
        ),
        detail: tr(context, 'Checking current road conditions.'),
        busy: true,
        icon: Icons.alt_route,
      );
    }
    if (_pendingRouteRefresh != null && _hasReliableGps) {
      return NavigationNotice(
        title: tr(context, 'Route update pending'),
        detail: tr(context, 'The interrupted route check will retry shortly.'),
        icon: Icons.schedule,
        actions: [_noticeAction('Retry Now', _retryRoute)],
      );
    }
    if (!_hasReliableGps || _offRoute) return null;
    if (_showRouteUpdate) {
      return NavigationNotice(
        title: tr(context, 'Route updated'),
        detail: [
          _displayMessage(_routeUpdateSummary!),
          if (_currentRoute.safetyStatus == 'critical')
            tr(context, 'Critical predicted risk on this route'),
          if (_currentRoute.needsCaution)
            tr(context, _currentRoute.conditionSummary),
          if (_liveDataUnavailable)
            tr(
              context,
              'Live road or weather data is unavailable or outdated. Confirm current conditions before travel.',
            ),
        ].join(' '),
        tone: _currentRoute.safetyStatus == 'critical'
            ? NavigationTone.danger
            : NavigationTone.information,
        icon: Icons.alt_route,
        // Blue is an update acknowledgement, not a declaration of safety.
        actions: [_noticeAction('Trip details', _showTripDetails)],
      );
    }
    if (_noDifferentDetour &&
        (_currentRoute.hasUnverifiedConditions ||
            _unconfirmedStaleRoads.isNotEmpty)) {
      return NavigationNotice(
        title: tr(context, 'No different detour found'),
        detail: tr(
          context,
          'Conditions still need confirmation. Check local updates.',
        ),
        tone: NavigationTone.caution,
        icon: Icons.alt_route,
        actions: [_noticeAction('View conditions', _showTripDetails)],
      );
    }
    if (_currentRoute.safetyStatus == 'critical') {
      return NavigationNotice(
        title: tr(context, 'Critical predicted risk on this route'),
        detail: tr(
          context,
          'This route was reviewed. Conditions may change; check current local updates.',
        ),
        tone: NavigationTone.danger,
        icon: Icons.gpp_maybe_outlined,
        actions: [_noticeAction('View conditions', _showTripDetails)],
      );
    }
    if (_currentRoute.hasUnverifiedConditions ||
        _unconfirmedStaleRoads.isNotEmpty) {
      final count = _currentRoute.unverifiedRoadCount;
      return NavigationNotice(
        title: count > 0
            ? '$count ${tr(context, count == 1 ? 'road segment unconfirmed' : 'road segments unconfirmed')}'
            : tr(context, 'Road conditions need confirmation'),
        detail: tr(
          context,
          _liveDataUnavailable
              ? 'Live road or weather data is unavailable or outdated. Confirm current conditions before travel.'
              : 'Check current local updates.',
        ),
        tone: NavigationTone.caution,
        icon: Icons.warning_amber_rounded,
        actions: [_noticeAction('View conditions', _showTripDetails)],
      );
    }
    if (_liveDataUnavailable) {
      return NavigationNotice(
        title: tr(context, 'Live conditions need confirmation'),
        detail: tr(
          context,
          'Live road or weather data is unavailable or outdated. Confirm current conditions before travel.',
        ),
        tone: NavigationTone.caution,
        icon: Icons.cloud_off_outlined,
        actions: [_noticeAction('View conditions', _showTripDetails)],
      );
    }
    if (_currentRoute.needsCaution || _warningChipMessage != null) {
      return NavigationNotice(
        title: tr(context, 'Caution on this route'),
        detail: tr(context, _currentRoute.conditionSummary),
        tone: NavigationTone.caution,
        icon: Icons.warning_amber_rounded,
        actions: [_noticeAction('View conditions', _showTripDetails)],
      );
    }
    return null;
  }

  Widget _mapControl(String tooltip, IconData icon, VoidCallback action) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: IconButton(
        tooltip: tr(context, tooltip),
        onPressed: action,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        color: p.primary,
        icon: Icon(icon),
      ),
    );
  }

  Widget _buildMapControls() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (_diagnostics != null)
        _mapControl(
          'Test diagnostics',
          Icons.bug_report_outlined,
          _showDiagnostics,
        ),
      const Spacer(),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasArrived) ...[
            _mapControl(
              'Route overview',
              Icons.route_outlined,
              _showRouteOverview,
            ),
            const SizedBox(height: 8),
          ],
          _mapControl('Recenter', Icons.my_location, () {
            setState(() => _isFollowingUser = true);
            final location =
                _currentLocation ?? _currentRoute.points.firstOrNull;
            if (location != null)
              _animateCameraToPosition(location, zoom: 17.5, pitch: 40);
          }),
        ],
      ),
    ],
  );

  bool get _progressPaused =>
      !_hasReliableGps ||
      _offRoute ||
      _isReRouting ||
      _riskReviewRequired ||
      _activeConfirmedHazard != null ||
      _routeFailureMessage != null ||
      _noClearRouteFound;

  Future<void> _showRouteOverview() async {
    final map = _mapboxMap;
    if (map == null) return;
    final points = _riskPreview?.points ?? _routeTracker.remainingPoints();
    if (points.isEmpty) return;
    setState(() => _isFollowingUser = false);
    try {
      final camera = await map.cameraForCoordinatesPadding(
        points.map((p) => Point(coordinates: p)).toList(),
        CameraOptions(bearing: 0, pitch: 0),
        MbxEdgeInsets(top: 210, left: 40, bottom: 250, right: 40),
        17,
        null,
      );
      if (!mounted || !identical(map, _mapboxMap) || _isFollowingUser) return;
      await map.flyTo(camera, MapAnimationOptions(duration: 700));
    } catch (_) {
      // Recenter and manual gestures remain available if camera fitting fails.
    }
  }

  void _showTripDetails() {
    if (_refreshTripDetails != null) return;
    final generation = ++_tripDetailsGeneration;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          _refreshTripDetails = () {
            if (mounted &&
                sheetContext.mounted &&
                generation == _tripDetailsGeneration)
              setSheetState(() {});
          };
          final notice = _navigationNotice();
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .72,
                child: NavigationTripDetailsSheet(
                  destination:
                      _navDestinationName ??
                      tr(context, 'Selected map destination'),
                  vehicle: tr(context, _navVehicleType),
                  conditionSummary: _currentRoute.conditionSummary,
                  scoreLabel: _currentRoute.safetyScoreLabel,
                  stepTiming: _routeTracker.hasStepTiming,
                  paused: _progressPaused,
                  notice:
                      notice != null &&
                          notice.title != tr(context, 'Route updated')
                      ? NavigationNotice(
                          title: notice.title,
                          detail: notice.detail,
                          tone: notice.tone,
                          icon: notice.icon,
                          busy: notice.busy,
                        )
                      : null,
                  gpsMessage:
                      !_hasArrived && !_hasReliableGps && _gpsMessage != null
                      ? tr(context, _gpsMessage!)
                      : null,
                  unconfirmedRoads: _hasArrived
                      ? const []
                      : [
                          for (final road in _unconfirmedStaleRoads)
                            '${_roadLabel(road.name)}: ${tr(context, 'Conditions unconfirmed')}',
                        ],
                  hazardAlerts: [
                    for (final alert in _currentRoute.hazardAlerts)
                      _displayMessage(alert),
                  ],
                  routeUpdate: _routeUpdateSummary == null
                      ? null
                      : _displayMessage(_routeUpdateSummary!),
                  updatedAt: _routeUpdatedAt == null
                      ? null
                      : '${tr(context, 'Updated at')} ${localizedClock(sheetContext, _routeUpdatedAt!)}',
                  showDetour: !_hasArrived && _unconfirmedStaleRoads.isNotEmpty,
                  onDetour: _isReRouting || !_hasReliableGps
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _requestDetour();
                        },
                  onClose: () => Navigator.pop(sheetContext),
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (generation == _tripDetailsGeneration) _refreshTripDetails = null;
    });
  }

  Widget _buildBottomStatusBar(BuildContext context) {
    final paused = !_hasArrived && _progressPaused;
    final reference =
        _isReRouting ||
        _activeConfirmedHazard != null ||
        _riskReviewRequired ||
        _routeFailureMessage != null ||
        _noClearRouteFound;
    final seconds = _routeTracker.remainingSeconds;
    return NavigationTripPanel(
      time: _hasArrived ? tr(context, 'Arrived') : navigationTime(seconds),
      distance: _hasArrived
          ? tr(context, 'Destination reached')
          : '${navigationDistance(_routeTracker.remainingDistanceMeters)} ${tr(context, 'remaining')}',
      estimateLabel: tr(
        context,
        _hasArrived
            ? 'Trip complete'
            : paused
            ? reference
                  ? 'Previous route estimate'
                  : 'Estimates paused'
            : 'Estimated time remaining',
      ),
      arrival: !_hasArrived && !paused && seconds.isFinite && seconds >= 0
          ? '${tr(context, 'Arrival')}: ${localizedClock(context, _timeNow().add(Duration(seconds: seconds.ceil())))}'
          : null,
      arrived: _hasArrived,
      paused: paused,
      onDetails: _showTripDetails,
      onEnd: () => Navigator.pop(context),
    );
  }
}
