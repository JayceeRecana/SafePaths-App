import 'package:shared_preferences/shared_preferences.dart';

class AccountSecurity {
  static const loginFailureLimit = 5;
  static const loginCooldown = Duration(minutes: 1);
  static const adminIdleLimit = Duration(minutes: 15);
  static const residentIdleLimit = Duration(minutes: 30);
  static const recoveryMessage =
      'If an account uses this email, password reset instructions will be sent. Check your inbox and spam folder.';
  static bool validEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
  static bool sessionExpired({
    required DateTime now,
    required DateTime? lastActivity,
    required bool isAdmin,
    bool navigating = false,
  }) {
    if (!isAdmin && navigating) return false;
    if (lastActivity == null ||
        lastActivity.isAfter(now.add(const Duration(minutes: 1))))
      return true;
    return now.difference(lastActivity) >=
        (isAdmin ? adminIdleLimit : residentIdleLimit);
  }

  static String loginError(String code) => switch (code) {
    'too-many-requests' =>
      'Too many sign-in attempts. Please wait and try again later.',
    'network-request-failed' =>
      'Cannot connect. Check your internet connection and try again.',
    'user-disabled' =>
      'This account is unavailable. Contact your administrator.',
    _ => 'Unable to sign in. Check your email and password.',
  };
  static Future<int> remainingLoginSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt('login_blocked_until') ?? 0;
    final ms = until - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  static Future<void> failedLogin({bool providerLimited = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt('login_failures') ?? 0) + 1;
    if (providerLimited || count >= loginFailureLimit) {
      await prefs.setInt(
        'login_blocked_until',
        DateTime.now().add(loginCooldown).millisecondsSinceEpoch,
      );
      await prefs.setInt('login_failures', 0);
    } else {
      await prefs.setInt('login_failures', count);
    }
  }

  static Future<void> clearFailures() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('login_failures');
    await prefs.remove('login_blocked_until');
  }
}

/// An active resident trip counts as activity so an idle timeout cannot interrupt guidance.
class SessionActivity {
  static bool navigating = false;
  static bool authenticationInProgress = false;
}
