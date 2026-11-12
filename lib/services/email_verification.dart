import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class VerificationActions {
  String get email;
  Future<bool> refresh();
  Future<DateTime?> nextResendAt();
  Future<void> send();
}

class FirebaseVerificationActions implements VerificationActions {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'signed-out';
  String get _key => 'verification_resend_$_uid';
  @override
  String get email => FirebaseAuth.instance.currentUser?.email ?? '';
  @override
  Future<DateTime?> nextResendAt() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> send() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    final next = await nextResendAt();
    if (next != null && next.isAfter(DateTime.now()))
      throw StateError('Please wait a minute before requesting another email.');
    // Reserve the cooldown before sending, including ambiguous network outcomes.
    await (await SharedPreferences.getInstance()).setInt(
      _key,
      DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    await user.sendEmailVerification().timeout(const Duration(seconds: 12));
  }

  @override
  Future<bool> refresh() async {
    await FirebaseAuth.instance.currentUser?.reload().timeout(
      const Duration(seconds: 10),
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return false;
    await user.getIdToken(true).timeout(const Duration(seconds: 10));
    return true;
  }
}
