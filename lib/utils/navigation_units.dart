/// Presentation only: route/provider calculations retain metres and seconds.
String navigationDistance(num metres) {
  if (!metres.isFinite || metres < 0) return 'Unknown distance';
  if (metres < 1000) return '${metres.round()} m';
  return '${(metres / 1000).toStringAsFixed(1)} km';
}

String navigationTime(num seconds) {
  if (!seconds.isFinite || seconds < 0) return 'Unknown time';
  final minutes = (seconds / 60).ceil();
  return '${minutes < 1 ? 1 : minutes} min';
}

String navigationRouteLabel(String summary) =>
    summary.toLowerCase().contains('detour')
    ? 'Detour'
    : summary.toLowerCase().contains('safest')
    ? 'Suggested route'
    : summary;
