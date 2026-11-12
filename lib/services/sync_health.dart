enum SyncCondition { connecting, live, cached, failed }

class SyncHealth {
  final DateTime Function() _now;
  SyncHealth({DateTime Function()? now}) : _now = now ?? DateTime.now;

  // Server timestamps can arrive a few seconds ahead of a phone's clock.
  // This does not extend the age limit for saved risk computations.
  static const allowedClockSkew = Duration(seconds: 30);
  static const riskMaxAge = Duration(minutes: 5);
  final Map<String, SyncCondition> channels = {
    'roads': SyncCondition.connecting,
    'reports': SyncCondition.connecting,
    'ownReports': SyncCondition.connecting,
    'alerts': SyncCondition.connecting,
    'risk': SyncCondition.connecting,
  };
  DateTime? lastRoadSync;
  DateTime? lastRiskCompute;
  bool get riskFresh {
    final computed = lastRiskCompute;
    if (computed == null) return false;
    final age = _now().difference(computed);
    return age >= -allowedClockSkew && age < riskMaxAge;
  }

  List<String> get affectedFeeds => [
    for (final entry in channels.entries)
      if (entry.value != SyncCondition.live ||
          entry.key == 'risk' && !riskFresh)
        switch (entry.key) {
          'roads' => 'Road conditions',
          'reports' => 'Resident reports',
          'ownReports' => 'Your report updates',
          'alerts' => 'Area alerts',
          'risk' => 'Risk estimates',
          _ => entry.key,
        },
  ];
  bool get roadsLive => channels['roads'] == SyncCondition.live;
  bool get healthy =>
      channels.values.every((s) => s == SyncCondition.live) && riskFresh;
  bool get failed => channels.values.contains(SyncCondition.failed);
  void update(String channel, {required bool fromCache, DateTime? now}) {
    channels[channel] = fromCache ? SyncCondition.cached : SyncCondition.live;
    if (channel == 'roads' && !fromCache) lastRoadSync = now ?? _now();
  }

  void fail(String channel) {
    channels[channel] = SyncCondition.failed;
  }

  void reset({bool clearHistory = false}) {
    for (final key in channels.keys) {
      channels[key] = SyncCondition.connecting;
    }
    lastRiskCompute = null;
    if (clearHistory) lastRoadSync = null;
  }
}
