class TimeUtils {
  static bool hasRecordedTime(DateTime? time) =>
      time != null && time.millisecondsSinceEpoch > 0;

  static DateTime localDay(DateTime time) {
    final local = time.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Calendar dates, not elapsed 24-hour periods. Missing/future-day records
  /// must not silently become Today or a misleading January 1970 group.
  static String submissionDayKey(DateTime time, DateTime now) {
    if (!hasRecordedTime(time)) return 'unknown';
    final day = localDay(time);
    if (day.isAfter(localDay(now))) return 'future';
    return '${day.year}-${day.month}-${day.day}';
  }

  /// Converts a [DateTime] into a concise human-readable relative time string.
  /// Examples: "Just now", "5m ago", "2h ago", "3d ago".
  static String getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
