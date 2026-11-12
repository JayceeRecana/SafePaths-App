import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../config/risk_config.dart';
import '../config/app_environment.dart';
import 'road_incident_service.dart';

enum WeatherState {
  clear,
  partlyCloudy,
  lightRain,
  moderateRain,
  heavyRain,
  typhoon,
}

abstract class WeatherService {
  Future<WeatherState> getCurrentWeather();
  Stream<WeatherState> get onWeatherChanged;
}

class WeatherNotifier extends ValueNotifier<WeatherState> {
  WeatherNotifier(super.value);
  void forceNotify() => notifyListeners();
}

class SimulatedWeatherService implements WeatherService {
  final bool _coreMode;
  bool _coreAvailable = false;
  bool _coreFromCache = true;
  List<Map<String, dynamic>> _coreForecast = [];
  SimulatedWeatherService.forTesting({bool coreMode = true})
    : _coreMode = coreMode;
  WeatherState _currentState = WeatherState.clear;
  final _weatherStreamController = WeatherNotifier(WeatherState.clear);

  bool isOverrideMode = false;
  double precipitationIntensity = 0.0;
  double windSpeed = 0.0;
  double temperature = 32.0;
  double humidity = 60.0;

  Timer? _pollingTimer;
  Timer? _expiryCheckTimer;
  DateTime? _overrideExpiresAt;
  DateTime? lastSuccessfulFetch;
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;

  double get weatherMultiplier =>
      RiskConfig.getWeatherMultiplier(_currentState);

  bool get isDataStale {
    if (_coreMode) {
      if (!_coreAvailable || _coreFromCache) return true;
      final now = DateTime.now();
      if (isOverrideMode)
        return _overrideExpiresAt == null || !now.isBefore(_overrideExpiresAt!);
      final age = lastSuccessfulFetch == null
          ? null
          : now.difference(lastSuccessfulFetch!);
      return age == null ||
          age < const Duration(minutes: -1) ||
          age > const Duration(minutes: 30);
    }
    if (isOverrideMode) return false;
    if (lastSuccessfulFetch == null) return true;
    return DateTime.now().difference(lastSuccessfulFetch!).inMinutes > 30;
  }

  // Valenzuela City, Philippines as default location for weather polling

  SimulatedWeatherService._internal()
    : _coreMode = AppEnvironment.sparkCoreEnabled {
    if (AppEnvironment.isFieldTest && !_coreMode) {
      isOverrideMode = true;
    }
    _initFirestoreListener();
  }
  static final SimulatedWeatherService instance =
      SimulatedWeatherService._internal();

  WeatherState get currentState {
    if (isOverrideMode &&
        _overrideExpiresAt != null &&
        DateTime.now().isAfter(_overrideExpiresAt!)) {
      // Lazy expiry fallback: ignore expired override and trigger live fetch
      isOverrideMode = false;
      if (_coreMode) _coreAvailable = false;
      _overrideExpiresAt = null;
      _expiryCheckTimer?.cancel();
      _fetchLiveWeather();
    }
    return _currentState;
  }

  void _startExpiryCheckTimer() {
    _expiryCheckTimer?.cancel();
    _expiryCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isOverrideMode &&
          _overrideExpiresAt != null &&
          DateTime.now().isAfter(_overrideExpiresAt!)) {
        debugPrint(
          '[WeatherService] Periodic timer detected expired drill override. Resetting to live weather.',
        );
        _expiryCheckTimer?.cancel();
        isOverrideMode = false;
        if (_coreMode) _coreAvailable = false;
        _weatherStreamController.forceNotify();
        _overrideExpiresAt = null;
        _fetchLiveWeather();
      }
    });
  }

  Future<void> disconnectAccount() async {
    await _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _expiryCheckTimer?.cancel();
    lastSuccessfulFetch = null;
    _coreAvailable = false;
    _coreFromCache = true;
  }

  Future<void> reconnectAccount() async {
    await disconnectAccount();
    _initFirestoreListener();
  }

  void _initFirestoreListener() {
    try {
      if (Firebase.apps.isNotEmpty) {
        _firestoreSubscription = FirebaseFirestore.instance
            .collection('system')
            .doc('weather')
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (_coreMode) {
                  applyCoreWeather(
                    snapshot.data() ?? {},
                    fromCache: snapshot.metadata.isFromCache,
                  );
                  return;
                }
                if (snapshot.exists) {
                  final data = snapshot.data();
                  if (data != null) {
                    final firestoreOverride =
                        data['isOverrideMode'] as bool? ?? false;

                    if (firestoreOverride) {
                      final expiresTimestamp =
                          data['overrideExpiresAt'] as Timestamp?;
                      _overrideExpiresAt = AppEnvironment.isFieldTest
                          ? null
                          : expiresTimestamp?.toDate();
                      if (_overrideExpiresAt != null &&
                          DateTime.now().isAfter(_overrideExpiresAt!)) {
                        // Admin drill override expired automatically after 30 minutes
                        isOverrideMode = false;
                        _overrideExpiresAt = null;
                        _expiryCheckTimer?.cancel();
                        _fetchLiveWeather();
                        return;
                      }

                      // Admin Drill / Simulation mode is actively turned on
                      _pollingTimer?.cancel();
                      final stateStr =
                          data['currentState'] as String? ?? 'clear';
                      final state = _parseWeatherState(stateStr);

                      precipitationIntensity =
                          (data['precipitationIntensity'] as num?)
                              ?.toDouble() ??
                          0.0;
                      windSpeed =
                          (data['windSpeed'] as num?)?.toDouble() ?? 0.0;
                      temperature =
                          (data['temperature'] as num?)?.toDouble() ?? 32.0;
                      humidity = (data['humidity'] as num?)?.toDouble() ?? 60.0;

                      isOverrideMode = true;
                      _updateLocalState(state);
                      _weatherStreamController.forceNotify();
                      _startExpiryCheckTimer();
                    } else {
                      if (!AppEnvironment.isFieldTest) {
                        isOverrideMode = false;
                        _overrideExpiresAt = null;
                        lastSuccessfulFetch =
                            (data['lastFetched'] as Timestamp?)?.toDate();
                        precipitationIntensity =
                            (data['precipitationIntensity'] as num?)
                                ?.toDouble() ??
                            0;
                        windSpeed =
                            (data['windSpeed'] as num?)?.toDouble() ?? 0;
                        temperature =
                            (data['temperature'] as num?)?.toDouble() ?? 0;
                        humidity = (data['humidity'] as num?)?.toDouble() ?? 0;
                        _updateLocalState(
                          _parseWeatherState(
                            data['currentState'] as String? ?? 'clear',
                          ),
                        );
                        _weatherStreamController.forceNotify();
                        return;
                      }
                      if (AppEnvironment.isFieldTest) {
                        isOverrideMode = true;
                        _overrideExpiresAt = null;
                        precipitationIntensity = 0;
                        windSpeed = 0;
                        _updateLocalState(WeatherState.clear);
                        return;
                      }
                    }
                  }
                }
              },
              onError: (e) {
                lastSuccessfulFetch = null;
                _coreAvailable = false;
                _weatherStreamController.forceNotify();
                debugPrint('[WeatherService] Firestore listener error: $e');
              },
            );
      }
    } catch (e) {
      debugPrint(
        '[WeatherService] Failed to initialize Firestore listener: $e',
      );
    }
  }

  /// Applies verified server metadata; cached or stale values remain visibly unavailable.
  void applyCoreWeather(Map<String, dynamic> data, {bool fromCache = false}) {
    DateTime? date(Object? value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
    _coreFromCache = fromCache;
    _overrideExpiresAt = date(data['overrideExpiresAt']);
    isOverrideMode = data['isOverrideMode'] == true;
    lastSuccessfulFetch = date(data['observedAt']);
    final state = data['currentState'];
    _coreAvailable =
        data['available'] == true &&
        data['studyArea'] == AppEnvironment.area.id &&
        WeatherState.values.any((s) => s.name == state) &&
        (isOverrideMode
            ? data['source'] == 'admin-drill'
            : data['source'] == 'open-meteo');
    for (final entry in [
      'precipitationIntensity',
      'windSpeed',
      'temperature',
      'humidity',
    ]) {
      if (data[entry] is! num || !(data[entry] as num).isFinite)
        _coreAvailable = false;
    }
    if (_coreAvailable) {
      precipitationIntensity = (data['precipitationIntensity'] as num)
          .toDouble();
      windSpeed = (data['windSpeed'] as num).toDouble();
      temperature = (data['temperature'] as num).toDouble();
      humidity = (data['humidity'] as num).toDouble();
      _updateLocalState(_parseWeatherState(state as String));
    }
    _coreForecast = [];
    for (final row
        in data['forecast'] is List ? data['forecast'] as List : []) {
      if (row is! Map) continue;
      final time = date(row['time']),
          temp = row['temperature'],
          chance = row['rainChance'];
      if (time == null ||
          temp is! num ||
          !temp.isFinite ||
          chance is! num ||
          !chance.isFinite ||
          !WeatherState.values.any((s) => s.name == row['state']))
        continue;
      _coreForecast.add({
        'time': time,
        'temperature': temp.toDouble(),
        'rainChance': chance.toDouble(),
        'state': _parseWeatherState(row['state'] as String),
      });
    }
    if (isOverrideMode) _startExpiryCheckTimer();
    _weatherStreamController.forceNotify();
  }

  void _updateLocalState(WeatherState state) {
    if (_currentState != state) {
      _currentState = state;
      _weatherStreamController.value = state;
      debugPrint(
        '[WeatherService] Local weather state updated to: $_currentState (Rain: $precipitationIntensity mm/h)',
      );
    }
  }

  WeatherState _parseWeatherState(String stateStr) {
    switch (stateStr) {
      case 'clear':
        return WeatherState.clear;
      case 'partlyCloudy':
        return WeatherState.partlyCloudy;
      case 'lightRain':
        return WeatherState.lightRain;
      case 'moderateRain':
        return WeatherState.moderateRain;
      case 'heavyRain':
        return WeatherState.heavyRain;
      case 'typhoon':
        return WeatherState.typhoon;
      default:
        return WeatherState.clear;
    }
  }

  String _weatherStateToString(WeatherState state) {
    switch (state) {
      case WeatherState.clear:
        return 'clear';
      case WeatherState.partlyCloudy:
        return 'partlyCloudy';
      case WeatherState.lightRain:
        return 'lightRain';
      case WeatherState.moderateRain:
        return 'moderateRain';
      case WeatherState.heavyRain:
        return 'heavyRain';
      case WeatherState.typhoon:
        return 'typhoon';
    }
  }

  Future<void> _fetchLiveWeather() async {
    if (Firebase.apps.isEmpty || AppEnvironment.isFieldTest && !_coreMode)
      return;
    try {
      await FirebaseFirestore.instance
          .collection('system')
          .doc('weather')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Weather refresh unavailable: $e');
    }
  }

  @override
  Future<WeatherState> getCurrentWeather() async {
    return currentState;
  }

  Future<void> fetchLiveWeather() => _fetchLiveWeather();

  @override
  Stream<WeatherState> get onWeatherChanged {
    throw UnimplementedError('Use listenable instead');
  }

  ValueNotifier<WeatherState> get listenable => _weatherStreamController;

  Map<String, double> _getMockStatsForState(WeatherState state) {
    switch (state) {
      case WeatherState.clear:
        return {
          'precipitationIntensity': 0.0,
          'windSpeed': 1.5,
          'temperature': 33.0,
          'humidity': 58.0,
        };
      case WeatherState.partlyCloudy:
        return {
          'precipitationIntensity': 0.0,
          'windSpeed': 2.5,
          'temperature': 31.0,
          'humidity': 65.0,
        };
      case WeatherState.lightRain:
        return {
          'precipitationIntensity': 2.2,
          'windSpeed': 4.0,
          'temperature': 30.5,
          'humidity': 75.0,
        };
      case WeatherState.moderateRain:
        return {
          'precipitationIntensity': 7.5,
          'windSpeed': 8.5,
          'temperature': 28.0,
          'humidity': 85.0,
        };
      case WeatherState.heavyRain:
        return {
          'precipitationIntensity': 22.0,
          'windSpeed': 14.0,
          'temperature': 26.5,
          'humidity': 92.0,
        };
      case WeatherState.typhoon:
        return {
          'precipitationIntensity': 65.0,
          'windSpeed': 35.0,
          'temperature': 25.0,
          'humidity': 98.0,
        };
    }
  }

  Future<void> setWeather(WeatherState newState) async {
    if (_coreMode) {
      await RoadIncidentService.coreOperations.run('weather-override', {
        'enable': true,
        'state': newState.name,
        'minutes': 30,
      });
      return;
    }
    isOverrideMode = true;
    final mockStats = _getMockStatsForState(newState);
    precipitationIntensity = mockStats['precipitationIntensity']!;
    windSpeed = mockStats['windSpeed']!;
    temperature = mockStats['temperature']!;
    humidity = mockStats['humidity']!;
    _updateLocalState(newState);

    if (Firebase.apps.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('system')
          .doc('weather')
          .set({
            'currentState': _weatherStateToString(newState),
            'isOverrideMode': true,
            'overrideExpiresAt': AppEnvironment.isFieldTest
                ? FieldValue.delete()
                : Timestamp.fromDate(
                    DateTime.now().add(const Duration(minutes: 30)),
                  ),
            'precipitationIntensity': precipitationIntensity,
            'windSpeed': windSpeed,
            'temperature': temperature,
            'humidity': humidity,
            'lastFetched': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .catchError((e) {
            debugPrint(
              '[WeatherService] Failed to set override weather in Firestore: $e',
            );
          });
    }
  }

  Future<void> toggleOverride(bool enable) async {
    if (_coreMode) {
      await RoadIncidentService.coreOperations.run('weather-override', {
        'enable': enable,
        if (enable) 'state': _currentState.name,
        if (enable) 'minutes': 30,
      });
      return;
    }
    if (AppEnvironment.isFieldTest && !enable) {
      setWeather(WeatherState.clear);
      return;
    }
    isOverrideMode = enable;
    _weatherStreamController.forceNotify();

    final mockStats = _getMockStatsForState(_currentState);
    if (enable) {
      precipitationIntensity = mockStats['precipitationIntensity']!;
      windSpeed = mockStats['windSpeed']!;
      temperature = mockStats['temperature']!;
      humidity = mockStats['humidity']!;
    }

    if (Firebase.apps.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('system')
          .doc('weather')
          .set({
            'isOverrideMode': enable,
            if (enable)
              'overrideExpiresAt': AppEnvironment.isFieldTest
                  ? FieldValue.delete()
                  : Timestamp.fromDate(
                      DateTime.now().add(const Duration(minutes: 30)),
                    ),
            if (enable) 'precipitationIntensity': precipitationIntensity,
            if (enable) 'windSpeed': windSpeed,
            if (enable) 'temperature': temperature,
            if (enable) 'humidity': humidity,
            'lastFetched': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .then((_) {
            if (!enable) {
              _fetchLiveWeather();
            }
          })
          .catchError((e) {
            debugPrint(
              '[WeatherService] Failed to toggle override in Firestore: $e',
            );
            if (!enable) {
              _fetchLiveWeather();
            }
          });
    } else {
      if (!enable) {
        _fetchLiveWeather();
      }
    }
  }

  List<Map<String, dynamic>> getHourlyForecast() {
    if (_coreMode)
      return isDataStale || isOverrideMode
          ? []
          : _coreForecast
                .where(
                  (r) => (r['time'] as DateTime).isAfter(
                    DateTime.now().subtract(const Duration(hours: 1)),
                  ),
                )
                .toList();
    final now = DateTime.now();
    final List<Map<String, dynamic>> forecast = [];

    double baseTemp = temperature;
    double baseRainChance = _currentState == WeatherState.clear
        ? 10.0
        : _currentState == WeatherState.partlyCloudy
        ? 20.0
        : _currentState == WeatherState.lightRain
        ? 40.0
        : _currentState == WeatherState.moderateRain
        ? 70.0
        : _currentState == WeatherState.heavyRain
        ? 90.0
        : 98.0;

    for (int i = 0; i < 8; i++) {
      final hourTime = now.add(Duration(hours: i));

      double hourTemp = baseTemp + (i * 0.2) * (i % 2 == 0 ? 1 : -1);
      double hourRainChance =
          baseRainChance + (i * 2.0) * (i % 3 == 0 ? -1 : 1);
      hourRainChance = hourRainChance.clamp(0.0, 100.0);

      WeatherState hourState = _currentState;
      if (i > 4 && _currentState != WeatherState.clear) {
        if (_currentState == WeatherState.typhoon) {
          hourState = WeatherState.heavyRain;
        } else if (_currentState == WeatherState.heavyRain) {
          hourState = WeatherState.moderateRain;
        } else if (_currentState == WeatherState.moderateRain) {
          hourState = WeatherState.lightRain;
        } else if (_currentState == WeatherState.lightRain) {
          hourState = WeatherState.clear;
        }
      }

      forecast.add({
        'time': hourTime,
        'temperature': hourTemp,
        'rainChance': hourRainChance,
        'state': hourState,
      });
    }
    return forecast;
  }

  String getWeatherDescription(WeatherState state, {DateTime? time}) {
    if (_coreMode && isDataStale) return 'Weather unavailable';
    if (_coreMode && state == WeatherState.typhoon)
      return isOverrideMode
          ? 'Severe weather drill'
          : 'Severe weather estimate';
    switch (state) {
      case WeatherState.clear:
        return 'Clear';
      case WeatherState.partlyCloudy:
        return 'Cloudy';
      case WeatherState.lightRain:
        return 'Light Rain';
      case WeatherState.moderateRain:
        return 'Mod. Rain';
      case WeatherState.heavyRain:
        return 'Heavy Rain';
      case WeatherState.typhoon:
        return 'Typhoon';
    }
  }

  IconData getWeatherIcon(WeatherState state, {DateTime? time}) {
    final t = time ?? DateTime.now();
    final bool isNight = t.hour >= 18 || t.hour < 6;

    switch (state) {
      case WeatherState.clear:
        return isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded;
      case WeatherState.partlyCloudy:
        return isNight ? Icons.bedtime_outlined : Icons.cloud_queue_rounded;
      case WeatherState.lightRain:
        return Icons.water_drop_outlined;
      case WeatherState.moderateRain:
        return Icons.cloudy_snowing;
      case WeatherState.heavyRain:
        return Icons.thunderstorm_outlined;
      case WeatherState.typhoon:
        return Icons.cyclone_rounded;
    }
  }

  Color getWeatherColor(WeatherState state, {DateTime? time}) {
    final t = time ?? DateTime.now();
    final bool isNight = t.hour >= 18 || t.hour < 6;

    switch (state) {
      case WeatherState.clear:
        return isNight
            ? const Color(0xFF5C6BC0)
            : Colors.orange; // Indigo/violet at night, bright orange by day
      case WeatherState.partlyCloudy:
        return isNight ? const Color(0xFF78909C) : Colors.blueGrey;
      case WeatherState.lightRain:
        return Colors.lightBlue;
      case WeatherState.moderateRain:
        return Colors.blue;
      case WeatherState.heavyRain:
        return Colors.indigo;
      case WeatherState.typhoon:
        return Colors.deepPurple;
    }
  }

  void dispose() {
    _expiryCheckTimer?.cancel();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _weatherStreamController.dispose();
  }
}
