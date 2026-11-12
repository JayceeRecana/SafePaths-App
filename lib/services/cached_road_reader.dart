import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/road_status.dart';
import 'account_security.dart';
import 'last_road_sync_store.dart';
import 'user_service.dart';

class CachedRoadSnapshot {
  final List<RoadStatus> roads;
  final DateTime? lastSync;
  const CachedRoadSnapshot(this.roads, this.lastSync);
}

/// Does not refresh credentials, infer an admin role, initialize live feeds,
/// write a document, or provide routing/reporting actions.
class CachedRoadReader {
  static bool isNetworkFailure(Object error) =>
      error is TimeoutException ||
      error is FirebaseException &&
          const [
            'unavailable',
            'deadline-exceeded',
            'network-request-failed',
          ].contains(error.code);

  static bool eligible({
    required bool signedIn,
    required bool anonymous,
    required bool verified,
    required DateTime now,
    required DateTime? lastActivity,
    required bool isAdmin,
  }) =>
      signedIn &&
      !anonymous &&
      verified &&
      !AccountSecurity.sessionExpired(
        now: now,
        lastActivity: lastActivity,
        isAdmin: isAdmin,
      );

  static Future<bool> sessionAllowed() async {
    if (Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final lastActivity = await UserService.lastActivity();
    final role = await UserService.getUserRole();
    return FirebaseAuth.instance.currentUser?.uid == user.uid &&
        eligible(
          signedIn: true,
          anonymous: user.isAnonymous,
          verified: user.emailVerified,
          now: DateTime.now(),
          lastActivity: lastActivity,
          // Unknown roles take the shorter timeout; cached roles grant no admin UI.
          isAdmin: role != UserRole.user,
        );
  }

  static Future<CachedRoadSnapshot> load() async {
    if (!await sessionAllowed()) throw StateError('Account access required.');
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('roads')
        .get(const GetOptions(source: Source.cache))
        .timeout(const Duration(seconds: 3));
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !await sessionAllowed()) {
      throw StateError('Account access required.');
    }
    final prefs = await SharedPreferences.getInstance();
    final last = LastRoadSyncStore(
      prefs,
      Firebase.app().options.projectId,
    ).read();
    return CachedRoadSnapshot(
      snapshot.docs
          .map((doc) => RoadStatus.fromJson({...doc.data(), 'id': doc.id}))
          .toList(),
      last,
    );
  }
}
