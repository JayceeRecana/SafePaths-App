import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { user, admin }

class UserService {
  static const String _roleKey = 'user_role';
  static const String _isLoggedInKey = 'is_logged_in';

  // Save user role
  static Future<void> saveUserRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.toString());
  }

  // Get user role
  static Future<UserRole?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleString = prefs.getString(_roleKey);
    if (roleString == null) return null;
    return UserRole.values.firstWhere(
      (e) => e.toString() == roleString,
      orElse: () => UserRole.user,
    );
  }

  // Save login state
  static Future<void> setLoggedIn(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, isLoggedIn);
  }

  // Get login state
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Clear user data (logout)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_isLoggedInKey);
  }
}
