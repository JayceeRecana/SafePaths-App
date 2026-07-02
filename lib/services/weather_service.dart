import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

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
  WeatherState _currentState = WeatherState.clear;
  final _weatherStreamController = WeatherNotifier(WeatherState.clear);
  
  bool isOverrideMode = false;
  double precipitationIntensity = 0.0;
  double windSpeed = 0.0;
  double temperature = 32.0;
  double humidity = 60.0;
  
  Timer? _pollingTimer;
  DateTime? lastSuccessfulFetch;
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;

  double get weatherMultiplier {
    switch (_currentState) {
      case WeatherState.clear: return 0.0;
      case WeatherState.partlyCloudy: return 0.0;
      case WeatherState.lightRain: return 0.2;
      case WeatherState.moderateRain: return 0.4;
      case WeatherState.heavyRain: return 0.7;
      case WeatherState.typhoon: return 1.0;
    }
  }

  bool get isDataStale {
    if (isOverrideMode) return false;
    if (lastSuccessfulFetch == null) return true;
    return DateTime.now().difference(lastSuccessfulFetch!).inMinutes > 30;
  }

  static final String _tomorrowIoApiKey = dotenv.env['TOMORROW_API_KEY'] ?? '';
  // Valenzuela City, Philippines as default location for weather polling
  static const double _lat = 14.6761;
  static const double _lon = 120.9842;

  SimulatedWeatherService._internal() {
    _startPolling();
    _initFirestoreListener();
  }
  static final SimulatedWeatherService instance = SimulatedWeatherService._internal();

  WeatherState get currentState => _currentState;

  void _initFirestoreListener() {
    try {
      if (Firebase.apps.isNotEmpty) {
        _firestoreSubscription = FirebaseFirestore.instance
            .collection('system')
            .doc('weather')
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            if (data != null) {
              final firestoreOverride = data['isOverrideMode'] as bool? ?? false;
              final stateStr = data['currentState'] as String? ?? 'clear';
              final state = _parseWeatherState(stateStr);
              
              precipitationIntensity = (data['precipitationIntensity'] as num?)?.toDouble() ?? 0.0;
              windSpeed = (data['windSpeed'] as num?)?.toDouble() ?? 0.0;
              temperature = (data['temperature'] as num?)?.toDouble() ?? 32.0;
              humidity = (data['humidity'] as num?)?.toDouble() ?? 60.0;
              
              final oldOverride = isOverrideMode;
              isOverrideMode = firestoreOverride;
              _updateLocalState(state);
              if (oldOverride != isOverrideMode) {
                _weatherStreamController.forceNotify();
              }
            }
          }
        }, onError: (e) {
          debugPrint('[WeatherService] Firestore listener error: $e');
        });
      }
    } catch (e) {
      debugPrint('[WeatherService] Failed to initialize Firestore listener: $e');
    }
  }

  void _updateLocalState(WeatherState state) {
    if (_currentState != state) {
      _currentState = state;
      _weatherStreamController.value = state;
      debugPrint('[WeatherService] Local weather state updated to: $_currentState');
    }
  }

  WeatherState _parseWeatherState(String stateStr) {
    switch (stateStr) {
      case 'clear': return WeatherState.clear;
      case 'partlyCloudy': return WeatherState.partlyCloudy;
      case 'lightRain': return WeatherState.lightRain;
      case 'moderateRain': return WeatherState.moderateRain;
      case 'heavyRain': return WeatherState.heavyRain;
      case 'typhoon': return WeatherState.typhoon;
      default: return WeatherState.clear;
    }
  }

  String _weatherStateToString(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return 'clear';
      case WeatherState.partlyCloudy: return 'partlyCloudy';
      case WeatherState.lightRain: return 'lightRain';
      case WeatherState.moderateRain: return 'moderateRain';
      case WeatherState.heavyRain: return 'heavyRain';
      case WeatherState.typhoon: return 'typhoon';
    }
  }

  void _startPolling() {
    _fetchLiveWeather();
  }

  void _scheduleNextPoll() {
    _pollingTimer?.cancel();
    
    // Dynamic polling: 5 mins during severe weather, 15 mins otherwise
    int minutes = (_currentState == WeatherState.heavyRain || _currentState == WeatherState.typhoon) ? 5 : 15;
    
    _pollingTimer = Timer(Duration(minutes: minutes), () {
      _fetchLiveWeather();
    });
  }

  Future<void> _fetchLiveWeather() async {
    if (isOverrideMode) return;

    try {
      if (Firebase.apps.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('system').doc('weather').get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            final firestoreOverride = data['isOverrideMode'] as bool? ?? false;
            if (firestoreOverride) {
              isOverrideMode = true;
              final stateStr = data['currentState'] as String? ?? 'clear';
              final state = _parseWeatherState(stateStr);
              precipitationIntensity = (data['precipitationIntensity'] as num?)?.toDouble() ?? 0.0;
              windSpeed = (data['windSpeed'] as num?)?.toDouble() ?? 0.0;
              temperature = (data['temperature'] as num?)?.toDouble() ?? 32.0;
              humidity = (data['humidity'] as num?)?.toDouble() ?? 60.0;
              _updateLocalState(state);
              _scheduleNextPoll();
              return;
            }
            
            final lastFetchedTimestamp = data['lastFetched'] as Timestamp?;
            if (lastFetchedTimestamp != null) {
              final age = DateTime.now().difference(lastFetchedTimestamp.toDate()).inMinutes;
              if (age < 15) {
                final stateStr = data['currentState'] as String? ?? 'clear';
                final state = _parseWeatherState(stateStr);
                precipitationIntensity = (data['precipitationIntensity'] as num?)?.toDouble() ?? 0.0;
                windSpeed = (data['windSpeed'] as num?)?.toDouble() ?? 0.0;
                temperature = (data['temperature'] as num?)?.toDouble() ?? 32.0;
                humidity = (data['humidity'] as num?)?.toDouble() ?? 60.0;
                _updateLocalState(state);
                lastSuccessfulFetch = lastFetchedTimestamp.toDate();
                _scheduleNextPoll();
                return;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WeatherService] Firestore check failed, falling back to direct API: $e');
    }

    try {
      final url = Uri.parse(
        'https://api.tomorrow.io/v4/weather/realtime?location=$_lat,$_lon&apikey=$_tomorrowIoApiKey'
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['data']['values'];
        
        final double intensity = (values['precipitationIntensity'] as num?)?.toDouble() ?? 0.0;
        final double wind = (values['windSpeed'] as num?)?.toDouble() ?? 0.0;
        final int weatherCode = (values['weatherCode'] as num?)?.toInt() ?? 1000;
        
        precipitationIntensity = intensity;
        windSpeed = wind;
        temperature = (values['temperature'] as num?)?.toDouble() ?? 32.0;
        humidity = (values['humidity'] as num?)?.toDouble() ?? 60.0;
        
        WeatherState newState = WeatherState.clear;
        
        if (windSpeed > 30.0 || precipitationIntensity > 50.0) {
          newState = WeatherState.typhoon;
        } else if (precipitationIntensity > 15.0) {
          newState = WeatherState.heavyRain;
        } else if (precipitationIntensity > 5.0) {
          newState = WeatherState.moderateRain;
        } else if (precipitationIntensity > 0.0) {
          newState = WeatherState.lightRain;
        } else {
          // Check Tomorrow.io weather codes for clouds
          // 1100 = Mostly Clear, 1101 = Partly Cloudy, 1102 = Mostly Cloudy, 1001 = Cloudy
          if (weatherCode == 1101 || weatherCode == 1102 || weatherCode == 1001) {
            newState = WeatherState.partlyCloudy;
          } else {
            newState = WeatherState.clear;
          }
        }

        _updateLocalState(newState);
        lastSuccessfulFetch = DateTime.now();

        if (Firebase.apps.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('system').doc('weather').set({
              'currentState': _weatherStateToString(newState),
              'isOverrideMode': false,
              'precipitationIntensity': precipitationIntensity,
              'windSpeed': windSpeed,
              'temperature': temperature,
              'humidity': humidity,
              'lastFetched': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (writeError) {
            debugPrint('[WeatherService] Failed to write live weather to Firestore: $writeError');
          }
        }
      } else {
        debugPrint('[WeatherService] Non-200 response: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[WeatherService] Error fetching weather: $e');
    } finally {
      _scheduleNextPoll();
    }
  }

  @override
  Future<WeatherState> getCurrentWeather() async {
    return _currentState;
  }

  @override
  Stream<WeatherState> get onWeatherChanged {
    throw UnimplementedError('Use listenable instead');
  }
  
  ValueNotifier<WeatherState> get listenable => _weatherStreamController;

  Map<String, double> _getMockStatsForState(WeatherState state) {
    switch (state) {
      case WeatherState.clear:
        return {'precipitationIntensity': 0.0, 'windSpeed': 1.5, 'temperature': 33.0, 'humidity': 58.0};
      case WeatherState.partlyCloudy:
        return {'precipitationIntensity': 0.0, 'windSpeed': 2.5, 'temperature': 31.0, 'humidity': 65.0};
      case WeatherState.lightRain:
        return {'precipitationIntensity': 2.2, 'windSpeed': 4.0, 'temperature': 30.5, 'humidity': 75.0};
      case WeatherState.moderateRain:
        return {'precipitationIntensity': 7.5, 'windSpeed': 8.5, 'temperature': 28.0, 'humidity': 85.0};
      case WeatherState.heavyRain:
        return {'precipitationIntensity': 22.0, 'windSpeed': 14.0, 'temperature': 26.5, 'humidity': 92.0};
      case WeatherState.typhoon:
        return {'precipitationIntensity': 65.0, 'windSpeed': 35.0, 'temperature': 25.0, 'humidity': 98.0};
    }
  }

  void setWeather(WeatherState newState) {
    isOverrideMode = true;
    final mockStats = _getMockStatsForState(newState);
    precipitationIntensity = mockStats['precipitationIntensity']!;
    windSpeed = mockStats['windSpeed']!;
    temperature = mockStats['temperature']!;
    humidity = mockStats['humidity']!;
    _updateLocalState(newState);
    
    if (Firebase.apps.isNotEmpty) {
      FirebaseFirestore.instance.collection('system').doc('weather').set({
        'currentState': _weatherStateToString(newState),
        'isOverrideMode': true,
        'precipitationIntensity': precipitationIntensity,
        'windSpeed': windSpeed,
        'temperature': temperature,
        'humidity': humidity,
        'lastFetched': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('[WeatherService] Failed to set override weather in Firestore: $e');
      });
    }
  }

  void toggleOverride(bool enable) {
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
      FirebaseFirestore.instance.collection('system').doc('weather').set({
        'isOverrideMode': enable,
        if (enable) 'precipitationIntensity': precipitationIntensity,
        if (enable) 'windSpeed': windSpeed,
        if (enable) 'temperature': temperature,
        if (enable) 'humidity': humidity,
        'lastFetched': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).then((_) {
        if (!enable) {
          _fetchLiveWeather();
        }
      }).catchError((e) {
        debugPrint('[WeatherService] Failed to toggle override in Firestore: $e');
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
    final now = DateTime.now();
    final List<Map<String, dynamic>> forecast = [];
    
    double baseTemp = temperature;
    double baseRainChance = _currentState == WeatherState.clear ? 10.0 :
                            _currentState == WeatherState.lightRain ? 40.0 :
                            _currentState == WeatherState.moderateRain ? 70.0 : 95.0;

    for (int i = 0; i < 8; i++) {
      final hourTime = now.add(Duration(hours: i));
      
      double hourTemp = baseTemp + (i * 0.2) * (i % 2 == 0 ? 1 : -1);
      double hourRainChance = baseRainChance + (i * 2.0) * (i % 3 == 0 ? -1 : 1);
      hourRainChance = hourRainChance.clamp(0.0, 100.0);
      
      WeatherState hourState = _currentState;
      if (i > 4 && _currentState != WeatherState.clear) {
        if (_currentState == WeatherState.typhoon) hourState = WeatherState.heavyRain;
        else if (_currentState == WeatherState.heavyRain) hourState = WeatherState.moderateRain;
        else if (_currentState == WeatherState.moderateRain) hourState = WeatherState.lightRain;
        else if (_currentState == WeatherState.lightRain) hourState = WeatherState.clear;
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

  String getWeatherDescription(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return 'Clear';
      case WeatherState.partlyCloudy: return 'Partly Cloudy';
      case WeatherState.lightRain: return 'Light Rain';
      case WeatherState.moderateRain: return 'Moderate Rain';
      case WeatherState.heavyRain: return 'Heavy Rain';
      case WeatherState.typhoon: return 'Typhoon';
    }
  }

  IconData getWeatherIcon(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return Icons.wb_sunny_rounded;
      case WeatherState.partlyCloudy: return Icons.cloud_queue_rounded;
      case WeatherState.lightRain: return Icons.water_drop_outlined;
      case WeatherState.moderateRain: return Icons.cloudy_snowing;
      case WeatherState.heavyRain: return Icons.thunderstorm_outlined;
      case WeatherState.typhoon: return Icons.cyclone_rounded;
    }
  }
  
  Color getWeatherColor(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return Colors.orange;
      case WeatherState.partlyCloudy: return Colors.blueGrey;
      case WeatherState.lightRain: return Colors.lightBlue;
      case WeatherState.moderateRain: return Colors.blue;
      case WeatherState.heavyRain: return Colors.indigo;
      case WeatherState.typhoon: return Colors.deepPurple;
    }
  }
}
