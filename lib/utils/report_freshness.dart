import '../models/user_report.dart';

class ReportFreshness {
  static const maximumAge = Duration(hours: 24);

  static DateTime observedAt(UserReport report) =>
      report.observedAt ?? report.lastUpdatedByUser ?? report.createdAt;

  static bool isOutdated(UserReport report, DateTime now) =>
      report.status == 'expired' ||
      now.difference(observedAt(report)) >= maximumAge ||
      observedAt(report).isAfter(now.add(const Duration(minutes: 1)));

  static List<UserReport> awaitingReviewForRoad(
    Iterable<UserReport> reports,
    String roadId,
    DateTime now,
  ) =>
      reports
          .where(
            (report) =>
                report.roadId == roadId &&
                const [
                  'pending',
                  'under_review',
                  'waiting_resident',
                ].contains(report.status) &&
                !isOutdated(report, now),
          )
          .toList()
        ..sort((a, b) {
          final time = observedAt(b).compareTo(observedAt(a));
          return time != 0 ? time : b.id.compareTo(a.id);
        });

  static String age(DateTime time, DateTime now) {
    final elapsed = now.difference(time);
    if (elapsed.isNegative) return 'time unconfirmed';
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} ${elapsed.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours} ${elapsed.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    return '${elapsed.inDays} ${elapsed.inDays == 1 ? 'day' : 'days'} ago';
  }
}
