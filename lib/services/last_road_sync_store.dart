import 'package:shared_preferences/shared_preferences.dart';

/// Only a synchronization timestamp is stored here. Road data stays in the
/// Firestore cache, which may be empty or evicted and is never a live guarantee.
class LastRoadSyncStore {
  final SharedPreferences preferences;
  final String scope;
  LastRoadSyncStore(this.preferences, this.scope);
  String get _key => 'roadSync.v1.$scope';

  DateTime? read({DateTime? now}) {
    final millis = preferences.getInt(_key);
    if (millis == null || millis <= 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    return time.isAfter(now ?? DateTime.now()) ? null : time;
  }

  Future<void> save(DateTime time) async {
    await preferences.setInt(_key, time.millisecondsSinceEpoch);
  }
}
