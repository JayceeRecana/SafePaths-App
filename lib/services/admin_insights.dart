import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_report.dart';

typedef AdminInsightsLoader = Future<AdminInsightsData> Function(int days);

class InsightBucket {
  final DateTime start, end;
  final int count;
  const InsightBucket(this.start, this.end, this.count);
}

/// A complete, server-checked submission cohort, not the live review queue.
class AdminInsightsData {
  final DateTime start, end, checkedAt;
  final List<UserReport> reports;
  AdminInsightsData({
    required this.start,
    required this.end,
    required this.checkedAt,
    required Iterable<UserReport> reports,
  }) : reports = List.unmodifiable(
         {
           for (final r in reports)
             if (!r.createdAt.isBefore(start) &&
                 r.createdAt.isBefore(end) &&
                 !r.createdAt.isAfter(checkedAt))
               r.id: r,
         }.values,
       );

  int get received => reports.length;
  int get originals => reports.where((r) => !r.isFollowup).length;
  int get followups => reports.where((r) => r.isFollowup).length;
  int get verified => reports
      .where((r) => const ['verified', 'resolved'].contains(r.status))
      .length;
  int get needsReview => reports.where((r) => r.needsAdminReview).length;
  int get waitingResident => reports.where((r) => r.awaitsResident).length;
  int get notVerified => reports.where((r) => r.status == 'dismissed').length;
  int get other =>
      received - verified - needsReview - waitingResident - notVerified;
  int? get verifiedPercent =>
      received == 0 ? null : (verified * 100 / received).round();
  int? get averageReviewMinutes {
    final durations = reports
        .where(
          (r) =>
              const ['verified', 'resolved', 'dismissed'].contains(r.status) &&
              r.reviewedAt != null &&
              !r.reviewedAt!.isBefore(r.createdAt) &&
              !r.reviewedAt!.isAfter(checkedAt),
        )
        .map((r) => r.reviewedAt!.difference(r.createdAt).inSeconds)
        .toList();
    if (durations.isEmpty) return null;
    return (durations.reduce((a, b) => a + b) / durations.length / 60).round();
  }

  Map<String, int> get roadCounts {
    final counts = <String, int>{};
    for (final r in reports) {
      if (r.roadId?.isNotEmpty == true)
        counts.update(r.roadId!, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<InsightBucket> get buckets {
    final days = DateTime(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime(start.year, start.month, start.day)).inDays;
    final step = days <= 7 ? 1 : 7;
    final result = <InsightBucket>[];
    for (var offset = 0; offset < days; offset += step) {
      final from = DateTime(start.year, start.month, start.day + offset);
      var to = DateTime(from.year, from.month, from.day + step);
      if (to.isAfter(end)) to = end;
      result.add(
        InsightBucket(
          from,
          to,
          reports
              .where(
                (r) => !r.createdAt.isBefore(from) && r.createdAt.isBefore(to),
              )
              .length,
        ),
      );
    }
    return result;
  }
}

class InsightsPage {
  final List<UserReport> reports;
  final bool fromCache;
  const InsightsPage(this.reports, {this.fromCache = false});
}

class AdminInsightsRepository {
  final String? Function() currentUid;
  final Future<InsightsPage> Function(DateTime start, DateTime end, int limit)
  fetch;
  final DateTime Function() now;
  AdminInsightsRepository({
    required this.currentUid,
    required this.fetch,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  Future<AdminInsightsData> load(int days) async {
    if (days != 7 && days != 30) throw ArgumentError('Unsupported range');
    final uid = currentUid();
    if (uid == null) throw StateError('Sign in to check insights.');
    final clock = now();
    final start = DateTime(clock.year, clock.month, clock.day - days + 1);
    final end = DateTime(clock.year, clock.month, clock.day + 1);
    final page = await fetch(
      start,
      end,
      AdminInsightsService.maximumReports + 1,
    ).timeout(const Duration(seconds: 15));
    if (currentUid() != uid || page.fromCache)
      throw StateError('Current account and server result not confirmed.');
    if (page.reports.length > AdminInsightsService.maximumReports)
      throw StateError(
        'Period exceeds the supported report limit. Totals unavailable.',
      );
    return AdminInsightsData(
      start: start,
      end: end,
      checkedAt: now(),
      reports: page.reports,
    );
  }
}

class AdminInsightsService {
  // Never silently display a partial period if the capstone outgrows this bound.
  static const maximumReports = 1000;
  static Future<AdminInsightsData> load(int days) => AdminInsightsRepository(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    fetch: (start, end, limit) async {
      final result = await FirebaseFirestore.instance
          .collection('reports')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .orderBy('createdAt')
          .limit(limit)
          .get(const GetOptions(source: Source.server));
      return InsightsPage(
        result.docs
            .map((d) => UserReport.fromJson({...d.data(), 'id': d.id}))
            .toList(),
        fromCache: result.metadata.isFromCache,
      );
    },
  ).load(days);
}
