import 'communication_service.dart';
import 'road_maintenance_service.dart';
import '../config/app_environment.dart';
import 'report_submission_repository.dart';
import 'resident_report_update.dart';
import 'admin_report_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'user_service.dart';
import 'sync_health.dart';
import 'last_road_sync_store.dart';
import 'report_history.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'weather_service.dart';
import 'notification_service.dart';
import '../utils/geo_utils.dart';
import '../utils/privacy_diagnostics.dart';

import '../models/road_status.dart';
import '../models/user_profile.dart';
import '../models/user_report.dart';
import '../models/broadcast_alert.dart';
import '../models/system_action_log.dart';
import '../models/alert_template.dart';
import 'risk_engine.dart';

// --- RE-EXPORTS FOR BACKWARDS COMPATIBILITY ---
export '../models/road_status.dart';
export '../models/user_profile.dart';
export '../models/user_report.dart';
export '../models/broadcast_alert.dart';
export '../models/system_action_log.dart';
export '../models/alert_template.dart';
export 'risk_engine.dart';

class AppStateService extends ChangeNotifier {
  static final AppStateService _instance = AppStateService._internal();
  static AppStateService get instance => _instance;

  AppStateService._internal();

  late final _reportSubmission = ReportSubmissionRepository.platform();
  final syncHealth = SyncHealth();
  final mapChanges = ValueNotifier<int>(0);
  List<UserReport> _activeReports = [];
  List<UserReport> _ownRecentReports = [];
  int _listenerGeneration = 0;
  Timer? _retryTimer;
  Timer? _freshnessTimer;
  int _retrySeconds = 5;
  bool _retrying = false;
  LastRoadSyncStore? _roadSyncStore;

  void _syncError(String channel, Object error) {
    if (syncHealth.channels[channel] != SyncCondition.failed) {
      debugPrint('[SyncHealth] $channel: ${privacySafeErrorCode(error)}');
    }
    syncHealth.fail(channel);
    notifyListeners();
    _retryTimer ??= Timer(Duration(seconds: _retrySeconds), () {
      _retryTimer = null;
      _retrySeconds = (_retrySeconds * 2).clamp(5, 60);
      retrySync();
    });
  }

  Future<void> retrySync() async {
    if (_retrying) return;
    if (!_useMock && FirebaseAuth.instance.currentUser == null) return;
    _retrying = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _initialized = false;
    syncHealth.reset();
    notifyListeners();
    try {
      await initialize();
    } catch (e) {
      _syncError('roads', e);
    } finally {
      _retrying = false;
    }
  }

  Future<void> clearSession() async {
    _listenerGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _freshnessTimer?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _roads = [];
    _reports = [];
    _activeReports = [];
    _ownRecentReports = [];
    mapChanges.value++;
    _alerts = [];
    _users = [];
    _initialized = false;
    _sessionUid = null;
    syncHealth.reset(clearHistory: true);
    _roadSyncStore = null;
    await SimulatedWeatherService.instance.disconnectAccount();
    SimulatedWeatherService.instance.listenable.removeListener(
      _onWeatherChanged,
    );
    notifyListeners();
  }

  bool get requiresLiveDataWarning =>
      !_useMock && initialized && !syncHealth.healthy;

  String? _sessionUid;
  bool _initialized = false;
  bool get initialized => _initialized;
  final List<StreamSubscription> _subscriptions = [];

  List<RoadStatus> _roads = [];
  List<UserReport> _reports = [];
  List<BroadcastAlert> _alerts = [];

  // Unread alert tracking — DateTime.now() default so fresh installs see 0 unread
  DateTime _lastSeenAlertsTimestamp = DateTime.now();

  // Default custom templates
  final List<AlertTemplate> _templates = [
    AlertTemplate(
      id: '1',
      label: 'Severe Flood',
      title: 'Severe Flood Warning',
      message:
          'Please avoid low-lying areas immediately. Severe flooding is expected.',
      severity: 2,
    ),
    AlertTemplate(
      id: '2',
      label: 'Road Clearing',
      title: 'Road Clearing Operations',
      message:
          'Clearing operations are ongoing. Expect heavy traffic and temporary blockages.',
      severity: 1,
    ),
    AlertTemplate(
      id: '3',
      label: 'Evacuation',
      title: 'Evacuation Notice',
      message:
          'Immediate evacuation is strongly advised for residents in vulnerable areas.',
      severity: 2,
    ),
  ];
  List<AlertTemplate> get templates => _templates;

  // Predictive Routing Engine
  Future<Map<String, dynamic>> buildAndVerifyRoadGraph() async {
    if (AppEnvironment.sparkCoreEnabled && !_useMock)
      return RoadMaintenanceService.rebuild();
    try {
      debugPrint('[AppStateService] Building Road Graph...');
      final snapshot = await FirebaseFirestore.instance
          .collection('roads')
          .get();
      List<RoadStatus> tempRoads = snapshot.docs
          .map((d) => RoadStatus.fromJson({...d.data(), 'id': d.id}))
          .toList();

      int orphanCount = 0;
      final validIds = tempRoads.map((r) => r.id).toSet();
      for (var road in tempRoads) {
        for (var nId in road.neighbors) {
          if (!validIds.contains(nId)) {
            orphanCount++;
          }
        }
      }

      int totalRoads = tempRoads.length;
      int totalConnections = 0;
      int disconnectedRoads = 0;

      // Reset neighbors
      for (int i = 0; i < tempRoads.length; i++) {
        tempRoads[i] = tempRoads[i].copyWith(neighbors: []);
      }

      // Precompute points and bounding boxes for fast spatial pruning (reduces O(n²·pts²) by >95%)
      final roadPoints = <int, List<GeoCoord>>{};
      final roadBoxes = <int, Map<String, double>>{};
      const bufferDegrees = 0.0003; // ~30m buffer in degrees

      for (int i = 0; i < tempRoads.length; i++) {
        final pts = GeoUtils.extractPoints(tempRoads[i].geometry);
        roadPoints[i] = pts;
        if (pts.isNotEmpty) {
          double minLat = pts.first.lat, maxLat = pts.first.lat;
          double minLng = pts.first.lng, maxLng = pts.first.lng;
          for (final p in pts) {
            if (p.lat < minLat) minLat = p.lat;
            if (p.lat > maxLat) maxLat = p.lat;
            if (p.lng < minLng) minLng = p.lng;
            if (p.lng > maxLng) maxLng = p.lng;
          }
          roadBoxes[i] = {
            'minLat': minLat - bufferDegrees,
            'maxLat': maxLat + bufferDegrees,
            'minLng': minLng - bufferDegrees,
            'maxLng': maxLng + bufferDegrees,
          };
        }
      }

      // Check intersections
      for (int i = 0; i < tempRoads.length; i++) {
        final roadA = tempRoads[i];
        final ptsA = roadPoints[i] ?? [];
        final boxA = roadBoxes[i];
        if (ptsA.isEmpty || boxA == null) continue;

        Set<String> newNeighbors = {};

        for (int j = 0; j < tempRoads.length; j++) {
          if (i == j) continue;
          final roadB = tempRoads[j];
          final ptsB = roadPoints[j] ?? [];
          final boxB = roadBoxes[j];
          if (ptsB.isEmpty || boxB == null) continue;

          // Fast bounding box overlap check (rejects disjoint roads in O(1))
          if (boxA['maxLat']! < boxB['minLat']! ||
              boxA['minLat']! > boxB['maxLat']! ||
              boxA['maxLng']! < boxB['minLng']! ||
              boxA['minLng']! > boxB['maxLng']!) {
            continue;
          }

          // Check if any point in B is very close to any SEGMENT of A (fixes T-junctions)
          bool intersects = false;
          for (final pB in ptsB) {
            for (int k = 0; k < ptsA.length - 1; k++) {
              final pA1 = ptsA[k];
              final pA2 = ptsA[k + 1];
              double dist = GeoUtils.pointToSegmentDistanceMeters(
                pB.lng,
                pB.lat,
                pA1.lng,
                pA1.lat,
                pA2.lng,
                pA2.lat,
              );
              if (dist < 25.0) {
                // 25 meters tolerance for T-junctions
                intersects = true;
                break;
              }
            }
            if (intersects) break;
          }

          if (!intersects) {
            // Check reverse: any point in A close to any segment in B
            for (final pA in ptsA) {
              for (int k = 0; k < ptsB.length - 1; k++) {
                final pB1 = ptsB[k];
                final pB2 = ptsB[k + 1];
                double dist = GeoUtils.pointToSegmentDistanceMeters(
                  pA.lng,
                  pA.lat,
                  pB1.lng,
                  pB1.lat,
                  pB2.lng,
                  pB2.lat,
                );
                if (dist < 25.0) {
                  intersects = true;
                  break;
                }
              }
              if (intersects) break;
            }
          }

          if (intersects) {
            newNeighbors.add(roadB.id);
          }
        }

        tempRoads[i] = roadA.copyWith(neighbors: newNeighbors.toList());
      }

      // Batch update Firestore and calculate metrics
      WriteBatch batch = FirebaseFirestore.instance.batch();
      var graphBatchCount = 0;

      int maxNeighbors = 0;
      List<String> disconnectedRoadNames = [];
      List<String> suspiciousRoads = [];
      int symmetryViolations = 0;

      // 1. Calculate symmetry violations
      for (var road in tempRoads) {
        for (var nId in road.neighbors) {
          final neighbor = tempRoads.firstWhere(
            (r) => r.id == nId,
            orElse: () => road,
          );
          if (neighbor.id != road.id && !neighbor.neighbors.contains(road.id)) {
            symmetryViolations++;
          }
        }
      }

      // 2. Calculate Connected Components
      Set<String> visited = {};
      int connectedComponents = 0;
      List<int> componentSizes = [];

      void dfs(String roadId) {
        visited.add(roadId);
        final road = tempRoads.firstWhere((r) => r.id == roadId);
        for (var nId in road.neighbors) {
          if (!visited.contains(nId)) {
            dfs(nId);
          }
        }
      }

      for (var road in tempRoads) {
        if (!visited.contains(road.id)) {
          int startSize = visited.length;
          dfs(road.id);
          componentSizes.add(visited.length - startSize);
          connectedComponents++;
        }
      }

      for (var road in tempRoads) {
        if (road.neighbors.isEmpty) {
          disconnectedRoads++;
          disconnectedRoadNames.add(road.name.isNotEmpty ? road.name : road.id);
        }
        if (road.neighbors.length > maxNeighbors) {
          maxNeighbors = road.neighbors.length;
        }
        if (road.neighbors.length > 8) {
          suspiciousRoads.add(
            '${road.name.isNotEmpty ? road.name : road.id} (${road.neighbors.length})',
          );
        }
        totalConnections += road.neighbors.length;

        final docRef = FirebaseFirestore.instance
            .collection('roads')
            .doc(road.id);
        batch.update(docRef, {
          'neighbors': road.neighbors,
          if (AppEnvironment.sparkCoreEnabled)
            'riskInputsUpdatedAt': FieldValue.serverTimestamp(),
        });
        graphBatchCount++;
        if (graphBatchCount == 400) {
          if (AppEnvironment.sparkCoreEnabled)
            batch.set(FirebaseFirestore.instance.doc('system/road_inputs'), {
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          graphBatchCount = 0;
        }
      }

      if (graphBatchCount > 0) {
        if (AppEnvironment.sparkCoreEnabled)
          batch.set(FirebaseFirestore.instance.doc('system/road_inputs'), {
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        await batch.commit();
      }

      double avgNeighbors = totalRoads > 0
          ? (totalConnections / totalRoads)
          : 0;

      debugPrint('--- ADVANCED GRAPH INTEGRITY REPORT ---');
      debugPrint('Total Roads: $totalRoads');
      debugPrint('Total Connections: $totalConnections');
      debugPrint(
        'Average Neighbors per Road: ${avgNeighbors.toStringAsFixed(2)}',
      );
      debugPrint('Maximum Neighbors: $maxNeighbors');
      debugPrint('Disconnected Roads: $disconnectedRoads');
      debugPrint('Orphan References (cleaned): $orphanCount');
      if (disconnectedRoadNames.isNotEmpty)
        debugPrint('   -> ${disconnectedRoadNames.join(', ')}');
      debugPrint('Symmetry Violations: $symmetryViolations');
      debugPrint('Connected Components: $connectedComponents');
      debugPrint('   -> Component Sizes: ${componentSizes.join(', ')}');
      debugPrint('Suspicious Roads (>8 neighbors): ${suspiciousRoads.length}');
      if (suspiciousRoads.isNotEmpty)
        debugPrint('   -> ${suspiciousRoads.join(', ')}');
      debugPrint('---------------------------------------');

      return {
        'totalRoads': totalRoads,
        'avgNeighbors': avgNeighbors,
        'disconnectedRoads': disconnectedRoads,
        'maximumNeighbors': maxNeighbors,
        'connectedComponents': connectedComponents,
      };
    } catch (e) {
      debugPrint('[AppStateService] Error building road graph: $e');
      rethrow;
    }
  }

  // State maps
  int lastRiskEngineExecutionMs = 0;
  DateTime? lastRiskEngineRun;
  List<UserProfile> _users = [];
  final List<SystemActionLog> _systemLogs = [];
  final Set<String> _dismissedAlertIds = {};
  Set<String> _rawDismissedAlertIds = {};
  bool _alertsLoaded = false;

  void _pruneDismissedAlerts() {
    if (!_alertsLoaded) {
      // Alerts haven't arrived from Firestore yet: keep all dismissed IDs optimistically
      _dismissedAlertIds.addAll(_rawDismissedAlertIds);
      return;
    }
    // Alerts have arrived: safely prune IDs not in active alert pool to prevent unbounded growth
    final activeAlertIds = _alerts.map((a) => a.id).toSet();
    _dismissedAlertIds.clear();
    for (final id in _rawDismissedAlertIds) {
      if (activeAlertIds.contains(id)) {
        _dismissedAlertIds.add(id);
      }
    }
  }

  List<RoadStatus> get roads => _roads;
  List<UserReport> get reports => _reports;
  List<BroadcastAlert> get alerts => _alerts
      .where(
        (a) =>
            !_dismissedAlertIds.contains(a.id) &&
            (!AppEnvironment.sparkCommunicationsEnabled ||
                a.studyArea == null ||
                a.isActive),
      )
      .toList();
  List<BroadcastAlert> get broadcastHistory => List.unmodifiable(_alerts);

  /// Number of alerts the user hasn't seen yet.
  int get unreadAlertCount =>
      alerts.where((a) => a.createdAt.isAfter(_lastSeenAlertsTimestamp)).length;

  /// Mark all current alerts as seen. Persists to SharedPreferences.
  Future<void> markAlertsSeen() async {
    _lastSeenAlertsTimestamp = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'lastSeenAlerts',
        _lastSeenAlertsTimestamp.millisecondsSinceEpoch,
      );
    } catch (_) {}
    notifyListeners();
  }

  List<UserProfile> get users => _users;
  List<SystemActionLog> get systemLogs => List.unmodifiable(_systemLogs);

  void _mergeReportFeeds() {
    _reports = mergeReportFeeds(_activeReports, _ownRecentReports);
  }

  ReportHistory createReportHistory({
    String? userId,
    DateTime? since,
    List<String>? statuses,
    String? dismissReason,
  }) {
    if (!_useMock)
      return ReportHistory(
        ReportHistoryRepository(
          firestore: _db,
          userId: userId,
          since: since,
          statuses: statuses,
          dismissReason: dismissReason,
        ).fetch,
      );
    return ReportHistory((cursor) async {
      final filtered =
          _reports
              .where(
                (report) =>
                    (dismissReason == null ||
                        report.dismissReason == dismissReason) &&
                    (statuses == null || statuses.contains(report.status)) &&
                    (userId == null || report.userId == userId) &&
                    (since == null || !report.createdAt.isBefore(since)),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final start = cursor == null
          ? 0
          : filtered.indexWhere((report) => report.id == cursor.id) + 1;
      final page = filtered.skip(start).take(ReportHistory.pageSize).toList();
      return ReportPage(
        page,
        next: page.length == ReportHistory.pageSize
            ? ReportCursor(
                Timestamp.fromDate(page.last.createdAt),
                page.last.id,
              )
            : null,
      );
    });
  }

  bool get _useMock => Firebase.apps.isEmpty;
  FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  void _onWeatherChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    SimulatedWeatherService.instance.listenable.removeListener(
      _onWeatherChanged,
    );
    _retryTimer?.cancel();
    _freshnessTimer?.cancel();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    mapChanges.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    final uid = _useMock ? 'mock' : FirebaseAuth.instance.currentUser?.uid;
    if (_initialized && uid == _sessionUid) return;
    _sessionUid = uid;
    final generation = ++_listenerGeneration;
    _initialized = true;
    _freshnessTimer?.cancel();
    if (!_useMock) {
      _freshnessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        mapChanges.value++;
        notifyListeners();
      });
    }

    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    if (_useMock) {
      _roads = [
        RoadStatus(
          id: 'macarthur',
          name: 'MacArthur Highway',
          status: 'not_passable',
          notes: 'Flooded',
          updatedAt: DateTime.now(),
        ),
        RoadStatus(
          id: 'rizal',
          name: 'Rizal Ave',
          status: 'passable',
          notes: 'Clear',
          updatedAt: DateTime.now(),
        ),
        RoadStatus(
          id: 'mh_del_pilar',
          name: 'M.H. Del Pilar',
          status: 'passable',
          notes: 'Clear',
          updatedAt: DateTime.now(),
        ),
        RoadStatus(
          id: 'karuhatan',
          name: 'Karuhatan Road',
          status: 'passable',
          notes: 'Clear',
          updatedAt: DateTime.now(),
        ),
      ];
      _reports = [
        UserReport(
          id: 'r1',
          title: 'Flooding Rizal',
          description: 'Water level high',
          createdAt: DateTime.now(),
          severity: 'High',
          status: 'pending',
          userId: 'mock_user',
        ),
        UserReport(
          id: 'r2',
          title: 'Debris MacArthur',
          description: 'Debris on road',
          createdAt: DateTime.now(),
          severity: 'Medium',
          status: 'pending',
          userId: 'mock_user',
        ),
        UserReport(
          id: 'r3',
          title: 'Traffic Karuhatan',
          description: 'Heavy traffic',
          createdAt: DateTime.now(),
          severity: 'Low',
          status: 'pending',
          userId: 'mock_user',
        ),
      ];
      _alerts = [
        BroadcastAlert(
          id: 'a1',
          title: 'Weather Advisory',
          message: 'Heavy rain expected',
          severity: 'Advisory',
          category: 'WEATHER UPDATE',
          createdAt: DateTime.now(),
        ),
        BroadcastAlert(
          id: 'a2',
          title: 'Flood Warning',
          message: 'Avoid low areas',
          severity: 'Warning',
          category: 'EMERGENCY',
          createdAt: DateTime.now(),
        ),
        BroadcastAlert(
          id: 'a3',
          title: 'System Alert',
          message: 'System maintenance',
          severity: 'Critical',
          category: 'SYSTEM',
          createdAt: DateTime.now(),
        ),
      ];
      mapChanges.value++;
      notifyListeners();
      return;
    }

    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (generation != _listenerGeneration) return;
        _roadSyncStore = LastRoadSyncStore(
          prefs,
          Firebase.app().options.projectId,
        );
        syncHealth.lastRoadSync ??= _roadSyncStore!.read();
      } catch (_) {
        // A failed preference read must not prevent cached Firestore reads.
      }
      await SimulatedWeatherService.instance.reconnectAccount();
      if (_sessionUid != uid) return;
      // Load last-seen timestamp for unread badge
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedMs = prefs.getInt('lastSeenAlerts');
        if (savedMs != null) {
          _lastSeenAlertsTimestamp = DateTime.fromMillisecondsSinceEpoch(
            savedMs,
          );
        }
        // If null (first install), keep DateTime.now() default → 0 unread
      } catch (_) {}

      _subscriptions.add(
        _db
            .collection('roads')
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                try {
                  if (generation != _listenerGeneration) return;
                  if (snapshot.docChanges.isNotEmpty || _roads.isEmpty) {
                    _roads = snapshot.docs
                        .map(
                          (doc) => RoadStatus.fromJson({
                            ...doc.data(),
                            'id': doc.id,
                          }),
                        )
                        .toList();
                    mapChanges.value++;
                  }
                  syncHealth.update(
                    'roads',
                    fromCache: snapshot.metadata.isFromCache,
                  );
                  if (!snapshot.metadata.isFromCache) {
                    unawaited(
                      _roadSyncStore
                          ?.save(syncHealth.lastRoadSync!)
                          .catchError((Object _) {}),
                    );
                  }
                  notifyListeners();
                } catch (e) {
                  _syncError('roads', e);
                }
              },
              onError: (Object e) {
                if (generation == _listenerGeneration) _syncError('roads', e);
              },
            ),
      );

      // Hazards stay complete. Historical records are fetched only by a paged view.
      _subscriptions.add(
        _db
            .collection('reports')
            .where(
              'status',
              whereIn: ['pending', 'under_review', 'waiting_resident'],
            )
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (generation != _listenerGeneration) return;
                try {
                  _activeReports = snapshot.docs
                      .map(
                        (doc) =>
                            UserReport.fromJson({...doc.data(), 'id': doc.id}),
                      )
                      .toList();
                  _mergeReportFeeds();
                  syncHealth.update(
                    'reports',
                    fromCache: snapshot.metadata.isFromCache,
                  );
                  notifyListeners();
                } catch (error) {
                  _syncError('reports', error);
                }
              },
              onError: (Object error) {
                if (generation == _listenerGeneration)
                  _syncError('reports', error);
              },
            ),
      );
      _subscriptions.add(
        _db
            .collection('reports')
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(ReportHistory.pageSize)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (generation != _listenerGeneration) return;
                try {
                  _ownRecentReports = snapshot.docs
                      .map(
                        (doc) =>
                            UserReport.fromJson({...doc.data(), 'id': doc.id}),
                      )
                      .toList();
                  _mergeReportFeeds();
                  syncHealth.update(
                    'ownReports',
                    fromCache: snapshot.metadata.isFromCache,
                  );
                  notifyListeners();
                } catch (error) {
                  _syncError('ownReports', error);
                }
              },
              onError: (Object error) {
                if (generation == _listenerGeneration)
                  _syncError('ownReports', error);
              },
            ),
      );

      _subscriptions.add(
        _db
            .collection('alerts')
            .orderBy('createdAt', descending: true)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                try {
                  if (generation != _listenerGeneration) return;
                  _alerts = snapshot.docs
                      .map(
                        (doc) => BroadcastAlert.fromJson({
                          ...doc.data(),
                          'id': doc.id,
                        }),
                      )
                      .where(
                        (a) =>
                            !AppEnvironment.sparkCommunicationsEnabled ||
                            a.studyArea == null ||
                            a.studyArea == AppEnvironment.area.id,
                      )
                      .toList();
                  _alertsLoaded = true;
                  _pruneDismissedAlerts();

                  // FCM owns system notifications. Showing another one for the
                  // same Firestore alert caused duplicate notifications.
                  syncHealth.update(
                    'alerts',
                    fromCache: snapshot.metadata.isFromCache,
                  );
                  notifyListeners();
                } catch (e) {
                  _syncError('alerts', e);
                }
              },
              onError: (Object e) {
                if (generation == _listenerGeneration) _syncError('alerts', e);
              },
            ),
      );

      _subscriptions.add(
        _db
            .doc('system/risk_job')
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (generation != _listenerGeneration) return;
                syncHealth.lastRiskCompute =
                    (snapshot.data()?['lastSuccess'] as Timestamp?)?.toDate();
                syncHealth.update(
                  'risk',
                  fromCache: snapshot.metadata.isFromCache,
                );
                if (snapshot.data()?['error'] != null) syncHealth.fail('risk');
                notifyListeners();
              },
              onError: (Object e) {
                if (generation == _listenerGeneration) _syncError('risk', e);
              },
            ),
      );

      final isAdmin = await UserService.getUserRole() == UserRole.admin;
      if (_sessionUid != uid) return;
      final userQuery = isAdmin
          ? _db.collection('users')
          : _db
                .collection('users')
                .where(
                  FieldPath.documentId,
                  isEqualTo:
                      FirebaseAuth.instance.currentUser?.uid ?? 'signed-out',
                );
      _subscriptions.add(
        userQuery.snapshots().listen(
          (snapshot) async {
            _users = snapshot.docs
                .map(
                  (doc) => UserProfile.fromJson({...doc.data(), 'id': doc.id}),
                )
                .toList();

            // Load personal dismissed alerts for current user
            try {
              final myUid = await UserService.getUserId();
              final userDoc = snapshot.docs.where((d) => d.id == myUid);
              if (userDoc.isNotEmpty) {
                final rawDismissed = userDoc.first.data()['dismissedAlertIds'];
                if (rawDismissed is List) {
                  _rawDismissedAlertIds = rawDismissed
                      .whereType<String>()
                      .toSet();
                  _pruneDismissedAlerts();
                }
              }
            } catch (_) {}

            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('User profile updates unavailable: $e');
          },
        ),
      );

      _subscriptions.add(
        _db
            .collection('alert_templates')
            .snapshots()
            .listen(
              (snapshot) {
                if (snapshot.docs.isNotEmpty) {
                  _templates.clear();
                  _templates.addAll(
                    snapshot.docs.map(
                      (doc) =>
                          AlertTemplate.fromJson({...doc.data(), 'id': doc.id}),
                    ),
                  );
                  notifyListeners();
                } else {
                  _seedDefaultTemplates();
                }
              },
              onError: (e) {
                debugPrint(
                  '[AppStateService] alert_templates stream error: $e',
                );
              },
            ),
      );

      SimulatedWeatherService.instance.listenable.removeListener(
        _onWeatherChanged,
      );
      SimulatedWeatherService.instance.listenable.addListener(
        _onWeatherChanged,
      );

      notifyListeners();
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  Future<void> _seedDefaultTemplates() async {
    try {
      final defaultList = [
        AlertTemplate(
          id: 'default_1',
          label: 'Severe Flood',
          title: 'Severe Flood Warning',
          message:
              'Please avoid low-lying areas immediately. Severe flooding is expected.',
          severity: 2,
        ),
        AlertTemplate(
          id: 'default_2',
          label: 'Road Clearing',
          title: 'Road Clearing Operations',
          message:
              'Clearing operations are ongoing. Expect heavy traffic and temporary blockages.',
          severity: 1,
        ),
        AlertTemplate(
          id: 'default_3',
          label: 'Evacuation',
          title: 'Evacuation Notice',
          message:
              'Immediate evacuation is strongly advised for residents in vulnerable areas.',
          severity: 2,
        ),
      ];
      final batch = _db.batch();
      for (final t in defaultList) {
        batch.set(_db.collection('alert_templates').doc(t.id), t.toJson());
      }
      await batch.commit();
    } catch (e) {
      debugPrint(
        '[AppStateService] Failed to seed default alert templates: $e',
      );
    }
  }

  Future<void> updateRoadStatus(
    String roadId,
    String status,
    String notes, {
    Map<String, dynamic>? geometry,
    String? name,
    String? vulnerability,
  }) async {
    if (_useMock) {
      final index = _roads.indexWhere((r) => r.id == roadId);
      if (index != -1) {
        _roads[index] = _roads[index].copyWith(
          status: status,
          notes: notes,
          updatedAt: DateTime.now(),
          source: 'manual',
          isVerified: true,
        );
      } else {
        _roads.add(
          RoadStatus(
            id: roadId,
            name: name ?? roadId,
            status: status,
            notes: notes,
            updatedAt: DateTime.now(),
            geometry: geometry,
            source: 'manual',
            isVerified: true,
          ),
        );
      }
      mapChanges.value++;
      notifyListeners();
      return;
    }

    final uid = await UserService.getUserId();
    String userName = 'Unknown';
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'] ?? 'Unknown Admin';
      }
    } catch (_) {}

    final Map<String, dynamic> data = {
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'updatedByName': userName,
      'source': 'manual',
      'isVerified': true,
    };
    if (geometry != null) {
      data['geometry'] = geometry;
    }
    if (name != null) {
      data['name'] = name;
    }
    if (vulnerability != null) {
      data['vulnerability'] = vulnerability;
    }
    await _db
        .collection('roads')
        .doc(roadId)
        .set(data, SetOptions(merge: true))
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception(
            'Unable to connect. Please check your internet connection.',
          ),
        );
  }

  Future<void> updateMultipleRoadStatus(
    Set<String> roadIds,
    String status,
    String notes, {
    String? vulnerability,
  }) async {
    final uid = await UserService.getUserId();
    String userName = 'Unknown';
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'] ?? 'Unknown Admin';
      }
    } catch (_) {}

    final Map<String, dynamic> data = {
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'updatedByName': userName,
      'source': 'manual',
      'isVerified': true,
    };
    if (vulnerability != null) {
      data['vulnerability'] = vulnerability;
    }

    WriteBatch batch = _db.batch();
    for (String roadId in roadIds) {
      batch.set(
        _db.collection('roads').doc(roadId),
        data,
        SetOptions(merge: true),
      );
    }

    await batch.commit().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception(
        'Unable to connect. Please check your internet connection.',
      ),
    );
  }

  Future<void> deleteRoadStatus(String roadId, {String? contextToken}) async {
    if (AppEnvironment.sparkCoreEnabled) {
      if (contextToken == null)
        throw StateError('Refresh the road deletion confirmation.');
      return RoadMaintenanceService.delete(roadId, contextToken);
    }
    await _db.collection('roads').doc(roadId).delete();
  }

  Future<void> submitReport(
    String title,
    String description,
    String floodLevel, [
    String? roadId,
    Map<String, dynamic>? location,
    bool isEmergency = false,
  ]) async {
    if (_useMock) {
      _reports.insert(
        0,
        UserReport(
          id: 'mock_report_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          description: description,
          createdAt: DateTime.now(),
          severity: floodLevel,
          status: 'pending',
          userId: 'mock_user',
          isEmergency: isEmergency,
        ),
      );
      notifyListeners();
      return;
    }

    final uid = await UserService.getUserId();
    final payload = <String, dynamic>{
      'title': title,
      'description': description,
      'severity': floodLevel,
      'roadId': roadId,
      'location': location,
      'isEmergency': isEmergency,
      if (location?['observedAt'] != null)
        'observedAt': location!['observedAt'],
    };
    await _reportSubmission.save(uid: uid, payload: payload);
  }

  Future<AdminActionResult> markReportUnderReview(String reportId) async {
    final latest = await AdminReportService.context(reportId: reportId);
    return AdminReportService.perform('start', {
      'reportId': reportId,
      'contextToken': latest['token'],
    });
  }

  Future<AdminActionResult> replyToReport(String reportId, String message) =>
      AdminReportService.perform('reply', {
        'reportId': reportId,
        'message': message.trim(),
      });

  /// Allows a citizen to update an existing report (severity, description) in real-time.
  Future<void> updateExistingReport({
    required String reportId,
    required String floodLevel,
    required String description,
    required DateTime expectedUpdatedAt,
  }) => ResidentReportUpdate.save(
    reportId: reportId,
    severity: floodLevel,
    description: description,
    expectedUpdatedAt: expectedUpdatedAt,
  );

  Future<void> addAlertTemplate(AlertTemplate template) async {
    if (_useMock) {
      final index = _templates.indexWhere((t) => t.id == template.id);
      if (index < 0) {
        _templates.add(template);
      } else {
        _templates[index] = template;
      }
      notifyListeners();
      return;
    }
    final docId = template.id.isEmpty
        ? _db.collection('alert_templates').doc().id
        : template.id;
    final payload = template.toJson()..['id'] = docId;
    await _db.collection('alert_templates').doc(docId).set(payload);
  }

  Future<void> deleteAlertTemplate(String id) async {
    if (_useMock) {
      _templates.removeWhere((t) => t.id == id);
      notifyListeners();
      return;
    }
    await _db.collection('alert_templates').doc(id).delete();
  }

  Future<BroadcastResult> broadcastAlert(
    String title,
    String message,
    String severity, {
    String? roadId,
    String? roadName,
    bool sendPush = false,
    int minutes = 180,
  }) async {
    if (AppEnvironment.sparkCommunicationsEnabled && !_useMock) {
      try {
        final result = await CommunicationService.command('broadcast-publish', {
          'title': title,
          'message': message,
          'severity': severity,
          'roadId': roadId,
          'sendPush': sendPush,
          'minutes': minutes,
          'studyArea': AppEnvironment.area.id,
        });
        return BroadcastResult(
          alertSaved: true,
          alertId: result['resourceId'] as String,
          queuedCount: result['queuedCount'] as int,
        );
      } catch (e) {
        return BroadcastResult(alertSaved: false, pushError: e.toString());
      }
    }
    if (_useMock) {
      String category = 'EMERGENCY';
      if (severity == 'Advisory') {
        category = 'WEATHER UPDATE';
      } else if (severity == 'Warning') {
        category = 'SYSTEM';
      }
      _alerts.insert(
        0,
        BroadcastAlert(
          id: 'mock_alert_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          message: message,
          severity: severity,
          category: category,
          createdAt: DateTime.now(),
          roadId: roadId,
          roadName: roadName,
        ),
      );
      notifyListeners();
      return BroadcastResult(alertSaved: true, pushSent: false);
    }

    String category = 'EMERGENCY';
    if (severity == 'Advisory') {
      category = 'WEATHER UPDATE';
    } else if (severity == 'Warning') {
      category = 'SYSTEM';
    }

    // Step 1: Firestore write
    String? savedAlertId;
    try {
      final uid = await UserService.getUserId();
      String userName = 'System';
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'System';
        }
      } catch (_) {}

      final docRef = await _db.collection('alerts').add({
        'title': title,
        'message': message,
        'severity': severity,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': uid,
        'createdByName': userName,
        if (roadId != null) 'roadId': roadId,
        if (roadName != null) 'roadName': roadName,
      });
      savedAlertId = docRef.id;

      // Also sync the broadcast message to the road's notes so the road sheet reflects it
      if (roadId != null) {
        try {
          await _db.collection('roads').doc(roadId).update({
            'notes': message,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint(
            '[AppStateService] Failed to sync broadcast to road notes: $e',
          );
        }
      }
    } catch (e) {
      return BroadcastResult(alertSaved: false, pushError: e.toString());
    }

    // Step 2: FCM push (only if admin toggled it on)
    bool pushSent = false;
    String? pushError;

    if (sendPush) {
      final pushRes = await NotificationService.instance.sendPushToTopic(
        title: title,
        body: message,
        data: {
          'alertId': savedAlertId,
          'severity': severity,
          'roadId': roadId ?? '',
          'roadName': roadName ?? '',
        },
      );
      pushSent = pushRes.success;
      if (!pushRes.success) {
        pushError = pushRes.message;
      }
    }

    // Single return point — no early returns from branches
    return BroadcastResult(
      alertSaved: true,
      pushSent: pushSent,
      pushError: pushError,
    );
  }

  /// Dismisses an alert for the current user only without deleting it for other citizens.
  Future<void> dismissAlertForUser(String alertId) async {
    _rawDismissedAlertIds.add(alertId);
    _dismissedAlertIds.add(alertId);
    notifyListeners();

    try {
      final uid = await UserService.getUserId();
      await _db.collection('users').doc(uid).set({
        'dismissedAlertIds': FieldValue.arrayUnion([alertId]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AppState] Failed to persist alert dismissal: $e');
    }
  }

  /// Clears all active alerts for the current user only without wiping the alerts collection.
  Future<void> clearAllAlertsForUser() async {
    final activeIds = _alerts.map((a) => a.id).toList();
    _rawDismissedAlertIds.addAll(activeIds);
    _dismissedAlertIds.addAll(activeIds);
    notifyListeners();

    try {
      final uid = await UserService.getUserId();
      await _db.collection('users').doc(uid).set({
        'dismissedAlertIds': FieldValue.arrayUnion(activeIds),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AppState] Failed to persist clear all alerts: $e');
    }
  }

  /// Admin-Only: Permanently deletes a broadcast alert from the database for ALL citizens.
  Future<void> deleteBroadcastAlert(String alertId) async {
    if (AppEnvironment.sparkCommunicationsEnabled)
      throw StateError('Use Withdraw and provide an explicit reason.');
    final role = await UserService.getUserRole();
    if (role != UserRole.admin) {
      throw Exception(
        'UNAUTHORIZED: Only administrators can purge alerts city-wide.',
      );
    }
    await _db.collection('alerts').doc(alertId).delete();
  }

  // Deprecated backward compatibility aliases
  Future<void> clearAllAlerts() => clearAllAlertsForUser();
  Future<void> removeAlert(String alertId) => dismissAlertForUser(alertId);

  double calculateLiveConfidence(UserReport report) {
    return getLiveConfidenceBreakdown(report)['total'] as double;
  }

  Map<String, dynamic> getLiveConfidenceBreakdown(UserReport report) {
    // 1. Authority (Fetch dynamically from user's trust score)
    double authority = report.authorityScore;
    try {
      final userProfile = _users.firstWhere((u) => u.id == report.userId);
      authority = userProfile.trustScore.toDouble();
    } catch (e) {
      // Ignore if user profile isn't loaded
    }

    // Re-apply photo bonus live
    if (report.imageUrl != null && report.imageUrl!.isNotEmpty) {
      authority = (authority + 30.0).clamp(0, 100);
    }

    final effectiveReport = UserReport(
      id: report.id,
      title: report.title,
      description: report.description,
      createdAt: report.createdAt,
      severity: report.severity,
      status: report.status,
      roadId: report.roadId,
      location: report.location,
      userId: report.userId,
      authorityScore: authority,
      confidenceScore: report.confidenceScore,
      imageUrl: report.imageUrl,
      dismissReason: report.dismissReason,
      adminReply: report.adminReply,
      reviewedAt: report.reviewedAt,
      isEmergency: report.isEmergency,
      lastUpdatedByUser: report.lastUpdatedByUser,
      observedAt: report.observedAt,
      incidentId: report.incidentId,
      adminReplies: report.adminReplies,
      pointsAwarded: report.pointsAwarded,
      incidentReviewStatus: report.incidentReviewStatus,
      hasAdminUpdates: report.hasAdminUpdates,
      reportType: report.reportType,
      rootReportId: report.rootReportId,
      conditionChange: report.conditionChange,
      originalSubmission: report.originalSubmission,
      photoSubmittedAt: report.photoSubmittedAt,
      rewardCorrection: report.rewardCorrection,
      followupCount: report.followupCount,
    );

    return RiskEngine.calculateLiveConfidenceBreakdown(
      report: effectiveReport,
      allRoads: _roads,
      pendingReports: _reports,
      weatherState: SimulatedWeatherService.instance.currentState,
      currentTime: DateTime.now(),
    );
  }

  Future<void> submitFeedback(Map<String, dynamic> data) async {
    if (AppEnvironment.sparkCommunicationsEnabled) {
      if (data['imageUrl'] != null && !AppEnvironment.sparkMediaEnabled)
        throw StateError('Screenshot support is not enabled in this build.');
      await CommunicationService.command('feedback-submit', {
        'category': data['category'],
        'rating': data['rating'],
        'comments': data['comments'],
        'allowFollowUp': data['allowFollowUp'] == true,
        if (data['imageUrl'] != null) 'imageUrl': data['imageUrl'],
      });
      return;
    }
    try {
      final docRef = await FirebaseFirestore.instance
          .collection('feedbacks')
          .add(data);
      debugPrint(
        '[AppStateService] Feedback submitted successfully: ${docRef.id}',
      );
    } catch (e) {
      debugPrint('Feedback save failed (${privacySafeErrorCode(e)}).');
      rethrow;
    }
  }
}
