import '../utils/time_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_report.dart';

class ReportCursor {
  final Object createdAt;
  final String id;
  const ReportCursor(this.createdAt, this.id);
}

class ReportPage {
  final List<UserReport> reports;
  final ReportCursor? next;
  final bool fromCache;
  const ReportPage(this.reports, {this.next, this.fromCache = false});
}

typedef ReportPageLoader = Future<ReportPage> Function(ReportCursor? cursor);

/// Prefer the freshest mutation; a late cached feed must not undo a review.
/// Ties favor the live feed for legacy records without server revision fields.
UserReport fresherReport(UserReport stored, UserReport live) {
  DateTime revision(UserReport report) => [
    report.createdAt,
    if (report.recordUpdatedAt != null) report.recordUpdatedAt!,
    if (report.lastUpdatedByUser != null) report.lastUpdatedByUser!,
    if (report.reviewedAt != null) report.reviewedAt!,
  ].reduce((a, b) => a.isAfter(b) ? a : b);
  if (stored.id != live.id || stored.userId != live.userId) return stored;
  return revision(stored).isAfter(revision(live)) ? stored : live;
}

/// Retain displaced live-head records once an older page has been requested,
/// including while its first request is still in flight.
void retainDisplacedHead<T>({
  required Map<String, T> older,
  required List<T> previous,
  required List<T> latest,
  required bool loadingOlder,
  required String Function(T) id,
}) {
  if (older.isEmpty && !loadingOlder) return;
  final latestIds = latest.map(id).toSet();
  for (final item in previous) {
    if (!latestIds.contains(id(item))) older.putIfAbsent(id(item), () => item);
  }
}

List<UserReport> mergeReportFeeds(
  List<UserReport> active,
  List<UserReport> ownRecent,
) {
  final byId = {for (final report in ownRecent) report.id: report};
  for (final report in active) {
    final stored = byId[report.id];
    byId[report.id] = stored == null ? report : fresherReport(stored, report);
  }
  return byId.values.toList()..sort((a, b) {
    final time = b.createdAt.compareTo(a.createdAt);
    return time != 0 ? time : b.id.compareTo(a.id);
  });
}

/// Match the server's newest-first submission order with stable ID ties.
/// Legacy records without a usable timestamp stay after dated records.
int compareReportSubmissions(UserReport a, UserReport b) {
  final knownA = TimeUtils.hasRecordedTime(a.createdAt),
      knownB = TimeUtils.hasRecordedTime(b.createdAt);
  if (knownA != knownB) return knownA ? -1 : 1;
  final time = b.createdAt.compareTo(a.createdAt);
  return time == 0 ? b.id.compareTo(a.id) : time;
}

/// Holds one page of records. Back navigation retains only small cursor values.
class ReportHistory extends ChangeNotifier {
  static const pageSize = 30;
  final ReportPageLoader loader;
  ReportHistory(this.loader);
  final List<ReportCursor?> _previous = [];
  ReportCursor? _start;
  ReportPage page = const ReportPage([]);
  bool loading = false;
  bool loaded = false;
  String? error;
  bool _disposed = false;
  int _operation = 0;
  int get pageNumber => _previous.length + 1;
  bool get canGoOlder =>
      loaded && !loading && !page.fromCache && page.next != null;
  bool get canGoNewer => !loading && _previous.isNotEmpty;

  Future<void> refresh() => _load(_start);
  Future<void> older() async {
    if (!canGoOlder) return;
    final start = _start;
    if (await _load(page.next, keepOnEmpty: true)) {
      _previous.add(start);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> newer() async {
    if (!canGoNewer) return;
    if (await _load(_previous.last)) {
      _previous.removeLast();
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> _load(ReportCursor? cursor, {bool keepOnEmpty = false}) async {
    if (loading || _disposed) return false;
    final operation = ++_operation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await loader(cursor).timeout(const Duration(seconds: 12));
      if (_disposed || operation != _operation) return false;
      if (keepOnEmpty && result.reports.isEmpty && !result.fromCache) {
        page = ReportPage(page.reports, fromCache: page.fromCache);
        return false;
      }
      if (result.fromCache &&
          result.reports.isEmpty &&
          loaded &&
          page.reports.isNotEmpty) {
        error =
            'Older history is unavailable offline. Your current page is preserved.';
        return false;
      }
      page = result;
      _start = cursor;
      loaded = true;
      return true;
    } catch (_) {
      if (!_disposed && operation == _operation) {
        error = 'History could not be loaded. Check your connection and retry.';
      }
      return false;
    } finally {
      if (!_disposed && operation == _operation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    super.dispose();
  }
}

class ReportHistoryRepository {
  final FirebaseFirestore db;
  final String? userId;
  final DateTime? since;
  final List<String>? statuses;
  final String? dismissReason;
  ReportHistoryRepository({
    FirebaseFirestore? firestore,
    this.userId,
    this.since,
    this.statuses,
    this.dismissReason,
  }) : db = firestore ?? FirebaseFirestore.instance;

  Future<ReportPage> fetch(ReportCursor? cursor) async {
    Query<Map<String, dynamic>> query = db.collection('reports');
    if (dismissReason != null)
      query = query.where('dismissReason', isEqualTo: dismissReason);
    if (statuses != null) query = query.where('status', whereIn: statuses);
    if (userId != null) query = query.where('userId', isEqualTo: userId);
    if (since != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since!),
      );
    }
    query = query
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(ReportHistory.pageSize);
    if (cursor != null) query = query.startAfter([cursor.createdAt, cursor.id]);
    final snapshot = await query.get().timeout(const Duration(seconds: 10));
    final docs = snapshot.docs;
    return ReportPage(
      docs
          .map((doc) => UserReport.fromJson({...doc.data(), 'id': doc.id}))
          .toList(),
      next: docs.length == ReportHistory.pageSize
          ? ReportCursor(docs.last.data()['createdAt'] as Object, docs.last.id)
          : null,
      fromCache: snapshot.metadata.isFromCache,
    );
  }
}
