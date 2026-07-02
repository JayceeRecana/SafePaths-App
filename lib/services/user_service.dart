import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

enum UserRole { user, admin }

class UserService {
  static const String _roleKey = 'user_role';

  // Get the true Firebase UID
  static Future<String> getUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return user.uid;
    }
    // Fallback: Login anonymously
    try {
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      return userCredential.user!.uid;
    } catch (e) {
      // Very worst-case fallback if network is entirely down on first launch
      debugPrint('[CRITICAL_WARNING] Firebase Anonymous Auth Failed. Using local offline fallback.');
      final prefs = await SharedPreferences.getInstance();
      String? offlineId = prefs.getString('offline_fallback_id');
      if (offlineId == null) {
        offlineId = 'anon_offline_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
        await prefs.setString('offline_fallback_id', offlineId);
      }
      return offlineId;
    }
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
    // Firebase Auth automatically manages session state.
    // We don't need to manually store boolean login state anymore.
  }

  static Future<bool> isLoggedIn() async {
    return FirebaseAuth.instance.currentUser != null;
  }

  static Future<void> clearUserData() async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
  }
}
