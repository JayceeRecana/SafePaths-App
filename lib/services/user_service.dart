import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_state_service.dart';
import 'notification_service.dart';

enum UserRole { user, admin }

class UserService {
  static const String _roleKey = 'user_role';

  static Future<String> getUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }
    return user.uid;
  }

  static Future<void> touchSession({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force ||
        prefs.getString('session_uid') != uid ||
        now - (prefs.getInt('session_last_activity') ?? 0) >= 30000) {
      await prefs.setString('session_uid', uid);
      await prefs.setInt('session_last_activity', now);
    }
  }

  static Future<DateTime?> lastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('session_uid') !=
        FirebaseAuth.instance.currentUser?.uid)
      return null;
    final ms = prefs.getInt('session_last_activity');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // Save user role locally for quick UI routing
  static Future<void> saveUserRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.toString());
  }

  // Get locally cached user role
  static Future<UserRole?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleString = prefs.getString(_roleKey);
    if (roleString == null) return null;
    return UserRole.values.firstWhere(
      (e) => e.toString() == roleString,
      orElse: () => UserRole.user,
    );
  }

  static Future<void> setLoggedIn(bool isLoggedIn) async {
    if (isLoggedIn) await touchSession(force: true);
  }

  static Future<bool> isLoggedIn() async {
    return FirebaseAuth.instance.currentUser != null;
  }

  static Future<void> clearUserData() async {
    try {
      await NotificationService.instance.clearDeviceToken();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    await AppStateService.instance.clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove('session_uid');
    await prefs.remove('session_last_activity');
  }
}
