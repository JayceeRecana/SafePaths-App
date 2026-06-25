import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum WeatherState {
  clear,
  lightRain,
  moderateRain,
  heavyRain,
  typhoon,
}

abstract class WeatherService {
  Future<WeatherState> getCurrentWeather();
  Stream<WeatherState> get onWeatherChanged;
}

class SimulatedWeatherService implements WeatherService {
  WeatherState _currentState = WeatherState.clear;
  final _weatherStreamController = ValueNotifier<WeatherState>(WeatherState.clear);
  
  bool isOverrideMode = false;
  Timer? _pollingTimer;
  DateTime? lastSuccessfulFetch;

  bool get isDataStale {
    if (isOverrideMode) return false;
    if (lastSuccessfulFetch == null) return true;
    return DateTime.now().difference(lastSuccessfulFetch!).inMinutes > 30;
  }

  static const String _tomorrowIoApiKey = String.fromEnvironment('TOMORROW_API_KEY', defaultValue: 'BWSwPD8cTYH7kGfeJQQi6gVTMNwP4HRr');
  // Valenzuela City, Philippines as default location for weather polling
  static const double _lat = 14.6761;
  static const double _lon = 120.9842;

  SimulatedWeatherService._internal() {
    _startPolling();
  }
  static final SimulatedWeatherService instance = SimulatedWeatherService._internal();

  WeatherState get currentState => _currentState;

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
      final url = Uri.parse(
        'https://api.tomorrow.io/v4/weather/realtime?location=$_lat,$_lon&apikey=$_tomorrowIoApiKey'
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['data']['values'];
        
        final precipitationIntensity = (values['precipitationIntensity'] as num?)?.toDouble() ?? 0.0;
        final windSpeed = (values['windSpeed'] as num?)?.toDouble() ?? 0.0;
        
        WeatherState newState = WeatherState.clear;
        
        if (windSpeed > 30.0 || precipitationIntensity > 50.0) {
          newState = WeatherState.typhoon;
        } else if (precipitationIntensity > 15.0) {
          newState = WeatherState.heavyRain;
        } else if (precipitationIntensity > 5.0) {
          newState = WeatherState.moderateRain;
        } else if (precipitationIntensity > 0.0) {
          newState = WeatherState.lightRain;
        }

        if (!isOverrideMode && _currentState != newState) {
          _currentState = newState;
          _weatherStreamController.value = newState;
          debugPrint('[WeatherService] Live weather updated: $_currentState');
        }
        lastSuccessfulFetch = DateTime.now();
      } else {
        debugPrint('[WeatherService] Non-200 response: ${response.statusCode}');
        // We do not update lastSuccessfulFetch, so it will eventually become stale
      }
    } catch (e) {
      debugPrint('[WeatherService] Error fetching weather: $e');
      // No lastSuccessfulFetch update here either
    } finally {
      // Always schedule the next poll whether the fetch succeeded or failed
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

  void setWeather(WeatherState newState) {
    // Calling this manually implicitly enables override mode
    isOverrideMode = true;
    if (_currentState != newState) {
      _currentState = newState;
      _weatherStreamController.value = newState;
      debugPrint('[WeatherService] Admin Override weather set: $_currentState');
    }
  }

  void toggleOverride(bool enable) {
    isOverrideMode = enable;
    if (!enable) {
      // If we turned off override, immediately fetch live weather
      _fetchLiveWeather();
    }
  }

  String getWeatherDescription(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return 'Clear';
      case WeatherState.lightRain: return 'Light Rain';
      case WeatherState.moderateRain: return 'Moderate Rain';
      case WeatherState.heavyRain: return 'Heavy Rain';
      case WeatherState.typhoon: return 'Typhoon';
    }
  }

  IconData getWeatherIcon(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return Icons.wb_sunny_rounded;
      case WeatherState.lightRain: return Icons.water_drop_outlined;
      case WeatherState.moderateRain: return Icons.cloudy_snowing;
      case WeatherState.heavyRain: return Icons.thunderstorm_outlined;
      case WeatherState.typhoon: return Icons.cyclone_rounded;
    }
  }
  
  Color getWeatherColor(WeatherState state) {
    switch (state) {
      case WeatherState.clear: return Colors.orange;
      case WeatherState.lightRain: return Colors.lightBlue;
      case WeatherState.moderateRain: return Colors.blue;
      case WeatherState.heavyRain: return Colors.indigo;
      case WeatherState.typhoon: return Colors.deepPurple;
    }
  }
}
