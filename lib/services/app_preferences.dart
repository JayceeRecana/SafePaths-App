import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences();
  static final instance = AppPreferences();
  SharedPreferences? _storage;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    try {
      _storage = await SharedPreferences.getInstance();
      _locale = Locale(
        _storage!.getString('app.language') == 'fil' ? 'fil' : 'en',
      );
      _themeMode = switch (_storage!.getString('app.theme')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Preference failures must not prevent access to safety information.
    }
  }

  Future<bool> setLanguage(String language) async {
    if (language != 'en' && language != 'fil') {
      throw ArgumentError.value(language);
    }
    _locale = Locale(language);
    notifyListeners();
    try {
      _storage ??= await SharedPreferences.getInstance();
      return await _storage!.setString('app.language', language);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      _storage ??= await SharedPreferences.getInstance();
      return await _storage!.setString('app.theme', mode.name);
    } catch (_) {
      return false;
    }
  }
}
